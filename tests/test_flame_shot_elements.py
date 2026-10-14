"""Flame Shot drawn round another element's sigil is a long shot of that element. A player: "if you replace the fire sigil
with another element it doesn't give you an earth shot or a water shot ... It gives you 'that element, column,
directed'". The seal reads as Flame Shot in that element ("Flame Shot (Water)": the page cast in the element of its
sigil, seal_canon.lua seal_page_takes) and casts a line of the element's shots that stretches out as it flies far
ahead, as Flame Shot's beam of flame does; round the fire sigil it is still Flame Shot.

python tests/test_flame_shot_elements.py
"""
import math
import random
import unittest

import run_tests as fx
from harness import WORLD_FILES, bare_world, load_reader


def flame_shot_copy(lua, sigil, side, seed):
    """Flame Shot drawn by hand from its page (tools/grimoire.py): the sigil low in the ring, the column across it, 'side'
    Regions down either side of the column, all pointing up"""
    random.seed(seed)
    t = fx.templates(lua)
    rstroke, (cx, cy, r) = fx.ring()
    strokes = [rstroke]
    strokes += fx.place(fx.hand(t[("sigil", sigil)]), cx, cy + 0.46 * r, 0.44 * r * random.uniform(0.92, 1.05))
    strokes += fx.place(fx.hand(t[("sign", "column")]), cx, cy - 0.36 * r, 0.82 * r * random.uniform(0.95, 1.03))
    for x in (-0.55, 0.55):
        for i in range(side):
            y = -0.62 + 0.64 * i / max(1, side - 1)
            strokes += fx.place(fx.hand(t[("sign", "regions")]), cx + x * r, cy + y * r, 0.18 * r * random.uniform(0.9, 1.1))
    random.shuffle(strokes)
    return strokes


class Reading(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = load_reader()

    def read(self, sigil, side, seed):
        res = self.lua.eval("read_spell")(fx.lua_strokes(self.lua, flame_shot_copy(self.lua, sigil, side, seed)))
        spell = res[0] if isinstance(res, tuple) else res
        return spell, res

    def test_another_sigil_makes_a_long_shot_of_its_element(self):
        elements = {"water": "water", "earth": "earth", "light": "light", "lightning": "thunder", "crystal": "crystal"}
        missed = []
        for sigil, element in elements.items():
            for side in (4, 5):
                for seed in range(3):
                    spell, res = self.read(sigil, side, seed)
                    if not spell or spell["named"] != "flame_shot" or spell["swapped"] != element:
                        missed.append(f"{sigil} x{side} #{seed}: {dict(spell) if spell else res}")
                        continue
                    self.assertEqual(f"Flame Shot ({self.lua.eval('DICTIONARY_ELEMENTS')[element]['name']})", spell["summary"])
                    data = self.lua.eval("seal_page_data")(spell)
                    self.assertTrue(data.startswith(f"element={element};"), data)
                    self.assertIn("manifest=flame_shot", data)
                    self.assertIn("named=flame_shot", data)
        # (a copy whose column reads as a sigil - Sword, Lightning - is no reading to tell an element by: as a whole it is
        # still Flame Shot)
        self.assertLessEqual(len(missed), 6, "\n".join(missed))

    def test_the_fire_sigil_is_still_flame_shot(self):
        for side in (4, 5):
            for seed in range(3):
                spell, res = self.read("fire", side, seed)
                self.assertTrue(spell, res)
                self.assertEqual("flame_shot", spell["named"], dict(spell))
                self.assertEqual("Flame Shot", spell["summary"])
                self.assertTrue(self.lua.eval("seal_page_data")(spell).startswith("element=fire;"))

    def test_a_plain_seal_of_columns_is_no_long_shot(self):
        """two Regions and a column are not Flame Shot's structure: a shot of the element, as before"""
        random.seed(3)
        strokes = fx.seal(self.lua, ["water"], [("column", 90, False), ("regions", 0, False), ("regions", 180, False)])
        res = self.lua.eval("read_spell")(fx.lua_strokes(self.lua, strokes))
        spell = res[0] if isinstance(res, tuple) else res
        self.assertTrue(spell, res)
        self.assertIsNone(spell["manifest"])


class Casting(unittest.TestCase):
    def setUp(self):
        self.lua = bare_world(WORLD_FILES + ["files/carriers.lua"])
        self.lua.execute("carriers_create(); make_world(); W.frame = 1000")

    def cast(self, data):
        self.lua.globals().TEST_DATA = data
        self.lua.execute('''
            FIRST = W.next_id
            cast_spell( PLAYER, parse_spell_data( TEST_DATA ), 0, GROUND - 8, 1, 0, 200, GROUND - 8, W.frame, nil )
        ''')
        return [e for e in self.lua.eval('''(function()
            local out = {}
            for id = FIRST, W.next_id - 1 do local e = W.entities[id] if e then out[#out + 1] = e end end
            return out end)()''').values()]

    def velocity(self, e):
        v = self.lua.eval(f'EntityGetFirstComponent( {e.id}, "VelocityComponent" )')
        return self.lua.eval(f'ComponentGetValue2( {v}, "mVelocity" )')

    def test_a_water_long_shot_is_a_line_of_water_shots(self):
        made = self.cast("element=water;form=column;force=0.24;range=0.54;precision=0.9;stability=1;directed=true;"
                         "manifest=flame_shot;named=flame_shot;span=0.82;b=")
        shots = [e for e in made if e.file.endswith("carriers/bolt_water.xml")]
        self.assertGreaterEqual(len(shots), 5)
        speeds = [math.hypot(*self.velocity(e)[:2]) for e in shots]
        angles = [math.atan2(self.velocity(e)[1], self.velocity(e)[0]) for e in shots]
        # one way, the lead fastest: the line stretches out as it flies
        self.assertLess(max(abs(a) for a in angles), 0.05)
        self.assertEqual(sorted(speeds, reverse=True), speeds)
        self.assertGreater(speeds[0], 1.25 * speeds[-1])
        self.assertEqual([], list(self.lua.eval("W.errors").values()))

    def test_lightning_and_the_game_s_own_elements(self):
        made = self.cast("element=thunder;form=column;precision=0.9;stability=1;manifest=flame_shot;b=")
        self.assertGreaterEqual(len([e for e in made if e.file.endswith("carriers/bolt_thunder.xml")]), 5)
        made = self.cast("element=vacuum;form=column;precision=0.9;stability=1;manifest=flame_shot;b=")
        self.assertTrue([e for e in made if e.file.endswith("black_hole.xml")])
        self.assertEqual([], list(self.lua.eval("W.errors").values()))

    def test_fire_is_flame_shot_s_beam_of_flame(self):
        made = self.cast("element=fire;form=column;precision=0.9;stability=1;manifest=flame_shot;named=flame_shot;b=")
        self.assertFalse([e for e in made if "carriers/bolt_" in e.file])
        self.assertTrue([e for e in made if e.name == "witch_flame_shot"], [e.name for e in made])


if __name__ == "__main__":
    unittest.main(verbosity=2)
