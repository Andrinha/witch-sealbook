"""Ornamental seals: handwriting, element combinations, harmless light and saved stags."""
import random
import unittest

from harness import world_runtime, cast_page, freeze_enemies
import make_grimoire as Generator
import grimoire as G
import wiki_spells as Wiki

SHAPES = ("dragon", "horse", "bird", "fish", "owlcat", "leech",
          "scalewolf", "torchstag", "liongoat", "frillram")


def recipe(shape, element=None):
    symbols = [G.sig(shape, 0, 0, .8)] if element is None else [
        G.sig(shape, 0, -.2, .7), G.sig(element, 0, .65, .3)]
    return G.Spell("test", "Test", "", "", "", "Sculpting", symbols)


def cast_shape(lua, shape, element="light"):
    lua.globals().DECORATIVE_DATA = (
        f"element={element};shape={shape};form=column;precision=1;stability=1;lifetime=-1")
    return lua.execute('''
        return cast_spell(PLAYER, parse_spell_data(DECORATIVE_DATA), 0, -40, 1, 0, 180, -40, W.frame, nil)
    ''')


class DecorativeSpells(unittest.TestCase):
    def test_creatures_are_read_whole_with_detached_parts_and_an_element(self):
        lua = Generator.lua_runtime()
        for shape in SHAPES:
            for element in (None, "light", "water", "fire"):
                for seed in (None, 1, 2, 3, 4):
                    with self.subTest(shape=shape, element=element, seed=seed):
                        strokes = Generator.render_recipe(lua, recipe(shape, element),
                            None if seed is None else random.Random(seed))
                        spell, data, seal = Generator.compile_page(lua, strokes)
                        self.assertIsNotNone(spell, data)
                        self.assertEqual(spell["shape"], shape)
                        self.assertEqual(spell["element"], element or "light")
                        # The animal's scales/hooves must not turn into modifiers.
                        self.assertTrue(all(s["kind"] == "sigil" for s in seal["symbols"].values()))

    def test_elements_and_their_modifiers_do_not_become_creatures(self):
        lua = Generator.lua_runtime()
        for element in ("fire", "water", "wind", "earth", "light"):
            for seed in range(4):
                symbols = [G.sig(element, 0, 0, .5)] + G.around("column", [0, 180], .72, .25)
                sample = G.Spell("plain", "", "", "", "", "", symbols)
                spell, data, _ = Generator.compile_page(lua, Generator.render_recipe(lua, sample, random.Random(seed)))
                self.assertIsNotNone(spell, data)
                self.assertIsNone(spell["shape"])
                self.assertEqual(spell["element"], element)

    def test_all_light_creatures_reveal_and_never_hurt_or_blind(self):
        for shape in SHAPES:
            with self.subTest(shape=shape):
                lua = world_runtime()
                lua.execute('EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent")); GROUND=10')
                freeze_enemies(lua, ((14, -45), (70, -40), (160, -40)))
                ids = list(cast_shape(lua, shape).values())
                lua.execute("simulate(120)")
                self.assertFalse(list(lua.eval("W.hits").values()))
                for e in ids:
                    self.assertTrue(lua.eval("EntityGetIsAlive")(e))
                    sprites = list((lua.eval("EntityGetComponent")(e, "SpriteComponent") or {}).values())
                    self.assertTrue(any(lua.eval("ComponentGetValue2")(c, "fog_of_war_hole") for c in sprites))
                for enemy in lua.eval("ENEMIES").values():
                    # A luminous leech must not attach a blindness effect either.
                    self.assertFalse(list((lua.eval("EntityGetAllChildren")(enemy) or {}).values()))
                lua.eval("simulate")(int(max(lua.eval("effect_params")(e)["frames"] for e in ids)) + 2)
                self.assertTrue(all(not lua.eval("EntityGetIsAlive")(e) for e in ids))
                self.assertFalse(list(lua.eval("W.errors").values()))
                self.assertFalse(list((lua.eval("TRAILS") or {}).values()))

    def test_fire_and_water_creatures_run_and_expire(self):
        for shape in SHAPES:
            for element in ("fire", "water"):
                with self.subTest(shape=shape, element=element):
                    lua = world_runtime()
                    lua.execute("GROUND=10")
                    ids = list(cast_shape(lua, shape, element).values())
                    lua.execute("simulate(1)")
                    max_particles = 0
                    for _ in range(90):
                        lua.execute("W.particles=0; simulate(1)")
                        max_particles = max(max_particles, lua.eval("W.particles"))
                    self.assertLess(max_particles / len(ids), 900)
                    lua.eval("simulate")(int(max(lua.eval("effect_params")(e)["frames"] for e in ids)) + 2)
                    self.assertTrue(all(not lua.eval("EntityGetIsAlive")(e) for e in ids))
                    self.assertFalse(list(lua.eval("W.errors").values()))
                    self.assertFalse(list((lua.eval("TRAILS") or {}).values()))

    def test_only_one_dragon_lives_in_the_world(self):
        dragons = '''
            local out = {}
            for id, ent in pairs(W.entities) do
                if ent.alive and ent.name == "witch_mover_sculpture" and effect_params(id).shape == "dragon" then out[#out+1] = id end
            end
            return out
        '''
        lua = world_runtime()
        # Piercing signs make more of the other sculptures, never a second dragon.
        lua.execute('''
            cast_spell(PLAYER, parse_spell_data("element=water;shape=dragon;precision=1;stability=1;b=pierce:3"),
                0, -40, 1, 0, 180, -40, W.frame, nil)
        ''')
        lua.execute("simulate(30)")
        first = list(lua.execute(dragons).values())
        self.assertEqual(len(first), 1)
        # Any other dragon, of any seal and element, takes its place.
        for cast in (lambda: cast_page(lua, "water_dragon"), lambda: cast_shape(lua, "dragon", "fire"),
                     lambda: cast_page(lua, "boilfire_dragon")):
            cast()
            lua.execute("simulate(2)")
            now = list(lua.execute(dragons).values())
            self.assertEqual(len(now), 1)
            self.assertNotIn(first[0], now)
            first = now
        self.assertEqual(len(list((lua.eval("TRAILS") or {}).values())), 1)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_torchstag_page_and_old_saved_horse_create_actual_stags(self):
        for legacy in (False, True):
            lua = world_runtime()
            lua.execute("GROUND=10")
            if legacy:
                lua.execute('''
                    cast_spell(PLAYER, parse_spell_data("element=fire;shape=horse;named=torchstag;precision=1;stability=1;b=mimic:1"),
                        0, -40, 1, 0, 200, -40, W.frame, nil)
                ''')
            else:
                cast_page(lua, "torchstag")
            effects = lua.execute('''
                local out = {}
                for id, ent in pairs(W.entities) do
                    if ent.alive and ent.name == "witch_mover_sculpture" then out[#out+1] = id end
                end
                return out
            ''')
            self.assertEqual(len(effects), 3)
            for e in effects.values():
                p = lua.eval("effect_params")(e)
                self.assertEqual((p["shape"], p["element"]), ("torchstag", "fire"))
            lua.execute("simulate(60)")
            self.assertGreater(lua.eval("W.real_fire"), 0)
            self.assertFalse(list(lua.eval("W.errors").values()))

    def test_torchstag_hand_copies_still_select_the_named_page(self):
        lua = Wiki.load()
        page = Wiki.page(lua, lua.eval("GRIMOIRE_BY_KEY.torchstag"))
        for draw in (Wiki.by_hand, lambda p, r: Wiki.as_player(p, r, False)):
            for seed in range(8):
                self.assertEqual(Wiki.read(lua, draw(page, random.Random(seed)))[0], "torchstag")


if __name__ == "__main__":
    unittest.main()
