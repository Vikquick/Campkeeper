import unittest

from wowenv import WowEnv

BENEFITS = 1229741
GROUP = ('Mock.inGroup = true\n'
         'Mock.group = { { name = "Bob", class = "PALADIN", benefits = 2400 }, { name = "Kim", class = "ROGUE" }, '
         '{ name = "Zed", class = "MAGE", visible = false } }')
PAIR = 'Mock.inGroup = true\nMock.group = { { name = "Bob", class = "PALADIN", benefits = 60 } }'


def started(prepare=""):
    env = WowEnv(locale="ruRU")
    env.lua.execute(prepare)
    env.load_toc()
    env.login()
    env.assert_no_errors()
    return env


def status(env):
    gb = env.ns.GroupBenefits
    return {m.name: (m.state, m.remaining) for m in gb.Status(gb).values()}


def chat_sent(env):
    return [(s.chatType, s.msg) for s in env.mock.sent.values() if s.kind == "chat"]


class StatusTest(unittest.TestCase):
    def test_has_none_and_unknown(self):
        env = started(GROUP)
        env.mock.AddAura(BENEFITS, 3600)
        self.assertEqual(status(env), {"Tester": ("has", 3600), "Bob": ("has", 2400), "Kim": ("none", None),
                                       "Zed": ("unknown", None)})

    def test_alone(self):
        env = started()
        self.assertEqual(status(env), {"Tester": ("none", None)})

    def test_hidden_values_are_unknown(self):
        env = started(GROUP)
        env.mock.AddAura(BENEFITS, 3600)
        env.mock.secretAuras = True
        s = status(env)
        self.assertEqual((s["Bob"][0], s["Tester"][0]), ("unknown", "unknown"))
        env.assert_no_errors()

    def test_combat_keeps_the_last_known_state(self):
        env = started(GROUP)
        before = status(env)
        env.mock.inCombat = True
        env.lua.execute("Mock.group[2].benefits = 3600")
        self.assertEqual(status(env), before)
        env.mock.inCombat = False
        self.assertEqual(status(env)["Kim"][0], "has")


class ChatTest(unittest.TestCase):
    def post(self, env):
        gb = env.ns.GroupBenefits
        return gb.PostToChat(gb)

    def test_members_without_benefits(self):
        env = started(GROUP)
        self.post(env)
        # Tester has none either; Zed is unknown and not listed
        self.assertEqual(chat_sent(env), [("PARTY", "Без бонусов лагеря: Tester, Kim")])

    def test_everyone_has_them(self):
        env = started(PAIR)
        env.mock.AddAura(BENEFITS, 3600)
        self.post(env)
        self.assertEqual(chat_sent(env), [("PARTY", "Бонусы лагеря есть у всех.")])

    def test_raid_chat(self):
        env = started(GROUP + "\nMock.inRaid = true")
        self.post(env)
        self.assertEqual([c for c, _ in chat_sent(env)], ["RAID"])

    def test_alone_nothing_is_sent(self):
        env = started()
        self.post(env)
        self.assertEqual(chat_sent(env), [])


class ReadyCheckTest(unittest.TestCase):
    def test_summary_for_the_player_only(self):
        env = started(GROUP)
        env.mock.AddAura(BENEFITS, 3600)
        env.fire("READY_CHECK", "Bob", 30)
        chat = "\n".join(env.chat())
        self.assertIn("Без бонусов лагеря: Kim", chat)
        self.assertIn("Бонусы неизвестны: Zed", chat)
        self.assertEqual(chat_sent(env), [])
        env.assert_no_errors()

    def test_everyone_has_them(self):
        env = started(PAIR)
        env.mock.AddAura(BENEFITS, 3600)
        env.fire("READY_CHECK", "Bob", 30)
        self.assertIn("Бонусы лагеря есть у всех.", "\n".join(env.chat()))

    def test_turned_off(self):
        env = started(GROUP)
        opts = env.lua.eval('LibStub("AceConfigRegistry-3.0"):GetOptionsTable("Campkeeper", "dialog", "x-1")')
        opts.args.alerts.args.readyCheck.set(None, False)
        env.fire("READY_CHECK", "Bob", 30)
        self.assertNotIn("Без бонусов лагеря", "\n".join(env.chat()))

    def test_not_in_a_group(self):
        env = started()
        env.fire("READY_CHECK", "Tester", 30)
        self.assertNotIn("бонус", "\n".join(env.chat()).lower())


if __name__ == "__main__":
    unittest.main()
