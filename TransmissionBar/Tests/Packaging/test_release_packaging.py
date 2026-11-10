import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[2] / 'scripts'


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


sources = module('sources', 'collect-release-sources.py')
metadata = module('metadata', 'release-metadata.py')


def archive_with_notice(path):
    with tarfile.open(path, 'w:gz') as archive:
        for name, content in [('example/COPYING', b'Example license'), ('../../LICENSE', b'Nested notice'), ('example/source.c', b'code')]:
            info = tarfile.TarInfo(name)
            info.size = len(content)
            archive.addfile(info, io.BytesIO(content))


class ReleasePackagingTests(unittest.TestCase):
    def test_notices_are_flattened_and_cannot_escape_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive_with_notice(root / 'source.tar.gz')
            sources.extract_notices(root / 'source.tar.gz', root / 'notices')
            self.assertEqual(len(list((root / 'notices').iterdir())), 2)
            self.assertFalse((root / 'LICENSE').exists())
            self.assertFalse((root / 'notices/source.c').exists())

    def test_download_requires_matching_checksum(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / 'source.archive'
            with patch.object(sources.urllib.request, 'urlopen', return_value=io.BytesIO(b'archive')):
                sources.download('https://example.com/source', hashlib.sha256(b'archive').hexdigest(), target)
            self.assertEqual(target.read_bytes(), b'archive')
            with patch.object(sources.urllib.request, 'urlopen', return_value=io.BytesIO(b'wrong')):
                with self.assertRaisesRegex(RuntimeError, 'checksum mismatch'):
                    sources.download('https://example.com/source', '0' * 64, target)
            self.assertFalse(target.exists())

    def test_formula_provenance_rejects_source_version_mismatch(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            resources = root / 'app/Contents/Resources'
            resources.mkdir(parents=True)
            (resources / 'engine-bundle-manifest.json').write_text(json.dumps([{'source': '/opt/homebrew/Cellar/transmission-cli/4.1.2/bin/transmission-daemon', 'bundled': 'Contents/Helpers/transmission-daemon'}]))
            data = {'formulae': [{'versions': {'stable': '4.1.3'}, 'revision': 0}]}
            with patch.object(sources.subprocess, 'check_output', return_value=json.dumps(data)):
                with self.assertRaisesRegex(RuntimeError, 'source metadata describes'):
                    sources.collect(root / 'app', root / 'sources')

    def test_exact_package_notices_and_recipe_are_collected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            keg = root / 'Cellar/transmission-cli/4.1.3'
            (keg / '.brew').mkdir(parents=True)
            (keg / '.brew/transmission-cli.rb').write_text('recipe')
            archive_with_notice(root / 'source.tar.gz')
            resources = root / 'app/Contents/Resources'
            resources.mkdir(parents=True)
            (resources / 'engine-bundle-manifest.json').write_text(json.dumps([{'source': str(keg / 'bin/transmission-daemon'), 'bundled': 'Contents/Helpers/transmission-daemon'}]))
            data = {'formulae': [{'versions': {'stable': '4.1.3'}, 'revision': 0, 'license': 'GPL-2.0-only OR GPL-3.0-only', 'urls': {'stable': {'url': 'https://example.com/source', 'checksum': 'a' * 64}}}]}
            def copy_archive(url, checksum, destination):
                destination.write_bytes((root / 'source.tar.gz').read_bytes())
            with patch.object(sources.subprocess, 'check_output', return_value=json.dumps(data)), patch.object(sources, 'download', side_effect=copy_archive):
                sources.collect(root / 'app', root / 'sources')
            provenance = json.loads((root / 'sources/PROVENANCE.json').read_text())
            self.assertEqual(provenance[0]['version'], '4.1.3')
            self.assertEqual((root / 'sources/transmission-cli-4.1.3/transmission-cli.rb').read_text(), 'recipe')
            self.assertTrue((resources / 'Licenses/Transmission-COPYING').is_file())

    def test_minimum_macos_covers_all_architecture_slices(self):
        text = 'cmd LC_BUILD_VERSION\ncmdsize 32\nplatform 1\nminos 13.0\nsdk 15.0\ncmd LC_VERSION_MIN_MACOSX\ncmdsize 16\nversion 15.1\nsdk 16.0\n'
        self.assertEqual(metadata.minimum_version(text), (15, 1, 0))
        with self.assertRaises(RuntimeError):
            metadata.minimum_version('cmd LC_BUILD_VERSION\nsdk 15.0\n')


if __name__ == '__main__':
    unittest.main()
