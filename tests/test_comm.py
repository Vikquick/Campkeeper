import unittest

from wowenv import WowEnv

FIRE1_PLACE, LODESTONE_PLACE = 1307227, 1307254
PREFIX = "CAMPK"


def started(prepare="Mock.inGroup = true"):
    env = WowEnv(locale="ruRU")
    env.lua.execute('Mock.items[279960] = { name = "Магнетит" }')
    env.lua.execute(prepare)
    env.load_toc()
    env.login()
    env.assert_no_errors()
    return env


def pump(env, seconds=3):
    """ChatThrottleLib sends from OnUpdate once bandwidth has built up (about a second or two)."""
    env.advance(seconds)


def sent(env, kind="CAMP"):
    out = []
    for s in env.mock.sent.values():
        if s.kind == "addon" and s.prefix == PREFIX:
            msg = env.ns.Protocol.Decode(env.ns.Protocol, s.msg)
            if msg and msg.t == kind:
                out.append((s.chatType, msg, s.msg))
    return out


def receive(env, msg_or_text, distribution="PARTY", sender="Ann-Realm"):
    text = msg_or_text if isinstance(msg_or_text, str) else env.ns.Protocol.Encode(env.ns.Protocol, msg_or_text)
    env.fire("CHAT_MSG_ADDON", PREFIX, text, distribution, sender)


def camp_msg(env, **fields):
    now = env.mock.serverTime
    msg = {"v": 1, "t": "CAMP", "id": "AAAAAAAA-%d" % now, "m": 1429, "x": 500, "y": 500, "tier": 1,
           "o": 0, "p": now - 10, "e": now + 590}
    msg.update(fields)
    return env.lua.table_from({k: v for k, v in msg.items() if v is not None})


def logs(env):
    return [e.msg for e in env.ns.Log.Entries(env.ns.Log).values()]


class ProtocolTest(unittest.TestCase):
    def setUp(self):
        self.env = started()
        self.p = self.env.ns.Protocol

    def test_round_trip(self):
        lua = self.env.lua
        now = self.env.mock.serverTime
        rec = lua.table_from({"id": "0ABCDEF1-%d" % now, "mapID": 1429, "x": 0.4567, "y": 0.1234, "tier": 2,
                              "objects": lua.table_from({"lodestone": True, "iron_oven": True}),
                              "placedAt": now, "expiresAt": now + 600})
        text = self.p.Encode(self.p, self.p.CampMessage(self.p, rec))
        back = self.p.CampRecord(self.p, self.p.Decode(self.p, text), "party", "Ann")
        self.assertEqual((back.mapID, back.x, back.y, back.tier), (1429, 0.457, 0.123, 2))
        self.assertEqual(sorted(back.objects.keys()), ["iron_oven", "lodestone"])  # iron_oven is bit 35
        self.assertEqual((back.placedAt, back.expiresAt), (now, now + 600))

    def test_incompatible_version_notice_once(self):
        receive(self.env, camp_msg(self.env, v=2))
        receive(self.env, camp_msg(self.env, v=2, id="other"))
        notices = [c for c in self.env.chat() if "несовместимая версия" in c]
        self.assertEqual(len(notices), 1)
        self.assertEqual(len(list(self.env.ns.CampStore.All(self.env.ns.CampStore).values())), 0)


class ValidationTest(unittest.TestCase):
    def check(self, reason, **fields):
        env = started()
        if reason == "ignored":
            env.lua.execute('Mock.ignored["Ann"] = true')
        receive(env, camp_msg(env, **fields))
        self.assertTrue(any(m.endswith(": " + reason) for m in logs(env)), (reason, logs(env)))
        self.assertEqual(len(list(env.ns.CampStore.All(env.ns.CampStore).values())), 0)

    def test_coords(self):
        self.check("coords", x=1001)

    def test_future(self):
        env = started()
        self.check("future", p=env.mock.serverTime + 300)

    def test_expired(self):
        env = started()
        self.check("expired", e=env.mock.serverTime - 1)

    def test_unknown_map(self):
        self.check("map", m=99999)

    def test_ignored(self):
        self.check("ignored")

    def test_shape(self):
        self.check("shape", tier=7)

    def test_rate_and_duplicate(self):
        env = started()
        msg = camp_msg(env)
        receive(env, msg)
        receive(env, msg)
        self.assertTrue(any(m.endswith(": duplicate") for m in logs(env)))
        for i in range(2):
            receive(env, camp_msg(env, id="X%d" % i, x=100 + i))
        self.assertTrue(any(m.endswith(": rate") for m in logs(env)))  # 4th message within a minute
        self.assertEqual(len(list(env.ns.CampStore.All(env.ns.CampStore).values())), 2)


class ChannelsTest(unittest.TestCase):
    def test_broadcast_to_guild_group_and_hidden_channel(self):
        env = started("Mock.inGroup = true\nMock.inGuild = true")
        env.advance(6)  # channel join is delayed after login
        self.assertEqual(env.mock.channels["Campkeeper"], 5)
        self.assertIn("Campkeeper", list(env.mock.removedChannels.values()))
        env.mock.Cast(FIRE1_PLACE)
        pump(env)
        self.assertEqual(sorted(c for c, _, _ in sent(env)), ["CHANNEL", "GUILD", "PARTY"])
        env.assert_no_errors()

    def test_disabling_shared_channel(self):
        env = started()
        env.advance(6)
        opts = env.lua.eval('LibStub("AceConfigRegistry-3.0"):GetOptionsTable("Campkeeper", "dialog", "x-1")')
        opts.args.sharing.args.channel.set(None, False)
        self.assertIsNone(env.mock.channels["Campkeeper"])
        env.mock.Cast(FIRE1_PLACE)
        pump(env)
        self.assertEqual([c for c, _, _ in sent(env)], ["PARTY"])

    def test_queue_while_restricted(self):
        env = started()
        env.advance(6)  # joined the shared channel
        env.mock.addonRestricted = True
        env.mock.Cast(FIRE1_PLACE)
        pump(env)
        self.assertEqual(sent(env), [])
        self.assertGreater(env.ns.Comm.QueueLength(env.ns.Comm), 0)
        env.mock.addonRestricted = False
        env.advance(5)
        self.assertEqual(len(sent(env)), 2)  # PARTY + CHANNEL
        self.assertEqual(env.ns.Comm.QueueLength(env.ns.Comm), 0)


class EventsTest(unittest.TestCase):
    def test_two_players_in_a_group(self):
        ann, bob = started(), started()
        ann.mock.Cast(FIRE1_PLACE)
        ann.mock.Cast(LODESTONE_PLACE)
        pump(ann, 8)  # two messages: the second waits for bandwidth
        for chat_type, _, text in sent(ann):
            if chat_type == "PARTY":
                receive(bob, text, "PARTY", "Ann-Realm")
        camps = list(bob.ns.CampStore.All(bob.ns.CampStore).values())
        self.assertEqual(len(camps), 1)
        self.assertEqual((camps[0].source, camps[0].tier, camps[0].confirmed), ("party", 1, True))
        self.assertEqual(sorted(camps[0].objects.keys()), ["lodestone"])
        bob.assert_no_errors()

    def test_sync_reply_after_random_delay(self):
        env = started("Mock.inGuild = true")
        env.ns.api.random = lambda: 0.5  # 2 + 0.5 * 6 = 5 s
        env.mock.Cast(FIRE1_PLACE)  # gives us a fresh camp to share
        pump(env)
        before = len(sent(env))
        receive(env, env.lua.table_from({"v": 1, "t": "SYNC", "id": "AAAAAAAA-1"}), "GUILD", "Cid-Realm")
        env.advance(4)
        self.assertEqual(len(sent(env)), before)
        env.advance(2)
        replies = [m for c, m, _ in sent(env) if m.r == "AAAAAAAA-1"]
        self.assertEqual(len(replies), 1)
        self.assertEqual(sent(env)[-1][0], "GUILD")

    def test_no_reply_when_two_others_answered(self):
        env = started("Mock.inGuild = true")
        env.ns.api.random = lambda: 1  # 8 s
        env.mock.Cast(FIRE1_PLACE)
        receive(env, env.lua.table_from({"v": 1, "t": "SYNC", "id": "S-1"}), "GUILD", "Cid-Realm")
        receive(env, camp_msg(env, id="D-1", x=100, r="S-1"), "GUILD", "Dan-Realm")
        receive(env, camp_msg(env, id="E-1", x=200, r="S-1"), "GUILD", "Eve-Realm")
        env.advance(9)
        self.assertEqual([m for _, m, _ in sent(env) if m.r == "S-1"], [])

    def test_sync_sent_after_login_in_guild(self):
        env = started("Mock.inGuild = true")
        env.advance(11)
        self.assertEqual([c for c, _, _ in sent(env, "SYNC")], ["GUILD"])


class IsolationTest(unittest.TestCase):
    def test_corrupt_message_is_logged_and_harmless(self):
        env = started()
        receive(env, "^1^Tgarbage")
        self.assertTrue(any("corrupt" in m for m in logs(env)))
        env.mock.AddAura(1283391)  # the panel keeps working
        self.assertTrue(env.ns.Panel.frame.shown)
        env.assert_no_errors()

    def test_handler_error_is_contained(self):
        env = started()
        env.ns.CampStore.Add = lambda *a: (_ for _ in ()).throw(RuntimeError("boom"))
        receive(env, camp_msg(env))
        self.assertTrue(any("error handling message" in m for m in logs(env)))
        env.assert_no_errors()


if __name__ == "__main__":
    unittest.main()
