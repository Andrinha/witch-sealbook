"""Water Rose: its page as the wiki's redraw has it, and the rose that grows.

python tests/test_water_rose.py
"""
import math
import random
import unittest

import wiki_spells as Wiki
from harness import cast_page
from render_water_rose import world, pen


class WaterRosePage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = Wiki.load()
        cls.entry = cls.lua.eval("GRIMOIRE_BY_KEY")["water_rose"]
        cls.page = Wiki.page(cls.lua, cls.entry)

    def test_page_follows_the_redraw_not_the_books_flower_frame(self):
        # Page units: the ring is 70 around (90, 90). The redraw's lines from the pentagon's corners stop
        # well inside the ring; the book's own Flower frame ran them out through it.
        reach = max(math.hypot(x - 90, y - 90) for stroke in self.page[1:] for x, y in stroke)
        self.assertLess(reach, 62)
        # A water sigil, a pentagon, five lines and four arcs in each of the five fields, and the ring.
        self.assertEqual(len(self.page), 1 + 3 + 1 + 5 + 20)
        # The unknown signs are read as a whole only: none of them is a coil of the book's vocabulary.
        self.assertEqual(self.entry["symbols"], "")
        self.assertNotIn(";b=", self.entry["spell"])
        self.assertIn("element=water", self.entry["spell"])

    def test_page_is_recognized_and_survives_a_hand_copy(self):
        self.assertEqual(Wiki.read(self.lua, self.page)[0], "water_rose")
        rng = random.Random(710)
        drawings = [Wiki.by_hand(self.page, rng) for _ in range(8)]
        drawings += [Wiki.as_player(self.page, rng, False) for _ in range(8)]
        good = sum(Wiki.read(self.lua, d)[0] == "water_rose" for d in drawings)
        self.assertGreaterEqual(good, 14)
        # The other pentagon page stays itself.
        flowers = Wiki.page(self.lua, self.lua.eval("GRIMOIRE_BY_KEY")["flowers_of_light"])
        self.assertEqual(Wiki.read(self.lua, flowers)[0], "flowers_of_light")


def trace(lua, effect, frames):
    """The pen's path while the effect lives: [(x, y, brush, cells a frame, draws)], one a frame."""
    path = []
    for _ in range(frames):
        lua.execute("simulate(1)")
        if not lua.eval("EntityGetIsAlive")(effect):
            break
        path.append(pen(lua))
    return path


class WaterRoseGrowth(unittest.TestCase):
    def assert_clean(self, lua):
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_new_and_saved_pages_grow_a_rose_of_standing_water_from_the_ground(self):
        for legacy in (False, True):
            with self.subTest(legacy=legacy):
                lua = world(None)
                effect = cast_page(lua, "water_rose", 100, 0, legacy=legacy)
                p = lua.eval("effect_params")(effect)
                self.assertEqual((p["kind"], p["mode"]), ("rose", "grow"))
                path = trace(lua, effect, 320)
                # The game's own root emitter, with water that stands still: real cells in the grid.
                (child,) = lua.eval("EntityGetWithTag")("witch_rose_pen").values()
                emitter = lua.eval("EntityGetFirstComponentIncludingDisabled")(child, "ParticleEmitterComponent")
                get = lambda name: lua.eval("ComponentGetValue2")(emitter, name)
                self.assertEqual(get("emitted_material_name"), "witch_still_water")
                self.assertEqual((get("create_real_particles"), get("x_vel_max"), get("y_vel_max")), (1, 0, 0))
                # It takes root on the ground under the cursor and ends well above it.
                self.assertAlmostEqual(path[0][0], 100, delta=0.01)
                self.assertAlmostEqual(path[0][1], 9, delta=0.01)
                drawn = [q for q in path if q[4]]
                top = min(q[1] for q in drawn)
                self.assertLess(top, 9 - 45)
                self.assertGreater(top, 9 - 80)
                self.assertTrue(all(q[1] <= 10 for q in drawn))
                # A pen that draws never moves so far in a frame that its line would break.
                for a, b in zip(path, path[1:]):
                    if a[4] and b[4]:
                        self.assertLessEqual(math.hypot(b[0] - a[0], b[1] - a[1]), 1.6)
                # The stem and leaves in a thick line, the petals in a fine one.
                self.assertEqual({q[2] for q in drawn}, {1, 0.7, 0.5})
                self.assertLess(sum(q[3] for q in drawn), 1800)
                # Grown, the pen rests: the rose stands without drawing more.
                self.assertEqual(lua.eval("effect_params")(effect)["phase"], 3)
                self.assertFalse(any(q[4] for q in trace(lua, effect, 60)))
                self.assertFalse(list(lua.eval("W.hits").values()))
                self.assertEqual(lua.eval("W.real_fire"), 0)
                self.assert_clean(lua)

    def test_standing_rose_drips_real_water_from_its_petals_and_leaf_tips(self):
        lua = world(None)
        lua.execute('''
            W.drops = {}
            local particle = GameCreateParticle
            function GameCreateParticle(material, x, y, n, vx, vy, visual, ...)
                if material == "water" then
                    table.insert(W.drops, {x = x, y = y, n = n, vx = vx, vy = vy, visual = visual, frame = W.frame})
                end
                return particle(material, x, y, n, vx, vy, visual, ...)
            end
        ''')
        effect = cast_page(lua, "water_rose", 100, 0)
        trace(lua, effect, 300)
        p = lua.eval("effect_params")(effect)
        self.assertEqual(p["phase"], 3)
        # Nothing drips while it grows; standing, a drop falls every twenty frames.
        grown = lua.eval("W.frame")
        early = [d for d in lua.eval("W.drops").values() if d.frame < grown - 60]
        self.assertFalse(early)
        lua.execute("W.drops = {}")
        self.assertFalse(any(q[4] for q in trace(lua, effect, 1200)))
        drops = list(lua.eval("W.drops").values())
        self.assertEqual(len(drops), 60)
        # One real cell of water each, let go at rest: it falls by itself.
        self.assertTrue(all((d.n, d.vx, d.vy, d.visual) == (1, 0, 0, False) for d in drops))
        tips = {(p["tip0x"], p["tip0y"]), (p["tip1x"], p["tip1y"])}
        from_leaves = [d for d in drops if (d.x, d.y) in tips]
        from_petals = [d for d in drops if (d.x, d.y) not in tips]
        self.assertTrue(from_leaves)
        self.assertEqual({(d.x, d.y) for d in from_leaves}, tips)
        self.assertGreater(len(from_petals), len(from_leaves))
        for d in from_petals:
            # under the lower petals: below the rose's middle, within its width
            self.assertGreater(d.y, p["ay"] + 5)
            self.assertLess(d.y, p["ay"] + 15)
            self.assertLess(abs(d.x - p["ax"]), 12)
        self.assertGreater(len({(d.x, d.y) for d in from_petals}), 5)
        # The rose is not used up: it still stands, and its pen never drew again.
        self.assertEqual(lua.eval("effect_params")(effect)["phase"], 3)
        self.assert_clean(lua)

    def test_rose_turns_back_into_water_when_its_time_is_up(self):
        lua = world(None)
        effect = cast_page(lua, "water_rose", 100, 0)
        lua.eval("effect_set")(effect, "frames", 30)
        trace(lua, effect, 400)
        self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
        self.assertFalse(list(lua.eval("EntityGetWithTag")("witch_rose_pen").values()))
        converts = [item[2] for item in lua.eval("W.added").values() if item[1] == "MagicConvertMaterialComponent"]
        self.assertEqual(len(converts), 1)
        self.assertEqual((converts[0].from_material_array, converts[0].to_material_array), ("witch_still_water", "water"))
        # The circle reaches from the root to the outermost petals.
        self.assertGreater(converts[0].radius, 45)
        self.assertLess(converts[0].radius, 80)
        self.assert_clean(lua)

    def test_growth_survives_a_reload_and_is_not_drawn_through_a_ceiling(self):
        live, loaded = world(-38), world(-38)
        a, b = cast_page(live, "water_rose", 100, 0), cast_page(loaded, "water_rose", 100, 0)
        first = trace(live, a, 70), trace(loaded, b, 70)
        self.assertEqual(*first)
        # A reload forgets Lua state; everything the rose needs is saved on the effect and its pen.
        loaded.execute('EFFECT_MODES.rose = nil; dofile("mods/witch_notebook/files/effects/rose.lua")')
        rest = trace(live, a, 260), trace(loaded, b, 260)
        self.assertEqual(*rest)
        self.assertEqual(len(list(loaded.eval("EntityGetWithTag")("witch_rose_pen").values())), 1)
        drawn = [q for q in first[0] + rest[0] if q[4]]
        # The ceiling at y = -38 begins right of x = 70: nothing is drawn in it.
        self.assertTrue(all(q[1] > -38 for q in drawn if q[0] > 70))
        # The stem stopped short of its full length to leave the rose room.
        self.assertLess(live.eval("effect_params")(a)["grown"], live.eval("effect_params")(a)["length"])
        self.assert_clean(live)
        self.assert_clean(loaded)

    def test_rose_roots_on_the_nearest_surface_and_grows_away_from_it(self):
        lua = world(None)
        # A wall's face at x = 120, twenty pixels right of the cursor: the game's probe points at it.
        lua.execute("function GetSurfaceNormal(x, y, length, rays) return true, 1, 0, 120 - x end")
        effect = cast_page(lua, "water_rose", 100, -60)
        path = trace(lua, effect, 12)
        self.assertEqual(path[0][:2], (120, -60))
        self.assertLess(path[-1][0], 112)
        self.assert_clean(lua)


if __name__ == "__main__":
    unittest.main(verbosity=2)
