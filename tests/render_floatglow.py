"""Zoomed contact sheet of the Floatglow Lamps, from the real Lua sprite/particle calls.

python tests/render_floatglow.py [name] -> tests/output/<name>.png (default floatglow_lamps)
Rows: the wall-anchored lamp on its bracket, the same without a wall (its tray is let go; the mock world has no
physics, so it stays where it was cast), and the Ch. 28 lantern flying after its caster.
Columns: lighting up, shining, and going out. Offline preview, not a game screenshot.
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

from harness import world_runtime, cast_page
from test_light_spells import still_player
from fluid_render_capture import texture
import wiki_spells as Wiki

OUT = Path(__file__).resolve().parent / "output"
FRAMES = [1, 8, 14, 24, 60, 100, 140, 150, 158]
SCALE, WIDTH, HEIGHT, LIFE = 6, 330, 330, 160
WALL = 112


def lamp(key, wall):
    lua = world_runtime()
    still_player(lua, 0, -20)
    lua.execute("for _, id in ipairs(ENEMIES) do EntityKill(id) end")
    if wall:
        lua.globals().WALL_X = WALL
        lua.execute('''
            local ray = RaytraceSurfaces
            function RaytraceSurfaces(x1, y1, x2, y2)
                if (x1 - WALL_X) * (x2 - WALL_X) <= 0 and x1 ~= x2 then
                    local t = (WALL_X - x1) / (x2 - x1)
                    return true, WALL_X, y1 + (y2 - y1) * t
                end
                return ray(x1, y1, x2, y2)
            end
        ''')
    particles, sprites, tick = [], [], [0]

    def particle(material, x, y, count, vx, vy, packed, lmin, lmax, force, front, collide, randomize, gx, gy):
        packed = int(packed) & 0xFFFFFFFF
        rgb = (packed & 255, (packed >> 8) & 255, (packed >> 16) & 255)
        particles.append((tick[0], x, y, vx, vy, rgb, (packed >> 24) / 255, max(lmin, 1 / 60), gy))

    lua.globals().GameCreateCosmeticParticle = particle
    lua.globals().GameCreateSpriteForXFrames = lambda path, x, y, *rest: sprites.append((path, x, y))
    effect = cast_page(lua, key, 100)
    lua.eval("effect_set")(effect, "frames", LIFE)
    lantern = key == "floatglow"
    cx, cy = (6, -36) if lantern else (100, -40)
    ox, oy = WIDTH / 2 - cx * SCALE, HEIGHT / 2 - cy * SCALE
    book = Image.open(Path(Wiki.MOD) / "files/gfx/spellbook.png").convert("RGBA")
    panels = []
    for frame in range(max(FRAMES) + 1):
        tick[0] = frame
        sprites.clear()
        lua.execute("simulate(1)")
        if frame not in FRAMES:
            continue
        bg = Image.new("RGB", (WIDTH, HEIGHT), (17, 20, 29))
        draw = ImageDraw.Draw(bg)
        if wall:
            draw.rectangle((WALL * SCALE + ox, 0, WIDTH, HEIGHT), fill=(58, 52, 56))
        if lantern:
            # The caster, standing in for the player: the lantern hangs by their shoulder.
            px, py = lua.eval("EntityGetTransform")(lua.eval("PLAYER"))[:2]
            draw.rectangle(((px - 4) * SCALE + ox, (py - 12) * SCALE + oy, (px + 4) * SCALE + ox, (py + 8) * SCALE + oy),
                           fill=(74, 58, 92))
            big = book.resize((book.width * SCALE, book.height * SCALE), Image.Resampling.NEAREST)
            bg.paste(big, (round((px + 3) * SCALE + ox), round((py - 8) * SCALE + oy)), big)
        for body in lua.eval("EntityGetWithTag")("witch_lamp_tray").values():
            # The physics tray draws itself in the game.
            bx, by = lua.eval("EntityGetTransform")(body)[:2]
            sprites.append(("mods/witch_notebook/files/gfx/floatglow_tray.png", bx, by))
        for path, x, y in sprites:
            image = texture(path)
            image = image.resize((image.width * SCALE, image.height * SCALE), Image.Resampling.NEAREST)
            bg.paste(image, (round((x - image.width / SCALE / 2) * SCALE + ox),
                             round((y - image.height / SCALE / 2) * SCALE + oy)), image)
        light = Image.new("RGB", bg.size)
        ld = ImageDraw.Draw(light)
        for born, x, y, vx, vy, rgb, alpha, life, gravity in particles:
            age = (frame - born) / 60
            if age >= life:
                continue
            fade = (1 - age / life) * alpha
            px = int((x + vx * age) // 1) * SCALE + ox
            py = int((y + vy * age + gravity * age * age / 2) // 1) * SCALE + oy
            ld.rectangle((px, py, px + SCALE - 1, py + SCALE - 1), fill=tuple(round(v * fade) for v in rgb))
        bg = ImageChops.add(bg, light.filter(ImageFilter.GaussianBlur(2 * SCALE)).point(lambda v: v // 2))
        bg = ImageChops.add(bg, light)
        ImageDraw.Draw(bg).text((6, 4), f"{key} frame {frame}", fill=(160, 165, 180))
        panels.append(bg)
    return panels


if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "floatglow_lamps"
    OUT.mkdir(exist_ok=True)
    rows = [lamp("floatglow_anchored", True), lamp("floatglow_anchored", False), lamp("floatglow", False)]
    sheet = Image.new("RGB", (WIDTH * len(FRAMES), HEIGHT * len(rows)))
    for y, row in enumerate(rows):
        for x, panel in enumerate(row):
            sheet.paste(panel, (x * WIDTH, y * HEIGHT))
    sheet.save(OUT / (name + ".png"))
    print(OUT / (name + ".png"))
