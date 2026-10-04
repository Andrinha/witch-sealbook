"""Renders the witch's books the way the game draws them, into PNG files - to look at the books' design without the game.
The mod's Lua runs with the Noita API stubbed (as in run_tests.py); every GUI call is recorded and painted with the
images the mod makes at init and the game's own pixel font.

    python tests/render_book.py [out_dir]        (default: tests/render; needs lupa, Pillow, numpy)

Writes, for the Spellbook: the first spread, the inks' pages, a spread of seals with the blank page, pasted sheets, the
grimoire, and a page turning over, frame by frame (flip_*.png, and flip.gif); for the Great Tome: its front, its blank
page, Petrification pasted in, a page turning (tome_flip.gif), its grimoire; for the Palm Quire: its first leaf, a seal
on it, a leaf flipping up (quire_flip.gif), a small sheet pasted in, the leaf's bottom curling up under the mouse.
"""
import os
import random
import sys
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import run_tests as R  # noqa: E402

SCALE = 3  # screen pixels per gui unit in the pictures
# the font isn't in the unpacked data (reference/noita_data), it is in the game's own folder
FONT_DIRS = [os.path.join(R.DATA, "data", "fonts"), r"C:\Program Files (x86)\Steam\steamapps\common\Noita\data\fonts"]
FONT_DIR = next((d for d in FONT_DIRS if os.path.exists(os.path.join(d, "font_pixel.xml"))), FONT_DIRS[-1])

GUI = r'''
draws, pixels, image_size = {}, {}, {}
local order, nz, ncolor = 0, nil, nil
local function push( t )
    order = order + 1
    t.order, t.z, t.color = order, nz or 0, ncolor
    draws[#draws + 1] = t
    nz, ncolor = nil, nil
end
function GuiZSetForNextWidget( g, z ) nz = z end
function GuiColorSetForNextWidget( g, r, gg, b, a ) ncolor = { r, gg, b, a } end
function GuiImage( g, id, x, y, file, alpha, sx, sy )
    sx = sx or 1
    if not sy or sy == 0 then sy = sx end
    push( { kind = "image", x = x, y = y, file = file, alpha = alpha or 1, sx = sx, sy = sy } )
end
function GuiText( g, x, y, text, scale ) push( { kind = "text", x = x, y = y, text = text, scale = scale or 1 } ) end
function GuiButton( g, id, x, y, text ) push( { kind = "text", x = x, y = y, text = text } ); return buttons[id] == true end
function GuiGetTextDimensions( g, t, scale ) return py_text_width( t ) * ( scale or 1 ), 9 end
local names, nid = {}, 0
function ModImageMakeEditable( f, w, h )
    if names[f] then return names[f], w, h end
    nid = nid + 1; names[f] = nid; image_size[f] = { w, h }; pixels[f] = {}
    return nid, w, h
end
local files = {}
setmetatable( names, { __newindex = function( t, k, v ) rawset( t, k, v ); files[v] = k end } )
function ModImageSetPixel( id, x, y, c )
    local f = files[id]
    pixels[f][y * image_size[f][1] + x + 1] = c
end
virtual = {}
-- the font's texture, read at init to cut the letters out of (book_gfx.lua create_glyphs)
function ModImageGetPixel( id, x, y )
    local f = files[id]
    if f and f:find( "^data/fonts/" ) then return py_font_pixel( x, y ) end
    return f and pixels[f] and pixels[f][y * image_size[f][1] + x + 1] or 0
end
function ModTextFileSetContent( f, c ) virtual[f] = c end
function ModTextFileGetContent( f ) return virtual[f] or py_read( f ) end
'''


class Font:
    """The game's pixel font (data/fonts/font_pixel.xml): glyph rectangles in a texture"""

    def __init__(self):
        root = ET.parse(os.path.join(FONT_DIR, "font_pixel.xml")).getroot()
        self.tex = np.asarray(Image.open(os.path.join(FONT_DIR, "font_pixel.png")).convert("RGBA")).astype(np.float32) / 255
        self.glyphs = {}
        for q in root.iter("QuadChar"):
            a = {k: float(v) for k, v in q.attrib.items()}
            self.glyphs[int(a["id"])] = a
        self.space = float(root.findtext("WordSpace").strip())

    def width(self, text):
        w = 0
        for ch in text:
            g = self.glyphs.get(ord(ch))
            w += g["width"] if g else self.space
        return w


class Canvas:
    def __init__(self, w, h, scale=SCALE):
        self.scale = scale
        self.img = np.zeros((int(h * scale), int(w * scale), 3), np.float32)
        # a dark cave behind the book, as in the game
        yy, xx = np.mgrid[0:self.img.shape[0], 0:self.img.shape[1]]
        self.img[:] = (np.array([0.07, 0.06, 0.07]) + 0.03 * np.sin(xx[..., None] / 97.0) * np.cos(yy[..., None] / 61.0))

    def blend(self, src, x, y):
        """src: h x w x 4 floats; x, y: screen pixels of its top left"""
        h, w = src.shape[:2]
        x0, y0 = int(round(x)), int(round(y))
        H, W = self.img.shape[:2]
        sx0, sy0 = max(0, -x0), max(0, -y0)
        dx0, dy0 = max(0, x0), max(0, y0)
        dx1, dy1 = min(W, x0 + w), min(H, y0 + h)
        if dx1 <= dx0 or dy1 <= dy0:
            return
        part = src[sy0:sy0 + dy1 - dy0, sx0:sx0 + dx1 - dx0]
        a = part[..., 3:4]
        self.img[dy0:dy1, dx0:dx1] = part[..., :3] * a + self.img[dy0:dy1, dx0:dx1] * (1 - a)

    def save(self, path):
        Image.fromarray((np.clip(self.img, 0, 1) * 255).astype(np.uint8)).save(path)
        return path


def abgr_to_rgba(c):
    c = int(c) & 0xFFFFFFFF
    return (c & 255, (c >> 8) & 255, (c >> 16) & 255, (c >> 24) & 255)


class Book:
    """The mod's book in a stubbed game, with a GUI that records what it draws"""

    def __init__(self, full_grimoire=False):
        self.font = Font()
        lua = R.bare_runtime()
        self.lua = lua
        lua.execute(R.STUBS)
        g = lua.globals()
        g.py_text_width = self.font.width
        tex = (self.font.tex * 255).round().astype(np.int64)
        g.py_font_pixel = lambda x, y: int(tex[y, x, 0] | tex[y, x, 1] << 8 | tex[y, x, 2] << 16 | tex[y, x, 3] << 24)
        read = g.py_read
        g.py_read = lambda f: open(os.path.join(FONT_DIR, os.path.basename(f)), encoding="utf-8").read() if f.startswith("data/fonts/") else read(f)
        lua.execute(GUI)
        for f in R.MOD_FILES:
            lua.execute(open(os.path.join(R.MOD, f), encoding="utf-8").read())
        lua.execute(open(os.path.join(R.MOD, "files", "grimoire.lua"), encoding="utf-8").read())
        lua.execute("sigils_create_images() book_gfx_create() sheets_create()")
        if full_grimoire:
            g.settings["witch_notebook.full_grimoire"] = True
        self.g = g
        self.images = {}

    def image(self, path):
        if path in self.images:
            return self.images[path]
        px = self.g.pixels[path]
        if px is not None:
            w, h = self.g.image_size[path][1], self.g.image_size[path][2]
            flat = np.zeros((h * w, 4), np.float32)
            for i, c in px.items():
                flat[i - 1] = abgr_to_rgba(c)
            arr = flat.reshape(h, w, 4) / 255
        else:
            real = R.read_game_file(path) and (os.path.join(R.MOD, path[len("mods/witch_notebook/"):]) if path.startswith("mods/") else os.path.join(R.DATA, path))
            arr = np.asarray(Image.open(real).convert("RGBA")).astype(np.float32) / 255
        self.images[path] = arr
        return arr

    def frame(self):
        """One update of the book; returns what it drew"""
        self.lua.execute("draws = {}")
        self.g.notebook_update()
        return list(self.g.draws.values())

    def render(self, draws, path, crop=None):
        W, H = self.g.SW, self.g.SH
        cv = Canvas(W, H)
        s = cv.scale
        ordered = sorted(draws, key=lambda d: (-float(d["z"] or 0), d["order"]))
        for d in ordered:
            color = d["color"]
            tint = np.array([color[1], color[2], color[3], color[4]], np.float32) if color else np.ones(4, np.float32)
            if d["kind"] == "image":
                src = self.image(d["file"])
                h, w = src.shape[:2]
                tw, th = max(1, int(round(w * abs(d["sx"]) * s))), max(1, int(round(h * abs(d["sy"]) * s)))
                ys = (np.arange(th) * h / th).astype(int)
                xs = (np.arange(tw) * w / tw).astype(int)
                part = src[ys][:, xs] * tint
                part[..., 3] *= float(d["alpha"])
                cv.blend(part, float(d["x"]) * s, float(d["y"]) * s)
            else:
                x = float(d["x"])
                k = float(d["scale"] or 1)
                for ch in d["text"]:
                    gl = self.font.glyphs.get(ord(ch))
                    if not gl:
                        x += self.font.space * k
                        continue
                    rx, ry, rw, rh = int(gl["rect_x"]), int(gl["rect_y"]), int(gl["rect_w"]), int(gl["rect_h"])
                    if rw > 0 and rh > 0:
                        glyph = self.font.tex[ry:ry + rh, rx:rx + rw]
                        n = max(1, int(round(s * k)))
                        glyph = np.repeat(np.repeat(glyph, n, 0), n, 1) * (tint if color else np.array([0.95, 0.95, 0.95, 1], np.float32))
                        cv.blend(glyph, (x + gl.get("offset_x", 0) * k) * s, (float(d["y"]) + gl.get("offset_y", 0) * k) * s)
                    x += gl["width"] * k
        if crop:
            x0, y0, x1, y1 = [int(v * s) for v in crop]
            cv.img = cv.img[y0:y1, x0:x1]
        return cv.save(path)


def open_book(G):
    G.key_b = True; G.notebook_update(); G.key_b = False


def turn(G, key=7):
    G.pressed[key] = True; G.notebook_update(); G.pressed[key] = False


# the witch carries all three books (run_tests.py) and they are theirs
CARRY_ALL = R.CARRY_ALL + '''
for _, key in ipairs( { "book", "quire", "tome" } ) do run_flags["witch_notebook_has_" .. key] = true end
'''
draw_on_blank = R.draw_on_blank


def switch_book(G, key):
    """A click on the book's name over the open book"""
    index = {"quire": 1, "book": 2, "tome": 3}[key]
    G.buttons[900100 + index] = True; G.notebook_update(); G.buttons[900100 + index] = False


def frames_gif(book, out, name, count):
    """the next 'count' frames: files name_NN.png and name.gif"""
    frames = [book.render(book.frame(), os.path.join(out, f"{name}_{k:02d}.png")) for k in range(count)]
    gif = [Image.open(f) for f in frames]
    gif[0].save(os.path.join(out, f"{name}.gif"), save_all=True, append_images=gif[1:], duration=33, loop=0)
    return frames


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "render")
    os.makedirs(out, exist_ok=True)
    book = Book()
    book.lua.execute(CARRY_ALL)
    G = book.g
    G.flask.witch_ink = 640
    G.flask.witch_ink_blood = 380
    G.flask.witch_ink_gold = 900
    open_book(G)
    for _ in range(3): book.frame()
    written = [book.render(book.frame(), os.path.join(out, "spread_1.png"))]
    # the right page's corner under the mouse turns up
    G.mouse[1], G.mouse[2] = R.RIGHT_X + 180 - 5, R.PAGE_Y + 180 - 5
    written.append(book.render(book.frame(), os.path.join(out, "corner.png"),
                               crop=(R.RIGHT_X + 100, R.PAGE_Y + 110, R.RIGHT_X + 200, R.PAGE_Y + 200)))
    G.mouse[1], G.mouse[2] = 0, 0
    for _ in range(3):
        turn(G)
        for _ in range(40): G.notebook_update()
    written.append(book.render(book.frame(), os.path.join(out, "spread_inks.png")))
    # two seals: one in conjuring ink, one in blood, and the blank page
    random.seed(3)
    turn(G)
    for _ in range(40): G.notebook_update()
    R.draw(G, R.column_seal(book.lua, "fire"))
    G.mouse[1], G.mouse[2] = R.LEFT_X - 26 + 6, R.PAGE_Y + 8 + 24 + 8  # the blood bottle
    G.left_down = G.left_just_down = True; G.notebook_update(); G.left_just_down = False; G.left_down = False
    R.draw(G, R.column_seal(book.lua, "water"))
    for _ in range(3): book.frame()
    G.mouse[1], G.mouse[2] = R.LEFT_X - 26 + 6, R.PAGE_Y + 8 + 24 + 8
    written.append(book.render(book.frame(), os.path.join(out, "spread_seals.png")))
    # a sheet picked up: pasted in after the seals
    G.globals["witch_notebook.pending_sheets"] = "water_dragon:azure;petrification:blood;"
    toggle = lambda: (setattr(G, "key_b", True), G.notebook_update(), setattr(G, "key_b", False))
    toggle(); toggle()
    for _ in range(3): book.frame()
    G.mouse[1], G.mouse[2] = R.RIGHT_X + 90, R.PAGE_Y + 90
    written.append(book.render(book.frame(), os.path.join(out, "spread_sheets.png")))
    # a page turning over, frame by frame
    turn(G, 4)
    written += frames_gif(book, out, "flip", 30)[::6]
    # the grimoire: the learned seals
    G.buttons[900007] = True; G.notebook_update(); G.buttons[900007] = False
    for _ in range(3): book.frame()
    written.append(book.render(book.frame(), os.path.join(out, "grimoire.png")))
    G.buttons[900007] = True; G.notebook_update(); G.buttons[900007] = False

    # the Great Tome: opened the first time it lies at its front, then turns to the blank page
    switch_book(G, "tome")
    for _ in range(3): book.frame()
    written.append(book.render(book.frame(), os.path.join(out, "tome_front.png")))
    for _ in range(60): G.notebook_update()
    G.mouse[1], G.mouse[2] = 0, 0
    written.append(book.render(book.frame(), os.path.join(out, "tome_blank.png")))
    random.seed(5)
    draw_on_blank(G, R.column_seal(book.lua, "earth"))
    G.globals["witch_notebook.pending_sheets"] = "petrification:blood;"
    for _ in range(3): G.notebook_update()
    turn(G, 7)
    for _ in range(60): G.notebook_update()
    written.append(book.render(book.frame(), os.path.join(out, "tome_sheets.png")))
    turn(G, 4)
    written += frames_gif(book, out, "tome_flip", 40)[::8]
    G.buttons[900007] = True; G.notebook_update(); G.buttons[900007] = False
    for _ in range(3): book.frame()
    written.append(book.render(book.frame(), os.path.join(out, "tome_grimoire.png")))
    G.buttons[900007] = True; G.notebook_update(); G.buttons[900007] = False

    # the Palm Quire: its first leaf, a seal on it, the leaf flipping up onto the lid
    switch_book(G, "quire")
    for _ in range(3): book.frame()
    written.append(book.render(book.frame(), os.path.join(out, "quire_first.png")))
    random.seed(7)
    draw_on_blank(G, R.column_seal(book.lua, "water"))
    for _ in range(120): G.notebook_update()
    view, side = G.notebook_view()
    G.mouse[1], G.mouse[2] = view.front.x + 60, view.front.y + 60
    written.append(book.render(book.frame(), os.path.join(out, "quire_seal.png")))
    G.mouse[1], G.mouse[2] = 0, 0
    turn(G, 7)
    written += frames_gif(book, out, "quire_flip", 30)[::6]
    G.globals["witch_notebook.pending_sheets"] = "pyreball:gold;"
    for _ in range(3): G.notebook_update()
    written.append(book.render(book.frame(), os.path.join(out, "quire_sheet.png")))
    # the bottom of the leaf curls up under the mouse
    turn(G, 4)
    for _ in range(40): G.notebook_update()
    view, side = G.notebook_view()
    G.mouse[1], G.mouse[2] = view.front.x + 60, view.front.y + 114
    written.append(book.render(book.frame(), os.path.join(out, "quire_curl.png")))
    print("\n".join(written))


if __name__ == "__main__":
    main()
