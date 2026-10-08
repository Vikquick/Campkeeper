import unittest

from wowenv import WowEnv

PREFIX = "CAMPK"


def started(prepare=""):
    env = WowEnv(locale="ruRU")
    env.lua.execute("""
      Mock.items[279944] = { name = "Круг для заточки" }
      Mock.items[279988] = { name = "Наковальня" }
      Mock.items[279960] = { name = "Магнетит" }
      Mock.items[279952] = { name = "Плавильня" }
      Mock.spells[1307227] = { name = "Обычный костер" }
      Mock.professions = { { skillLine = 186, rank = 300 }, { skillLine = 185, rank = 50 } }
    """)
    env.lua.execute(prepare)
    env.load_toc()
    env.login()
    env.assert_no_errors()
    return env


class WindowTest(unittest.TestCase):
    def test_toggle_and_tabs(self):
        env = started()
        w = env.ns.Window
        env.mock.Slash("/ck")
        self.assertTrue(w.IsShown(w))
        self.assertEqual(w.frame.selectedTab, 1)
        self.assertTrue(w.contents[1].shown)
        for i in (2, 3, 1):
            w.tabs[i].scripts.OnClick(w.tabs[i])
            self.assertEqual([c.shown for c in w.contents.values()], [j == i for j in (1, 2, 3)])
        self.assertIn("CampkeeperWindow", list(env.g.UISpecialFrames.values()))
        env.mock.Slash("/campkeeper")
        self.assertFalse(w.IsShown(w))
        env.assert_no_errors()


class CatalogTabTest(unittest.TestCase):
    def test_grid(self):
        env = started("Mock.knownSpells[1230171] = true")  # Изготовить круг для заточки
        tab = env.ns.CatalogTab
        grid = list(tab.Grid(tab).values())
        self.assertEqual(len(grid), 12)
        smith = next(r for r in grid if r.profession == "blacksmithing")
        self.assertEqual(smith.name, "Кузнечное дело")
        self.assertIsNone(smith.playerSkill)
        self.assertEqual((smith.cells[1].name, smith.cells[1].known), ("Круг для заточки", True))
        self.assertEqual((smith.cells[2].name, smith.cells[2].replaces, smith.cells[2].skill),
                         ("Наковальня", "Круг для заточки", 140))
        cooking = next(r for r in grid if r.profession == "cooking")
        self.assertEqual((cooking.cells[1].key, cooking.cells[1].name, cooking.playerSkill), ("fire1", "Обычный костер", 50))
        mining = next(r for r in grid if r.profession == "mining")
        self.assertEqual(mining.playerSkill, 300)
        env.ns.Window.Show(env.ns.Window, 1)
        env.assert_no_errors()


def send_professions(env, sender, professions):
    """A group member's Campkeeper reports professions ({skillLineID: skill}) in party chat."""
    text = env.ns.Protocol.Encode(env.ns.Protocol, env.lua.table_from(
        {"v": 1, "t": "PROF", "p": env.lua.table_from(professions)}))
    env.fire("CHAT_MSG_ADDON", PREFIX, text, "PARTY", sender + "-Realm")


class PlannerTabTest(unittest.TestCase):
    def setUp(self):
        self.env = started('Mock.inGroup = true\nMock.group = { { name = "Bob", class = "PALADIN" }, { name = "Kim", class = "ROGUE" } }')
        self.tab = self.env.ns.PlannerTab

    def members(self):
        return {m.name: m for m in self.tab.Members(self.tab).values()}

    def test_members_from_group_and_addon(self):
        env = self.env
        m = self.members()
        self.assertEqual(sorted(m), ["Bob", "Kim", "Tester"])
        self.assertEqual((m["Tester"].source, m["Tester"].professions.mining), ("self", 300))
        self.assertEqual(m["Bob"].source, "none")
        send_professions(env, "Bob", {186: 150, 164: 300, 9999: 5})
        bob = self.members()["Bob"]
        self.assertEqual((bob.source, bob.professions.mining, bob.professions.blacksmithing), ("addon", 150, 300))
        env.assert_no_errors()

    def test_plan_to_group_chat(self):
        env = self.env
        send_professions(env, "Kim", {185: 10})
        env.ns.Window.Show(env.ns.Window, 2)
        self.tab.PostToChat(self.tab)
        chat = [s for s in env.mock.sent.values() if s.kind == "chat"]
        self.assertEqual(len(chat), 1)
        self.assertEqual(chat[0].chatType, "PARTY")
        # Bob is a paladin: mining (lodestone/smelter, Blessing of Might) is skipped, so neither Tester
        # nor Kim is needed elsewhere and the higher Cooking (Tester) lights the fire
        self.assertEqual(chat[0].msg, "План лагеря: Обычный костер - Tester;")
        env.assert_no_errors()

    def test_professions_sent_after_roster_change(self):
        env = self.env
        env.fire("GROUP_ROSTER_UPDATE")
        env.fire("GROUP_ROSTER_UPDATE")
        env.advance(6)
        profs = []
        for s in env.mock.sent.values():
            if s.kind == "addon" and s.prefix == PREFIX:
                msg = env.ns.Protocol.Decode(env.ns.Protocol, s.msg)
                if msg and msg.t == "PROF":
                    profs.append((s.chatType, msg.p[186]))
        self.assertEqual(profs, [("PARTY", 300)])


class PlannerTabUiTest(unittest.TestCase):
    def open(self, prepare=""):
        env = started(prepare)
        env.ns.Window.Show(env.ns.Window, 2)
        return env, env.ns.PlannerTab

    def test_alone_gets_an_explanation(self):
        env, tab = self.open()
        self.assertEqual(list(tab.lastLines.values()), ["1. Обычный костер - Tester"])
        self.assertEqual(list(tab.lastNotes.values()), ["В группе вы один: для других объектов нужны ещё участники."])
        ui = tab.ui
        self.assertEqual([r.checked for r in list(ui.roles.values())[:3]], [True, False, False])
        self.assertEqual([r.checked for r in list(ui.fires.values())[:3]], [True, False, False])
        env.assert_no_errors()

    def test_radio_selects_fire_and_goal(self):
        env, tab = self.open()
        fires = list(tab.ui.fires.values())
        fires[2].scripts.OnClick(fires[2])
        self.assertEqual([r.checked for r in fires[:3]], [False, False, True])
        self.assertEqual(tab.lastPlan.slots, 10)
        self.assertEqual(list(tab.lastNotes.values())[0], "Этот костёр некому развести (Кулинария 220)")

    def test_members_without_addon_and_covered_note(self):
        env, tab = self.open('Mock.inGroup = true\nMock.group = { { name = "Bob", class = "PALADIN" }, '
                             '{ name = "Kim", class = "ROGUE" } }')
        rows = list(tab.ui.members.values())
        kim = next(r for r in rows if r.memberName == "Kim")
        self.assertEqual((kim.name.text, kim.profs.text), ("Kim (нет Campkeeper)", "профессии неизвестны"))
        notes = list(tab.lastNotes.values())
        self.assertIn("Без Campkeeper: Bob, Kim - их профессии неизвестны и в план не входят.", notes)
        self.assertTrue(any(n.startswith("Пропущено, этот бафф даёт класс в группе: ") and "Магнетит" in n for n in notes))
        # alone among known members, but not alone in the group: no "you are alone" note
        self.assertNotIn("В группе вы один: для других объектов нужны ещё участники.", notes)

        send_professions(env, "Kim", {164: 150})
        kim = next(r for r in list(tab.ui.members.values()) if r.memberName == "Kim")
        self.assertEqual((kim.name.text, kim.profs.text), ("Kim (через Campkeeper)", "Кузнечное дело 150"))
        self.assertIn("2. Наковальня (T2) - Kim", list(tab.lastLines.values()))
        self.assertIn("Без Campkeeper: Bob - их профессии неизвестны и в план не входят.", list(tab.lastNotes.values()))
        env.assert_no_errors()


class AltsTabTest(unittest.TestCase):
    def test_rows_and_minimap_tooltip(self):
        env = started("Mock.bags[279960] = 2\nMock.itemCooldown = { start = Mock.time, duration = 750 }")
        env.lua.execute("""
          local chars = LibStub("AceAddon-3.0"):GetAddon("Campkeeper").db.global.chars
          chars["Alt - Realm"] = { name = "Alt", realm = "Realm", class = "MAGE", items = {},
            professions = { tailoring = { skill = 140 } }, recipes = {}, cooldownReadyAt = Mock.serverTime - 5 }
        """)
        tab = env.ns.AltsTab
        rows = list(tab.Rows(tab).values())
        self.assertEqual([r.name for r in rows], ["Tester", "Alt"])
        me, alt = rows
        self.assertEqual((me["items"], me.cooldown, me.ready), (2, "12:30", False))
        self.assertEqual((alt.professions, alt.cooldown, alt.ready, alt.blueprints), ("Портняжное дело 140", "готово", True, "неизвестно"))

        lines = []
        tooltip = env.lua.table_from({
            "AddLine": lambda self, text, *a: lines.append(text),
            "AddDoubleLine": lambda self, left, right, *a: lines.append(f"{left}: {right}"),
        })
        env.lua.eval('function(ns, tt) ns.callbacks:Fire("MINIMAP_TOOLTIP", tt) end')(env.ns, tooltip)
        self.assertEqual(lines, ["Перезарядка походных предметов", "Tester: 12:30", "Alt: готово"])
        w = env.ns.Window
        w.Show(w, 3)
        self.assertTrue(w.contents[3].shown)
        env.assert_no_errors()

    def test_cooldown_counts_down_while_open(self):
        env = started("Mock.bags[279960] = 1; Mock.itemCooldown = { start = Mock.time, duration = 750 }")
        w = env.ns.Window
        w.Show(w, 3)
        self.assertEqual(env.ns.AltsTab.lastCooldownText, "Перезарядка походных предметов: 12:30")
        env.advance(5)
        self.assertEqual(env.ns.AltsTab.lastCooldownText, "Перезарядка походных предметов: 12:25")
        env.assert_no_errors()


if __name__ == "__main__":
    unittest.main()
