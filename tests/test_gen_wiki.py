import json
import unittest

from wowenv import ROOT
import gen_wiki

TEXTS = json.loads((ROOT / "tools/wiki_objects.json").read_text(encoding="utf-8"))


class WikiPageTest(unittest.TestCase):
    def setUp(self):
        self.catalog = gen_wiki.load_catalog()

    def test_every_catalog_object_has_text(self):
        self.assertEqual(sorted(TEXTS["objects"]), sorted(self.catalog["order"]))
        self.assertEqual(sorted(TEXTS["classBuffs"]), sorted(self.catalog["classBuffs"]))
        self.assertEqual(sorted(TEXTS["professions"]), sorted(self.catalog["professions"]))

    def test_page_takes_numbers_from_the_catalog(self):
        page = gen_wiki.render(self.catalog, TEXTS)
        self.assertIn("| Expert Campfire | 220 | 10 |", page)
        self.assertIn("| 2 | Anvil | 140 | Also gives the Sharpening Wheel bonus", page)
        self.assertIn("| Mining | Lodestone | +20 melee Attack Power. | Blessing of Might |", page)
        self.assertIn("| 2 | Repair Bot | 140 | Everyone nearby can buy reagents and repair gear. "
                      "Place it over the Reagent Bot to upgrade. |", page)
        # no replacement, no exclusivity line
        self.assertIn("| 3 | Anarchist's Workbench | 300 | Required to craft certain items. No stat bonus. |", page)

    def test_missing_text_is_an_error(self):
        texts = json.loads(json.dumps(TEXTS))
        del texts["objects"]["loom"]
        with self.assertRaisesRegex(KeyError, "loom"):
            gen_wiki.render(self.catalog, texts)

    def test_committed_page_is_up_to_date(self):
        page = gen_wiki.render(self.catalog, TEXTS)
        self.assertEqual((ROOT / "docs/wiki/Camp-Objects.md").read_text(encoding="utf-8"), page,
                         "run python tools/gen_wiki.py")


if __name__ == "__main__":
    unittest.main()
