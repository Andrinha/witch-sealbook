"""The pen's helpers in the open book (notebook.lua): Undo (book_undo.lua) takes back the last line, erasing, marking or
Clear - a seal that awoke from it opens again as a draft; the compass (book_compass.lua), its key held, draws a true
ring - set from the middle, then along its circle wherever the mouse goes.

Run with python tests/test_pen_tools.py.
"""
import math
import os
import random
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import player_signs as ps  # noqa: E402
import run_tests as R  # noqa: E402
from harness import MOD, load_mod  # noqa: E402

UNDO_BUTTON = 900096   # notebook.lua BUTTON.UNDO
CLEAR_BUTTON = 900099  # BUTTON.CLEAR
CTRL, Z = 224, 29      # data/scripts/debug/keycodes.lua: Key_LCTRL, Key_z
SHIFT, RSHIFT = 225, 229  # Key_LSHIFT (the compass's key), Key_RSHIFT


def book():
    lua = load_mod()
    lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
    G = lua.globals()
    R.open_book(G)
    return lua, G


def ctrl_z(G):
    G.keys_down[CTRL] = True; G.pressed[Z] = True
    G.notebook_update()
    G.pressed[Z] = False; G.keys_down[CTRL] = False
    G.notebook_update()


def lines(G, i=1):
    text = G.globals[f"witch_notebook.seal_{i}_strokes"] or ""
    return text.count("|") + 1 if text else 0


def draw(G, strokes, right=False):
    """strokes made for a 180 page drawn on the Spellbook's left or right page"""
    x0 = R.RIGHT_X if right else R.LEFT_X
    for stroke in strokes:
        G.left_down = True
        for x, y in stroke:
            G.mouse[1], G.mouse[2] = x0 + x, R.PAGE_Y + y
            G.notebook_update()
        G.left_down = False; G.notebook_update()
        for _ in range(5): G.notebook_update()


def wait_reading(G):
    for _ in range(200):
        if G.BookReading.waiting() == 0:
            break
        G.notebook_update()
    G.notebook_update()


class Undo(unittest.TestCase):
    def test_lines_taken_back_one_by_one(self):
        lua, G = book()
        R.draw_on_blank(G, [[(40, 40), (60, 40)], [(40, 60), (60, 60)], [(40, 80), (60, 80)]])
        self.assertEqual(3, lines(G))
        ink = G.flask.witch_ink
        R.press_button(G, UNDO_BUTTON)
        self.assertEqual(2, lines(G))
        ctrl_z(G)
        self.assertEqual(1, lines(G))
        self.assertEqual(ink, G.flask.witch_ink)  # the ink spent stays spent, as erasing gives none back
        ctrl_z(G)
        self.assertEqual(0, lines(G))
        ctrl_z(G)  # nothing left: nothing happens
        self.assertEqual(0, lines(G))
        draw(G, [[(40, 40), (60, 40)]])  # the page, an empty draft, is drawn on as before
        self.assertEqual(1, lines(G))

    def test_erasing_and_clear_taken_back(self):
        lua, G = book()
        R.draw_on_blank(G, [[(30, 90), (150, 90)]])
        before = G.globals["witch_notebook.seal_1_strokes"]
        G.mouse[1], G.mouse[2] = R.LEFT_X + 90, R.PAGE_Y + 90
        G.right_down = True; G.notebook_update(); G.right_down = False; G.notebook_update()
        self.assertEqual(2, lines(G))
        ctrl_z(G)
        self.assertEqual(before, G.globals["witch_notebook.seal_1_strokes"])
        # the points erased before are whole again: erased again, the line parts again
        G.right_down = True; G.notebook_update(); G.right_down = False; G.notebook_update()
        self.assertEqual(2, lines(G))
        R.press_button(G, CLEAR_BUTTON)
        self.assertEqual(0, lines(G))
        ctrl_z(G)
        self.assertEqual(2, lines(G))
        ctrl_z(G)
        self.assertEqual(before, G.globals["witch_notebook.seal_1_strokes"])

    def test_marking_taken_back(self):
        lua, G = book()
        R.draw_on_blank(G, [[(40, 40), (60, 40)], [(40, 60), (60, 60)]])
        page = lua.eval("BookStore.load")("book").seals[1]
        menu = lua.table_from({"page": page, "strokes": lua.table_from([page.strokes[1]])})
        lua.eval("BookMarks.on_pick")(lua.table_from({"kind": "sign", "key": "column"}), menu)
        self.assertEqual("sign:column@1", G.globals["witch_notebook.seal_1_marks"])
        ctrl_z(G)
        self.assertEqual("", G.globals["witch_notebook.seal_1_marks"])
        self.assertEqual(2, lines(G))

    def test_a_line_being_drawn_taken_back(self):
        lua, G = book()
        R.draw_on_blank(G, [[(40, 40), (60, 40)]])
        G.left_down = True
        for x in range(40, 80, 2):
            G.mouse[1], G.mouse[2] = R.LEFT_X + x, R.PAGE_Y + 100
            G.notebook_update()
        G.keys_down[CTRL] = True; G.pressed[Z] = True; G.notebook_update(); G.pressed[Z] = False; G.keys_down[CTRL] = False
        for x in range(80, 120, 2):  # the button still held: no new line
            G.mouse[1], G.mouse[2] = R.LEFT_X + x, R.PAGE_Y + 100
            G.notebook_update()
        G.left_down = False; G.notebook_update()
        self.assertEqual(1, lines(G))

    def test_a_seal_awoken_opens_again(self):
        # the line that closed the ring awoke the seal: Undo takes it back, the seal is a draft again and the book casts
        # what it cast before; closed again, it awakens again
        lua, G = book()
        random.seed(3)
        strokes = R.column_seal(lua, "fire")
        R.draw_on_blank(G, strokes)
        wait_reading(G)
        self.assertEqual(1, R.seal_count(G))
        self.assertEqual("1", G.globals["witch_notebook.active"])
        spell = G.globals["witch_notebook.seal_1_spell"]
        ctrl_z(G)
        self.assertEqual("1", G.globals["witch_notebook.seal_1_draft"])
        self.assertEqual("0", G.globals["witch_notebook.active"])
        self.assertEqual("", G.globals["witch_notebook.active_spell"])
        self.assertEqual(len(strokes) - 1, lines(G))
        draw(G, strokes[-1:])  # the pen is back on that page
        wait_reading(G)
        self.assertEqual("", G.globals["witch_notebook.seal_1_draft"])
        self.assertEqual(spell, G.globals["witch_notebook.seal_1_spell"])
        self.assertEqual("1", G.globals["witch_notebook.active"])

    def test_the_seal_cast_before_is_cast_again(self):
        lua, G = book()
        random.seed(3)
        draw(G, R.column_seal(lua, "fire"))
        wait_reading(G)
        water = R.column_seal(lua, "water")
        draw(G, water, right=True)  # the next page, on the same spread
        wait_reading(G)
        self.assertEqual("2", G.globals["witch_notebook.active"])
        ctrl_z(G)
        self.assertEqual("1", G.globals["witch_notebook.seal_2_draft"])
        self.assertEqual("1", G.globals["witch_notebook.active"])
        self.assertTrue(G.globals["witch_notebook.active_spell"].startswith("element=fire"))
        # taken back further: the water page's lines one by one, then nothing more (the fire seal awoke before them)
        for n in range(len(water) - 1, 0, -1):
            ctrl_z(G)
            self.assertEqual(n - 1, lines(G, 2))
        ctrl_z(G)
        self.assertEqual("", G.globals["witch_notebook.seal_1_draft"])

    def test_an_awoken_seal_out_of_view_stays(self):
        lua, G = book()
        random.seed(3)
        R.draw_on_blank(G, R.column_seal(lua, "fire"))
        wait_reading(G)
        for _ in range(2):
            G.pressed[7] = True; G.notebook_update(); G.pressed[7] = False
        for _ in range(80): G.notebook_update()
        ctrl_z(G)
        self.assertEqual("", G.globals["witch_notebook.seal_1_draft"])


def compass(G, path, key=SHIFT, right=False):
    """the mouse along 'path' (page units of a 180 page) with the button and the compass's key held, then let go"""
    x0 = R.RIGHT_X if right else R.LEFT_X
    G.keys_down[key] = True
    G.left_down = True
    for i, (x, y) in enumerate(path):
        G.mouse[1], G.mouse[2] = x0 + x, R.PAGE_Y + y
        G.left_just_down = i == 0
        G.notebook_update()
    G.left_just_down = G.left_down = False
    G.notebook_update()
    G.keys_down[key] = False
    G.notebook_update()


def set_compass(G, cx, cy, r, **kw):
    """pressed at the middle, pulled out to the size"""
    compass(G, [(cx + t, cy) for t in range(0, int(r) + 1, 2)] + [(cx + r, cy)], **kw)


def around(cx, cy, r, a0, a1, reach=None, step=0.05):
    """pressed on the circle at a0, a little way along it, then the mouse round to a1 'reach' from the middle"""
    d = 1 if a1 >= a0 else -1
    start = [(cx + r * math.cos(a0 + d * t), cy + r * math.sin(a0 + d * t)) for t in (0, 0.04, 0.08)]
    reach = reach or r
    n = max(2, int(abs(a1 - a0) / step))
    return start + [(cx + reach * math.cos(a0 + (a1 - a0) * k / n), cy + reach * math.sin(a0 + (a1 - a0) * k / n)) for k in range(1, n + 1)]


def page_strokes(lua, i=1):
    """the page's lines, each a list of its points"""
    lines = lua.eval("BookStore.load")("book").seals[i].strokes
    return [[st[k] for k in range(1, len(st) + 1)] for st in (lines[j] for j in range(1, len(lines) + 1))]


def symbols(lua, cx, cy, r):
    t = R.templates(lua)
    out = R.place(R.hand(t[("sigil", "fire")]), cx, cy, r * 0.45)
    for deg in (0, 180):
        a = math.radians(deg)
        out += R.place(R.hand(t[("sign", "column")]), cx + 0.7 * r * math.cos(a), cy + 0.7 * r * math.sin(a), r * 0.23, a - math.pi / 2)
    return out


class Compass(unittest.TestCase):
    def test_a_true_ring_round_the_symbols(self):
        # the symbols drawn, the compass set at their middle and drawn round once - the mouse far outside the line, a
        # little wobbly: the ring is a true circle and the seal awakens
        lua, G = book()
        random.seed(5)
        cx, cy, r = 91, 89, 68
        drawn = symbols(lua, cx, cy, r)
        draw(G, drawn)
        ink = G.flask.witch_ink
        set_compass(G, cx, cy, r)
        self.assertEqual(0, R.seal_count(G))
        self.assertEqual(len(drawn), len(page_strokes(lua)))  # setting it draws nothing
        rng = random.Random(1)
        path = [(x + rng.uniform(-1.5, 1.5), y + rng.uniform(-1.5, 1.5)) if k > 3 else (x, y)
                for k, (x, y) in enumerate(around(cx, cy, r, 0.3, 0.3 + 2 * math.pi + 0.4, reach=r + 30))]
        compass(G, path)
        wait_reading(G)
        self.assertEqual(1, R.seal_count(G))
        spell = G.globals["witch_notebook.seal_1_spell"]
        self.assertTrue(spell.startswith("element=fire;form=column"), spell)
        pts = page_strokes(lua)[-1]
        off = max(abs(math.dist((p.x, p.y), (cx, cy)) - r) for p in pts)
        self.assertLess(off, 0.6)  # (the page keeps a seal's points to a tenth)
        # once round and a little more, and no further: the ink of that much line
        length = sum(math.dist((a.x, a.y), (b.x, b.y)) for a, b in zip(pts, pts[1:]))
        self.assertAlmostEqual(length, r * (2 * math.pi + 0.12), delta=4)
        self.assertAlmostEqual(ink - G.flask.witch_ink, length * G.INK_PER_UNIT, delta=2)

    def test_a_ring_left_open_closed_later(self):
        # the manga's way: the ring with its gap, the symbols, the gap closed - on the same circle, the compass kept
        lua, G = book()
        random.seed(6)
        cx, cy, r = 90, 90, 66
        set_compass(G, cx, cy, r)
        compass(G, around(cx, cy, r, 0, math.radians(300)))
        draw(G, symbols(lua, cx, cy, r))
        wait_reading(G)
        self.assertEqual(0, R.seal_count(G))
        compass(G, around(cx, cy, r, math.radians(298), math.radians(362)), key=RSHIFT)  # either Shift
        wait_reading(G)
        self.assertEqual(1, R.seal_count(G))
        self.assertTrue(G.globals["witch_notebook.seal_1_spell"].startswith("element=fire;form=column"))
        strokes = page_strokes(lua)
        for ring in (strokes[0], strokes[-1]):
            for p in ring:
                self.assertLess(abs(math.dist((p.x, p.y), (cx, cy)) - r), 0.6)
        # taken back, the gap is open again; the compass still set, it closes again
        ctrl_z(G)
        self.assertEqual("1", G.globals["witch_notebook.seal_1_draft"])
        compass(G, around(cx, cy, r, math.radians(-62), math.radians(2)))
        wait_reading(G)
        self.assertEqual(1, R.seal_count(G))

    def test_set_anew(self):
        lua, G = book()
        draw(G, [[(20, 20), (24, 20)]])
        page = lua.eval("BookStore.load")("book").seals[1]
        set_compass(G, 90, 90, 60)
        self.assertEqual((90, 90, 60), (page.compass.x, page.compass.y, round(page.compass.r)))
        # pressed by its middle: the needle back in its hole, a ring round the same middle
        set_compass(G, 92, 88, 30)
        self.assertEqual((90, 90), (page.compass.x, page.compass.y))
        self.assertAlmostEqual(32, page.compass.r, delta=1.5)
        # pressed by the circle's line and pulled off it: set anew from the press, nothing drawn
        compass(G, [(90 + 32, 90), (90 + 32 + 5, 90), (90 + 32 + 20, 90), (90 + 32 + 40, 90)])
        self.assertEqual((122, 90), (page.compass.x, page.compass.y))
        self.assertAlmostEqual(40, page.compass.r, delta=1)
        self.assertEqual(1, lines(G))
        # a click with the key held sets nothing
        compass(G, [(40, 140)])
        self.assertEqual((122, 90), (page.compass.x, page.compass.y))

    def test_the_line_stops_off_the_paper(self):
        # a circle running past the page's edge: the line is drawn where the paper is, in pieces
        lua, G = book()
        draw(G, [[(20, 20), (24, 20)]])
        set_compass(G, 60, 90, 70)
        compass(G, around(60, 90, 70, 0, 2 * math.pi + 0.1))
        strokes = page_strokes(lua)
        self.assertEqual(3, len(strokes))  # the dot, the arc over the top and round to the bottom, cut by the left edge
        for st in strokes[1:]:
            for p in st:
                self.assertTrue(6 <= p.x <= 174 and 6 <= p.y <= 174)


DOUBT = r'''
-- the drawing of COUNT lines, none marked, is read as if the book couldn't tell the sign of lines IDS: "ambiguous"
local real = read_spell
function read_spell( strokes )
	local marked = false
	for _, stroke in ipairs( strokes ) do marked = marked or stroke.mark ~= nil end
	if #strokes ~= COUNT or marked then return real( strokes ) end
	local lines = {}
	for _, i in ipairs( { IDS } ) do lines[#lines + 1] = strokes[i] end
	return nil, "A sign is ambiguous", { trouble = lines, doubt = lines }
end
'''


def doubtful_seal(lua):
    """A fire seal with two columns that the book reads as if it couldn't tell the second one (read_spell stubbed, for a
    reading the book really doubts is a matter of chance; test_the_symbol_a_seal_fails_on has what compile_spell tells):
    its strokes, the one closing the ring last, and the column's (1-based)"""
    random.seed(3)
    strokes = R.column_seal(lua, "fire")
    t = R.templates(lua)
    sigil, column = len(t[("sigil", "fire")]), len(t[("sign", "column")])
    ids = list(range(2 + sigil + column, 2 + sigil + 2 * column))
    lua.execute(DOUBT.replace("COUNT", str(len(strokes))).replace("IDS", ", ".join(map(str, ids))))
    return strokes, ids


class Doubt(unittest.TestCase):
    def test_the_symbol_a_seal_fails_on(self):
        # compile_spell tells the one symbol it failed on, that a mark would make read: an ambiguous sign, a sigil too
        # imprecise; not a sign too small (marked, it is still too small)
        lua = load_mod()
        compile_ = lua.eval("compile_spell")
        lines = lua.table_from([lua.table_from([lua.table_from({"x": 1, "y": 1})])])
        tree = R.seal_tree(lua, ["fire"], [("column", False), ("column", False)])
        tree.symbols[2].score, tree.symbols[2].margin, tree.symbols[2].strokes = 0.5, 0.01, lines
        self.assertEqual((None, "A sign is ambiguous"), compile_(tree))
        self.assertTrue(lua.eval("rawequal")(lines, tree.doubt))
        tree = R.seal_tree(lua, ["fire"], [("column", False), ("column", False)])
        tree.symbols[1].score, tree.symbols[1].strokes = 0.4, lines
        self.assertEqual((None, "The sigil is too imprecise"), compile_(tree))
        self.assertTrue(lua.eval("rawequal")(lines, tree.doubt))
        tree = R.seal_tree(lua, ["fire"], [("column", False), ("column", False)])
        tree.symbols[2].size, tree.symbols[2].strokes = 0.03, lines
        self.assertEqual((None, "A sign is too small"), compile_(tree))
        self.assertIsNone(tree.doubt)

    def test_what_a_doubtful_sign_looks_like_and_mark(self):
        # the seal fails on a sign it can't decide on: under it, the two readings it looks most like and [Mark]; a click
        # there opens the menu of its readings, a pick awakens the seal
        lua, G = book()
        lua.execute("texts = {} function GuiText( g, x, y, t ) texts[#texts + 1] = t end")
        strokes, ids = doubtful_seal(lua)
        draw(G, strokes)
        wait_reading(G)
        self.assertEqual(0, R.seal_count(G))
        page = lua.eval("BookStore.load")("book").seals[1]
        self.assertIsNotNone(page.doubt)
        doubt = [page.doubt.strokes[k] for k in range(1, len(page.doubt.strokes) + 1)]
        same = lua.eval("rawequal")
        self.assertTrue(len(ids) == len(doubt) and all(same(page.strokes[i], d) for i, d in zip(ids, doubt)))  # the page's own lines
        offered = page.doubt["items"]  # (.items is the proxy's own method)
        items = [offered[k] for k in range(1, len(offered) + 1)]
        self.assertEqual(2, len(items))
        self.assertEqual(("sign", "column"), (items[0].kind, items[0].key))
        G.mouse[1], G.mouse[2] = 0, 0
        lua.execute("texts = {}")
        G.notebook_update()
        said = [t for t in lua.eval("texts").values() if t.endswith("?") and " or " in t]
        self.assertEqual(1, len(said), list(lua.eval("texts").values()))
        self.assertTrue(said[0].startswith("Column "), said[0])
        self.assertIn(" or ", said[0])
        at = lua.eval("BookMarks.doubt_at")
        self.assertIsNotNone(at)
        # [Mark]: the menu of the sign's readings, by it
        G.mouse[1], G.mouse[2] = (at.x0 + at.x1) / 2, (at.y0 + at.y1) / 2
        G.left_down = G.left_just_down = True; G.notebook_update(); G.left_just_down = False
        G.left_down = False; G.notebook_update()
        menu = lua.eval("BookMarks.menu")
        self.assertIsNotNone(menu)
        self.assertTrue(len(menu.strokes) == len(doubt) and all(same(menu.strokes[k + 1], d) for k, d in enumerate(doubt)))
        self.assertEqual(0, R.seal_count(G))  # the click drew nothing
        self.assertEqual(len(strokes), lines(G))
        row = next(row for row in menu.rows.values() if row.item and row.item.key == "column")
        G.mouse[1], G.mouse[2] = (row.x0 + row.x1) / 2, (row.y0 + row.y1) / 2
        G.left_down = G.left_just_down = True; G.notebook_update(); G.left_just_down = False
        G.left_down = False; G.notebook_update()
        wait_reading(G)
        self.assertEqual(1, R.seal_count(G))
        self.assertTrue(G.globals["witch_notebook.seal_1_marks"].startswith("sign:column@"))
        self.assertTrue(G.globals["witch_notebook.seal_1_spell"].startswith("element=fire;form=column"))

    def test_the_hint_goes_with_a_change(self):
        # it stays while the lines are as they were; a line drawn takes it away, taken back the doubt is told again
        lua, G = book()
        strokes, _ = doubtful_seal(lua)
        draw(G, strokes)
        wait_reading(G)
        for _ in range(60): G.notebook_update()
        self.assertIsNotNone(lua.eval("BookMarks.doubt_at"))
        draw(G, [[(20, 160), (24, 160)]])  # a dash in the corner, out of the ring: read again
        self.assertIsNone(lua.eval("BookMarks.doubt_at"))
        wait_reading(G)
        self.assertIsNone(lua.eval("BookMarks.doubt_at"))
        ctrl_z(G)
        wait_reading(G)
        G.notebook_update()
        self.assertIsNotNone(lua.eval("BookMarks.doubt_at"))


if __name__ == "__main__":
    unittest.main()
