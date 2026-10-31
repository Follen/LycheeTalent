"""Exercise the installer only against isolated fake AddOns directories."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = shutil.which('pwsh') or shutil.which('powershell')


@unittest.skipUnless(os.name == 'nt' and POWERSHELL, 'Windows PowerShell is required for the installation contract')
class InstallTests(unittest.TestCase):
    def setUp(self):
        self.parent = (ROOT / 'analyze' / 'install-contract-tests').resolve()
        self.parent.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix='case-', dir=self.parent)
        self.root = Path(self.temp.name).resolve()
        self.assertTrue(self.root.is_relative_to(self.parent))
        self.addCleanup(self.cleanup)
        self.repo = self.root / 'repo'
        self.source = self.repo / 'addon' / 'LycheeTalent'
        self.source.mkdir(parents=True)
        (self.repo / 'tools').mkdir()
        shutil.copyfile(ROOT / 'tools/install.ps1', self.repo / 'tools/install.ps1')
        self.loaded = ['Core.lua']
        self.write_toc()
        (self.source / 'Core.lua').write_bytes(b'-- original source\n')
        self.target = self.root / 'game' / 'Interface' / 'AddOns'
        self.target.mkdir(parents=True)
        self.installed = self.target / 'LycheeTalent'

    def cleanup(self):
        # TemporaryDirectory recursively removes only the verified test root.
        resolved = Path(self.temp.name).resolve()
        if not resolved.is_relative_to(self.parent) or resolved == self.parent:
            raise RuntimeError('Temporary cleanup escaped its intended root')
        self.temp.cleanup()

    def run_install(self):
        return subprocess.run([POWERSHELL, '-NoProfile', '-File', str(self.repo / 'tools/install.ps1'),
                               '-AddOnsPath', str(self.target)], capture_output=True, text=True,
                              encoding='utf-8', errors='replace', timeout=30)

    def write_toc(self):
        (self.source / 'LycheeTalent.toc').write_text('## Version: 1.1.2\n' + '\n'.join(self.loaded) + '\n', encoding='utf-8')

    def add_source(self, name, content):
        path = self.source / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        self.loaded.append(name)
        self.write_toc()

    def install(self):
        result = self.run_install()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return result

    def receipt(self):
        return json.loads((self.installed / 'lychee-talent.install.json').read_text(encoding='utf-8-sig'))

    def junction(self, link, target):
        script = self.root / 'junction.ps1'
        script.write_text('param([string]$Link,[string]$Target)\n$ErrorActionPreference="Stop"\n'
                          'New-Item -ItemType Junction -Path $Link -Target $Target | Out-Null\n', encoding='utf-8')
        result = subprocess.run([POWERSHELL, '-NoProfile', '-File', str(script), '-Link', str(link),
                                 '-Target', str(target)], capture_output=True, text=True,
                                encoding='utf-8', errors='replace', timeout=30)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_updates_owned_files_and_removes_only_owned_obsolete_files(self):
        self.add_source('Obsolete.lua', b'-- owned obsolete\n')
        self.install()
        (self.installed / 'External.txt').write_bytes(b'keep external notes\n')
        (self.source / 'Obsolete.lua').unlink()
        self.loaded.remove('Obsolete.lua')
        self.write_toc()
        (self.source / 'Core.lua').write_bytes(b'-- next source\n')
        self.install()
        self.assertEqual(b'-- next source\n', (self.installed / 'Core.lua').read_bytes())
        self.assertFalse((self.installed / 'Obsolete.lua').exists())
        self.assertEqual(b'keep external notes\n', (self.installed / 'External.txt').read_bytes())
        self.assertEqual(2, len(self.receipt()['files']))

    def test_modified_owned_file_aborts_before_other_writes(self):
        self.install()
        (self.installed / 'Core.lua').write_bytes(b'-- external edit\n')
        self.add_source('New.lua', b'-- new source\n')
        result = self.run_install()
        self.assertNotEqual(0, result.returncode)
        self.assertEqual(b'-- external edit\n', (self.installed / 'Core.lua').read_bytes())
        self.assertFalse((self.installed / 'New.lua').exists())

    def test_new_source_cannot_overwrite_an_unmanaged_target(self):
        self.install()
        original_receipt = (self.installed / 'lychee-talent.install.json').read_bytes()
        (self.installed / 'New.lua').write_bytes(b'-- unmanaged private file\n')
        self.add_source('New.lua', b'-- new source\n')
        (self.source / 'Core.lua').write_bytes(b'-- changed source\n')
        result = self.run_install()
        self.assertNotEqual(0, result.returncode, 'Unmanaged target collision was silently overwritten')
        self.assertEqual(b'-- unmanaged private file\n', (self.installed / 'New.lua').read_bytes())
        self.assertEqual(b'-- original source\n', (self.installed / 'Core.lua').read_bytes())
        self.assertEqual(original_receipt, (self.installed / 'lychee-talent.install.json').read_bytes())

    def test_identical_new_target_is_verified_before_adoption(self):
        self.install()
        content = b'-- verified identical file\n'
        (self.installed / 'New.lua').write_bytes(content)
        self.add_source('New.lua', content)
        self.install()
        entries = {entry['path'].replace('\\', '/'): entry for entry in self.receipt()['files']}
        self.assertEqual(hashlib.sha256(content).hexdigest().upper(), entries['New.lua']['sha256'])

    def test_receipt_path_cannot_escape_package(self):
        self.install()
        outside = self.root / 'outside.txt'
        outside.write_bytes(b'private outside file\n')
        receipt = self.receipt()
        receipt['files'].append({'path': str(outside), 'sha256': hashlib.sha256(outside.read_bytes()).hexdigest().upper()})
        (self.installed / 'lychee-talent.install.json').write_text(json.dumps(receipt), encoding='utf-8')
        (self.source / 'Core.lua').write_bytes(b'-- changed source\n')
        result = self.run_install()
        self.assertNotEqual(0, result.returncode)
        self.assertEqual(b'private outside file\n', outside.read_bytes())
        self.assertEqual(b'-- original source\n', (self.installed / 'Core.lua').read_bytes())

    def test_source_junction_is_rejected(self):
        outside = self.root / 'outside-source'
        outside.mkdir()
        (outside / 'Private.lua').write_bytes(b'private data must not be copied\n')
        self.junction(self.source / 'Linked', outside)
        result = self.run_install()
        self.assertNotEqual(0, result.returncode)
        self.assertFalse((self.installed / 'Linked' / 'Private.lua').exists())
        self.assertEqual(b'private data must not be copied\n', (outside / 'Private.lua').read_bytes())

    def test_target_junction_is_rejected_before_overwriting_outside(self):
        self.install()
        outside = self.root / 'outside-target'
        outside.mkdir()
        (outside / 'New.lua').write_bytes(b'private outside file\n')
        self.add_source('Linked/New.lua', b'-- new source\n')
        self.junction(self.installed / 'Linked', outside)
        result = self.run_install()
        self.assertNotEqual(0, result.returncode)
        self.assertEqual(b'private outside file\n', (outside / 'New.lua').read_bytes())

    def test_private_file_and_unloaded_lua_are_rejected(self):
        for name in ('.env', 'raw.sqlite', 'SavedVariables.lua'):
            with self.subTest(name=name):
                path = self.source / name
                path.write_bytes(b'private canary data\n')
                result = self.run_install()
                self.assertNotEqual(0, result.returncode)
                self.assertFalse((self.installed / name).exists())
                path.unlink()

    def test_runtime_xml_cannot_read_external_entities(self):
        self.add_source('embed.xml', b'<!DOCTYPE Ui [<!ENTITY x SYSTEM "file:///C:/private.txt">]><Ui>&x;</Ui>')
        result = self.run_install()
        self.assertNotEqual(0, result.returncode)
        self.assertFalse(self.installed.exists())

    def test_later_package_failure_prevents_all_package_writes(self):
        self.install()
        (self.source / 'Core.lua').write_bytes(b'-- main update must wait\n')
        package = self.repo / 'addon' / 'LycheeTalent_Data_MAGE'
        package.mkdir()
        (package / 'LycheeTalent_Data_MAGE.toc').write_text('## Version: 1.1.1\nData.lua\n', encoding='utf-8')
        (package / 'Data.lua').write_bytes(b'-- mismatched class package\n')
        result = self.run_install()
        self.assertNotEqual(0, result.returncode)
        self.assertEqual(b'-- original source\n', (self.installed / 'Core.lua').read_bytes())
        self.assertFalse((self.target / package.name).exists())


if __name__ == '__main__':
    unittest.main()
