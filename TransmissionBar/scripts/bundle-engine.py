#!/usr/bin/env python3
"""Copy a Mach-O engine and its non-system dependency closure into an app."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

def run(*args):
    return subprocess.check_output(args, text=True).strip()

source, app = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
helpers, frameworks = app/'Contents/Helpers', app/'Contents/Frameworks'
helpers.mkdir(parents=True, exist_ok=True)
frameworks.mkdir(parents=True, exist_ok=True)
copied = {}
manifest = []

def rpaths(path):
    lines = run('otool', '-l', str(path)).splitlines()
    result = []
    for i, line in enumerate(lines):
        if line.strip() == 'cmd LC_RPATH':
            result.append(lines[i+2].strip().split('path ', 1)[1].split(' (offset', 1)[0])
    return result

def expand(value, parent):
    return value.replace('@loader_path', str(parent)).replace('@executable_path', str(source.parent))

def resolve(name, owner, search):
    if name.startswith('@rpath/'):
        for base in search:
            candidate = Path(base)/name[len('@rpath/'):]
            if candidate.exists(): return candidate.resolve()
        raise RuntimeError(f'Unresolved dependency {name} in {owner}')
    path = Path(expand(name, owner.parent))
    if not path.exists(): raise RuntimeError(f'Missing dependency {path}')
    return path.resolve()

def copy_binary(original, destination, inherited=()):
    original = original.resolve()
    if original in copied: return copied[original]
    copied[original] = destination
    shutil.copy2(original, destination)
    destination.chmod(0o755)
    subprocess.run(['codesign', '--remove-signature', str(destination)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    search = [expand(p, original.parent) for p in rpaths(original)] + list(inherited)
    deps = [line.strip().split(' (compatibility', 1)[0] for line in run('otool', '-L', str(original)).splitlines()[1:]]
    # A dylib's first entry may be its own install ID.
    id_output = run('otool', '-D', str(original)).splitlines()
    own_id = id_output[1].strip() if len(id_output)>1 else None
    if own_id:
        subprocess.check_call(['install_name_tool', '-id', '@rpath/'+destination.name, str(destination)])
    for name in deps:
        if name == own_id or name.startswith(('/usr/lib/', '/System/Library/')): continue
        dependency = resolve(name, original, search)
        digest = hashlib.sha256(str(dependency).encode()).hexdigest()[:10]
        target = frameworks/(digest+'-'+dependency.name)
        target = copy_binary(dependency, target, search)
        prefix = '@loader_path/' if destination.parent == frameworks else '@executable_path/../Frameworks/'
        subprocess.check_call(['install_name_tool', '-change', name, prefix+target.name, str(destination)])
    # Remove build-machine search paths after all edges have explicit relative paths.
    for value in rpaths(original):
        subprocess.check_call(['install_name_tool', '-delete_rpath', value, str(destination)])
    subprocess.check_call(['codesign', '--force', '--sign', '-', str(destination)])
    manifest.append({'source': str(original), 'bundled': str(destination.relative_to(app))})
    return destination

copy_binary(source, helpers/source.name)
for destination in copied.values():
    dependencies = run('otool', '-L', str(destination))
    for line in dependencies.splitlines()[1:]:
        name=line.strip().split(' (compatibility',1)[0]
        if not name.startswith(('/usr/lib/', '/System/Library/', '@loader_path/', '@executable_path/', '@rpath/')):
            raise RuntimeError(f'Nonportable reference remains: {name}')
resources = app/'Contents/Resources'
resources.mkdir(parents=True, exist_ok=True)
manifest_path = resources/'engine-bundle-manifest.json'
previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else []
merged = {item['bundled']: item for item in previous + manifest}
manifest_path.write_text(json.dumps(list(merged.values()), indent=2))
print(f'Bundled engine and {len(copied)-1} dependency libraries.')
