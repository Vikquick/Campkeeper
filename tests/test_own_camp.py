import unittest

from wowenv import WowEnv

BENEFITS = 1229741
FIRE1_PLACE, LODESTONE_PLACE, ROCK_GARDEN_PLACE = 1307227, 1307254, 1307386
HEADER = "Бонусы лагеря"
DESCRIPTION = "Получены следующие бонусы лагеря:\r\n\r\nМагнетит: сила атаки ближнего боя повышена на 20.\r\n\r\n"
ELWYNN_WIDTH = 3000  # yards per map unit along x in the mock world


def started(prepare=""):
    env = WowEnv(locale="ruRU")
    env.lua.execute('Mock.items[279960] = { name = "Магнетит" }')
    env.lua.execute(prepare)
    env.load_toc()
    env.login()
    env.assert_no_errors()
    return env


def char(env):
    p = env.ns.Professions
    return p.Char(p)


def move(env, yards_east):
    env.mock.player.x = env.mock.player.x + yards_east / ELWYNN_WIDTH


class ProfessionsTest(unittest.TestCase):
    def test_professions_and_skills_scanned_at_login(self):
        env = started("""
          Mock.professions = { { skillLine = 186, rank = 75 }, { skillLine = 185, rank = 150 }, { skillLine = 999, rank = 1 } }
        """)
        c = char(env)
        self.assertEqual(c.professions.mining.skill, 75)
        self.assertEqual(c.professions.cooking.skill, 150)
        self.assertEqual(env.ns.Professions.Skill(env.ns.Professions, "alchemy"), 0)
        self.assertTrue(any("999" in e.msg for e in env.ns.Log.Entries(env.ns.Log).values()))
        self.assertEqual(c["class"], "WARRIOR")

    def test_bags_update(self):
        env = started()
        updates = env.fired("PROFESSIONS_UPDATED")
        env.lua.execute("Mock.bags[279960] = 2")
        env.fire("BAG_UPDATE_DELAYED")
        self.assertEqual(char(env)["items"][279960], 2)
        self.assertEqual(env.ns.Professions.ItemInBags(env.ns.Professions, "lodestone"), 279960)
        self.assertIn(("items",), updates)
        env.lua.execute("Mock.bags[279960] = nil")
        env.fire("BAG_UPDATE_DELAYED")
        self.assertIsNone(char(env)["items"][279960])

    def test_recipes_from_spellbook_and_profession_window(self):
        env = started("Mock.knownSpells[1230161] = true")  # Изготовить магнетит
        self.assertTrue(env.ns.Professions.KnowsRecipe(env.ns.Professions, "lodestone"))
        self.assertFalse(env.ns.Professions.KnowsRecipe(env.ns.Professions, "mana_well"))
        env.lua.execute("Mock.recipes[1230564] = true")  # Изготовить колодец маны
        env.fire("TRADE_SKILL_SHOW")
        self.assertTrue(env.ns.Professions.KnowsRecipe(env.ns.Professions, "mana_well"))


class OwnCampTest(unittest.TestCase):
    def setUp(self):
        self.env = started()
        self.oc = self.env.ns.OwnCamp

    def camp(self):
        return self.oc.Get(self.oc)

    def test_fire_creates_own_camp(self):
        placed = self.env.fired("OWN_CAMP_PLACED")
        self.env.mock.Cast(FIRE1_PLACE)
        camp = self.camp()
        self.assertEqual(camp.tier, 1)
        self.assertEqual(camp.expiresAt - camp.placedAt, 600)
        self.assertEqual(camp.mapID, 1429)
        self.assertEqual(len(placed), 1)
        self.assertEqual(self.oc.FireRemaining(self.oc), 600)
        self.env.advance(601)
        self.assertIsNone(self.camp())

    def test_object_nearby_joins_camp_far_one_does_not(self):
        self.env.mock.Cast(FIRE1_PLACE)
        move(self.env, 5)
        self.env.mock.Cast(LODESTONE_PLACE)
        self.assertIsNotNone(self.camp().objects.lodestone)
        self.env.mock.Cast(ROCK_GARDEN_PLACE)  # replaces the lodestone
        self.assertIsNone(self.camp().objects.lodestone)
        self.assertIsNotNone(self.camp().objects.rock_garden)

        other = started()
        other.mock.Cast(FIRE1_PLACE)
        move(other, 40)
        other.mock.Cast(LODESTONE_PLACE)
        camp = other.ns.OwnCamp.Get(other.ns.OwnCamp)
        self.assertIsNone(camp.objects.lodestone)

    def test_placement_error_after_attempt(self):
        failed = self.env.fired("CAMP_PLACE_FAILED")
        self.env.fire("UI_ERROR_MESSAGE", 58, "Предмет пока недоступен.")
        self.assertEqual(failed, [])  # no attempt, unrelated error
        self.env.fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-2", LODESTONE_PLACE)
        self.env.fire("UI_ERROR_MESSAGE", 58, "Предмет пока недоступен.")
        self.assertEqual(failed, [("lodestone", "cooldown")])
        self.oc.NoteAttempt(self.oc, "lodestone")
        self.env.fire("UI_ERROR_MESSAGE", 57, "Нельзя расположить объект так близко к существу или предмету.")
        self.assertEqual(failed[-1], ("lodestone", "blocked"))


class CooldownTest(unittest.TestCase):
    def test_cooldown_read_from_any_camp_item(self):
        env = started("Mock.bags[279960] = 1")
        updates = env.fired("CAMP_COOLDOWN_UPDATED")
        env.lua.execute("Mock.itemCooldown = { start = Mock.time, duration = 3600 }")
        env.fire("BAG_UPDATE_COOLDOWN")
        ready_at = env.mock.serverTime + 3600
        self.assertEqual(char(env).cooldownReadyAt, ready_at)
        self.assertEqual(updates, [(ready_at,)])
        self.assertEqual(env.ns.OwnCamp.CooldownRemaining(env.ns.OwnCamp), 3600)

    def test_last_known_value_without_items(self):
        env = started("Mock.bags[279960] = 1\nMock.itemCooldown = { start = Mock.time, duration = 3600 }")
        ready_at = char(env).cooldownReadyAt
        env.lua.execute("Mock.bags[279960] = nil")
        env.fire("BAG_UPDATE_DELAYED")
        later = env.relog(after_seconds=1200, prepare="Mock.itemCooldown = { start = 0, duration = 0 }")
        self.assertEqual(char(later).cooldownReadyAt, ready_at)
        self.assertEqual(later.ns.OwnCamp.CooldownRemaining(later.ns.OwnCamp), 2400)
        later.assert_no_errors()

    def test_global_cooldown_is_not_camping_cooldown(self):
        env = started("Mock.bags[279960] = 1\nMock.itemCooldown = { start = Mock.time, duration = 1.5 }")
        self.assertEqual(env.ns.OwnCamp.CooldownRemaining(env.ns.OwnCamp), 0)


class LastBenefitsTest(unittest.TestCase):
    def test_benefits_survive_relog(self):
        env = started()
        b = env.mock.AddAura(BENEFITS, 3600)
        env.lua.eval("function(id, t) Mock.tooltips[id] = t end")(b, env.lua.table_from([HEADER, DESCRIPTION]))
        env.advance(1)
        env.advance(1800 - 1)  # 30 minutes left at logout
        later = env.relog(after_seconds=600)  # aura is gone on this client
        oc = later.ns.OwnCamp
        self.assertAlmostEqual(oc.BenefitsRemaining(oc), 1200, delta=2)
        objects = [o.key for o in oc.LastBenefits(oc).objects.values()]
        self.assertEqual(objects, ["lodestone"])

    def test_boosted_rest_hidden_without_spell_id(self):
        env = started()
        self.assertIsNone(env.ns.Catalog.auras.boostedRest)
        self.assertIsNone(env.ns.OwnCamp.BoostedRestRemaining(env.ns.OwnCamp))


class AlertsTest(unittest.TestCase):
    def notices(self, env):
        return list(env.mock.raidNotices.values())

    def test_benefits_gained_and_ending_once(self):
        env = started()
        shown = env.fired("ALERT_SHOWN")
        env.mock.AddAura(BENEFITS, 3600)
        self.assertEqual(shown, [("gained",)])
        self.assertIn("Бонусы лагеря получены.", self.notices(env))
        env.advance(3300)
        self.assertEqual(shown, [("gained",), ("ending",)])
        env.advance(400)
        self.assertEqual(len(shown), 2)

    def test_restored_aura_does_not_announce_gain(self):
        env = started(f"Mock.auras[7] = {{ auraInstanceID = 7, spellId = {BENEFITS}, duration = 3600, "
                      f"expirationTime = Mock.time + 1800 }}")
        shown = env.fired("ALERT_SHOWN")
        env.fire("PLAYER_ENTERING_WORLD")
        self.assertEqual(shown, [])
        env.advance(1500)
        self.assertEqual(shown, [("ending",)])

    def test_fire_and_cooldown_alerts(self):
        env = started("Mock.bags[279960] = 1")
        shown = env.fired("ALERT_SHOWN")
        env.lua.execute("Mock.itemCooldown = { start = Mock.time, duration = 3600 }")
        env.mock.Cast(FIRE1_PLACE)
        env.advance(540)
        self.assertEqual(shown, [("fire",)])
        env.advance(3600)
        self.assertEqual(shown, [("fire",), ("cooldown",)])

    def test_disabled_alert_is_silent(self):
        env = started("Mock.bags[279960] = 1")
        env.lua.eval('LibStub("AceAddon-3.0"):GetAddon("Campkeeper")').db.profile.alerts.cooldown = False
        shown = env.fired("ALERT_SHOWN")
        env.lua.execute("Mock.itemCooldown = { start = Mock.time, duration = 60 }")
        env.fire("BAG_UPDATE_COOLDOWN")
        env.advance(120)
        self.assertEqual(shown, [])

    def test_camp_nearby_throttled(self):
        env = started()
        shown = env.fired("ALERT_SHOWN")
        near = env.mock.AddAura(1283391)
        env.mock.RemoveAura(near)
        env.advance(10)
        env.mock.AddAura(1283391)
        self.assertEqual(shown, [("near",)])
        env.assert_no_errors()


if __name__ == "__main__":
    unittest.main()
