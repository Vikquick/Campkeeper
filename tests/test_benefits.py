import unittest

from wowenv import WowEnv

CORE = ["Core/Log.lua", "Core/Util.lua", "Data/Catalog.lua", "Core/Catalog.lua", "Core/BenefitsParser.lua"]
HEADER = "Бонусы лагеря"
DESCRIPTION = "Получены следующие бонусы лагеря:\r\n\r\nМагнетит: сила атаки ближнего боя повышена на 20.\r\n\r\n"
REMAINING = "Осталось 60 |4минута:минуты:минут;"

RU_NAMES = {279960: "Магнетит", 279944: "Круг для заточки", 279988: "Наковальня", 279955: "Горн мастера"}
EN_NAMES = {279960: "Lodestone", 279944: "Sharpening Wheel", 279988: "Anvil"}


def set_tooltip(env, instance, *lines):
    env.lua.eval("function(id, t) Mock.tooltips[id] = t end")(instance, env.lua.table_from(list(lines)))


def parser_env(locale="ruRU", names=RU_NAMES):
    env = WowEnv(locale=locale)
    for item, name in names.items():
        env.lua.execute(f'Mock.items[{item}] = {{ name = "{name}" }}')
    env.load_core(CORE)
    return env


class ParseLinesTest(unittest.TestCase):
    def parse(self, env, *lines):
        p = env.ns.BenefitsParser
        return p.ParseLines(p, env.lua.table_from(list(lines)))

    def objects(self, result):
        return [(o.key, o.tier, o.effect) for o in result.objects.values()]

    def log(self, env):
        return [e.msg for e in env.ns.Log.Entries(env.ns.Log).values()]

    def test_real_ru_tooltip(self):
        env = parser_env()
        r = self.parse(env, HEADER, DESCRIPTION, REMAINING)
        self.assertEqual(self.objects(r), [("lodestone", 1, "сила атаки ближнего боя повышена на 20.")])
        self.assertEqual(len(r.unknown), 0)
        self.assertEqual(self.log(env), [], "header and remaining-time lines must not be reported")

    def test_en_tooltip(self):
        env = parser_env("enUS", EN_NAMES)
        r = self.parse(env, "Camp Benefits",
                       "You have gained the following camp benefits:\r\n\r\nLodestone: Melee attack power increased by 20.\r\n\r\n"
                       "Sharpening Wheel: Strength increased by 6.", "60 min remaining")
        self.assertEqual([k for k, _, _ in self.objects(r)], ["lodestone", "sharpening_wheel"])

    def test_case_and_colour_codes_are_ignored(self):
        env = parser_env()
        r = self.parse(env, HEADER, "|cffffd100МАГНЕТИТ:|r +20 к силе атаки")
        self.assertEqual(self.objects(r), [("lodestone", 1, "+20 к силе атаки")])

    def test_unknown_line_is_kept_and_logged(self):
        env = parser_env()
        r = self.parse(env, HEADER, "Получены следующие бонусы лагеря:\r\nТаинственный тотем: +5 к удаче")
        self.assertEqual(self.objects(r), [])
        unknown = list(r.unknown.values())
        self.assertEqual((unknown[0].name, unknown[0].effect), ("Таинственный тотем", "+5 к удаче"))
        self.assertTrue(any("Таинственный тотем" in m for m in self.log(env)))

    def test_higher_tier_name_and_replaced_t1_name(self):
        env = parser_env()
        r = self.parse(env, HEADER, "Наковальня: сила повышена на 6.\r\nКруг для заточки: сила повышена на 6.")
        self.assertEqual([(k, t) for k, t, _ in self.objects(r)], [("anvil", 2), ("sharpening_wheel", 1)])


class RetryTest(unittest.TestCase):
    def run_parse(self, env, instance):
        results = []
        p = env.ns.BenefitsParser
        env.lua.eval("function(p, id, sink) p:Parse(id, function(c) sink.add(c) end) end")(
            p, instance, env.lua.table_from({"add": lambda c: results.append(c)}))
        return results

    def test_retries_until_description_appears(self):
        env = parser_env()
        set_tooltip(env, 5, HEADER, REMAINING)
        results = self.run_parse(env, 5)
        self.assertEqual(results, [])
        env.advance(1)
        self.assertEqual(results, [])
        set_tooltip(env, 5, HEADER, DESCRIPTION)
        env.advance(1)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0].objects[1].key, "lodestone")

    def test_gives_up_after_five_attempts(self):
        env = parser_env()
        results = self.run_parse(env, 99)  # no tooltip at all
        env.advance(10)
        self.assertEqual(results, [None])
        msgs = [e.msg for e in env.ns.Log.Entries(env.ns.Log).values()]
        self.assertTrue(any("after 5 attempts" in m for m in msgs))


if __name__ == "__main__":
    unittest.main()
