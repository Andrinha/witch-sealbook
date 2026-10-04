"""Water Cage: a sphere of real standing water that seals the creatures in it.

python tests/test_water_cage.py
"""
import math
import unittest
from pathlib import Path

from PIL import Image

from harness import world_runtime, cast_page, freeze_enemies, wall

GFX = Path(__file__).resolve().parent.parent / "files" / "gfx"
SIZES, GROW = (16, 21, 27, 34), 24


def world(positions):
    lua = world_runtime()
    freeze_enemies(lua, positions)
    return lua


def held(lua, i):
    """the effect that seals enemy i in water, and its parameters"""
    effect = lua.eval("held_as")(lua.eval("ENEMIES")[i], "water")
    return effect, effect and lua.eval("effect_params")(effect)


def place(lua, i):
    return tuple(lua.eval("EntityGetTransform")(lua.eval("ENEMIES")[i])[:2])


def minds(lua, i):
    enemy = lua.eval("ENEMIES")[i]
    comp = lua.eval("EntityGetComponentIncludingDisabled")(enemy, "AnimalAIComponent")[1]
    return bool(lua.eval("ComponentGetIsEnabled")(comp))


def body(lua, effect):
    return [c for c in (lua.eval("EntityGetAllChildren")(effect) or {}).values()
            if lua.eval("EntityGetIsAlive")(c) and lua.eval("EntityHasTag")(c, "witch_water_cage_body")]


class WaterCagePictures(unittest.TestCase):
    def test_pictures_are_a_sphere_that_swells_from_its_middle(self):
        for r in SIZES:
            with self.subTest(r=r):
                fill = Image.open(GFX / f"water_cage_{r}_fill.png").convert("RGB")
                rim = Image.open(GFX / f"water_cage_{r}_rim.png").convert("RGB")
                self.assertEqual(fill.size, rim.size)
                c = fill.width // 2
                cells = {}
                for y in range(fill.height):
                    for x in range(fill.width):
                        a, b = fill.getpixel((x, y)), rim.getpixel((x, y))
                        # No cell belongs to both emitters, and each is put for certain: red 255.
                        self.assertFalse(a[0] and b[0])
                        if a[0] or b[0]:
                            self.assertEqual((a[0] or b[0], a[2] + b[2]), (255, 0))
                            cells[(x - c, y - c)] = ("fill" if a[0] else "rim", a[1] + b[1])
                # Together they are the whole disc, with no hole in it.
                disc = {(x, y) for x in range(-r - 1, r + 2) for y in range(-r - 1, r + 2) if math.hypot(x, y) <= r + 0.5}
                self.assertEqual(set(cells), disc)
                # Its skin is the bright material all the way round; its middle is the clear one.
                self.assertTrue(all(part == "rim" for (x, y), (part, _) in cells.items() if math.hypot(x, y) > r - 1))
                self.assertEqual(cells[(0, 0)], ("fill", 0))
                self.assertGreater(sum(part == "fill" for part, _ in cells.values()), 0.7 * len(cells))
                # The moments are the emitter's own frames (255 / GROW a frame), later the further out.
                steps = {int(k * 255 / GROW) for k in range(GROW + 1)}
                self.assertEqual({moment for _, moment in cells.values()}, steps)
                for (x, y), (_, moment) in cells.items():
                    self.assertAlmostEqual(moment / 255, math.hypot(x, y) / (r + 0.5), delta=0.5 / GROW + 0.01)


class WaterCage(unittest.TestCase):
    def assert_clean(self, lua):
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_sphere_of_standing_water_forms_round_the_creature_at_the_cursor(self):
        lua = world([(150, -20), (600, -20), (700, -20)])
        effect = cast_page(lua, "water_cage", 152, -22)
        p = lua.eval("effect_params")(effect)
        self.assertEqual((p["kind"], p["mode"]), ("water_cage", "sphere"))
        # Round the middle of its body, not at its feet or at the cursor.
        self.assertEqual(tuple(lua.eval("EntityGetTransform")(effect)[:2]), (150, -24))
        lua.execute("simulate(1)")
        self.assertEqual(lua.eval("effect_params")(effect)["r"], 21)
        (child,) = body(lua, effect)
        self.assertEqual(lua.eval("W.entities")[child].file, "mods/witch_notebook/files/entities/water_cage_21.xml")
        emitters = list(lua.eval("EntityGetComponentIncludingDisabled")(child, "ParticleEmitterComponent").values())
        get = lambda e, name: lua.eval("ComponentGetValue2")(e, name)
        self.assertEqual([get(e, "emitted_material_name") for e in emitters], ["witch_cage_water", "witch_cage_rim"])
        for e, part in zip(emitters, ("fill", "rim")):
            # Real cells, from the middle out, never through a wall, and mended for as long as it stands.
            self.assertEqual((get(e, "create_real_particles"), get(e, "image_animation_raytrace_from_center"),
                              get(e, "image_animation_loop"), get(e, "is_emitting")), (1, 1, 1, 1))
            self.assertEqual(get(e, "image_animation_file"), f"mods/witch_notebook/files/gfx/water_cage_21_{part}.png")
            self.assertEqual(get(e, "image_animation_speed"), 255 / GROW)
        # Swollen, it is mended four times slower.
        lua.execute(f"simulate({GROW + 1})")
        self.assertEqual([get(e, "image_animation_speed") for e in emitters], [255 / GROW / 4] * 2)
        self.assertTrue(lua.eval("py_material")("witch_cage_water") and lua.eval("py_material")("witch_cage_rim"))
        self.assert_clean(lua)

    def test_creatures_in_and_near_it_are_drawn_to_its_middle_and_sealed(self):
        lua = world([(150, -20), (185, -22), (230, -20)])
        cast_page(lua, "water_cage", 150, -20)
        lua.execute("simulate(2)")
        # The one it was cast on, and the one a little outside its skin; not the one far off.
        self.assertTrue(held(lua, 1)[0] and held(lua, 2)[0])
        self.assertFalse(held(lua, 3)[0])
        self.assertEqual((minds(lua, 1), minds(lua, 2), minds(lua, 3)), (False, False, True))
        before = place(lua, 2)
        lua.execute("simulate(1)")
        step = math.dist(before, place(lua, 2))
        self.assertGreater(step, 1)
        self.assertLessEqual(step, 2.51)
        lua.execute("simulate(40)")
        for i in (1, 2):
            x, y = place(lua, i)
            # Floating in the middle: its body's middle (4 above its feet) is the sphere's, give or take the bob.
            self.assertAlmostEqual(x, 150, delta=0.01)
            self.assertAlmostEqual(y, -20, delta=1.6)
        self.assertEqual(place(lua, 3), (230, -20))
        # It chokes: the caster's drowning damage, and nothing else.
        hits = list(lua.eval("W.hits").values())
        self.assertTrue(hits)
        self.assertEqual({(h.id, h.kind, h.who) for h in hits},
                         {(lua.eval("ENEMIES")[i], "DAMAGE_DROWNING", lua.eval("PLAYER")) for i in (1, 2)})
        # Held a second time it is not caught again: one seal each.
        names = [lua.eval("EntityGetName")(c) for c in lua.eval("EntityGetAllChildren")(lua.eval("ENEMIES")[1]).values()
                 if lua.eval("EntityGetIsAlive")(c)]
        self.assertEqual(names.count("witch_held_water"), 1)
        self.assert_clean(lua)

    def test_it_bursts_into_fading_water_and_lets_them_go(self):
        lua = world([(150, -20), (600, -20), (700, -20)])
        effect = cast_page(lua, "water_cage", 150, -20)
        frames = lua.eval("effect_params")(effect)["frames"]
        self.assertGreater(frames, 6 * 60)
        self.assertLess(frames, 14 * 60)
        lua.execute(f"simulate({int(frames) - 1})")
        self.assertTrue(held(lua, 1)[0])
        self.assertFalse(minds(lua, 1))
        self.assertEqual(len(body(lua, effect)), 1)
        lua.execute("simulate(3)")
        # The emitters are gone and the standing water turns, once, into water that dries away.
        self.assertFalse(body(lua, effect))
        converts = [item[2] for item in lua.eval("W.added").values() if item[1] == "MagicConvertMaterialComponent"]
        self.assertEqual(len(converts), 1)
        self.assertEqual((converts[0].from_material_array, converts[0].to_material_array, converts[0].loop),
                         ("witch_cage_water,witch_cage_rim", "water_fading,water_fading", False))
        self.assertEqual(converts[0].radius, 24)
        self.assertTrue(minds(lua, 1))
        lua.execute("simulate(20)")
        self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
        self.assertFalse(held(lua, 1)[0] and lua.eval("EntityGetIsAlive")(held(lua, 1)[0]))
        self.assert_clean(lua)

    def test_cast_on_an_empty_spot_it_waits_and_seals_who_comes_up_to_it(self):
        lua = world([(150, -20), (600, -20), (700, -20)])
        effect = cast_page(lua, "water_cage", 60, -70)
        self.assertEqual(tuple(lua.eval("EntityGetTransform")(effect)[:2]), (60, -70))
        lua.execute("simulate(60)")
        self.assertFalse(held(lua, 1)[0])
        self.assertTrue(minds(lua, 1))
        lua.execute("EntitySetTransform(ENEMIES[1], 95, -66); simulate(4)")
        seal, p = held(lua, 1)
        self.assertTrue(seal)
        self.assertEqual((p["cage"], p["cx"], p["cy"], p["oy"]), (effect, 60, -70, -4))
        # It is sealed for what is left of the cage's time, and no longer.
        left = lua.eval("effect_params")(effect)["frames"] - 60
        self.assertAlmostEqual(p["frames"], left, delta=5)
        self.assert_clean(lua)

    def test_it_does_not_reach_through_a_wall_and_frees_its_captives_if_it_is_dispelled(self):
        lua = world([(150, -20), (185, -22), (700, -20)])
        wall(lua, 170)
        effect = cast_page(lua, "water_cage", 150, -20)
        lua.execute("simulate(30)")
        self.assertTrue(held(lua, 1)[0])
        self.assertFalse(held(lua, 2)[0])
        self.assertEqual(place(lua, 2), (185, -22))
        lua.eval("EntityKill")(effect)
        lua.execute("simulate(2)")
        self.assertTrue(minds(lua, 1))
        self.assert_clean(lua)

    def test_a_big_creature_gets_a_bigger_sphere_and_a_reload_changes_nothing(self):
        lua = world([(150, -20), (600, -20), (700, -20)])
        lua.execute('''
            local box = EntityGetFirstComponentIncludingDisabled(ENEMIES[1], "HitboxComponent")
            for name, v in pairs({aabb_min_x = -18, aabb_max_x = 18, aabb_min_y = -30, aabb_max_y = 2}) do
                ComponentSetValue2(box, name, v)
            end
        ''')
        effect = cast_page(lua, "water_cage", 150, -20)
        self.assertEqual(tuple(lua.eval("EntityGetTransform")(effect)[:2]), (150, -34))
        lua.execute("simulate(10)")
        # Half its diagonal is 24: the sphere that holds it is the 34 one (27 would leave it no room).
        self.assertEqual(lua.eval("effect_params")(effect)["r"], 34)
        self.assertEqual(held(lua, 1)[1]["oy"], -14)
        lua.execute('''
            EFFECT_MODES.water_cage, EFFECT_MODES.held = nil, nil
            dofile("mods/witch_notebook/files/effects/water_cage.lua")
            dofile("mods/witch_notebook/files/effects/held.lua")
            simulate(60)
        ''')
        self.assertEqual(len(body(lua, effect)), 1)
        self.assertTrue(held(lua, 1)[0])
        x, y = place(lua, 1)
        self.assertAlmostEqual(y, -20, delta=1.6)
        self.assert_clean(lua)


if __name__ == "__main__":
    unittest.main(verbosity=2)
