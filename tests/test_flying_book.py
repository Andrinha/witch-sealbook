"""Seal of Expansion and Levitation: the flying book grows, beats its halves like wings and carries the caster.

python tests/test_flying_book.py
"""
import unittest

from harness import world_runtime, cast_page
from fluid_render_capture import texture

BOOK = "mods/witch_notebook/files/gfx/flying_book_"


class FlyingBook(unittest.TestCase):
    def test_book_grows_then_beats_its_halves_under_the_casters_feet(self):
        lua = world_runtime()
        lua.execute("for _, id in ipairs(ENEMIES) do EntityKill(id) end")
        drawn = []
        lua.globals().GameCreateSpriteForXFrames = lambda path, x, y, *rest: drawn.append((path, x, y))
        effect = cast_page(lua, "expansion_levitation")
        lua.eval("effect_set")(effect, "frames", 200)
        frames = []
        for _ in range(199):
            drawn.clear()
            lua.execute("simulate(1)")
            if not lua.eval("EntityGetIsAlive")(effect):
                break
            self.assertEqual(len(drawn), 1)
            px, py = lua.eval("EntityGetTransform")(lua.eval("PLAYER"))[:2]
            path, x, y = drawn[0]
            # Always right under the caster, its spine at their feet.
            self.assertAlmostEqual(x, px, delta=0.51)
            self.assertTrue(4 <= y - py <= 11, y - py)
            frames.append(path[len(BOOK):-4])
        # It grows out of the small book in hand, and shrinks back at the end.
        self.assertEqual(frames[:12], ["small"] * 6 + ["mid"] * 6)
        self.assertEqual(frames[-3:], ["small"] * 3)
        # In between it is never still: tips up, level, down, level, each for seven frames.
        flying = frames[12:-12]
        self.assertEqual(set(flying), {"1", "2", "3"})
        runs = []
        for name in flying:
            if runs and runs[-1][0] == name:
                runs[-1][1] += 1
            else:
                runs.append([name, 1])
        self.assertTrue(all(length <= 7 for _, length in runs))
        order = "".join(name for name, _ in runs)
        self.assertIn("1232123", order)
        # Three full frames of one size with the spine on the same row, so the book does not jump as it beats.
        sizes = {texture(BOOK + f"{i}.png").size for i in (1, 2, 3)}
        self.assertEqual(sizes, {(34, 20)})
        tips = []
        for i in (1, 2, 3):
            image = texture(BOOK + f"{i}.png")
            self.assertTrue(image.getpixel((16, 13))[3] and image.getpixel((17, 13))[3])
            tips.append(min(y for y in range(20) if image.getpixel((0, y))[3]))
        # tips up, level, down
        self.assertLess(tips[0], tips[1])
        self.assertLess(tips[1], tips[2])
        self.assertLess(texture(BOOK + "small.png").width, texture(BOOK + "mid.png").width)
        self.assertLess(texture(BOOK + "mid.png").width, 34)
        self.assertFalse(list(lua.eval("W.errors").values()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
