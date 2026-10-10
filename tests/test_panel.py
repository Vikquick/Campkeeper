import unittest

from wowenv import WowEnv

NEAR, SITTING, BENEFITS = 1283391, 1229739, 1229741
LODESTONE_PLACE = 1307254


def started(prepare=""):
    env = WowEnv(locale="ruRU")
    env.lua.execute('Mock.items[279960] = { name = "Магнетит" }\n'
                    'Mock.professions = { { skillLine = 186, rank = 150 } }')
    env.lua.execute(prepare)
    env.load_toc()
    env.login()
    env.assert_no_errors()
    return env


def panel(env):
    return env.ns.Panel


def shown(env):
    return panel(env).frame.shown


def row(env, i):
    return panel(env).rows[i]


class VisibilityTest(unittest.TestCase):
    def test_shown_near_camp_hidden_ten_seconds_after_leaving(self):
        env = started()
        self.assertFalse(shown(env))
        near = env.mock.AddAura(NEAR)
        self.assertTrue(shown(env))
        env.mock.RemoveAura(near)
        self.assertTrue(shown(env))
        env.advance(9)
        self.assertTrue(shown(env))
        env.advance(2)
        self.assertFalse(shown(env))
        env.assert_no_errors()

    def test_benefits_away_from_the_fire_do_not_keep_it(self):
        # author's choice 2026-10-10: the panel is for the camp; the buff itself shows the time left
        env = started()
        near = env.mock.AddAura(NEAR)
        env.mock.AddAura(BENEFITS, 3600)
        env.advance(1)
        self.assertTrue(shown(env))
        env.mock.RemoveAura(near)
        env.advance(9)
        self.assertTrue(shown(env))
        env.advance(2)
        self.assertFalse(shown(env))
        env.mock.AddAura(NEAR)  # back at a camp with the benefits still on
        self.assertTrue(shown(env))
        env.assert_no_errors()

    def test_hidden_in_combat_and_back_after(self):
        env = started()
        env.mock.AddAura(NEAR)
        env.fire("PLAYER_REGEN_DISABLED")
        env.mock.inCombat = True
        self.assertFalse(shown(env))
        env.advance(3)  # ticker must not show it again in combat
        self.assertFalse(shown(env))
        env.mock.inCombat = False
        env.fire("PLAYER_REGEN_ENABLED")
        self.assertTrue(shown(env))

    def test_disabled_in_settings(self):
        env = started()
        opts = env.lua.eval('LibStub("AceConfigRegistry-3.0"):GetOptionsTable("Campkeeper", "dialog", "x-1")')
        opts.args.general.args.panel.set(None, False)
        env.mock.AddAura(NEAR)
        self.assertFalse(shown(env))


class SecureRowTest(unittest.TestCase):
    def test_placeable_row_uses_item(self):
        env = started("Mock.bags[279960] = 1")
        env.mock.AddAura(NEAR)
        b = row(env, 1)
        self.assertTrue(b.protected)
        self.assertEqual(b.attributes["type"], "item")
        self.assertEqual(b.attributes["item"], "item:279960")
        self.assertEqual(b.name.text, "Магнетит")
        self.assertEqual(b.status.text, "нажмите, чтобы поставить")
        b.scripts.PreClick(b)  # click notes the attempt so a following error is attributed
        failed = env.fired("CAMP_PLACE_FAILED")
        env.fire("UI_ERROR_MESSAGE", 57, "...")
        self.assertEqual(failed, [("lodestone", "blocked")])
        self.assertEqual(panel(env).hint.text, "Слишком близко к другому объекту или существу.")

    def test_attributes_deferred_until_combat_ends(self):
        env = started()
        env.mock.AddAura(NEAR)
        env.fire("PLAYER_REGEN_DISABLED")
        env.mock.inCombat = True
        env.lua.execute("Mock.bags[279960] = 1")
        env.fire("BAG_UPDATE_DELAYED")  # would need a SetAttribute; the mock errors on that in combat
        env.assert_no_errors()
        self.assertIsNone(row(env, 1).attributes["item"])
        env.mock.inCombat = False
        env.fire("PLAYER_REGEN_ENABLED")
        self.assertEqual(row(env, 1).attributes["item"], "item:279960")
        env.assert_no_errors()


class SittingBarTest(unittest.TestCase):
    def test_bar_text_by_state(self):
        env = started()
        env.mock.AddAura(NEAR)
        self.assertEqual(panel(env).barText.text, "Сядьте у костра, чтобы получить бонусы")
        env.mock.AddAura(SITTING, 60)
        env.advance(18)
        self.assertEqual(panel(env).barText.text, "Сидите ещё 42 с")
        env.mock.AddAura(BENEFITS, 3600)
        self.assertTrue(panel(env).barText.text.startswith("Бонусы до "))

    def test_cooldown_hint(self):
        env = started("Mock.bags[279960] = 1\nMock.itemCooldown = { start = Mock.time, duration = 3600 }")
        env.mock.AddAura(NEAR)
        env.ns.OwnCamp.NoteAttempt(env.ns.OwnCamp, "lodestone")
        env.fire("UI_ERROR_MESSAGE", 58, "Предмет пока недоступен.")
        self.assertEqual(panel(env).hint.text, "Походные предметы на перезарядке: 1:00:00")
        self.assertEqual(panel(env).cooldownText.text, "Перезарядка походных предметов: 1:00:00")
        env.advance(7)
        self.assertIsNone(panel(env).hint.text)


class LongEffectTest(unittest.TestCase):
    def test_long_effect_is_cut_to_first_sentence_with_full_text_in_tooltip(self):
        env = started('Mock.items[279978] = { name = "Лагерная палатка" }')
        effect = ("объем опыта, который вы получаете после отдыха, немного увеличен. "
                  "Этот эффект можно получить не чаще чем раз в 1 ч.")
        b = env.mock.AddAura(BENEFITS, 3600)
        env.lua.eval("function(id, t) Mock.tooltips[id] = t end")(b, env.lua.table_from(
            ["Бонусы лагеря", "Получены следующие бонусы лагеря:\r\n\r\nПалатка: " + effect + "\r\n\r\n"]))
        env.advance(1)
        r = row(env, 1)
        self.assertEqual(r.name.text, "Лагерная палатка")
        self.assertEqual(r.status.text, "объем опыта, который вы получаете после отдыха, немного увеличен.")
        self.assertEqual(r.status.width, 150)  # fixed column: the rest is cut, never spills over the panel
        self.assertEqual(r.effect, effect)
        self.assertEqual(panel(env).frame.width, 300)
        env.assert_no_errors()


class HeaderTest(unittest.TestCase):
    def test_own_fire_header(self):
        env = started('Mock.spells[1307252] = { name = "Костер подмастерья" }')
        env.mock.AddAura(NEAR)
        env.mock.Cast(1307252)
        env.mock.Cast(LODESTONE_PLACE)
        self.assertEqual(panel(env).title.text, "Костер подмастерья  1/5")
        self.assertEqual(panel(env).fireText.text, "Костёр погаснет через 10:00")
        env.advance(60)
        self.assertEqual(panel(env).fireText.text, "Костёр погаснет через 9:00")
        self.assertTrue(panel(env).fireText.shown)


class LogNoiseTest(unittest.TestCase):
    def test_missing_class_buff_name_logged_once(self):
        env = started("Mock.spells[19740] = nil")
        env.mock.AddAura(NEAR)
        env.advance(5)  # panel refreshes every second
        msgs = [e.msg for e in env.ns.Log.Entries(env.ns.Log).values() if "19740" in e.msg]
        self.assertEqual(len(msgs), 1)


if __name__ == "__main__":
    unittest.main()
