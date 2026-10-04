"""Wall Bend and Sand Cage as they are built, from the real Lua pieces and sprites.

python tests/render_earth_builds.py [name] -> tests/output/<name>.png (default earth_builds)
Rows: Wall Bend rising in front of the caster; Sand Cage winding up round an enemy; the Serpent's Bed of Sand
heaping up on the ground.
Offline preview: the pieces are drawn where their static bodies stand; dust and crumbling are not shown.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

from harness import world_runtime, cast_page, freeze_enemies
from fluid_render_capture import texture

OUT = Path(__file__).resolve().parent / "output"
FRAMES = [1, 8, 16, 24, 34, 46, 60]
SCALE, WIDTH, HEIGHT = 6, 420, 480
SOLID = "mods/witch_notebook/files/entities/solid/"


def pieces(lua):
    """the solid pieces standing now: [(image path, x, y)]"""
    out = []
    for entity in lua.eval("W.entities").values():
        if entity.alive and entity.file and entity.file.startswith(SOLID):
            kind = entity.file[len(SOLID):-4]
            out.append(("mods/witch_notebook/files/gfx/solid/" + kind + ".png", entity.x, entity.y))
    return out


def paste(bg, path, x, y, ox, oy):
    image = texture(path)
    big = image.resize((image.width * SCALE, image.height * SCALE), Image.Resampling.NEAREST)
    bg.paste(big, (round((x - image.width / 2) * SCALE + ox), round((y - image.height / 2) * SCALE + oy)), big)


def row(key):
    lua = world_runtime()
    lua.execute("GROUND = 10")
    sprites = []
    lua.globals().GameCreateSpriteForXFrames = lambda path, x, y, *rest: sprites.append((path, x, y))
    if key == "serpents_bed":
        lua.execute("for _, id in ipairs(ENEMIES) do EntityKill(id) end")
        cast_page(lua, key, 100, -10)
        cx, cy, body = 100, -8, None
    elif key == "sand_cage":
        freeze_enemies(lua, ((120, -6), (400, -40), (500, -40)))
        cast_page(lua, key, 120, -6)
        cx, cy, body = 120, -10, (120, -6)
    else:
        lua.execute('''
            EntitySetTransform(PLAYER, 0, 6)
            EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent"))
            for _, id in ipairs(ENEMIES) do EntityKill(id) end
        ''')
        lua.globals().TEST_KEY = key
        lua.execute('''
            local data = seal_page_data({named = TEST_KEY, precision = 1, stability = 1})
            cast_spell(PLAYER, parse_spell_data(data), 0, 2, 1, 0, 200, 2, W.frame, nil)
        ''')
        cx, cy, body = 10, -22, (0, 2)
    ox, oy = WIDTH / 2 - cx * SCALE, HEIGHT / 2 - cy * SCALE
    panels, last = [], 0
    for frame in FRAMES:
        for _ in range(frame - last):
            sprites.clear()
            lua.execute("simulate(1)")
        last = frame
        bg = Image.new("RGB", (WIDTH, HEIGHT), (17, 20, 29))
        draw = ImageDraw.Draw(bg)
        draw.rectangle((0, 10 * SCALE + oy, WIDTH, HEIGHT), fill=(58, 52, 56))
        # a stand-in for the caster or the caged enemy: 8 x 18
        if body:
            draw.rectangle(((body[0] - 4) * SCALE + ox, (body[1] - 10) * SCALE + oy, (body[0] + 4) * SCALE + ox, (body[1] + 8) * SCALE + oy),
                           fill=(74, 58, 92))
        solid = pieces(lua)
        for path, x, y in solid:
            paste(bg, path, x, y, ox, oy)
        for path, x, y in sprites:
            paste(bg, path, x, y, ox, oy)
        # the cage's bands: a sprite of the effect's own, drawn in front of the creature
        for entity in lua.eval("W.entities").values():
            if not entity.alive:
                continue
            for cid in entity.comps.values():
                comp = lua.eval("W.comps")[cid]
                values = comp["values"]
                if comp.type == "SpriteComponent" and "witch_cage_bands" in (values._tags or "") and values.visible:
                    image = texture(values.image_file)
                    paste(bg, values.image_file, entity.x - values.offset_x + image.width / 2,
                          entity.y - values.offset_y + image.height / 2, ox, oy)
        draw.text((6, 4), f"{key} frame {frame}, {len(solid)} pieces", fill=(160, 165, 180))
        panels.append(bg)
    return panels


if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "earth_builds"
    OUT.mkdir(exist_ok=True)
    rows = [row("wall_bend"), row("sand_cage"), row("serpents_bed")]
    sheet = Image.new("RGB", (WIDTH * len(FRAMES), HEIGHT * len(rows)))
    for y, panels in enumerate(rows):
        for x, panel in enumerate(panels):
            sheet.paste(panel, (x * WIDTH, y * HEIGHT))
    sheet.save(OUT / (name + ".png"))
    print(OUT / (name + ".png"))
