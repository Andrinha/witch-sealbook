"""Wall Breaker: what its projectile crushes into sand.

python tests/test_wall_breaker.py
"""
import unittest

from harness import world_runtime, cast_page


class WallBreaker(unittest.TestCase):
    def test_projectile_turns_stone_and_earth_into_sand(self):
        lua = world_runtime()
        lua.execute('''
            dofile_once("mods/witch_notebook/files/carriers.lua")
            carriers_create()
            W.added = {}
        ''')
        cast_page(lua, "wall_breaker")
        crush = [item[2] for item in lua.eval("W.added").values()
                 if item[1] == "MagicConvertMaterialComponent" and "rock_static" in (item[2].from_material_array or "")]
        self.assertEqual(len(crush), 1)
        before, after = crush[0].from_material_array.split(","), crush[0].to_material_array.split(",")
        self.assertEqual(len(before), len(after))
        turns = dict(zip(before, after))
        # Stone as before, and now earth of every kind too.
        for material in ("rock_static", "sandstone", "soil", "soil_lush", "soil_dead", "soil_dark", "soil_lush_dark", "fungisoil"):
            self.assertEqual(turns[material], "sand", material)
        self.assertEqual(turns["snow_static"], "snow")
        # Every name is a real material; hard rock and temple bricks still withstand it.
        self.assertTrue(all(lua.globals().py_material(m) for m in before + after))
        self.assertFalse({"rock_hard", "templebrick_static", "steel_static"} & set(before))
        self.assertFalse(list(lua.eval("W.errors").values()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
