"""Offline previews from actual Lua particles; these are not Noita screenshots."""
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

from harness import world_runtime
from test_decorative_spells import cast_shape, SHAPES
import make_grimoire as Generator

OUT = Path(__file__).resolve().parent / "output"
FONT = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 18)
REFERENCE = Path(__file__).resolve().parents[2] / "reference/wha-wiki/images"


def render(shape, element):
    lua = world_runtime()
    lua.execute('''
        EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent"))
        for _, id in ipairs(ENEMIES) do EntityKill(id) end
        GROUND=10
    ''')
    particles, tick = [], [0]

    def particle(material, x, y, count, vx, vy, packed, lmin, lmax, *extra):
        packed = int(packed) & 0xFFFFFFFF
        rgb = (packed & 255, (packed >> 8) & 255, (packed >> 16) & 255)
        particles.append((tick[0], x, y, vx, vy, rgb, (packed >> 24) / 255, max(lmin, 1 / 60)))

    lua.globals().GameCreateCosmeticParticle = particle
    e = cast_shape(lua, shape, element)[1]
    frames = []
    for frame in range(96):
        tick[0] = frame
        lua.execute("simulate(1)")
        x, y, *_ = lua.eval("EntityGetTransform")(e)
        bg = Image.new("RGB", (640, 360), (17, 20, 29))
        draw = ImageDraw.Draw(bg)
        scale, ox, oy = 3, 320 - x * 3, 215 - y * 3
        if shape in ("horse", "scalewolf", "torchstag", "liongoat", "frillram"):
            draw.line((0, 218, 640, 218), fill=(58, 50, 48), width=2)
        light, glow = Image.new("RGB", bg.size), Image.new("RGB", bg.size)
        ld, gd = ImageDraw.Draw(light), ImageDraw.Draw(glow)
        keep = []
        for born, px, py, vx, vy, rgb, alpha, life in particles:
            age = (frame - born) / 60
            if age >= life:
                continue
            keep.append((born, px, py, vx, vy, rgb, alpha, life))
            fade = (1 - age / life) * alpha
            sx, sy = round((px + vx * age) * scale + ox), round((py + vy * age) * scale + oy)
            c = tuple(round(v * fade) for v in rgb)
            ld.rectangle((sx, sy, sx + 2, sy + 2), fill=c)
            gd.ellipse((sx-4, sy-4, sx+4, sy+4), fill=tuple(round(v * .35) for v in c))
        particles = keep
        bg = ImageChops.add(ImageChops.add(bg, glow.filter(ImageFilter.GaussianBlur(3))), light)
        draw = ImageDraw.Draw(bg)
        draw.text((16, 12), f"{shape.title()} / {element}", fill=(235, 215, 180), font=FONT)
        draw.text((16, 330), "Offline Lua particle preview - camera follows the sculpture", fill=(125, 127, 140), font=FONT)
        frames.append(bg)
    frames[0].save(OUT / f"decorative_{shape}_{element}.gif", save_all=True,
                   append_images=frames[1:], duration=33, loop=0)
    return frames[60]


def reference_sheet():
    lua = Generator.lua_runtime()
    sheet = Image.new("RGB", (960, 1080), (246, 241, 232))
    names = {"scalewolf": "Scalewolf_Sign.png", "torchstag": "Torchstag_Sign.png",
             "liongoat": "Liongoat_Sigil_Redraw.png", "frillram": "Frillram_Sigil.png"}
    for i, (key, name) in enumerate(names.items()):
        x, y = (i % 2) * 480, (i // 2) * 540
        # Keep the reference proportions, as well as the rendered template's.
        source = Image.open(REFERENCE / name).convert("RGB")
        source.thumbnail((220, 440))
        sheet.paste(Image.new("RGB", (230, 460), "white"), (x, y + 40))
        sheet.paste(source, (x + (230-source.width)//2, y + 40 + (460-source.height)//2))
        panel = Image.new("RGB", (230, 460), "white")
        draw = ImageDraw.Draw(panel)
        strokes = Generator.templates(lua)[("sigil", key)]
        for stroke in Generator.place(strokes, 115, 230, 200, 0):
            draw.line(stroke, fill=(119, 0, 0), width=4, joint="curve")
        sheet.paste(panel, (x + 240, y + 40))
        draw = ImageDraw.Draw(sheet)
        draw.text((x + 10, y + 8), key.title() + " - wiki / book", fill=(65, 44, 32), font=FONT)
    sheet.save(OUT / "decorative_sigils.png")


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    sheet = Image.new("RGB", (1280, 1800), (17, 20, 29))
    for i, shape in enumerate(SHAPES):
        sheet.paste(render(shape, "fire" if shape == "torchstag" else "light"), ((i % 2) * 640, (i // 2) * 360))
    sheet.save(OUT / "decorative_spells.png")
    reference_sheet()
    print(OUT / "decorative_spells.png")
