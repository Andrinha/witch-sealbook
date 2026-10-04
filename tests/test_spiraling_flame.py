"""Flight, terrain occlusion, damage and recognition regressions for Spiraling Flame.

Run from the mod directory: python tests/test_spiraling_flame.py
"""
import random
import unittest

from harness import world_runtime
import wiki_spells as Wiki


def cast(lua, tx=240, ty=-40, legacy=False, extra=""):
    lua.globals().TEST_TX, lua.globals().TEST_TY = tx, ty
    lua.globals().TEST_DATA = (
        "element=fire;form=column;force=0.63;range=0.58;lifetime=0.17;precision=1;stability=1;named=spiraling_flame"
        + ("" if legacy else ";manifest=spiraling_flame") + extra
    )
    return lua.execute('''
        local data = parse_spell_data(TEST_DATA)
        local made = cast_spell(PLAYER, data, 0, -40, 1, 0, TEST_TX, TEST_TY, W.frame, nil)
        return made[1]
    ''')


def book_cast(lua, key="book", legacy=False, tx=240, ty=-40):
    lua.globals().TEST_BOOK = {"book": "spellbook", "quire": "palm_quire", "tome": "great_tome"}[key]
    lua.globals().TEST_KEY = key
    lua.globals().TEST_TX, lua.globals().TEST_TY = tx, ty
    lua.globals().TEST_DATA = (
        "element=fire;form=column;force=0.63;range=0.58;lifetime=0.17;precision=1;stability=1;named=spiraling_flame"
        + ("" if legacy else ";manifest=spiraling_flame")
    )
    return lua.execute('''
        BOOK_ITEM = EntityLoad("mods/witch_notebook/files/entities/" .. TEST_BOOK .. ".xml", 0, -36)
        EntityAddChild(PLAYER, BOOK_ITEM)
        EntitySetTransform(PLAYER, 0, -36)
        EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent"))
        CONTROLS = EntityGetFirstComponent(PLAYER, "ControlsComponent")
        INV = EntityGetFirstComponent(PLAYER, "Inventory2Component")
        ComponentSetValue2(INV, "mActiveItem", BOOK_ITEM)
        ComponentSetValue2(CONTROLS, "enabled", true)
        ComponentSetValue2(CONTROLS, "mMousePosition", TEST_TX, TEST_TY)
        ComponentSetValue2(CONTROLS, "mButtonDownFire", true)
        ComponentSetValue2(CONTROLS, "mButtonFrameFire", W.frame + 1)
        GlobalsSetValue(book_var(TEST_KEY, "active_spell"), TEST_DATA)
        simulate(2)
        return EntityGetWithTag("witch_spiraling_stream")[1]
    ''')


def stream_emitter(lua, effect):
    children = lua.eval("EntityGetAllChildren")(effect)
    plume = next(c for c in children.values() if lua.eval("EntityHasTag")(c, "witch_spiraling_plume"))
    return plume, lua.eval("EntityGetFirstComponent")(plume, "ParticleEmitterComponent")


class SpiralingFlame(unittest.TestCase):
    def test_held_fire_sound_continues_and_stops_with_emission(self):
        lua = world_runtime()
        lua.execute('''
            W.fire_sounds = {}
            function GamePlaySound(bank, event, x, y)
                if event == "player_projectiles/flamethrower/create" then
                    W.fire_sounds[#W.fire_sounds + 1] = {x = x, y = y, frame = W.frame}
                end
            end
        ''')
        effect = book_cast(lua)
        lua.execute("simulate(120)")
        sounds = list(lua.eval("W.fire_sounds").values())
        # A held jet must remain audible well after its initial cast, with a
        # bounded rate rather than a sound per frame or per spawned ember.
        self.assertGreaterEqual(len(sounds), 8)
        self.assertLessEqual(len(sounds), 15)
        self.assertLessEqual(lua.eval("W.frame") - sounds[-1]["frame"], 15)

        lua.execute('EntitySetTransform(PLAYER, 30, -50); simulate(16)')
        params = lua.eval("effect_params")(effect)
        last = list(lua.eval("W.fire_sounds").values())[-1]
        self.assertAlmostEqual(last["x"], params["ox"])
        self.assertAlmostEqual(last["y"], params["oy"])

        before = lua.eval("#W.fire_sounds")
        lua.execute('''
            original_trace = RaytraceSurfacesAndLiquiform
            function RaytraceSurfacesAndLiquiform(x, y) return true, x, y end
            simulate(30)
        ''')
        self.assertEqual(lua.eval("#W.fire_sounds"), before)
        lua.execute('RaytraceSurfacesAndLiquiform = original_trace; simulate(1)')
        self.assertEqual(lua.eval("#W.fire_sounds"), before + 1)

        lua.execute('ComponentSetValue2(CONTROLS, "mButtonDownFire", false); simulate(30)')
        self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
        self.assertEqual(lua.eval("#W.fire_sounds"), before + 1)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_near_cursor_sets_direction_without_shortening_the_jet(self):
        for tx, ty in ((0, -40), (0.5, -40), (3, -40), (-3, -40), (0, -43)):
            with self.subTest(cursor=(tx, ty)):
                lua = world_runtime()
                effect = book_cast(lua, tx=tx, ty=ty)
                lua.execute("simulate(30)")
                p = lua.eval("effect_params")(effect)
                self.assertTrue(lua.eval("EntityGetIsAlive")(effect))
                _, emitter = stream_emitter(lua, effect)
                life = lua.eval("ComponentGetValue2")(emitter, "lifetime_max")
                particles = list(lua.eval('EntityGetWithTag("witch_spiraling_ember")').values())
                flight = lua.eval("effect_params")(particles[-1])
                self.assertAlmostEqual(flight["length"], p["length"])
                self.assertLessEqual(abs(flight["frames"] / 60 * flight["speed"] - p["length"]), p["speed"] / 60)
                self.assertAlmostEqual(p["ox"], p["dx"] * 8)
                self.assertAlmostEqual(p["oy"], -40 + p["dy"] * 8)
                direction = (p["dx"], p["dy"])
                lua.execute('''
                    local p = effect_params(EntityGetWithTag("witch_spiraling_stream")[1])
                    ComponentSetValue2(CONTROLS, "mMousePosition", p.dx * 500, -40 + p.dy * 500)
                    simulate(1)
                ''')
                p = lua.eval("effect_params")(effect)
                self.assertEqual(lua.eval("ComponentGetValue2")(emitter, "lifetime_max"), life)
                self.assertAlmostEqual(p["dx"], direction[0])
                self.assertAlmostEqual(p["dy"], direction[1])
                self.assertFalse(list(lua.eval("W.errors").values()))

    def test_particle_flow_widens_with_travel_and_uses_native_fire_damage(self):
        lua = world_runtime()
        effect = book_cast(lua)
        lua.execute('''
            function fx_dot() error("A held flame must use native particles, not a drawn beam") end
            W.flow_points = {}
            for frame = 1, 300 do
                simulate(1)
                for _, id in ipairs(EntityGetWithTag("witch_spiraling_ember")) do
                    local x, y = EntityGetTransform(id)
                    W.flow_points[#W.flow_points + 1] = {x = x, y = y}
                end
            end
        ''')
        p = lua.eval("effect_params")(effect)
        samples = [(v["x"], v["y"]) for v in lua.eval("W.flow_points").values()]
        near = [abs(y - p["oy"]) for x, y in samples if 0.1 <= (x - p["ox"]) / p["length"] <= 0.25]
        far = [abs(y - p["oy"]) for x, y in samples if 0.65 <= (x - p["ox"]) / p["length"] <= 1]
        self.assertGreater(max(far), max(near) * 2)
        _, emitter = stream_emitter(lua, effect)
        get = lambda key: lua.eval("ComponentGetValue2")(emitter, key)
        self.assertEqual(get("emitted_material_name"), "fire")
        self.assertEqual(get("custom_style"), "FIRE")
        self.assertEqual(get("emit_real_particles"), 1)
        self.assertEqual(get("create_real_particles"), 0)
        self.assertEqual(get("emit_cosmetic_particles"), 0)
        self.assertEqual(get("direction_random_deg"), 0)
        self.assertEqual(get("is_trail"), 0)
        self.assertEqual(get("attractor_force"), 0)
        self.assertLess(get("gravity")[1], 0)
        self.assertGreater(get("area_circle_radius")[1], 0)
        self.assertTrue(get("fade_based_on_lifetime"))
        # no enemy near the flow: nothing is hurt
        self.assertFalse(list(lua.eval("W.hits").values()))
        light = list(lua.eval("EntityGetComponent")(effect, "LightComponent").values())[-1]
        self.assertEqual(lua.eval("ComponentGetValue2")(light, "radius"), 80)
        self.assertTrue(any(lua.eval("ComponentGetValue2")(c, "fog_of_war_hole")
                            for c in lua.eval("EntityGetComponent")(effect, "SpriteComponent").values()))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_held_fire_sustains_one_bounded_jet_in_every_book(self):
        for key in ("book", "quire", "tome"):
            with self.subTest(book=key):
                lua = world_runtime()
                effect = book_cast(lua, key)
                self.assertIsNotNone(effect)
                for _ in range(240):
                    lua.execute("W.particles = 0; simulate(1); W.max_particles = math.max(W.max_particles, W.particles)")
                self.assertTrue(lua.eval("EntityGetIsAlive")(effect))
                self.assertEqual(list(lua.eval('EntityGetWithTag("witch_spiraling_stream")').values()), [effect])
                p = lua.eval("effect_params")(effect)
                _, emitter = stream_emitter(lua, effect)
                particles = list(lua.eval('EntityGetWithTag("witch_spiraling_ember")').values())
                self.assertAlmostEqual(lua.eval("effect_params")(particles[-1])["length"], p["length"])
                self.assertLessEqual(lua.eval("ComponentGetValue2")(emitter, "count_max"), 8)
                self.assertLessEqual(len(particles), 15)
                self.assertLess(lua.eval("W.max_particles"), 800)
                self.assertGreater(lua.eval("W.real_fire"), 0)
                self.assertLessEqual(lua.eval("W.real_fire"), 200)
                self.assertFalse(list(lua.eval("W.errors").values()))

    def test_live_aim_and_caster_movement_change_the_jet(self):
        lua = world_runtime()
        effect = book_cast(lua)
        lua.execute('''
            simulate(30)
            EntitySetTransform(PLAYER, 30, -56)
            ComponentSetValue2(CONTROLS, "mMousePosition", -200, -120)
            simulate(1)
        ''')
        p = lua.eval("effect_params")(effect)
        x, y, *_ = lua.eval("EntityGetTransform")(effect)
        self.assertLess(p["dx"], 0)
        self.assertLess(p["dy"], 0)
        self.assertAlmostEqual(p["ox"], 30 + p["dx"] * 8)
        self.assertAlmostEqual(p["oy"], -60 + p["dy"] * 8)
        self.assertAlmostEqual(x, p["ox"])
        self.assertAlmostEqual(y, p["oy"])
        lua.execute('ComponentSetValue2(CONTROLS, "mMousePosition", 30, -60); simulate(1)')
        self.assertTrue(lua.eval("EntityGetIsAlive")(effect))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_stream_stops_when_input_or_book_is_no_longer_valid(self):
        changes = {
            "release": 'ComponentSetValue2(CONTROLS, "mButtonDownFire", false)',
            "open_book": 'ComponentSetValue2(CONTROLS, "enabled", false)',
            "switch_item": 'ComponentSetValue2(INV, "mActiveItem", INVENTORY[3])',
            "change_page": 'GlobalsSetValue(book_var(TEST_KEY, "active_spell"), "element=water;form=column")',
            "drop_book": 'EntityRemoveFromParent(BOOK_ITEM)',
            "delete_book": 'EntityKill(BOOK_ITEM)',
            "dead_owner": 'EntityKill(PLAYER)',
            "missing_controls": 'EntityRemoveComponent(PLAYER, CONTROLS)',
            "busy": 'GlobalsSetValue(BUSY_VAR, tostring(W.frame + 100))',
        }
        for name, change in changes.items():
            with self.subTest(reason=name):
                lua = world_runtime()
                effect = book_cast(lua)
                lua.execute("simulate(30)")
                plume, _ = stream_emitter(lua, effect)
                existing = set(lua.eval('EntityGetWithTag("witch_spiraling_ember")').values())
                lua.execute(change + "; simulate(1)")
                self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
                self.assertFalse(lua.eval("EntityGetIsAlive")(plume))
                self.assertLessEqual(set(lua.eval('EntityGetWithTag("witch_spiraling_ember")').values()), existing)
                lua.execute("simulate(60)")
                self.assertFalse(list(lua.eval('EntityGetWithTag("witch_spiraling_ember")').values()))
                self.assertFalse(list(lua.eval("W.errors").values()))

    def test_particle_flow_and_ignition_cannot_cross_a_wall(self):
        lua = world_runtime()
        lua.execute('''
            EntitySetTransform(ENEMIES[1], 35, -36)
            EntitySetTransform(ENEMIES[2], 60, -36)
            EntitySetTransform(ENEMIES[3], 35, -100)
            for _, id in ipairs(ENEMIES) do EntityRemoveComponent(id, EntityGetFirstComponent(id, "CharacterDataComponent")) end
            function RaytraceSurfaces(x1, y1, x2, y2)
                if (x1 - 50) * (x2 - 50) <= 0 and x1 ~= x2 then
                    local t = (50 - x1) / (x2 - x1)
                    return true, 50, y1 + (y2 - y1) * t
                end
                return false, x2, y2
            end
            RaytraceSurfacesAndLiquiform = RaytraceSurfaces
            local particle = GameCreateParticle
            function GameCreateParticle(m, x, y, ...)
                assert(m ~= "fire" or x < 50, "fire crossed the wall")
                particle(m, x, y, ...)
            end
        ''')
        effect = book_cast(lua)
        lua.execute("simulate(90)")
        self.assertGreater(lua.eval("W.real_fire"), 0)
        # the flame burns the enemy before the wall, at most once per six frames, and none behind it or off its path
        hits = [(h["id"], h["frame"]) for h in lua.eval("W.hits").values()]
        first = lua.eval("ENEMIES[1]")
        self.assertTrue(hits)
        self.assertEqual({who for who, _ in hits}, {first})
        frames = sorted(frame for _, frame in hits)
        self.assertTrue(all(b - a >= 6 for a, b in zip(frames, frames[1:])))
        self.assertTrue(all(h["kind"] == "DAMAGE_FIRE" for h in lua.eval("W.hits").values()))
        _, emitter = stream_emitter(lua, effect)
        self.assertTrue(lua.eval("ComponentGetValue2")(emitter, "collide_with_grid"))
        lua.execute('''
            -- Put the same wall inside the eight-pixel hand offset.
            EntitySetTransform(PLAYER, 47, -36)
            simulate(30) -- let fire already emitted reach the wall and expire
            W.real_fire = 0
            simulate(6)
        ''')
        self.assertFalse(lua.eval("ComponentGetValue2")(emitter, "is_emitting"))
        self.assertEqual(lua.eval("W.real_fire"), 0)
        lua.execute('ComponentSetValue2(CONTROLS, "mMousePosition", 47, -200); simulate(1)')
        self.assertTrue(lua.eval("ComponentGetValue2")(emitter, "is_emitting"))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_repress_restarts_and_amplification_is_spent_once_per_stream(self):
        lua = world_runtime()
        lua.execute('GlobalsSetValue(AMPLIFY_VAR, "3")')
        effect = book_cast(lua, legacy=True)
        lua.execute("simulate(60)")
        self.assertEqual(lua.eval('GlobalsGetValue(AMPLIFY_VAR, "0")'), "2")
        lua.execute('ComponentSetValue2(CONTROLS, "mButtonDownFire", false); simulate(1)')
        self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
        lua.execute('''
            ComponentSetValue2(CONTROLS, "mButtonDownFire", true)
            ComponentSetValue2(CONTROLS, "mButtonFrameFire", W.frame + 1)
            simulate(2)
        ''')
        ids = list(lua.eval('EntityGetWithTag("witch_spiraling_stream")').values())
        self.assertEqual(len(ids), 1)
        self.assertNotEqual(ids[0], effect)
        self.assertEqual(lua.eval('GlobalsGetValue(AMPLIFY_VAR, "0")'), "1")
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_old_particles_keep_their_direction_when_the_nozzle_turns_or_moves(self):
        lua = world_runtime()
        baseline = world_runtime()
        book_cast(baseline)
        baseline.execute("simulate(7)")
        effect = book_cast(lua)
        lua.execute("simulate(7)")
        old = list(lua.eval('EntityGetWithTag("witch_spiraling_ember")').values())[0]
        old_ids = set(lua.eval('EntityGetWithTag("witch_spiraling_ember")').values())
        before = lua.eval("effect_params")(old)
        vx, vy = before["vx"], before["vy"]
        x0, y0, *_ = lua.eval("EntityGetTransform")(old)
        _, emitter = stream_emitter(lua, effect)
        self.assertGreater(vx, 200)
        lua.execute('''
            EntitySetTransform(PLAYER, 100, -36)
            ComponentSetValue2(CONTROLS, "mMousePosition", 100, -240)
            simulate(6)
        ''')
        after = lua.eval("effect_params")(old)
        x1, y1, *_ = lua.eval("EntityGetTransform")(old)
        self.assertEqual((after["vx"], after["vy"]), (vx, vy))
        baseline.execute("simulate(6)")
        bx, by, *_ = baseline.eval("EntityGetTransform")(old)
        self.assertAlmostEqual(x1, bx)
        self.assertAlmostEqual(y1, by)
        self.assertLess(x1, 100)  # the old plume was not dragged to the new hand position
        new = next(c for c in lua.eval('EntityGetWithTag("witch_spiraling_ember")').values() if c not in old_ids)
        self.assertLess(lua.eval("effect_params")(new)["vy"], -200)
        lua.execute('ComponentSetValue2(CONTROLS, "mButtonDownFire", false); simulate(1)')
        self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
        self.assertTrue(lua.eval("EntityGetIsAlive")(old))
        self.assertTrue(lua.eval("EntityGetIsAlive")(new))
        lua.execute("simulate(60)")
        self.assertFalse(list(lua.eval('EntityGetWithTag("witch_spiraling_ember")').values()))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_water_extinguishes_flow_and_releasing_does_not_inject_more_fire(self):
        lua = world_runtime()
        effect = book_cast(lua)
        lua.execute('''
            simulate(7)
            local trace = RaytraceSurfacesAndLiquiform
            SUBMERGED = true
            function RaytraceSurfacesAndLiquiform(x1, y1, x2, y2)
                if SUBMERGED then return true, x1, y1 end
                return trace(x1, y1, x2, y2)
            end
            W.real_fire = 0
            simulate(30)
        ''')
        _, emitter = stream_emitter(lua, effect)
        self.assertFalse(lua.eval("ComponentGetValue2")(emitter, "is_emitting"))
        self.assertEqual(lua.eval("W.real_fire"), 0)
        self.assertFalse(list(lua.eval('EntityGetWithTag("witch_spiraling_ember")').values()))
        self.assertTrue(lua.eval("EntityGetIsAlive")(effect))
        lua.execute("SUBMERGED = false; simulate(30)")
        self.assertTrue(lua.eval("ComponentGetValue2")(emitter, "is_emitting"))
        self.assertGreater(lua.eval("W.real_fire"), 0)
        self.assertFalse(list(lua.eval("W.hits").values()))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_each_particle_rotates_during_flight_and_reverse_spin_mirrors_it(self):
        paths = []
        for spin in (1, -1):
            lua = world_runtime()
            lua.globals().TEST_SPIN = spin
            particle = lua.execute('''
                return effect_spawn("flame", "ember", 8, -40, {
                    ox = 8, oy = -40, dx = 1, dy = 0, speed = 250, length = 67, r = 9,
                    phase = 0, turns = 1.5, spin = TEST_SPIN, frames = 17, fuel = 0,
                    owner = PLAYER, hidden = false
                })
            ''')
            path = []
            for step in range(16):
                lua.execute("simulate(1)")
                x, y, *_ = lua.eval("EntityGetTransform")(particle)
                path.append((x, y))
            # A single particle crosses its own launch axis repeatedly; merely
            # oscillating the nozzle's birth velocity would leave a straight path.
            sides = [y + 40 + 12.5 * ((i + 1) / 60) ** 2 for i, (x, y) in enumerate(path)]
            self.assertGreater(max(sides), 8)
            self.assertLess(min(sides), -8)
            self.assertGreaterEqual(sum(a * b < 0 for a, b in zip(sides, sides[1:])), 2)
            self.assertTrue(all(b[0] > a[0] for a, b in zip(path, path[1:])))
            child = list(lua.eval("EntityGetAllChildren")(particle).values())[0]
            emitter = lua.eval("EntityGetFirstComponent")(child, "ParticleEmitterComponent")
            self.assertEqual(lua.eval("ComponentGetValue2")(emitter, "custom_style"), "FIRE")
            self.assertEqual(lua.eval("ComponentGetValue2")(emitter, "emit_real_particles"), 1)
            self.assertLess(lua.eval("ComponentGetValue2")(emitter, "lifetime_max"), 0.1)
            self.assertLessEqual(lua.eval("ComponentGetValue2")(emitter, "count_max"), 2)
            lua.execute("simulate(2)")
            self.assertFalse(lua.eval("EntityGetIsAlive")(particle))
            self.assertFalse(lua.eval("EntityGetIsAlive")(child))
            self.assertFalse(list(lua.eval("W.errors").values()))
            paths.append(path)
        for i, (a, b) in enumerate(zip(*paths)):
            self.assertAlmostEqual(a[0], b[0])
            self.assertAlmostEqual(a[1] + b[1], -80 - 25 * ((i + 1) / 60) ** 2)

    def test_side_wall_blocks_the_curved_particle_even_when_its_axis_is_clear(self):
        lua = world_runtime()
        lua.execute('''
            function RaytraceSurfacesAndLiquiform(x1, y1, x2, y2)
                if (y1 + 45) * (y2 + 45) <= 0 and y1 ~= y2 then
                    local t = (-45 - y1) / (y2 - y1)
                    return true, x1 + (x2 - x1) * t, -45
                end
                return false, x2, y2
            end
            local particle = GameCreateParticle
            function GameCreateParticle(m, x, y, ...)
                assert(m ~= "fire" or y > -45, "fire crossed the side wall")
                particle(m, x, y, ...)
            end
        ''')
        particle = lua.execute('''
            return effect_spawn("flame", "ember", 8, -40, {
                ox = 8, oy = -40, dx = 1, dy = 0, speed = 250, length = 67, r = 9,
                phase = 0, turns = 1.5, spin = 1, frames = 17, fuel = 1, owner = PLAYER
            })
        ''')
        lua.execute("simulate(4)")
        self.assertTrue(lua.eval("EntityGetIsAlive")(particle))
        child = list(lua.eval("EntityGetAllChildren")(particle).values())[0]
        lua.execute("simulate(12)")
        self.assertFalse(lua.eval("EntityGetIsAlive")(particle))
        self.assertFalse(lua.eval("EntityGetIsAlive")(child))
        x, y, *_ = lua.eval("EntityGetTransform")(particle)
        self.assertGreater(y, -45)
        self.assertLess(x, 8 + 67)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_straight_axis_and_cleanup(self):
        for tx, ty in ((240, -40), (-200, -140), (0, -250), (0, -40), (3, -40)):
            with self.subTest(target=(tx, ty)):
                lua = world_runtime()
                effect = cast(lua, tx, ty)
                p = lua.eval("effect_params")(effect)
                self.assertEqual(p["kind"], "flame")
                samples = []
                for _ in range(160):
                    lua.execute("W.particles = 0; simulate(1); W.max_particles = math.max(W.max_particles, W.particles)")
                    if lua.eval("EntityGetIsAlive")(effect):
                        x, y, *_ = lua.eval("EntityGetTransform")(effect)
                        samples.append((x, y))
                        cross = (x - p["ox"]) * p["dy"] - (y - p["oy"]) * p["dx"]
                        self.assertAlmostEqual(cross, 0, places=6)
                        along = (x - p["ox"]) * p["dx"] + (y - p["oy"]) * p["dy"]
                        self.assertLessEqual(along, p["reach"] + 0.001)
                self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
                self.assertLess(lua.eval("W.max_particles"), 800)
                self.assertFalse(list(lua.eval("W.errors").values()))
                self.assertTrue(samples or tx == 3)

    def test_wall_blocks_flight_damage_and_real_fire(self):
        lua = world_runtime()
        lua.execute('''
            EntitySetTransform(ENEMIES[1], 62, -36)
            EntitySetTransform(ENEMIES[2], 105, -36)
            EntitySetTransform(ENEMIES[3], 110, -36)
            function RaytraceSurfaces(x1, y1, x2, y2)
                if (x1 - 80) * (x2 - 80) <= 0 and x1 ~= x2 then
                    local t = (80 - x1) / (x2 - x1)
                    return true, 80, y1 + (y2 - y1) * t
                end
                return false, x2, y2
            end
        ''')
        effect = cast(lua)
        lua.execute("simulate(120)")
        hits = list(lua.eval("W.hits").values())
        self.assertTrue(hits)
        for hit in hits:
            self.assertEqual(hit["id"], lua.eval("ENEMIES[1]"))
            self.assertEqual(hit["who"], lua.eval("PLAYER"))
            self.assertEqual(hit["kind"], "DAMAGE_FIRE")
        self.assertGreater(lua.eval("W.real_fire"), 0)
        self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
        self.assertLessEqual(lua.eval("effect_params")(effect)["head"], 71)

    def test_damage_follows_the_whole_column_with_cooldown(self):
        lua = world_runtime()
        lua.execute('''
            EntitySetTransform(ENEMIES[1], 60, -36)
            EntitySetTransform(ENEMIES[2], 110, -36)
            EntitySetTransform(ENEMIES[3], 60, -100)
            for _, id in ipairs(ENEMIES) do EntityRemoveComponent(id, EntityGetFirstComponent(id, "CharacterDataComponent")) end
        ''')
        cast(lua)
        lua.execute("simulate(120)")
        hits = list(lua.eval("W.hits").values())
        self.assertEqual({hit["id"] for hit in hits}, {lua.eval("ENEMIES[1]"), lua.eval("ENEMIES[2]")})
        for target in (lua.eval("ENEMIES[1]"), lua.eval("ENEMIES[2]")):
            frames = [hit["frame"] for hit in hits if hit["id"] == target]
            self.assertGreaterEqual(len(frames), 2)
            self.assertTrue(all(b - a >= 6 for a, b in zip(frames, frames[1:])))

    def test_old_saved_pages_and_clear_ink(self):
        lua = world_runtime()
        effect = cast(lua, legacy=True, extra=";ink=clear:1")
        p = lua.eval("effect_params")(effect)
        self.assertEqual((p["kind"], p["mode"], p["hidden"]), ("flame", "spiral", 1))
        lua.execute("simulate(120)")
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_wiki_redraw_is_recognized_by_hand(self):
        lua = Wiki.load()
        entry = lua.eval('GRIMOIRE_BY_KEY.spiraling_flame')
        base = Wiki.page(lua, entry)
        rng = random.Random(73)
        for draw in (Wiki.by_hand, lambda b, r: Wiki.as_player(b, r, True)):
            for _ in range(8):
                named, _ = Wiki.read(lua, draw(base, rng))
                self.assertEqual(named, "spiraling_flame")
        self.assertIn("manifest=spiraling_flame", entry["spell"])


if __name__ == "__main__":
    unittest.main()
