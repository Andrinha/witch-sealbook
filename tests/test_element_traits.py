"""Elements' natures on the mod's own shots (files/element_traits.lua): an airy shot passes through creatures, an earthen
one bounces, a cold one freezes water, a ghostly one passes through walls; where they end a bright one flares, a wet one
puts out fire, a murky one bursts into smoke, a sparkling one into sparks. A splash's drops take only the light ones. The
notes tell them.

python tests/test_element_traits.py
"""
import unittest

from harness import WORLD_FILES, bare_world, load_mod


def world():
    lua = bare_world(WORLD_FILES + ["files/carriers.lua"])
    lua.execute("carriers_create()")
    return lua


class Traits(unittest.TestCase):
    def setUp(self):
        self.lua = world()
        self.lua.execute("W.errors = {}; make_world(); W.frame = 1000")

    def shot(self, element, form="column", extra=""):
        """the first projectile of the element's carrier a cast makes"""
        g = self.lua.globals()
        g.TEST_DATA = f"element={element};form={form};force=0.5;precision=1;stability=1;b=thrust:2{extra}"
        self.first = self.lua.eval("W.next_id")
        self.lua.execute("cast_spell( PLAYER, parse_spell_data( TEST_DATA ), 0, GROUND - 8, 0.99, -0.13, 150, -20, W.frame, nil )")
        return self.lua.eval(f'''(function()
            for id = {self.first}, W.next_id - 1 do
                local e = W.entities[id]
                if e and e.file:find( "/carriers/", 1, true ) then return id end
            end end)()''')

    def proj(self, e, field):
        return self.lua.eval(f'ComponentGetValue2( EntityGetFirstComponentIncludingDisabled( {e}, "ProjectileComponent" ), "{field}" )')

    def made(self, name):
        return self.lua.eval(f'''(function()
            local n = 0
            for id = {self.first}, W.next_id - 1 do
                local e = W.entities[id]
                if e and ( e.name:find( "{name}", 1, true ) or e.file:find( "{name}", 1, true ) ) then n = n + 1 end
            end
            return n end)()''')

    def no_errors(self):
        self.assertEqual([], list(self.lua.eval("W.errors").values()))

    def test_airy_passes_through(self):
        wind, fire = self.shot("wind"), None
        self.assertTrue(self.proj(wind, "penetrate_entities"))
        fire = self.shot("fire")
        self.assertFalse(self.proj(fire, "penetrate_entities"))
        self.no_errors()

    def test_earthen_bounces(self):
        self.assertEqual(1, self.proj(self.shot("earth"), "bounces_left"))
        self.assertEqual(1, self.proj(self.shot("sandstorm"), "bounces_left"))  # a mix is both: it passes through and bounces
        self.assertTrue(self.proj(self.shot("sandstorm"), "penetrate_entities"))
        self.assertEqual(0, self.proj(self.shot("water"), "bounces_left"))
        # Ricochet bounces more: a resonance comes after the nature
        self.assertGreater(self.proj(self.shot("earth", extra=",reflect:2;resonance=ricochet"), "bounces_left"), 1)
        self.no_errors()

    def test_ghostly_passes_through_walls(self):
        self.assertFalse(self.proj(self.shot("phantasm"), "collide_with_world"))
        self.no_errors()

    def test_cold_freezes_water(self):
        e = self.shot("ice")
        converts = self.lua.eval(f'''(function()
            local out = {{}}
            for _, c in ipairs( EntityGetComponentIncludingDisabled( {e}, "MagicConvertMaterialComponent" ) or {{}} ) do
                out[#out + 1] = ComponentGetValue2( c, "to_material_array" )
            end
            return table.concat( out, ";" ) end)()''')
        self.assertIn("ice_static", converts)
        self.no_errors()

    def test_where_they_end(self):
        for element, name in (("light", "witch_trait_flare"), ("smoke", "witch_trait_puff"), ("water", "witch_douse"),
                              ("flicker", "splash_flicker")):
            self.lua.execute("make_world()")
            e = self.shot(element)
            self.lua.execute(f"EntityKill( {e} ); simulate( 2 )")
            self.assertGreater(self.made(name), 0, element)
        self.no_errors()

    def test_drops_take_only_the_light_ones(self):
        traits = self.lua.eval("element_traits")
        self.assertIn("bounce", traits("earth", True))
        self.assertNotIn("pass", traits("wind", True))  # a splash's drops pass through only with Piercing
        self.assertNotIn("flare", traits("light", True))
        self.assertIn("flare", traits("light", False))
        self.assertEqual(set(), set(traits("fire", False)))

    def test_smoke_blinds_whoever_is_in_it(self):
        self.lua.execute('''
            W.added = {}
            local e = effect_spawn( "trait", "puff", 120, GROUND - 6, { frames = 60, r = 18, owner = PLAYER } )
            simulate( 2 )
        ''')
        self.assertTrue(self.lua.eval('(function() for _, c in ipairs( EntityGetAllChildren( ENEMIES[1] ) or {} ) do '
                                      'if EntityGetFilename( c ):find( "blindness", 1, true ) then return true end end end)()'))
        self.no_errors()


class Notes(unittest.TestCase):
    def test_the_notes_tell_the_nature(self):
        mod = load_mod()
        notes = mod.eval("spell_notes")
        text = " ".join(l["text"] for l in notes("element=wind;form=column;force=0.5;precision=1;stability=1;b=thrust:2").values())
        self.assertIn("passes through creatures", text)
        text = " ".join(l["text"] for l in notes("element=light;form=burst;force=0.5;precision=1;stability=1").values())
        self.assertNotIn("flares up", text)  # a splash's drops don't flare


if __name__ == "__main__":
    unittest.main(verbosity=2)
