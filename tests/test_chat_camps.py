import unittest

from test_camp_store import Store
from wowenv import WowEnv

NEAR = 1283391
FIRE1_PLACE = 1307227
PIN = "|cffffff00|Hworldmap:1429:3000:4000|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Map Pin Location]|h|r"
PIN2 = PIN.replace("3000:4000", "7000:7000")


def started(prepare=""):
    env = WowEnv(locale="ruRU")
    env.lua.execute('Mock.items[279960] = { name = "Магнетит" }\n'
                    'Mock.spells[1307227] = { name = "Обычный костер" }\n'
                    'Mock.spells[1307252] = { name = "Костер подмастерья" }')
    env.lua.execute(prepare)
    env.load_toc()
    env.login()
    env.assert_no_errors()
    return env


def say(env, text, sender="Ann-Realm", event="CHAT_MSG_CHANNEL"):
    env.fire(event, text, sender)


def camps(env):
    return Store(env).all()


def logs(env):
    return [e.msg for e in env.ns.Log.Entries(env.ns.Log).values()]


class RecognitionTest(unittest.TestCase):
    def test_player_without_the_addon(self):
        env = started()
        say(env, "костер тут " + PIN)
        (r,) = camps(env)
        self.assertEqual((r.source, r.mapID, r.x, r.y, r.confirmed), ("chat", 1429, 0.3, 0.4, False))
        self.assertIsNone(r.tier)
        self.assertTrue(r.reporters["Ann"])
        self.assertEqual(r.lastSeen, env.mock.serverTime)

    def test_every_chat_that_is_read(self):
        for event in ("CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY",
                      "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD"):
            env = started()
            say(env, "camp here " + PIN, event=event)
            self.assertEqual(len(camps(env)), 1, event)

    def test_pin_without_a_camp_word_and_word_without_a_pin(self):
        env = started()
        say(env, "тут редкий моб " + PIN)
        say(env, "кто-нибудь ставил лагерь?")
        say(env, "whisper is not read " + PIN, event="CHAT_MSG_WHISPER")
        self.assertEqual(camps(env), [])
        env.assert_no_errors()

    def lodestone_tag(self, env, tier=2, minutes=7):
        """The tag another Campkeeper writes for a camp with a Lodestone."""
        a = env.ns.Announce
        record = env.lua.table_from({"mapID": 1429, "x": 0.3, "y": 0.4, "tier": tier,
                                     "objects": env.lua.table_from({"lodestone": True}),
                                     "expiresAt": env.mock.serverTime + minutes * 60})
        text = a.Build(a, record, env.mock.serverTime)
        return text[text.index("(Campkeeper "):]

    def test_campkeeper_announcement_gives_tier_time_and_objects(self):
        env = started()
        say(env, "Костер подмастерья, 1/5 - Магнетит. Ещё 7 мин. " + PIN + " " + self.lodestone_tag(env))
        (r,) = camps(env)
        self.assertEqual((r.tier, r.expiresAt), (2, env.mock.serverTime + 420))
        self.assertEqual(sorted(r.objects.keys()), ["lodestone"])

    def test_campkeeper_announcement_in_another_language(self):
        # the objects come from the code in the tag, not from the names in the text
        env = started()
        say(env, "Feu de camp de compagnon, 1/5 - Pierre d'aimant. 7 min. " + PIN + " " + self.lodestone_tag(env))
        (r,) = camps(env)
        self.assertEqual((r.tier, sorted(r.objects.keys())), (2, ["lodestone"]))
        pins = env.ns.Pins
        self.assertIn("Магнетит", list(pins.TooltipLines(pins, r).lines.values()))  # shown in our language

    def test_tag_without_the_object_code(self):
        env = started()
        say(env, "Костер подмастерья, 1/5 - Магнетит. Ещё 7 мин. " + PIN + " (Campkeeper T2 7m)")
        (r,) = camps(env)
        self.assertEqual((r.tier, list(r.objects.keys())), (2, []))

    def test_fire_about_to_go_out_is_not_added(self):
        env = started()
        say(env, "Лагерь здесь. " + PIN + " (Campkeeper T1 0m)")
        self.assertEqual(camps(env), [])


class TrustTest(unittest.TestCase):
    def test_default_lifetime_is_ten_minutes(self):
        env = started()
        say(env, "костер тут " + PIN)
        env.advance(599)
        self.assertEqual(len(camps(env)), 1)
        env.advance(2)
        self.assertEqual(camps(env), [])

    def test_second_reporter_confirms(self):
        env = started()
        say(env, "костер тут " + PIN, sender="Ann-Realm")
        say(env, "campfire " + PIN, sender="Bob-Realm")
        (r,) = camps(env)
        self.assertTrue(r.confirmed)

    def test_own_message_is_ignored(self):
        env = started("Mock.uniqueNames = true\nMock.surname = \"Narec\"")
        env.mock.Cast(FIRE1_PLACE)
        env.mock.AddAura(NEAR)
        env.mock.Slash("/ck announce")
        (sent,) = [s for s in env.mock.sent.values() if s.kind == "chat"]
        say(env, sent.msg, sender="Tester Narec")
        self.assertEqual([r.source for r in camps(env)], ["self"])

    def test_logout_without_camps_is_quiet(self):
        # beta 2026-10-13: AceDB strips the empty camps table at logout before our handler runs
        env = started()
        env.fire("PLAYER_LOGOUT")
        env.assert_no_errors()

    def test_pin_tooltip_names_the_source(self):
        env = started()
        say(env, "костер тут " + PIN)
        pins = env.ns.Pins
        lines = list(pins.TooltipLines(pins, camps(env)[0]).lines.values())
        self.assertIn("Источник: чат", lines)
        self.assertIn("Не подтверждён: сообщил один игрок", lines)

    def test_chat_camps_are_not_saved_and_not_sent_to_the_guild(self):
        env = started("Mock.inGuild = true")
        Store(env).add("kept", x=0.8, y=0.8, source="guild")
        say(env, "костер тут " + PIN, sender="Ann-Realm")
        say(env, "campfire " + PIN, sender="Bob-Realm")  # confirmed now
        fresh = [r.source for r in env.ns.Comm.FreshCamps(env.ns.Comm).values()]
        self.assertEqual(fresh, ["guild"])
        env = env.relog(5)
        self.assertEqual([r.id for r in camps(env)], ["kept"])


class ValidationTest(unittest.TestCase):
    def test_ignored_sender(self):
        env = started('Mock.ignored["Ann"] = true')
        say(env, "костер тут " + PIN)
        self.assertEqual(camps(env), [])

    def test_fourth_report_in_a_minute_is_dropped(self):
        env = started()
        for i in range(4):
            say(env, "костер тут " + PIN.replace("3000:4000", "%d:4000" % (1000 + i * 2000)))
        self.assertEqual(len(camps(env)), 3)
        env.advance(61)
        say(env, "костер тут " + PIN2)
        self.assertEqual(len(camps(env)), 4)

    def test_unknown_map_and_coordinates_off_the_map(self):
        env = started()
        say(env, "camp " + PIN.replace(":1429:", ":999999:"))
        say(env, "camp " + PIN.replace("3000:4000", "30000:4000"))
        self.assertEqual(camps(env), [])
        env.assert_no_errors()

    def test_secret_text_is_skipped(self):
        env = started()
        env.fire("CHAT_MSG_CHANNEL", env.mock.Secret(), "Ann-Realm")
        env.fire("CHAT_MSG_CHANNEL", "костер тут " + PIN, env.mock.Secret())
        self.assertEqual(camps(env), [])
        env.assert_no_errors()

    def test_handler_error_is_contained(self):
        env = started()
        env.lua.eval("function(ns) ns.CampStore.Add = function() error('boom') end end")(env.ns)
        say(env, "костер тут " + PIN)
        self.assertTrue(any("boom" in m for m in logs(env)))
        env.assert_no_errors()

    def test_turned_off_in_settings(self):
        env = started()
        opts = env.lua.eval('LibStub("AceConfigRegistry-3.0"):GetOptionsTable("Campkeeper", "dialog", "x-1")')
        opts.args.sharing.args.chat.set(None, False)
        say(env, "костер тут " + PIN)
        self.assertEqual(camps(env), [])
        opts.args.sharing.args.chat.set(None, True)
        say(env, "костер тут " + PIN)
        self.assertEqual(len(camps(env)), 1)


if __name__ == "__main__":
    unittest.main()
