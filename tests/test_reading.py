"""Reading a seal in the background (book_reading.lua): the book reads a drawing a share of each frame - the page open to
drawing, erasing and turning meanwhile - and reads it as it would at once. A reading of a drawing changed since is given
up; any change to a drawing whose ring is closed reads it again - a line drawn, a piece erased. A reading goes on with the
book shut or another one open; pages read in turn; a page left being read when the game is saved is read as its book
opens; a saved seal's parts are read in the background; a mistake in a reading is told, not left hanging.

The tests' clock goes on a millisecond each time it is looked at (SLOW_CLOCK): a reading pauses every few templates and
takes hundreds of frames. Without a clock (the other tests) a reading runs through in the frame.

Run with python tests/test_reading.py.
"""
import json
import math
import os
import random
import sys
import time
import unittest

from lupa.luajit21 import LuaError

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_tests as R  # noqa: E402
from harness import MOD, load_mod  # noqa: E402

SLOW_CLOCK = """
clock_t, clock_step = 0, 0.001
function GameGetRealWorldTimeSinceStarted() clock_t = clock_t + clock_step return clock_t end
"""
TEXTS = """
texts = {}
function GuiText( g, x, y, str ) texts[#texts + 1] = str end
"""
SAME = "function( a, b ) return rawequal( a, b ) end"
CLEAR, TRY = 900099, 900098      # notebook.lua BUTTON.CLEAR, BUTTON.RETRY
QUIRE_TAB = 900100 + 1           # BUTTON.BOOK + the Palm Quire's place on BOOK_SHELF
TURN_ON = 7                      # D


def runtime(slow=True, grimoire=False, carry_all=False):
    lua = load_mod()
    if grimoire:
        lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
    if carry_all:
        lua.execute(R.CARRY_ALL)
    if slow:
        lua.execute(SLOW_CLOCK)
    return lua, lua.globals()


def waiting(lua):
    return lua.eval("BookReading.waiting()")


def settle(lua, G, limit=60000):
    """frames until nothing waits to be read"""
    frames = 0
    while waiting(lua) > 0:
        G.notebook_update()
        frames += 1
        assert frames < limit, "the reading never ends"
    return frames


def pen(G, x0, strokes):
    """strokes (page units of a 180 page) drawn on the page whose left edge is x0, a frame a point"""
    for stroke in strokes:
        G.left_down = True
        for x, y in stroke:
            G.mouse[1], G.mouse[2] = x0 + x, R.PAGE_Y + y
            G.notebook_update()
        G.left_down = False
        G.notebook_update()


def rub(G, x0, points):
    """RMB held along the points"""
    G.right_down = True
    for x, y in points:
        G.mouse[1], G.mouse[2] = x0 + x, R.PAGE_Y + y
        G.notebook_update()
    G.right_down = False
    G.notebook_update()


def page(lua, i, key="book"):
    return lua.eval("BookStore.load")(key).seals[i]


def records(G):
    return int(G.globals["witch_notebook.debug_next"] or 0)


def fire_seal(lua, seed):
    """a fire sigil and two columns in a ring left open; the stroke that closes it; the ring"""
    random.seed(seed)
    arc, closing, (cx, cy, r) = R.prepared_ring()
    t = R.templates(lua)
    symbols = R.place(R.hand(t[("sigil", "fire")]), cx, cy, r * 0.45)
    for deg in (0, 180):
        a = math.radians(deg)
        symbols += R.place(R.hand(t[("sign", "column")]), cx + 0.7 * r * math.cos(a), cy + 0.7 * r * math.sin(a), r * 0.23, a - math.pi / 2)
    return [arc] + symbols, closing, (cx, cy, r)


class ReadingInTheBook(unittest.TestCase):
    def test_a_closed_ring_awakens_frames_later_as_read_at_once(self):
        lua0, G0 = runtime(slow=False)
        R.open_book(G0)
        drawing, closing, _ = fire_seal(lua0, 3)
        pen(G0, R.LEFT_X, drawing + [closing])
        at_once = G0.globals["witch_notebook.seal_1_spell"]
        self.assertTrue(at_once)

        lua, G = runtime()
        R.open_book(G)
        drawing, closing, _ = fire_seal(lua, 3)
        pen(G, R.LEFT_X, drawing)
        before = records(G)
        pen(G, R.LEFT_X, [closing])
        # the ring closed: read in the background, the page says so
        draft = page(lua, 1)
        self.assertEqual(0, R.seal_count(G))
        self.assertTrue(lua.eval("BookReading.reading")(draft))
        self.assertEqual("1", G.globals["witch_notebook.seal_1_reading"])
        lua.execute(TEXTS)
        G.notebook_update()
        self.assertIn("Reading the seal...", list(G.texts.values()))
        frames = settle(lua, G)
        self.assertGreater(frames, 20)
        self.assertEqual(1, R.seal_count(G))
        self.assertEqual(at_once, G.globals["witch_notebook.seal_1_spell"])
        self.assertEqual("1", G.globals["witch_notebook.active"])
        self.assertEqual("", G.globals["witch_notebook.seal_1_reading"])
        self.assertEqual(before + 1, records(G))
        # the pen left the awoken page
        self.assertFalse(lua.eval(SAME)(lua.eval("BookStore.load( 'book' ).edit"), draft))
        G.texts = lua.table()
        G.notebook_update()
        self.assertNotIn("Reading the seal...", list(G.texts.values()))

    def test_a_line_drawn_while_reading_reads_again(self):
        lua, G = runtime()
        R.open_book(G)
        drawing, closing, (cx, cy, r) = fire_seal(lua, 5)
        pen(G, R.LEFT_X, drawing)
        before = records(G)
        pen(G, R.LEFT_X, [closing])
        for _ in range(5):
            G.notebook_update()
        self.assertEqual(1, waiting(lua))
        # a third column, while the book reads
        t = R.templates(lua)
        a = math.radians(90)
        column = R.place(R.hand(t[("sign", "column")]), cx + 0.7 * r * math.cos(a), cy + 0.7 * r * math.sin(a), r * 0.23, a - math.pi / 2)
        pen(G, R.LEFT_X, column)
        settle(lua, G)
        # only the drawing as it is now was read to the end
        self.assertEqual(before + 1, records(G))
        self.assertEqual(1, R.seal_count(G))
        self.assertEqual(len(drawing) + 1 + len(column), G.globals["witch_notebook.seal_1_strokes"].count("|") + 1)

    def test_lines_marked_while_reading_read_again(self):
        import test_marks as TM
        lua, G = runtime()
        G.clock_step = 0.004
        R.open_book(G)
        view, side = G.notebook_view()
        pos, k = view[side], view.size / 180
        drawing, closing, (cx, cy, r) = fire_seal(lua, 3)
        pen(G, R.LEFT_X, drawing)
        before = records(G)
        pen(G, R.LEFT_X, [closing])
        R.press_button(G, TM.MARK_BUTTON)
        TM.lasso(G, pos, k, cx, cy, 0.33 * r)  # round the sigil, the book still reading
        self.assertEqual(1, waiting(lua))
        rows = list(lua.eval("BookMarks.menu").rows.values())
        TM.click_row(G, next(row for row in rows if row.item and row.item.key == "flicker"))
        settle(lua, G)
        self.assertEqual(before + 1, records(G))
        self.assertIn("element=flicker", G.globals["witch_notebook.seal_1_spell"])

    def test_erasing_the_ring_open_while_reading_gives_it_up(self):
        lua, G = runtime()
        R.open_book(G)
        drawing, closing, _ = fire_seal(lua, 5)
        pen(G, R.LEFT_X, drawing)
        before = records(G)
        pen(G, R.LEFT_X, [closing])
        for _ in range(5):
            G.notebook_update()
        rub(G, R.LEFT_X, closing[10:20])
        settle(lua, G)
        self.assertEqual(before, records(G))
        self.assertEqual(0, R.seal_count(G))
        self.assertEqual("", G.globals["witch_notebook.seal_1_reading"])
        self.assertFalse(lua.eval("BookReading.reading")(page(lua, 1)))

    def test_erasing_reads_a_closed_ring_again(self):
        # a stray zigzag in the ring: the seal fails; erased, the seal is read again and awakens
        lua, G = runtime(slow=False)
        R.open_book(G)
        drawing, closing, (cx, cy, r) = fire_seal(lua, 3)
        ax, ay = cx, cy - 0.6 * r
        zigzag = R.densify([(ax - 9 + 18 * i / 12 + (3 if i % 2 else -3) * 0.3, ay + (5 if i % 2 else -5) + (i % 3)) for i in range(13)])
        pen(G, R.LEFT_X, drawing + [zigzag, closing])
        failed = records(G)
        self.assertEqual(0, R.seal_count(G))
        self.assertIn("not recognized", G.notebook_result() or "")
        rub(G, R.LEFT_X, zigzag)
        self.assertEqual(failed + 1, records(G))
        self.assertEqual(1, R.seal_count(G))
        self.assertTrue(G.globals["witch_notebook.seal_1_spell"].startswith("element=fire;form=column;"))

    def test_pages_turned_and_drawn_on_while_reading(self):
        lua, G = runtime()
        G.clock_step = 0.004  # a frame reads a few templates only: the reading outlasts the turning
        R.open_book(G)
        drawing, closing, _ = fire_seal(lua, 8)
        pen(G, R.LEFT_X, drawing + [closing])
        # on to the next pair of blank pages, and a line drawn there while the seal on page 3 is read
        G.pressed[TURN_ON] = True; G.notebook_update(); G.pressed[TURN_ON] = False
        for _ in range(60):
            G.notebook_update()
        self.assertEqual(1, waiting(lua))
        view, side = G.notebook_view()
        self.assertEqual("back", side)
        pen(G, R.LEFT_X, [[(40 + i, 100) for i in range(30)]])
        settle(lua, G)
        self.assertEqual("", G.globals["witch_notebook.seal_1_draft"])
        self.assertEqual("1", G.globals["witch_notebook.active"])
        # the book stays where it was turned, the pen on the page drawn on there
        self.assertEqual("1", G.globals["witch_notebook.seal_3_draft"])
        self.assertTrue(G.globals["witch_notebook.seal_3_strokes"])
        pen(G, R.LEFT_X, [[(40 + i, 120) for i in range(30)]])
        self.assertEqual(2, G.globals["witch_notebook.seal_3_strokes"].count("|") + 1)

    def test_turned_away_the_book_tells_what_became_of_it(self):
        lua, G = runtime()
        G.clock_step = 0.004
        R.open_book(G)
        drawing, closing, (cx, cy, r) = fire_seal(lua, 3)
        pen(G, R.LEFT_X, drawing + [closing])
        G.pressed[TURN_ON] = True; G.notebook_update(); G.pressed[TURN_ON] = False
        settle(lua, G)
        lua.execute(TEXTS)
        G.notebook_update()
        self.assertTrue(any(str(t).endswith("awakens on its page.") for t in G.texts.values()))
        # one that fails: a stray zigzag in it
        drawing, closing, (cx, cy, r) = fire_seal(lua, 5)
        ax, ay = cx, cy - 0.6 * r
        zigzag = R.densify([(ax - 9 + 18 * i / 12 + (3 if i % 2 else -3) * 0.3, ay + (5 if i % 2 else -5) + (i % 3)) for i in range(13)])
        pen(G, R.LEFT_X, drawing + [zigzag, closing])
        G.pressed[TURN_ON] = True; G.notebook_update(); G.pressed[TURN_ON] = False
        settle(lua, G)
        G.texts = lua.table()
        G.notebook_update()
        self.assertIn("A seal drawn before does not awaken: a sign inside the ring is not recognized.", list(G.texts.values()))

    def test_a_page_torn_out_before_the_one_read(self):
        lua, G = runtime()
        R.open_book(G)
        first, first_closing, _ = fire_seal(lua, 3)
        pen(G, R.LEFT_X, first + [first_closing])
        settle(lua, G)
        second, second_closing, _ = fire_seal(lua, 5)
        pen(G, R.RIGHT_X, second + [second_closing])
        self.assertEqual(1, waiting(lua))
        R.press_button(G, 900005)  # "tear out" under the left page, twice
        R.press_button(G, 900005)
        self.assertEqual("1", G.globals["witch_notebook.seal_1_draft"])  # the page being read moved up
        settle(lua, G)
        self.assertEqual(1, R.seal_count(G))
        self.assertEqual("", G.globals["witch_notebook.seal_1_draft"])
        self.assertEqual("1", G.globals["witch_notebook.active"])

    def test_the_book_shut_while_reading(self):
        lua, G = runtime()
        R.open_book(G)
        drawing, closing, _ = fire_seal(lua, 3)
        pen(G, R.LEFT_X, drawing + [closing])
        R.toggle_book(G)
        self.assertEqual(1, waiting(lua))
        settle(lua, G)
        self.assertEqual(1, R.seal_count(G))
        self.assertEqual("1", G.globals["witch_notebook.active"])
        self.assertEqual(G.globals["witch_notebook.seal_1_spell"], G.globals["witch_notebook.active_spell"])
        self.assertTrue(G.component_values["item_name"].startswith("Spellbook: Fire"))

    def test_another_book_opened_while_reading(self):
        lua, G = runtime(carry_all=True)
        R.open_book(G)
        drawing, closing, _ = fire_seal(lua, 3)
        pen(G, R.LEFT_X, drawing + [closing])
        G.buttons[QUIRE_TAB] = True; G.notebook_update(); G.buttons[QUIRE_TAB] = False
        self.assertEqual("quire", G.globals["witch_notebook.open_book"])
        settle(lua, G)
        self.assertEqual(1, R.seal_count(G))
        self.assertEqual("1", G.globals["witch_notebook.active"])
        self.assertIsNone(G.globals["witch_notebook.quire.seal_1_spell"])
        # the Spellbook's pen went on to its blank page
        self.assertTrue(lua.eval(SAME)(lua.eval("BookStore.load( 'book' ).edit"), lua.eval("BookStore.load( 'book' ).blank")))

    def test_two_pages_read_in_turn(self):
        lua, G = runtime()
        R.open_book(G)
        left, left_closing, _ = fire_seal(lua, 3)
        right, right_closing, _ = fire_seal(lua, 5)
        lua.execute("order = {} local apply = BookReading.on_read BookReading.on_read = function( job, out ) order[#order + 1] = job.index apply( job, out ) end")
        pen(G, R.LEFT_X, left)
        pen(G, R.RIGHT_X, right)
        before = records(G)
        pen(G, R.LEFT_X, [left_closing])
        pen(G, R.RIGHT_X, [right_closing])
        self.assertEqual(2, waiting(lua))
        settle(lua, G)
        self.assertEqual(before + 2, records(G))
        self.assertEqual(2, R.seal_count(G))
        self.assertEqual([1, 2], list(G.order.values()))
        self.assertEqual("2", G.globals["witch_notebook.active"])  # the last one read

    def test_cleared_while_reading(self):
        lua, G = runtime()
        R.open_book(G)
        drawing, closing, _ = fire_seal(lua, 3)
        pen(G, R.LEFT_X, drawing)
        before = records(G)
        pen(G, R.LEFT_X, [closing])
        R.press_button(G, CLEAR)
        settle(lua, G)
        self.assertEqual(before, records(G))
        self.assertEqual(0, R.seal_count(G))
        self.assertEqual("", G.globals["witch_notebook.seal_1_strokes"])
        self.assertEqual("", G.globals["witch_notebook.seal_1_reading"])

    def test_try_seal_while_reading_reads_once(self):
        lua, G = runtime()
        R.open_book(G)
        drawing, closing, _ = fire_seal(lua, 3)
        pen(G, R.LEFT_X, drawing)
        before = records(G)
        pen(G, R.LEFT_X, [closing])
        R.press_button(G, TRY)
        R.press_button(G, TRY)
        settle(lua, G)
        self.assertEqual(before + 1, records(G))
        self.assertEqual(1, R.seal_count(G))

    def test_a_page_being_read_when_saved_is_read_as_its_book_opens(self):
        lua, G = runtime()
        R.open_book(G)
        drawing, closing, _ = fire_seal(lua, 3)
        pen(G, R.LEFT_X, drawing + [closing])
        self.assertEqual("1", G.globals["witch_notebook.seal_1_reading"])
        # saved now: a fresh Lua state with the same globals - the reading lost with the old one
        lua2, N = runtime()
        for k, v in G.globals.items():
            N.globals[k] = v
        R.open_book(N, to_blank=False)
        settle(lua2, N)
        self.assertEqual(1, R.seal_count(N))
        self.assertEqual("1", N.globals["witch_notebook.active"])
        # a page saved waiting with its ring open since: not read, no longer waiting
        lua3, O = runtime()
        for k, v in G.globals.items():
            O.globals[k] = v
        O.globals["witch_notebook.seal_1_strokes"] = "|".join(G.globals["witch_notebook.seal_1_strokes"].split("|")[:-1])
        R.open_book(O, to_blank=False)
        self.assertEqual(0, waiting(lua3))
        self.assertEqual("", O.globals["witch_notebook.seal_1_reading"])

    def test_a_saved_seal_tells_its_parts_after_a_while(self):
        lua, G = runtime(slow=False)
        R.open_book(G)
        drawing, closing, (cx, cy, r) = fire_seal(lua, 3)
        pen(G, R.LEFT_X, drawing + [closing])
        R.toggle_book(G)
        lua2, N = runtime()
        for k, v in G.globals.items():
            N.globals[k] = v
        R.open_book(N, to_blank=False)
        seal = page(lua2, 1)
        parts_known = lua2.eval("function( s ) return s.parts ~= nil and s.parts_of == s.strokes end")
        N.mouse[1], N.mouse[2] = R.LEFT_X + cx, R.PAGE_Y + cy
        N.notebook_update()
        self.assertFalse(parts_known(seal))  # not read in the frame the mouse came over it
        frames = 0
        while not parts_known(seal):
            N.notebook_update()
            frames += 1
            self.assertLess(frames, 60000)
        self.assertGreater(frames, 20)
        self.assertGreater(len(seal.parts), 0)

    def test_a_mistake_in_a_reading_is_told(self):
        lua, G = runtime()
        R.open_book(G)
        drawing, closing, _ = fire_seal(lua, 3)
        pen(G, R.LEFT_X, drawing)
        lua.execute("real_read_spell = read_spell function read_spell( s ) recognizer_pause( 100 ) error( 'broken on purpose' ) end")
        G.left_down = True
        for x, y in closing:
            G.mouse[1], G.mouse[2] = R.LEFT_X + x, R.PAGE_Y + y
            G.notebook_update()
        G.left_down = False
        with self.assertRaises(LuaError) as raised:
            G.notebook_update()  # the reading starts as the ring closes, and fails at once
        self.assertIn("broken on purpose", str(raised.exception))
        self.assertEqual(0, waiting(lua))
        self.assertEqual("The book could not read this drawing", G.notebook_result())
        self.assertEqual("", G.globals["witch_notebook.seal_1_reading"])
        self.assertIn("broken on purpose", G.globals["witch_notebook.debug_" + str(records(G))])
        # mended, the next change reads it
        lua.execute("read_spell = real_read_spell")
        R.press_button(G, TRY)
        settle(lua, G)
        self.assertEqual(1, R.seal_count(G))


class ReadingSpreadOverFrames(unittest.TestCase):
    def test_sliced_readings_read_as_at_once(self):
        # the drawings from the game, each read a few templates a frame and read in one go: the same
        lua, G = runtime(grimoire=True)
        seals = json.load(open(os.path.join(MOD, "tests", "data", "player_seals.json"), encoding="utf-8"))
        lua.execute("""
            got = {}
            BookReading.on_read = function( job, out )
                got[#got + 1] = out.spell and ( out.spell.data or serialize_spell( out.spell ) ) or ( "fails: " .. tostring( out.err ) )
            end
            function read_page( list )
                local st = BookStore.load( "book" )
                local page = { strokes = {}, point_count = 0, draft = "1", sheet = "" }
                for i, text in ipairs( list ) do
                    page.strokes[i] = strokes_decode( text )[1]
                    page.point_count = page.point_count + #page.strokes[i]
                end
                st.seals[#st.seals + 1] = page
                BookReading.read( st, page )
                local steps = 0
                while BookReading.waiting() > 0 do BookReading.step( false ) steps = steps + 1 end
                return steps
            end
        """)
        slow = lua.eval("GameGetRealWorldTimeSinceStarted")
        sliced, steps = [], []
        for e in seals:
            steps.append(G.read_page(lua.table_from(e["strokes"])))
            sliced.append(G.got[len(sliced) + 1])
        G.GameGetRealWorldTimeSinceStarted = None
        for e in seals:
            self.assertEqual(1, G.read_page(lua.table_from(e["strokes"])))
        at_once = [G.got[len(seals) + i + 1] for i in range(len(seals))]
        G.GameGetRealWorldTimeSinceStarted = slow
        for e, a, b in zip(seals, sliced, at_once):
            self.assertEqual(b, a, e["name"])
        self.assertGreater(min(steps), 3)

    def test_frames_stay_short(self):
        # the slowest drawing from the game, read with the real clock: the book open, no frame takes long
        lua, G = runtime(slow=False, grimoire=True)
        G.py_clock = time.perf_counter
        lua.execute("function GameGetRealWorldTimeSinceStarted() return py_clock() end")
        R.open_book(G)
        lua.execute("SealRead.template_sets() seal_canon_prepare()")  # made before the first reading (BookReading.prepare)
        seals = json.load(open(os.path.join(MOD, "tests", "data", "player_seals.json"), encoding="utf-8"))
        heavy = next(e for e in seals if e["name"] == "wind and 4 turned columns")
        lua.execute("""
            function as_draft( list )
                local st = BookStore.load( "book" )
                local page = { strokes = {}, point_count = 0, draft = "1", sheet = "" }
                for i, text in ipairs( list ) do
                    page.strokes[i] = strokes_decode( text )[1]
                    page.point_count = page.point_count + #page.strokes[i]
                end
                return st, page
            end
        """)
        st, draft = G.as_draft(lua.table_from(heavy["strokes"]))
        started = time.perf_counter()
        lua.eval("read_spell")(draft.strokes)
        at_once = time.perf_counter() - started
        st.seals[len(st.seals) + 1] = draft
        lua.eval("BookReading.read")(st, draft)
        longest, frames = 0, 0
        while waiting(lua) > 0:
            started = time.perf_counter()
            G.notebook_update()
            longest = max(longest, time.perf_counter() - started)
            frames += 1
        print(f"\n  read at once: {at_once * 1000:.0f} ms; in the background: {frames} frames, the longest {longest * 1000:.1f} ms")
        self.assertGreater(frames, 20)
        self.assertLess(longest, 0.05)


if __name__ == "__main__":
    unittest.main()
