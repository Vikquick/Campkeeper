import unittest

from wowenv import WowEnv

NEAR, SITTING, BENEFITS = 1283391, 1229739, 1229741
# Real tooltip of "Camp Benefits" with one Lodestone (camp probe log, ruRU).
HEADER = "Бонусы лагеря"
DESCRIPTION = "Получены следующие бонусы лагеря:\r\n\r\nМагнетит: сила атаки ближнего боя повышена на 20.\r\n\r\n"
REMAINING = "Осталось 60 |4минута:минуты:минут;"


def set_tooltip(env, instance, *lines):
    env.lua.eval("function(id, t) Mock.tooltips[id] = t end")(instance, env.lua.table_from(list(lines)))


def started(prepare="", tooltips=None):
    env = WowEnv(locale="ruRU")
    for instance, lines in (tooltips or {}).items():
        set_tooltip(env, instance, *lines)
    env.lua.execute('Mock.items[279960] = { name = "Магнетит" }\nMock.items[279988] = { name = "Наковальня" }\n'
                    'Mock.items[279944] = { name = "Круг для заточки" }')
    env.lua.execute(prepare)
    env.load_toc()
    env.login()
    env.assert_no_errors()
    return env


class CampStateTest(unittest.TestCase):
    def setUp(self):
        self.env = started()
        self.cs = self.env.ns.CampState
        self.changes = self.env.fired("CAMP_STATE_CHANGED")

    def state(self):
        return self.cs.Get(self.cs)

    def add(self, spell, duration=0):
        return self.env.mock.AddAura(spell, duration)

    def test_approach_sit_and_get_benefits(self):
        self.assertEqual(self.state(), "AWAY")
        near = self.add(NEAR)
        self.assertEqual(self.state(), "NEAR")
        self.assertEqual([c[:2] for c in self.changes], [("AWAY", "NEAR")])

        self.add(SITTING, 60)
        self.assertEqual(self.state(), "SITTING")
        self.assertEqual(self.cs.SittingRemaining(self.cs), 60)
        self.env.advance(18)
        self.assertEqual(self.cs.SittingRemaining(self.cs), 42)

        self.add(BENEFITS, 3600)
        self.assertEqual(self.state(), "BUFFED")
        self.assertEqual(self.cs.Info(self.cs).benefitsExpires, self.env.mock.time + 3600)
        self.assertEqual([c[1] for c in self.changes], ["NEAR", "SITTING", "BUFFED"])

        # walking away keeps the benefits
        self.env.mock.RemoveAura(self.env.mock.AuraID(SITTING))
        self.env.mock.RemoveAura(near)
        self.assertEqual(self.state(), "BUFFED")
        self.env.assert_no_errors()

    def test_highest_aura_wins_and_expiry_returns_to_away(self):
        self.add(NEAR)
        b = self.add(BENEFITS, 3600)
        self.assertEqual(self.state(), "BUFFED")
        self.env.mock.RemoveAura(b)
        self.assertEqual(self.state(), "NEAR")
        self.env.mock.RemoveAura(self.env.mock.AuraID(NEAR))
        self.assertEqual(self.state(), "AWAY")

    def test_refresh_updates_expiry(self):
        b = self.add(BENEFITS, 3600)
        self.env.advance(100)
        self.env.mock.RefreshAura(b, 3600)
        self.assertEqual(self.cs.Info(self.cs).benefitsExpires, self.env.mock.time + 3600)

    def test_full_update_rebuilds(self):
        self.env.lua.execute(f"Mock.auras[1] = {{ auraInstanceID = 1, spellId = {NEAR}, duration = 0, expirationTime = 0 }}")
        self.assertEqual(self.state(), "AWAY")  # nothing fired yet
        self.env.fire("UNIT_AURA", "player", self.env.lua.table_from({"isFullUpdate": True}))
        self.assertEqual(self.state(), "NEAR")

    def test_unrelated_aura_does_not_rebuild(self):
        calls = []
        api = self.env.ns.api
        original = api.playerAura
        api.playerAura = lambda spell: calls.append(spell) or original(spell)
        camp = lambda: [s for s in calls if s in (NEAR, SITTING, BENEFITS)]
        self.add(12345, 30)
        self.assertEqual(camp(), [])
        self.add(NEAR)
        self.assertEqual(len(camp()), 3)

    def test_frozen_in_combat_then_rebuilt(self):
        self.add(NEAR)
        self.env.mock.inCombat = True
        self.add(SITTING, 60)
        self.add(BENEFITS, 3600)
        self.assertEqual(self.state(), "NEAR")
        self.env.mock.inCombat = False
        self.env.fire("PLAYER_REGEN_ENABLED")
        self.assertEqual(self.state(), "BUFFED")
        self.env.assert_no_errors()

    def test_secret_values_freeze_state(self):
        self.add(NEAR)
        self.env.mock.secretAuras = True
        self.add(SITTING, 60)
        self.assertEqual(self.state(), "NEAR")
        self.assertTrue(self.cs.IsDirty(self.cs))
        self.env.mock.secretAuras = False
        self.env.fire("PLAYER_REGEN_ENABLED")
        self.assertEqual(self.state(), "SITTING")


class ReloadTest(unittest.TestCase):
    def test_state_and_composition_restored_after_reload(self):
        env = started(f"Mock.auras[7] = {{ auraInstanceID = 7, spellId = {BENEFITS}, duration = 3600, "
                      f"expirationTime = Mock.time + 1800 }}", tooltips={7: (HEADER, DESCRIPTION, REMAINING)})
        cs = env.ns.CampState
        self.assertEqual(cs.Get(cs), "BUFFED")
        info = cs.Info(cs)
        self.assertEqual(info.benefitsExpires, env.mock.time + 1800)
        objects = list(info.benefits.objects.values())
        self.assertEqual([o.key for o in objects], ["lodestone"])


class BenefitsIntegrationTest(unittest.TestCase):
    def test_composition_parsed_when_tooltip_fills_in_late(self):
        env = started()
        cs = env.ns.CampState
        parsed = env.fired("CAMP_BENEFITS_PARSED")
        b = env.mock.AddAura(BENEFITS, 3600)
        set_tooltip(env, b, HEADER, REMAINING)  # description not there yet
        self.assertEqual(parsed, [])
        set_tooltip(env, b, HEADER, DESCRIPTION, REMAINING)
        env.advance(1)
        self.assertEqual(len(parsed), 1)
        lodestone = cs.Info(cs).benefits.objects[1]
        self.assertEqual((lodestone.key, lodestone.effect), ("lodestone", "сила атаки ближнего боя повышена на 20."))
        env.assert_no_errors()


if __name__ == "__main__":
    unittest.main()
