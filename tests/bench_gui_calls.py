"""How many GUI images the open book draws a frame for one page of a seal (book_draw.lua D.strokes): the audit's
measure (AUDIT 2026-10-21, P1) - every dot of a line was an image of its own.

    python tests/bench_gui_calls.py        (needs lupa, Pillow, numpy and the game's font, as render_book.py)

Prints, for pages of the wiki's seals pasted in from sheets and for the grimoire's pages, the images drawn a frame for
the spread showing them, less what the same spread draws with the page empty.
"""
import os
import statistics
import sys
import warnings

warnings.simplefilter("ignore")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_book as RB  # noqa: E402
import run_tests as R  # noqa: E402


def images(book):
    return sum(1 for d in book.frame() if d["kind"] == "image")


def sheet_page(key, book_key, turn_to_it):
    """images a frame for the spread with the sheet 'key' pasted into 'book_key', less the same spread before"""
    book = RB.Book()
    book.lua.execute(RB.CARRY_ALL)
    G = book.g
    R.open_book(G)
    if book_key != "book":
        RB.switch_book(G, book_key)
        for _ in range(80): G.notebook_update()
    G.mouse[1], G.mouse[2] = 0, 0
    G.globals["witch_notebook.pending_sheets"] = key + ":ink;"
    for _ in range(3): G.notebook_update()
    turn_to_it(G)
    for _ in range(80): G.notebook_update()
    with_page = images(book)
    return with_page


def main():
    rows = []
    # the spread the sheet is pasted on: the book opens there
    def reopen(G):
        G.key_b = True; G.notebook_update(); G.key_b = False
        G.key_b = True; G.notebook_update(); G.key_b = False
    for key, book_key in [("petrification", "tome"), ("water_dragon", "book"), ("flame_shot", "book"), ("pyreball", "quire")]:
        rows.append((key, book_key, sheet_page(key, book_key, reopen)))
    blank = RB.Book()
    blank.lua.execute(RB.CARRY_ALL)
    R.open_book(blank.g)
    for _ in range(3): blank.frame()
    base = images(blank)
    for key, book_key, n in rows:
        print(f"{key:14s} {book_key:6s} {n:6d} images a frame (the spread with the blank pages: {base})")
    # the grimoire: every spread of the Spellbook's, the whole grimoire unlocked
    book = RB.Book(full_grimoire=True)
    book.lua.execute(RB.CARRY_ALL)
    G = book.g
    R.open_book(G, to_blank=False)
    G.buttons[900007] = True; G.notebook_update(); G.buttons[900007] = False
    counts = []
    for _ in range(70):
        for _ in range(40): G.notebook_update()
        counts.append(images(book))
        G.pressed[7] = True; G.notebook_update(); G.pressed[7] = False
    print(f"grimoire spreads: median {statistics.median(counts):.0f}, most {max(counts)} images a frame")


if __name__ == "__main__":
    main()
