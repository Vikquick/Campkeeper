import unittest

from wowenv import ROOT, WowEnv
import toc


class SmokeTest(unittest.TestCase):
    def test_toc_files_present(self):
        _lua, missing = toc.load_order(ROOT / "Campkeeper/Campkeeper.toc")
        self.assertEqual(missing, [], "run: python tools/fetch_libs.py")

    def test_toc_declares_forever_interface(self):
        text = (ROOT / "Campkeeper/Campkeeper.toc").read_text(encoding="utf-8")
        self.assertIn("## Interface: 16001", text)
        self.assertIn("## SavedVariables: CampkeeperDB", text)

    def test_addon_loads_and_enables(self):
        env = WowEnv()
        env.load_toc()
        env.login()
        env.assert_no_errors()
        addon = env.lua.eval('LibStub("AceAddon-3.0"):GetAddon("Campkeeper")')
        self.assertTrue(addon.db is not None, "OnInitialize did not create the database")
        self.assertTrue(env.lua.eval('LibStub("AceAddon-3.0"):GetAddon("Campkeeper"):IsEnabled()'))
        self.assertEqual(env.g.CampkeeperDB["global"]["dbVersion"], 1)


if __name__ == "__main__":
    unittest.main()
