"""Zoomed contact sheet of Flame Burst's flying fireball, from the real Lua sprite/particle calls.

python tests/render_flame_burst.py [name] -> tests/output/<name>.png (default flame_burst_flight)
Top row: level flight; bottom row: a diagonal shot. Offline preview, not a game screenshot.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

from harness import world_runtime, cast_page
from fluid_render_capture import sprites, draw_sprites

OUT = Path(__file__).resolve().parent / "output"
FRAMES = [3, 7, 11, 15, 19, 23, 27, 31, 35]
SCALE, WIDTH, HEIGHT = 4, 440, 240


def flight(target):
    lua = world_runtime()
    lua.execute('''
        EntitySetTransform(PLAYER, 0, -20)
        EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent"))
        for _, id in ipairs(ENEMIES) do EntityKill(id) end
    ''')
    particles, tick = [], [0]

    def particle(material, x, y, count, vx, vy, packed, lmin, lmax, force, front, collide, randomize, gx, gy):
        packed = int(packed) & 0xFFFFFFFF
        rgb = (packed & 255, (packed >> 8) & 255, (packed >> 16) & 255)
        particles.append((tick[0], x, y, vx, vy, rgb, (packed >> 24) / 255, max(lmin, 1 / 60), gy))

    lua.globals().GameCreateCosmeticParticle = particle
    effect = cast_page(lua, "flame_burst", *target)
    panels = []
    for frame in range(max(FRAMES) + 1):
        tick[0] = frame
        lua.execute("simulate(1)")
        if frame not in FRAMES:
            continue
        hx, hy = lua.eval("EntityGetTransform")(effect)[:2]
        dx, dy = target[0], target[1] + 40
        n = math.hypot(dx, dy)
        cx, cy = hx - dx / n * 16, hy - dy / n * 16
        ox, oy = WIDTH / 2 - cx * SCALE, HEIGHT / 2 - cy * SCALE
        bg = Image.new("RGB", (WIDTH, HEIGHT), (17, 20, 29))
        samples = sprites(lua, layer=None)
        draw_sprites(bg, samples, ox, oy, SCALE)
        glow = draw_sprites(Image.new("RGB", bg.size), samples, ox, oy, SCALE)
        light = Image.new("RGB", bg.size)
        ld = ImageDraw.Draw(light)
        for born, x, y, vx, vy, rgb, alpha, life, gravity in particles:
            age = (frame - born) / 60
            if age >= life:
                continue
            fade = (1 - age / life) * alpha
            px = (x + vx * age) * SCALE + ox
            py = (y + vy * age + gravity * age * age / 2) * SCALE + oy
            ld.rectangle((px, py, px + SCALE - 1, py + SCALE - 1), fill=tuple(round(v * fade) for v in rgb))
        bg = ImageChops.add(bg, glow.filter(ImageFilter.GaussianBlur(2 * SCALE)))
        bg = ImageChops.add(bg, light)
        ImageDraw.Draw(bg).text((6, 4), f"frame {frame}", fill=(160, 165, 180))
        panels.append(bg)
    return panels


if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "flame_burst_flight"
    OUT.mkdir(exist_ok=True)
    rows = [flight((260, -40)), flight((220, -170))]
    sheet = Image.new("RGB", (WIDTH * len(FRAMES), HEIGHT * len(rows)))
    for y, row in enumerate(rows):
        for x, panel in enumerate(row):
            sheet.paste(panel, (x * WIDTH, y * HEIGHT))
    sheet.save(OUT / (name + ".png"))
    print(OUT / (name + ".png"))
