"""Marking what lines are (book_marks.lua, seal.lua take_marked / seal_mark_readings): the witch circles the lines of a
sign the book misreads and picks what they are from the readings offered. The pick decides what the lines are read as;
how well they are drawn as it still sets the seal's precision. Signs drawn the way players draw them (player_signs.py)
find their own reading among those offered; the marks stay with the page, through erasing and a saved run.

Run with python tests/test_marks.py.
"""
import math
import os
import random
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import player_signs as ps  # noqa: E402
import run_tests as R  # noqa: E402
from harness import MOD, load_mod, load_reader  # noqa: E402

MARK_BUTTON = 900097  # notebook.lua BUTTON.MARK
ERASE_BUTTON = 900009  # BUTTON.ERASER


def fire_seal(lua, seed=3):
    """a fire sigil and two columns in a ring left open, the stroke that closes it, and which strokes are the sigil's and
    a column's (1-based, the ring first)"""
    random.seed(seed)
    t = R.templates(lua)
    arc, closing, (cx, cy, r) = R.prepared_ring()
    sigil = R.place(R.hand(t[("sigil", "fire")]), cx, cy, r * 0.45)
    columns = []
    for deg in (0, 180):
        a = math.radians(deg)
        columns.append(R.place(R.hand(t[("sign", "column")]), cx + 0.7 * r * math.cos(a), cy + 0.7 * r * math.sin(a), r * 0.23, a - math.pi / 2))
    strokes = [arc] + sigil + columns[0] + columns[1]
    sigil_ids = list(range(2, 2 + len(sigil)))
    column_ids = list(range(2 + len(sigil), 2 + len(sigil) + len(columns[0])))
    return strokes, closing, sigil_ids, column_ids, (cx, cy, r)


def read(lua, L):
    res = lua.eval("read_spell")(L)
    return (res[0], res[1]) if isinstance(res, tuple) else (res, None)


def mark(lua, L, ids, kind, key):
    m = lua.table_from({"kind": kind, "key": key})
    for i in ids:
        L[i].mark = m


class MarkedReading(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = load_reader()

    def test_a_mark_decides_what_lines_are(self):
        lua = self.lua
        strokes, closing, sigil, column, _ = fire_seal(lua)
        L = R.lua_strokes(lua, strokes + [closing])
        plain, _ = read(lua, L)
        self.assertEqual(("fire", "column"), (plain.element, plain.form))
        mark(lua, L, sigil, "sigil", "light")
        lit, _ = read(lua, L)
        self.assertEqual("light", lit.element)
        mark(lua, L, column, "sign", "levitation")
        floats, _ = read(lua, L)
        self.assertEqual("light", floats.element)
        self.assertIn("float", floats.summary.lower())
        # a column is no Levitation: the seal is read so, but less precise
        self.assertLess(floats.precision, plain.precision - 0.1)

    def test_a_marked_sigil_is_never_too_faint_its_precision_tells(self):
        # a fire sigil marked as Smoke looks little like it: unmarked, so faint a reading would be "too imprecise"; marked,
        # the seal is no more precise than it
        lua = self.lua
        strokes, closing, sigil, _, _ = fire_seal(lua, seed=5)
        L = R.lua_strokes(lua, strokes + [closing])
        mark(lua, L, sigil, "sigil", "smoke")
        spell, err = read(lua, L)
        self.assertIsNotNone(spell, err)
        self.assertEqual("smoke", spell.element)
        self.assertLess(spell.precision, 0.5)
        tree = lua.eval("parse_seal")(L)
        tree = tree[0] if isinstance(tree, tuple) else tree
        smoke = next(s for s in tree.symbols.values() if s.marked)
        q = (smoke.score - lua.eval("SEAL_MIN_SCORE")) / (lua.eval("SEAL_GOOD_SCORE") - lua.eval("SEAL_MIN_SCORE"))
        self.assertAlmostEqual(round(q, 2), spell.precision, delta=0.011)

    def test_every_sigil_offered_awakens(self):
        # a sigil alone in its ring, marked as any sigil the menu offers - however little like it (under the 35% the
        # symbols' check asks of unmarked ones): it awakens, as precise as the menu said
        lua = self.lua
        t = R.templates(lua)
        offered = lua.eval("seal_mark_readings")
        low = 0
        for seed in range(3):
            random.seed(seed)
            arc, closing, _ = R.prepared_ring()
            sig = R.place(R.hand(t[("sigil", "fire")]), 90, 90, 30)
            L = R.lua_strokes(lua, [arc] + sig + [closing])
            ids = list(range(2, 2 + len(sig)))
            for item in offered(L, lua.table_from([L[i] for i in ids]), 8).values():
                if item.kind != "sigil":
                    continue
                mark(lua, L, ids, "sigil", item.key)
                spell, err = read(lua, L)
                self.assertIsNotNone(spell, f"{item.key}: {err}")
                q = max(0, min(1, (item.score - lua.eval("SEAL_MIN_SCORE")) / (lua.eval("SEAL_GOOD_SCORE") - lua.eval("SEAL_MIN_SCORE"))))
                self.assertLessEqual(spell.precision, round(q, 2) + 0.011)
                low += q < 0.35
        self.assertGreater(low, 0)

    def test_unmarked_lines_read_as_before(self):
        lua = self.lua
        strokes, closing, sigil, _, _ = fire_seal(lua, seed=8)
        L = R.lua_strokes(lua, strokes + [closing])
        before, _ = read(lua, L)
        mark(lua, L, sigil, "sigil", "fire")
        same, _ = read(lua, L)
        self.assertEqual((before.element, before.form), (same.element, same.form))

    def test_readings_offered(self):
        # the circled sigil: its own reading first, signs and sigils it looks like after it, the precision each would give
        lua = self.lua
        strokes, _, sigil, column, _ = fire_seal(lua)
        L = R.lua_strokes(lua, strokes)
        offered = lua.eval("seal_mark_readings")
        items = list(offered(L, lua.table_from([L[i] for i in sigil]), 8).values())
        self.assertEqual(("sigil", "fire"), (items[0].kind, items[0].key))
        self.assertLessEqual(len(items), 8)
        self.assertEqual(sorted((i.score for i in items), reverse=True), [i.score for i in items])
        self.assertTrue(all(i.score >= lua.eval("SEAL_MIN_SCORE") for i in items))
        # a column by the ring, in its pose there (the ring still open)
        items = list(offered(L, lua.table_from([L[i] for i in column]), 8).values())
        self.assertEqual(("sign", "column"), (items[0].kind, items[0].key))

    def test_player_signs_find_their_reading(self):
        # every sign as the wiki and the book's legend draw it (not the legend from before its redraw: players who drew
        # that learned another sign), by hand by the ring: its own reading is offered
        lua = self.lua
        ps.add_book(lua)
        t = R.templates(lua)
        offered = lua.eval("seal_mark_readings")
        rng = random.Random(7)
        found, total, missing = 0, 0, []
        for key, variants in ps.SHAPES.items():
            for variant in variants:
                if variant == "old":
                    continue
                for _ in range(2):
                    random.seed(rng.random())
                    ring, (cx, cy, r) = R.ring()
                    sig = R.place(R.hand(t[("sigil", "fire")]), cx, cy, r * 0.45)
                    a, d = rng.uniform(0, 2 * math.pi), rng.uniform(0.58, 0.76) * r
                    sign = R.place(ps.player_sign(key, variant, rng), cx + d * math.cos(a), cy + d * math.sin(a), r * rng.uniform(0.18, 0.34),
                                   a - math.pi / 2 + math.radians(rng.uniform(-8, 8)), tilt=0)
                    L = R.lua_strokes(lua, [ring] + sig + sign)
                    chosen = lua.table_from([L[i] for i in range(len(sig) + 2, len(sig) + len(sign) + 2)])
                    keys = [i.key for i in offered(L, chosen, 8).values() if i.kind == "sign"]
                    total += 1
                    found += key in keys
                    if key not in keys:
                        missing.append((key, variant))
        self.assertGreaterEqual(found, 0.97 * total, missing)


class KeptMarks(unittest.TestCase):
    def test_marks_as_text(self):
        lua = load_mod()
        L = R.lua_strokes(lua, [[(0, 0), (1, 1)], [(2, 2), (3, 3)], [(4, 4), (5, 5)], [(6, 6), (7, 7)]])
        mark(lua, L, [1, 3], "sign", "pull")
        mark(lua, L, [4], "sigil", "light")
        text = lua.eval("strokes_encode_marks")(L)
        self.assertEqual("sign:pull@1,3;sigil:light@4", text)
        back = lua.eval("strokes_apply_marks")(R.lua_strokes(lua, [[(0, 0)], [(1, 1)], [(2, 2)], [(3, 3)]]), text)
        self.assertEqual("pull", back[1].mark.key)
        self.assertIsNone(back[2].mark)
        self.assertTrue(lua.eval("rawequal")(back[1].mark, back[3].mark))  # one symbol
        # a seal's lighter copy keeps them
        thin = lua.eval("strokes_thin")(L)
        self.assertEqual(text, lua.eval("strokes_encode_marks")(thin))


def lasso(G, pos, k, cx, cy, radius):
    """a loop of the mouse round cx, cy (page units for a 180 page) with the button held, then let go"""
    G.left_down = True
    for i in range(31):
        a = i / 30 * 2 * math.pi
        G.mouse[1], G.mouse[2] = pos.x + (cx + radius * math.cos(a)) * k, pos.y + (cy + radius * math.sin(a)) * k
        G.left_just_down = i == 0
        G.notebook_update()
    G.left_down = G.left_just_down = False
    G.notebook_update()
    G.notebook_update()


def click_row(G, row):
    G.mouse[1], G.mouse[2] = (row.x0 + row.x1) / 2, (row.y0 + row.y1) / 2
    G.left_down = G.left_just_down = True; G.notebook_update(); G.left_just_down = False
    G.notebook_update(); G.left_down = False; G.notebook_update()


def click_ink(G, view):
    G.mouse[1], G.mouse[2] = view.panel.x + 5, view.panel.y + 10
    G.left_down = G.left_just_down = True; G.notebook_update(); G.left_just_down = G.left_down = False; G.notebook_update()


class MarkInTheBook(unittest.TestCase):
    def test_circle_pick_and_close_the_ring(self):
        lua = load_mod()
        lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
        lua.execute(R.CARRY_ALL)
        G = lua.globals()
        R.open_book(G)
        strokes, closing, sigil, _, (cx, cy, r) = fire_seal(lua)
        view, side = G.notebook_view()
        pos, k = view[side], view.size / 180
        R.draw_on_blank(G, strokes[1:] + strokes[:1])  # the symbols, then the ring with its gap
        R.press_button(G, MARK_BUTTON)
        # nothing circled: the book says so
        lasso(G, pos, k, 12, 12, 4)
        self.assertIsNone(lua.eval("BookMarks.menu"))
        self.assertIn("circle", (G.notebook_result() or "").lower())
        # round the sigil: its readings, Fire first
        lasso(G, pos, k, cx, cy, 0.33 * r)
        menu = lua.eval("BookMarks.menu")
        self.assertIsNotNone(menu)
        rows = list(menu.rows.values())
        self.assertEqual(("item", "Fire"), (rows[0].kind, rows[0].text))
        self.assertEqual("cancel", rows[-1].kind)
        flicker = next(row for row in rows if row.item and row.item.key == "flicker")
        click_row(G, flicker)
        self.assertIsNone(lua.eval("BookMarks.menu"))
        self.assertTrue(G.globals["witch_notebook.seal_1_marks"].startswith("sigil:flicker@"))
        # the pen again: the ring closed, the seal is read with the mark
        G.mouse[1], G.mouse[2] = view.panel.x + 5, view.panel.y + 10
        G.left_down = G.left_just_down = True; G.notebook_update(); G.left_just_down = G.left_down = False; G.notebook_update()
        G.left_down = True
        for x, y in closing:
            G.mouse[1], G.mouse[2] = pos.x + x * k, pos.y + y * k
            G.notebook_update()
        G.left_down = False; G.notebook_update()
        self.assertEqual(1, R.seal_count(G))
        self.assertIn("element=flicker", G.globals["witch_notebook.seal_1_spell"])
        # a new run of the save: the page keeps its marks
        lua2 = load_mod()
        G2 = lua2.globals()
        for key, value in G.globals.items():
            G2.globals[key] = value
        page = lua2.eval("BookStore.load")("book").seals[1]
        self.assertEqual(len(sigil), sum(1 for s in page.strokes.values() if s.mark and s.mark.key == "flicker"))

    def test_mark_opens_a_drawn_seal(self):
        # a seal that awoke misread: "Mark" opens nothing itself, a click with it on the seal opens it again to mark its
        # lines - the lasso begins with that click; the pick awakens it again
        lua = load_mod()
        lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
        lua.execute(R.CARRY_ALL)
        G = lua.globals()
        R.open_book(G)
        strokes, closing, sigil, _, (cx, cy, r) = fire_seal(lua, seed=6)
        view, side = G.notebook_view()
        pos, k = view[side], view.size / 180
        R.draw_on_blank(G, strokes[1:] + strokes[:1] + [closing])
        self.assertEqual(1, R.seal_count(G))
        self.assertEqual("1", G.globals["witch_notebook.active"])
        R.press_button(G, MARK_BUTTON)
        self.assertEqual("", G.globals["witch_notebook.seal_1_draft"])
        lasso(G, pos, k, cx, cy, 0.33 * r)
        self.assertEqual("1", G.globals["witch_notebook.seal_1_draft"])
        rows = list(lua.eval("BookMarks.menu").rows.values())
        click_row(G, next(row for row in rows if row.item and row.item.key == "flicker"))
        self.assertEqual("", G.globals["witch_notebook.seal_1_draft"])
        self.assertIn("element=flicker", G.globals["witch_notebook.seal_1_spell"])
        # drawn again: a click-and-loop with "Mark" on it
        lasso(G, pos, k, cx, cy, 0.33 * r)
        self.assertEqual("1", G.globals["witch_notebook.seal_1_draft"])
        self.assertIsNotNone(lua.eval("BookMarks.menu"))

    def test_a_seal_opened_and_left_as_it_was_awakens_again(self):
        # "Mark" opens the active seal; nothing is marked (Cancel), an ink is chosen: it stays open to be drawn on; the
        # book put away, it is awake and active as before. One marked and left unawakened stays a draft.
        lua = load_mod()
        lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
        lua.execute(R.CARRY_ALL)
        G = lua.globals()
        R.open_book(G)
        strokes, closing, sigil, _, (cx, cy, r) = fire_seal(lua, seed=6)
        view, side = G.notebook_view()
        pos, k = view[side], view.size / 180
        R.draw_on_blank(G, strokes[1:] + strokes[:1] + [closing])
        spell = G.globals["witch_notebook.seal_1_spell"]
        R.press_button(G, MARK_BUTTON)
        lasso(G, pos, k, cx, cy, 0.33 * r)
        self.assertEqual("1", G.globals["witch_notebook.seal_1_draft"])
        self.assertEqual("0", G.globals["witch_notebook.active"])
        click_row(G, list(lua.eval("BookMarks.menu").rows.values())[-1])  # Cancel
        click_ink(G, view)
        self.assertEqual("1", G.globals["witch_notebook.seal_1_draft"])
        R.toggle_book(G)
        self.assertEqual("", G.globals["witch_notebook.seal_1_draft"])
        self.assertEqual("1", G.globals["witch_notebook.active"])
        self.assertEqual(spell, G.globals["witch_notebook.seal_1_spell"])
        # put back, the seal under the mouse tells its parts (Mark dropped them)
        R.open_book(G, to_blank=False)
        G.mouse[1], G.mouse[2] = pos.x + cx * k, pos.y + cy * k
        G.notebook_update()
        # opened again: RMB closes the menu
        R.press_button(G, MARK_BUTTON)
        lasso(G, pos, k, cx, cy, 0.33 * r)
        G.right_down = G.right_just_down = True; G.notebook_update(); G.right_just_down = G.right_down = False
        self.assertIsNone(lua.eval("BookMarks.menu"))
        G.notebook_update()
        # marked as a sign in the middle: no element sigil, it stays a draft; the book put away, still one
        lasso(G, pos, k, cx, cy, 0.33 * r)
        rows = list(lua.eval("BookMarks.menu").rows.values())
        click_row(G, next(row for row in rows if row.item and row.item.kind == "sign"))
        self.assertEqual("1", G.globals["witch_notebook.seal_1_draft"])
        R.toggle_book(G)
        self.assertEqual("1", G.globals["witch_notebook.seal_1_draft"])
        # the menu open, one click on an ink closes it and takes the pen: the button held on the page draws, no lasso
        R.open_book(G, to_blank=False)
        R.press_button(G, MARK_BUTTON)
        lasso(G, pos, k, cx, cy, 0.33 * r)
        self.assertIsNotNone(lua.eval("BookMarks.menu"))
        click_ink(G, view)
        self.assertIsNone(lua.eval("BookMarks.menu"))
        G.left_down = True
        for t in range(5):
            G.mouse[1], G.mouse[2] = pos.x + (cx + t) * k, pos.y + cy * k
            G.notebook_update()
        self.assertIsNone(lua.eval("BookMarks.lasso"))
        G.left_down = False; G.notebook_update()

    def test_erase_then_a_press_opens_a_drawn_seal(self):
        # an ink or Erase chosen opens nothing; with the eraser a press on the drawn seal opens it as [edit] does, the
        # press erasing on it at once. Opened and left as it was, the book put away, it is awake and active again.
        lua = load_mod()
        lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
        lua.execute(R.CARRY_ALL)
        G = lua.globals()
        R.open_book(G)
        strokes, closing, sigil, columns, (cx, cy, r) = fire_seal(lua, seed=6)
        view, side = G.notebook_view()
        pos, k = view[side], view.size / 180
        R.draw_on_blank(G, strokes[1:] + strokes[:1] + [closing])
        click_ink(G, view)
        R.press_button(G, ERASE_BUTTON)
        self.assertEqual("", G.globals["witch_notebook.seal_1_draft"])
        # a press on an empty spot: open, nothing erased; put back with the book
        G.mouse[1], G.mouse[2] = pos.x + (cx - 0.6 * r) * k, pos.y + (cy + 0.6 * r) * k
        G.left_down = G.left_just_down = True; G.notebook_update(); G.left_just_down = G.left_down = False; G.notebook_update()
        self.assertEqual("1", G.globals["witch_notebook.seal_1_draft"])
        self.assertEqual("0", G.globals["witch_notebook.active"])
        R.toggle_book(G)
        self.assertEqual("", G.globals["witch_notebook.seal_1_draft"])
        self.assertEqual("1", G.globals["witch_notebook.active"])
        # pressed on a column's line and along it: erased
        R.open_book(G, to_blank=False)
        R.press_button(G, ERASE_BUTTON)  # the book opens with the pen
        before = G.globals["witch_notebook.seal_1_strokes"]
        G.left_down = G.left_just_down = True
        for x, y in strokes[columns[0] - 1]:
            G.mouse[1], G.mouse[2] = pos.x + x * k, pos.y + y * k
            G.notebook_update()
            G.left_just_down = False
        G.left_down = False; G.notebook_update()
        self.assertEqual("1", G.globals["witch_notebook.seal_1_draft"])
        self.assertNotEqual(before, G.globals["witch_notebook.seal_1_strokes"])

    def test_rmb_drawn_across_a_seal_opens_it(self):
        # RMB clicked on a drawn seal leaves it be; held and drawn along a line of it, the seal opens and the line is
        # erased from where it was pressed
        lua = load_mod()
        lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
        lua.execute(R.CARRY_ALL)
        G = lua.globals()
        R.open_book(G)
        strokes, closing, sigil, columns, (cx, cy, r) = fire_seal(lua, seed=6)
        view, side = G.notebook_view()
        pos, k = view[side], view.size / 180
        R.draw_on_blank(G, strokes[1:] + strokes[:1] + [closing])
        before = G.globals["witch_notebook.seal_1_strokes"]
        x, y = strokes[columns[0] - 1][0]
        G.mouse[1], G.mouse[2] = pos.x + x * k, pos.y + y * k
        G.right_down = G.right_just_down = True; G.notebook_update(); G.right_just_down = G.right_down = False; G.notebook_update()
        self.assertEqual("", G.globals["witch_notebook.seal_1_draft"])
        self.assertEqual(before, G.globals["witch_notebook.seal_1_strokes"])
        G.right_down = G.right_just_down = True
        for x, y in strokes[columns[0] - 1]:
            G.mouse[1], G.mouse[2] = pos.x + x * k, pos.y + y * k
            G.notebook_update()
            G.right_just_down = False
        G.right_down = False; G.notebook_update()
        self.assertEqual("1", G.globals["witch_notebook.seal_1_draft"])
        self.assertNotEqual(before, G.globals["witch_notebook.seal_1_strokes"])

    def test_a_line_drawn_on_a_seal_opens_it(self):
        # with the pen a click on a drawn seal chooses it and leaves it be; a line drawn on from it opens it as [edit]
        # does, the line begun where it was pressed
        lua = load_mod()
        lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
        lua.execute(R.CARRY_ALL)
        G = lua.globals()
        R.open_book(G)
        strokes, closing, sigil, columns, (cx, cy, r) = fire_seal(lua, seed=6)
        view, side = G.notebook_view()
        pos, k = view[side], view.size / 180
        R.draw_on_blank(G, strokes[1:] + strokes[:1] + [closing])
        lines = G.globals["witch_notebook.seal_1_strokes"].count("|") + 1
        x0, y0 = cx - 0.6 * r, cy + 0.6 * r
        G.mouse[1], G.mouse[2] = pos.x + x0 * k, pos.y + y0 * k
        G.left_down = G.left_just_down = True; G.notebook_update(); G.left_just_down = G.left_down = False; G.notebook_update()
        self.assertEqual("", G.globals["witch_notebook.seal_1_draft"])
        self.assertEqual("1", G.globals["witch_notebook.active"])
        G.left_down = G.left_just_down = True
        for t in range(10):
            G.mouse[1], G.mouse[2] = pos.x + (x0 + 2 * t) * k, pos.y + y0 * k
            G.notebook_update()
            G.left_just_down = False
            if t == 3:
                self.assertEqual("1", G.globals["witch_notebook.seal_1_draft"])
        G.left_down = False; G.notebook_update()
        self.assertEqual(lines + 1, G.globals["witch_notebook.seal_1_strokes"].count("|") + 1)
        x, y = map(float, G.globals["witch_notebook.seal_1_strokes"].split("|")[-1].split(" ")[0].split(","))
        self.assertLess(math.dist((x, y), (x0 * k, y0 * k)), 1)

    def test_marked_lines_shown_again_and_unmarked(self):
        lua = load_mod()
        lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
        lua.execute(R.CARRY_ALL)
        G = lua.globals()
        R.open_book(G)
        strokes, _, sigil, _, (cx, cy, r) = fire_seal(lua, seed=4)
        view, side = G.notebook_view()
        pos, k = view[side], view.size / 180
        R.draw_on_blank(G, strokes[1:] + strokes[:1])
        R.press_button(G, MARK_BUTTON)
        lasso(G, pos, k, cx, cy, 0.33 * r)
        rows = list(lua.eval("BookMarks.menu").rows.values())
        click_row(G, next(row for row in rows if row.item and row.item.key == "flicker"))
        # a click on the marked lines: their readings again, the one marked starred, the book's own reading back
        x, y = strokes[sigil[0] - 1][len(strokes[sigil[0] - 1]) // 2]
        G.mouse[1], G.mouse[2] = pos.x + x * k, pos.y + y * k
        G.left_down = True; G.notebook_update(); G.left_down = False; G.notebook_update(); G.notebook_update()
        rows = list(lua.eval("BookMarks.menu").rows.values())
        self.assertIn("* Flickering Light", [row.text for row in rows])
        unmark = next(row for row in rows if row.kind == "unmark")
        click_row(G, unmark)
        self.assertEqual("", G.globals["witch_notebook.seal_1_marks"])
        # erased in part, a marked line's pieces stay marked
        lasso(G, pos, k, cx, cy, 0.33 * r)
        rows = list(lua.eval("BookMarks.menu").rows.values())
        other = next(row for row in rows if row.item and row.item.key != "fire")
        click_row(G, other)
        x, y = strokes[sigil[0] - 1][len(strokes[sigil[0] - 1]) // 2]
        G.mouse[1], G.mouse[2] = pos.x + x * k, pos.y + y * k
        G.right_down = True; G.notebook_update(); G.right_down = False; G.notebook_update()
        marks = G.globals["witch_notebook.seal_1_marks"]
        self.assertTrue(marks.startswith(f"{other.item.kind}:{other.item.key}@"), marks)
        self.assertGreater(len(marks.split("@")[1].split(",")), len(sigil))
        # erased but for a scrap by the first line's start: no longer what it was marked as, the mark is gone
        ax, ay = strokes[sigil[0] - 1][0]
        reach = 2.5 * 6 / k  # notebook.lua ERASER_RADIUS, page units of a 180 page
        for index in sigil:
            G.right_down = True
            for x, y in strokes[index - 1]:
                if (x - ax) ** 2 + (y - ay) ** 2 > reach ** 2:
                    G.mouse[1], G.mouse[2] = pos.x + x * k, pos.y + y * k
                    G.notebook_update()
            G.right_down = False; G.notebook_update()
        self.assertEqual("", G.globals["witch_notebook.seal_1_marks"])


if __name__ == "__main__":
    unittest.main()
