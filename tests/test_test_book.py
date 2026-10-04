"""The Test Book (files/test_book.lua): every seal on its pages compiles and casts, the pages hold every sign that does
something with every element and form (the pairs tests/test_sign_effects.py checks) and every sign each way of
manifesting takes, its sections lead to their pages, and a click on a page in the open book makes that seal the one the
book casts. The notes beside its pages (files/spell_notes.lua) tell every sign, and their numbers are what is cast; a
seal drawn in a book has them too, under the book while the mouse is over it.

python tests/test_test_book.py
"""
import collections
import unittest

from harness import WORLD_FILES, bare_world, load_cast, load_mod, load_reader
import run_tests as R


def spell_fields(data):
    """'element=fire;...;b=pull:2' -> ({field: value}, {behavior: weight}) of the seal itself (not those inside it)"""
    fields = dict(kv.split("=", 1) for kv in data.split("&")[0].split(";") if "=" in kv)
    behaviors = {}
    for part in filter(None, fields.get("b", "").split(",")):
        key, w = part.split(":")
        behaviors[key] = float(w)
    return fields, behaviors


class Pages(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = lua = load_reader()
        lua.execute('dofile_once( "mods/witch_notebook/files/sigils.lua" )')
        lua.execute('dofile_once( "mods/witch_notebook/files/test_book.lua" )')
        cls.pages = list(lua.eval("TestBook.pages()").values())

    def test_every_page_compiles(self):
        self.assertEqual([], list(self.lua.eval("TestBook.errors").values()))
        self.assertGreater(len(self.pages), 5000)
        keys = [p["key"] for p in self.pages]
        self.assertEqual(len(keys), len(set(keys)))
        strokes = self.lua.eval("TestBook.strokes")
        for p in self.pages[::97]:
            self.assertGreater(len(strokes(p)), 2, p["key"])

    def test_sections_lead_to_their_pages(self):
        """groups, items and parts begin in the order of the pages and each holds the pages of its own title"""
        starts = []
        for g in self.lua.eval("TestBook.sections()").values():
            items = list(g["items"].values())
            self.assertEqual(g["page"], items[0]["page"])
            for item in items:
                parts = list(item["parts"].values())
                self.assertEqual(item["page"], parts[0]["page"])
                for part in parts:
                    starts.append(part["page"])
                    self.assertEqual(self.pages[part["page"] - 1]["title"], item["name"] + " - " + part["name"])
        self.assertEqual(starts, sorted(starts))
        self.assertEqual(1, starts[0])

    def test_every_sign_with_every_element_and_form(self):
        """each sign's behavior that works on what an element makes in a form has a page there (the empty ring takes no
        signs); each way of manifesting has a page with each sign it takes"""
        lua = self.lua
        carrier_of = lua.eval("function(e, f, fl) local x = dictionary_effect(e, f, fl) return x and x.carrier end")
        works = lua.eval("dictionary_behavior_works")
        looks = lua.eval("DICTIONARY_LOOKS")
        behaviors = [b["key"] for b in lua.eval("DICTIONARY_BEHAVIORS").values() if b["key"] not in ("thrust", "float")]
        have, own = collections.defaultdict(set), collections.defaultdict(set)
        for p in self.pages:
            f, b = spell_fields(p["spell"])
            if f.get("manifest") or f.get("shape"):
                own[f.get("manifest") or f.get("shape")] |= set(b)
            elif f["element"] != "shockwave":
                have[(f["element"], carrier_of(f["element"], f["form"], True if f.get("floats") == "true" else None))] |= set(b)
        missing = [f"{element}/{carrier}: {k}" for (element, carrier), got in sorted(have.items()) for k in behaviors
                   if works(k, carrier) and k not in got and not (k == "scatter" and not (looks[element] and looks[element]["material"]))]
        self.assertGreater(len(have), 150)
        self.assertEqual([], missing)
        signs = lua.eval("DICTIONARY_MANIFEST_SIGNS")
        missing = [f"{key}: {sorted(set(signs[key].keys()) - got)}" for key, got in own.items()
                   if signs[key] and set(signs[key].keys()) - got]
        self.assertEqual([], missing)


class Casting(unittest.TestCase):
    """Every page's seal is cast with the Test Book in hand and makes something; the seals that manifest in a way of
    their own are cast in the small world (as tests/test_sign_effects.py does) and run a few frames without an error"""

    @classmethod
    def setUpClass(cls):
        reader = load_reader()
        reader.execute('dofile_once( "mods/witch_notebook/files/sigils.lua" )')
        reader.execute('dofile_once( "mods/witch_notebook/files/test_book.lua" )')
        spells = sorted({p["spell"] for p in reader.eval("TestBook.pages()").values()})
        cls.own = [d for d in spells if "manifest=" in d or "shape=" in d]
        cls.carried = [d for d in spells if d not in cls.own]

    def test_every_page_casts(self):
        lua = load_cast()
        G = lua.globals()
        errors = []
        for data in self.carried:
            # what one seal leaves in the run's globals (a quill drawing, a cloak casting) doesn't hold the next one back
            lua.execute("for k in pairs( globals ) do globals[k] = nil end")
            G.shots = lua.table()
            book = G.make_book(data, "test")
            controls, holder = G.make_controls(1, 0, 100, 0)
            try:
                made = G.spellbook_use(book, holder, controls, 100)
                if not list(G.shots.values()) and not (made and list(made.values())):
                    errors.append(f"{data}: nothing cast")
            except Exception as e:  # noqa: BLE001
                errors.append(f"{data}: {str(e).splitlines()[0]}")
        self.assertGreater(len(self.carried), 4000)
        self.assertEqual([], errors[:10], f"{len(errors)} of {len(self.carried)}")

    def test_every_way_of_manifesting_casts(self):
        lua = bare_world(WORLD_FILES + ["files/carriers.lua"])
        lua.execute("carriers_create()")
        cast = lua.eval('''function( data )
            W.errors = {}; make_world(); W.frame = 1000
            cast_spell( PLAYER, parse_spell_data( data ), 0, GROUND - 8, 0.99, -0.13, 150, -20, W.frame, nil )
            simulate( 5 )
            local errors = {}
            for _, e in ipairs( W.errors ) do errors[#errors + 1] = tostring( e ) end
            return table.concat( errors, "; " )
        end''')
        errors = []
        for data in self.own:
            try:
                err = cast(data)
                if err:
                    errors.append(f"{data}: {err}")
            except Exception as e:  # noqa: BLE001
                errors.append(f"{data}: {str(e).splitlines()[0]}")
        self.assertGreater(len(self.own), 300)
        self.assertEqual([], errors[:10], f"{len(errors)} of {len(self.own)}")


class Notes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_mod()
        cls.pages = list(cls.mod.eval("TestBook.pages()").values())

    def test_every_page_tells_its_sign(self):
        notes = self.mod.eval("TestBook.notes")
        missing = []
        for p in self.pages:
            lines = list(notes(p).values())
            self.assertEqual("head", lines[0]["kind"], p["key"])
            signs = [l["text"] for l in lines if l["kind"] == "sign"]
            if p["sign"] not in ("plain", "alone", "nothing inside") and not p["sign"].startswith("with ") and not signs:
                missing.append(p["name"])
        self.assertEqual([], missing[:10], len(missing))

    def test_the_numbers_are_what_is_cast(self):
        """lifetime, speed, damage, blast, a field's radius and damage, the number of shots: as the small world has them"""
        numbers = self.mod.eval("spell_numbers")
        looks = self.mod.eval("DICTIONARY_LOOKS")
        lua = bare_world(WORLD_FILES + ["files/carriers.lua"])
        lua.execute("carriers_create()")
        measure = lua.eval('''function( data )
            W.errors = {}; make_world(); W.frame = 1000
            local first = W.next_id
            cast_spell( PLAYER, parse_spell_data( data ), 0, GROUND - 8, 0.99, -0.13, 150, -20, W.frame, nil )
            local out = { shots = 0 }
            for id = first, W.next_id - 1 do
                local e = W.entities[id]
                local p = e and e.file:find( "/carriers/", 1, true ) and EntityGetFirstComponentIncludingDisabled( id, "ProjectileComponent" )
                local a = e and e.file:find( "/carriers/", 1, true ) and EntityGetFirstComponentIncludingDisabled( id, "AreaDamageComponent" )
                if p then
                    local vx, vy = ComponentGetValue2( EntityGetFirstComponentIncludingDisabled( id, "VelocityComponent" ), "mVelocity" )
                    local r = ComponentObjectGetValue2( p, "config_explosion", "explosion_radius" )
                    out.shots, out.lasts, out.speed = out.shots + 1, ComponentGetValue2( p, "lifetime" ), math.sqrt( vx * vx + vy * vy )
                    out.generic, out.blast = ComponentGetValue2( p, "damage" ), r and r > 0 and r or nil
                elseif a then
                    out.radius, out.dpf = ComponentGetValue2( a, "circle_radius" ), ComponentGetValue2( a, "damage_per_frame" )
                    out.lasts = ComponentGetValue2( EntityGetFirstComponentIncludingDisabled( id, "LifetimeComponent" ), "lifetime" )
                end
            end
            return out
        end''')
        every = self.mod.eval("DICTIONARY_CARRIER_BASE")["field_every"]
        wrong, checked = [], 0
        for p in self.pages:
            n = numbers(p["spell"])
            if not n["lasts"] or n["lights"]:
                continue  # told only for the shots, the orbs and the fields the mod builds itself
            m = measure(p["spell"])
            look = looks[spell_fields(p["spell"])[0]["element"]]
            pairs = [("lasts", n["lasts"], m["lasts"]), ("speed", n["speed"] or 0, m["speed"] or 0), ("blast", n["blast"], m["blast"]),
                     ("radius", n["radius"], m["radius"])]
            if n["hit"] is not None:
                pairs.append(("hit", n["hit"], (m["generic"] + sum((look["damage"] or {}).values())) * 25))
            if n["dps"] is not None:
                pairs.append(("dps", n["dps"], m["dpf"] * 60 / every * 25))
            if n["shots"] is not None:
                pairs.append(("shots", n["shots"], m["shots"]))
            for key, told, cast in pairs:
                if not told and not cast:
                    continue
                checked += 1
                if told is None or cast is None or abs(told - cast) > 0.02 * max(abs(told), abs(cast), 1) + 0.6:
                    wrong.append(f"{p['name']}: {key} told {told}, cast {cast}")
        self.assertGreater(checked, 10000)
        self.assertEqual([], wrong[:10], len(wrong))


class DrawnSeals(unittest.TestCase):
    def test_the_notes_of_a_drawn_seal_under_the_mouse(self):
        import random
        lua = load_mod()
        lua.execute(R.CARRY_ALL + "said = {} function GuiText( g, x, y, text ) said[#said + 1] = text end")
        G = lua.globals()
        R.open_book(G)
        random.seed(3)
        R.draw_on_blank(G, R.column_seal(lua, "fire"))
        for _ in range(30):
            G.notebook_update()
        view = G.notebook_view()[0]
        G.mouse[1], G.mouse[2] = view.back.x + 90, view.back.y + 90
        lua.execute("said = {}")
        G.notebook_update()
        text = " ".join(lua.eval("said").values())
        self.assertIn("A shot of fire flies from the hand", text)
        self.assertIn("hits for", text)
        # the inks a seal is drawn with: the blood's numbers are its average, the golden glows
        notes = lua.eval("spell_notes")
        plain = "element=fire;form=column;force=0.6;focus=0.7;spread=-0.4;range=0.4;lifetime=0;stability=1;precision=1;b=thrust:2"
        told = [l["text"] for l in notes(plain + ";ink=blood:0.7,gold:0.3").values()]
        self.assertTrue(any(t.startswith("Blood Ink (70%)") for t in told), told)
        numbers = lua.eval("spell_numbers")
        self.assertGreater(numbers(plain + ";ink=blood:1")["hit"], numbers(plain)["hit"])
        self.assertGreater(numbers(plain + ";ink=azure:1")["lasts"], numbers(plain)["lasts"])


class InTheBook(unittest.TestCase):
    def test_click_a_page_and_jump_to_a_section(self):
        lua = load_mod()
        lua.execute(R.CARRY_ALL + '''
            books_carried[#books_carried + 1] = 14
            book_keys[14] = "test"
        ''')
        G = lua.globals()
        R.open_book(G)
        for _ in range(100):
            G.notebook_update()
        G.buttons[900104] = True; G.notebook_update(); G.buttons[900104] = False  # the Test Book's name over the book
        for _ in range(40):
            G.notebook_update()
        view, blank = G.notebook_view()
        self.assertIsNone(blank)  # nothing to draw on
        pages = lua.eval("TestBook.pages()")
        R.click(G, view.front.x + 90, view.front.y + 90)
        self.assertEqual(G.globals["witch_notebook.test.active_wiki"], pages[2]["key"])
        self.assertEqual(G.globals["witch_notebook.test.active_spell"], pages[2]["spell"])
        self.assertTrue(G.globals["witch_notebook.test.active_strokes"])
        # the third group, Mixes: the book turns to its first page
        mixes = lua.eval("TestBook.sections()")[3]
        G.buttons[900203] = True; G.notebook_update(); G.buttons[900203] = False
        for _ in range(120):
            G.notebook_update()
        G.key_b = True; G.notebook_update(); G.key_b = False
        spread = int(G.globals["witch_notebook.test.spread"])
        self.assertEqual(spread, (mixes["page"] + 1) // 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
