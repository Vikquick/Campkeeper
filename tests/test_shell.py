import unittest

from wowenv import WowEnv


def started(locale="enUS"):
    env = WowEnv(locale=locale)
    env.load_toc()
    env.login()
    env.assert_no_errors()
    return env


class LocaleTest(unittest.TestCase):
    def help_lines(self, locale):
        env = started(locale)
        env.mock.Slash("/camp help")
        env.assert_no_errors()
        return env.chat()

    def test_russian_client_gets_russian_strings(self):
        chat = "\n".join(self.help_lines("ruRU"))
        self.assertIn("Команды:", chat)
        self.assertIn("открыть окно Campkeeper", chat)

    def test_unsupported_locale_falls_back_to_english(self):
        chat = "\n".join(self.help_lines("deDE"))
        self.assertIn("Commands:", chat)
        self.assertIn("open the Campkeeper window", chat)

    def test_every_english_key_has_a_russian_translation(self):
        en, ru = WowEnv(locale="enUS"), WowEnv(locale="ruRU")
        for env in (en, ru):
            env.load_toc()
        en_keys = set(en.lua.eval('LibStub("AceLocale-3.0"):GetLocale("Campkeeper")').keys())
        ru_table = ru.lua.eval('LibStub("AceLocale-3.0"):GetLocale("Campkeeper")')
        untranslated = [k for k in en_keys if ru_table[k] == k]
        self.assertEqual(untranslated, [])


class DebugCommandTest(unittest.TestCase):
    def test_debug_shows_records_and_clear_empties_log(self):
        env = started()
        env.lua.eval('function(ns) ns.log("api", "first problem") ns.log("comm", "second problem") end')(env.ns)
        env.mock.Slash("/camp debug")
        chat = "\n".join(env.chat())
        self.assertIn("Debug log: 2 records", chat)
        self.assertIn("[api] first problem", chat)
        self.assertIn("[comm] second problem", chat)

        env.mock.Slash("/camp debug clear")
        self.assertEqual(env.ns.Log.Count(env.ns.Log), 0)
        env.assert_no_errors()

    def test_log_is_persisted_in_saved_variables(self):
        env = started()
        env.lua.eval('function(ns) ns.log("api", "kept") end')(env.ns)
        stored = env.g.CampkeeperDB["global"]["debugLog"]
        self.assertEqual(stored["count"], 1)
        self.assertEqual(stored[1]["msg"], "kept")

    def test_options_are_registered(self):
        env = started()
        opts = env.lua.eval('LibStub("AceConfigRegistry-3.0"):GetOptionsTable("Campkeeper", "dialog", "x-1")')
        self.assertIsNotNone(opts)
        self.assertEqual(env.lua.eval('LibStub("AceAddon-3.0"):GetAddon("Campkeeper").db.profile.panel.enabled'), True)
        self.assertTrue(any(c.registered for c in env.mock.settings.values()), "no Settings category")

    def test_config_command_opens_dialog(self):
        env = started()
        env.mock.Slash("/camp config")
        env.assert_no_errors()
        self.assertIsNotNone(env.lua.eval('LibStub("AceConfigDialog-3.0").OpenFrames["Campkeeper"]'))


if __name__ == "__main__":
    unittest.main()
