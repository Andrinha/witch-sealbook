"""Independent checks of the $P+ metric and the game's recognizer API.

Run with python tests/test_recognizer.py; also included in tests/run_tests.py.
"""
import math
from pathlib import Path
import random
import sys
import unittest

from lupa import luajit21


def reference_distance(source, target):
    """Published $P+ directed distance: nearest targets, then uncovered targets back to source."""
    used = set()
    total = 0.0
    for point in source:
        index = min(range(len(target)), key=lambda j: math.dist(point, target[j]))
        used.add(index)
        total += math.dist(point, target[index])
    for index, point in enumerate(target):
        if index not in used:
            total += min(math.dist(point, other) for other in source)
    return total


class RecognizerTests(unittest.TestCase):
    def setUp(self):
        self.lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
        source = (Path(__file__).resolve().parents[1] / "files/recognizer.lua").read_text(encoding="utf-8")
        self.lua.execute(source + """
            test_cloud_match = cloud_match
            test_cloud_points = to_cloud
            function test_cloud(strokes) return to_cloud(normalize(flatten(strokes))) end
        """)

    def drawing(self, strokes):
        return self.lua.table_from([
            self.lua.table_from([self.lua.table_from({"x": x, "y": y}) for x, y in stroke])
            for stroke in strokes
        ])

    def cloud(self, points):
        return self.lua.table_from({
            "xs": self.lua.table_from([p[0] for p in points]),
            "ys": self.lua.table_from([p[1] for p in points]),
            "angles": self.lua.table_from([p[2] for p in points]), "n": len(points),
        })

    def test_distance_matches_reference(self):
        rng = random.Random(17)
        for n in range(1, 9):
            for _ in range(12):
                # Quantized coordinates include ties and duplicated points.
                a = [tuple(rng.randrange(5) / 4 for _ in range(3)) for _ in range(n)]
                b = [tuple(rng.randrange(5) / 4 for _ in range(3)) for _ in range(n)]
                expected = min(reference_distance(a, b), reference_distance(b, a))
                actual = self.lua.globals().test_cloud_match(self.cloud(a), self.cloud(b))
                self.assertAlmostEqual(actual, expected, places=12)

    def test_curvature_changes_distance_with_identical_positions(self):
        straight = [(0, 0, 0), (1, 0, 0)]
        bent = [(0, 0, 0.25), (1, 0, 0.25)]
        match = self.lua.globals().test_cloud_match
        self.assertEqual(match(self.cloud(straight), self.cloud(straight)), 0)
        self.assertAlmostEqual(match(self.cloud(straight), self.cloud(bent)), 0.5)

    def test_pen_lifts_do_not_create_corners(self):
        lines = [[(x, y) for x in (0, 2.5, 5, 7.5, 10)] for y in (0, 10)]
        for strokes in (lines, [list(reversed(s)) for s in reversed(lines)]):
            cloud = self.lua.globals().test_cloud(self.drawing(strokes))
            self.assertTrue(all(abs(a) < 1e-8 for a in cloud["angles"].values()))

    def test_real_corner_has_a_turning_angle(self):
        points = self.lua.table_from([
            self.lua.table_from({"x": x, "y": y, "id": 1}) for x, y in ((0, 0), (1, 0), (1, 1))
        ])
        right_angle = self.lua.globals().test_cloud_points(points)
        self.assertAlmostEqual(right_angle["angles"][2], 0.5)
        cloud = self.lua.globals().test_cloud(self.drawing([[(0, 0), (10, 0), (10, 10)]]))
        angles = list(cloud["angles"].values())
        self.assertGreater(max(angles), 0.1)
        self.assertTrue(all(0 <= a <= 1 for a in angles))

    def test_best_matches_full_scores_with_penalties_and_floor(self):
        shapes = {
            "line": [[(0, 0), (0.25, 0), (0.5, 0), (0.75, 0), (1, 0)]],
            "corner": [[(0, 0), (1, 0), (1, 1)]],
            "triangle": [[(0, 1), (0.5, 0), (1, 1), (0, 1)]],
        }
        penalties = {"line": 0.02, "corner": 0.08, "triangle": 0}
        entries = self.lua.table_from([
            self.lua.table_from({"key": key, "shape": self.drawing(shape), "penalty": penalties[key]})
            for key, shape in shapes.items()
        ])
        templates = self.lua.globals().recognizer_new_set(entries)
        for shape in shapes.values():
            for strokes in (shape, [list(reversed(s)) for s in shape]):
                drawing = self.drawing(strokes)
                scores = self.lua.globals().recognizer_scores(templates, drawing)
                expected = max(m["score"] - penalties[m["key"]] for m in scores.values())
                for floor in (-0.1, 0.7, 1.0):
                    best = self.lua.globals().recognizer_best(templates, drawing, floor)
                    if expected <= floor:
                        self.assertIsNone(best)
                    else:
                        self.assertIsNotNone(best)
                        self.assertAlmostEqual(best["score"] - penalties[best["key"]], expected, places=12)

    def test_empty_and_zero_length_drawings_are_unrecognized(self):
        entries = self.lua.table_from([
            self.lua.table_from({"key": "line", "shape": self.drawing([[(0, 0), (0.25, 0), (0.5, 0), (0.75, 0), (1, 0)]])})
        ])
        templates = self.lua.globals().recognizer_new_set(entries)
        for strokes in ([], [[]], [[(1, 1)]], [[(1, 1), (1, 1)]]):
            drawing = self.drawing(strokes)
            self.assertIsNone(self.lua.globals().recognizer_best(templates, drawing))
            self.assertEqual(len(self.lua.globals().recognizer_scores(templates, drawing)), 0)

    def test_alternative_margin_groups_poses_and_uses_penalties(self):
        shape = self.drawing([[(0, 0), (1, 0), (1, 1)]])
        entries = self.lua.table_from([
            self.lua.table_from({"key": key, "shape": shape, "penalty": penalty})
            for key, penalty in (("corner", 0), ("corner", 0.01), ("other", 0.08))
        ])
        templates = self.lua.globals().recognizer_new_set(entries)
        best = self.lua.globals().recognizer_best(templates, shape, 0.95, True)
        self.assertEqual(best["key"], "corner")
        # The different key is below the floor and still counts; duplicate poses do not.
        self.assertAlmostEqual(best["margin"], 0.08, places=12)
        for template in templates.values():
            if template["key"] == "other": template["penalty"] = 0
        tied = self.lua.globals().recognizer_best(templates, shape, 0, True)
        self.assertEqual(tied["margin"], 0)
        self.assertIsNone(self.lua.globals().recognizer_best(templates, shape, 1, True))


def run_checks():
    return unittest.TextTestRunner(stream=sys.stdout, verbosity=1).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(RecognizerTests)
    ).wasSuccessful()


if __name__ == "__main__":
    raise SystemExit(0 if run_checks() else 1)
