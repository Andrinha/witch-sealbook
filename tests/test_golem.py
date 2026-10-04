"""The Golem: it rises from the ground, follows the caster, strikes enemies (never itself), falls and falls apart.

python tests/test_golem.py
"""
import unittest

from harness import world_runtime, freeze_enemies

GFX = "mods/witch_notebook/files/gfx/golem_"


def summon(enemies=(), direction=1, ground=10):
    """Cast the Golem standing at (0, ground - 4) with the enemies frozen at 'enemies'; returns lua, the effect."""
    lua = world_runtime()
    lua.globals().TEST_GROUND, lua.globals().TEST_DIR = ground, direction
    lua.execute('''
        GROUND = TEST_GROUND
        EntitySetTransform(PLAYER, 0, GROUND - 4)
        EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent"))
    ''')
    freeze_enemies(lua, list(enemies) + [(5000 + 100 * i, -5000) for i in range(3 - len(enemies))])
    effect = lua.execute('''
        local data = seal_page_data({named = "golem", precision = 1, stability = 1})
        return cast_spell(PLAYER, parse_spell_data(data), 0, GROUND - 8, TEST_DIR, 0, TEST_DIR * 200, GROUND - 8, W.frame, nil)[1]
    ''')
    return lua, effect


def frame_of(lua, effect):
    lua.globals().TEST_E = effect
    path = lua.eval('ComponentGetValue2(EntityGetComponentIncludingDisabled(TEST_E, "SpriteComponent", "witch_golem")[1], "image_file")')
    return path[len(GFX):-4]


def where(lua, effect):
    x, y = lua.eval("EntityGetTransform")(effect)[:2]
    return x, y


class Golem(unittest.TestCase):
    def assert_clean(self, lua):
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_it_rises_out_of_the_ground_in_front_of_the_caster(self):
        for direction in (1, -1):
            with self.subTest(direction=direction):
                lua, effect = summon(direction=direction)
                seen = []
                for _ in range(60):
                    lua.execute("simulate(1)")
                    if not seen or seen[-1] != frame_of(lua, effect):
                        seen.append(frame_of(lua, effect))
                self.assertEqual(seen[:4], ["rise_1", "rise_2", "rise_3", "stand"])
                x, y = where(lua, effect)
                self.assertEqual((x, y), (direction * 22, 10))  # its feet on the ground, the picture's last row above it
                self.assert_clean(lua)

    def test_it_walks_to_an_enemy_and_strikes_it_not_itself(self):
        lua, effect = summon(enemies=[(120, 6)])
        lua.execute("simulate(260)")
        hits = [dict(h) for h in lua.eval("W.hits").values()]
        enemy = lua.eval("ENEMIES[1]")
        player = lua.eval("PLAYER")
        self.assertGreaterEqual(len(hits), 2)
        self.assertEqual({h["id"] for h in hits}, {enemy})
        self.assertEqual({h["who"] for h in hits}, {player})
        x, _ = where(lua, effect)
        self.assertTrue(90 <= x <= 120, x)  # it stopped within its fist's reach
        # blows come a swing apart, each after the fist was reared up
        gaps = [b["frame"] - a["frame"] for a, b in zip(hits, hits[1:])]
        self.assertTrue(all(gap >= 40 for gap in gaps), gaps)
        self.assert_clean(lua)

    def test_the_blow_shows_the_fist_reared_then_brought_down(self):
        lua, effect = summon(enemies=[(40, 6)])
        seen = []
        for _ in range(140):
            lua.execute("simulate(1)")
            if not seen or seen[-1] != frame_of(lua, effect):
                seen.append(frame_of(lua, effect))
        self.assertIn("windup", seen)
        self.assertEqual(seen[seen.index("windup") + 1], "slam")

    def test_with_no_enemy_it_follows_the_caster(self):
        lua, effect = summon()
        lua.execute("simulate(60); EntitySetTransform(PLAYER, 150, GROUND - 4); simulate(120)")
        x, _ = where(lua, effect)
        self.assertGreater(x, 100)
        self.assertIn(frame_of(lua, effect), ("walk_1", "walk_2"))
        lua.execute("simulate(120)")
        x, _ = where(lua, effect)
        self.assertTrue(115 <= x <= 125, x)  # it stops a few steps short of them
        self.assertEqual(frame_of(lua, effect), "stand")
        self.assertFalse(list(lua.eval("W.hits").values()))
        self.assert_clean(lua)

    def test_it_faces_the_way_it_goes(self):
        lua, effect = summon()
        lua.execute("simulate(60); EntitySetTransform(PLAYER, -150, GROUND - 4); simulate(30)")
        lua.globals().TEST_E = effect
        self.assertEqual(lua.eval("(select(4, EntityGetTransform(TEST_E)))"), -1)

    def test_it_falls_when_the_ground_goes_and_lands(self):
        lua, effect = summon()
        lua.execute("simulate(60); GROUND = 90; simulate(3)")
        _, y = where(lua, effect)
        self.assertTrue(10 < y < 20, y)  # falling, not set down on the far ground at once
        lua.execute("simulate(60)")
        _, y = where(lua, effect)
        self.assertEqual(y, 90)
        self.assert_clean(lua)

    def test_broken_it_falls_apart_into_sand(self):
        lua, effect = summon()
        lua.globals().TEST_E = effect
        lua.execute('''
            simulate(60)
            W.sand = 0
            local particle = GameCreateParticle
            function GameCreateParticle(m, ...) if m == "sand" then W.sand = W.sand + 1 end particle(m, ...) end
            ComponentSetValue2(EntityGetFirstComponent(TEST_E, "DamageModelComponent"), "hp", 0)
            simulate(1)
        ''')
        self.assertFalse(lua.eval("EntityGetIsAlive(TEST_E)"))
        self.assertGreater(lua.eval("W.sand"), 40)
        self.assert_clean(lua)

    def test_left_far_behind_it_rises_again_beside_the_caster(self):
        lua, effect = summon()
        lua.execute("simulate(60); EntitySetTransform(PLAYER, 900, GROUND - 4); simulate(2)")
        x, y = where(lua, effect)
        self.assertTrue(abs(x - 900) <= 20, x)
        self.assertEqual(y, 10)
        self.assertEqual(frame_of(lua, effect), "rise_1")
        self.assert_clean(lua)

    def test_with_no_ground_in_reach_nothing_rises(self):
        lua = world_runtime()
        made = lua.execute('''
            GROUND = 5000
            EntitySetTransform(PLAYER, 0, 0)
            EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent"))
            local data = seal_page_data({named = "golem", precision = 1, stability = 1})
            return cast_spell(PLAYER, parse_spell_data(data), 0, 0, 1, 0, 200, 0, W.frame, nil)
        ''')
        self.assertFalse(list((made or {}).values()) if made is not None else [])
        self.assertTrue(any("no ground" in str(text) for text in lua.eval("W.prints").values()))


if __name__ == "__main__":
    unittest.main()
