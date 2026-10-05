"""Signs do what the book says they do. Every sign dictionary.lua lists for a carrier (DICTIONARY_BEHAVIORS) changes what
the spell makes, for every element and form; every sign a way of manifesting of its own lists (DICTIONARY_MANIFEST_SIGNS)
changes the effect it spawns; the others are left out of the spell when the seal is read, so its summary doesn't promise
them. Then what the signs on the wave, the field, the cloud and the ring do in the small world.

python tests/test_sign_effects.py
"""
import math
import unittest

from harness import WORLD_FILES, bare_world

SNAPSHOT = r'''
local function ser( v )
	if type( v ) == "table" then
		local keys = {}
		for k in pairs( v ) do keys[#keys + 1] = tostring( k ) end
		table.sort( keys )
		local out = {}
		for _, k in ipairs( keys ) do out[#out + 1] = k .. "=" .. ser( v[k] ) end
		return "{" .. table.concat( out, "," ) .. "}"
	elseif type( v ) == "number" then
		return string.format( "%.3f", v )
	end
	return tostring( v )
end
-- what a cast makes: every entity made, with its place and components
function snapshot_cast( data, manifest, shape )
	W.errors = {}; W.added = {}; W.made = {}
	make_world()
	W.frame = 1000
	GlobalsSetValue( "witch_notebook.window", "0" )
	SetRandomSeed( 1, 1 )
	local first = W.next_id
	local spell = parse_spell_data( data )
	if manifest or shape then
		local ctx = { shooter = PLAYER, spell = spell, x = 0, y = GROUND - 8, aim_x = 0.99, aim_y = -0.13, tx = 150, ty = -20,
			frame = W.frame, power = 1.4 }
		if shape then MANIFESTS.sculpture( ctx ) else MANIFESTS[manifest]( ctx ) end
	else
		cast_spell( PLAYER, spell, 0, GROUND - 8, 0.99, -0.13, 150, -20, W.frame, nil )
	end
	local lines = {}
	for id = first, W.next_id - 1 do
		local e = W.entities[id]
		if e then
			local comps = {}
			for _, cid in ipairs( e.comps ) do
				local c = W.comps[cid]
				if c then comps[#comps + 1] = c.type .. ser( c.values ) end
			end
			table.sort( comps )
			lines[#lines + 1] = string.format( "%s %s@%.0f,%.0f[%s]", e.name, e.file, e.x, e.y, table.concat( comps, ";" ) )
		end
	end
	return table.concat( lines, "\n" )
end
'''

FORMS = [("column", False), ("levitation", False), ("levitation", True), ("dispersion", False), ("burst", False),
         ("field", False), ("rain", False), ("ring", False)]
# the form's own signs, as a read seal has them
FORM_SIGNS = {"column": "thrust:1", "levitation": "float:1"}
WEIGHT = {"spin": 0.8, "pierce": 2}


def world():
    lua = bare_world(WORLD_FILES + ["files/carriers.lua"])
    lua.execute("carriers_create()")
    lua.execute(SNAPSHOT)
    return lua


class SignsOnCarriers(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = world()

    def test_every_listed_sign_changes_the_spell(self):
        lua = self.lua
        effect = lua.eval("function(e, f, fl) local x = dictionary_effect(e, f, fl) return x and x.carrier, x and x.file end")
        works, snap = lua.eval("dictionary_behavior_works"), lua.eval("snapshot_cast")
        looks = lua.eval("DICTIONARY_LOOKS")
        behaviors = [b["key"] for b in lua.eval("DICTIONARY_BEHAVIORS").values() if b["key"] not in ("thrust", "float")]
        failures, checked = [], 0
        for element in sorted(looks.keys()):
            for form, floats in FORMS:
                carrier, file = effect(element, form, floats or None)
                if file and file.startswith("data/"):
                    continue  # the game's projectiles: the stub can't read all of them
                own = FORM_SIGNS.get(form)
                base = f"element={element};form={form};force=0.5;precision=0.9;stability=1" + (";floats=true" if floats else "")
                before = snap(base + ";b=" + (own or ""), None, None)
                for b in behaviors:
                    if not works(b, carrier) or (b == "scatter" and not looks[element]["material"]):
                        continue
                    checked += 1
                    signs = ",".join(([own] if own else []) + [f"{b}:{WEIGHT.get(b, 1)}"])
                    if snap(base + ";b=" + signs, None, None) == before:
                        failures.append(f"{element} {form}{' floats' if floats else ''} ({carrier}): {b}")
        self.assertGreater(checked, 2000)
        self.assertEqual([], failures)

    def test_every_listed_sign_changes_a_way_of_manifesting(self):
        lua = self.lua
        snap = lua.eval("snapshot_cast")
        shapes = {d["shape"] for d in lua.eval("DICTIONARY_SIGILS").values() if d["shape"]}
        manifests = set(lua.eval("MANIFESTS").keys())
        failures = []
        for key, signs in lua.eval("DICTIONARY_MANIFEST_SIGNS").items():
            self.assertTrue(key in manifests or key in shapes, key)
            shape = key if key in shapes else None
            for sign in signs.keys():
                changed = False
                for element in ("water", "light", "fire", "earth"):
                    base = f"element={element};form=burst;{'shape' if shape else 'manifest'}={key};force=0.5;precision=0.9;stability=1;b="
                    if snap(base + f"{sign}:1", None if shape else key, shape) != snap(base, None if shape else key, shape):
                        changed = True
                        break
                if not changed:
                    failures.append(f"{key}: {sign}")
        self.assertEqual([], failures)


def seal_tree(lua, sigils, signs):
    """a seal tree as parse_seal returns it: sigils in the middle, signs (key, inverted) evenly around"""
    syms = [lua.table_from({"kind": "sigil", "key": k, "angle": 0, "dist": 0.1, "size": 0.45, "score": 0.8, "inverted": False})
            for k in sigils]
    for i, (k, inverted) in enumerate(signs):
        syms.append(lua.table_from({"kind": "sign", "key": k, "angle": 2 * math.pi * i / len(signs), "dist": 0.7, "size": 0.25,
                                    "score": 0.8, "inverted": inverted, "turn": 0}))
    return lua.table_from({"ring": lua.table_from({"x": 0, "y": 0, "r": 70, "roundness": 0.02}), "symbols": lua.table_from(syms),
                           "layers": lua.table(), "frames": lua.table(), "subs": lua.table(), "links": lua.table(), "glaives": 0})


class Reading(unittest.TestCase):
    """A sign that does nothing to what it is drawn round is left out of the spell and its summary"""

    @classmethod
    def setUpClass(cls):
        cls.lua = world()

    def spell(self, sigils, signs):
        res = self.lua.eval("compile_spell")(seal_tree(self.lua, sigils, signs))
        spell = res[0] if isinstance(res, tuple) else res
        self.assertTrue(spell, res)
        return set(spell["behaviors"].keys()), spell["summary"]

    def test_left_out(self):
        cases = [
            (["fire"], [("column", False)] * 2 + [("reflection", False)] * 2, "reflect"),     # a shot doesn't reflect
            (["whorl"], [("pull", False)] * 2, "pull"),                                      # the whirlwind takes none of it
            (["dragon"], [("crosshair", False)] * 2, "homing"),
            (["light"], [("column", False)] * 2 + [("collection", True)] * 2, "scatter"),   # light has no matter to scatter
            (["water"], [("dispersion", False)] * 2 + [("gathering", False)] * 2, "gather"),  # a wave gathers nothing
        ]
        for sigils, signs, key in cases:
            have, summary = self.spell(sigils, signs)
            self.assertNotIn(key, have, (sigils, summary))
        have, summary = self.spell(["fire"], [("diamond", False)] * 2)
        self.assertEqual(set(), have, summary)

    def test_a_faint_special_sigil_alone_is_no_spell(self):
        """Pieces of a torn element sigil read as a special one (a wind sigil's S as Repetition, 0.55) make no spell; a
        creature's sigil, never matched as closely, takes less"""
        def compiled(key, score):
            tree = seal_tree(self.lua, [key], [("levitation", False)] * 2)
            tree["symbols"][1]["score"] = score
            res = self.lua.eval("compile_spell")(tree)
            return res if isinstance(res, tuple) else (res, None)
        spell, err = compiled("repetition", 0.55)
        self.assertIsNone(spell)
        self.assertEqual("The sigil is too faint", err)
        self.assertIsNotNone(compiled("repetition", 0.62)[0])
        self.assertIsNotNone(compiled("scalewolf", 0.55)[0])

    def test_kept(self):
        # a field round the caster: Dispersion held by Stability
        have, summary = self.spell(["fire"], [("dispersion", False), ("reflection", False), ("stability", False), ("reflection", False)])
        self.assertIn("reflect", have)
        self.assertIn("reflects projectiles", summary)
        self.assertIn("circle around", summary)
        have, summary = self.spell(["dragon"], [("expansion", False)] * 2)
        self.assertIn("grow", have)
        have, summary = self.spell(["water"], [("dispersion", False)] * 2 + [("crush", False)] * 2)
        self.assertIn("crush", have)


class InTheWorld(unittest.TestCase):
    def setUp(self):
        self.lua = world()
        self.lua.execute("W.errors = {}; make_world(); W.frame = 1000")

    def cast(self, data, tx=150, ty=-20):
        g = self.lua.globals()
        g.TEST_DATA, g.TEST_TX, g.TEST_TY = data, tx, ty
        return self.lua.execute('''
            local made = cast_spell( PLAYER, parse_spell_data( TEST_DATA .. ";precision=0.9;stability=1" ), 0, GROUND - 8, 0.99, -0.13,
                TEST_TX, TEST_TY, W.frame, nil )
            local out = {}
            for _, e in ipairs( made ) do if type( e ) == "number" then out[#out + 1] = e end end
            return out
        ''')

    def entity_with(self, kind):
        """the newest entity with a component of this kind"""
        return self.lua.eval(f'''(function()
            local best
            for id, e in pairs( W.entities ) do
                if e.alive and EntityGetFirstComponentIncludingDisabled( id, "{kind}" ) and ( not best or id > best ) then best = id end
            end
            return best end)()''')

    def no_errors(self):
        self.assertEqual([], list(self.lua.eval("W.errors").values()))

    def test_field_reflects_enemy_projectiles(self):
        self.cast("element=fire;form=field;b=reflect:1")
        self.lua.execute('''
            SHOT = EntityCreateNew( "enemy shot" )
            EntitySetTransform( SHOT, 20, GROUND - 8 )
            EntityAddTag( SHOT, "projectile" )
            EntityAddComponent2( SHOT, "ProjectileComponent", { mWhoShot = ENEMIES[1], lifetime = 500 } )
            EntityAddComponent2( SHOT, "VelocityComponent", { mVelocity = { -60, 0 } } )
            simulate( 2 )
        ''')
        who, vx, _ = self.lua.eval('''ComponentGetValue2( EntityGetFirstComponent( SHOT, "ProjectileComponent" ), "mWhoShot" ),
            ComponentGetValue2( EntityGetFirstComponent( SHOT, "VelocityComponent" ), "mVelocity" )''')
        self.assertEqual(who, self.lua.globals().PLAYER)
        self.assertGreater(vx, 0)
        self.no_errors()

    def test_field_keeps_creatures_out(self):
        self.cast("element=fire;form=field;b=bound:1")
        # an enemy just outside the edge of the field round the caster is pushed out, one just inside in
        self.lua.execute('''
            EntitySetTransform( ENEMIES[3], 34, GROUND - 8 )
            EntitySetTransform( ENEMIES[1], 28, GROUND - 8 )
            simulate( 2 )
        ''')
        out_vx = self.lua.eval('ComponentGetValue2( EntityGetFirstComponent( ENEMIES[3], "CharacterDataComponent" ), "mVelocity" )')[0]
        in_vx = self.lua.eval('ComponentGetValue2( EntityGetFirstComponent( ENEMIES[1], "CharacterDataComponent" ), "mVelocity" )')[0]
        self.assertGreater(out_vx, 0)
        self.assertLess(in_vx, 0)
        self.no_errors()

    def test_field_strength_and_time(self):
        def field(data):
            self.cast(data)
            e = self.entity_with("AreaDamageComponent")
            return self.lua.eval(f'''ComponentGetValue2( EntityGetFirstComponent( {e}, "AreaDamageComponent" ), "damage_per_frame" ),
                ComponentGetValue2( EntityGetFirstComponent( {e}, "LifetimeComponent" ), "lifetime" )''')
        weak, short = field("element=fire;form=field;force=0;lifetime=0;b=")
        strong, long = field("element=fire;form=field;force=1;lifetime=1;b=strong:1")
        self.assertGreater(strong, weak * 1.5)
        self.assertGreater(long, short)

    def test_wave_holds_chills_and_turns_the_ground(self):
        self.lua.execute("W.added = {}")
        self.cast("element=water;form=dispersion;force=0.5;b=hold:1,cool:1,crush:1")
        converts = [item[2] for item in self.lua.eval("W.added").values() if item[1] == "MagicConvertMaterialComponent"]
        self.assertTrue(any("rock_static" in (c.from_material_array or "") and not c.loop for c in converts))
        self.assertTrue(any("water" in (c.from_material_array or "") and not c.loop for c in converts))
        self.lua.execute("simulate( 25 )")
        # the enemy 40 px away was struck as the wave passed: held in water
        self.assertTrue(self.lua.eval('held_as( ENEMIES[3], "water" )'))
        self.no_errors()

    def test_wave_reflects(self):
        self.cast("element=wind;form=dispersion;b=reflect:1")
        self.lua.execute('''
            SHOT = EntityCreateNew( "enemy shot" )
            EntitySetTransform( SHOT, 30, GROUND - 8 )
            EntityAddTag( SHOT, "projectile" )
            EntityAddComponent2( SHOT, "ProjectileComponent", { mWhoShot = ENEMIES[1], lifetime = 500 } )
            EntityAddComponent2( SHOT, "VelocityComponent", { mVelocity = { -20, 0 } } )
            simulate( 22 )
        ''')
        self.assertEqual(self.lua.eval('ComponentGetValue2( EntityGetFirstComponent( SHOT, "ProjectileComponent" ), "mWhoShot" )'),
                         self.lua.globals().PLAYER)
        self.no_errors()

    def test_detection_places_the_field_at_the_nearest_enemy(self):
        self.cast("element=fire;form=field;b=sense:1")
        e = self.entity_with("AreaDamageComponent")
        x, y = self.lua.eval(f"EntityGetTransform( {e} )")[:2]
        ex, ey = self.lua.eval("EntityGetTransform( ENEMIES[3] )")[:2]
        self.assertLess(math.hypot(x - ex, y - ey), 6)

    def test_cloud_follows_enemies(self):
        self.cast("element=water;form=rain;b=homing:1", tx=60, ty=-60)
        cloud = self.lua.eval('(function() for id, e in pairs( W.entities ) do if e.file:find( "carriers/cloud_", 1, true ) then return id end end end)()')
        g = self.lua.globals()
        g.CLOUD = cloud
        x0, y0 = self.lua.eval("EntityGetTransform( CLOUD )")[:2]
        ex, ey = self.lua.eval("EntityGetTransform( ENEMIES[3] )")[:2]
        self.lua.execute("simulate( 30 )")
        x1, y1 = self.lua.eval("EntityGetTransform( CLOUD )")[:2]
        self.assertLess(math.hypot(x1 - ex, y1 - (ey - 36)), math.hypot(x0 - ex, y0 - (ey - 36)))
        self.no_errors()

    def test_ring_grows(self):
        def radius(data):
            made = self.cast(data)
            return self.lua.eval(f"effect_params( {list(made.values())[0]} ).radius")
        self.assertGreater(radius("element=fire;form=ring;b=grow:1"), radius("element=fire;form=ring;b="))

    def test_forms_of_the_game_s_own_elements(self):
        effect = self.lua.eval("function(e, f) local x = dictionary_effect(e, f) return x.carrier, x.at end")
        self.assertEqual(effect("thunder", "dispersion")[0], "nova")
        for element in ("vacuum", "beam", "thunder", "ball_lightning"):
            self.assertEqual(effect(element, "ring")[0], "ring", element)
        for element in ("vacuum", "beam", "ball_lightning"):
            self.assertEqual(effect(element, "rain"), ("cloud", "sky"), element)


if __name__ == "__main__":
    unittest.main(verbosity=2)
