"""Exercise the release packager with each installed PowerShell runtime."""
from pathlib import Path
import os
import shutil
import struct
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]


class PackageTests(unittest.TestCase):
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
                     "-OutputDirectory", output], capture_output=True, text=True, env=env,
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
