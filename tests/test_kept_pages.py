"""A book keeps all its pages for the next session (book_store.lua): a seal awakening again on an earlier page - edited,
or opened by "Mark" - set the count of pages to its own until 2026-10-21, and the seals after it were gone after a
reload (a Workshop player: "any spell after number 2 would clear when booting up the same run"). Their pages were still
in the save: a new session finds them again.

Run with python tests/test_kept_pages.py.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_tests as R  # noqa: E402
import test_marks as T  # noqa: E402
from harness import MOD, load_mod  # noqa: E402

EDIT_LEFT, EDIT_RIGHT, RETRY = 900300, 900301, 900098  # notebook.lua BUTTON


def book_with_three_seals():
    lua = load_mod()
    lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
    lua.execute(R.CARRY_ALL)
    G = lua.globals()
    R.open_book(G)

    def draw_at(x0, seed):
        strokes, closing, *_ = T.fire_seal(lua, seed=seed)
        for st in strokes[1:] + strokes[:1] + [closing]:
            G.left_down = True
            for x, y in st:
                G.mouse[1], G.mouse[2] = x0 + x, R.PAGE_Y + y
                G.notebook_update()
            G.left_down = False; G.notebook_update()
            for _ in range(20): G.notebook_update()
        for _ in range(60): G.notebook_update()

    draw_at(R.LEFT_X, 10)
    draw_at(R.RIGHT_X, 11)
    G.pressed[7] = True; G.notebook_update(); G.pressed[7] = False
    for _ in range(60): G.notebook_update()
    draw_at(R.LEFT_X, 12)
    G.pressed[4] = True; G.notebook_update(); G.pressed[4] = False  # A: back to the first two
    for _ in range(60): G.notebook_update()
    return lua, G


def reload(G):
    """a new session of the save: the book's pages as BookStore.load reads them"""
    lua2 = load_mod()
    G2 = lua2.globals()
    for key, value in G.globals.items():
        G2.globals[key] = value
    return lua2.eval("BookStore.load")("book"), G2


class KeptPages(unittest.TestCase):
    def test_a_seal_awakened_again_keeps_the_pages_after_it(self):
        _, G = book_with_three_seals()
        self.assertEqual(3, R.seal_count(G))
        # the second seal edited and tried again
        G.mouse[1], G.mouse[2] = R.RIGHT_X + 90, R.PAGE_Y + 90
        G.buttons[EDIT_RIGHT] = True; G.notebook_update(); G.buttons[EDIT_RIGHT] = False
        self.assertEqual("1", G.globals["witch_notebook.seal_2_draft"])
        R.press_button(G, RETRY)
        self.assertEqual("", G.globals["witch_notebook.seal_2_draft"])
        st, _ = reload(G)
        self.assertEqual(3, sum(1 for s in st.seals.values() if s.draft != "1" and s.spell != ""))

    def test_pages_lost_to_the_old_count_are_found(self):
        _, G = book_with_three_seals()
        G.globals["witch_notebook.seals"] = "1"  # as the old code left it after the first seal awoke again
        st, G2 = reload(G)
        self.assertEqual(3, len(st.seals))
        self.assertEqual("3", G2.globals["witch_notebook.seals"])

    def test_a_torn_out_page_stays_gone(self):
        _, G = book_with_three_seals()
        for _ in range(2):  # "tear out" asks again: a second click tears the last seal out
            G.buttons[900005] = True; G.notebook_update(); G.buttons[900005] = False
        G.pressed[7] = True; G.notebook_update(); G.pressed[7] = False
        for _ in range(60): G.notebook_update()
        st, _ = reload(G)
        self.assertEqual(R.seal_count(G), sum(1 for s in st.seals.values() if s.draft != "1"))


if __name__ == "__main__":
    unittest.main()
