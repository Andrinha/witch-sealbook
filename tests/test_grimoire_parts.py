"""The parts of the wiki's seals (files/grimoire_parts.lua, made by tools/make_grimoire_parts.py): every one names a
symbol of the dictionary and strokes its page has; a seal made of the dictionary's symbols names only those; and on a
grimoire page the part under the mouse is named (notebook.lua draw_parts)."""
import os
import unittest

import run_tests as R
from harness import MOD, load_mod, load_reader


class GrimoireParts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = load_reader()
        cls.lua.execute('dofile_once( "mods/witch_notebook/files/grimoire_parts.lua" )')

    def test_every_part_is_a_symbol_on_its_page(self):
        lua = self.lua
        by_key = lua.eval("GRIMOIRE_BY_KEY")
        sigils, signs = lua.eval("DICTIONARY_SIGILS"), lua.eval("DICTIONARY_SIGNS")
        count = lua.eval("function( e ) return #grimoire_strokes( e ) end")
        wrong, parts = [], 0
        for key, text in lua.eval("GRIMOIRE_PARTS").items():
            entry = by_key[key]
            if entry is None:
                wrong.append(f"{key}: no such seal")
                continue
            known = set()
            for signature in (entry["symbols"] or "", entry["recipe"] or ""):
                known |= {p.split("=")[0] for p in signature.split(",") if "=" in p}
            n = count(entry)
            for item in text.split(";"):
                kind, name, inverted, ids = item.split(":")
                parts += 1
                if kind not in ("sigil", "sign", "mark"):
                    wrong.append(f"{key}: a part of kind {kind}")
                elif kind != "mark" and (sigils if kind == "sigil" else signs)[name] is None:
                    wrong.append(f"{key}: {kind} {name} isn't in the dictionary")
                if known and kind != "mark" and f"{kind}:{name}" not in known:
                    wrong.append(f"{key}: {kind} {name} isn't in its recipe")
                if not all(1 <= int(i) <= n for i in ids.split(",")):
                    wrong.append(f"{key}: strokes {ids} past its {n} (make_grimoire_parts.py after make_grimoire.py)")
        self.assertGreater(parts, 1500)
        self.assertEqual([], wrong[:10], len(wrong))


    def test_every_glyph_of_a_traced_seal_has_a_part(self):
        # Snowfending, traced from the wiki: its fire, two Stillness and four Crosshairs named, its waves and curls its
        # own marks - every stroke but the ring
        lua = self.lua
        parts = lua.eval("GRIMOIRE_PARTS").snowfending.split(";")
        n = lua.eval("function( e ) return #grimoire_strokes( e ) end")(lua.eval("GRIMOIRE_BY_KEY").snowfending)
        covered = {int(i) for p in parts for i in p.split(":")[3].split(",")}
        kinds = [":".join(p.split(":")[:2]) for p in parts]
        self.assertEqual(n - 1, len(covered))
        self.assertEqual((1, 2, 4), (kinds.count("sigil:fire"), kinds.count("sign:stillness"), kinds.count("sign:crosshair")))


    def test_twins_round_the_ring_are_named_alike(self):
        # Glowstone Path: the two waves at its top mirror each other - the right one, torn in its strokes, is joined up
        # and named like the left one; its own glyphs - a bar with an arc at each side, three strokes down each
        # diagonal - are whole, one mark each
        parts = self.lua.eval("GRIMOIRE_PARTS").glowstone_path.split(";")
        kinds = [":".join(p.split(":")[:2]) for p in parts]
        self.assertEqual(2, kinds.count("sign:stability"))
        marks = [p.split(":")[3].split(",") for p in parts if p.startswith("mark")]
        self.assertEqual([3, 3, 3, 3], [len(ids) for ids in marks])


class GrimoirePageUnderTheMouse(unittest.TestCase):
    def test_the_part_under_the_mouse_is_named(self):
        lua = load_mod()
        lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
        lua.execute(R.CARRY_ALL + "said = {} local t = GuiText function GuiText( g, x, y, text, ... ) said[#said + 1] = text end")
        G = lua.globals()
        G.settings["witch_notebook.full_grimoire"] = True
        R.open_book(G)
        G.buttons[900007] = True; G.notebook_update(); G.buttons[900007] = False
        for _ in range(60):
            G.notebook_update()
        view = G.notebook_view()[0]
        named = set()
        for dx in range(10, 171, 4):
            for dy in range(10, 171, 4):
                G.mouse[1], G.mouse[2] = view.back.x + dx, view.back.y + dy
                lua.execute("said = {}")
                G.notebook_update()
                parts = [t for t in lua.eval("said").values() if t.startswith(("Fire:", "Levitation:", "A sign of "))]
                self.assertLessEqual(len(parts), 1, parts)
                named.update(parts)
        # the first page: Pyreball, a fire sigil and four levitations
        self.assertEqual({"Fire: the element", "Levitation: floats"}, named)

    def test_a_wiki_seal_drawn_by_hand_is_told_like_its_page(self):
        # Snowfending copied onto a blank page: the book knows it as the wiki's seal and tells its parts the way its
        # grimoire page does (seal.lua seal_parts) - its fire and Crosshairs, and its own waves and curls (a copy is a
        # drawing of its own: a part read on the edge of sure may be named on one and not the other)
        lua = load_mod()
        lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
        lua.execute(R.CARRY_ALL + "said = {} local t = GuiText function GuiText( g, x, y, text, ... ) said[#said + 1] = text end")
        G = lua.globals()
        R.open_book(G)
        entry = lua.eval("GRIMOIRE_BY_KEY").snowfending
        strokes = [[(p["x"], p["y"]) for p in st.values()] for st in lua.eval("grimoire_strokes")(entry).values()]
        # the ring drawn last, as the book's guide teaches (a ring closed first wakes empty: the shockwave)
        span = lambda s: max(max(x for x, _ in s) - min(x for x, _ in s), max(y for _, y in s) - min(y for _, y in s))
        strokes.sort(key=span)
        R.draw_on_blank(G, strokes)
        for _ in range(30):
            G.notebook_update()
        view = G.notebook_view()[0]
        told = set()
        for dx in range(10, 171, 3):
            for dy in range(10, 171, 3):
                G.mouse[1], G.mouse[2] = view.back.x + dx, view.back.y + dy
                lua.execute("said = {}")
                G.notebook_update()
                told.update(t.split(":")[0] for t in lua.eval("said").values() if t.startswith(("Fire:", "Stillness:", "Crosshair:", "A sign of ")))
        self.assertLessEqual({"Fire", "Crosshair", "A sign of Snowfending's own"}, told)
        self.assertLessEqual(told, {"Fire", "Stillness", "Crosshair", "A sign of Snowfending's own"})


if __name__ == "__main__":
    unittest.main()
