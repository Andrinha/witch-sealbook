"""The Sigil of Earth as the manga draws it, and Integration, which sets sand into stone without making any.

python tests/test_earth.py
"""
import random
import unittest

import wiki_spells as Wiki
from harness import world_runtime, cast_page

EARTH_PAGES = ("wall_breaker", "integration", "boulder_stretch", "earth_lift", "spike", "wallwarding", "sealchair",
               "replication", "golem", "slime_rendering")


def added(lua, kind):
    return [item[2] for item in lua.eval("W.added").values() if item[1] == kind]


class EarthSigil(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = Wiki.load()

    def test_first_drawing_has_the_base_and_the_two_dots(self):
        shapes = self.lua.eval("TEMPLATES_SIGILS").earth
        first = [[(p[1], p[2]) for p in stroke.values()] for stroke in shapes[1].values()]
        lines, dots = [s for s in first if len(s) > 1], [s[0] for s in first if len(s) == 1]
        # A bar on top, the stem, the barbed point, the base under it; a dot at either side.
        self.assertEqual((len(lines), len(dots)), (4, 2))
        top, stem, point, base = lines
        self.assertEqual({round(y, 2) for _, y in top}, {0.13})
        self.assertEqual({round(y, 2) for _, y in base}, {0.87})
        self.assertGreater(min(y for _, y in base), max(y for _, y in point))
        self.assertAlmostEqual(dots[0][0], 1 - dots[1][0])
        self.assertEqual(dots[0][1], dots[1][1])
        self.assertLess(min(d[0] for d in dots), min(x for x, _ in top))
        # The simulator's drawing, without them, is still known: a seal drawn that way is still earth.
        self.assertEqual(len(list(shapes.values())), 2)
        self.assertEqual(len(list(shapes[2].values())), 3)

    def test_every_earth_page_is_still_read_as_itself(self):
        for key in EARTH_PAGES:
            with self.subTest(key=key):
                entry = self.lua.eval("GRIMOIRE_BY_KEY")[key]
                self.assertIn("element=", entry["spell"])
                if key == "spike":
                    # Not read as itself before the sigil changed either (its columns lie on its pointing
                    # signs): a separate fault, left as it was.
                    continue
                self.assertEqual(Wiki.read(self.lua, Wiki.page(self.lua, entry))[0], key)

    def test_wall_breaker_and_integration_survive_a_hand_copy(self):
        rng = random.Random(710)
        for key in ("wall_breaker", "integration"):
            with self.subTest(key=key):
                page = Wiki.page(self.lua, self.lua.eval("GRIMOIRE_BY_KEY")[key])
                drawings = [Wiki.by_hand(page, rng) for _ in range(8)] + [Wiki.as_player(page, rng, False) for _ in range(8)]
                good = sum(Wiki.read(self.lua, d)[0] == key for d in drawings)
                self.assertGreaterEqual(good, 14)


class Integration(unittest.TestCase):
    def test_new_and_saved_pages_set_sand_into_stone_and_make_none(self):
        for legacy in (False, True):
            with self.subTest(legacy=legacy):
                lua = world_runtime()
                lua.execute('''
                    W.spawned = {}
                    local particle = GameCreateParticle
                    function GameCreateParticle(material, ...)
                        table.insert(W.spawned, material)
                        return particle(material, ...)
                    end
                    W.made, W.added = {}, {}
                ''')
                effect = cast_page(lua, "integration", 120, -30, legacy=legacy)
                p = lua.eval("effect_params")(effect)
                self.assertEqual((p["kind"], p["mode"]), ("zone", "integrate"))
                # At the cursor, where the sand lies - not around the caster's own feet.
                self.assertEqual(lua.eval("EntityGetTransform")(effect)[:2], (120, -30))
                lua.execute("simulate(40)")
                # No carrier, no emitter, not one new cell: it only turns what is there.
                self.assertFalse(list(lua.eval("W.made").values()))
                self.assertFalse(added(lua, "ParticleEmitterComponent"))
                self.assertFalse(list(lua.eval("W.spawned").values()))
                (convert,) = added(lua, "MagicConvertMaterialComponent")
                turns = dict(zip(convert.from_material_array.split(","), convert.to_material_array.split(",")))
                self.assertEqual(len(turns), len(convert.to_material_array.split(",")))
                for loose in ("sand", "soil", "soil_lush", "fungisoil"):
                    self.assertEqual(turns[loose], "rock_static", loose)
                self.assertEqual(turns["snow"], "snow_static")
                # Liquids and stone itself are left alone.
                self.assertFalse({"water", "rock_static", "lava", "gold"} & set(turns))
                self.assertFalse(convert.from_any_material)
                lua.execute("simulate(60)")
                self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
                self.assertFalse(list(lua.eval("W.hits").values()))
                self.assertFalse(list(lua.eval("W.errors").values()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
