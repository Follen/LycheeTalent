"""Offline repository contracts: load paths, release notices and maintained docs."""
import html
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class TextOnly(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)


def normalized(text):
    return ' '.join(html.unescape(text).split())


class RepositoryTests(unittest.TestCase):
    def test_toc_loads_existing_files_and_covers_lua_sources(self):
        for toc in (ROOT / 'addon').glob('*/*.toc'):
            with self.subTest(toc=toc.name):
                loaded = set()

                def visit(path):
                    path = path.resolve()
                    self.assertTrue(path.is_relative_to(toc.parent.resolve()), f'{toc.name}: escaped load path')
                    self.assertTrue(path.is_file(), f'{toc.name}: {path}')
                    relative = path.relative_to(toc.parent).as_posix()
                    if relative in loaded:
                        return
                    loaded.add(relative)
                    if path.suffix == '.xml':
                        for element in ET.parse(path).iter():
                            if element.tag.rsplit('}', 1)[-1] in ('Script', 'Include') and element.get('file'):
                                visit(path.parent / element.get('file').replace('\\', '/'))

                for line in toc.read_text(encoding='utf-8').splitlines():
                    if line.strip() and not line.lstrip().startswith('#'):
                        visit(toc.parent / line.strip().replace('\\', '/'))
                sources = {path.relative_to(toc.parent).as_posix()
                           for path in toc.parent.rglob('*.lua')}
                self.assertEqual(sources, {path for path in loaded if path.endswith('.lua')})

    def test_embedded_lycheeui_matches_its_frozen_manifest(self):
        library = ROOT / 'addon/LycheeTalent/Libs/LycheeUI'
        manifest = json.loads((library / '.lock').read_text(encoding='utf-8'))
        self.assertEqual('LycheeUI', manifest['library'])
        self.assertEqual('frozen', manifest['status'])
        expected = {entry['path']: entry['sha256'] for entry in manifest['runtimeFiles']}
        actual = {path.relative_to(library).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in library.rglob('*') if path.is_file() and path.name != '.lock'}
        self.assertEqual(expected, actual)

    def test_release_notices_match_root_documents(self):
        for name in ('LICENSE', 'THIRD_PARTY_NOTICES.md'):
            with self.subTest(name=name):
                self.assertEqual((ROOT / name).read_bytes(),
                                 (ROOT / 'addon/LycheeTalent' / name).read_bytes())

    def test_markdown_local_links_resolve(self):
        documents = list(ROOT.glob('*.md')) + list((ROOT / 'docs').rglob('*.md'))
        for document in documents:
            for target in re.findall(r'\]\(([^)]+)\)', document.read_text(encoding='utf-8')):
                target = target.split('#', 1)[0]
                if not target or '://' in target or target.startswith('mailto:'):
                    continue
                with self.subTest(document=str(document.relative_to(ROOT)), target=target):
                    self.assertTrue((document.parent / target).exists())

    def test_platform_markdown_and_html_have_the_same_text(self):
        for language in ('en', 'zh-CN'):
            stem = ROOT / 'docs/publishing' / ('description.' + language)
            markdown = stem.with_suffix(stem.suffix + '.md').read_text(encoding='utf-8')
            # These copy-ready descriptions contain headings and unordered lists;
            # compare their text, not HTML styling or Markdown delimiters.
            markdown = re.sub(r'^(?:#{1,6}|-)\s+', '', markdown, flags=re.MULTILINE)
            parser = TextOnly()
            parser.feed(stem.with_suffix(stem.suffix + '.html').read_text(encoding='utf-8'))
            with self.subTest(language=language):
                self.assertEqual(normalized(markdown), normalized(' '.join(parser.parts)))


if __name__ == '__main__':
    unittest.main()
