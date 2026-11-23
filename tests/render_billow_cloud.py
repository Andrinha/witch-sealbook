"""The Billow's cloud as it stands and gathers, from the real Lua pieces and particles.

python tests/render_billow_cloud.py [name] -> tests/output/<name>.png (default billow_cloud)
Rows: the lone cloud gathering; Expansion's heap; Collection growing a billow at a time; the tempers - a cloud of
water raining, of fire shedding embers, of crystal snowing, of lightning striking at the beast beneath.
Offline preview: the solid pieces where their static bodies stand; the particles the effect sheds (its streams,
rain, embers, snow, bolts) as short streaks of the last few frames.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

from harness import world_runtime, freeze_enemies
from fluid_render_capture import texture
from render_earth_builds import paste, pieces

OUT = Path(__file__).resolve().parent / "output"
SCALE, WIDTH, HEIGHT = 6, 420, 480

# (label, extra spell data, frames to show, a beast under the cloud)
ROWS = [
    ("billow", "", [1, 8, 20, 40, 60, 90], False),
    ("billow, two Expansions", ";b=grow:2", [1, 20, 40, 60, 80], False),
    ("billow, two Collections", ";b=gather:2", [1, 30, 60, 260, 500, 740, 980, 1220], False),
    ("billow of water", ";element=water", [1, 40, 80, 120, 160, 200], False),
    ("billow of fire", ";element=fire", [1, 40, 80, 120, 160, 200], False),
    ("billow of crystal", ";element=crystal", [1, 40, 80, 120, 160, 200], False),
    ("billow of lightning", ";element=thunder", [1, 40, 80, 120, 160, 200, 240], True),
]

# what the world is asked for, kept so the sheet can be drawn again: particles and pours, with their frames
TRACE = r'''
SPARKS, POURS = {}, {}
local cosmetic = GameCreateCosmeticParticle
function GameCreateCosmeticParticle(m, x, y, n, vx, vy, color, lmin, lmax, force, front, collide, randomize, gx, gy)
    SPARKS[#SPARKS + 1] = { frame = W.frame, x = x, y = y, vx = vx, vy = vy, color = color, life = lmax }
    return cosmetic(m, x, y, n, vx, vy, color, lmin, lmax, force, front, collide, randomize, gx, gy)
end
local pour = GameCreateParticle
function GameCreateParticle(m, x, y, n, vx, vy, a, b, c)
    POURS[#POURS + 1] = { frame = W.frame, m = m, x = x, y = y }
    return pour(m, x, y, n, vx, vy, a, b, c)
end
'''

POUR_COLORS = {"water": (90, 150, 255), "snow": (235, 245, 255)}


def abgr(color):
    """a color_abgr_merge number -> (r, g, b), alpha"""
    return (color & 255, (color >> 8) & 255, (color >> 16) & 255), ((color >> 24) & 255) / 255


def streaks(lua, draw, frame, ox, oy):
    """the particles shed in the last few frames, drawn as short streaks where they have got to"""
    window = 8
    for s in lua.eval("SPARKS").values():
        age = frame - s["frame"]
        if not 0 <= age <= window:
            continue
        (r, g, b), alpha = abgr(s["color"])
        t, life = age / 60, min(0.3, s["life"] or 0.3)
        x, y, vx, vy = s["x"], s["y"], s["vx"], s["vy"]
        draw.line((((x + vx * t) * SCALE + ox, (y + vy * t) * SCALE + oy),
                   ((x + vx * (t + life)) * SCALE + ox, (y + vy * (t + life)) * SCALE + oy)),
                  fill=(r, g, b), width=2)
        del alpha
    for p in lua.eval("POURS").values():
        age = frame - p["frame"]
        if not 0 <= age <= window or p["m"] not in POUR_COLORS:
            continue
        vy = {"water": 30, "snow": 10}[p["m"]]
        t = age / 60
        x, y = p["x"], p["y"]
        draw.line(((x * SCALE + ox, (y + vy * t) * SCALE + oy), (x * SCALE + ox, (y + vy * (t + 0.3)) * SCALE + oy)),
                  fill=POUR_COLORS[p["m"]], width=2)


def row(label, extra, frames, beast):
    lua = world_runtime()
    lua.execute("GROUND = 10000")
    lua.execute(TRACE)
    if beast:
        freeze_enemies(lua, ((120, -16), (400, -40), (500, -40)))
    else:
        lua.execute("for _, id in ipairs(ENEMIES) do EntityKill(id) end")
    lua.globals().TEST_EXTRA = extra
    lua.execute('''
        local data = "manifest=cloud;precision=1;stability=1" .. TEST_EXTRA
        cast_spell(PLAYER, parse_spell_data(data), 0, -40, 1, 0, 120, -40, W.frame, nil)
    ''')
    cx, cy = 120, -35
    ox, oy = WIDTH / 2 - cx * SCALE, HEIGHT / 2 - cy * SCALE
    panels, last = [], 0
    for frame in frames:
        for _ in range(frame - last):
            lua.execute("simulate(1)")
        last = frame
        now = lua.eval("W.frame")
        bg = Image.new("RGB", (WIDTH, HEIGHT), (17, 20, 29))
        draw = ImageDraw.Draw(bg)
        # the beast beneath the storm cloud, 8 x 18, for the bolt to strike at
        if beast:
            draw.rectangle(((120 - 4) * SCALE + ox, (-16 - 10) * SCALE + oy, (120 + 4) * SCALE + ox, (-16 + 8) * SCALE + oy),
                           fill=(74, 58, 92))
        for path, x, y in pieces(lua):
            paste(bg, path, x, y, ox, oy)
        streaks(lua, draw, now, ox, oy)
        draw.text((6, 4), f"{label}, frame {frame}", fill=(160, 165, 180))
        panels.append(bg)
    return panels


if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "billow_cloud"
    OUT.mkdir(exist_ok=True)
    rows = [row(*r) for r in ROWS]
    columns = max(len(r) for r in rows)
    sheet = Image.new("RGB", (WIDTH * columns, HEIGHT * len(rows)))
    for y, panels in enumerate(rows):
        for x, panel in enumerate(panels):
            sheet.paste(panel, (x * WIDTH, y * HEIGHT))
    sheet.save(OUT / (name + ".png"))
    print(OUT / (name + ".png"))
