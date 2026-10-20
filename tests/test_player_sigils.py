"""Sigils drawn as players draw them read right (2026-10-21; Workshop players: light read as fire, Flickering Light
"imprecise or too faint most of the time"). As with the signs (player_signs.py): the wiki's picture, in any stroke order,
the pen lifted at any corner, with a hand's proportions, in the middle of a ring with two columns.

- fire: the wiki's (a triangle, its stem, two horns) and a plain triangle with its stem
- light: the wiki's and the anime's - a small diamond in the middle of a square, rays out from its sides - and the
  simulator's diamond filling the square (the book's legend)
- Flickering Light: the wiki's star outline, and the hexagram as two triangles

Measured 2026-10-21 with 60 seals each (before -> after the wiki's light template, the star kept sharp and read by its
form, two triangles): light wiki 4 -> 47, legend 17 -> 24, star 8 -> 56, triangles 0 -> 58; fire 60 and 51 unchanged.

Run with python tests/test_player_sigils.py.
"""
import math
import os
import random
import sys
import unittest
import zlib
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import player_signs as ps  # noqa: E402
import run_tests as fx  # noqa: E402
from harness import load_reader  # noqa: E402
from player_signs import P  # noqa: E402

# the wiki's Flickering Light (Sigil_of_Flickering_light_redraw.png, 500 px): its twelve corners from the top
STAR = [(x / 500, y / 500) for x, y in [(247, 72), (288, 152), (394, 152), (341, 256), (389, 349), (292, 349), (253, 425),
                                        (213, 349), (106, 349), (163, 243), (112, 152), (205, 152), (247, 72)]]
SIGILS = {
    "fire": {
        "wiki": [P((0.5, 0.1), (0.9, 0.72), (0.1, 0.72), (0.5, 0.1)), P((0.5, 0.72), (0.5, 0.95)), P((0.25, 0.46), (0.07, 0.28)),
                 P((0.75, 0.46), (0.93, 0.28))],
        "plain": [P((0.5, 0.1), (0.9, 0.72), (0.1, 0.72), (0.5, 0.1)), P((0.5, 0.72), (0.5, 0.95))],
    },
    "light": {
        "wiki": [P((0.2, 0.2), (0.8, 0.2), (0.8, 0.8), (0.2, 0.8), (0.2, 0.2)), P((0.5, 0.38), (0.62, 0.5), (0.5, 0.62), (0.38, 0.5), (0.5, 0.38)),
                 P((0.5, 0.2), (0.5, 0.02)), P((0.5, 0.8), (0.5, 0.98)), P((0.2, 0.5), (0.02, 0.5)), P((0.8, 0.5), (0.98, 0.5))],
        "legend": [P((0.2, 0.2), (0.8, 0.2), (0.8, 0.8), (0.2, 0.8), (0.2, 0.2)), P((0.5, 0.2), (0.8, 0.5), (0.5, 0.8), (0.2, 0.5), (0.5, 0.2)),
                   P((0.5, 0.2), (0.5, 0.02)), P((0.5, 0.8), (0.5, 0.98)), P((0.2, 0.5), (0.02, 0.5)), P((0.8, 0.5), (0.98, 0.5))],
    },
    "flicker": {
        "wiki": [P(*STAR)],
        "triangles": [P(STAR[0], STAR[4], STAR[8], STAR[0]), P(STAR[10], STAR[2], STAR[6], STAR[10])],
    },
}
SEALS = 20
FLOOR = {("fire", "wiki"): 19, ("fire", "plain"): 15, ("light", "wiki"): 14, ("light", "legend"): 5,
         ("flicker", "wiki"): 18, ("flicker", "triangles"): 18}


def player_sigil_seal(lua, key, variant, rng):
    """a ring round the sigil drawn by hand, a column on either side"""
    random.seed(rng.random())  # run_tests' hand and place draw from random
    t = fx.templates(lua)
    ring, (cx, cy, r) = fx.ring()
    lines, nodes = ps.strokes_of(SIGILS[key][variant], rng)
    strokes = [ring] + fx.place(ps.hand_shape(lines, nodes, rng), cx, cy, r * rng.uniform(0.4, 0.55), tilt=0.1)
    for deg in (0, 180):
        a = math.radians(deg)
        strokes += fx.place(fx.hand(t[("sign", "column")]), cx + 0.7 * r * math.cos(a), cy + 0.7 * r * math.sin(a), r * 0.23, a - math.pi / 2)
    return strokes


def trial(lua, key, variant, n=SEALS):
    rng = random.Random(zlib.crc32((key + variant).encode()) % 1000)
    got = Counter()
    for _ in range(n):
        res = lua.eval("read_spell")(fx.lua_strokes(lua, player_sigil_seal(lua, key, variant, rng)))
        spell, err = (res[0], res[1]) if isinstance(res, tuple) else (res, None)
        got[spell.element if spell else err] += 1
    return got


class PlayerSigils(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = load_reader()

    def test_sigils_drawn_as_players_draw_them(self):
        low = []
        for (key, variant), floor in FLOOR.items():
            got = trial(self.lua, key, variant)
            if got[key] < floor:
                low.append(f"{key} {variant}: {got[key]}/{SEALS} (floor {floor}) {dict(got.most_common(3))}")
        self.assertEqual([], low)


if __name__ == "__main__":
    unittest.main()
