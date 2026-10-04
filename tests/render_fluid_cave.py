"""Gas sprites in an uneven cave: shows where fire fails to reach terrain.

python tests/render_fluid_cave.py -> tests/output/fluid_cave_<spell>.png
Top: actual sprite/cosmetic calls; terrain hides the body, which is drawn
behind the world grid (--front shows it unhidden). Bottom: solver cells (grey
solid, orange drawn as a sprite, magenta hot without one).
"""
from pathlib import Path
import sys

from PIL import Image, ImageChops, ImageDraw

from harness import world_runtime, cast_page
from fluid_render_capture import sprites, draw_sprites

OUT = Path(__file__).resolve().parent / "output"
X0, Y0, X1, Y1, SCALE = -70, -100, 210, 0, 4
ROCK, SKY, FRONT = (58, 54, 62), (14, 18, 24), False

CAVE = '''
    function TERRAIN(x, y)
        local floor_y = math.floor(-18 + 5 * math.sin(x * 0.09) + 3 * math.sin(x * 0.31 + 1))
        local roof_y = math.floor(-74 + 4 * math.sin(x * 0.13 + 2) + 2 * math.sin(x * 0.4))
        if y >= floor_y or y <= roof_y then return true end
        if x >= 118 and x < 126 and y <= -48 then return true end
        if x >= 66 and x < 78 and y >= -31 then return true end
        if x >= -52 and x < -44 and y >= -50 and y < -36 then return true end
        return false
    end
    function RaytraceSurfacesAndLiquiform(x1, y1, x2, y2)
        local dx, dy = x2 - x1, y2 - y1
        local n = math.max(1, math.ceil(math.max(math.abs(dx), math.abs(dy)) * 2))
        for k = 0, n do
            local x, y = x1 + dx * k / n, y1 + dy * k / n
            if TERRAIN(math.floor(x), math.floor(y)) then return true, x, y end
        end
        return false, x2, y2
    end
    local trace = RaytraceSurfacesAndLiquiform
    RAYS = 0
    function RaytraceSurfacesAndLiquiform(...) RAYS = RAYS + 1; return trace(...) end
    RaytraceSurfaces = RaytraceSurfacesAndLiquiform
    for _, id in ipairs(ENEMIES) do EntityKill(id) end
    dofile_once("mods/witch_notebook/files/effects/flame_fields.lua")
    dofile_once("mods/witch_notebook/files/effects/flame_shot.lua")
    local draw = FlameFluidDraw.draw
    function FlameFluidDraw.draw(s, p, frame, options, alpha)
        LAST = { s = s, frame = frame, floor = options.render_floor or 0.035 }
        return draw(s, p, frame, options, alpha)
    end
'''


def background(lua):
    terrain = lua.globals().TERRAIN
    image, rock = Image.new("RGB", (X1 - X0, Y1 - Y0), SKY), Image.new("L", (X1 - X0, Y1 - Y0))
    for y in range(Y0, Y1):
        for x in range(X0, X1):
            if terrain(x, y):
                image.putpixel((x - X0, y - Y0), ROCK)
                rock.putpixel((x - X0, y - Y0), 255)
    size = (image.width * SCALE, image.height * SCALE)
    return image.resize(size, Image.Resampling.NEAREST), rock.resize(size, Image.Resampling.NEAREST)


def panels(lua, back, rock, pixels):
    view = back.copy()
    draw_sprites(view, sprites(lua, layer="body"), -X0 * SCALE, -Y0 * SCALE, scale=SCALE)
    if not FRONT:
        view.paste(back, (0, 0), rock)
    draw_sprites(view, sprites(lua, layer="glow"), -X0 * SCALE, -Y0 * SCALE, scale=SCALE)
    light = Image.new("RGB", view.size)
    ld = ImageDraw.Draw(light)
    for x, y, c in pixels:
        alpha = (c >> 24) / 255
        px, py = (x - X0) * SCALE, (y - Y0) * SCALE
        ld.rectangle((px, py, px + SCALE - 1, py + SCALE - 1),
                     fill=tuple(round(((c >> shift) & 255) * alpha) for shift in (0, 8, 16)))
    view = ImageChops.add(view, light)
    debug = back.copy()
    dd = ImageDraw.Draw(debug)
    last = lua.globals().LAST
    if last is not None:
        s, frame = last.s, last.frame
        model = s.model
        for i, d in s.d.items():
            solid = s.solid[i]
            hot = not solid and d > last.floor
            if not solid and not hot:
                continue
            gx, gy = (i - 1) % model.width + 1, (i - 1) // model.width + 1
            corners = []
            for ax, ay in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)):
                wx, wy, _ = model.world(s, frame, gx + ax, gy + ay)
                corners.append(((wx - X0) * SCALE, (wy - Y0) * SCALE))
            if solid:
                dd.polygon(corners, outline=(120, 120, 135))
            else:
                slot = s.draw_slots[i] if s.draw_slots is not None else None
                dd.polygon(corners, fill=(255, 150, 40) if slot is not None else (255, 0, 255))
    return view, debug


def render(key, ticks, tx=200, ty=-40):
    lua = world_runtime()
    lua.execute(CAVE)
    pixels = []
    lua.globals().GameCreateCosmeticParticle = lambda m, x, y, n, vx, vy, c, *a: pixels.append((x, y, int(c) & 0xFFFFFFFF))
    back, rock = background(lua)
    cast_page(lua, key, tx, ty)
    sheet = Image.new("RGB", (back.width * len(ticks), back.height * 2 + 4), (0, 0, 0))
    tick = 0
    for col, target in enumerate(ticks):
        while tick < target:
            pixels.clear()
            lua.eval("simulate")(1)
            tick += 1
        view, debug = panels(lua, back, rock, pixels)
        sheet.paste(view, (col * back.width, 0))
        sheet.paste(debug, (col * back.width, back.height + 4))
    print(key, "rays/frame:", round(lua.eval("RAYS") / tick))
    errors = list(lua.eval("W.errors").values())
    if errors:
        print("errors:", errors[:3])
    OUT.mkdir(exist_ok=True)
    path = OUT / f"fluid_cave_{key}{'_down' if ty != -40 else ''}{'_front' if FRONT else ''}.png"
    sheet.save(path)
    print(path)


if __name__ == "__main__":
    FRONT = "--front" in sys.argv
    sys.argv = [a for a in sys.argv if a != "--front"]
    keys = sys.argv[1:] or ["ring_of_fire", "flame_shot", "flame_burst"]
    for key in keys:
        render(key, (12, 24) if key != "flame_shot" else (14, 26))
    if not sys.argv[1:]:
        render("flame_shot", (12, 22), tx=150, ty=30)
