#!/usr/bin/env python3
"""Set the app's minimum macOS to cover every bundled Mach-O binary."""
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def minimum_version(output):
    versions = []
    command = None
    for line in output.splitlines():
        words = line.split()
        if len(words) == 2 and words[0] == 'cmd':
            command = words[1]
        if len(words) == 2 and ((command == 'LC_BUILD_VERSION' and words[0] == 'minos')
                                or (command == 'LC_VERSION_MIN_MACOSX' and words[0] == 'version')):
            if re.fullmatch(r'\d+(\.\d+){0,2}', words[1]):
                parts = tuple(map(int, words[1].split('.')))
                versions.append(parts + (0,) * (3 - len(parts)))
    if not versions:
        raise RuntimeError('Mach-O minimum macOS version missing')
    return max(versions)


def write_metadata(app, output):
    plist = app / 'Contents/Info.plist'
    with plist.open('rb') as stream:
        info = plistlib.load(stream)
    binaries = [app / 'Contents/MacOS' / info['CFBundleExecutable']]
    for directory in ['Helpers', 'Frameworks']:
        binaries.extend(path for path in (app / 'Contents' / directory).iterdir() if path.is_file())
    minimum = max([ (13, 0, 0) ] + [minimum_version(subprocess.check_output(['otool', '-l', str(path)], text=True)) for path in binaries])
    minimum_text = '.'.join(map(str, minimum))
    info['LSMinimumSystemVersion'] = minimum_text
    with plist.open('wb') as stream:
        plistlib.dump(info, stream)
    metadata = {'app_version': info['CFBundleShortVersionString'], 'minimum_macos': minimum_text,
                'architecture': subprocess.check_output(['uname', '-m'], text=True).strip(),
                'engine': subprocess.check_output([str(app / 'Contents/Helpers/transmission-daemon'), '--version'], text=True, stderr=subprocess.STDOUT).strip()}
    output.write_text(json.dumps(metadata, indent=2) + '\n')
    print('Packaged minimum macOS:', minimum_text)


if __name__ == '__main__':
    write_metadata(Path(sys.argv[1]), Path(sys.argv[2]))
