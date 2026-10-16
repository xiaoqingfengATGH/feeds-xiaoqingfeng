"""Packaging contract; does not execute target binaries locally."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class Packaging(unittest.TestCase):
    def test_private_component_ownership(self):
        recipe = ROOT / 'homepublish-engines/Makefile'
        self.assertTrue(recipe.exists(), 'private engines recipe missing')
        text = recipe.read_text()
        self.assertIn('/usr/libexec/homepublish', text)
        self.assertNotIn('/usr/sbin/nginx', text)
        self.assertIn('1.30.6', text)
        self.assertIn('d39388d1edcc9fe7a35449fc5c23d222d20d6f81', text)
    def test_runtime_dependency(self):
        text = (ROOT / 'homepublish/Makefile').read_text()
        self.assertIn('+libubus-lua', text)
        self.assertIn('+homepublish-engines', text)
        self.assertNotIn('+nginx-ssl', text)
if __name__ == '__main__': unittest.main()
