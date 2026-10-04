"""Fire spell regressions: custom manifestations, walls, hazards and harmless heat.

python tests/test_fire_spells.py
"""
from pathlib import Path
import random
import re
import tempfile
import unittest

from PIL import Image
from fluid_render_capture import sprites as visible_sprites

from harness import DATA, MATERIALS, world_runtime, cast_page, freeze_enemies, wall
import wiki_spells as Wiki
import make_grimoire as Generator


def plume_emitters(lua, source):
    return [(child, lua.eval("EntityGetFirstComponent")(child, "ParticleEmitterComponent"))
            for child in (lua.eval("EntityGetAllChildren")(source) or {}).values()
            if lua.eval("EntityHasTag")(child, "witch_fluid_fire_emitter")]


class FireSpells(unittest.TestCase):
    def test_saved_pages_use_new_effects(self):
        for key, mode in (("pyreball", "ball"), ("flame_shot", "shot"), ("flame_burst", "burst"), ("ring_of_fire", "ring")):
            for legacy in (False, True):
                with self.subTest(spell=key, legacy=legacy):
                    lua = world_runtime()
                    e = cast_page(lua, key, legacy=legacy)
                    p = lua.eval("effect_params")(e)
                    self.assertEqual((p["kind"], p["mode"]), ("flame", mode))
                    self.assertFalse(lua.eval("EntityGetFirstComponent")(e, "ProjectileComponent"))
                    lua.eval("simulate")(int(p["frames"]) + 100)
                    self.assertFalse(lua.eval("EntityGetIsAlive")(e))
                    self.assertFalse(list(lua.eval("W.errors").values()))

    def test_pyreball_stays_put_supplies_native_fire_and_expires(self):
        lua = world_runtime()
        freeze_enemies(lua, ((55, -40), (170, -40), (60, -100)))
        e = cast_page(lua, "pyreball")
        lua.execute("simulate(120)")
        x, y, *_ = lua.eval("EntityGetTransform")(e)
        self.assertAlmostEqual(x, 60)
        self.assertEqual(y, -40)
        self.assertTrue(lua.eval("EntityGetIsAlive")(e))
        # The stub does not simulate material burning. There must be no independent
        # damage aura that could continue hurting creatures through extinguished fire.
        self.assertFalse(list(lua.eval("W.hits").values()))
        self.assertGreater(lua.eval("W.real_fire"), 0)
        children = plume_emitters(lua, e)
        lua.eval("simulate")(int(lua.eval("effect_params")(e)["frames"]) + 1)
        self.assertFalse(lua.eval("EntityGetIsAlive")(e))
        self.assertTrue(all(not lua.eval("EntityGetIsAlive")(child) for child, _ in children))
        self.assertIsNone(lua.globals().FlameFields.states[e])
        supplied = lua.eval("W.real_fire")
        lua.execute("simulate(60)")
        self.assertEqual(lua.eval("W.real_fire"), supplied)

    def test_pyreball_renders_evolving_orange_gas_and_supplies_native_fire_from_hot_cells(self):
        lua = world_runtime()
        e = cast_page(lua, "pyreball", tx=60, ty=-40)
        samples = []
        densities, colors, sprites = [], [], []

        def particle(material, x, y, count, vx, vy, visual, *args):
            if material == "fire":
                samples.append((x, y, count, vx, vy, visual))
                state = lua.globals().FlameFields.states[e]
                frame = lua.table_from(dict(ox=60, oy=-40, head=0, dx=1, dy=0))
                densities.append(state.model.density(state, frame, x, y))

        lua.globals().GameCreateParticle = particle
        lua.globals().GameCreateCosmeticParticle = lambda material, x, y, n, vx, vy, color, *args: colors.append(int(color) & 0xFFFFFFFF)

        lua.execute('''
            function fx_flame_ball() error("Pyreball must render its fluid density") end
            function fx_dot() error("Pyreball must render its fluid density directly") end
        ''')
        for _ in range(30):
            lua.eval("simulate")(1)
            sprites.extend(visible_sprites(lua))
        before = list(lua.globals().FlameFields.states[e].d.values())
        for _ in range(90):
            lua.eval("simulate")(1)
            sprites.extend(visible_sprites(lua))
        self.assertNotEqual(before, list(lua.globals().FlameFields.states[e].d.values()))
        self.assertFalse(list(lua.eval("W.errors").values()))
        self.assertTrue(sprites)
        for path in {s.path for s in sprites}:
            with Image.open(Path(__file__).resolve().parents[1] / path.removeprefix("mods/witch_notebook/")) as image:
                colors.extend(r | g << 8 | b << 16 | a << 24 for r, g, b, a in image.getdata() if a > 0)
        self.assertTrue(all(lua.globals().W.comps[s.component]["values"].emissive for s in sprites))
        self.assertTrue(all((c & 255) >= ((c >> 8) & 255) >= ((c >> 16) & 255) for c in colors))
        self.assertGreater(len(samples), 10)
        self.assertLessEqual(sum(s[2] for s in samples), 80)
        self.assertTrue(all(s[2:] == (1, 0, 0, False) for s in samples))
        self.assertTrue(all(d > 0.08 for d in densities))
        self.assertTrue(any(abs(y + 40) > 0.1 for _, y, *_ in samples))
        self.assertEqual(len(plume_emitters(lua, e)), 4)
        for _, emitter in plume_emitters(lua, e):
            get = lambda field: lua.eval("ComponentGetValue2")(emitter, field)
            self.assertEqual(get("area_circle_radius"), (0, 0))
            self.assertEqual(get("custom_style"), "FIRE")
            self.assertEqual(get("create_real_particles"), 0)
            self.assertEqual(get("emit_real_particles"), 1)
            self.assertEqual(get("emit_cosmetic_particles"), 0)
            self.assertTrue(get("is_emitting"))
            self.assertEqual(get("collide_with_grid"), 1)
            self.assertEqual(get("count_max"), 1)

    def test_pyreball_does_not_supply_fire_or_damage_through_walls(self):
        lua = world_runtime()
        freeze_enemies(lua, ((57, -40), (63, -40), (90, -40)))
        wall(lua, 60)
        e = cast_page(lua, "pyreball", tx=100, ty=-40)
        samples = []
        lua.globals().GameCreateParticle = lambda m, x, y, *args: samples.append((m, x, y))
        lua.execute("simulate(120)")
        self.assertLess(lua.eval("EntityGetTransform")(e)[0], 60)
        self.assertTrue(samples)
        self.assertTrue(all(x < 60 for _, x, _ in samples))
        for child, emitter in plume_emitters(lua, e):
            self.assertLess(lua.eval("EntityGetTransform")(child)[0], 60)
            self.assertEqual(lua.eval("ComponentGetValue2")(emitter, "area_circle_radius"), (0, 0))
        self.assertFalse(list(lua.eval("W.hits").values()))

    def test_pyreball_liquid_blocks_supply_and_does_not_destroy_the_liquid(self):
        lua = world_runtime()
        e = cast_page(lua, "pyreball", tx=60, ty=-40)
        lua.execute('''
            local trace = RaytraceSurfacesAndLiquiform
            SUBMERGED = true
            function RaytraceSurfacesAndLiquiform(x1, y1, x2, y2)
                if SUBMERGED then return true, x1, y1 end
                return trace(x1, y1, x2, y2)
            end
            simulate(120)
        ''')
        self.assertEqual(lua.eval("W.real_fire"), 0)
        self.assertFalse(list(lua.eval("W.hits").values()))
        self.assertTrue(lua.eval("EntityGetIsAlive")(e))
        self.assertEqual(sum(lua.globals().FlameFields.states[e].d.values()), 0)
        self.assertFalse(plume_emitters(lua, e))
        lua.execute("SUBMERGED = false; simulate(120)")
        self.assertGreater(lua.eval("W.real_fire"), 0)
        self.assertTrue(all(lua.eval("ComponentGetValue2")(emitter, "is_emitting")
                            for _, emitter in plume_emitters(lua, e)))

    def test_pyreball_does_not_inject_fire_across_a_liquid_boundary(self):
        lua = world_runtime()
        e = cast_page(lua, "pyreball", tx=58, ty=-40)
        lua.execute('''
            function RaytraceSurfacesAndLiquiform(x1, y1, x2, y2)
                if x1 >= 60 or x2 >= 60 then return true, 60, y2 end
                return false, x2, y2
            end
        ''')
        samples = []
        lua.globals().GameCreateParticle = lambda m, x, y, *args: samples.append((x, y))
        lua.execute("simulate(120)")
        self.assertTrue(samples)
        self.assertTrue(all(x < 60 for x, _ in samples))
        self.assertTrue(all(lua.eval("EntityGetTransform")(child)[0] < 60
                            for child, _ in plume_emitters(lua, e)))

    def test_pyreball_expansion_and_strengthening_scale_bounded_supply(self):
        def supply(extra):
            lua = world_runtime()
            lua.globals().EXTRA = extra
            e = lua.execute('''
                local data = seal_page_data({named = "pyreball", precision = 1, stability = 1})
                local spell = parse_spell_data(data .. EXTRA)
                return cast_spell(PLAYER, spell, 0, -40, 1, 0, 60, -40, W.frame, nil)[1]
            ''')
            lua.execute("simulate(120)")
            return lua.eval("effect_params")(e)["r"], lua.eval("W.real_fire")

        base_r, base = supply("")
        big_r, big = supply(";b=grow:2,strong:2")
        self.assertGreater(big_r, base_r)
        self.assertGreater(big, base)
        self.assertLessEqual(big, 80)

    def test_pyreball_recasting_preserves_supply_budget_and_refreshes_lifetime(self):
        baseline = world_runtime()
        reference = cast_page(baseline, "pyreball")
        baseline.execute("simulate(120)")
        lua = world_runtime()
        e = cast_page(lua, "pyreball")
        for _ in range(120):
            self.assertEqual(cast_page(lua, "pyreball"), e)
            lua.execute("simulate(1)")
        self.assertEqual(lua.eval("W.real_fire"), baseline.eval("W.real_fire"))
        self.assertEqual(list(lua.eval("EntityGetWithTag")("witch_pyreball").values()), [e])
        self.assertEqual(len(plume_emitters(lua, e)), 4)
        for name in ("d", "u", "v"):
            self.assertEqual(list(lua.globals().FlameFields.states[e][name].values()),
                             list(baseline.globals().FlameFields.states[reference][name].values()))
        pool = plume_emitters(lua, e)
        lua.execute('FlameFields.states = {}; function EntityLoad() error("Renewed field must reuse its saved sources") end; simulate(1)')
        baseline.eval("simulate")(1)
        self.assertEqual(plume_emitters(lua, e), pool)
        for name in ("d", "u", "v"):
            self.assertLess(max(abs(a-b) for a,b in zip(lua.globals().FlameFields.states[e][name].values(),
                                                       baseline.globals().FlameFields.states[reference][name].values())), 1e-8)
        # Renew an almost-expired source, then run beyond its previous deadline.
        lua.execute(f'effect_set({e}, "frames", 1)')
        self.assertEqual(cast_page(lua, "pyreball"), e)
        lua.execute("simulate(120)")
        self.assertTrue(lua.eval("EntityGetIsAlive")(e))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_pyreball_recasting_updates_light_without_dimming_gold_ink(self):
        lua = world_runtime()
        e = lua.execute('''
            local data = seal_page_data({named = "pyreball", precision = 1, stability = 1})
            return cast_spell(PLAYER, parse_spell_data(data .. ";ink=gold:1"),
                0, -40, 1, 0, 60, -40, W.frame, nil)[1]
        ''')
        lights = list(lua.eval("EntityGetComponent")(e, "LightComponent").values())
        self.assertEqual(len(lights), 2)
        gold_radius = lua.eval("ComponentGetValue2")(lights[0], "radius")
        lua.execute(f'effect_set({e}, "hidden", 1); simulate(2)')
        self.assertEqual(lua.eval("ComponentGetValue2")(lights[0], "radius"), gold_radius)
        self.assertEqual(lua.eval("ComponentGetValue2")(lights[1], "radius"), 12)
        self.assertEqual(cast_page(lua, "pyreball", tx=60, ty=-40), e)
        lua.execute("simulate(2)")
        self.assertEqual(lua.eval("ComponentGetValue2")(lights[1], "radius"), 80)
        fog = [c for c in lua.eval("EntityGetComponent")(e, "SpriteComponent").values()
               if lua.eval("ComponentGetValue2")(c, "fog_of_war_hole")]
        self.assertEqual(len(fog), 2)

    def test_flame_shot_travels_straight_and_stops_at_wall(self):
        lua = world_runtime()
        freeze_enemies(lua, ((60, -40), (105, -40), (150, -40)))
        wall(lua)
        e = cast_page(lua, "flame_shot", 220, -40)
        for _ in range(int(lua.eval("effect_params")(e)["frames"]) + 2):
            lua.execute("simulate(1)")
            if lua.eval("EntityGetIsAlive")(e):
                x, y, *_ = lua.eval("EntityGetTransform")(e)
                self.assertLess(x, 80)
                self.assertAlmostEqual(y, -40)
        hits = list(lua.eval("W.hits").values())
        self.assertTrue(hits)
        self.assertEqual({h["id"] for h in hits}, {lua.eval("ENEMIES[1]")})
        self.assertFalse(lua.eval("EntityGetIsAlive")(e))

    def test_fire_ring_hits_once_and_does_not_cross_wall(self):
        lua = world_runtime()
        freeze_enemies(lua, ((20, -40), (65, -40), (-150, -40)))
        wall(lua, 35)
        cast_page(lua, "ring_of_fire")
        lua.execute("simulate(80)")
        hits = list(lua.eval("W.hits").values())
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0]["id"], lua.eval("ENEMIES[1]"))
        self.assertEqual(hits[0]["who"], lua.eval("PLAYER"))
        self.assertEqual(hits[0]["kind"], "DAMAGE_FIRE")

    def test_burst_opens_ring_then_explodes_on_wall(self):
        lua = world_runtime()
        freeze_enemies(lua, ((20, -40), (63, -40), (115, -40)))
        wall(lua)
        cast_page(lua, "flame_burst", 220, -40)
        lua.execute("simulate(90)")
        rings = []
        for entity in lua.eval("W.entities").values():
            if entity["name"] == "witch_flame_ring":
                p = lua.eval("effect_params")(entity["id"])
                rings.append((entity, p))
        self.assertEqual(len(rings), 2)
        opening = next(p for _, p in rings if p["blast"] != 1)
        explosion_e, explosion = next((e, p) for e, p in rings if p["blast"] == 1)
        self.assertGreater(explosion["r"], opening["r"] * 2)
        self.assertLess(explosion_e["x"], 80)
        self.assertGreater(explosion["born"], opening["born"])
        hits = list(lua.eval("W.hits").values())
        self.assertTrue(any(h["kind"] == "DAMAGE_EXPLOSION" for h in hits))
        self.assertNotIn(lua.eval("ENEMIES[3]"), {h["id"] for h in hits})

    def test_cold_flame_and_warmth_do_not_burn(self):
        for key in ("phantasmal_fireball", "snugstone", "snowfending"):
            with self.subTest(spell=key):
                lua = world_runtime()
                cast_page(lua, key)
                lua.execute("simulate(90)")
                self.assertEqual(lua.eval("W.real_fire"), 0)
                self.assertFalse(list(lua.eval("W.hits").values()))

    def test_snowfending_thaws_every_vanilla_snow_and_ice_material(self):

        lua = world_runtime()
        e = cast_page(lua, "snowfending")
        lua.execute("simulate(1)")
        conversions = list(lua.eval("EntityGetComponent")(e, "MagicConvertMaterialComponent").values())
        thaw = next(c for c in conversions
                    if "snow_static" in lua.eval("ComponentGetValue2")(c, "from_material_array").split(","))
        sources = lua.eval("ComponentGetValue2")(thaw, "from_material_array").split(",")
        targets = lua.eval("ComponentGetValue2")(thaw, "to_material_array").split(",")
        self.assertEqual(len(sources), len(targets))
        self.assertEqual(len(sources), len(set(sources)))
        mapping = dict(zip(sources, targets))
        materials = (Path(DATA) / "data/materials.xml").read_text(encoding="utf-8")
        icy = set()
        for entry in re.finditer(r'<CellData(?:Child)?\s([^>]+)>', materials):
            attrs = dict(re.findall(r'([\w.]+)="([^"]*)"', entry[1]))
            name = attrs.get("name", "")
            if "snow" in name or "ice" in name or "[frozen]" in attrs.get("tags", ""):
                icy.add(name)
        self.assertEqual(set(mapping), icy)
        self.assertTrue(set(targets) <= MATERIALS)
        self.assertEqual(mapping["snow_static"], "water")
        self.assertEqual(mapping["snowrock_static"], "rock_static")
        self.assertEqual(mapping["ice_glass_b2"], "water")
        for material in ("ice_cold_static", "ice_acid_static", "ice_poison_glass",
                         "ice_radioactive_static", "ice_meteor_static", "ice_ceiling", "ice_b2"):
            self.assertEqual(mapping[material], "rock_static", material)
        self.assertEqual(mapping["ice_blood_glass"], "blood")
        self.assertEqual(mapping["ice_slime_glass"], "slime")
        self.assertEqual(mapping["grass_ice"], "grass")
        self.assertTrue(lua.eval("ComponentGetValue2")(thaw, "is_circle"))
        self.assertTrue(lua.eval("ComponentGetValue2")(thaw, "loop"))
        self.assertEqual(lua.eval("ComponentGetValue2")(thaw, "radius"),
                         int(lua.eval("effect_params")(e)["r"]))
        lua.execute("simulate(120)")
        self.assertEqual(list(lua.eval("EntityGetComponent")(e, "MagicConvertMaterialComponent").values()),
                         conversions)
        self.assertEqual(lua.eval("W.real_fire"), 0)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_snowfending_expanded_thawing_preserves_other_warmth_spells(self):
        lua = world_runtime()
        e = cast_page(lua, "snugstone")
        lua.execute("simulate(1)")
        converters = list(lua.eval("EntityGetComponent")(e, "MagicConvertMaterialComponent").values())
        self.assertTrue(converters)
        sources = set()
        for c in converters:
            sources.update(lua.eval("ComponentGetValue2")(c, "from_material_array").split(","))
        self.assertNotIn("snowrock_static", sources)
        self.assertNotIn("ice_meteor_static", sources)

    def test_recasting_sustained_flames_does_not_stack_emitters(self):
        for key, tag in (("pyreball", "witch_pyreball"), ("phantasmal_fireball", "witch_phantasm")):
            with self.subTest(spell=key):
                lua = world_runtime()
                e = cast_page(lua, key)
                for _ in range(12):
                    lua.execute("simulate(1)")
                    self.assertEqual(cast_page(lua, key), e)
                tagged = list(lua.eval("EntityGetWithTag")(tag).values())
                self.assertEqual(tagged, [e])
                lights = list(lua.eval("EntityGetComponent")(e, "LightComponent").values())
                self.assertEqual(len(lights), 1)

    def test_incremental_build_preserves_other_seals(self):
        source = Path(Generator.OUT).read_text(encoding="utf-8")
        old_out = Generator.OUT
        output = Path(__file__).resolve().parent / "output"
        output.mkdir(exist_ok=True)
        target_path = None
        try:
            with tempfile.NamedTemporaryFile(dir=output, suffix=".lua", delete=False) as temp:
                target_path = Path(temp.name).resolve()
            self.assertTrue(target_path.is_relative_to(output.resolve()))
            Generator.OUT = str(target_path)
            target_path.write_text(source, encoding="utf-8")
            entries, _ = Generator.build(only={"pyreball"}, verbose=False)
            rebuilt = target_path.read_text(encoding="utf-8")
            before = {line.split('key = "')[1].split('"')[0]: line for line in source.splitlines() if 'key = "' in line}
            self.assertEqual(len(entries), len(before))
            after = {line.split('key = "')[1].split('"')[0]: line for line in rebuilt.splitlines() if 'key = "' in line}
            self.assertEqual(before.keys(), after.keys())
            for key in before.keys() - {"pyreball"}:
                self.assertEqual(before[key], after[key], key)
        finally:
            Generator.OUT = old_out
            if target_path is not None and target_path.is_relative_to(output.resolve()):
                target_path.unlink(missing_ok=True)

    def test_fire_pages_still_recognize_hand_drawings(self):
        lua = Wiki.load()
        rng = random.Random(191)
        for key in ("pyreball", "flame_shot", "flame_burst", "ring_of_fire"):
            with self.subTest(spell=key):
                entry = lua.eval("GRIMOIRE_BY_KEY")[key]
                base = Wiki.page(lua, entry)
                self.assertEqual(Wiki.read(lua, base)[0], key)
                good = sum(Wiki.read(lua, Wiki.by_hand(base, rng))[0] == key for _ in range(4))
                self.assertGreaterEqual(good, 3)


if __name__ == "__main__":
    unittest.main()
