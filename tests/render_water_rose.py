"""The Water Rose as its pen draws it: the cells the emitter would leave, frame by frame.

python tests/render_water_rose.py [name] -> tests/output/<name>.png (default water_rose_growth)
Top row: on open ground. Bottom row: under a low ceiling, which the stem turns away from.
The offline world has no cells: each frame this places the emitter's count of cells at random within its brush,
as the game does. Colors, glow and the final fall into water are the game's and are not shown.
"""
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw

from harness import world_runtime, cast_page

OUT = Path(__file__).resolve().parent / "output"
FRAMES = [10, 30, 55, 80, 110, 150, 200, 260]
SCALE, WIDTH, HEIGHT = 5, 380, 500


def pen(lua):
    """the pen's position, brush, cells a frame, and whether it draws"""
    for child in lua.eval("EntityGetWithTag")("witch_rose_pen").values():
        emitter = lua.eval("EntityGetFirstComponentIncludingDisabled")(child, "ParticleEmitterComponent")
        get = lambda name: lua.eval("ComponentGetValue2")(emitter, name)
        x, y = lua.eval("EntityGetTransform")(child)[:2]
        return x, y, get("x_pos_offset_max"), int(get("count_max")), bool(get("is_emitting"))


def grow(lua, effect, frames, rng=None):
    """simulate 'frames' frames; returns the cells drawn, in order"""
    rng = rng or random.Random(1)
    cells = []
    for _ in range(frames):
        lua.execute("simulate(1)")
        state = pen(lua) if lua.eval("EntityGetIsAlive")(effect) else None
        if state and state[4]:
            x, y, brush, count, _ = state
            for _ in range(count):
                cell = (round(x + rng.uniform(-brush, brush)), round(y + rng.uniform(-brush, brush)))
                if cell not in cells:
                    cells.append(cell)
    return cells


def world(ceiling):
    lua = world_runtime()
    lua.execute("for _, id in ipairs(ENEMIES) do EntityKill(id) end; GROUND = 10")
    if ceiling is not None:
        lua.globals().CEILING = ceiling
        lua.execute('''
            local ray = RaytraceSurfaces
            function RaytraceSurfaces(x1, y1, x2, y2)
                if x1 > 70 and (y1 - CEILING) * (y2 - CEILING) <= 0 and y1 ~= y2 then
                    return true, x1 + (x2 - x1) * (CEILING - y1) / (y2 - y1), CEILING
                end
                return ray(x1, y1, x2, y2)
            end
        ''')
    return lua


def row(ceiling):
    lua = world(ceiling)
    effect = cast_page(lua, "water_rose", 100, 0)
    rng, cells, panels, last = random.Random(1), [], [], 0
    for frame in FRAMES:
        cells += [c for c in grow(lua, effect, frame - last, rng) if c not in cells]
        last = frame
        bg = Image.new("RGB", (WIDTH, HEIGHT), (17, 20, 29))
        draw = ImageDraw.Draw(bg)
        ox, oy = WIDTH / 2 - 100 * SCALE, HEIGHT - 30 - 10 * SCALE
        draw.rectangle((0, 10 * SCALE + oy, WIDTH, HEIGHT), fill=(58, 52, 56))
        if ceiling is not None:
            draw.rectangle((70 * SCALE + ox, 0, WIDTH, ceiling * SCALE + oy), fill=(58, 52, 56))
        for x, y in cells:
            draw.rectangle((x * SCALE + ox, y * SCALE + oy, x * SCALE + ox + SCALE - 1, y * SCALE + oy + SCALE - 1),
                           fill=(90, 168, 220))
        draw.text((6, 4), f"frame {frame}, {len(cells)} cells", fill=(160, 165, 180))
        panels.append(bg)
    return panels


if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "water_rose_growth"
    OUT.mkdir(exist_ok=True)
    rows = [row(None), row(-38)]
    sheet = Image.new("RGB", (WIDTH * len(FRAMES), HEIGHT * len(rows)))
    for y, panels in enumerate(rows):
        for x, panel in enumerate(panels):
            sheet.paste(panel, (x * WIDTH, y * HEIGHT))
    sheet.save(OUT / (name + ".png"))
    print(OUT / (name + ".png"))
