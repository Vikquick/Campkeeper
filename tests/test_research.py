import unittest

from wowenv import WowEnv

NEAR, SITTING, BENEFITS = 1283391, 1229739, 1229741
FIRE1_PLACE, LODESTONE_PLACE = 1307227, 1307254
HEADER = "Бонусы лагеря"
LODESTONE = "Получены следующие бонусы лагеря:\r\n\r\nМагнетит: сила атаки ближнего боя повышена на 20.\r\n\r\n"
TENT = "Получены следующие бонусы лагеря:\r\n\r\nЛагерная палатка: прибавка к опыту во время отдыха.\r\n\r\n"
YARD = 1 / 3000


def started(prepare=""):
    env = WowEnv(locale="ruRU")
    env.lua.execute('Mock.items[279960] = { name = "Магнетит" }\n'
                    'Mock.items[279978] = { name = "Лагерная палатка" }\n'
                    'Mock.items[279988] = { name = "Наковальня" }\n'
                    'Mock.inGroup = true')
    env.lua.execute(prepare)
    env.load_toc()
    env.login()
    env.assert_no_errors()
    return env


def research(env):
    return env.g.CampkeeperDB["global"]["research"]


def benefits(env, description):
    b = env.mock.AddAura(BENEFITS, 3600)
    env.lua.eval("function(id, t) Mock.tooltips[id] = t end")(b, env.lua.table_from([HEADER, description]))
    env.advance(1)
    return b


class Q1Test(unittest.TestCase):
    def test_raw_lines_parsed_and_own_camp(self):
        env = started()
        env.mock.Cast(FIRE1_PLACE)
        env.mock.Cast(LODESTONE_PLACE)
        benefits(env, LODESTONE)
        q1 = list(research(env)["q1"].values())
        self.assertEqual(len(q1), 1)
        self.assertEqual(list(q1[0].lines.values()), [HEADER, LODESTONE])
        self.assertEqual(list(q1[0].parsed.values()), ["lodestone:T1"])
        self.assertEqual(list(q1[0].own.values()), ["lodestone:T1"])
        env.fire("PLAYER_ENTERING_WORLD")  # same tooltip again is not duplicated
        self.assertEqual(len(list(research(env)["q1"].values())), 1)


class Q2FireTest(unittest.TestCase):
    def test_radius_and_burn_time(self):
        env = started()
        env.mock.Cast(FIRE1_PLACE)
        near = env.mock.AddAura(NEAR)
        env.mock.player.x = env.mock.player.x + 6 * YARD
        env.advance(590)
        env.mock.RemoveAura(near)
        q2 = [(e.near, e.d) for e in research(env)["q2"].values()]
        self.assertEqual(q2, [(True, 0), (False, 6)])
        fire = list(research(env)["fire"].values())
        self.assertEqual((fire[0].elapsed, fire[0].tier), (590, 1))

    def test_walking_away_is_not_a_burnout(self):
        env = started()
        env.mock.Cast(FIRE1_PLACE)
        near = env.mock.AddAura(NEAR)
        env.mock.player.x = env.mock.player.x + 40 * YARD
        env.mock.RemoveAura(near)
        self.assertEqual(list(research(env)["fire"].values()), [])
        self.assertEqual(list(research(env)["q2"].values())[-1].d, 40)


class Q3DurationsTest(unittest.TestCase):
    def test_new_auras_at_camp_with_tent(self):
        env = started()
        env.mock.AddAura(4444, 30, "Вне лагеря")  # AWAY: ignored
        env.mock.AddAura(NEAR)
        env.mock.AddAura(SITTING, 60)
        benefits(env, TENT)
        env.mock.AddAura(12345, 7200, "Усиленный отдых")
        q3 = research(env)["q3"]
        self.assertIsNone(q3[4444])
        self.assertEqual((q3[12345].name, q3[12345].duration, q3[12345].tent), ("Усиленный отдых", 7200, True))
        self.assertIsNone(q3[BENEFITS])
        d = research(env)["durations"]
        self.assertEqual((d.sitting[60], d.benefits[3600]), (1, 1))


class Q4Test(unittest.TestCase):
    def test_camp_blueprint_in_bags(self):
        env = started("""
          Mock.itemClass[500001] = 9
          Mock.itemClass[500002] = 9
          Mock.containers[0] = { [1] = 500001, [2] = 500002 }
          Mock.bagTooltips["0:1"] = { "Чертеж: Наковальня", "Использование: Обучает изготовлению наковальни.", "Already known" }
          Mock.bagTooltips["0:2"] = { "Чертеж: клинок из железного дерева", "Требуется: Кузнечное дело (300)" }
        """)
        env.advance(6)
        q4 = research(env)["q4"]
        self.assertEqual((q4[500001].teaches, q4[500001].known, q4[500001].name), ("anvil", True, "Чертеж: Наковальня"))
        self.assertIsNone(q4[500002])
        self.assertTrue(research(env)["q4other"][500002])


class Q5Test(unittest.TestCase):
    def test_sent_echo_and_others(self):
        env = started()
        env.mock.Cast(FIRE1_PLACE)
        env.fire("CHAT_MSG_ADDON", "CAMPK", "x", "PARTY", "Tester-Realm")
        env.fire("CHAT_MSG_ADDON", "CAMPK", "x", "CHANNEL", "Ann-Realm")
        env.fire("CHAT_MSG_ADDON", "OTHER", "x", "CHANNEL", "Ann-Realm")
        q5 = research(env)["q5"]
        self.assertEqual(q5.sent["PARTY"], 1)
        self.assertEqual(q5.echo["PARTY"], 1)
        self.assertEqual(q5.others["CHANNEL"], 1)
        self.assertTrue(q5.senders["Ann"])

    def test_queue_reason_and_flush(self):
        env = started()
        env.mock.chatLockdown = True
        env.mock.Cast(FIRE1_PLACE)
        q5 = research(env)["q5"]
        self.assertEqual((q5.queued["PARTY"], q5.reasons["lockdown"]), (1, 1))
        self.assertIsNone(q5.flushed["PARTY"])
        env.mock.chatLockdown = False
        env.advance(5)
        self.assertEqual(q5.flushed["PARTY"], 1)


    def test_client_state_samples_and_changes(self):
        env = started()
        env.advance(10)
        q5 = research(env)["q5"]
        self.assertGreaterEqual(q5.state["free"], 2)
        env.mock.addonRestricted = True
        env.advance(5)
        self.assertEqual(q5.state["restricted"], 1)
        change = list(q5.changes.values())[-1]
        self.assertEqual((change["from"], change["to"]), ("free", "restricted"))
        self.assertIsNotNone(change["combat"])
        env.advance(5)
        self.assertEqual(len(list(q5.changes.values())), 1)  # no new entry without a change


class CommTestCommand(unittest.TestCase):
    def test_sends_past_the_restriction_and_reports_echo(self):
        env = started()
        env.advance(6)  # joined the shared channel
        env.mock.addonRestricted = True
        env.mock.Slash("/ck commtest")
        tests = [s for s in env.mock.sent.values()
                 if s.kind == "addon" and s.prefix == "CAMPK" and s.msg.startswith("CKTEST")]
        self.assertEqual(sorted(s.chatType for s in tests), ["CHANNEL", "PARTY", "WHISPER"])
        whisper = next(s for s in tests if s.chatType == "WHISPER")
        self.assertEqual(whisper.target, "Tester")
        env.fire("CHAT_MSG_ADDON", "CAMPK", whisper.msg, "WHISPER", "Tester-Realm")
        env.advance(5)
        last = list(research(env)["q5"]["tests"].values())[-1]
        self.assertEqual(last["why"], "restricted")
        self.assertEqual(last["results"]["WHISPER"], "ok")
        self.assertTrue(last["echo"]["WHISPER"])
        self.assertIsNone(last["echo"]["PARTY"])
        chat = "\n".join(env.chat())
        self.assertIn("Сообщения аддонов: ограничены клиентом (restricted)", chat)
        self.assertIn("Эхо получено: WHISPER; нет эха: CHANNEL, PARTY", chat)
        env.mock.Slash("/ck report")
        self.assertIn("Q5 проверка: WHISPER ok эхо, CHANNEL ok -, PARTY ok - (restricted)", "\n".join(env.chat()))
        env.assert_no_errors()


    def test_whisper_and_echo_use_the_surname(self):
        env = started('Mock.uniqueNames = true\nMock.surname = "Narec"')
        env.mock.Slash("/ck commtest")
        whisper = next(s for s in env.mock.sent.values() if s.kind == "addon" and s.chatType == "WHISPER")
        self.assertEqual(whisper.target, "Tester Narec")
        env.fire("CHAT_MSG_ADDON", "CAMPK", whisper.msg, "WHISPER", "Tester Narec")
        env.advance(5)
        q5 = research(env)["q5"]
        self.assertEqual(q5.echo["WHISPER"], 1)
        self.assertIsNone(q5.others["WHISPER"])


class BlockedErrorsCatalogTest(unittest.TestCase):
    def test_blocked_errors_and_catalog(self):
        env = started("Mock.missingItems = { [279960] = true }\nMock.missingSpells = { [1307254] = true }")
        env.fire("ADDON_ACTION_BLOCKED", "Campkeeper", "CampkeeperPanelRow1:Show()")
        env.fire("ADDON_ACTION_BLOCKED", "OtherAddon", "Foo()")
        self.assertEqual([b.func for b in research(env)["blocked"].values()], ["CampkeeperPanelRow1:Show()"])

        env.ns.OwnCamp.NoteAttempt(env.ns.OwnCamp, "lodestone")
        env.fire("UI_ERROR_MESSAGE", 57, "Нельзя расположить объект так близко к существу или предмету.")
        errors = list(research(env)["errors"].values())
        self.assertEqual((errors[0].type, errors[0].key), (57, "lodestone"))

        env.advance(6)
        c = research(env)["catalog"]
        self.assertEqual(list(c.missingItems.values()), [279960])
        self.assertEqual(list(c.missingSpells.values()), [1307254])


class ReportTest(unittest.TestCase):
    def test_report_and_clear(self):
        env = started()
        benefits(env, LODESTONE)
        env.advance(6)
        env.mock.Slash("/ck report")
        chat = "\n".join(env.chat())
        self.assertIn("Данные беты (хранятся только у вас):", chat)
        self.assertIn("Q1 подсказки бонусов: 1; старшие тиры: -; неизвестные имена: -", chat)
        self.assertIn("Длительности: сидение - с; бонусы 3600 x1 с", chat)
        self.assertIn("Проверка каталога (сборка 70245): нет предметов 0, нет заклинаний 0", chat)
        env.mock.Slash("/ck report clear")
        self.assertEqual(len(list(research(env)["q1"].values())), 0)
        env.assert_no_errors()

    def test_disabled_collects_nothing_but_keeps_data(self):
        env = started()
        benefits(env, LODESTONE)
        opts = env.lua.eval('LibStub("AceConfigRegistry-3.0"):GetOptionsTable("Campkeeper", "dialog", "x-1")')
        opts.args.general.args.research.set(None, False)
        env.mock.AddAura(SITTING, 60)
        self.assertEqual(len(list(research(env)["q1"].values())), 1)
        self.assertIsNone(research(env)["durations"].sitting[60])

    def test_research_data_is_never_sent(self):
        env = started("Mock.inGuild = true")
        env.mock.Cast(FIRE1_PLACE)
        benefits(env, LODESTONE)
        env.advance(15)
        p = env.ns.Protocol
        for s in env.mock.sent.values():
            if s.kind == "addon":
                self.assertEqual(s.prefix, "CAMPK")
                self.assertIn(p.Decode(p, s.msg).t, ("CAMP", "SYNC", "PROF"))
                self.assertNotIn("Бонусы лагеря", s.msg)
            else:
                self.fail("unexpected chat message: %s" % s.msg)


if __name__ == "__main__":
    unittest.main()
