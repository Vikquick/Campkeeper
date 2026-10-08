import unittest

from wowenv import WowEnv

BENEFITS = 1229741
FIRE1_PLACE, LODESTONE_PLACE, ROCK_GARDEN_PLACE = 1307227, 1307254, 1307386
HEADER = "Бонусы лагеря"
DESCRIPTION = "Получены следующие бонусы лагеря:\r\n\r\nМагнетит: сила атаки ближнего боя повышена на 20.\r\n\r\n"
YARD = 1 / 3000  # Elwynn Forest in the mock world: 3000 yd per map unit along x


def started():
    env = WowEnv(locale="ruRU")
    env.lua.execute('Mock.items[279960] = { name = "Магнетит" }')
    env.load_toc()
    env.login()
    env.assert_no_errors()
    return env


class Store:
    def __init__(self, env):
        self.env, self.cs = env, env.ns.CampStore

    def add(self, id, x=0.5, y=0.5, mapID=1429, source="channel", objects=(), reporters=(), **extra):
        lua = self.env.lua
        rec = {"id": id, "mapID": mapID, "x": x, "y": y, "source": source,
               "objects": lua.table_from({k: True for k in objects}),
               "reporters": lua.table_from({r: True for r in reporters})}
        rec.update(extra)
        return self.cs.Add(self.cs, lua.table_from(rec))

    def all(self):
        return list(self.cs.All(self.cs).values())

    def objects(self, r):
        return sorted(r.objects.keys())


class MergeTest(unittest.TestCase):
    def setUp(self):
        self.env = started()
        self.s = Store(self.env)

    def test_two_reports_of_one_camp_merge(self):
        self.s.add("a", objects=["lodestone"], reporters=["Ann"])
        self.s.add("b", x=0.5 + 12 * YARD, objects=["mana_well"], reporters=["Bob"])
        camps = self.s.all()
        self.assertEqual(len(camps), 1)
        self.assertEqual(self.s.objects(camps[0]), ["lodestone", "mana_well"])
        self.assertEqual(sorted(camps[0].reporters.keys()), ["Ann", "Bob"])

    def test_far_apart_other_map_or_other_time_do_not_merge(self):
        now = self.env.mock.serverTime
        self.s.add("a")
        self.s.add("far", x=0.5 + 40 * YARD)
        self.s.add("other-map", mapID=1453)
        self.s.add("old", expiresAt=now - 1, placedAt=now - 700, lastSeen=now - 700)
        self.assertEqual(len(self.s.all()), 3)  # "old" is already expired

    def test_own_coordinates_win(self):
        self.s.add("rumour", x=0.5 + 10 * YARD, source="channel")
        self.s.add("mine", x=0.5, source="self", tier=2)
        camps = self.s.all()
        self.assertEqual(len(camps), 1)
        self.assertEqual((camps[0].x, camps[0].source, camps[0].tier), (0.5, "self", 2))


class ExpiryTest(unittest.TestCase):
    def test_expired_and_untimed_records_are_pruned(self):
        env = started()
        s = Store(env)
        now = env.mock.serverTime
        s.add("timed", placedAt=now, expiresAt=now + 600, source="party")
        s.add("untimed", mapID=1453, source="party")
        env.advance(599)
        self.assertEqual(len(s.all()), 2)
        env.advance(31)  # prune ticker every 30 s
        self.assertEqual(len(list(env.g.CampkeeperDB["global"]["camps"].keys())), 0)

    def test_limit_drops_oldest_channel_report(self):
        env = started()
        s = Store(env)
        s.cs.LIMIT = 3
        s.add("g1", x=0.1, source="guild", lastSeen=env.mock.serverTime - 50)
        s.add("c-old", x=0.2, lastSeen=env.mock.serverTime - 40)
        s.add("c-new", x=0.3, lastSeen=env.mock.serverTime - 10)
        s.add("c-newest", x=0.4)
        ids = sorted(r.id for r in s.all())
        self.assertEqual(ids, ["c-new", "c-newest", "g1"])


class ConfirmationTest(unittest.TestCase):
    def test_channel_needs_two_reporters(self):
        env = started()
        s = Store(env)
        r = s.add("a", reporters=["Ann"])
        self.assertFalse(r.confirmed)
        r = s.add("b", x=0.5 + 3 * YARD, reporters=["Bob"])
        self.assertTrue(r.confirmed)
        self.assertTrue(s.add("p", mapID=1453, source="party").confirmed)


class OwnAndSeenTest(unittest.TestCase):
    def test_own_camp_record_follows_replacements(self):
        env = started()
        env.mock.Cast(FIRE1_PLACE)
        env.mock.Cast(LODESTONE_PLACE)
        s = Store(env)
        camps = s.all()
        self.assertEqual(len(camps), 1)
        self.assertEqual((camps[0].source, camps[0].tier), ("self", 1))
        self.assertEqual(s.objects(camps[0]), ["lodestone"])
        self.assertTrue(camps[0].id.startswith("0ABCDEF1-"))
        env.mock.Cast(ROCK_GARDEN_PLACE)
        self.assertEqual(s.objects(s.all()[0]), ["rock_garden"])

    def test_benefits_at_foreign_camp_create_seen_record(self):
        env = started()
        b = env.mock.AddAura(BENEFITS, 3600)
        env.lua.eval("function(id, t) Mock.tooltips[id] = t end")(b, env.lua.table_from([HEADER, DESCRIPTION]))
        env.advance(1)
        camps = Store(env).all()
        self.assertEqual(len(camps), 1)
        r = camps[0]
        self.assertEqual((r.source, r.mapID, r.x, r.y), ("seen", 1429, 0.5, 0.5))
        self.assertEqual(sorted(r.objects.keys()), ["lodestone"])
        self.assertTrue(r.confirmed)

    def test_benefits_at_own_camp_do_not_duplicate_it(self):
        env = started()
        env.mock.Cast(FIRE1_PLACE)
        b = env.mock.AddAura(BENEFITS, 3600)
        env.lua.eval("function(id, t) Mock.tooltips[id] = t end")(b, env.lua.table_from([HEADER, DESCRIPTION]))
        env.advance(1)
        self.assertEqual([r.source for r in Store(env).all()], ["self"])


if __name__ == "__main__":
    unittest.main()
