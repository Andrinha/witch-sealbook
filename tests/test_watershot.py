"""Watershot: water pours out of the book while fire is held, as from a flask that never runs dry.

python tests/test_watershot.py
"""
import math
import unittest

from harness import world_runtime, cast_page


def count_water(lua):
    """Record every real water particle: W.water[frame] = {x, y, vx, vy}, ..."""
    lua.execute('''
        W.water = {}
        local particle = GameCreateParticle
        function GameCreateParticle(material, x, y, n, vx, vy, visual, ...)
            if material == "water" and not visual then
                W.water[W.frame] = W.water[W.frame] or {}
                table.insert(W.water[W.frame], {x = x, y = y, vx = vx, vy = vy})
            end
            return particle(material, x, y, n, vx, vy, visual, ...)
        end
    ''')


def poured(lua, frame=None):
    frame = lua.eval("W.frame") if frame is None else frame
    return list((lua.eval("W.water")[frame] or {}).values())


def book_pour(lua, key="book", legacy=False, tx=240, ty=-40):
    """Press fire with the Watershot page active in a held book; returns the pouring effect."""
    lua.globals().TEST_BOOK = {"book": "spellbook", "quire": "palm_quire", "tome": "great_tome"}[key]
    lua.globals().TEST_KEY, lua.globals().TEST_LEGACY = key, legacy
    lua.globals().TEST_TX, lua.globals().TEST_TY = tx, ty
    return lua.execute('''
        TEST_DATA = seal_page_data({named = "watershot", precision = 1, stability = 1})
        if TEST_LEGACY then TEST_DATA = TEST_DATA:gsub(";manifest=[%w_]+", "") end
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
        return EntityGetWithTag("witch_water_pour")[1]
    ''')


class Watershot(unittest.TestCase):
    def assert_clean(self, lua):
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_water_pours_from_the_book_for_as_long_as_fire_is_held(self):
        for key in ("book", "quire", "tome"):
            for legacy in (False, True):
                with self.subTest(book=key, legacy=legacy):
                    lua = world_runtime()
                    count_water(lua)
                    effect = book_pour(lua, key, legacy)
                    self.assertIsNotNone(effect)
                    p = lua.eval("effect_params")(effect)
                    self.assertEqual((p["kind"], p["mode"]), ("aura", "pour"))
                    # Not a jet: no projectile, no damage, no item in the inventory.
                    self.assertFalse(lua.eval("EntityGetFirstComponent")(effect, "ProjectileComponent"))
                    # It never runs dry: ten seconds on, the same stream still pours every frame.
                    lua.execute("simulate(600)")
                    self.assertTrue(lua.eval("EntityGetIsAlive")(effect))
                    counts = {len(poured(lua, lua.eval("W.frame") - i)) for i in range(60)}
                    self.assertEqual(counts, {5})
                    for drop in poured(lua):
                        # Out of the book's mouth, eight pixels towards the cursor, and on towards it.
                        self.assertAlmostEqual(drop.x, 8, delta=1.01)
                        self.assertAlmostEqual(drop.y, -40, delta=1.01)
                        self.assertGreater(drop.vx, 100)
                        self.assertLess(abs(drop.vy), 20)
                    loops = [c for c in lua.eval("EntityGetComponent")(effect, "AudioLoopComponent").values()
                             if lua.eval("ComponentGetValue2")(c, "event_name") == "materials/spray_potion"]
                    self.assertEqual(len(loops), 1)
                    # Let go: it stops at once.
                    lua.eval("ComponentSetValue2")(lua.eval("CONTROLS"), "mButtonDownFire", False)
                    lua.execute("simulate(1)")
                    self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
                    self.assertFalse(poured(lua))
                    self.assertFalse(list(lua.eval("W.hits").values()))
                    self.assert_clean(lua)

    def test_stream_follows_the_cursor_and_pours_harder_when_it_is_far(self):
        lua = world_runtime()
        count_water(lua)
        book_pour(lua, tx=0, ty=-340)
        lua.execute("simulate(1)")
        far = poured(lua)
        self.assertTrue(all(d.vy < -100 and abs(d.vx) < 20 and d.y < -40 for d in far))
        lua.eval("ComponentSetValue2")(lua.eval("CONTROLS"), "mMousePosition", -30, -40)
        lua.execute("simulate(1)")
        near = poured(lua)
        self.assertTrue(all(d.vx < -60 and d.x < 0 for d in near))
        speed = lambda drops: sum(math.hypot(d.vx, d.vy) for d in drops) / len(drops)
        self.assertGreater(speed(far), speed(near) + 20)
        self.assert_clean(lua)

    def test_it_stops_when_the_page_or_the_item_changes_and_a_new_press_starts_one_stream(self):
        for reason in ("page", "item"):
            with self.subTest(reason=reason):
                lua = world_runtime()
                count_water(lua)
                effect = book_pour(lua)
                if reason == "page":
                    lua.execute('GlobalsSetValue(book_var("book", "active_spell"), "element=fire;form=column")')
                else:
                    lua.execute('ComponentSetValue2(INV, "mActiveItem", 0)')
                lua.execute("simulate(1)")
                self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
                self.assertFalse(poured(lua))
                self.assert_clean(lua)
        lua = world_runtime()
        first = book_pour(lua)
        lua.execute('''
            ComponentSetValue2(CONTROLS, "mButtonFrameFire", W.frame + 1)
            local next_cast = EntityGetFirstComponent(BOOK_ITEM, "VariableStorageComponent")
            for _, c in ipairs(EntityGetComponent(BOOK_ITEM, "VariableStorageComponent")) do
                if ComponentGetValue2(c, "name") == "witch_notebook_next_cast" then ComponentSetValue2(c, "value_int", 0) end
            end
            simulate(2)
        ''')
        streams = list(lua.eval('EntityGetWithTag("witch_water_pour")').values())
        self.assertEqual(len(streams), 1)
        self.assertNotEqual(streams[0], first)
        self.assert_clean(lua)

    def test_cast_without_a_book_pours_for_a_while_the_way_it_was_aimed(self):
        lua = world_runtime()
        count_water(lua)
        effect = cast_page(lua, "watershot", 0, -300)
        frames = lua.eval("effect_params")(effect)["frames"]
        self.assertGreater(frames, 60)
        lua.execute("simulate(30)")
        self.assertTrue(all(d.vy < -80 for d in poured(lua)))
        self.assertEqual(len(poured(lua)), 5)
        lua.eval("simulate")(frames)
        self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
        self.assertFalse(poured(lua))
        self.assert_clean(lua)

    def test_a_wall_at_the_books_mouth_keeps_the_water_on_the_casters_side(self):
        lua = world_runtime()
        lua.globals().WALL_X = 5
        lua.execute('''
            function RaytraceSurfaces(x1, y1, x2, y2)
                if (x1 - WALL_X) * (x2 - WALL_X) <= 0 and x1 ~= x2 then
                    return true, WALL_X, y1 + (y2 - y1) * (WALL_X - x1) / (x2 - x1)
                end
                return false, x2, y2
            end
        ''')
        count_water(lua)
        book_pour(lua)
        lua.execute("simulate(5)")
        drops = poured(lua)
        self.assertEqual(len(drops), 5)
        self.assertTrue(all(d.x < 5 for d in drops))
        self.assert_clean(lua)


if __name__ == "__main__":
    unittest.main(verbosity=2)
