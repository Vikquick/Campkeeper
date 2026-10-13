import unittest

from test_camp_store import Store, YARD
from wowenv import WowEnv

NEAR = 1283391
FIRE1_PLACE = 1307227
PIN = "|Hworldmap:1429:5000:5000|h"


def started(prepare=""):
    env = WowEnv(locale="ruRU")
    env.lua.execute('Mock.items[279960] = { name = "Магнетит" }\n'
                    'Mock.spells[1307227] = { name = "Обычный костер" }')
    env.lua.execute(prepare)
    env.load_toc()
    env.login()
    env.assert_no_errors()
    return env


def chat_sent(env):
    return [s for s in env.mock.sent.values() if s.kind == "chat"]


def current(env):
    return env.ns.Announce.CurrentCamp(env.ns.Announce)


class CurrentCampTest(unittest.TestCase):
    def test_own_camp(self):
        env = started()
        env.mock.Cast(FIRE1_PLACE)
        env.mock.AddAura(NEAR)
        camp = current(env)
        self.assertEqual((camp.source, camp.tier), ("self", 1))

    def test_known_camp_nearby_wins_by_trust_then_distance(self):
        env = started()
        s = Store(env)
        s.add("far", x=0.5 + 35 * YARD, source="party")
        s.add("chan", x=0.5 + 5 * YARD + 0.2, source="channel")  # another camp, out of range
        env.mock.AddAura(NEAR)
        self.assertEqual(current(env).id, "far")
        env.mock.Cast(FIRE1_PLACE)  # the own fire right here is trusted more
        self.assertEqual(current(env).source, "self")

    def test_unknown_camp_is_the_player_position_without_objects(self):
        env = started()
        env.mock.AddAura(NEAR)
        camp = current(env)
        self.assertTrue(camp.id.startswith("here-1429-"))
        self.assertEqual((camp.mapID, camp.x, camp.y, camp.tier), (1429, 0.5, 0.5, None))
        self.assertEqual(list(camp.objects.keys()), [])

    def test_away_from_any_camp(self):
        env = started()
        Store(env).add("stale", source="party")  # a record here, but no campfire aura: the fire is gone
        self.assertIsNone(current(env))
        env.mock.Slash("/ck announce")
        self.assertEqual(chat_sent(env), [])
        self.assertIn("Вы не у лагеря.", "\n".join(env.chat()))


class SendTest(unittest.TestCase):
    def at_camp(self, prepare=""):
        env = started(prepare)
        env.mock.Cast(FIRE1_PLACE)
        env.mock.AddAura(NEAR)
        return env

    def channels(self, env):
        return [c.key for c in env.ns.Announce.Channels(env.ns.Announce).values()]

    def test_available_channels(self):
        self.assertEqual(self.channels(self.at_camp()), ["general"])
        self.assertEqual(self.channels(self.at_camp("Mock.inGroup = true\nMock.inGuild = true")),
                         ["group", "guild", "general"])
        self.assertEqual(self.channels(self.at_camp("Mock.generalChannel = nil\nMock.inGuild = true")), ["guild"])

    def test_default_is_group_then_guild_then_general(self):
        env = self.at_camp("Mock.inGroup = true\nMock.inGuild = true")
        env.mock.Slash("/ck announce")
        sent = chat_sent(env)
        self.assertEqual([s.chatType for s in sent], ["PARTY"])
        self.assertIn("Обычный костер, 0/3.", sent[0].msg)
        self.assertIn(PIN, sent[0].msg)
        self.assertTrue(sent[0].msg.endswith("(Campkeeper T1 10m)"))

        env = self.at_camp("Mock.inRaid = true\nMock.inGroup = true")
        env.mock.Slash("/ck announce")
        self.assertEqual([s.chatType for s in chat_sent(env)], ["RAID"])

        env = self.at_camp()
        env.mock.Slash("/ck announce")
        sent = chat_sent(env)
        self.assertEqual([(s.chatType, s.target) for s in sent], [("CHANNEL", 1)])

    def test_explicit_channel(self):
        env = self.at_camp("Mock.inGroup = true\nMock.inGuild = true")
        env.mock.Slash("/ck announce guild")
        env.mock.Slash("/ck announce general")
        self.assertEqual([s.chatType for s in chat_sent(env)], ["GUILD", "CHANNEL"])

    def test_unavailable_and_unknown_channel(self):
        env = self.at_camp()
        env.mock.Slash("/ck announce guild")
        env.mock.Slash("/ck announce everyone")
        self.assertEqual(chat_sent(env), [])
        chat = "\n".join(env.chat())
        self.assertIn("Этот чат сейчас недоступен.", chat)
        self.assertIn("/ck announce [group||guild||general]", chat)

    def test_repeat_waits_two_minutes(self):
        env = self.at_camp("Mock.inGroup = true")
        env.mock.Slash("/ck announce")
        env.advance(30)
        env.mock.Slash("/ck announce")
        self.assertEqual(len(chat_sent(env)), 1)
        self.assertIn("Этот лагерь уже объявлен в этом чате. Подождите 1:30.", "\n".join(env.chat()))
        env.mock.Slash("/ck announce general")  # another channel is free
        self.assertEqual(len(chat_sent(env)), 2)
        env.advance(91)
        env.mock.Slash("/ck announce")
        self.assertEqual(len(chat_sent(env)), 3)
        env.assert_no_errors()

    def test_language_of_the_announcement_is_a_setting(self):
        env = self.at_camp("Mock.inGroup = true")
        opts = env.lua.eval('LibStub("AceConfigRegistry-3.0"):GetOptionsTable("Campkeeper", "dialog", "x-1")')
        language = opts.args.sharing.args.language
        self.assertEqual(language.get(), "client")
        self.assertEqual(dict(language["values"].items()),
                         {"client": "Как в игре", "enUS": "Английский", "ruRU": "Русский"})
        language.set(None, "enUS")
        env.mock.Slash("/ck announce")
        (sent,) = chat_sent(env)
        self.assertTrue(sent.msg.startswith("Basic Campfire, 0/3. 10 min left. "), sent.msg)
        self.assertTrue(sent.msg.endswith("(Campkeeper T1 10m)"))
        env = env.relog(1)
        self.assertEqual(env.ns.Announce.Language(env.ns.Announce), "enUS")  # the choice is saved

    def test_unknown_camp_is_a_short_line_with_a_hint_for_the_player(self):
        # beta 2026-10-14: at a camp of someone else the line was "Camp. [pin] (Campkeeper -:-:0)"
        env = started("Mock.inGroup = true")
        env.mock.AddAura(NEAR)
        env.mock.Slash("/ck announce")
        (sent,) = chat_sent(env)
        self.assertTrue(sent.msg.startswith("Лагерь здесь. "), sent.msg)
        self.assertTrue(sent.msg.endswith("|h|r (Campkeeper)"), sent.msg)
        self.assertIn("Об этом лагере пока ничего не известно: посидите у костра, и в объявлении будет его состав.",
                      "\n".join(env.chat()))
        env.fire("CHAT_MSG_PARTY", sent.msg, "Tester-Realm")  # the bare tag still confirms delivery
        self.assertIn("seen in chat: group", [e.msg for e in env.ns.Log.Entries(env.ns.Log).values()])

    def test_known_camp_gets_no_hint(self):
        env = self.at_camp("Mock.inGroup = true")
        env.mock.Slash("/ck announce")
        self.assertNotIn("ничего не известно", "\n".join(env.chat()))

    def test_nothing_is_announced_without_the_player(self):
        env = self.at_camp("Mock.inGroup = true\nMock.inGuild = true")
        env.advance(600)
        self.assertEqual(chat_sent(env), [])


def logs(env):
    return [e.msg for e in env.ns.Log.Entries(env.ns.Log).values()]


class ConfirmationTest(unittest.TestCase):
    """The debug log answers "did my announcement go out?": sent, then seen in chat or not."""

    def announced(self):
        env = started()
        env.mock.Cast(FIRE1_PLACE)
        env.mock.AddAura(NEAR)
        env.mock.Slash("/ck announce")
        (sent,) = chat_sent(env)
        return env, sent

    def test_sent_and_seen_are_logged(self):
        env, sent = self.announced()
        self.assertTrue(any(m.startswith("sent to general (CHANNEL 1)") for m in logs(env)), logs(env))
        env.fire("CHAT_MSG_CHANNEL", sent.msg, "Tester-Realm")
        self.assertIn("seen in chat: general", logs(env))
        env.advance(6)
        self.assertNotIn("Объявление не появилось в чате", "\n".join(env.chat()))
        self.assertFalse(any("not seen" in m for m in logs(env)))
        env.assert_no_errors()

    def test_missing_echo_is_reported(self):
        env, _ = self.announced()
        env.advance(6)
        self.assertIn("not seen in chat after 5 s: general", logs(env))
        self.assertIn("Объявление не появилось в чате: игра могла его не пропустить.", "\n".join(env.chat()))

    def test_confirmation_does_not_need_chat_reading(self):
        env, sent = self.announced()
        opts = env.lua.eval('LibStub("AceConfigRegistry-3.0"):GetOptionsTable("Campkeeper", "dialog", "x-1")')
        opts.args.sharing.args.chat.set(None, False)
        env.fire("CHAT_MSG_CHANNEL", sent.msg, "Tester-Realm")
        self.assertIn("seen in chat: general", logs(env))


if __name__ == "__main__":
    unittest.main()
