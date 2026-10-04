"""Structural sigil checks and acceptance of small or ambiguous modifiers."""
import itertools
import json
import math
from pathlib import Path
import random
import sys
import unittest

import run_tests as fixtures


class FlickerShapeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = fixtures.load_mod()
        source = (Path(fixtures.MOD) / "files/seal.lua").read_text(encoding="utf-8")
        cls.lua.execute(source + "\nfunction test_flicker_shape(strokes) return flicker_shape(strokes, bbox(strokes)) end")
        cls.match = cls.lua.globals().test_flicker_shape
        cls.template = fixtures.templates(cls.lua)[("sigil", "flicker")]

    def setUp(self):
        self.random_state = random.getstate()

    def tearDown(self):
        random.setstate(self.random_state)

    def matches(self, strokes):
        return self.match(fixtures.lua_strokes(self.lua, strokes))

    def test_hand_drawn_stars_at_different_sizes_and_rotations(self):
        random.seed(100)
        for size in (15, 30, 60):
            for _ in range(40):
                star = fixtures.place(fixtures.hand(self.template), 90, 90, size, angle=random.uniform(-math.pi, math.pi))
                self.assertTrue(self.matches(star), f"star size {size}")

    def test_split_stars_in_any_stroke_order_and_direction(self):
        random.seed(71)
        stroke = fixtures.place(fixtures.hand(self.template), 90, 90, 50)[0]
        for count in (2, 3):
            cuts = [round((len(stroke) - 1) * i / count) for i in range(count + 1)]
            parts = [stroke[cuts[i]:cuts[i + 1] + 1] for i in range(count)]
            for order in itertools.permutations(parts):
                for flips in itertools.product((False, True), repeat=count):
                    self.assertTrue(self.matches([list(reversed(part)) if flip else part for part, flip in zip(order, flips)]))

    def test_small_gaps_at_pen_lifts_are_allowed(self):
        random.seed(72)
        stroke = fixtures.place(fixtures.hand(self.template), 90, 90, 50)[0]
        halfway = len(stroke) // 2
        self.assertTrue(self.matches([stroke[:halfway - 1], stroke[halfway + 1:]]))

    def test_convex_outlines_are_not_stars(self):
        for width, height in ((20, 20), (30, 20)):
            oval = [(90 + width * math.cos(i * math.tau / 100), 90 + height * math.sin(i * math.tau / 100)) for i in range(101)]
            self.assertFalse(self.matches([oval]))
        square = fixtures.densify([(70, 70), (110, 70), (110, 110), (70, 110), (70, 70)])
        self.assertFalse(self.matches([square]))

    def test_open_and_disconnected_outlines_are_not_stars(self):
        random.seed(73)
        stroke = fixtures.place(fixtures.hand(self.template), 90, 90, 50)[0]
        cut = len(stroke) // 2
        self.assertFalse(self.matches([stroke[:len(stroke) * 2 // 3]]))
        displaced = [(x + 35, y) for x, y in stroke[cut:]]
        self.assertFalse(self.matches([stroke[:cut + 1], displaced]))
        examples = json.loads((Path(fixtures.MOD) / "tests/data/player_seals.json").read_text(encoding="utf-8"))
        example = next(e for e in examples if e["name"] == "open central loop mistaken for flicker")
        loop = [tuple(map(float, p.split(","))) for p in example["strokes"][3].split()]
        self.assertFalse(self.matches([loop]))

    def test_degenerate_outlines_are_not_stars(self):
        for strokes in ([], [[]], [[(1, 1)]], [[(1, 1), (1, 1)]]):
            self.assertFalse(self.matches(strokes))

    def test_saved_drawing_rejected_through_tome_after_correction(self):
        examples = json.loads((Path(fixtures.MOD) / "tests/data/player_seals.json").read_text(encoding="utf-8"))
        example = next(e for e in examples if e["name"] == "open central loop mistaken for flicker")
        # draw_on_blank accepts 180-page coordinates; the original drawing was made on a 240-page tome.
        strokes = [[tuple(float(v) * 0.75 for v in p.split(",")) for p in st.split()] for st in example["strokes"]]
        lua = fixtures.load_mod()
        lua.execute((Path(fixtures.MOD) / "files/grimoire.lua").read_text(encoding="utf-8"))
        lua.execute(fixtures.CARRY_ALL)
        G = lua.globals()
        G.held_item = 13
        fixtures.open_book(G)
        fixtures.draw_on_blank(G, strokes)
        self.assertEqual(G.globals["witch_notebook.debug_next"], "2")
        self.assertFalse(G.globals["witch_notebook.tome.active_spell"])
        pages = int(G.globals["witch_notebook.tome.seals"] or 0)
        self.assertGreater(pages, 0)
        for i in range(1, pages + 1):
            self.assertFalse(G.globals[f"witch_notebook.tome.seal_{i}_spell"])


class ModifierAcceptanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = fixtures.load_mod()
        examples = json.loads((Path(fixtures.MOD) / "tests/data/player_seals.json").read_text(encoding="utf-8"))
        example = next(e for e in examples if e["name"] == "lightning with ambiguous peripheral remnants")
        cls.strokes = [[tuple(map(float, p.split(","))) for p in st.split()] for st in example["strokes"]]

    def test_latest_drawing_and_rounding_variants_reject(self):
        for seed in range(30):
            rng = random.Random(seed)
            strokes = [[(x + rng.uniform(-0.049, 0.049), y + rng.uniform(-0.049, 0.049)) for x, y in st]
                       for st in self.strokes]
            result, spell = fixtures.run(self.lua, strokes)
            self.assertIsNone(spell, f"rounding seed {seed}: {result}")

    def test_ambiguous_modifiers_reject_after_tiny_remnants_are_removed(self):
        strokes = [st for st in self.strokes if max(max(x for x, y in st) - min(x for x, y in st),
                                                  max(y for x, y in st) - min(y for x, y in st)) >= 4]
        result, spell = fixtures.run(self.lua, strokes)
        self.assertIsNone(spell, result)

    def test_latest_lightning_without_modifiers_is_valid(self):
        # The last drawing's ring consists of strokes 2, 3, 17; stroke 18 is the central lightning.
        result, spell = fixtures.run(self.lua, [self.strokes[i - 1] for i in (2, 3, 17, 18)])
        self.assertEqual(result, "thunder:burst")
        self.assertEqual(len(spell["behaviors"]), 0)

    def test_latest_drawing_rejected_through_tome(self):
        lua = fixtures.load_mod()
        lua.execute((Path(fixtures.MOD) / "files/grimoire.lua").read_text(encoding="utf-8"))
        lua.execute(fixtures.CARRY_ALL)
        G = lua.globals()
        G.held_item = 13
        fixtures.open_book(G)
        fixtures.draw_on_blank(G, [[(x * 0.75, y * 0.75) for x, y in st] for st in self.strokes])
        # Both the ring closing and the subsequent lightning stroke trigger recognition.
        self.assertGreaterEqual(int(G.globals["witch_notebook.debug_next"] or 0), 2)
        self.assertFalse(G.globals["witch_notebook.tome.active_spell"])
        for i in range(1, int(G.globals["witch_notebook.tome.seals"] or 0) + 1):
            self.assertFalse(G.globals[f"witch_notebook.tome.seal_{i}_spell"])

    def test_modifier_size_and_ambiguity_are_independent_gates(self):
        for size, score, margin, expected in ((0.03, 0.9, 0.1, False), (0.25, 0.55, 0.01, False),
                                              (0.25, 0.55, 0.1, True), (0.25, 0.8, 0.01, True)):
            tree = fixtures.seal_tree(self.lua, ["fire"], [("crosshair", False)])
            sign = tree["symbols"][2]
            sign["size"], sign["score"], sign["margin"] = size, score, margin
            result = self.lua.globals().compile_spell(tree)
            spell = result[0] if isinstance(result, tuple) else result
            self.assertEqual(spell is not None, expected, (size, score, margin))


def run_checks():
    return unittest.TextTestRunner(stream=sys.stdout, verbosity=1).run(
        unittest.TestSuite(unittest.defaultTestLoader.loadTestsFromTestCase(cls)
                           for cls in (FlickerShapeTests, ModifierAcceptanceTests))
    ).wasSuccessful()


if __name__ == "__main__":
    raise SystemExit(0 if run_checks() else 1)
