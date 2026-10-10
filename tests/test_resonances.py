"""Resonances (files/resonances.lua, files/resonance_cast.lua): seals whose element, form and signs together make something
of their own. Each resonance's recipe resonates and keeps the signs it is made of; a wiki's seal never resonates; the
summary and the notes name it; and in the small world each does what its notes say.

python tests/test_resonances.py
"""
import math
import unittest

from harness import WORLD_FILES, bare_world, load_mod, read_mod_file

FORMS = {  # the Test Book's forms as signs: (sign, inverted) pairs
    "Splash": [],
    "Column": [("column", False)] * 2,
    "Orb": [("levitation", False)] * 2 + [("column", False)],
    "Hanging": [("levitation", False)] * 2,
    "Wave": [("dispersion", False)] * 2,
    "Field": [("dispersion", False), ("stability", False)],
    "Rain": [],
    "Ring": [("regions", False), ("regions", True), ("regions", False), ("regions", True)],
}
SIGILS = {"fire": "fire", "water": "water", "wind": "wind", "earth": "earth", "light": "light", "crystal": "crystal",
          "flicker": "flicker", "sand": "sand", "thunder": "lightning"}


def world():
    lua = bare_world(WORLD_FILES + ["files/carriers.lua"])
    lua.execute("carriers_create()")
    return lua


def tree(lua, sigils, signs, turn=0.0, frame=None):
    """a seal tree as parse_seal returns it: the sigils in the middle, the signs (key, inverted) evenly round the ring, the
    signs of form turned sideways by 'turn'"""
    syms = [lua.table_from({"kind": "sigil", "key": k, "angle": 0, "dist": 0.05, "size": 0.45, "score": 0.9, "inverted": False})
            for k in sigils]
    n = len(signs)
    for i, (k, inverted) in enumerate(signs):
        a = 2 * math.pi * i / max(n, 1)
        t = turn if k in ("column", "levitation", "regions", "pull") else 0.0
        syms.append(lua.table_from({"kind": "sign", "key": k, "angle": a, "dist": 0.7, "size": 0.25, "score": 0.9,
                                    "inverted": inverted, "turn": t, "dir": a - math.pi + (math.pi if inverted else 0) + t}))
    frames = lua.table_from([lua.table_from({"key": frame, "score": 0.9, "size": 0.95})]) if frame else lua.table()
    return lua.table_from({"ring": lua.table_from({"x": 0, "y": 0, "r": 70, "roundness": 0.0}), "symbols": lua.table_from(syms),
                           "layers": lua.table(), "frames": frames, "subs": lua.table(), "links": lua.table(), "glaives": 0})


def recipe_seal(lua, r, element=None):
    """the seal of a resonance's recipe in its first form, drawn round the element's sigil"""
    recipe = r["recipe"]
    form = list(recipe["forms"].values())[0]
    signs = list(FORMS[form])
    for key in recipe["signs"].values():
        signs += [(key.rstrip("~"), key.endswith("~"))] * 2
    element = element or recipe["element"] or "fire"
    turn = math.radians(45) if recipe["turned"] else 0.0
    return tree(lua, [SIGILS.get(element, element)], signs, turn, "rain" if form == "Rain" else None)


def compiled(lua, seal):
    res = lua.eval("compile_spell")(seal)
    spell = res[0] if isinstance(res, tuple) else res
    assert spell, res
    return spell


class Recipes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = world()
        cls.resonances = list(cls.lua.eval("RESONANCES").values())

    def test_every_recipe_resonates(self):
        wrong = []
        for r in self.resonances:
            spell = compiled(self.lua, recipe_seal(self.lua, r))
            if spell["resonance"] != r["key"]:
                wrong.append(f"{r['key']}: {spell['resonance']} ({spell['summary']})")
                continue
            self.assertIn(r["name"].split()[0], spell["summary"])
            data = self.lua.eval("serialize_spell")(spell)
            self.assertIn("resonance=" + r["key"], data)
            # the signs it is made of stay in the spell, even those that alone do nothing on its carrier
            for key in r["needs"] or {}:
                self.assertIn(key, spell["behaviors"], r["key"])
            if r["forbidden"]:
                self.assertTrue(spell["forbidden"], r["key"])
        self.assertEqual([], wrong)

    def test_the_most_particular_resonance_wins(self):
        lua = self.lua
        # a hot drill still bores a tunnel; a hot crushing shot that doesn't spin melts the rock
        drill = compiled(lua, tree(lua, ["fire"], FORMS["Column"] + [("crush", False)] * 2 + [("windsign", False)] * 2))
        self.assertEqual("drill", drill["resonance"])
        magma = compiled(lua, tree(lua, ["fire"], FORMS["Column"] + [("crush", False)] * 2))
        self.assertEqual("magma", magma["resonance"])
        # Crushing on a water shot is no resonance: the sign grinds as it always does
        plain = compiled(lua, tree(lua, ["water"], FORMS["Column"] + [("crush", False)] * 2))
        self.assertIsNone(plain["resonance"])
        # a sawblade needs something hard: a fire shot turned sideways only spins
        spun = compiled(lua, tree(lua, ["fire"], FORMS["Column"], math.radians(45)))
        self.assertIsNone(spun["resonance"])
        self.assertIn("spin", spun["behaviors"])

    def test_a_lone_sign_that_does_nothing_is_still_left_out(self):
        lua = self.lua
        # Reflection on a fire shot is Ricochet; Diamond is nothing, and a field doesn't fly
        spell = compiled(lua, tree(lua, ["fire"], FORMS["Field"] + [("pierce", False)] * 2))
        self.assertIsNone(spell["resonance"])
        self.assertNotIn("pierce", spell["behaviors"])

    def test_a_wiki_seal_never_resonates(self):
        lua = self.lua
        for entry in lua.eval("GRIMOIRE").values():
            self.assertNotIn("resonance=", entry["spell"], entry["key"])

    def test_the_notes_tell_it(self):
        mod = load_mod()
        notes = mod.eval("spell_notes")
        told = [line["text"] for line in notes("element=fire;form=column;force=0.5;precision=1;stability=1;resonance=ricochet;"
                                               "b=thrust:2,reflect:2").values()]
        self.assertTrue(any(t.startswith("Resonance - Ricochet: ") and "6 times" in t for t in told), told)
        self.assertFalse(any(t.startswith("Reflection:") for t in told), told)  # the sign is told by the resonance
        # one that makes magic of its own tells none of the carrier's numbers
        told = [line["text"] for line in notes("element=fire;form=column;force=0.5;precision=1;stability=1;resonance=breath;"
                                               "b=thrust:2,gust:2").values()]
        self.assertTrue(any("Breath of fire" in t and "real flames" in t for t in told), told)
        self.assertFalse(any("hits for" in t for t in told), told)
        lines = list(notes("element=fire;form=column;force=0.5;precision=1;stability=1;resonance=breath;b=thrust:2,gust:2").values())
        self.assertEqual("Breath of fire: a short cone of the element", lines[0]["text"])  # headed by it, not by the shot
        self.assertFalse(any("fire damage" in l["text"] for l in lines))

    def test_the_grimoire_keeps_what_was_found(self):
        """a resonance found is a page of the grimoire's Discoveries, drawn of its recipe; the footer counts them and gives a
        clue to one not found yet"""
        import run_tests as RT
        mod = load_mod()
        mod.execute(read_mod_file("files/grimoire.lua"))
        mod.execute("said = {} function GuiText( g, x, y, text ) said[#said + 1] = text end")
        G = mod.globals()
        G.notebook_on_player_spawned(1)
        RT.open_book(G, to_blank=False)
        mod.eval("resonance_discover")("ricochet")
        RT.press_button(G, 900007)  # [Grimoire]
        for _ in range(30):
            G.notebook_update()
        mod.execute("said = {}")
        G.notebook_update()
        said = " ".join(mod.eval("said").values())
        self.assertIn("Resonances found: 1 of", said)
        self.assertIn("Seals learned: 0 of", said)  # the discoveries are no wiki seals
        self.assertIn("a clue:", said)
        entry = mod.eval("TestBook.resonance_entry")("ricochet")
        self.assertEqual("res:ricochet", entry["key"])
        self.assertIn("resonance=ricochet", entry["spell"])
        self.assertEqual("Column + Reflection", entry["sign"])
        self.assertGreater(len(list(mod.eval("TestBook.strokes")(entry).values())), 3)
        self.assertIn("Ricochet", said)  # its page's title
        for r in mod.eval("RESONANCES").values():
            self.assertTrue(mod.eval("TestBook.resonance_entry")(r["key"]), r["key"])

    def test_found_once(self):
        mod = load_mod()
        discover = mod.eval("resonance_discover")
        self.assertTrue(discover("ricochet"))
        self.assertFalse(discover("ricochet"))
        self.assertTrue(discover("vortex"))
        self.assertEqual({"ricochet", "vortex"}, set(mod.eval("resonance_found()").keys()))
        self.assertFalse(discover("no_such_thing"))


class InTheWorld(unittest.TestCase):
    def setUp(self):
        self.lua = world()
        self.lua.execute("W.errors = {}; make_world(); W.frame = 1000")

    def cast(self, key, element=None, tx=150, ty=-20):
        r = self.lua.eval("RESONANCE_BY_KEY")[key]
        spell = compiled(self.lua, recipe_seal(self.lua, r, element))
        self.assertEqual(key, spell["resonance"])
        g = self.lua.globals()
        g.TEST_DATA, g.TEST_TX, g.TEST_TY = self.lua.eval("serialize_spell")(spell), tx, ty
        self.first = self.lua.eval("W.next_id")
        made = self.lua.execute('''
            local made = cast_spell( PLAYER, parse_spell_data( TEST_DATA ), 0, GROUND - 8, 0.99, -0.13, TEST_TX, TEST_TY, W.frame, nil )
            local out = {}
            for _, e in ipairs( made ) do out[#out + 1] = e end
            return out
        ''')
        return list(made.values())

    def made_files(self):
        return self.lua.eval(f'''(function()
            local out = {{}}
            for id = {self.first}, W.next_id - 1 do local e = W.entities[id] if e then out[#out + 1] = e.file end end
            return out end)()''').values()

    def entities(self, pattern):
        """the entities made since the cast whose file or name holds 'pattern'"""
        return list(self.lua.eval(f'''(function()
            local out = {{}}
            for id = {self.first}, W.next_id - 1 do
                local e = W.entities[id]
                if e and e.alive and ( e.file:find( "{pattern}", 1, true ) or e.name:find( "{pattern}", 1, true ) ) then out[#out + 1] = id end
            end
            return out end)()''').values())

    def value(self, e, kind, field):
        return self.lua.eval(f'ComponentGetValue2( EntityGetFirstComponentIncludingDisabled( {e}, "{kind}" ), "{field}" )')

    def has(self, e, kind):
        return self.lua.eval(f'EntityGetFirstComponentIncludingDisabled( {e}, "{kind}" ) ~= nil')

    def no_errors(self):
        self.assertEqual([], list(self.lua.eval("W.errors").values()))

    def test_ricochet_bounces(self):
        self.cast("ricochet", "fire")
        shot = self.entities("bolt_fire")[0]
        self.assertGreaterEqual(self.value(shot, "ProjectileComponent", "bounces_left"), 6)
        self.assertTrue(self.value(shot, "ProjectileComponent", "bounce_always"))
        self.no_errors()

    def test_drill_bores_wide(self):
        self.lua.execute("W.added = {}")
        self.cast("drill", "earth")
        shot = self.entities("bolt_earth")[0]
        self.assertTrue(self.value(shot, "ProjectileComponent", "penetrate_world"))
        radii = [c[2]["radius"] for c in self.lua.eval("W.added").values() if c[1] == "MagicConvertMaterialComponent"]
        self.assertGreater(max(radii), 15)
        # it doesn't curl round as a spinning shot does
        self.assertFalse(any("spin.lua" in str(c[2]["script_source_file"]) for c in self.lua.eval("W.added").values()
                             if c[1] == "LuaComponent"))
        self.no_errors()

    def test_boomerang_comes_back(self):
        self.cast("boomerang", "water")
        shot = self.entities("bolt_water")[0]
        far = 0
        for _ in range(120):
            self.lua.execute("simulate( 1 )")
            if not self.lua.eval(f"EntityGetIsAlive( {shot} )"):
                break
            x, y = self.lua.eval(f"EntityGetTransform( {shot} )")[:2]
            far = max(far, math.hypot(x, y - 2))
        self.assertGreater(far, 30)
        self.assertFalse(self.lua.eval(f"EntityGetIsAlive( {shot} )"), "it should be caught again")
        self.no_errors()

    def test_grapple_pulls_the_caster_to_a_wall(self):
        self.cast("grapple", "light")
        shot = self.entities("bolt_light")[0]
        self.lua.execute(f"EntitySetTransform( {shot}, 60, GROUND - 2 ); EntityKill( {shot} )")
        reel = self.entities("witch_resonance_reel")
        self.assertTrue(reel)
        self.lua.execute("simulate( 6 )")
        vx = self.lua.eval('ComponentGetValue2( EntityGetFirstComponent( PLAYER, "CharacterDataComponent" ), "mVelocity" )')[0]
        self.assertGreater(vx, 50)
        self.no_errors()

    def test_grapple_drags_an_enemy(self):
        self.cast("grapple", "light")
        shot = self.entities("bolt_light")[0]
        self.lua.execute(f"local x, y = EntityGetTransform( ENEMIES[1] ) EntitySetTransform( {shot}, x, y - 4 ); EntityKill( {shot} )")
        self.assertTrue(self.entities("witch_resonance_tow"))
        self.lua.execute("simulate( 3 )")
        vx = self.lua.eval('ComponentGetValue2( EntityGetFirstComponent( ENEMIES[1], "CharacterDataComponent" ), "mVelocity" )')[0]
        self.assertLess(vx, -50)
        self.no_errors()

    def test_blink_carries_the_caster(self):
        self.cast("blink", "wind")
        shot = self.entities("bolt_wind")[0]
        self.assertTrue(self.has(shot, "TeleportProjectileComponent"))
        self.no_errors()

    def test_swarm_fans_out_seeking(self):
        made = self.cast("swarm", "fire")
        self.assertEqual(4, len(made))
        shots = self.entities("bolt_fire")
        angles = []
        for s in shots:
            self.assertTrue(self.has(s, "HomingComponent"))
            self.assertFalse(self.value(s, "ProjectileComponent", "penetrate_entities"))  # each mote stops at its enemy
            vx, vy = self.lua.eval(f'ComponentGetValue2( EntityGetFirstComponent( {s}, "VelocityComponent" ), "mVelocity" )')
            angles.append(math.degrees(math.atan2(vy, vx)))
        self.assertGreater(max(angles) - min(angles), 90)
        self.no_errors()

    def test_cluster_bursts(self):
        made = self.cast("cluster", "earth")
        self.assertEqual(1, len(made))  # one big shot, not one for each Piercing sign
        shot = self.entities("bolt_earth")[0]
        self.lua.execute(f"EntityKill( {shot} )")
        self.assertEqual(4, len(self.entities("splash_earth")))
        self.no_errors()

    def test_breath_of_each_nature(self):
        self.assertEqual(["data/entities/projectiles/deck/flamethrower.xml"] * 3, self.cast("breath", "fire"))
        self.lua.execute("make_world()")
        self.assertEqual(["data/entities/projectiles/deck/freezing_gaze_beam.xml"] * 5, self.cast("breath", "crystal"))
        self.lua.execute("make_world()")
        made = self.cast("breath", "sand")
        self.assertEqual(9, len(made))
        self.assertTrue(all("splash_sand" in f for f in made))
        self.no_errors()

    def test_lance_passes_through(self):
        self.cast("lance", "light")
        shot = self.entities("bolt_light")[0]
        self.assertTrue(self.value(shot, "ProjectileComponent", "penetrate_entities"))
        self.assertGreater(self.value(shot, "ProjectileComponent", "ground_penetration_coeff"), 0)
        self.no_errors()

    def test_sawblade(self):
        self.assertEqual(["data/entities/projectiles/deck/disc_bullet.xml"], self.cast("sawblade", "crystal"))
        disc = self.entities("disc_bullet")[0]
        self.assertIn("frozen", self.value(disc, "ProjectileComponent", "damage_game_effect_entities"))
        self.no_errors()

    def test_magma_melts(self):
        self.lua.execute("W.added = {}")
        self.cast("magma", "fire")
        converts = [c[2] for c in self.lua.eval("W.added").values() if c[1] == "MagicConvertMaterialComponent"]
        self.assertTrue(any("lava" in (c["to_material_array"] or "") for c in converts))
        self.lua.execute("make_world(); W.added = {}")
        self.cast("magma", "fire")  # the recipe's first form is the shot; the wave melts too
        self.no_errors()

    def test_frostfire_freezes(self):
        self.cast("frostfire", "fire")
        shot = self.entities("bolt_fire")[0]
        p = f'EntityGetFirstComponentIncludingDisabled( {shot}, "ProjectileComponent" )'
        self.assertEqual(0, self.lua.eval(f'ComponentObjectGetValue2( {p}, "damage_by_type", "fire" )'))
        self.assertGreater(self.lua.eval(f'ComponentObjectGetValue2( {p}, "damage_by_type", "ice" )'), 0)
        effects = self.lua.eval(f'ComponentGetValue2( {p}, "damage_game_effect_entities" )')
        self.assertNotIn("on_fire", effects)
        self.assertIn("frozen", effects)
        self.no_errors()

    def test_sentry_shoots_at_an_enemy(self):
        self.cast("sentry", "fire", tx=40, ty=-10)
        orb = self.entities("orb_fire")[0]
        self.lua.execute(f"EntitySetTransform( {orb}, 30, -10 ); EntitySetTransform( ENEMIES[3], 60, -10 )")
        before = len(self.entities("bolt_fire"))
        self.lua.execute("simulate( 10 )")
        self.assertGreater(len(self.entities("bolt_fire")), before)
        self.no_errors()

    def test_mine_waits_then_bursts(self):
        self.cast("mine", "fire", tx=80, ty=-40)
        orb = self.entities("orb_fire")[0]
        self.lua.execute(f"EntitySetTransform( {orb}, 80, -40 )")
        self.lua.execute("simulate( 9 )")
        self.assertTrue(self.lua.eval(f"EntityGetIsAlive( {orb} )"))
        self.lua.execute(f"EntitySetTransform( ENEMIES[2], 84, -40 ); simulate( 4 )")
        self.assertFalse(self.lua.eval(f"EntityGetIsAlive( {orb} )"))
        self.assertTrue(self.entities("witch_nova_nova"))
        self.no_errors()

    def test_vortex_draws_in_and_round(self):
        self.cast("vortex", "wind", tx=60, ty=-20)
        orb = self.entities("orb_wind")[0]
        self.lua.execute(f'''
            EntitySetTransform( {orb}, 60, -20 )
            EntitySetTransform( ENEMIES[2], 100, -20 )
            EntityRemoveComponent( ENEMIES[2], EntityGetFirstComponent( ENEMIES[2], "CharacterDataComponent" ) )
            EntityAddComponent2( ENEMIES[2], "CharacterDataComponent", {{}} )
            simulate( 1 )
        ''')
        vx, vy = self.lua.eval('ComponentGetValue2( EntityGetFirstComponent( ENEMIES[2], "CharacterDataComponent" ), "mVelocity" )')
        self.assertLess(vx, 0)       # drawn in
        self.assertNotEqual(vy, 0)   # and round
        self.no_errors()

    def test_quake_shakes_the_ground(self):
        self.lua.execute("W.damage = 0")
        made = self.cast("quake", "earth")
        self.assertEqual(2, len(made))
        self.assertTrue(self.entities("witch_resonance_quake"))
        self.lua.execute("simulate( 30 )")
        self.assertGreater(self.lua.eval("W.damage"), 0)
        self.no_errors()

    def test_collapse_draws_in_then_bursts(self):
        self.cast("collapse", "fire")
        wave = self.entities("witch_nova_nova")[0]
        self.lua.execute("simulate( 26 )")
        self.assertFalse(self.lua.eval(f"EntityGetIsAlive( {wave} )"))
        burst = [e for e in self.entities("witch_nova_nova") if e != wave]
        self.assertTrue(burst)
        r_in = self.lua.eval(f"effect_params( {wave} ).r")
        self.assertGreater(self.lua.eval(f"effect_params( {burst[0]} ).r"), r_in * 1.3)
        self.no_errors()

    def test_tide_rolls_both_ways(self):
        self.cast("tide", "water")
        waves = self.entities("witch_mover_wave")
        self.assertEqual(2, len(waves))
        self.assertEqual({-1, 1}, {int(self.lua.eval(f"effect_params( {w} ).dx")) for w in waves})
        self.no_errors()

    def test_forbidden_fields(self):
        for key, element, file in (("healing_spring", "water", "regeneration_field"), ("frenzy", "fire", "berserk_field"),
                                   ("charm", "flicker", "charm_field")):
            self.lua.execute("make_world(); W.globals = {}")
            self.assertEqual([f"data/entities/projectiles/deck/{file}.xml"], self.cast(key, element))
            self.assertTrue(self.entities("witch_knights_come"), key)  # the Knights Moralis come
        self.no_errors()

    def test_rain_of_meteors_and_acid(self):
        made = self.cast("meteors", "earth")
        self.assertEqual(1, len(made))
        self.lua.execute("simulate( 61 )")
        meteors = self.entities("meteor_rain_meteor")
        self.assertTrue(meteors)
        for m in meteors:  # the caster is spared
            self.assertTrue(self.value(m, "ProjectileComponent", "explosion_dont_damage_shooter"))
        self.lua.execute("simulate( 300 )")
        self.assertFalse(self.entities("witch_resonance_meteors"))  # it is over after a few seconds
        self.lua.execute("make_world()")
        self.assertEqual(["data/entities/projectiles/deck/cloud_acid.xml"], self.cast("acid_rain", "water"))
        cloud = self.entities("cloud_acid")[0]
        self.assertLess(self.value(cloud, "ProjectileComponent", "lifetime"), 999)
        self.no_errors()

    def test_halo_turns_shots_back(self):
        self.cast("halo", "fire")
        self.lua.execute('''
            SHOT = EntityCreateNew( "enemy shot" )
            EntitySetTransform( SHOT, 30, GROUND - 10 )
            EntityAddTag( SHOT, "projectile" )
            EntityAddComponent2( SHOT, "ProjectileComponent", { mWhoShot = ENEMIES[1], lifetime = 500 } )
            EntityAddComponent2( SHOT, "VelocityComponent", { mVelocity = { -60, 0 } } )
            simulate( 40 )
        ''')
        who = self.lua.eval('ComponentGetValue2( EntityGetFirstComponent( SHOT, "ProjectileComponent" ), "mWhoShot" )')
        self.assertEqual(who, self.lua.globals().PLAYER)
        self.no_errors()

    def test_blades_cut(self):
        self.lua.execute('''
            W.cuts = 0
            local damage = EntityInflictDamage
            function EntityInflictDamage( id, amount, kind, ... )
                if kind == "DAMAGE_SLICE" then W.cuts = W.cuts + 1 end
                return damage( id, amount, kind, ... )
            end
        ''')
        self.cast("blades", "fire")
        self.lua.execute("EntitySetTransform( ENEMIES[3], 22, GROUND - 10 ); simulate( 60 )")
        self.assertGreater(self.lua.eval("W.cuts"), 0)
        self.no_errors()


    def test_exchange_swaps(self):
        self.cast("exchange", "light")
        shot = self.entities("bolt_light")[0]
        self.assertEqual("SWAPPER", self.value(shot, "HitEffectComponent", "effect_hit"))
        self.no_errors()

    def test_limpet_sticks_then_bursts(self):
        self.cast("limpet", "fire")
        shot = self.entities("bolt_fire")[0]
        self.lua.execute(f"local x, y = EntityGetTransform( ENEMIES[1] ) EntitySetTransform( {shot}, x, y - 4 ); EntityKill( {shot} )")
        limpet = self.entities("witch_resonance_limpet")
        self.assertTrue(limpet)
        self.lua.execute("EntitySetTransform( ENEMIES[1], 100, GROUND - 4 ); simulate( 2 )")
        x = self.lua.eval(f"EntityGetTransform( {limpet[0]} )")[0]
        self.assertLess(abs(x - 100), 3)  # it went with the creature
        self.lua.execute("simulate( 80 )")
        self.assertTrue(self.entities("witch_nova_nova"))
        self.no_errors()

    def test_satellite_circles_the_caster(self):
        self.cast("satellite", "fire")
        orb = self.entities("orb_fire")[0]
        seen = []
        for _ in range(40):
            self.lua.execute("simulate( 1 )")
            x, y = self.lua.eval(f"EntityGetTransform( {orb} )")[:2]
            seen.append((x, y))
        px, py = self.lua.eval("EntityGetTransform( PLAYER )")[:2]
        dists = [math.hypot(x - px, y - (py - 6)) for x, y in seen[20:]]
        self.assertLess(max(dists), 40)
        self.assertGreater(min(dists), 15)
        angles = {round(math.degrees(math.atan2(y - py, x - px)) / 45) for x, y in seen[20:]}
        self.assertGreater(len(angles), 3)  # it goes round
        self.no_errors()

    def test_fountain_pours(self):
        self.cast("fountain", "water", tx=40, ty=-30)
        orb = self.entities("orb_water")[0]
        emitters = self.lua.eval(f'''(function()
            local out = {{}}
            for _, c in ipairs( EntityGetComponentIncludingDisabled( {orb}, "ParticleEmitterComponent" ) or {{}} ) do
                if ComponentGetValue2( c, "create_real_particles" ) == true and ComponentGetValue2( c, "y_vel_min" ) == 10 then
                    out[#out + 1] = ComponentGetValue2( c, "emitted_material_name" )
                end
            end
            return out end)()''')
        self.assertIn("water", list(emitters.values()))
        # an element of no matter has nothing to pour: no fountain
        r = self.lua.eval("RESONANCE_BY_KEY")["fountain"]
        light = compiled(self.lua, recipe_seal(self.lua, r, "light"))
        self.assertNotEqual("fountain", light["resonance"])
        self.no_errors()

    def test_tether_holds(self):
        self.cast("tether", "light", tx=40, ty=-10)
        orb = self.entities("orb_light")[0]
        self.lua.execute(f"EntitySetTransform( {orb}, 40, -10 ); EntitySetTransform( ENEMIES[1], 100, -10 ); simulate( 2 )")
        vx = self.lua.eval('ComponentGetValue2( EntityGetFirstComponent( ENEMIES[1], "CharacterDataComponent" ), "mVelocity" )')[0]
        self.assertLess(vx, -20)  # pulled back towards the orb
        self.no_errors()

    def test_updraft_lifts(self):
        self.cast("updraft", "wind")
        self.assertTrue(self.entities("witch_resonance_updraft"))
        self.lua.execute('''
            local cd = EntityGetFirstComponent( PLAYER, "CharacterDataComponent" )
            ComponentSetValue2( cd, "mFlyingTimeLeft", 0 )
            EntitySetTransform( ENEMIES[3], 20, GROUND - 4 )
            simulate( 3 )
        ''')
        self.assertEqual(self.lua.eval('ComponentGetValue2( EntityGetFirstComponent( PLAYER, "CharacterDataComponent" ), "fly_time_max" )'),
                         self.lua.eval('ComponentGetValue2( EntityGetFirstComponent( PLAYER, "CharacterDataComponent" ), "mFlyingTimeLeft" )'))
        self.no_errors()

    def test_barrage_falls(self):
        made = self.cast("barrage", "crystal", tx=80, ty=-10)
        self.assertEqual(1, len(made))
        self.lua.execute("simulate( 60 )")
        self.assertEqual(10, len([f for f in self.made_files() if "bolt_crystal" in f]))  # a pair of Piercing: 4 + 3 x 2
        self.no_errors()

    def test_fissure_runs_and_throws(self):
        self.lua.execute("W.damage = 0; EntitySetTransform( ENEMIES[3], 40, GROUND - 4 )")
        made = self.cast("fissure", "earth")
        self.assertEqual(1, len(made))
        crack = self.entities("witch_resonance_fissure")[0]
        x0 = self.lua.eval(f"EntityGetTransform( {crack} )")[0]
        self.lua.execute("simulate( 20 )")
        x1 = self.lua.eval(f"EntityGetTransform( {crack} )")[0]
        self.assertGreater(x1, x0 + 30)
        self.assertGreater(self.lua.eval("W.damage"), 0)
        self.no_errors()

    def test_chain_storm_leaps(self):
        self.lua.execute("W.damage = 0")
        self.cast("chain_storm", "thunder")
        self.assertTrue(self.entities("witch_resonance_arcs"))
        self.lua.execute("simulate( 30 )")
        self.assertGreater(self.lua.eval("W.damage"), 0)
        self.no_errors()

    def test_rampart_sets_a_ring(self):
        self.cast("rampart", "earth")
        pieces = [f for f in self.made_files() if "/solid/stone_block" in f]
        self.assertGreaterEqual(len(pieces), 6)  # not into the ground under the caster
        self.no_errors()

    def test_guardian_lights_fly_at_enemies(self):
        self.cast("guardian", "light")
        ring = self.entities("witch_orbit_ring")[0]
        lights = self.lua.eval(f"effect_params( {ring} ).count")
        self.lua.execute("EntitySetTransform( ENEMIES[3], 50, GROUND - 4 ); simulate( 40 )")
        self.assertGreater(len(self.entities("bolt_light")), 0)
        self.assertLess(self.lua.eval(f"effect_params( {ring} ).count"), lights)
        self.no_errors()


    def strike(self, file_part, enemy=1):
        """the shot ends on an enemy"""
        shot = self.entities(file_part)[0]
        self.lua.execute(f"local x, y = EntityGetTransform( ENEMIES[{enemy}] ) EntitySetTransform( {shot}, x, y - 4 ); EntityKill( {shot} )")

    def has_effect(self, enemy, name):
        return self.lua.eval(f'''(function() for _, c in ipairs( EntityGetAllChildren( ENEMIES[{enemy}] ) or {{}} ) do
            if EntityGetFilename( c ):find( "{name}", 1, true ) or EntityGetName( c ):find( "{name}", 1, true ) then return true end
            end return false end)()''')

    def test_ice_coffin_freezes(self):
        self.cast("ice_coffin", "crystal")
        self.strike("bolt_crystal")
        self.assertTrue(self.has_effect(1, "effect_frozen.xml"))
        self.assertTrue(self.has_effect(1, "witch_held_"))
        self.no_errors()

    def test_entomb_walls_in(self):
        self.lua.execute("EntitySetTransform( ENEMIES[2], 150, -30 )")
        self.cast("entomb", "earth")
        self.strike("bolt_earth", 2)
        self.assertGreaterEqual(len([f for f in self.made_files() if "/solid/stone_block" in f]), 4)
        self.assertTrue(self.has_effect(2, "witch_held_"))
        self.no_errors()

    def test_cyclone_lifts(self):
        self.cast("cyclone", "wind")
        y0 = self.lua.eval("EntityGetTransform( ENEMIES[1] )")[1]
        self.strike("bolt_wind")
        self.assertTrue(self.entities("witch_resonance_cyclone"))
        self.lua.execute("simulate( 30 )")
        self.assertLess(self.lua.eval("EntityGetTransform( ENEMIES[1] )")[1], y0 - 15)
        self.no_errors()

    def test_wisp_hunts_through_walls(self):
        self.cast("wisp", "unburning")
        wisp = self.entities("bolt_phantasm")[0]
        self.assertTrue(self.has(wisp, "HomingComponent"))
        self.assertFalse(self.value(wisp, "ProjectileComponent", "collide_with_world"))
        self.assertGreater(self.value(wisp, "ProjectileComponent", "lifetime"), 200)
        self.lua.execute(f"local x, y = EntityGetTransform( {wisp} ) EntitySetTransform( ENEMIES[3], x, y ); simulate( 4 )")
        self.assertTrue(self.has_effect(3, "effect_confusion"))
        self.no_errors()

    def test_fireworks(self):
        made = self.cast("fireworks", "flicker")
        self.assertEqual(2, len(made))
        self.assertTrue(all("/fireworks/firework_" in f for f in made))
        self.no_errors()

    def test_pillar_rises(self):
        self.cast("pillar", "earth")
        shot = self.entities("bolt_earth")[0]
        self.lua.execute(f"EntitySetTransform( {shot}, 60, GROUND - 5 ); EntityKill( {shot} )")
        blocks = [e for e in self.entities("/solid/stone_block")]
        self.assertGreaterEqual(len(blocks), 3)
        ys = sorted(self.lua.eval(f"EntityGetTransform( {b} )")[1] for b in blocks)
        self.assertGreater(ys[-1] - ys[0], 15)  # one over another
        self.no_errors()

    def test_sunburst_blinds(self):
        self.cast("sunburst", "light")
        self.strike("bolt_light")
        self.assertTrue(self.has_effect(1, "effect_blindness"))
        self.no_errors()


if __name__ == "__main__":
    unittest.main(verbosity=2)
