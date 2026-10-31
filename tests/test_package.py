"""Exercise the release packager with each installed PowerShell runtime."""
from pathlib import Path
from contextlib import contextmanager
import os
import shutil
import struct
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]


class PackageTests(unittest.TestCase):
    def shells(self):
        found=[path for name in ('powershell','pwsh') if (path:=shutil.which(name))]
        if not found:self.skipTest('PowerShell is not installed')
        return found

    @contextmanager
    def fixture(self):
        with tempfile.TemporaryDirectory() as directory:
            project=Path(directory)/'project';(project/'tools').mkdir(parents=True)
            shutil.copy2(ROOT/'tools/package.ps1',project/'tools/package.ps1')
            shutil.copytree(ROOT/'addon',project/'addon')
            for name in ('LICENSE','THIRD_PARTY_NOTICES.md'):shutil.copy2(ROOT/name,project/name)
            yield project,Path(directory)/'dist'

    def package(self,shell,project,output):
        env={key:value for key,value in os.environ.items() if key.upper()!='PSMODULEPATH'}
        return subprocess.run([shell,'-NoProfile','-File',str(project/'tools/package.ps1'),'-OutputDirectory',str(output)],capture_output=True,env=env)

    def test_unloaded_lua_and_xml_are_rejected_before_creating_an_archive(self):
        for shell in self.shells():
            for suffix in ('.lua','.xml'):
                with self.subTest(shell=shell,suffix=suffix),self.fixture() as (project,output):
                    (project/'addon/LycheeTalent'/('SavedVariables'+suffix)).write_text('PRIVATE_AUDIT_CANARY',encoding='utf-8')
                    result=self.package(shell,project,output)
                    self.assertNotEqual(result.returncode,0,'An unreferenced runtime file must not enter the release archive')
                    self.assertFalse(output.exists())

    def test_missing_and_escaping_toc_or_xml_references_are_rejected(self):
        for shell in self.shells():
            for xml in (False,True):
                for escaped in (False,True):
                    with self.subTest(shell=shell,xml=xml,escaped=escaped),self.fixture() as (project,output):
                        folder=project/'addon/LycheeTalent';reference='../LycheeTalent_Data_MAGE/Data.lua' if escaped else 'Missing.lua'
                        toc=folder/'LycheeTalent.toc'
                        if xml:
                            (folder/'Audit.xml').write_text('<Ui><Script file="'+reference+'"/></Ui>',encoding='utf-8');reference='Audit.xml'
                        with toc.open('a',encoding='utf-8') as stream:stream.write('\n'+reference+'\n')
                        self.assertNotEqual(self.package(shell,project,output).returncode,0)
                        self.assertFalse(output.exists())

    def test_source_directory_junction_is_rejected(self):
        if os.name!='nt':self.skipTest('Windows junction regression')
        for shell in self.shells():
            with self.subTest(shell=shell),self.fixture() as (project,output):
                external=project.parent/'external';external.mkdir();(external/'Private.lua').write_text('PRIVATE_AUDIT_CANARY',encoding='utf-8')
                link=project/'addon/LycheeTalent/AuditLink'
                made=subprocess.run(['cmd','/c','mklink','/J',str(link),str(external)],capture_output=True)
                self.assertEqual(made.returncode,0,made.stdout+made.stderr)
                try:
                    result=self.package(shell,project,output)
                    self.assertNotEqual(result.returncode,0)
                    self.assertFalse(output.exists())
                finally:os.rmdir(link)

    def test_loaded_xml_cannot_enable_dtd_or_external_entities(self):
        for shell in self.shells():
            with self.subTest(shell=shell),self.fixture() as (project,output):
                external=project.parent/'private.txt';external.write_text('PRIVATE_AUDIT_CANARY',encoding='utf-8')
                folder=project/'addon/LycheeTalent'
                (folder/'Audit.xml').write_text('<!DOCTYPE Ui [<!ENTITY audit SYSTEM "'+external.as_uri()+'">]><Ui>&audit;</Ui>',encoding='utf-8')
                with (folder/'LycheeTalent.toc').open('a',encoding='utf-8') as stream:stream.write('\nAudit.xml\n')
                result=self.package(shell,project,output)
                self.assertNotEqual(result.returncode,0)
                self.assertIn(b'DTD',result.stderr)
                self.assertFalse(output.exists())

    def test_sibling_output_with_a_shared_name_prefix_is_allowed(self):
        for shell in self.shells():
            with self.subTest(shell=shell),self.fixture() as (project,_):
                output=project/'addon-output'
                result=self.package(shell,project,output)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertEqual(len(list(output.glob('*.zip'))),1)

    def test_toc_cannot_load_a_resource_file_as_code(self):
        for shell in self.shells():
            with self.subTest(shell=shell),self.fixture() as (project,output):
                with (project/'addon/LycheeTalent/LycheeTalent.toc').open('a',encoding='utf-8') as stream:stream.write('\nMedia/logo.tga\n')
                self.assertNotEqual(self.package(shell,project,output).returncode,0)
                self.assertFalse(output.exists())

    def test_zip_uses_portable_paths_and_preserves_contents(self):
        shells = [path for name in ("powershell", "pwsh") if (path := shutil.which(name))]
        if not shells:
            self.skipTest("PowerShell is not installed")
        # Let each runtime resolve its own built-in modules when launched from pwsh.
        env = {key: value for key, value in os.environ.items() if key.upper() != "PSMODULEPATH"}
        for shell in shells:
            with self.subTest(shell=shell), tempfile.TemporaryDirectory() as output:
                result = subprocess.run(
                    [shell, "-NoProfile", "-File", str(ROOT / "tools/package.ps1"),
                     "-OutputDirectory", output], capture_output=True, env=env,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                archives = list(Path(output).glob("*.zip"))
                self.assertEqual(len(archives), 1)
                with zipfile.ZipFile(archives[0]) as archive, archives[0].open("rb") as raw:
                    names = [entry.orig_filename for entry in archive.infolist()]
                    self.assertIn("LycheeTalent/LycheeTalent.toc", names)
                    for entry in archive.infolist():
                        # ZipInfo.filename silently normalizes backslashes on Windows.
                        self.assertNotIn("\\", entry.orig_filename)
                        raw.seek(entry.header_offset)
                        header = struct.unpack("<4s5H3I2H", raw.read(30))
                        self.assertEqual(header[0], b"PK\x03\x04")
                        local_name = raw.read(header[-2]).decode("utf-8")
                        self.assertEqual(local_name, entry.orig_filename)
                        self.assertEqual(archive.read(entry), (ROOT / "addon" / local_name).read_bytes())


if __name__ == "__main__":
    unittest.main()
