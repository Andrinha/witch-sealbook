"""Structural sigil checks and acceptance of small or ambiguous modifiers."""
import itertools
import json
import math
from pathlib import Path
import random
import sys
import unittest

import run_tests as fixtures
from harness import load_reader


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


class WaterIsNotWindTests(unittest.TestCase):
    """The water sigil drawn small and rough, or as players draw it - a rounder S, the drops round, big or far out, a drop
    in two strokes: its S alone reads as wind (the wind sigil's simplest template) and its drops as signs beside it, in
    the middle of the seal - where no seal has signs. Read whole, or by its parts (seal.lua water_shape), it is water."""
    @classmethod
    def setUpClass(cls):
        cls.lua = fixtures.load_mod()
        cls.drawings = json.loads((Path(fixtures.MOD) / "tests/data/water_not_wind.json").read_text(encoding="utf-8"))
        source = (Path(fixtures.MOD) / "files/seal.lua").read_text(encoding="utf-8")
        cls.lua.execute(source + "\nfunction test_water_shape(strokes) return water_shape(strokes) end")

    def test_the_drops_beside_the_s_are_water(self):
        self.assertGreater(len(self.drawings), 3)
        for i, d in enumerate(self.drawings):
            result, spell = fixtures.run(self.lua, [[tuple(p) for p in st] for st in d["strokes"]])
            self.assertEqual("water:burst", result, f"drawing {i}: {d['note']}")

    def test_rays_chevrons_and_dots_beside_an_s_are_no_drops(self):
        # the sigils with an S between marks of other kinds keep their own reading
        templates = fixtures.templates(self.lua)
        for key in ("wind", "sand", "aeriforms", "undulation"):
            strokes = fixtures.place(templates[("sigil", key)], 90, 90, 30, tilt=0)
            self.assertIsNone(self.lua.globals().test_water_shape(fixtures.lua_strokes(self.lua, strokes)), key)
        s = fixtures.place([templates[("sigil", "water")][0]], 90, 90, 30, tilt=0)
        for side in (-1, 1):
            s.append(fixtures.densify([(90 + side * 12, 86), (90 + side * 16, 96)]))
        self.assertIsNone(self.lua.globals().test_water_shape(fixtures.lua_strokes(self.lua, s)), "rays")


class ExpansionCornersTests(unittest.TestCase):
    """The wiki draws Expansion as corners one inside the other; drawn so they read as Binding's two arcs, one inside the
    other, unless the sign has that drawing too (tools/import_templates.py). Binding stays Binding."""
    @classmethod
    def setUpClass(cls):
        cls.lua = fixtures.load_mod()
        cls.drawings = json.loads((Path(fixtures.MOD) / "tests/data/expansion_corners.json").read_text(encoding="utf-8"))

    def test_nested_corners_are_expansion(self):
        self.assertGreater(len(self.drawings), 4)
        for i, d in enumerate(self.drawings):
            result, spell = fixtures.run(self.lua, [[tuple(p) for p in st] for st in d["strokes"]])
            self.assertIsNotNone(spell, f"drawing {i}: {d['note']}: {result}")
            self.assertEqual([d["behavior"]], list(spell["behaviors"].keys()), f"drawing {i}: {d['note']}")


class FlameShotCopiesTests(unittest.TestCase):
    """Flame Shot copied by hand: a few Regions more or fewer than the page's ten (hands don't count them), or its column
    read about as well as Dispersion - the seal is still Flame Shot (seal_canon.lua, seal_spell.lua)."""
    @classmethod
    def setUpClass(cls):
        cls.lua = load_reader()
        cls.drawings = json.loads((Path(fixtures.MOD) / "tests/data/flame_shot_copies.json").read_text(encoding="utf-8"))

    def test_copies_are_flame_shot(self):
        self.assertGreater(len(self.drawings), 0)
        for i, d in enumerate(self.drawings):
            strokes = [[tuple(p) for p in st] for st in d["strokes"]]
            res = self.lua.eval("read_spell")(fixtures.lua_strokes(self.lua, strokes))
            spell = res[0] if isinstance(res, tuple) else res
            self.assertIsNotNone(spell, f"drawing {i}: {d['note']}: {res[1] if isinstance(res, tuple) else ''}")
            self.assertEqual(d["named"], spell["named"], f"drawing {i}: {d['note']}")


class TwinSignsTests(unittest.TestCase):
    """A seal's signs are drawn round its ring alike: one drawn worse than its twins, read weakly as another sign or torn,
    is read as they are (seal.lua read_twins); a different sign drawn clearly stays what it is."""
    @classmethod
    def setUpClass(cls):
        cls.lua = fixtures.load_mod()
        cls.drawings = json.loads((Path(fixtures.MOD) / "tests/data/twin_signs.json").read_text(encoding="utf-8"))

    def test_signs_read_like_their_twins_and_odd_ones_stay(self):
        self.assertGreater(len(self.drawings), 4)
        for i, d in enumerate(self.drawings):
            strokes = [[tuple(p) for p in st] for st in d["strokes"]]
            res = self.lua.eval("parse_seal")(fixtures.lua_strokes(self.lua, strokes))
            tree = res[0] if isinstance(res, tuple) else res
            self.assertIsNotNone(tree, f"drawing {i}: {d['note']}")
            got = sorted(s["key"] for s in tree["symbols"].values() if s["kind"] == "sign")
            self.assertEqual(d["signs"], got, f"drawing {i}: {d['note']}")


class TroubleMarksTests(unittest.TestCase):
    """A seal that fails tells which strokes it fails on (seal.trouble), for the book to mark them red."""
    @classmethod
    def setUpClass(cls):
        cls.lua = fixtures.load_mod()

    def read(self, strokes):
        spell, err, tree = self.lua.eval("read_spell")(fixtures.lua_strokes(self.lua, strokes))
        marked = [[(p["x"], p["y"]) for p in st.values()] for st in (tree["trouble"] or {}).values()] if tree else []
        return spell, err, marked

    def test_a_scribble_that_is_no_sign_is_marked(self):
        random.seed(5)
        strokes = fixtures.seal(self.lua, ["fire"], [("column", 90, False), ("column", 270, False)])
        scribble = [(55 + 9 * math.cos(t * 2.3) + t * 0.5, 50 + 7 * math.sin(t * 3.1)) for t in range(40)]
        spell, err, marked = self.read(strokes + [scribble])
        self.assertIsNone(spell)
        self.assertEqual([scribble], marked, err)

    def test_an_ambiguous_sign_of_a_player_is_marked(self):
        examples = json.loads((Path(fixtures.MOD) / "tests/data/player_seals.json").read_text(encoding="utf-8"))
        example = next(e for e in examples if e["name"] == "lightning with ambiguous peripheral remnants")
        strokes = [[tuple(map(float, p.split(","))) for p in st.split()] for st in example["strokes"]]
        spell, err, marked = self.read(strokes)
        self.assertIsNone(spell)
        # only some of its strokes: not the ring, not the lightning in the middle (strokes 2, 3, 17, 18)
        self.assertTrue(0 < len(marked) < len(strokes), err)
        for i in (2, 3, 17, 18):
            self.assertNotIn(strokes[i - 1], marked, err)

    def test_a_seal_that_reads_marks_nothing(self):
        random.seed(7)
        spell, err, marked = self.read(fixtures.seal(self.lua, ["fire"], [("column", 90, False), ("column", 270, False)]))
        self.assertIsNotNone(spell, err)
        self.assertEqual([], marked)


def _arc(cx, cy, r, a0, a1, rng):
    """an arc of the ring as a hand draws it, a point about every unit"""
    n = max(4, int(abs(a1 - a0) * r))
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n) + rng.gauss(0, 0.5), cy + r * math.sin(a0 + (a1 - a0) * i / n) + rng.gauss(0, 0.5))
            for i in range(n + 1)]


def _inside(lua, cx, cy, r):
    """a fire sigil and two columns: a seal of Fire, column"""
    t = fixtures.templates(lua)
    strokes = fixtures.place(fixtures.hand(t[("sigil", "fire")]), cx, cy, r * 0.45)
    for deg in (0, 180):
        a = math.radians(deg)
        strokes += fixtures.place(fixtures.hand(t[("sign", "column")]), cx + 0.7 * r * math.cos(a), cy + 0.7 * r * math.sin(a), r * 0.23,
                                  a - math.pi / 2)
    return strokes


class RingInPiecesTests(unittest.TestCase):
    """A ring drawn in many pieces - redrawn bit by bit, a lopsided part erased and drawn again in short arcs - is closed
    when its pieces go all the way round (seal.lua assemble_ring); a ring left open stays open, and tells where its gap is."""
    @classmethod
    def setUpClass(cls):
        cls.lua = fixtures.load_mod()
        cls.closed = cls.lua.eval("seal_ring_closed")

    def test_a_ring_in_many_pieces_is_closed(self):
        rng = random.Random(31)
        for pieces in (5, 6, 8, 20, 24, 32):
            for overlap in (0.06, -0.03):  # the ends drawn over each other, or a little short of each other
                random.seed(pieces)
                a0 = rng.uniform(0, 2 * math.pi)
                ring = [_arc(90, 90, 68, a0 + 2 * math.pi * j / pieces - overlap, a0 + 2 * math.pi * (j + 1) / pieces + overlap, rng)
                        for j in range(pieces)]
                strokes = ring + _inside(self.lua, 90, 90, 68)
                self.assertTrue(self.closed(fixtures.lua_strokes(self.lua, strokes)), (pieces, overlap))
                self.assertEqual("fire:column", fixtures.run(self.lua, strokes)[0], (pieces, overlap))

    def test_a_gap_patched_in_short_arcs_closes_the_ring(self):
        rng = random.Random(32)
        for patches in (3, 4, 8, 12):
            random.seed(patches)
            a0 = rng.uniform(0, 2 * math.pi)
            strokes = [_arc(90, 90, 68, a0 + 1.2, a0 + 2 * math.pi, rng)]
            strokes += [_arc(90, 90, 68 * rng.uniform(0.97, 1.04), a0 + 1.2 * j / patches - 0.05, a0 + 1.2 * (j + 1) / patches + 0.05, rng)
                        for j in range(patches)]
            strokes += _inside(self.lua, 90, 90, 68)
            self.assertTrue(self.closed(fixtures.lua_strokes(self.lua, strokes)), patches)
            self.assertEqual("fire:column", fixtures.run(self.lua, strokes)[0], patches)

    def test_a_ring_left_open_stays_open_and_tells_where_its_gap_is(self):
        rng = random.Random(33)
        random.seed(33)
        gap = math.radians(40)
        for pieces in (1, 5, 24, 32):
            span = (2 * math.pi - gap) / pieces
            # the gap at the top: from -90 - 20 to -90 + 20 degrees
            a0 = -math.pi / 2 + gap / 2
            ring = [_arc(90, 90, 68, a0 + span * j - 0.03, a0 + span * (j + 1) + 0.03, rng) for j in range(pieces)]
            strokes = ring + _inside(self.lua, 90, 90, 68)
            self.assertFalse(self.closed(fixtures.lua_strokes(self.lua, strokes)), pieces)
            spell, err, partial = self.lua.eval("read_spell")(fixtures.lua_strokes(self.lua, strokes))
            self.assertIsNone(spell)
            self.assertEqual("The ring is not closed", err)
            self.assertLess(abs(partial["gap_at"] + math.pi / 2), 0.2, pieces)
            self.assertGreater(len(list(partial["trouble"].values())), 0)

    def test_a_ring_of_short_pieces_needs_no_big_stroke_inside(self):
        rng = random.Random(36)
        for pieces in (20, 32):
            ring = [_arc(90, 90, 68, math.tau * j / pieces - 0.03, math.tau * (j + 1) / pieces + 0.03, rng)
                    for j in range(pieces)]
            self.assertEqual("shockwave:burst", fixtures.run(self.lua, ring)[0], pieces)

    def test_a_signs_base_cannot_close_the_rings_gap(self):
        rng = random.Random(37)
        gap = 0.7
        a0, span = -math.pi / 2 + gap / 2, (math.tau - gap) / 24
        ring = [_arc(90, 90, 68, a0 + span * j - 0.03, a0 + span * (j + 1) + 0.03, rng) for j in range(24)]
        # The column's base lies along the missing arc, but belongs to its stem inside the ring.
        base = fixtures.densify([(68, 24), (112, 24)])
        stem = fixtures.densify([(90, 24), (90, 48)])
        strokes = ring + [base, stem]
        self.assertFalse(self.closed(fixtures.lua_strokes(self.lua, strokes)))
        self.assertEqual("The ring is not closed", fixtures.run(self.lua, strokes)[0])


class TrySealTests(unittest.TestCase):
    """Players asked for "Try seal" at any time: a drawing the book doesn't read by itself - a ring it doesn't see closed -
    can be tried, and the book tells why it fails: an open ring and where its gap is, the ring marked."""
    def test_try_seal_reads_any_drawing_and_tells_where_the_gap_is(self):
        lua = fixtures.load_mod()
        G = lua.globals()
        fixtures.open_book(G)
        rng = random.Random(34)
        random.seed(34)
        a0 = -math.pi / 2 + 0.5
        strokes = [_arc(90, 90, 68, a0, a0 + 2 * math.pi - 1.0, rng)] + _inside(lua, 90, 90, 68)
        fixtures.draw(G, strokes)
        self.assertEqual(0, int(G.globals["witch_notebook.debug_next"] or 0))  # an open ring: not read by itself
        self.assertIsNotNone(G.notebook_button_rects[900098])
        fixtures.press_button(G, 900098)
        self.assertEqual(1, int(G.globals["witch_notebook.debug_next"] or 0))
        self.assertEqual("The ring is not closed - its gap is at the top", G.notebook_result())
        self.assertEqual(0, fixtures.seal_count(G))

    def test_a_ring_redrawn_in_pieces_awakens_the_seal(self):
        lua = fixtures.load_mod()
        G = lua.globals()
        fixtures.open_book(G)
        rng = random.Random(35)
        random.seed(35)
        ring = [_arc(90, 90, 68, 2 * math.pi * j / 6 - 0.05, 2 * math.pi * (j + 1) / 6 + 0.05, rng) for j in range(6)]
        fixtures.draw(G, _inside(lua, 90, 90, 68) + ring)  # the ring last, a piece at a time
        self.assertEqual(1, fixtures.seal_count(G))
        self.assertTrue((G.globals["witch_notebook.seal_1_spell"] or "").startswith("element=fire;form=column;"))


def run_checks():
    return unittest.TextTestRunner(stream=sys.stdout, verbosity=1).run(
        unittest.TestSuite(unittest.defaultTestLoader.loadTestsFromTestCase(cls)
                           for cls in (FlickerShapeTests, ModifierAcceptanceTests, WaterIsNotWindTests, TwinSignsTests,
                                       TroubleMarksTests, RingInPiecesTests, TrySealTests))
    ).wasSuccessful()


if __name__ == "__main__":
    raise SystemExit(0 if run_checks() else 1)
