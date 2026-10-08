import unittest

from wowenv import WowEnv

CORE = ["Core/Log.lua", "Core/Util.lua", "Data/Catalog.lua", "Core/Catalog.lua"]


def catalog_env(locale="ruRU"):
    env = WowEnv(locale=locale)
    env.lua.execute("""
      Mock.items[279944] = { name = "Круг для заточки" }
      Mock.items[279988] = { name = "Наковальня" }
      Mock.items[279957] = { name = "Пир Поваренка" }
      Mock.spells[1307257] = { name = "Пир Пирожка", description = "Накрывает пир Пирожка." }
      Mock.spells[1307227] = { name = "Обычный костер" }
    """)
    env.load_core(CORE)
    return env


class CatalogLookupTest(unittest.TestCase):
    def setUp(self):
        self.env = catalog_env()
        self.cat = self.env.ns.Catalog

    def call(self, method, *args):
        return getattr(self.cat, method)(self.cat, *args)

    def test_anvil_replaces_sharpening_wheel(self):
        anvil = self.call("Get", "anvil")
        self.assertEqual(anvil.profession, "blacksmithing")
        self.assertEqual(self.env.lua.eval("function(c) return c:Profession('blacksmithing') end")(self.cat), 164)
        self.assertEqual((anvil.tier, anvil.skill), (2, 140))
        self.assertEqual(self.call("Replaces", "anvil"), "sharpening_wheel")
        self.assertEqual(self.call("Name", "anvil"), ("Наковальня", True))
        self.assertEqual(self.call("Name", "sharpening_wheel")[0], "Круг для заточки")

    def test_higher_tier_without_replacement(self):
        bench = self.call("Get", "anarchist_workbench")
        self.assertEqual((bench.profession, bench.tier), ("engineering", 3))
        self.assertIsNone(self.call("Replaces", "anarchist_workbench"))
        self.assertEqual(list(self.call("Chain", "anvil").values()), ["sharpening_wheel", "anvil", "master_forge"])

    def test_fire_tiers(self):
        fires = [self.call("Fire", t) for t in (1, 2, 3)]
        self.assertEqual([f.skill for f in fires], [1, 140, 220])
        self.assertEqual([f.slots for f in fires], [3, 5, 10])
        self.assertEqual([f.burn for f in fires], [600, 600, 600])
        self.assertEqual(self.call("Name", "fire1")[0], "Обычный костер")

    def test_lookup_by_item_and_spell(self):
        self.assertEqual(self.call("ByItem", 279960).key, "lodestone")
        self.assertEqual(self.call("ByItem", 279973).key, "faction_banner")
        self.assertEqual(self.call("ByPlaceSpell", 1307240).key, "faction_banner")
        self.assertEqual(self.call("ByPlaceSpell", 1307252).key, "fire2")
        self.assertIsNone(self.call("ByItem", 1))

    def test_names_include_item_and_placement_spell(self):
        self.assertEqual(set(self.call("Names", "cooking_feast").values()), {"Пир Поваренка", "Пир Пирожка"})

    def test_order_lists_every_object_once(self):
        order = list(self.cat.order.values())
        self.assertEqual(len(order), 35)
        self.assertEqual(len(set(order)), 35)


class CatalogLoadingTest(unittest.TestCase):
    def test_placeholder_until_item_data_loads(self):
        env = catalog_env()
        env.lua.execute('Mock.items[279960] = { name = "Магнетит", loaded = false }')
        cat = env.ns.Catalog
        updated = env.fired("CATALOG_UPDATED")

        name, real = cat.Name(cat, "lodestone")
        self.assertEqual((name, real), ("Загрузка...", False))
        self.assertTrue(env.mock.requested["items"][279960])

        env.lua.execute("Mock.items[279960].loaded = true")
        cat.OnItemLoaded(cat, 279960, True)
        self.assertEqual(updated, [("lodestone",)])
        self.assertEqual(cat.Name(cat, "lodestone"), ("Магнетит", True))

    def test_english_client_names_come_from_client(self):
        env = catalog_env(locale="enUS")
        env.lua.execute('Mock.items[279960] = { name = "Lodestone" }')
        cat = env.ns.Catalog
        self.assertEqual(cat.Name(cat, "lodestone")[0], "Lodestone")

    def test_failed_load_is_logged(self):
        env = catalog_env()
        env.lua.execute('Mock.items[279960] = { name = "Магнетит", loaded = false }')
        cat = env.ns.Catalog
        cat.Name(cat, "lodestone")
        cat.OnItemLoaded(cat, 279960, False)
        msgs = [e.msg for e in env.ns.Log.Entries(env.ns.Log).values()]
        self.assertTrue(any("279960" in m for m in msgs))


class CatalogInAddonTest(unittest.TestCase):
    def test_item_load_event_reaches_catalog(self):
        env = WowEnv()
        env.lua.execute('Mock.items[279960] = { name = "Lodestone", loaded = false }')
        env.load_toc()
        env.login()
        updated = env.fired("CATALOG_UPDATED")
        cat = env.ns.Catalog
        self.assertFalse(cat.Name(cat, "lodestone")[1])
        env.mock.LoadItem(279960)
        self.assertEqual(updated, [("lodestone",)])
        env.assert_no_errors()


if __name__ == "__main__":
    unittest.main()
