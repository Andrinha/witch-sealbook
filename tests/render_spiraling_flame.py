"""Render actual flame.lua particle calls offline, plus the wiki/page comparison.

python tests/render_spiraling_flame.py -> tests/output/spiraling_flame.{gif,png}
This approximates the finite scripted column only. The held native fire stream
must be checked in Noita; this is not an in-game screenshot.
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

from harness import world_runtime
from test_spiraling_flame import cast
import wiki_spells as Wiki

HERE = Path(__file__).resolve().parent
OUT = HERE / "output"
FONT = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 16)


def seal_comparison(lua):
    reference = Image.open(HERE.parent.parent / "reference/wha-wiki/images/Spiraling_Flame_Redraw.png").convert("RGB")
    page = Image.new("RGB", (450, 450), "white")
    draw = ImageDraw.Draw(page)
    entry = lua.eval("GRIMOIRE_BY_KEY.spiraling_flame")
    for stroke in Wiki.page(lua, entry):
        pts = [((x - 90) * 209 / 70 + 225, (y - 90) * 209 / 70 + 225) for x, y in stroke]
        if len(pts) > 1:
            draw.line(pts, fill=(119, 0, 0), width=6, joint="curve")
    sheet = Image.new("RGB", (920, 488), (246, 241, 232))
    sheet.paste(reference, (5, 30))
    sheet.paste(page, (465, 30))
    draw = ImageDraw.Draw(sheet)
    draw.text((15, 6), "Wiki redraw", fill=(65, 44, 32), font=FONT)
    draw.text((475, 6), "Book page", fill=(65, 44, 32), font=FONT)
    sheet.save(OUT / "spiraling_flame_seal.png")


def animation(lua):
    particles = []
    tick = [0]

    def particle(material, x, y, count, vx, vy, packed, lmin, lmax, force, front, collide, randomize, gx, gy):
        packed = int(packed) & 0xFFFFFFFF
        rgb = (packed & 255, (packed >> 8) & 255, (packed >> 16) & 255)
        particles.append((tick[0], x, y, vx, vy, rgb, (packed >> 24) / 255, max(lmin, 1 / 60), gy))

    lua.globals().GameCreateCosmeticParticle = particle
    lua.execute("for _, id in ipairs(ENEMIES) do EntityKill(id) end")
    cast(lua, tx=275, ty=-40)
    book = Image.open(HERE.parent / "files/gfx/spellbook.png").convert("RGBA")
    frames = []
    snapshot = None
    for frame in range(100):
        tick[0] = frame
        lua.execute("simulate(1)")
        bg = Image.new("RGB", (360, 120), (17, 20, 29))
        d = ImageDraw.Draw(bg)
        d.line((0, 100, 360, 100), fill=(43, 39, 44))
        for x in range(0, 360, 12):
            d.line((x, 103, x + 7, 103), fill=(33, 29, 37))
        # Existing book sprite only provides scale and a visible source.
        bg.paste(book, (25, 73 - book.height // 2), book)
        light = Image.new("RGB", bg.size)
        glow = Image.new("RGB", bg.size)
        ld, gd = ImageDraw.Draw(light), ImageDraw.Draw(glow)
        keep = []
        for born, x, y, vx, vy, rgb, alpha, life, gravity in particles:
            age = (frame - born) / 60
            if age >= life:
                continue
            keep.append((born, x, y, vx, vy, rgb, alpha, life, gravity))
            fade = (1 - age / life) * alpha
            px, py = round(x + vx * age + 40), round(y + vy * age + gravity * age * age / 2 + 112)
            if 0 <= px < bg.width and 0 <= py < bg.height:
                c = tuple(round(v * fade) for v in rgb)
                ld.point((px, py), fill=c)
                gd.ellipse((px - 2, py - 2, px + 2, py + 2), fill=tuple(round(v * 0.5) for v in c))
        particles = keep
        bg = ImageChops.add(bg, glow.filter(ImageFilter.GaussianBlur(2)))
        bg = ImageChops.add(bg, light)
        bg = bg.resize((1080, 360), Image.Resampling.NEAREST)
        d = ImageDraw.Draw(bg)
        d.text((16, 12), "Spiraling Flame - scripted cast preview (held fire: check in game)", fill=(210, 199, 177), font=FONT)
        if frame == 25:
            snapshot = bg.copy()
        frames.append(bg)
    frames[0].save(OUT / "spiraling_flame.gif", save_all=True, append_images=frames[1:], duration=[17] * 95 + [800] * 5, loop=0)
    snapshot.save(OUT / "spiraling_flame.png")


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    lua = world_runtime()
    seal_comparison(lua)
    animation(lua)
    print(OUT)
