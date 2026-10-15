"""Langues : chaque texte affiché a sa traduction anglaise."""

import ast
import os
import unittest

from tests import support
from faxel.core import i18n, lang_en

SRC = os.path.join(os.path.dirname(support.HERE), "src")


def translatable_strings():
    found = {}
    for folder, _dirs, files in os.walk(SRC):
        for name in files:
            if not name.endswith(".py"):
                continue
            path = os.path.join(folder, name)
            with open(path, encoding="utf-8") as handle:
                tree = ast.parse(handle.read())
            for node in ast.walk(tree):
                if not isinstance(node, ast.Call) or not node.args:
                    continue
                func = getattr(node.func, "id", getattr(node.func, "attr", None))
                first = node.args[0]
                if func == "tr" and isinstance(first, ast.Constant) and isinstance(first.value, str):
                    found.setdefault(first.value, os.path.relpath(path, SRC))
    return found


class I18nTest(unittest.TestCase):
    def tearDown(self):
        i18n.init("fr")

    def test_every_string_has_an_english_translation(self):
        missing = {text: where for text, where in translatable_strings().items() if text not in lang_en.EN}
        self.assertEqual(missing, {}, "Textes sans traduction anglaise")

    def test_placeholders_match(self):
        import re
        for french, english in lang_en.EN.items():
            self.assertEqual(sorted(re.findall(r"{\w+}", french)), sorted(re.findall(r"{\w+}", english)), french)

    def test_language_choice(self):
        self.assertEqual(i18n.init("system", ["en-US", "fr-FR"]), "en")
        self.assertEqual(i18n.init("system", ["fr-CA"]), "fr")
        self.assertEqual(i18n.init("system", ["es-ES"]), "en")
        self.assertEqual(i18n.init("system", []), "fr")
        self.assertEqual(i18n.init("en", ["fr-FR"]), "en")
        self.assertEqual(i18n.tr("Bibliothèque"), "Library")
        self.assertEqual(i18n.tr("{count} photo(s)", count=3), "3 photo(s)")
        i18n.init("fr")
        self.assertEqual(i18n.tr("Reprendre"), "Reprendre")


if __name__ == "__main__":
    unittest.main()
