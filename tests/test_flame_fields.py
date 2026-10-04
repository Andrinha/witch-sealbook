"""Fluid rings, burst jets and violet flames: persistence, occlusion and budgets.

python tests/test_flame_fields.py
"""
import math
import unittest
from fluid_render_capture import sprites

from harness import world_runtime, cast_page, freeze_enemies, wall
from test_effect_profiler import enable


def emitters(lua, effect):
    return [child for child in (lua.eval("EntityGetAllChildren")(effect) or {}).values()
            if lua.eval("EntityHasTag")(child, "witch_fluid_fire_emitter")]


def field(lua, effect):
    state = lua.globals().FlameFields.states[effect]
    return {name: list(state[name].values()) for name in ("d", "u", "v")}


class FlameFields(unittest.TestCase):
    def assert_clean(self, lua):
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_all_presets_evolve_independent_finite_density_and_velocity(self):
        lua = world_runtime()
        effects = [cast_page(lua, key, 500, -40) for key in
                   ("ring_of_fire", "flame_burst", "forbidden_flames", "pyreball")]
        lua.execute("simulate(12)")
        states = [lua.globals().FlameFields.states[e] for e in effects]
        self.assertEqual([(s.model.width, s.model.height) for s in states],
                         [(32, 32), (28, 18), (20, 24), (24, 28)])
        before = [field(lua, e) for e in effects]
        lua.eval("simulate")(6)
        for effect, previous in zip(effects, before):
            current = field(lua, effect)
            self.assertNotEqual(current, previous)
            self.assertGreater(sum(current["d"]), 0)
            self.assertTrue(all(math.isfinite(v) for values in current.values() for v in values))
            self.assertTrue(all(0 <= d <= 3.2 for d in current["d"]))
            curl = list(lua.globals().FlameFields.states[effect].curl.values())
            self.assertLess(min(curl), -0.001)
            self.assertGreater(max(curl), 0.001)
        self.assertFalse(lua.eval("rawequal")(states[0].d, states[1].d))
        self.assertFalse(lua.eval("rawequal")(states[0].pressure_a, states[2].pressure_a))
        self.assert_clean(lua)

    def test_ring_stops_injection_and_cools_after_expansion(self):
        lua = world_runtime()
        e = cast_page(lua, "ring_of_fire")
        lua.eval("effect_set")(e, "frames", 100)
        grow = int(lua.eval("effect_params")(e)["grow"])
        lua.eval("simulate")(grow + 2)
        mass = sum(field(lua, e)["d"])
        previous = field(lua, e)
        lua.eval("simulate")(12)
        self.assertLess(sum(field(lua, e)["d"]), mass * 0.55)
        self.assertNotEqual(field(lua, e)["u"], previous["u"])
        self.assert_clean(lua)

    def test_ring_and_blast_circulation_transports_heat_beyond_the_static_inlet(self):
        # A control uses the same inlet, seed, decay and time steps, but no flow.
        # Texture variation alone must not satisfy the turbulence regression.
        for radius, grow, age in ((55, 28, 34), (80, 16, 24)):
            with self.subTest(radius=radius):
                results = []
                for still in (False, True):
                    lua = world_runtime()
                    lua.globals().TEST_RADIUS, lua.globals().TEST_GROW = radius, grow
                    lua.globals().TEST_AGE, lua.globals().TEST_STILL = age, still
                    lua.execute('''
                        dofile_once("mods/witch_notebook/files/effects/flame_fields.lua")
                        local F=FlameFields.presets.ring.model
                        local source=F.source
                        if TEST_STILL then
                            F.tuning.vorticity,F.tuning.buoyancy=0,0
                            F.source=function(s,p,age,dt)
                                source(s,p,age,dt)
                                for i=1,#s.u do s.u[i],s.v[i]=0,0 end
                            end
                        end
                        TEST_FRAME={ox=0,oy=-40,head=0,dx=1,dy=0,speed=0,
                            r=TEST_RADIUS,grow=TEST_GROW,blast=TEST_GROW==16,cell=TEST_RADIUS*2.8/32}
                        TEST_STATE=F.new(TEST_FRAME,23)
                        for age=0,TEST_AGE,2 do F.step(TEST_STATE,TEST_FRAME,age,2/60) end
                    ''')
                    state = lua.globals().TEST_STATE
                    density = list(state.d.values())
                    results.append(density)
                    if not still:
                        weighted_curl = sum(abs(c) * d for c, d in zip(state.curl.values(), density)) / sum(density)
                        self.assertGreater(weighted_curl, 4)
                        self.assertTrue(all(math.isfinite(v) for v in state.u.values()))
                        self.assertTrue(all(math.isfinite(v) for v in state.v.values()))
                    self.assert_clean(lua)
                transport = sum(abs(a - b) for a, b in zip(*results)) / sum(results[1])
                self.assertGreater(transport, 0.4)

    def test_circulation_is_an_initial_impulse_and_is_not_reseeded_each_tick(self):
        lua = world_runtime()
        launched, later, expired = lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/flame_fields.lua")
            local F=FlameFields.presets.ring.model
            local p={ox=0,oy=-40,head=0,dx=1,dy=0,speed=0,r=80,grow=16,cell=7}
            local function speed(age)
                local s=F.new(p,23);F.mask(s,p);F.source(s,p,age,2/60)
                local sum=0
                for i=1,#s.u do sum=sum+math.abs(s.u[i])+math.abs(s.v[i]) end
                return sum
            end
            return speed(0),speed(2),speed(18)
        ''')
        self.assertGreater(launched, later * 20)
        self.assertEqual(expired, 0)
        self.assert_clean(lua)

    def test_profiling_counts_all_fields_without_changing_their_evolution(self):
        for key in ("ring_of_fire", "flame_burst", "forbidden_flames", "pyreball"):
            with self.subTest(spell=key):
                off, on = world_runtime(), world_runtime()
                enable(on)
                a, b = cast_page(off, key, 500, -40), cast_page(on, key, 500, -40)
                off.eval("simulate")(16)
                on.eval("simulate")(15)
                on.execute('''
                    W.observed_rays = 0
                    local ray = RaytraceSurfacesAndLiquiform
                    function RaytraceSurfacesAndLiquiform(...)
                        W.observed_rays = W.observed_rays + 1
                        return ray(...)
                    end
                    simulate(1)
                ''')
                self.assertEqual(field(off, a), field(on, b))
                profile = on.globals().EffectProfiler
                self.assertGreater(profile.row[profile.index["pixels"]], 0)
                self.assertGreater(profile.row[profile.index["save"]], 0)
                self.assertEqual(profile.row[profile.index["rays"]], on.eval("W.observed_rays"))
                self.assertTrue(all(s.meter is None for s in on.globals().FlameFields.states.values()))
                self.assert_clean(on)

    def test_concurrent_rings_and_plumes_stagger_steady_solver_ticks(self):
        for key, period in (("ring_of_fire", 2), ("forbidden_flames", 4), ("pyreball", 4)):
            with self.subTest(spell=key):
                lua = world_runtime()
                effects = [cast_page(lua, key, 20 + i * 7 if key == "pyreball" else 200) for i in range(6)]
                self.assertEqual(len(set(effects)), 6)
                lua.eval("simulate")(1)
                model = lua.globals().FlameFields.states[effects[0]].model
                lua.globals().TEST_MODEL = model
                lua.execute('''
                    W.steps = {}
                    local step = TEST_MODEL.step
                    TEST_MODEL.step = function(...)
                        W.steps[W.frame] = (W.steps[W.frame] or 0) + 1
                        return step(...)
                    end
                    simulate(8)
                ''')
                self.assertLessEqual(max(lua.eval("W.steps").values()), math.ceil(6 / period))
                self.assertEqual(sum(lua.eval("W.steps").values()), 6 * 8 / period)
                self.assert_clean(lua)

    def test_reload_between_ticks_preserves_fields_phase_and_owned_emitters(self):
        for key in ("ring_of_fire", "flame_burst", "forbidden_flames", "pyreball"):
            with self.subTest(spell=key):
                lua, reference = world_runtime(), world_runtime()
                e, other = cast_page(lua, key, 500, -40), cast_page(reference, key, 500, -40)
                lua.eval("simulate")(11)
                reference.eval("simulate")(11)
                pool = emitters(lua, e)
                saved = lua.eval("effect_params")(e)
                phase, cell = saved["fluid_phase"], saved["fluid_cell"]
                self.assertTrue(saved["fluid_state"].startswith("3:"))
                lua.execute('''
                    FlameFields.states = {}
                    function EntityLoad() error("Reload must reuse saved emitters") end
                ''')
                for _ in range(6):
                    lua.eval("simulate")(1)
                    reference.eval("simulate")(1)
                    for name, values in field(lua, e).items():
                        self.assertLess(max(abs(a-b) for a, b in zip(values, field(reference, other)[name])), 1e-8)
                self.assertEqual(emitters(lua, e), pool)
                p = lua.eval("effect_params")(e)
                self.assertEqual((p["fluid_phase"], p["fluid_cell"]), (phase, cell))
                self.assert_clean(lua)

    def test_pixel_native_and_ignition_supplies_are_bounded(self):
        for key, cap, pool_cap, fuel in (("ring_of_fire", 512, 6, 4),
                                        ("forbidden_flames", 160, 3, 1), ("pyreball", 256, 4, 4)):
            with self.subTest(spell=key):
                lua = world_runtime()
                lua.execute('''
                    W.pixel_frames, W.fuel_frames = {}, {}
                    local pixel, particle = GameCreateCosmeticParticle, GameCreateParticle
                    function GameCreateCosmeticParticle(...)
                        W.pixel_frames[W.frame] = (W.pixel_frames[W.frame] or 0) + 1
                        return pixel(...)
                    end
                    function GameCreateParticle(material, x, y, count, ...)
                        if material == "fire" then W.fuel_frames[W.frame] = (W.fuel_frames[W.frame] or 0) + count end
                        return particle(material, x, y, count, ...)
                    end
                ''')
                e = cast_page(lua, key)
                counts = []
                for _ in range(30):
                    lua.eval("simulate")(1)
                    counts.append(len(sprites(lua)) + (lua.eval("W.pixel_frames")[lua.eval("W.frame")] or 0))
                self.assertGreater(max(counts), 0)
                self.assertLessEqual(max(counts), cap)
                self.assertLessEqual(max(lua.eval("W.fuel_frames").values()), fuel)
                self.assertEqual(len(emitters(lua, e)), pool_cap)
                for child in emitters(lua, e):
                    comp = lua.eval("EntityGetFirstComponent")(child, "ParticleEmitterComponent")
                    get = lambda name: lua.eval("ComponentGetValue2")(comp, name)
                    self.assertEqual(get("count_max"), 1)
                    self.assertEqual(get("area_circle_radius"), (0, 0))
                    self.assertEqual(get("emit_real_particles"), 1)
                    self.assertEqual(get("create_real_particles"), 0)
                self.assert_clean(lua)

    def test_rings_and_violet_sources_do_not_supply_heat_across_thin_walls(self):
        for key, source_x, wall_x in (("ring_of_fire", 0, 18),
                                      ("forbidden_flames", 90, 92), ("pyreball", 60, 62)):
            with self.subTest(spell=key):
                lua = world_runtime()
                wall(lua, wall_x)
                samples = []
                lua.globals().GameCreateCosmeticParticle = lambda material, x, y, *args: samples.append(x)
                lua.globals().GameCreateParticle = lambda material, x, y, *args: samples.append(x)
                freeze_enemies(lua, ((wall_x + 2, -40), (wall_x + 8, -40), (400, -40)))
                e = cast_page(lua, key, source_x, -40)
                samples.clear()  # Ignore the book's unrelated cast-sign decoration.
                for _ in range(28):
                    lua.eval("simulate")(1)
                    samples.extend(s.x for s in sprites(lua))
                self.assertTrue(samples)
                self.assertTrue(all(x < wall_x for x in samples))
                self.assertFalse(list(lua.eval("W.hits").values()))
                for child in emitters(lua, e):
                    self.assertLess(lua.eval("EntityGetTransform")(child)[0], wall_x)
                self.assert_clean(lua)

    def test_liquid_arrival_on_non_solver_frame_erases_heat_and_is_saved(self):
        for key in ("ring_of_fire", "forbidden_flames", "pyreball"):
            with self.subTest(spell=key):
                lua = world_runtime()
                e = cast_page(lua, key)
                lua.eval("simulate")(1)
                self.assertGreater(sum(field(lua, e)["d"]), 0)
                lua.execute('''
                    function RaytraceSurfacesAndLiquiform(x, y) return true, x, y end
                    simulate(1)
                ''')
                self.assertEqual(sum(field(lua, e)["d"]), 0)
                self.assertTrue(lua.globals().FlameFields.states[e].dirty)
                state = lua.eval("effect_params")(e)["fluid_state"]
                for child in emitters(lua, e):
                    comp = lua.eval("EntityGetFirstComponent")(child, "ParticleEmitterComponent")
                    self.assertFalse(lua.eval("ComponentGetValue2")(comp, "is_emitting"))
                lua.execute("FlameFields.states = {}; simulate(1)")
                self.assertEqual(sum(field(lua, e)["d"]), 0)
                self.assertEqual(lua.eval("effect_params")(e)["fluid_state"], state)
                self.assert_clean(lua)

    def test_violet_source_is_suppressed_by_water_and_resumes_when_clear(self):
        lua = world_runtime()
        lua.execute("function RaytraceSurfacesAndLiquiform(x,y) return true,x,y end")
        e = cast_page(lua, "forbidden_flames", 90, -40)
        freeze_enemies(lua, ((90, -40), (100, -40), (200, -40)))
        lua.eval("simulate")(22)
        self.assertTrue(lua.eval("EntityGetIsAlive")(e))
        self.assertEqual(sum(field(lua, e)["d"]), 0)
        self.assertEqual(lua.eval("W.real_fire"), 0)
        self.assertFalse(list(lua.eval("W.hits").values()))
        lua.execute('''
            function RaytraceSurfacesAndLiquiform(x1,y1,x2,y2) return false,x2,y2 end
            simulate(40)
        ''')
        self.assertGreater(sum(field(lua, e)["d"]), 0)
        self.assertGreater(lua.eval("W.real_fire"), 0)
        self.assertEqual({h.id for h in lua.eval("W.hits").values()}, {lua.eval("ENEMIES[1]")})
        self.assert_clean(lua)

    def test_violet_damage_requires_hot_gas_instead_of_the_whole_radius(self):
        lua = world_runtime()
        freeze_enemies(lua, ((90, -40), (101, -40), (90, -53)))
        cast_page(lua, "forbidden_flames", 90, -40)
        lua.eval("simulate")(42)
        hits = list(lua.eval("W.hits").values())
        self.assertTrue(hits)
        self.assertEqual({h.id for h in hits}, {lua.eval("ENEMIES[1]")})
        self.assertTrue(all(h.who == lua.globals().PLAYER and h.kind == "DAMAGE_FIRE" for h in hits))
        self.assert_clean(lua)

    def test_burst_impacts_liquid_and_both_of_its_rings_own_fluid_fields(self):
        lua = world_runtime()
        wall(lua, 34)
        lua.execute("function RaytraceSurfaces(x1,y1,x2,y2) return false,x2,y2 end")
        e = cast_page(lua, "flame_burst", 300, -40)
        lua.eval("simulate")(8)
        self.assertFalse(lua.eval("EntityGetIsAlive")(e))
        rings = [entity.id for entity in lua.eval("W.entities").values()
                 if entity.name == "witch_flame_ring"]
        self.assertEqual(len(rings), 2)
        self.assertTrue(all(sum(field(lua, ring)["d"]) > 0 for ring in rings))
        blast = next(ring for ring in rings if lua.eval("effect_params")(ring)["blast"] == 1)
        self.assertAlmostEqual(lua.eval("EntityGetTransform")(blast)[0], 33)
        self.assertIsNone(lua.globals().FlameFields.states[e])
        self.assert_clean(lua)

    def test_translating_stationary_source_sweeps_gas_before_render_and_reload(self):
        lua = world_runtime()
        wall(lua, 95)
        e = cast_page(lua, "forbidden_flames", 90, -40)
        lua.eval("simulate")(9)
        mass = sum(field(lua, e)["d"])
        self.assertGreater(mass, 0)
        lua.eval("EntitySetTransform")(e, 100, -40)
        lua.eval("simulate")(1)
        # A faint tail which stays to the left of the wall survives. Every
        # cell swept through the wall must be extinguished on this mask tick.
        self.assertLess(sum(field(lua, e)["d"]), mass * 0.01)
        lua.globals().TEST_EFFECT = e
        swept_mass = lua.execute('''
            local s, mass = FlameFields.states[TEST_EFFECT], 0
            for i,d in ipairs(s.d) do
                if ((i-1)%20+1-10.5)*s.cell+100 > 95 then mass=mass+d end
            end
            return mass
        ''')
        self.assertEqual(swept_mass, 0)
        saved = field(lua, e)
        self.assertEqual(lua.eval("effect_params")(e)["fluid_ox"], 100)
        lua.execute("FlameFields.states = {}; simulate(1)")
        self.assertLess(max(abs(a-b) for a,b in zip(field(lua,e)["d"],saved["d"])), 1e-10)
        lua.eval("simulate")(5)
        self.assertGreater(sum(field(lua, e)["d"]), 0)
        self.assert_clean(lua)

    def test_old_ring_save_bootstraps_a_field_in_its_fading_tail(self):
        lua = world_runtime()
        e = cast_page(lua, "ring_of_fire")
        lua.eval("effect_set")(e, "born", lua.eval("W.frame") - 31)
        lua.eval("simulate")(1)
        self.assertGreater(sum(field(lua, e)["d"]), 0)
        self.assertTrue(lua.eval("effect_params")(e)["fluid_state"].startswith("3:"))
        self.assert_clean(lua)

    def test_old_native_pyreball_plume_is_replaced_without_duplicate_emission(self):
        lua = world_runtime()
        e = cast_page(lua, "pyreball")
        old = lua.eval("EntityLoad")("mods/witch_notebook/files/entities/pyreball_plume.xml", 60, -40)
        lua.eval("EntityAddChild")(e, old)
        lua.eval("simulate")(1)
        self.assertFalse(lua.eval("EntityGetIsAlive")(old))
        self.assertEqual(len(emitters(lua, e)), 4)
        self.assertGreater(sum(field(lua, e)["d"]), 0)
        lua.execute("FlameFields.states = {}; simulate(1)")
        self.assertEqual(len(emitters(lua, e)), 4)
        self.assert_clean(lua)

    def test_pyreball_size_renewal_changes_the_inlet_without_resetting_its_clock_or_pool(self):
        lua = world_runtime()
        e = cast_page(lua, "pyreball", 60)
        lua.eval("simulate")(16)
        saved, previous = lua.eval("effect_params")(e), field(lua, e)
        born, phase, radius = saved["fluid_born"], saved["fluid_phase"], saved["r"]
        pool = emitters(lua, e)
        changed = lua.execute('''
            local data=seal_page_data({named="pyreball",precision=1,stability=1})
            return cast_spell(PLAYER,parse_spell_data(data..";b=grow:2,strong:2"),
                0,-40,1,0,60,-40,W.frame,nil)[1]
        ''')
        self.assertEqual(changed, e)
        self.assertEqual(field(lua, e), previous)
        self.assertGreater(lua.eval("effect_params")(e)["r"], radius)
        lua.execute('function EntityLoad() error("Size renewal must retain owned emitters") end; simulate(12)')
        renewed = lua.eval("effect_params")(e)
        self.assertEqual((renewed["fluid_born"], renewed["fluid_phase"], renewed["fluid_cell"]), (born, phase, 2))
        self.assertEqual(emitters(lua, e), pool)
        self.assertGreater(sum(field(lua, e)["d"]), sum(previous["d"]))
        self.assert_clean(lua)

    def test_expiry_removes_owned_emitters_and_cache_without_affecting_another_source(self):
        lua = world_runtime()
        short = cast_page(lua, "ring_of_fire")
        long = cast_page(lua, "forbidden_flames")
        lua.eval("simulate")(2)
        children = emitters(lua, short)
        lua.eval("simulate")(60)
        self.assertFalse(lua.eval("EntityGetIsAlive")(short))
        self.assertTrue(all(not lua.eval("EntityGetIsAlive")(child) for child in children))
        self.assertIsNone(lua.globals().FlameFields.states[short])
        self.assertTrue(lua.eval("EntityGetIsAlive")(long))
        self.assertGreater(sum(field(lua, long)["d"]), 0)
        self.assert_clean(lua)


if __name__ == "__main__":
    unittest.main(verbosity=2)
