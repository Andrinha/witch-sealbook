"""Read Sword seals, save them on a page, and follow their strikes in the Lua world."""
import random
import unittest

import run_tests as drawings
from harness import cast_page, freeze_enemies, world_runtime
from test_sign_effects import seal_tree


class Blade(unittest.TestCase):
    def setUp(self):
        self.lua = world_runtime()
        self.lua.execute("""
            EntitySetTransform(PLAYER, 0, -40)
            EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent"))
        """)

    def tearDown(self):
        self.assertEqual([], list(self.lua.eval("W.errors").values()))

    def cast(self, elements, signs=(), aim=1):
        tree = seal_tree(self.lua, ["sword", *elements], [(sign, False) for sign in signs])
        result = self.lua.eval("compile_spell")(tree)
        spell = result[0] if isinstance(result, tuple) else result
        self.assertIsNotNone(spell, result)
        self.assertEqual("blade", spell.manifest)
        data = self.lua.eval("serialize_spell")(spell)
        blade = self.lua.eval("""function(data, aim)
            return cast_spell(PLAYER, parse_spell_data(data), 0, -40, aim, 0, 150 * aim, -40, W.frame, nil)[1]
        end""")(data, aim)
        return spell, blade

    def hit_frames(self, enemy):
        target = self.lua.globals().ENEMIES[enemy]
        return {hit.frame for hit in self.lua.eval("W.hits").values() if hit.id == target}

    def test_plain_sweep_reaches_each_enemy_as_the_edge_passes(self):
        freeze_enemies(self.lua, ((16, -57), (16, -27), (-18, -42)))
        _, blade = self.cast(["fire"])
        self.lua.execute("simulate(80)")
        first, second = self.hit_frames(1), self.hit_frames(2)
        self.assertEqual(1, len(first))
        self.assertEqual(1, len(second))
        self.assertLess(min(first), min(second))
        self.assertFalse(self.hit_frames(3))
        self.assertFalse(self.lua.eval("EntityGetIsAlive")(blade))
        hits = list(self.lua.eval("W.hits").values())
        self.assertTrue(all(hit.who == self.lua.globals().PLAYER for hit in hits))
        self.assertIn("DAMAGE_FIRE", {hit.kind for hit in hits})

    def test_spiraling_wind_can_reach_behind_the_caster(self):
        freeze_enemies(self.lua, ((-17, -42), (18, -42), (140, -42)))
        spell, _ = self.cast(["lightning"], ["windsign", "windsign"])
        self.assertTrue(spell.behaviors.whirl)
        self.lua.execute("simulate(80)")
        self.assertEqual(1, len(self.hit_frames(1)))
        self.assertEqual(1, len(self.hit_frames(2)))
        self.assertFalse(self.hit_frames(3))
        self.assertIn("DAMAGE_ELECTRICITY", {hit.kind for hit in self.lua.eval("W.hits").values()})

    def test_water_and_crystal_mix_into_an_ice_blade(self):
        freeze_enemies(self.lua, ((18, -42),))
        spell, blade = self.cast(["water", "crystal"])
        self.assertEqual("ice", spell.element)
        self.assertEqual("ice", self.lua.eval("effect_params")(blade).element)
        self.lua.execute("simulate(1)")
        freeze = self.lua.eval("EntityGetFirstComponent")(blade, "MagicConvertMaterialComponent")
        self.assertIn("ice_static", self.lua.eval("ComponentGetValue2")(freeze, "to_material_array"))
        self.lua.execute("simulate(60)")
        self.assertIn("DAMAGE_ICE", {hit.kind for hit in self.lua.eval("W.hits").values()})

    def test_left_facing_sweep_crosses_the_angle_wrap(self):
        freeze_enemies(self.lua, ((-18, -52), (-18, -31), (18, -40)))
        self.cast(["light"], aim=-1)
        self.lua.execute("simulate(60)")
        self.assertTrue(self.hit_frames(1) and self.hit_frames(2))
        self.assertLess(min(self.hit_frames(1)), min(self.hit_frames(2)))
        self.assertFalse(self.hit_frames(3))

    def test_water_sweeps_mirror_the_tip_and_spray_on_every_frame(self):
        _, right = self.cast(["water"])
        _, left = self.cast(["water"], aim=-1)
        self.lua.execute("""
            local emit = GameCreateParticle
            SPRAY = {}
            function GameCreateParticle(material, x, y, count, vx, vy, ...)
                if material == "water" then SPRAY[x > 0] = {vx=vx, vy=vy} end
                return emit(material, x, y, count, vx, vy, ...)
            end
        """)
        frames = int(self.lua.eval("effect_params")(right).frames)
        for tick in range(frames):
            with self.subTest(tick=tick):
                self.lua.execute("SPRAY = {}; simulate(1)")
                rx, ry, *_ = self.lua.eval("EntityGetTransform")(right)
                lx, ly, *_ = self.lua.eval("EntityGetTransform")(left)
                self.assertAlmostEqual(rx, -lx)
                self.assertAlmostEqual(ry, ly)
                spray = self.lua.globals().SPRAY
                self.assertAlmostEqual(spray[True].vx, -spray[False].vx)
                self.assertAlmostEqual(spray[True].vy, spray[False].vy)

    def test_thrust_reaches_further_and_misses_to_the_side(self):
        freeze_enemies(self.lua, ((36, -40), (20, -54), (-10, -40)))
        self.cast(["crystal"], ["column", "column"])
        self.lua.execute("simulate(60)")
        self.assertTrue(self.hit_frames(1))
        self.assertFalse(self.hit_frames(2) or self.hit_frames(3))

    def test_reflection_only_parries_shots_crossing_the_edge(self):
        self.lua.execute("""
            function test_shot(x, vx, owner)
                local e = EntityCreateNew("test shot")
                EntityAddTag(e, "projectile")
                EntitySetTransform(e, x, -40)
                local c = EntityAddComponent2(e, "ProjectileComponent", {mWhoShot=owner, lifetime=300})
                EntityAddComponent2(e, "VelocityComponent", {mVelocity={vx, 0}})
                return c
            end
            FRONT = test_shot(24, -8, ENEMIES[1])
            BACK = test_shot(-18, 8, ENEMIES[1])
        """)
        self.cast(["earth"], ["reflection"])
        self.lua.execute("simulate(60)")
        self.assertEqual(self.lua.globals().PLAYER, self.lua.eval('ComponentGetValue2(FRONT, "mWhoShot")'))
        self.assertEqual(self.lua.globals().ENEMIES[1], self.lua.eval('ComponentGetValue2(BACK, "mWhoShot")'))

    def test_piercing_releases_one_bounded_volley(self):
        self.lua.execute('dofile_once("mods/witch_notebook/files/carriers.lua"); carriers_create()')
        self.cast(["fire"], ["pierce"] * 4)
        self.lua.execute("simulate(60)")
        bolts = [e for e in self.lua.globals().W.entities.values() if e.file.endswith("carriers/bolt_fire.xml")]
        self.assertEqual(3, len(bolts))
        for bolt in bolts:
            c = self.lua.eval("EntityGetFirstComponent")(bolt.id, "ProjectileComponent")
            self.assertTrue(self.lua.eval("ComponentGetValue2")(c, "penetrate_entities"))
            self.assertEqual(self.lua.globals().PLAYER, self.lua.eval("ComponentGetValue2")(c, "mWhoShot"))

    def test_pulling_and_entwining_apply_to_the_struck_target(self):
        freeze_enemies(self.lua, ((20, -40),))
        self.lua.execute('TEST_VEL = EntityAddComponent2(ENEMIES[1], "VelocityComponent", {mVelocity={0, 0}})')
        self.cast(["water"], ["pull", "pull", "entwine", "entwine"])
        for _ in range(60):
            self.lua.eval("simulate")(1)
            if self.hit_frames(1):
                break
        self.assertTrue(self.hit_frames(1))
        self.assertLess(self.lua.eval('ComponentGetValue2(TEST_VEL, "mVelocity")')[0], 0)
        self.assertTrue(self.lua.eval('held_as(ENEMIES[1], "ribbon")'))

    def test_hand_drawn_sword_keeps_the_element_and_modifier_on_the_saved_page(self):
        state = random.getstate()
        self.addCleanup(random.setstate, state)
        random.seed(2)
        strokes = drawings.seal(self.lua, ["sword", "lightning"],
                                [("windsign", 90, False), ("windsign", 270, False)])
        result = self.lua.eval("read_spell")(drawings.lua_strokes(self.lua, strokes))
        spell = result[0] if isinstance(result, tuple) else result
        saved = self.lua.eval("parse_spell_data")(self.lua.eval("seal_page_data")(spell))
        self.assertEqual(("blade", "thunder"), (saved.manifest, saved.element))
        self.assertTrue(saved.behaviors.whirl)

    def test_raincleaver_from_a_saved_page_wets_its_target(self):
        freeze_enemies(self.lua, ((18, -42),))
        blade = cast_page(self.lua, "raincleaver", legacy=True)
        self.assertEqual("water", self.lua.eval("effect_params")(blade).element)
        self.lua.execute("simulate(1)")
        self.assertTrue(self.lua.eval("EntityGetFirstComponent")(blade, "LiquidDisplacerComponent"))
        start = self.lua.eval("EntityGetTransform")(blade)
        self.lua.execute("simulate(5)")
        self.assertNotEqual(start, self.lua.eval("EntityGetTransform")(blade))
        self.lua.execute("simulate(80)")
        children = self.lua.eval("EntityGetAllChildren(ENEMIES[1])") or {}
        files = [self.lua.globals().W.entities[child].file for child in children.values()]
        self.assertTrue(any(path.endswith("effect_apply_wet.xml") for path in files), files)

    def test_mirrored_wind_on_raincleaver_preserves_its_direction(self):
        tree = seal_tree(self.lua, ["sword"], [("windsign", False)])
        wind = tree.symbols[2]
        wind.mirror = True
        extras = self.lua.eval("extra_behaviors")(tree, self.lua.eval("GRIMOIRE_BY_KEY.raincleaver"))
        self.assertIsNotNone(extras)
        page = self.lua.table_from({"named": "raincleaver", "extras": extras})
        saved = self.lua.eval("parse_spell_data")(self.lua.eval("seal_page_data")(page))
        self.assertLess(saved.behaviors.whirl, 0)

    def test_growing_blade_draws_its_hilt_and_tip_within_a_fixed_budget(self):
        self.lua.execute("""
            dofile_once("mods/witch_notebook/files/effects/blade_draw.lua")
            W.dots = {}
            GameCreateCosmeticParticle = function(material, x, y)
                W.dots[#W.dots + 1] = {x=x, y=y}
            end
        """)
        for style in ("sweep", "thrust", "spin"):
            with self.subTest(style=style):
                self.lua.execute("W.dots = {}")
                self.lua.globals().wn_blade_draw(None, self.lua.table_from({"element": "fire"}), 4,
                                                  0, -40, 0, 62, 0.5, style)
                dots = list(self.lua.eval("W.dots").values())
                self.assertLessEqual(len(dots), 250)
                self.assertTrue(any(dot.x < -4 for dot in dots))
                self.assertTrue(any(dot.x >= 60 for dot in dots))
                self.assertTrue(all(abs(dot.x) < 85 and abs(dot.y + 40) < 65 for dot in dots))


if __name__ == "__main__":
    unittest.main()
