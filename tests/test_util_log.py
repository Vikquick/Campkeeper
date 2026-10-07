import unittest

from wowenv import WowEnv

CORE = ["Core/Log.lua", "Core/Util.lua"]


def env_with_core():
    env = WowEnv()
    env.load_files("Campkeeper", CORE)
    return env


class UtilTest(unittest.TestCase):
    def setUp(self):
        self.env = env_with_core()
        self.lua = self.env.lua
        self.ns = self.env.ns

    def log_messages(self):
        return [e.msg for e in self.ns.Log.Entries(self.ns.Log).values()]

    def test_api_error_is_contained_and_logged(self):
        result = self.lua.eval("""(function(ns)
          local value = ns.Util.safeCall("Broken", function() error("boom") end)
          return value == nil and "continued"
        end)""")(self.ns)
        self.assertEqual(result, "continued")
        msgs = self.log_messages()
        self.assertEqual(len(msgs), 1)
        self.assertIn("Broken", msgs[0])
        self.assertIn("boom", msgs[0])
        self.env.assert_no_errors()

    def test_secret_value_is_dropped_and_logged(self):
        result = self.lua.eval("""(function(ns)
          local secret = {}
          Mock.secrets = { [secret] = true }
          local a, b = ns.Util.safeCall("Aura", function() return 1, secret end)
          return a == nil and b == nil
        end)""")(self.ns)
        self.assertTrue(result)
        self.assertIn("secret", self.log_messages()[0])

    def test_passes_all_return_values(self):
        n = self.lua.eval("""(function(ns)
          return select("#", ns.Util.safeCall("Many", function() return 1, 2, 3, 4, 5, 6, 7 end))
        end)""")(self.ns)
        self.assertEqual(n, 7)

    def test_missing_function_is_logged(self):
        self.lua.eval('function(ns) ns.Util.safeCall("C_Nope.Fn", nil) end')(self.ns)
        self.assertIn("C_Nope.Fn", self.log_messages()[0])

    def test_normalize_strips_codes_and_lowercases_cyrillic(self):
        norm = self.lua.eval("function(ns, s) return ns.Util.normalize(s) end")
        self.assertEqual(norm(self.ns, "  |cff00ff00Магнетит|r "), "магнетит")
        self.assertEqual(norm(self.ns, "ЁЛКА Ящик"), "елка ящик")
        self.assertEqual(norm(self.ns, "|T123:0|tMana Well"), "mana well")


class LogTest(unittest.TestCase):
    def setUp(self):
        self.env = env_with_core()
        self.ns = self.env.ns
        self.log = self.ns.Log

    def entries(self):
        return [e.msg for e in self.log.Entries(self.log).values()]

    def test_ring_buffer_evicts_oldest(self):
        for i in range(1, 202):
            self.log.Add(self.log, "test", f"m{i}")
        msgs = self.entries()
        self.assertEqual(len(msgs), 200)
        self.assertEqual(msgs[0], "m2")
        self.assertEqual(msgs[-1], "m201")

    def test_attach_keeps_pending_records(self):
        self.log.Add(self.log, "early", "before db")
        storage = self.env.lua.table()
        self.log.Attach(self.log, storage)
        self.log.Add(self.log, "late", "after db")
        self.assertEqual(self.entries(), ["before db", "after db"])
        self.assertEqual(storage["count"], 2)

    def test_format_errors_do_not_escape(self):
        self.env.lua.eval('function(ns) ns.log("x", "%d apples", "many") end')(self.ns)
        self.assertEqual(self.entries(), ["%d apples"])


if __name__ == "__main__":
    unittest.main()
