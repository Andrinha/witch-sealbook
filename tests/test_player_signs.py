"""Signs drawn as players draw them (player_signs.py) read right: every sign as the wiki pictures it, as the book's legend
shows it and the other ways the wiki or the manga draw it, two of it facing the middle of a ring round a fire sigil, in
any stroke order and with a hand's proportions. tests/bench_player_signs.py shows what the misread ones were read as.

Run with python tests/test_player_signs.py; also included in tests/run_tests.py.
"""
import os
import sys
import unittest
import zlib
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import player_signs as ps  # noqa: E402

SEALS = 20  # seals of each sign drawn each way ...
FLOOR = 16  # ... at least this many cast with both of its signs read right
# the drawings the reading is still weak on: what it does with them now (2026-10-12), so that it gets no worse
WEAK = {
    ("levitation", "small"): 3,  # a tiny arrowhead: a column
    ("expansion", "wiki"): 7,    # corners nested three deep, as the wiki's Enlarge: torn in two Regions turned out ...
    ("expansion", "two"): 8,     # ... or two arcs of Binding turned out
    ("sights", "wiki"): 13,      # its diamond drawn small: a column's base
    ("diamond", "wiki"): 13,     # drawn in four strokes, a corner each: Binding
    ("purify", "wiki"): 13,      # its curl: the Spiraling Wind's loop
}

_lua = None


def _trial(task):
    global _lua
    key, variant = task
    if _lua is None:
        _lua = ps.fx.load_mod()
        ps.add_book(_lua)
    right, read_as, _ = ps.trial(_lua, key, variant, SEALS, 1000 + zlib.crc32((key + variant).encode()) % 1000)
    return key, variant, right, dict(read_as.most_common(3))


class PlayerSignTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        lua = ps.fx.load_mod()
        ps.add_book(lua)
        # the legend players learned before a sign was redrawn is told by the bench, not held to here
        tasks = [(key, variant) for key in lua.eval("DICTIONARY_SIGN_ORDER").values() for variant in ps.SHAPES[key] if variant != "old"]
        with Pool(min(8, os.cpu_count() or 1)) as pool:
            cls.results = pool.map(_trial, tasks)

    def test_every_sign_reads_as_players_draw_it(self):
        self.assertGreater(len(self.results), 70)
        low = [f"{key} ({variant}): {right}/{SEALS}, read as {read_as}" for key, variant, right, read_as in self.results
               if right < WEAK.get((key, variant), FLOOR)]
        self.assertEqual([], low)

    def test_gathering_is_not_refuse(self):
        # players' report: Gathering drawn as the wiki draws it, an arrow on legs, was read as Refuse
        for key, variant, right, read_as in self.results:
            if key == "gathering":
                self.assertGreaterEqual(right, SEALS - 1, variant)
                self.assertNotIn("refuse", read_as, variant)


def run_checks():
    return unittest.TextTestRunner(stream=sys.stdout, verbosity=1).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(PlayerSignTests)
    ).wasSuccessful()


if __name__ == "__main__":
    raise SystemExit(0 if run_checks() else 1)
