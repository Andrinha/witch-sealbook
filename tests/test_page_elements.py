"""The manga's seals drawn round another element's sigil than their own (seal_canon.lua seal_page_takes). A page whose
magic takes that element is the page in it - "Pyreball (Water)", cast in water; a page whose magic is its own element's
(Integration, Purify, Water Cage...) is no longer that page - it is read sign by sign, where a faithful copy round
another sigil used to be named the page and cast in the page's element. And what each page in another element makes in
the small world.

python tests/test_page_elements.py
"""
import random
import unittest

import run_tests as fx
from harness import WORLD_FILES, bare_world, load_reader


def swapped_drawing(lua, key, sigil, seed=1):
    """the page's own drawing with its element sigil (grimoire_parts.lua) drawn again as 'sigil', as big and where it was"""
    parts = lua.eval("GRIMOIRE_PARTS")[key]
    own = lua.eval("seal_page_sigil")(lua.eval("GRIMOIRE_BY_KEY")[key])
    part = next(p for p in parts.split(";") if p.startswith(f"sigil:{own}:"))
    idx = {int(i) for i in part.split(":")[3].split(",")}
    strokes = [[(p["x"], p["y"]) for p in s.values()] for s in lua.eval(f'grimoire_strokes( GRIMOIRE_BY_KEY["{key}"] )').values()]
    xs = [x for i in idx for x, _ in strokes[i - 1]]
    ys = [y for i in idx for _, y in strokes[i - 1]]
    random.seed(seed)
    sigil_strokes = fx.place(fx.templates(lua)[("sigil", sigil)], (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2,
                             max(max(xs) - min(xs), max(ys) - min(ys)), tilt=0.05, noise=0.15)
    return [s for i, s in enumerate(strokes) if i + 1 not in idx] + sigil_strokes


class Reading(unittest.TestCase):
    """(A page whose magic in another element is what its signs make of that element anyway - Pyreball round water an
    orb of water hanging at the cursor, Ring of Fire a wave, the Water Bolt piercing shots, the sculptures, puppets and
    ribbons their element's - takes none: it is read sign by sign, and resonates as a seal of the witch's own does)"""
    @classmethod
    def setUpClass(cls):
        cls.lua = load_reader()
        cls.lua.execute('dofile_once( "mods/witch_notebook/files/grimoire_parts.lua" )')

    def read(self, strokes):
        res = self.lua.eval("read_spell")(fx.lua_strokes(self.lua, strokes))
        return res[0] if isinstance(res, tuple) else res

    def test_every_page_round_another_sigil(self):
        lua = self.lua
        by_key, sigils = lua.eval("GRIMOIRE_BY_KEY"), lua.eval("DICTIONARY_SIGILS")
        page_sigil, takes, cast_in = lua.eval("seal_page_sigil"), lua.eval("seal_page_takes"), lua.eval("seal_page_element")
        title = lua.eval("seal_page_title")
        parts = lua.eval("GRIMOIRE_PARTS")
        wrong, swappable, checked = [], 0, 0
        for key in sorted(parts.keys()):
            entry = by_key[key]
            own = page_sigil(entry)
            if not own or not any(p.startswith(f"sigil:{own}:") for p in parts[key].split(";")):
                continue
            sigil = "fire" if own == "water" else "water"
            element = sigils[sigil]["element"]
            spell = self.read(swapped_drawing(lua, key, sigil))
            checked += 1
            named = spell and spell["named"]
            if takes(entry, element):
                swappable += 1
                want = cast_in(entry, element)
                # (or the manga's own page of that structure round that sigil: Sealchair is Pyreball round earth)
                if named == key:
                    if spell["element"] != want or spell["summary"] != title(entry, want):
                        wrong.append(f"{key} round {sigil}: {spell['element']}, {spell['summary']}")
                    data = lua.eval("seal_page_data")(spell)
                    if not data.startswith(f"element={want};") or f"named={key}" not in data:
                        wrong.append(f"{key} round {sigil}: page data {data[:60]}")
                elif not named or (by_key[named]["recipe"] or "").find(f"sigil:{sigil}=") < 0:
                    wrong.append(f"{key} round {sigil}: read as {named or (spell and spell['summary'])}")
            elif named == key:
                wrong.append(f"{key} round {sigil}: still {key} in {spell['element']}, its magic takes no {element}")
        self.assertGreater(checked, 50)
        self.assertGreater(swappable, 7)
        self.assertEqual([], wrong)

    def test_the_page_s_own_sigil_is_still_the_page(self):
        for key in ("pyreball", "water_bolt_27", "carousel", "watershot", "integration", "spike"):
            parts = self.lua.eval("GRIMOIRE_PARTS")[key]
            own = self.lua.eval("seal_page_sigil")(self.lua.eval("GRIMOIRE_BY_KEY")[key])
            spell = self.read(swapped_drawing(self.lua, key, own))
            self.assertTrue(spell, key)
            self.assertEqual(key, spell["named"], key)
            self.assertIsNone(spell["swapped"], key)
            self.assertEqual(self.lua.eval("GRIMOIRE_BY_KEY")[key]["name"], spell["summary"])
            self.assertTrue(parts)

    def test_a_page_taking_no_element_is_its_structure_in_the_new_one(self):
        """Pyreball round water: not Pyreball cast in fire, as a faithful copy used to be - an orb of water hanging at the
        cursor, as its four Levitation signs make of water; Wall Breaker round fire: Magma, a resonance of the witch's own"""
        spell = self.read(swapped_drawing(self.lua, "pyreball", "water"))
        self.assertEqual((None, "water", "levitation", True), (spell["named"], spell["element"], spell["form"], spell["floats"]))
        spell = self.read(swapped_drawing(self.lua, "wall_breaker", "fire"))
        self.assertEqual((None, "fire", "magma"), (spell["named"], spell["element"], spell["resonance"]))

    def test_the_compressed_element_of_a_page_compresses_the_new_one(self):
        """The Great Water Bolt is ice - its water compressed by its Convergence signs; round fire it is plasma"""
        spell = self.read(swapped_drawing(self.lua, "water_bolt_27", "fire"))
        self.assertEqual(("water_bolt_27", "plasma"), (spell["named"], spell["element"]))
        self.assertEqual("Great Water Bolt (Plasma)", spell["summary"])


def with_signs(lua, strokes, sign, count=2):
    """'count' of 'sign' drawn beside the seal where it has room, facing its middle"""
    import math
    ring = lua.eval("function(s) local r = SealRead.find_ring(s) return r.x, r.y, r.r end")(fx.lua_strokes(lua, strokes))
    cx, cy, r = ring
    pts = [p for s in strokes for p in s if ((p[0] - cx) ** 2 + (p[1] - cy) ** 2) ** 0.5 < 0.97 * r]
    best = None
    for base in range(0, 360, 5):
        room = min(min(math.hypot(cx + 0.72 * r * math.cos(math.radians(base + 360 * k / count)) - x,
                                  cy + 0.72 * r * math.sin(math.radians(base + 360 * k / count)) - y) for x, y in pts)
                   for k in range(count))
        if not best or room > best[0]:
            best = (room, base)
    random.seed(5)
    out = list(strokes)
    for k in range(count):
        a = math.radians(best[1] + 360 * k / count)
        out += fx.place(fx.templates(lua)[("sign", sign)], cx + 0.72 * r * math.cos(a), cy + 0.72 * r * math.sin(a), r * 0.18,
                        a - math.pi / 2, tilt=0.05, noise=0.15)
    return out


class Modifiers(unittest.TestCase):
    """Signs drawn beside one of the wiki's seals known as a whole (traced from the wiki) add what its way of manifesting
    takes, as they do beside a seal of signs (seal_canon.lua seal_extra_strokes): Water Dragon and two Expansions is a
    bigger dragon; before, the whole drawing named the page and the signs were lost"""
    @classmethod
    def setUpClass(cls):
        cls.lua = load_reader()

    def read(self, key, sign=None):
        strokes = [[(p["x"], p["y"]) for p in s.values()] for s in self.lua.eval(f'grimoire_strokes( GRIMOIRE_BY_KEY["{key}"] )').values()]
        if sign:
            strokes = with_signs(self.lua, strokes, sign)
        res = self.lua.eval("read_spell")(fx.lua_strokes(self.lua, strokes))
        return res[0] if isinstance(res, tuple) else res

    def test_signs_beside_a_whole_seal(self):
        for key, sign, behavior, text in (("water_dragon", "expansion", "grow", "big"), ("time_stop", "expansion", "grow", "big"),
                                          ("time_stop", "stability", "still", None), ("spiraling_flame", "strengthen", "strong", "strengthened")):
            spell = self.read(key, sign)
            self.assertEqual(key, spell["named"], key)
            self.assertIn(behavior, dict(spell["extras"] or {}), f"{key} + {sign}")
            if text:
                self.assertIn(text, spell["summary"])
            self.assertIn(f"{behavior}:", self.lua.eval("seal_page_data")(spell), key)

    def test_a_whole_seal_alone_adds_nothing(self):
        for key in ("water_dragon", "time_stop", "spiraling_flame", "petrification"):
            spell = self.read(key)
            self.assertEqual(key, spell["named"])
            self.assertFalse(spell["extras"], key)

    def test_signs_its_way_doesn_t_take_add_nothing(self):
        """Strengthening beside Time Stop: time stops no harder (DICTIONARY_MANIFEST_SIGNS)"""
        spell = self.read("time_stop", "strengthen")
        self.assertEqual("time_stop", spell["named"])
        self.assertNotIn("strong", dict(spell["extras"] or {}))


class Casting(unittest.TestCase):
    def setUp(self):
        self.lua = bare_world(WORLD_FILES + ["files/carriers.lua"])
        self.lua.execute('''
            carriers_create(); make_world(); W.frame = 1000
            MATTER = {}
            local create = GameCreateParticle
            function GameCreateParticle( m, ... ) MATTER[#MATTER + 1] = m return create( m, ... ) end
        ''')

    def cast(self, key, element, frames=0):
        g = self.lua.globals()
        g.TEST_KEY, g.TEST_ELEMENT = key, element
        self.lua.execute('''
            FIRST = W.next_id
            local data = seal_page_data( { named = TEST_KEY, swapped = TEST_ELEMENT, precision = 1, stability = 1 } )
            cast_spell( PLAYER, parse_spell_data( data ), 0, GROUND - 8, 1, 0, 120, GROUND - 30, W.frame, nil )
        ''')
        self.lua.execute(f"simulate( {frames} )")
        made = [e for e in self.lua.eval('''(function()
            local out = {}
            for id = FIRST, W.next_id - 1 do local e = W.entities[id] if e then out[#out + 1] = e end end
            return out end)()''').values()]
        self.assertEqual([], list(self.lua.eval("W.errors").values()), key)
        return made

    def params(self, e):
        return self.lua.eval(f"effect_params( {e.id} )")

    def effect(self, made, name):
        return [e for e in made if e.name == name]

    def files(self, made, part):
        return [e for e in made if part in e.file]

    def test_flame_burst_round_water_bursts_into_a_wave_of_water(self):
        made = self.cast("flame_burst", "water", frames=120)
        self.assertTrue(self.files(made, "carriers/bolt_water"))
        waves = self.effect(made, "witch_nova_nova")
        self.assertTrue(waves)
        self.assertEqual("water", self.params(waves[0]).element)

    def test_spike_round_crystal_bursts_into_crystal_shards(self):
        made = self.cast("spike", "crystal", frames=2)
        self.assertGreaterEqual(len(self.files(made, "carriers/bolt_crystal")), 5)
        self.assertFalse(self.files(made, "carriers/bolt_stone"))
        self.assertGreaterEqual(len(self.files(self.cast("spike", "earth", frames=2), "carriers/bolt_stone")), 5)

    def test_watershot_round_sand_pours_sand(self):
        self.cast("watershot", "sand", frames=10)
        self.assertIn("sand", set(self.lua.eval("MATTER").values()))
        self.assertNotIn("water", set(self.lua.eval("MATTER").values()))

    def test_lights_stags_and_puppets_of_another_element(self):
        for key, element, name in (("carousel", "fire", "witch_orbit_carousel"), ("torchstag", "water", "witch_mover_sculpture"),
                                   ("giant_water_puppet", "earth", "witch_mover_puppet")):
            made = self.effect(self.cast(key, element), name)
            self.assertTrue(made, key)
            self.assertEqual(element, self.params(made[0]).element, key)

    def test_expansion_on_the_spike_the_carousel_and_the_lamps(self):
        def made_with(key, grow):
            self.lua.globals().TEST_GROW = grow
            self.lua.globals().TEST_KEY = key
            self.lua.execute('''
                make_world(); W.frame = 1000
                FIRST = W.next_id
                local spell = parse_spell_data( seal_page_data( { named = TEST_KEY, precision = 1, stability = 1,
                    extras = TEST_GROW > 0 and { grow = TEST_GROW } or nil } ) )
                cast_spell( PLAYER, spell, 0, GROUND - 8, 1, 0, 120, GROUND - 30, W.frame, nil )
                simulate( 2 )
            ''')
            return [e for e in self.lua.eval('''(function()
                local out = {}
                for id = FIRST, W.next_id - 1 do local e = W.entities[id] if e then out[#out + 1] = e end end
                return out end)()''').values()]
        plain, grown = made_with("spike", 0), made_with("spike", 2)
        self.assertGreater(len(self.files(grown, "carriers/bolt_stone")), len(self.files(plain, "carriers/bolt_stone")))
        for key, name in (("carousel", "witch_orbit_carousel"), ("floatglow", "witch_light_lamp")):
            small = self.params(self.effect(made_with(key, 0), name)[0]).big
            big = self.params(self.effect(made_with(key, 2), name)[0]).big
            self.assertGreater(big, small, key)

    def test_raincleaver_cuts_with_water(self):
        """Its sword has no element sigil; its water is in the small seals round it - it cut with light"""
        self.lua.execute('''
            FIRST = W.next_id
            local data = seal_page_data( { named = "raincleaver", precision = 1, stability = 1 } )
            cast_spell( PLAYER, parse_spell_data( data ), 0, GROUND - 8, 1, 0, 120, GROUND - 30, W.frame, nil )
        ''')
        made = [e for e in self.lua.eval('''(function()
            local out = {}
            for id = FIRST, W.next_id - 1 do local e = W.entities[id] if e then out[#out + 1] = e end end
            return out end)()''').values()]
        slashes = self.effect(made, "witch_nova_slash")
        self.assertTrue(slashes)
        self.assertEqual("water", self.params(slashes[0]).element)

    def test_the_great_water_bolt_round_fire_is_a_plasma_bolt_to_the_aim_point(self):
        made = self.cast("water_bolt_27", "plasma")
        bolts = self.files(made, "carriers/bolt_plasma")
        self.assertTrue(bolts)
        self.assertFalse(self.files(made, "carriers/bolt_ice"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
