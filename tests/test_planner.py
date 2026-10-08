import unittest

from wowenv import WowEnv

CORE = ["Core/Log.lua", "Core/Util.lua", "Data/Catalog.lua", "Core/Catalog.lua", "Core/Planner.lua"]


def planner_env():
    env = WowEnv(locale="ruRU")
    env.lua.execute("""
      Mock.items[279960] = { name = "Магнетит" }
      Mock.items[279948] = { name = "Сад камней" }
      Mock.items[279952] = { name = "Плавильня" }
      Mock.spells[1307252] = { name = "Костер подмастерья" }
    """)
    env.load_core(CORE)
    return env


def plan(env, members, **opts):
    lua = env.lua
    ms = [lua.table_from({"name": m[0], "class": m[1], "professions": lua.table_from(m[2])}) for m in members]
    inp = {"members": lua.table_from(ms), "role": opts.get("role", "dungeon")}
    for k in ("slots", "fireTier"):
        if k in opts:
            inp[k] = opts[k]
    p = env.ns.Planner
    return p.Plan(p, lua.table_from(inp))


def picks(result):
    return [(o.member, o.key) for o in result.objects.values()]


FISHER = ("Fin", "ROGUE", {"fishing": 300})
MINER = ("Max", "WARRIOR", {"mining": 300})
TAILOR = ("Tia", "MAGE", {"tailoring": 300})
SKINNER = ("Sam", "HUNTER", {"skinning": 300})
COOK = ("Cid", "WARLOCK", {"cooking": 225})


class PlannerTest(unittest.TestCase):
    def setUp(self):
        self.env = planner_env()

    def test_slots_limit_by_weight(self):
        members = [FISHER, MINER, TAILOR, SKINNER, ("Al", "ROGUE", {"alchemy": 300}), COOK]
        r = plan(self.env, members, slots=3)
        self.assertEqual(r.slots, 3)
        self.assertEqual(r.fire.member, "Cid")
        # dungeon weights: fishing 5, then 4s in key order: alchemy, mining, skinning
        self.assertEqual(picks(r), [("Fin", "fishing_hut"), ("Al", "alchemy_lab"), ("Max", "smelter")])

    def test_class_buff_in_group_skips_object(self):
        paladin = ("Pal", "PALADIN", {})
        r = plan(self.env, [FISHER, MINER, paladin], slots=5)
        keys = [k for _, k in picks(r)]
        self.assertNotIn("fishing_hut", keys)  # kings
        self.assertNotIn("smelter", keys)      # might

    def test_highest_tier_by_free_member(self):
        low = ("Low", "ROGUE", {"mining": 50})
        r = plan(self.env, [low, MINER], slots=3)
        self.assertEqual(picks(r), [("Max", "smelter")])

    def test_one_item_per_member_including_fire(self):
        allround = ("Ace", "ROGUE", {"cooking": 300, "mining": 300, "fishing": 300})
        r = plan(self.env, [allround], slots=5)
        self.assertEqual(r.fire.member, "Ace")
        self.assertEqual(picks(r), [])
        r = plan(self.env, [allround, ("Bo", "ROGUE", {"mining": 20})], slots=5)
        self.assertEqual(picks(r), [("Bo", "lodestone")])

    def test_fire_tier_needs_cooking_skill(self):
        r = plan(self.env, [("Cid", "WARLOCK", {"cooking": 150}), MINER], fireTier=3)
        self.assertIsNone(r.fire)
        self.assertEqual(r.slots, 10)

    def test_fire_to_member_least_needed(self):
        cook_miner = ("Ann", "ROGUE", {"cooking": 50, "mining": 300})
        cook_only = ("Zed", "ROGUE", {"cooking": 10})
        r = plan(self.env, [cook_miner, cook_only], slots=3)
        self.assertEqual(r.fire.member, "Zed")
        self.assertEqual(picks(r), [("Ann", "smelter")])

    def test_deterministic(self):
        members = [FISHER, MINER, TAILOR, SKINNER, COOK]
        a = picks(plan(self.env, members, slots=5, role="leveling"))
        b = picks(plan(self.env, list(reversed(members)), slots=5, role="leveling"))
        self.assertEqual(a, b)

    def test_chat_lines(self):
        r = plan(self.env, [MINER, ("Cid", "WARLOCK", {"cooking": 150})], fireTier=2)
        p = self.env.ns.Planner
        lines = list(p.ChatLines(p, r).values())
        self.assertEqual(lines, ["План лагеря: Костер подмастерья - Cid; Плавильня (T3) - Max;"])
        self.assertTrue(all(len(l.encode()) < 255 for l in lines))


if __name__ == "__main__":
    unittest.main()
