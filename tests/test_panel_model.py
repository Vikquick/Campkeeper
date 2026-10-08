import unittest

from wowenv import WowEnv

BENEFITS = 1229741
FIRE2_PLACE, LODESTONE_PLACE = 1307252, 1307254
HEADER = "Бонусы лагеря"
DESCRIPTION = "Получены следующие бонусы лагеря:\r\n\r\nМагнетит: сила атаки ближнего боя повышена на 20.\r\n\r\n"

SETUP = """
  Mock.items[279960] = { name = "Магнетит" }
  Mock.items[279948] = { name = "Сад камней" }
  Mock.items[279944] = { name = "Круг для заточки" }
  Mock.spells[19740] = { name = "Благословение могущества" }
  Mock.spells[25782] = { name = "Великое благословение могущества" }
  Mock.professions = { { skillLine = 186, rank = 150 }, { skillLine = 164, rank = 10 } }
"""


def started(prepare=""):
    env = WowEnv(locale="ruRU")
    env.lua.execute(SETUP)
    env.lua.execute(prepare)
    env.load_toc()
    env.login()
    env.assert_no_errors()
    return env


def build(env):
    m = env.ns.PanelModel
    return m.Build(m)


def rows(model):
    return [(r.key, r.status) for r in model.rows.values()]


class PanelModelTest(unittest.TestCase):
    def test_item_in_bags_is_placeable(self):
        env = started("Mock.bags[279960] = 1")
        self.assertEqual(rows(build(env)), [("lodestone", "placeable")])
        self.assertEqual(build(env).rows[1].item, 279960)

    def test_best_tier_with_enough_skill(self):
        env = started("Mock.bags[279960] = 1\nMock.bags[279948] = 1")  # T1 and T2 mining, skill 150
        self.assertEqual(rows(build(env)), [("rock_garden", "placeable")])

    def test_not_enough_skill(self):
        env = started("Mock.bags[279944] = 1")  # sharpening wheel needs blacksmithing 20, have 10
        self.assertEqual(rows(build(env)), [])

    def test_cooldown_not_ready_hides_placeable(self):
        env = started("Mock.bags[279960] = 1\nMock.itemCooldown = { start = Mock.time, duration = 3600 }")
        model = build(env)
        self.assertEqual(rows(model), [])
        self.assertEqual(model.header.cooldownRemaining, 3600)

    def test_class_buff_covers_object(self):
        env = started("Mock.bags[279960] = 1")
        env.mock.AddAura(25782, 3600, "Великое благословение могущества")
        self.assertEqual(rows(build(env)), [("lodestone", "covered")])

    def test_placed_object_from_benefits(self):
        env = started("Mock.bags[279960] = 1")
        b = env.mock.AddAura(BENEFITS, 3600)
        env.lua.eval("function(id, t) Mock.tooltips[id] = t end")(b, env.lua.table_from([HEADER, DESCRIPTION]))
        env.advance(1)
        model = build(env)
        self.assertEqual(rows(model), [("lodestone", "placed")])
        self.assertEqual(model.rows[1].effect, "сила атаки ближнего боя повышена на 20.")
        self.assertEqual(model.sitting.state, "BUFFED")

    def test_upgrade_offered_over_placed_lower_tier(self):
        env = started("Mock.bags[279948] = 1")
        env.mock.Cast(FIRE2_PLACE)
        env.mock.Cast(LODESTONE_PLACE)
        model = build(env)
        self.assertEqual(rows(model), [("lodestone", "placed"), ("rock_garden", "placeable")])
        self.assertEqual((model.header.fireTier, model.header.used, model.header.slots), (2, 1, 5))
        self.assertEqual(model.header.fireRemaining, 600)


if __name__ == "__main__":
    unittest.main()
