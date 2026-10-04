"""Purify and Sewer Grate: they clean foul liquid and pour out no water of their own.

python tests/test_purify.py
"""
import unittest

from harness import world_runtime, cast_page


def added(lua, kind):
    return [item[2] for item in lua.eval("W.added").values() if item[1] == kind]


class Purify(unittest.TestCase):
    def test_new_and_saved_pages_only_purify(self):
        for key in ("purify", "sewer_grate"):
            for legacy in (False, True):
                with self.subTest(key=key, legacy=legacy):
                    lua = world_runtime()
                    lua.execute('''
                        W.spawned = {}
                        local particle = GameCreateParticle
                        function GameCreateParticle(material, ...)
                            table.insert(W.spawned, material)
                            return particle(material, ...)
                        end
                        W.made, W.added = {}, {}
                    ''')
                    effect = cast_page(lua, key, legacy=legacy)
                    p = lua.eval("effect_params")(effect)
                    self.assertEqual((p["kind"], p["mode"]), ("zone", "purify"))
                    # The wave is around the caster, not a carrier flying off or a field of water.
                    self.assertEqual(lua.eval("EntityGetTransform")(effect)[:2], (0, -40))
                    lua.execute("simulate(60)")
                    # No carrier was loaded, nothing emits a material, and not one real cell was created.
                    self.assertFalse(list(lua.eval("W.made").values()))
                    self.assertFalse(added(lua, "ParticleEmitterComponent"))
                    self.assertFalse(list(lua.eval("W.spawned").values()))
                    self.assertFalse(lua.eval("EntityGetFirstComponent")(effect, "ProjectileComponent"))
                    # One conversion: foul liquids into water, cell for cell.
                    (convert,) = added(lua, "MagicConvertMaterialComponent")
                    foul, clean = convert.from_material_array.split(","), convert.to_material_array.split(",")
                    self.assertEqual(len(foul), len(clean))
                    self.assertEqual(set(clean), {"water"})
                    self.assertTrue({"acid", "poison", "radioactive_liquid", "slime", "water_swamp", "blood"} <= set(foul))
                    # Clean water, lava and the like are left as they are.
                    self.assertFalse({"water", "lava", "oil", "alcohol"} & set(foul))
                    self.assertFalse(convert.from_any_material)
                    self.assertGreaterEqual(convert.radius, 50)
                    # It ends by itself and harms no one.
                    lua.execute("simulate(120)")
                    self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
                    self.assertFalse(list(lua.eval("W.hits").values()))
                    self.assertFalse(list(lua.eval("W.errors").values()))

    def test_purify_sign_on_other_seals_cleans_acid_too(self):
        lua = world_runtime()
        lua.execute('''
            dofile_once("mods/witch_notebook/files/carriers.lua")
            carriers_create()
            W.added = {}
            cast_spell(PLAYER, parse_spell_data("element=water;form=column;precision=1;stability=1;b=purify:1"),
                0, -40, 1, 0, 200, -40, W.frame, nil)
        ''')
        lists = [c.from_material_array for c in added(lua, "MagicConvertMaterialComponent") if c.from_material_array]
        self.assertTrue(any("acid" in text.split(",") for text in lists))
        for c in added(lua, "MagicConvertMaterialComponent"):
            if c.from_material_array:
                self.assertEqual(len(c.from_material_array.split(",")), len(c.to_material_array.split(",")))
        self.assertFalse(list(lua.eval("W.errors").values()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
