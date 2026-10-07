import copy
import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path

from wowenv import ROOT
import gen_catalog

TIERS = json.loads((ROOT / "tools/catalog_tiers.json").read_text(encoding="utf-8"))


class SourceTableTest(unittest.TestCase):
    """tools/catalog_tiers.json against the facts in docs/research/2026-10-08-campsite-client-data.md."""

    def objects(self):
        return [o for fam in TIERS["families"] for o in fam["objects"]]

    def test_counts(self):
        self.assertEqual(len(TIERS["families"]), 12)
        self.assertEqual(len(TIERS["professions"]), 12)
        # 11 professions with three tiers + cooking (feast T2, oven T3; its T1 role is the fire)
        self.assertEqual(len(self.objects()), 35)
        self.assertEqual([f["slots"] for f in TIERS["fires"]], [3, 5, 10])
        self.assertEqual([f["skill"] for f in TIERS["fires"]], [1, 140, 220])

    def test_keys_and_items_are_unique(self):
        keys = [o["key"] for o in self.objects()]
        self.assertEqual(len(keys), len(set(keys)))
        items = [i for o in self.objects() for i in o["items"]] + [f["item"] for f in TIERS["fires"]]
        self.assertEqual(len(items), len(set(items)))
        self.assertTrue(all(279938 <= i <= 279996 for i in items))

    def test_tiers_and_skills(self):
        skill_by_tier = {1: 20, 2: 140, 3: 300}
        for fam in TIERS["families"]:
            tiers = [o["tier"] for o in fam["objects"]]
            self.assertEqual(tiers, sorted(set(tiers)), fam["key"])
            for o in fam["objects"]:
                self.assertEqual(o["skill"], skill_by_tier[o["tier"]], o["key"])


def fake_scan():
    """A scan with one family (two tiers) and one fire, shaped like out/scan.json."""
    return {
        "items": {
            "1": {"name": "Wheel", "spellName": "Wheel", "tooltip": ["Requires: Smithing (20)"]},
            "2": {"name": "Anvil", "spellName": "Anvil", "tooltip": ["Requires: Smithing (140)"]},
            "9": {"name": "Fire Kit", "spellName": "Fire", "tooltip": ["Requires: Cooking (1)"]},
        },
        "spells": {
            "10": {"name": "Wheel", "description": "Create a wheel."},
            "11": {"name": "Wheel", "description": "Grants Strength."},
            "12": {"name": "Anvil", "description": "May be placed over a Wheel to replace it."},
            "19": {"name": "Fire", "description": "Create a fire."},
            "20": {"name": "Fire", "description": "Creates a fire with 3 slots."},
            "21": {"name": "Fire", "description": ""},
        },
    }


def fake_tiers():
    return {
        "auras": {"near": 1, "sitting": 2, "benefits": 3},
        "professions": {"smithing": 164, "cooking": 185},
        "classBuffs": {"might": {"spells": [19740], "classes": ["PALADIN"]}},
        "fires": [{"tier": 1, "item": 9, "skill": 1, "slots": 3, "burn": 600}],
        "families": [{
            "key": "smithing", "profession": "smithing", "exclusiveWith": ["might"],
            "weights": {"leveling": 1, "dungeon": 2, "craft": 3},
            "objects": [
                {"key": "wheel", "tier": 1, "skill": 20, "kind": "buff", "items": [1]},
                {"key": "anvil", "tier": 2, "skill": 140, "kind": "buff", "items": [2]},
            ],
        }],
    }


class GeneratorTest(unittest.TestCase):
    def test_resolves_spells_and_replacements(self):
        cat = gen_catalog.build(fake_tiers(), fake_scan())
        wheel, anvil = cat["objects"]["wheel"], cat["objects"]["anvil"]
        self.assertEqual((wheel["place"], wheel["craft"], wheel["replaces"]), ([11], 10, None))
        self.assertEqual((anvil["place"], anvil["craft"], anvil["replaces"]), ([12], None, "wheel"))
        self.assertEqual(anvil["exclusiveWith"], ["might"])
        self.assertEqual(cat["fires"][0]["place"], 20)
        self.assertEqual(cat["fires"][0]["craft"], 19)
        self.assertEqual(cat["order"], ["wheel", "anvil"])

    def test_missing_item_names_the_object(self):
        scan = fake_scan()
        del scan["items"]["2"]
        with self.assertRaises(gen_catalog.CatalogError) as ctx:
            gen_catalog.build(fake_tiers(), scan)
        self.assertIn("anvil: item 2 not found", str(ctx.exception))

    def test_skill_mismatch_is_reported(self):
        scan = fake_scan()
        scan["items"]["2"]["tooltip"] = ["Requires: Smithing (150)"]
        with self.assertRaises(gen_catalog.CatalogError) as ctx:
            gen_catalog.build(fake_tiers(), scan)
        self.assertIn("requires skill 150", str(ctx.exception))

    def test_previous_order_must_be_kept(self):
        tiers = fake_tiers()
        gen_catalog.build(tiers, fake_scan(), previous_order=["wheel"])  # appending is fine
        tiers["families"][0]["objects"].reverse()
        tiers["families"][0]["objects"][0]["tier"], tiers["families"][0]["objects"][1]["tier"] = 2, 1
        with self.assertRaises(gen_catalog.CatalogError) as ctx:
            gen_catalog.build(tiers, fake_scan(), previous_order=["wheel", "anvil"])
        self.assertIn("order changed", str(ctx.exception))

    def test_cli_exits_nonzero_with_object_name(self):
        scan = fake_scan()
        del scan["items"]["1"]
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "tiers.json").write_text(json.dumps(fake_tiers()), encoding="utf-8")
            (tmp / "scan.json").write_text(json.dumps(scan), encoding="utf-8")
            err = io.StringIO()
            with redirect_stderr(err):
                code = gen_catalog.main(["--tiers", str(tmp / "tiers.json"), "--scan", str(tmp / "scan.json"),
                                         "--out", str(tmp / "Catalog.lua")])
        self.assertEqual(code, 1)
        self.assertIn("wheel", err.getvalue())

    def test_committed_catalog_keeps_previous_order(self):
        order = gen_catalog.previous_order(ROOT / "Campkeeper/Data/Catalog.lua")
        expected = [o["key"] for fam in TIERS["families"] for o in fam["objects"]]
        self.assertEqual(order, expected[:len(order)])

    @unittest.skipUnless((ROOT / "out/scan.json").is_file(), "needs out/scan.json from /fad scan camp")
    def test_committed_catalog_is_up_to_date(self):
        self.assertEqual(gen_catalog.main(["--check"]), 0)


if __name__ == "__main__":
    unittest.main()
