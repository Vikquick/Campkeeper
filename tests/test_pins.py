import unittest

from test_camp_store import Store, YARD, started


class PinsTest(unittest.TestCase):
    def setUp(self):
        self.env = started()
        self.s = Store(self.env)
        self.pins = self.env.ns.Pins

    def refresh(self):
        self.pins.Refresh(self.pins)
        return {p.id: p for p in self.pins.shown.values()}

    def test_pins_for_camps_with_alpha_and_edge(self):
        self.s.add("near", x=0.5 + 100 * YARD, reporters=["Ann"])  # unconfirmed, 100 yd away
        self.s.add("far", x=0.5 + 900 * YARD, source="guild")
        shown = self.refresh()
        self.assertEqual(sorted(shown), ["far", "near"])
        self.assertEqual(shown["near"].alpha, 0.5)
        self.assertEqual(shown["far"].alpha, 1)
        self.assertTrue(shown["near"].floatOnEdge)
        self.assertFalse(shown["far"].floatOnEdge)
        self.env.assert_no_errors()

    def test_pins_follow_store_updates(self):
        self.s.add("a", source="party")
        self.env.advance(0)  # refresh is deferred to the next frame
        self.assertEqual([p.id for p in self.pins.shown.values()], ["a"])
        self.s.cs.Remove(self.s.cs, "a")
        self.env.advance(0)
        self.assertEqual(list(self.pins.shown.values()), [])

    def test_tooltip_lines(self):
        now = self.env.mock.serverTime
        self.env.lua.execute('Mock.spells[1307252] = { name = "Костер подмастерья" }')
        r = self.s.add("a", objects=["lodestone"], reporters=["Ann"], tier=2,
                       placedAt=now - 125, expiresAt=now + 475)
        t = self.pins.TooltipLines(self.pins, r)
        self.assertEqual(t.title, "Костер подмастерья")
        self.assertEqual(list(t.lines.values()), [
            "Магнетит", "Возраст: 2:05", "Погаснет через: 7:55", "Источник: общий канал",
            "Не подтверждён: сообщил один игрок", "Клик: поставить путевую точку"])


class WaypointTest(unittest.TestCase):
    def test_builtin_waypoint_without_tomtom(self):
        env = started()
        r = Store(env).add("a", x=0.25, y=0.75, source="party")
        self.assertEqual(env.ns.Pins.Waypoint(env.ns.Pins, r), "builtin")
        self.assertEqual(env.mock.waypoint.uiMapID, 1429)
        self.assertEqual((env.mock.waypoint.position.x, env.mock.waypoint.position.y), (0.25, 0.75))
        self.assertTrue(env.mock.superTracked)

    def test_tomtom_when_loaded(self):
        env = started()
        env.lua.execute("TomTom = { AddWaypoint = function(self, m, x, y, opts) Mock.tomtom = { m, x, y, opts.title } end }")
        r = Store(env).add("a", x=0.25, y=0.75, source="party")
        self.assertEqual(env.ns.Pins.Waypoint(env.ns.Pins, r), "tomtom")
        self.assertEqual(list(env.mock.tomtom.values())[:3], [1429, 0.25, 0.75])
        self.assertIsNone(env.mock.waypoint)


if __name__ == "__main__":
    unittest.main()
