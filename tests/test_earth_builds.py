"""Wall Bend's bent brickwork and Sand Cage's panels.

python tests/test_earth_builds.py
"""
import unittest

from harness import world_runtime, cast_page, freeze_enemies
from fluid_render_capture import texture
from render_earth_builds import pieces

BANDS = "mods/witch_notebook/files/gfx/sand_cage_bands_"


def boxes(lua):
    """every standing piece as (kind, left, top, right, bottom)"""
    out = []
    for path, x, y in pieces(lua):
        image = texture(path)
        kind = path.split("/")[-1][:-4]
        out.append((kind, x - image.width / 2, y - image.height / 2, x + image.width / 2, y + image.height / 2))
    return out


class WallBend(unittest.TestCase):
    def wall(self, direction):
        lua = world_runtime()
        lua.execute('''
            GROUND = 10
            EntitySetTransform(PLAYER, 0, 6)
            EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent"))
            for _, id in ipairs(ENEMIES) do EntityKill(id) end
        ''')
        lua.globals().TEST_DIR = direction
        effect = lua.execute('''
            local data = seal_page_data({named = "wall_bend", precision = 1, stability = 1})
            return cast_spell(PLAYER, parse_spell_data(data), 0, 2, TEST_DIR, 0, TEST_DIR * 200, 2, W.frame, nil)[1]
        ''')
        lua.execute("simulate(70)")
        return lua, effect

    def test_wall_is_staggered_brickwork_that_bends_back_over_the_caster(self):
        for direction in (1, -1):
            with self.subTest(direction=direction):
                lua, effect = self.wall(direction)
                built = boxes(lua)
                # Bricks and half bricks only: no more round blocks stacked like beads.
                self.assertEqual({b[0] for b in built}, {"stone_brick", "stone_brick_half"})
                courses = {}
                for kind, left, top, right, bottom in built:
                    courses.setdefault(bottom, []).append((left, right, kind))
                levels = sorted(courses, reverse=True)
                self.assertGreaterEqual(len(levels), 12)
                # It stands on the ground, each course four pixels high and whole: a brick and a half, 12 wide.
                self.assertEqual(levels[0], 10)
                self.assertEqual({a - b for a, b in zip(levels, levels[1:])}, {4})
                spans = []
                for level in levels:
                    row = sorted(courses[level])
                    self.assertEqual([kind for _, _, kind in row].count("stone_brick"), 1)
                    self.assertEqual(row[0][1], row[1][0])
                    spans.append((row[0][0], row[1][1], row[0][1]))
                self.assertEqual({right - left for left, right, _ in spans}, {12})
                # The joints of neighboring courses do not line up.
                self.assertTrue(all(a[2] - a[0] != b[2] - b[0] for a, b in zip(spans, spans[1:])))
                # The foot stands in front of the caster; the top has come back over them, course by course,
                # never by more than a third of the wall's thickness at once.
                foot, top = (spans[0][0] + spans[0][1]) / 2, (spans[-1][0] + spans[-1][1]) / 2
                self.assertEqual(foot, direction * 18)
                self.assertGreaterEqual((foot - top) * direction, 10)
                self.assertLess(abs(top), abs(foot))
                steps = [(a[0] - b[0]) * direction for a, b in zip(spans, spans[1:])]
                self.assertTrue(all(0 <= step <= 4 for step in steps))
                self.assertFalse(list(lua.eval("W.errors").values()))

    def cast(self, world, direction=1, y=6):
        """Cast Wall Bend standing at (0, y) in a world set up by the Lua text 'world'; returns lua, the effect."""
        lua = world_runtime()
        lua.execute(world)
        lua.globals().TEST_DIR, lua.globals().TEST_Y = direction, y
        effect = lua.execute('''
            EntitySetTransform(PLAYER, 0, TEST_Y)
            EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent"))
            for _, id in ipairs(ENEMIES) do EntityKill(id) end
            local data = seal_page_data({named = "wall_bend", precision = 1, stability = 1})
            return cast_spell(PLAYER, parse_spell_data(data), 0, TEST_Y - 4, TEST_DIR, 0, TEST_DIR * 200, TEST_Y - 4, W.frame, nil)[1]
        ''')
        lua.execute("simulate(70)")
        return lua, effect

    def test_wall_rises_only_out_of_ground(self):
        # In the air, with no ground within reach below: nothing rises, and the witch is told why.
        lua, effect = self.cast("GROUND = 10", y=-200)
        self.assertFalse(boxes(lua))
        self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
        self.assertIn("Wall Bend: there is no ground here to draw up", list(lua.eval("W.prints").values()))
        self.assertFalse(list(lua.eval("W.errors").values()))
        # A little above the ground: it still rises out of the ground itself, not from the caster's height.
        lua, effect = self.cast("GROUND = 10", y=-20)
        built = boxes(lua)
        self.assertTrue(built)
        self.assertEqual(max(b[4] for b in built), 10)
        # At an edge, with a drop where it would stand: it rises a little nearer, where there is ground.
        ledge = '''
            GROUND = 10
            function RaytracePlatforms(x1, y1, x2, y2)
                if x1 < 16 and (y1 - GROUND) * (y2 - GROUND) <= 0 and y1 ~= y2 then return true, x1, GROUND end
                return false, x2, y2
            end
        '''
        lua, effect = self.cast(ledge)
        built = boxes(lua)
        self.assertTrue(built)
        foot = [b for b in built if b[4] == 10]
        self.assertEqual((min(b[1] for b in foot), max(b[3] for b in foot)), (8, 20))
        # Past the edge altogether (the caster turned the other way stands on ground; this way there is none).
        lua, effect = self.cast(ledge.replace("x1 < 16", "x1 < 5"))
        self.assertFalse(boxes(lua))
        self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
        # Rock where the wall would stand is not ground to rise from either.
        lua, effect = self.cast('''
            GROUND = 10
            function RaytracePlatforms(x1, y1, x2, y2)
                if x1 > 8 then return true, x1, y1 end
                if (y1 - GROUND) * (y2 - GROUND) <= 0 and y1 ~= y2 then return true, x1, GROUND end
                return false, x2, y2
            end
        ''')
        self.assertFalse(boxes(lua))
        self.assertFalse(list(lua.eval("W.errors").values()))


class SandCage(unittest.TestCase):
    def cage(self):
        lua = world_runtime()
        lua.execute("GROUND = 10")
        freeze_enemies(lua, ((120, -6), (400, -40), (500, -40)))
        drawn = []
        lua.globals().GameCreateSpriteForXFrames = lambda path, x, y, *rest: drawn.append((path, x, y))
        effect = cast_page(lua, "sand_cage", 120, -6)
        return lua, effect, drawn

    def bands(self, lua, effect):
        """the cage's band sprite: (image, visible, z, the image's top-left in the world) or None"""
        sprites = lua.eval("EntityGetComponentIncludingDisabled")(effect, "SpriteComponent", "witch_cage_bands")
        if not sprites or not list(sprites.values()):
            return None
        (sprite,) = sprites.values()
        get = lambda name: lua.eval("ComponentGetValue2")(sprite, name)
        x, y = lua.eval("EntityGetTransform")(effect)[:2]
        return get("image_file"), bool(get("visible")), get("z_index"), (x - get("offset_x"), y - get("offset_y"))

    def test_panels_wind_up_a_teardrop_and_leave_the_caged_one_room(self):
        lua, effect, drawn = self.cage()
        shown = []
        for _ in range(70):
            lua.execute("simulate(1)")
            shown.append(self.bands(lua, effect))
        built = boxes(lua)
        self.assertEqual({b[0] for b in built}, {"sand_panel"})
        self.assertEqual(len(built), 26)
        # The enemy stands at (120, -6), about 8 by 18: no solid panel is put into it.
        for _, left, top, right, bottom in built:
            self.assertFalse(left < 124 and right > 116 and top < 2 and bottom > -16, (left, top, right, bottom))
        # Widest about the enemy, a point over its head, closed under its feet.
        centers = sorted(((top + bottom) / 2, (left + right) / 2) for _, left, top, right, bottom in built)
        self.assertEqual(centers[0][1], 120)
        self.assertLess(centers[0][0], -40)
        self.assertEqual(centers[-1][1], 120)
        widest = max(abs(x - 120) for _, x in centers)
        self.assertGreaterEqual(widest, 15)
        self.assertLessEqual(widest, 17)
        # The bands in front are a picture, shown as far up as the sides stand: a third, two thirds, all.
        order = [b[0] for b in shown if b and b[1]]
        self.assertEqual(sorted(set(order)), [BANDS + "1.png", BANDS + "2.png", BANDS + "3.png"])
        self.assertEqual(order, sorted(order))
        self.assertFalse(shown[0][1])
        self.assertEqual(shown[-1][:2], (BANDS + "3.png", True))
        for i in (1, 2, 3):
            self.assertEqual(texture(BANDS + f"{i}.png").size, (34, 54))
        # One sprite of the effect's own, nearer the eye than creatures (the player's sprite is at z 0.6, the
        # world grid at 0): the caged one shows through the gaps, behind the bands, not over them.
        self.assertFalse(drawn)
        self.assertTrue(all(b[2] < 0 for b in shown))
        # It lies inside the cage's outline on whole pixels, its last row just under the lowest panel.
        left, top = shown[-1][3]
        self.assertEqual((left, top), (round(left), round(top)))
        lowest = max(bottom for _, _, _, _, bottom in built)
        self.assertEqual(left + 17, 120)
        self.assertLessEqual(abs(top + 54 - lowest), 4)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_bands_go_when_the_cage_does(self):
        lua, effect, drawn = self.cage()
        lua.eval("effect_set")(effect, "frames", 80)
        lua.execute("simulate(60)")
        self.assertTrue(self.bands(lua, effect)[1])
        lua.execute("simulate(21)")
        self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
        self.assertFalse(list(lua.eval("W.errors").values()))


class SerpentsBed(unittest.TestCase):
    def bed(self, ground=True, enemies=((400, -40), (450, -40), (500, -40))):
        lua = world_runtime()
        if ground:
            lua.execute("GROUND = 10")
        freeze_enemies(lua, enemies)
        effect = cast_page(lua, "serpents_bed", 100, -10)
        return lua, effect

    def held(self, lua, creature):
        """names of the held effects on a creature"""
        names = [lua.eval("EntityGetName")(child) for child in (lua.eval("EntityGetAllChildren")(creature) or {}).values()
                 if lua.eval("EntityGetIsAlive")(child)]
        return [name for name in names if name.startswith("witch_held_")]

    def test_bed_heaps_up_from_the_middle_out_of_gathered_sand_and_rests_on_the_ground(self):
        lua, effect = self.bed()
        self.assertEqual(lua.eval("effect_params")(effect)["mode"], "bed")
        # First the sand gathers: nothing stands yet.
        lua.execute("simulate(20)")
        self.assertFalse(boxes(lua))
        # Then billows, the middle ones first.
        lua.execute("simulate(10)")
        early = boxes(lua)
        self.assertTrue(0 < len(early) < 12)
        self.assertTrue(all(abs((b[1] + b[3]) / 2 - 100) <= 14 for b in early))
        lua.execute("simulate(40)")
        built = boxes(lua)
        # Twelve billows of three sizes, no single boulder; a wide low cloud lying on the ground.
        self.assertEqual(len(built), 12)
        self.assertEqual({b[0] for b in built}, {"sand_puff_l", "sand_puff_m", "sand_puff_s"})
        left, top = min(b[1] for b in built), min(b[2] for b in built)
        right, bottom = max(b[3] for b in built), max(b[4] for b in built)
        self.assertGreaterEqual(right - left, 70)
        self.assertLessEqual(bottom - top, 30)
        self.assertAlmostEqual((left + right) / 2, 100, delta=1)
        self.assertLessEqual(abs(bottom - 10), 2)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_bed_hangs_where_it_was_cast_when_there_is_no_ground(self):
        lua, effect = self.bed(ground=False)
        lua.execute("simulate(70)")
        built = boxes(lua)
        self.assertEqual(len(built), 12)
        self.assertAlmostEqual((min(b[2] for b in built) + max(b[4] for b in built)) / 2, -10, delta=4)

    def test_a_billow_that_is_gone_grows_again(self):
        lua, effect = self.bed()
        lua.execute("simulate(70)")
        lua.execute('''
            for id, entity in pairs(W.entities) do
                if entity.alive and entity.file and entity.file:find("sand_puff_m") then EntityKill(id); break end
            end
        ''')
        self.assertEqual(len(boxes(lua)), 11)
        lua.execute("simulate(61)")
        self.assertEqual(len(boxes(lua)), 12)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_a_beast_on_the_bed_falls_asleep_once_and_the_witch_does_not(self):
        lua, effect = self.bed(enemies=((100, -18), (400, -40), (450, -40)))
        beast, other, player = lua.eval("ENEMIES[1]"), lua.eval("ENEMIES[2]"), lua.eval("PLAYER")
        lua.execute('''
            EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent"))
            EntitySetTransform(PLAYER, 110, -18)
        ''')
        lua.execute("simulate(60)")
        self.assertFalse(self.held(lua, beast))
        # A second or so on the finished bed, and it sleeps; the witch beside it and the beast far off do not.
        lua.execute("simulate(80)")
        self.assertEqual(self.held(lua, beast), ["witch_held_sleep"])
        self.assertFalse(self.held(lua, player))
        self.assertFalse(self.held(lua, other))
        self.assertFalse(list(lua.eval("W.hits").values()))
        # It wakes after six seconds and is not put to sleep by the same bed again.
        lua.execute("simulate(420)")
        self.assertFalse(self.held(lua, beast))
        lua.execute("simulate(120)")
        self.assertFalse(self.held(lua, beast))
        self.assertFalse(list(lua.eval("W.errors").values()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
