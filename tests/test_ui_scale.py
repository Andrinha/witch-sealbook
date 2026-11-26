"""Book rendering and pointer input share the same runtime UI scale."""

import unittest

import run_tests as R
from harness import load_mod


def load_ui(width, height):
    lua = load_mod()
    g = lua.globals()
    g.SW, g.SH = width, height
    lua.execute("""
        function InputGetMousePosOnScreen() return mouse[1] * 720 / SH, mouse[2] * 720 / SH end
        function GuiStartFrame() images, widgets = {}, {} end
        function GuiImage(g, id, x, y, file, alpha, sx, sy)
            images[file] = { x = x, y = y, sx = sx or 1, sy = sy or sx or 1 }
        end
        function GuiGetTextDimensions(g, text, scale)
            scale = scale or 1
            return #text * 4 * scale, 8 * scale
        end
        function GuiButton(g, id, x, y, text, scale)
            widgets[text] = { id = id, x = x, y = y, scale = scale or 1 }
            return buttons[id] == true
        end
    """)
    return lua, g


class UIScale(unittest.TestCase):
    def test_scaled_page_and_clear_button_match_pointer(self):
        for percent in (50, 100, 125):
            with self.subTest(percent=percent):
                lua, G = load_ui(1280, 720)
                G.settings["witch_notebook.ui_scale"] = percent
                if percent == 125:
                    G.settings["witch_notebook.mouse_calibration"] = "2,-10,2,-14,1280,720"
                    lua.execute("""
                        function InputGetMousePosOnScreen() return (mouse[1] + 10) / 2, (mouse[2] + 14) / 2 end
                    """)
                R.open_book(G)

                view, side = G.notebook_view()
                image = G.images[G.book_page_image(view["def"], "page", side == "front")]
                scale = percent / 100
                self.assertAlmostEqual(scale, image.sx)
                self.assertAlmostEqual(scale, image.sy)

                G.left_down = True
                for x in (45, 55, 65):
                    G.mouse[1], G.mouse[2] = image.x + x * scale, image.y + 60 * scale
                    G.notebook_update()
                G.left_down = False
                G.notebook_update()
                stroke = G.BookStore.load("book").seals[1].strokes[1]
                self.assertAlmostEqual(45, stroke[1].x)
                self.assertAlmostEqual(60, stroke[1].y)

                clear = G.widgets["Clear"]
                self.assertAlmostEqual(scale, clear.scale)
                G.mouse[1], G.mouse[2] = clear.x + 4 * scale, clear.y + 4 * scale
                G.left_down = G.left_just_down = True
                G.notebook_update()
                G.left_down = G.left_just_down = False
                G.buttons[clear.id] = True
                G.notebook_update()
                self.assertEqual(0, len(G.BookStore.load("book").seals[1].strokes))

    def test_tome_and_navigation_fit_on_a_small_screen(self):
        lua, G = load_ui(640, 360)
        lua.execute(R.CARRY_ALL)
        G.held_item = 13
        G.settings["witch_notebook.ui_scale"] = 125
        R.open_book(G)

        view, _ = G.notebook_view()
        book = view["def"]
        self.assertEqual("tome", book.key)
        cover = G.images[G.book_cover_image(book)]
        self.assertGreater(cover.sx, 1)
        self.assertGreaterEqual(cover.x, 0)
        self.assertGreaterEqual(cover.y, 0)
        self.assertLessEqual(cover.x + 2 * (book.page + book.gap + book.margin) * cover.sx, G.SW)
        self.assertLessEqual(cover.y + (book.page + 2 * book.margin) * cover.sy, G.SH)
        for label, button in G.widgets.items():
            width, height = G.GuiGetTextDimensions(None, label, button.scale)
            self.assertGreaterEqual(button.x, 0, label)
            self.assertGreaterEqual(button.y, 0, label)
            self.assertLessEqual(button.x + width, G.SW, label)
            self.assertLessEqual(button.y + height, G.SH, label)


if __name__ == "__main__":
    unittest.main()
