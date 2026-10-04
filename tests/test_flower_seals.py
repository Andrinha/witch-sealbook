"""The flower seal (Flowers of Light, Flowers of Sand): one drawing round whatever sigil stands in its middle.

python tests/test_flower_seals.py
"""
import math
import random
import sys
import unittest
from pathlib import Path

import wiki_spells as Wiki
from harness import world_runtime

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import grimoire as G  # noqa: E402
import make_grimoire as MG  # noqa: E402


def drawn(lua, *middle):
    """the flower seal with 'middle' inside its pentagon, as a clean page"""
    return [MG.circle(MG.CENTER, MG.CENTER, MG.RADIUS)] + MG.render_symbols(
        lua, G.flower_seal(*middle), MG.CENTER, MG.CENTER, MG.RADIUS)


def glance(lua, strokes):
    """what the book takes a finished drawing for, as it does in the game: (named, element, summary, data) or None"""
    spell = lua.eval("seal_named_spell")(Wiki.lua_strokes(lua, strokes))
    return spell and (spell["named"], spell["element"], spell["summary"], spell["data"])


def by_players(lua, strokes, rng, count=6):
    """the drawing copied by hand, half of the copies the way a player draws with the mouse"""
    return [glance(lua, Wiki.as_player(strokes, rng, False) if i % 2 else Wiki.by_hand(strokes, rng)) for i in range(count)]


class FlowerPages(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = Wiki.load()
        cls.light = cls.lua.eval("GRIMOIRE_BY_KEY")["flowers_of_light"]
        cls.sand = cls.lua.eval("GRIMOIRE_BY_KEY")["flowers_of_sand"]

    def test_flowers_of_sand_is_the_flowers_of_light_seal_round_the_sand_sigil(self):
        light, sand = Wiki.page(self.lua, self.light), Wiki.page(self.lua, self.sand)
        middle = lambda page: [s for s in page[1:] if max(math.hypot(x - 90, y - 90) for x, y in s) < 0.3 * 70]
        body = lambda page: [s for s in page if s not in middle(page)]
        # The same ring, pentagon, rays and curls, stroke for stroke.
        self.assertEqual(body(light), body(sand))
        self.assertEqual(len(body(sand)), 1 + 1 + 5 + 10)
        # In the middle the light crest on one, the book's own sand sigil on the other, inside the pentagon.
        self.assertEqual(len(middle(light)), 7)
        sigil = self.lua.eval("TEMPLATES_SIGILS")["sand"][1]
        self.assertEqual(len(middle(sand)), len(list(sigil.values())))
        self.assertEqual(sorted(middle(sand)), sorted(Wiki.page(self.lua, self.sand)[-len(middle(sand)):]))
        for entry, key in ((self.light, "light"), (self.sand, "sand")):
            self.assertEqual((entry["middle"], entry["middle_reach"], entry["manifest"], entry["symbols"]),
                             (key, G.FLOWER_MIDDLE, "bloom", ""))
            self.assertIn(f"element={key};", entry["spell"])
            self.assertIn(f"manifest=bloom;named={entry['key']}", entry["spell"])
            self.assertNotIn(";b=", entry["spell"])
        # No purification signs any more: the unknown curls are known only as a whole.
        self.assertEqual(self.sand["recipe"], "sigil:sand=1")

    def test_each_page_is_itself_at_a_glance_and_in_a_players_hand(self):
        rng = random.Random(24)
        for entry in (self.light, self.sand):
            with self.subTest(key=entry["key"]):
                page = Wiki.page(self.lua, entry)
                self.assertEqual(glance(self.lua, page)[:3], (entry["key"], entry["middle"], entry["name"]))
                got = by_players(self.lua, page, rng, 8)
                self.assertGreaterEqual(sum(g is not None and g[0] == entry["key"] for g in got), 7)
                # Never the other page, and never another element.
                self.assertTrue(all(g is None or g[0] == entry["key"] for g in got))
        # The other pentagon page stays itself.
        rose = self.lua.eval("GRIMOIRE_BY_KEY")["water_rose"]
        self.assertEqual(glance(self.lua, Wiki.page(self.lua, rose))[0], "water_rose")

    def test_another_sigil_in_the_middle_blooms_in_its_element(self):
        rng = random.Random(7)
        names = {"water": "Water", "fire": "Fire", "wind": "Wind"}
        for sigil, name in names.items():
            with self.subTest(sigil=sigil):
                page = drawn(self.lua, G.sig(sigil, 0, 0, 0.38))
                got = [glance(self.lua, page)] + by_players(self.lua, page, rng, 6)
                good = [g for g in got if g is not None]
                self.assertGreaterEqual(len(good), 6)
                for named, element, summary, data in good:
                    # None of the wiki's seals: the flowers' spell in that element.
                    self.assertEqual((named, element, summary), (None, sigil, name + ", flowers"))
                    self.assertTrue(data.startswith(f"element={sigil};form=burst;"))
                    self.assertIn(";manifest=bloom", data)
                    self.assertNotIn("named=", data)

    def test_a_sigil_of_the_same_element_is_the_page_and_an_empty_middle_is_the_wikis_seal(self):
        # The book's own light sigil for the redraw's crest: Flowers of Light all the same.
        self.assertEqual(glance(self.lua, drawn(self.lua, G.sig("light", 0, 0, 0.38)))[0], "flowers_of_light")
        # Purification is a water sigil: water flowers.
        self.assertEqual(glance(self.lua, drawn(self.lua, G.sig("purification", 0, 0, 0.38)))[1:3], ("water", "Water, flowers"))
        # Nothing in the middle, or a sigil that is no element (Aeriforms makes a bubble of its own): the wiki's seal.
        self.assertEqual(glance(self.lua, drawn(self.lua))[0], "flowers_of_light")
        self.assertEqual(glance(self.lua, drawn(self.lua, G.sig("aeriforms", 0, 0, 0.38)))[0], "flowers_of_light")

    def test_read_sign_by_sign_the_pages_are_named_the_same(self):
        for entry in (self.light, self.sand):
            self.assertEqual(Wiki.read(self.lua, Wiki.page(self.lua, entry))[0], entry["key"])
        # With a sigil no page has, the sign by sign reading names no seal of the wiki's.
        self.assertIsNone(Wiki.read(self.lua, drawn(self.lua, G.sig("water", 0, 0, 0.38)))[0])


class FlowerCasts(unittest.TestCase):
    def cast(self, lua, data):
        lua.globals().TEST_DATA = data
        return lua.execute(
            "return cast_spell(PLAYER, parse_spell_data(TEST_DATA), 0, -40, 1, 0, 120, -30, W.frame, nil)[1]")

    def test_flowers_bloom_in_the_sigils_element(self):
        lua = world_runtime()
        lua.execute("GROUND = 10")
        reader = Wiki.load()
        water = glance(reader, drawn(reader, G.sig("water", 0, 0, 0.38)))[3]
        sand = glance(reader, Wiki.page(reader, reader.eval("GRIMOIRE_BY_KEY")["flowers_of_sand"]))[3]
        light = glance(reader, Wiki.page(reader, reader.eval("GRIMOIRE_BY_KEY")["flowers_of_light"]))[3]
        made = {}
        for name, data in (("water", water), ("sand", sand), ("light", light)):
            effect = self.cast(lua, data)
            p = lua.eval("effect_params")(effect)
            self.assertEqual((p["kind"], p["mode"], p["element"]), ("light", "bloom", name))
            made[name] = p["frames"]
        lua.execute("simulate(3)")
        # Sand flowers are solid, to stand on; a water rose lasts a moment; flowers of light shine long.
        solid = [f for f in lua.eval("W.made").values() if f.endswith("solid/sand_flower.xml")]
        self.assertEqual(len(solid), 4)
        self.assertLess(made["water"], 3 * 60)
        self.assertGreater(made["light"], 40 * 60)
        self.assertFalse(list(lua.eval("W.errors").values()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
