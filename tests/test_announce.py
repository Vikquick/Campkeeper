import json
import unittest

from wowenv import ROOT, WowEnv

CORE = ["Core/Log.lua", "Core/Util.lua", "Data/Catalog.lua", "Data/Names.lua", "Core/Catalog.lua",
        "Core/Announce.lua"]
RU_NAMES = {279978: "Лагерная палатка", 279967: "Аквариум", 279960: "Магнетит", 279944: "Круг для заточки",
            279956: "Колодец маны", 279976: "Зачарованная лютня", 279950: "Реагентобот",
            279968: "Набор первой помощи", 279962: "Ароматная свеча", 279979: "Лагерный стул"}
FIRES = {1307227: "Обычный костер", 1307252: "Костер подмастерья", 1307237: "Костер умельца"}
LINK = "|cffffff00|Hworldmap:1413:5001:2804|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Map Pin Location]|h|r"
NOW = 1760000000
DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"


def announce_env(locale="ruRU", names=RU_NAMES, fires=FIRES):
    env = WowEnv(locale=locale)
    for item, name in names.items():
        env.lua.execute(f'Mock.items[{item}] = {{ name = "{name}" }}')
    for spell, name in fires.items():
        env.lua.execute(f'Mock.spells[{spell}] = {{ name = "{name}" }}')
    env.load_core(CORE)
    return env


def camp(env, tier=1, objects=("camp_tent", "fish_bowl"), left=420, **extra):
    r = {"id": "AAAAAAAA-1", "mapID": 1413, "x": 0.50012, "y": 0.28043, "tier": tier,
         "objects": env.lua.table_from({k: True for k in objects})}
    if left is not None:
        r["expiresAt"] = NOW + left
    r.update(extra)
    return env.lua.table_from({k: v for k, v in r.items() if v is not None})


def code(env, *keys):
    """The objects as the tag carries them: a bit mask in catalog order, written in base 36."""
    order = list(env.ns.Catalog.order.values())
    mask = sum(1 << i for i, key in enumerate(order) if key in keys)
    out = ""
    while mask:
        mask, d = divmod(mask, 36)
        out = DIGITS[d] + out
    return out or "0"


class BuildTest(unittest.TestCase):
    def build(self, env, record, language=None):
        return env.ns.Announce.Build(env.ns.Announce, record, NOW, language)

    def test_full_message(self):
        env = announce_env()  # objects go in catalog order
        text = self.build(env, camp(env))
        self.assertEqual(text, "Обычный костер, 2/3 - Аквариум, Лагерная палатка. Ещё 7 мин. " + LINK
                         + " (Campkeeper T1 7m #%s)" % code(env, "camp_tent", "fish_bowl"))

    def test_no_objects_and_unknown_time(self):
        env = announce_env()
        text = self.build(env, camp(env, tier=2, objects=(), left=None))
        self.assertEqual(text, "Костер подмастерья, 0/5. " + LINK + " (Campkeeper T2)")

    def test_unknown_tier(self):
        env = announce_env()
        text = self.build(env, camp(env, tier=None, objects=("lodestone",), left=None))
        self.assertEqual(text, "Лагерь здесь - Магнетит. " + LINK + " (Campkeeper #%s)" % code(env, "lodestone"))

    def test_many_objects_fit_into_255_bytes_and_the_code_stays_complete(self):
        env = announce_env()
        objects = ("camp_tent", "fish_bowl", "lodestone", "sharpening_wheel", "mana_well", "enchanted_lute",
                   "reagent_bot", "first_aid_kit", "incense_candle", "camp_chair")
        text = self.build(env, camp(env, tier=3, objects=objects))
        self.assertLessEqual(len(text.encode("utf-8")), 255)
        self.assertIn("10/10", text)
        self.assertRegex(text, r", \+\d+\. Ещё 7 мин\. ")
        self.assertTrue(text.endswith(LINK + " (Campkeeper T3 7m #%s)" % code(env, *objects)))

    def test_other_locale_falls_back_to_english(self):
        env = announce_env(locale="deDE", names={279960: "Magnetstein"}, fires={1307227: "Einfaches Lagerfeuer"})
        text = self.build(env, camp(env, objects=("lodestone",)))
        self.assertEqual(text, "Einfaches Lagerfeuer, 1/3 - Magnetstein. 7 min left. " + LINK
                         + " (Campkeeper T1 7m #%s)" % code(env, "lodestone"))

    def test_link_text_is_the_client_string_as_is(self):
        # the client's MAP_PIN_HYPERLINK already carries the pin icon; a link whose text differs from
        # what the client itself would make is not accepted in chat
        env = announce_env()
        env.lua.execute('MAP_PIN_HYPERLINK = "|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Метка на карте"')
        a = env.ns.Announce
        self.assertEqual(a.Link(a, 1413, 0.5, 0.25),
                         "|cffffff00|Hworldmap:1413:5000:2500|h"
                         "[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Метка на карте]|h|r")

    def test_minutes_round_up_and_never_negative(self):
        env = announce_env()
        self.assertIn("Ещё 1 мин.", self.build(env, camp(env, left=20)))
        self.assertIn("(Campkeeper T1 0m #", self.build(env, camp(env, left=-5)))


class LanguageTest(unittest.TestCase):
    def build(self, env, record, language=None):
        return env.ns.Announce.Build(env.ns.Announce, record, NOW, language)

    def test_english_from_a_russian_client(self):
        env = announce_env()
        text = self.build(env, camp(env), "enUS")
        self.assertEqual(text, "Basic Campfire, 2/3 - Fish Bowl, Camp Tent. 7 min left. " + LINK
                         + " (Campkeeper T1 7m #%s)" % code(env, "camp_tent", "fish_bowl"))

    def test_russian_from_another_client(self):
        env = announce_env(locale="deDE", names={}, fires={})  # the client knows no names at all
        text = self.build(env, camp(env, tier=2, objects=("lodestone",)), "ruRU")
        self.assertEqual(text, "Костер подмастерья, 1/5 - Магнетит. Ещё 7 мин. " + LINK
                         + " (Campkeeper T2 7m #%s)" % code(env, "lodestone"))

    def test_camp_without_a_known_fire_in_the_chosen_language(self):
        env = announce_env()
        self.assertEqual(self.build(env, camp(env, tier=None, objects=(), left=None), "enUS"),
                         "Camp here. " + LINK + " (Campkeeper)")

    def test_client_and_unknown_language_use_the_client_names(self):
        env = announce_env()
        default = self.build(env, camp(env))
        self.assertEqual(self.build(env, camp(env), "client"), default)
        self.assertEqual(self.build(env, camp(env), "xxXX"), default)


class NamesDataTest(unittest.TestCase):
    def setUp(self):
        self.env = announce_env()
        self.names = self.env.ns.NamesData

    def test_every_object_and_fire_has_a_name_in_each_language(self):
        order = sorted(self.env.ns.Catalog.order.values())
        for language in ("enUS", "ruRU"):
            data = self.names[language]
            self.assertEqual(sorted(data.objects.keys()), order, language)
            self.assertEqual(len(list(data.fires.values())), 3, language)
            self.assertTrue(all(isinstance(n, str) and n for n in data.objects.values()), language)

    def test_english_names_match_the_wiki(self):
        wiki = json.loads((ROOT / "tools/wiki_objects.json").read_text(encoding="utf-8"))
        self.assertEqual(dict(self.names.enUS.objects.items()), {k: v["name"] for k, v in wiki["objects"].items()})
        self.assertEqual(list(self.names.enUS.fires.values()), [wiki["fires"][t] for t in ("1", "2", "3")])


class ParseTest(unittest.TestCase):
    def parse(self, env, text):
        return env.ns.Announce.Parse(env.ns.Announce, text)

    def test_round_trip(self):
        env = announce_env()
        a = env.ns.Announce
        p = self.parse(env, a.Build(a, camp(env), NOW))
        self.assertEqual((p.mapID, p.tier, p.minutes, p.campkeeper), (1413, 1, 7, True))
        self.assertAlmostEqual(p.x, 0.5001)
        self.assertAlmostEqual(p.y, 0.2804)
        self.assertEqual(sorted(p.objects.keys()), ["camp_tent", "fish_bowl"])

    def test_every_object_survives_the_code(self):
        env = announce_env()
        a = env.ns.Announce
        everything = tuple(env.ns.Catalog.order.values())
        p = self.parse(env, a.Build(a, camp(env, tier=3, objects=everything), NOW))
        self.assertEqual(sorted(p.objects.keys()), sorted(everything))

    def test_unknown_tier_and_time(self):
        env = announce_env()
        p = self.parse(env, "Лагерь здесь. " + LINK + " (Campkeeper)")
        self.assertEqual((p.tier, p.minutes, p.campkeeper), (None, None, True))
        self.assertEqual(list(p.objects.keys()), [])

    def test_objects_are_understood_in_any_language(self):
        env = announce_env(locale="deDE", names={}, fires={})  # no object name is known to this client
        text = ("Обычный костер, 2/3 - Аквариум, Лагерная палатка. Ещё 7 мин. " + LINK
                + " (Campkeeper T1 7m #%s)" % code(env, "camp_tent", "fish_bowl"))
        p = self.parse(env, text)
        self.assertEqual((p.mapID, p.tier, p.minutes), (1413, 1, 7))
        self.assertEqual(sorted(p.objects.keys()), ["camp_tent", "fish_bowl"])

    def test_tag_without_the_object_code(self):
        env = announce_env()
        p = self.parse(env, "Обычный костер, 1/3 - Магнетит. " + LINK + " (Campkeeper T1 7m)")
        self.assertEqual((p.tier, p.minutes, p.campkeeper), (1, 7, True))
        self.assertEqual(list(p.objects.keys()), [])  # names in the text are not trusted

    def test_garbage_code_gives_no_objects(self):
        env = announce_env()
        p = self.parse(env, "camp " + LINK + " (Campkeeper T1 7m #zzzzzzzzzzzzzzzzzzzz)")
        self.assertEqual((p.tier, list(p.objects.keys())), (1, []))

    def test_plain_message_with_pin(self):
        env = announce_env()
        p = self.parse(env, "костер тут " + LINK)
        self.assertEqual((p.mapID, p.campkeeper, p.tier), (1413, False, None))
        self.assertIsNone(p.objects)

    def test_no_pin(self):
        env = announce_env()
        self.assertIsNone(self.parse(env, "кто-нибудь ставил лагерь? (Campkeeper T1 7m)"))

    def test_looks_like_a_camp(self):
        env = announce_env()
        looks = lambda text: env.ns.Announce.Looks(env.ns.Announce, text)
        for text in ("костер тут", "Костёр у реки", "ЛАГЕРЬ на севере", "campfire here", "Camp at the lake",
                     "Lagerfeuer am See", "feu de camp ici", "hoguera aqui", "campamento"):
            self.assertTrue(looks(text + " " + LINK), text)
        for text in ("тут редкий моб", "rare spawn here", "champion of the light", "need a healer"):
            self.assertFalse(looks(text + " " + LINK), text)


class ThrottleTest(unittest.TestCase):
    def test_same_camp_and_channel_waits_two_minutes(self):
        env = announce_env()
        a = env.ns.Announce
        self.assertEqual(a.CanAnnounce(a, "AAAAAAAA-1", "general", NOW), True)
        a.MarkAnnounced(a, "AAAAAAAA-1", "general", NOW)
        ok, wait = a.CanAnnounce(a, "AAAAAAAA-1", "general", NOW + 30)
        self.assertEqual((ok, wait), (False, 90))
        self.assertEqual(a.CanAnnounce(a, "AAAAAAAA-1", "general", NOW + 120), True)

    def test_other_channel_and_other_camp_are_free(self):
        env = announce_env()
        a = env.ns.Announce
        a.MarkAnnounced(a, "AAAAAAAA-1", "group", NOW)
        self.assertEqual(a.CanAnnounce(a, "AAAAAAAA-1", "guild", NOW), True)
        self.assertEqual(a.CanAnnounce(a, "BBBBBBBB-1", "group", NOW), True)


if __name__ == "__main__":
    unittest.main()
