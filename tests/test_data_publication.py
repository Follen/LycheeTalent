import json
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class DataPublicationTests(unittest.TestCase):
    def test_every_published_build_matches_public_payload(self):
        db_path = ROOT / 'data/private/wcl.sqlite3'
        if not db_path.exists():
            self.skipTest('local public WCL payload database is absent')
        from sys import path
        path.insert(0, str(ROOT / 'tools/wcl'))
        from collect import lua,CLASSES,HERO_CHOICES

        publication = json.loads((ROOT / 'data/publication.json').read_text(encoding='utf-8'))
        db = sqlite3.connect(db_path)
        total = 0
        for (class_name,) in db.execute('SELECT DISTINCT class FROM builds ORDER BY class'):
            builds = [json.loads(row[0]) for row in db.execute(
                'SELECT payload FROM builds WHERE class=? ORDER BY id', (class_name,))]
            with self.subTest(class_name=class_name), tempfile.TemporaryDirectory() as directory:
                expected = Path(directory) / 'expected.lua'
                payload={
                    'version': publication.get('class_collected', {}).get(class_name, publication['collected']),
                    'patch': publication.get('patch','12.1'), 'builds': builds,
                }
                if publication.get('heroMapping'):
                    cls,specs=next((cls,specs) for cls,(token,specs) in CLASSES.items() if token==class_name)
                    payload['heroTrees']=[[{'id':hero['id'],'name':hero['name']} for hero in HERO_CHOICES[(cls,spec)]] for spec in specs]
                expected.write_text('return ' + lua(payload), encoding='utf-8',newline='\n')
                proc = subprocess.run(
                    ['lua', 'tests/data_equivalence.lua', class_name, str(expected)],
                    cwd=ROOT, capture_output=True, text=True, check=False,
                )
                self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
                self.assertIn(f'builds={len(builds)}', proc.stdout)
                total += len(builds)
        self.assertEqual(total, publication['builds'])


if __name__ == '__main__':
    unittest.main()
