#!/usr/bin/env python3
"""Collect exact Homebrew source archives and notices for bundled helpers."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request
import zipfile


def formula_keg(source):
    path = Path(source).resolve()
    parts = path.parts
    if 'Cellar' not in parts:
        raise RuntimeError(f'Cannot identify the Homebrew formula for {path.name}')
    index = parts.index('Cellar')
    return parts[index + 1], parts[index + 2], Path(*parts[:index + 3])


def download(url, checksum, destination):
    if not isinstance(url, str) or not url.startswith('https://') or not isinstance(checksum, str) or len(checksum) != 64:
        raise RuntimeError('Source archive requires an HTTPS URL and SHA-256 checksum')
    digest = hashlib.sha256()
    with urllib.request.urlopen(url, timeout=120) as response, destination.open('wb') as output:
        while block := response.read(1024 * 1024):
            output.write(block)
            digest.update(block)
    if digest.hexdigest() != checksum:
        destination.unlink()
        raise RuntimeError(f'Source checksum mismatch for {destination.name}')


def extract_notices(archive, output):
    """Read regular license files without extracting archive paths or links."""
    def wanted(name):
        name = Path(name).name.lower()
        return name.startswith(('copying', 'license', 'licence', 'notice', 'copyright', 'authors'))

    count = 0
    def write(name, data):
        nonlocal count
        if len(data) > 2 * 1024 * 1024:
            raise RuntimeError('Unexpectedly large notice file')
        target = output / (hashlib.sha256(name.encode()).hexdigest()[:12] + '-' + Path(name).name)
        target.write_bytes(data)
        count += 1

    output.mkdir(parents=True, exist_ok=True)
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as source:
            for member in source.infolist():
                if not member.is_dir() and wanted(member.filename):
                    if member.file_size > 2 * 1024 * 1024:
                        raise RuntimeError('Unexpectedly large notice file')
                    write(member.filename, source.read(member))
    else:
        with tarfile.open(archive, 'r:*') as source:
            for member in source:
                if member.isfile() and wanted(member.name):
                    if member.size > 2 * 1024 * 1024:
                        raise RuntimeError('Unexpectedly large notice file')
                    with source.extractfile(member) as stream:
                        write(member.name, stream.read())
    if count == 0:
        raise RuntimeError(f'No notices found in {archive.name}; review this formula before releasing')


def collect(app, destination):
    resources = app / 'Contents/Resources'
    manifest = json.loads((resources / 'engine-bundle-manifest.json').read_text())
    notices = resources / 'Licenses'
    notices.mkdir(parents=True, exist_ok=True)
    destination.mkdir(parents=True, exist_ok=True)
    packages = {}
    for item in manifest:
        name, version, keg = formula_keg(item['source'])
        key = (name, version)
        packages.setdefault(key, {'keg': keg, 'binaries': []})['binaries'].append(item['bundled'])
    provenance = []
    for (name, version), package in sorted(packages.items()):
        data = json.loads(subprocess.check_output(['brew', 'info', '--json=v2', '--formula', name], text=True))['formulae'][0]
        stable = data['versions']['stable']
        revision = data.get('revision', 0)
        expected = stable + (f'_{revision}' if revision else '')
        if version != expected:
            raise RuntimeError(f'{name} {version} is installed but source metadata describes {expected}. Run brew upgrade {name} and rebuild.')
        source = data['urls']['stable']
        directory = destination / f'{name}-{version}'
        directory.mkdir()
        archive = directory / 'source.archive'
        download(source['url'], source['checksum'], archive)
        extract_notices(archive, notices / f'{name}-{version}')
        recipe = package['keg'] / '.brew' / f'{name}.rb'
        if not recipe.is_file():
            raise RuntimeError(f'Installed Homebrew recipe missing for {name}')
        shutil.copy2(recipe, directory / f'{name}.rb')
        (directory / 'formula.json').write_text(json.dumps(data, indent=2) + '\n')
        provenance.append({'formula': name, 'version': version, 'license': data.get('license'),
                           'source_url': source['url'], 'source_sha256': source['checksum'],
                           'binaries': package['binaries']})
    text = json.dumps(provenance, indent=2) + '\n'
    (destination / 'PROVENANCE.json').write_text(text)
    (notices / 'PROVENANCE.json').write_text(text)
    project = Path(__file__).resolve().parents[1]
    shutil.copy2(project / 'COPYING', notices / 'Transmission-COPYING')
    shutil.copytree(project / 'licenses', notices / 'license-texts', dirs_exist_ok=True)
    shutil.copy2(project / 'THIRD-PARTY.md', notices / 'README.md')
    print(f'Collected checked source archives and notices for {len(packages)} Homebrew packages.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    collect(args.app, args.destination)
