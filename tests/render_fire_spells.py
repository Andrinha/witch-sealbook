"""Approximate previews of the real Lua particle calls for the fire spell audit.

python tests/render_fire_spells.py -> tests/output/fire_spells.png and individual GIFs.
These are offline cosmetic particle previews, not game screenshots.
Flame Shot and held Spiraling Flame get labelled placeholders.
render_flame_shot.py previews the actual Flame Shot fluid density separately.
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

from harness import world_runtime, cast_page
from fluid_render_capture import Sprite, sprites as visible_sprites, draw_sprites

HERE = Path(__file__).resolve().parent
OUT = HERE / "output"
FONT = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 16)
SPELLS = [("pyreball", "Pyreball (2D fluid)", 40), ("flame_shot", "Flame Shot", 25),
          ("flame_burst", "Flame Burst", 51), ("ring_of_fire", "Ring of Fire", 19),
          ("phantasmal_fireball", "Phantasmal Fireball", 30), ("spiraling_flame", "Spiraling Flame", 25),
          ("forbidden_flames", "Forbidden Flames (2D fluid)", 40)]


def render(key, title, snapshot_frame, field_source=None, draw_source=None, sky=(17, 20, 29), bloom=True):
    if key in ("spiraling_flame", "flame_shot"):
        preview = Image.new("RGB", (720, 440), (17, 20, 29))
        draw = ImageDraw.Draw(preview)
        draw.text((16, 12), title, fill=(235, 215, 180), font=FONT)
        text = "Lua fluid + native Noita fire" if key == "flame_shot" else "Native Noita fire simulation"
        draw.text((90, 175), text, fill=(235, 215, 180), font=FONT)
        draw.text((90, 205), "Check the flame in game.", fill=(160, 165, 180), font=FONT)
        draw.text((16, 415), "Offline renderer does not simulate material cells", fill=(125, 127, 140), font=FONT)
        preview.save(OUT / (key + ".gif"))
        return preview
    lua = world_runtime()
    if field_source is not None:
        lua.execute('dofile_once("mods/witch_notebook/files/effects/flame_fields.lua")')
        lua.execute(field_source)
    if draw_source is not None:
        lua.execute('dofile_once("mods/witch_notebook/files/effects/fluid_draw.lua")')
        lua.execute(draw_source)
    lua.execute('''
        EntitySetTransform(PLAYER, 0, -20)
        EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent"))
        for _, id in ipairs(ENEMIES) do EntityKill(id) end
    ''')
    particles, sprites, tick = [], [], [0]

    def particle(material, x, y, count, vx, vy, packed, lmin, lmax, force, front, collide, randomize, gx, gy):
        packed = int(packed) & 0xFFFFFFFF
        rgb = (packed & 255, (packed >> 8) & 255, (packed >> 16) & 255)
        particles.append((tick[0], x, y, vx, vy, rgb, (packed >> 24) / 255, max(lmin, 1 / 60), gy))

    lua.globals().GameCreateCosmeticParticle = particle

    def sprite(path, x, y, centered, ox, oy, lifetime, emissive):
        sprites.append((path, x, y))

    lua.globals().GameCreateSpriteForXFrames = sprite
    cast_page(lua, key, tx=210)
    book = Image.open(HERE.parent / "files/gfx/spellbook.png").convert("RGBA")
    frames, snapshot = [], None
    for frame in range(95):
        tick[0] = frame
        sprites.clear()
        lua.execute("simulate(1)")
        # Leave room for large, advected rings instead of cropping their curls.
        width, height = (480, 280) if key in ("flame_burst", "ring_of_fire") else (360, 220)
        offset_y = height // 2 + 40
        bg = Image.new("RGB", (width, height), sky)
        d = ImageDraw.Draw(bg)
        d.line((0, height - 15, width, height - 15), fill=(43, 39, 44))
        offset_x = 50 if key == "flame_burst" else 160 if key == "ring_of_fire" else 80
        bg.paste(book, (offset_x - 12, height // 2 - book.height // 2), book)
        light, glow = Image.new("RGB", bg.size), Image.new("RGB", bg.size)
        ld, gd = ImageDraw.Draw(light), ImageDraw.Draw(glow)
        keep = []
        for born, x, y, vx, vy, rgb, alpha, life, gravity in particles:
            age = (frame - born) / 60
            if age >= life:
                continue
            keep.append((born, x, y, vx, vy, rgb, alpha, life, gravity))
            fade = (1 - age / life) * alpha
            px, py = round(x + vx * age + offset_x), round(y + vy * age + gravity * age * age / 2 + offset_y)
            if 0 <= px < bg.width and 0 <= py < bg.height:
                c = tuple(round(v * fade) for v in rgb)
                ld.point((px, py), fill=c)
                gd.ellipse((px - 2, py - 2, px + 2, py + 2), fill=tuple(round(v * 0.5) for v in c))
        particles = keep
        samples = [Sprite(path, x, y) for path, x, y in sprites] + visible_sprites(lua, layer=None)
        draw_sprites(bg, samples, offset_x, offset_y)
        if bloom:
            draw_sprites(glow, samples, offset_x, offset_y)
            bg = ImageChops.add(bg, glow.filter(ImageFilter.GaussianBlur(2)))
        bg = ImageChops.add(bg, light)
        bg = bg.resize((720, 440), Image.Resampling.NEAREST)
        d = ImageDraw.Draw(bg)
        d.text((16, 12), title, fill=(235, 215, 180), font=FONT)
        d.text((16, 415), "Offline preview; " + ("glow approximated" if bloom else "no added bloom"), fill=(125, 127, 140), font=FONT)
        if frame == snapshot_frame:
            snapshot = bg.copy()
        frames.append(bg)
    frames[0].save(OUT / (key + ".gif"), save_all=True, append_images=frames[1:],
                   duration=[17] * 94 + [800], loop=0)
    return snapshot


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    sheet = Image.new("RGB", (1440, 440 * ((len(SPELLS)+1)//2)), (17, 20, 29))
    for i, (key, title, snapshot_frame) in enumerate(SPELLS):
        snapshot = render(key, title, snapshot_frame)
        sheet.paste(snapshot, ((i % 2) * 720, (i // 2) * 440))
    sheet.save(OUT / "fire_spells.png")
    print(OUT / "fire_spells.png")
