"""Mirror Cloak of Borrowshade: the caster looks like the nearest beast, and nothing else about them changes.

python tests/test_mirror_cloak.py
"""
import unittest

from harness import world_runtime, cast_page, freeze_enemies

PLAYER_SPRITE = "data/enemies_gfx/player.xml"
BEAST_SPRITE = "data/enemies_gfx/zombie.xml"


def world(sprite=BEAST_SPRITE):
    """The player with their body and arm sprites, a beast 40 pixels away with 'sprite' (None: it has none)."""
    lua = world_runtime()
    freeze_enemies(lua, ((40, -40), (900, -40), (950, -40)))
    lua.globals().BEAST_FILE = sprite
    lua.execute('''
        EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent"))
        EntitySetTransform(PLAYER, 0, -40)
        BODY = EntityAddComponent2(PLAYER, "SpriteComponent", {_tags = "character,lukki_disable",
            image_file = "data/enemies_gfx/player.xml", offset_x = 6, offset_y = 14, z_index = 0.6})
        local arm = EntityCreateNew("arm_r")
        EntityAddTag(arm, "player_arm_r")
        EntityAddChild(PLAYER, arm)
        ARM = EntityAddComponent2(arm, "SpriteComponent", {_tags = "with_item", image_file = "data/enemies_gfx/player_arm.xml", alpha = 1})
        BEAST = ENEMIES[1]
        if BEAST_FILE then
            EntityAddComponent2(BEAST, "SpriteComponent", {image_file = BEAST_FILE, offset_x = 0, offset_y = 0, z_index = -1})
        end
        local genome = EntityGetFirstComponent(BEAST, "GenomeDataComponent")
        ComponentSetValue2(genome, "herd_id", 7)
        PLAYER_HERD = ComponentGetValue2(EntityGetFirstComponent(PLAYER, "GenomeDataComponent"), "herd_id")
        function look()
            return ComponentGetValue2(BODY, "image_file"), ComponentGetValue2(BODY, "offset_x"), ComponentGetValue2(BODY, "offset_y"),
                ComponentGetValue2(ARM, "alpha"), ComponentGetValue2(EntityGetFirstComponent(PLAYER, "GenomeDataComponent"), "herd_id")
        end
    ''')
    return lua


class MirrorCloak(unittest.TestCase):
    def assert_clean(self, lua):
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_caster_wears_the_beasts_sprite_and_gets_their_own_back(self):
        lua = world()
        herd = lua.eval("PLAYER_HERD")
        self.assertNotEqual(herd, 7)
        effect = cast_page(lua, "mirror_cloak")
        lua.eval("effect_set")(effect, "frames", 120)
        lua.execute("simulate(2)")
        # The beast's sprite on the caster's own body, its offsets with it; the separate arm hidden; its kind taken.
        self.assertEqual(lua.eval("look")(), (BEAST_SPRITE, 0, 0, 0, 7))
        # Only the look: the caster is the same entity with the same controls, body and hitbox - not polymorphed.
        player = lua.eval("PLAYER")
        self.assertTrue(lua.eval("EntityGetIsAlive")(player))
        self.assertTrue(lua.eval("EntityHasTag")(player, "player_unit"))
        for kind in ("ControlsComponent", "Inventory2Component", "DamageModelComponent"):
            self.assertTrue(lua.eval("EntityGetFirstComponent")(player, kind), kind)
        self.assertFalse(list(lua.eval("W.hits").values()))
        self.assertIn("You look like", " ".join(str(t) for t in lua.eval("W.prints").values()))
        # When its time is up everything is as it was.
        lua.execute("simulate(125)")
        self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
        self.assertEqual(lua.eval("look")(), (PLAYER_SPRITE, 6, 14, 1, herd))
        self.assert_clean(lua)

    def test_a_second_cloak_over_the_first_still_returns_the_true_look(self):
        lua = world()
        herd = lua.eval("PLAYER_HERD")
        first = cast_page(lua, "mirror_cloak")
        lua.execute("simulate(5)")
        # Another beast is nearer now, with another sprite and kind.
        lua.execute('''
            EntitySetTransform(ENEMIES[2], 10, -40)
            EntityAddComponent2(ENEMIES[2], "SpriteComponent", {image_file = "data/enemies_gfx/shotgunner.xml", offset_x = 2, offset_y = 3})
            ComponentSetValue2(EntityGetFirstComponent(ENEMIES[2], "GenomeDataComponent"), "herd_id", 9)
        ''')
        second = cast_page(lua, "mirror_cloak")
        self.assertFalse(lua.eval("EntityGetIsAlive")(first))
        lua.eval("effect_set")(second, "frames", 60)
        lua.execute("simulate(2)")
        self.assertEqual(lua.eval("look")(), ("data/enemies_gfx/shotgunner.xml", 2, 3, 0, 9))
        lua.execute("simulate(70)")
        self.assertEqual(lua.eval("look")(), (PLAYER_SPRITE, 6, 14, 1, herd))
        self.assert_clean(lua)

    def test_casting_with_no_beast_near_takes_the_cloak_off(self):
        lua = world()
        herd = lua.eval("PLAYER_HERD")
        cast_page(lua, "mirror_cloak")
        lua.execute("simulate(5)")
        self.assertEqual(lua.eval("look")()[0], BEAST_SPRITE)
        lua.execute("for _, id in ipairs(ENEMIES) do EntityKill(id) end")
        effect = cast_page(lua, "mirror_cloak")
        lua.execute("simulate(2)")
        self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
        self.assertEqual(lua.eval("look")(), (PLAYER_SPRITE, 6, 14, 1, herd))
        self.assert_clean(lua)

    def test_beast_without_a_sprite_of_its_own_still_lends_its_kind(self):
        lua = world(sprite=None)
        effect = cast_page(lua, "mirror_cloak")
        lua.execute("simulate(2)")
        self.assertEqual(lua.eval("look")(), (PLAYER_SPRITE, 6, 14, 1, 7))
        self.assertIn("To them you are", " ".join(str(t) for t in lua.eval("W.prints").values()))
        lua.eval("effect_set")(effect, "frames", 10)
        lua.execute("simulate(12)")
        self.assertEqual(lua.eval("look")()[4], lua.eval("PLAYER_HERD"))
        self.assert_clean(lua)


if __name__ == "__main__":
    unittest.main(verbosity=2)
