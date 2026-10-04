"""Preview real Lua particle calls; output is approximate, not a Noita screenshot."""
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

from harness import world_runtime, cast_page
from test_light_spells import still_player, item, hold_book, KEYS
import wiki_spells as Wiki

OUT = Path(__file__).resolve().parent / "output"
FONT = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 16)


def render(key):
    lua = world_runtime()
    still_player(lua, 0, -20)
    lua.execute("for _, id in ipairs(ENEMIES) do EntityKill(id) end")
    tick, particles = [0], []

    def particle(material, x, y, count, vx, vy, packed, lmin, lmax, force, front, collide, randomize, gx, gy):
        packed = int(packed) & 0xFFFFFFFF
        rgb = (packed & 255, (packed >> 8) & 255, (packed >> 16) & 255)
        particles.append((tick[0], x, y, vx, vy, rgb, (packed >> 24) / 255, max(lmin, 1 / 60), gy))

    lua.globals().GameCreateCosmeticParticle = particle
    if key == "glowstone_path":
        lua.execute("GROUND = 10")
    if key == "light_tracer":
        held_book = hold_book(lua)
        item(lua, "first", 50, -40)
        item(lua, "second", 160, -75)
        item(lua, "third", 230, -5)
        cast_page(lua, key, 50, -40)
    elif key in ("light_beam", "ancient_light_beacon"):
        cast_page(lua, key, 200, -120)
    else:
        cast_page(lua, key, 160)
    entry = lua.eval("GRIMOIRE_BY_KEY")[key]
    book = Image.open(Path(Wiki.MOD) / "files/gfx/spellbook.png").convert("RGBA")
    frames = []
    for frame in range(120):
        tick[0] = frame
        if key == "light_tracer" and frame in (30, 60):
            cast_page(lua, key, *( (160, -75) if frame == 30 else (230, -5) ))
        if key == "light_tracer" and frame in (90, 105):
            inv = lua.eval("EntityGetFirstComponent")(lua.eval("PLAYER"), "Inventory2Component")
            lua.eval("ComponentSetValue2")(inv, "mActiveItem", 0 if frame == 90 else held_book)
        if key == "glowstone_path" and frame >= 15:
            lua.eval("EntitySetTransform")(lua.eval("PLAYER"), min(130, (frame - 15) * 1.4), 7)
        lua.execute("simulate(1)")
        bg = Image.new("RGB", (360, 230), (17, 20, 29))
        draw = ImageDraw.Draw(bg)
        scale = 0.85 if key == "ancient_light_beacon" else 1
        ox, oy = 65, 155
        draw.line((0, oy + 10 * scale, 360, oy + 10 * scale), fill=(43, 39, 44))
        bg.paste(book, (ox - 12, round(oy - 40 * scale) - book.height // 2), book)
        if key == "light_tracer":
            for x, y in ((50, -40), (160, -75), (230, -5)):
                draw.polygon([(ox+x-3,oy+y), (ox+x,oy+y-5), (ox+x+3,oy+y), (ox+x,oy+y+3)], fill=(90, 100, 125))
        light, glow = Image.new("RGB", bg.size), Image.new("RGB", bg.size)
        ld, gd = ImageDraw.Draw(light), ImageDraw.Draw(glow)
        keep = []
        for born,x,y,vx,vy,rgb,alpha,life,gravity in particles:
            age = (frame - born) / 60
            if age >= life:
                continue
            keep.append((born,x,y,vx,vy,rgb,alpha,life,gravity))
            fade = (1 - age / life) * alpha
            px = round((x + vx * age) * scale + ox)
            py = round((y + vy * age + gravity * age * age / 2) * scale + oy)
            if 0 <= px < bg.width and 0 <= py < bg.height:
                c = tuple(round(v * fade) for v in rgb)
                ld.point((px, py), fill=c)
                gd.ellipse((px-2,py-2,px+2,py+2), fill=tuple(round(v * 0.5) for v in c))
        particles = keep
        bg = ImageChops.add(ImageChops.add(bg, glow.filter(ImageFilter.GaussianBlur(2))), light)
        bg = bg.resize((720, 460), Image.Resampling.NEAREST)
        draw = ImageDraw.Draw(bg)
        draw.text((16,12), entry["name"], fill=(235,215,180), font=FONT)
        caption = "Offline particle preview"
        if key == "ancient_light_beacon":
            caption += " - 85% scale, interpreted effect"
        draw.text((16,435), caption, fill=(125,127,140), font=FONT)
        frames.append(bg)
    frames[0].save(OUT / (key + ".gif"), save_all=True, append_images=frames[1:],
                   duration=[17] * 119 + [700], loop=0)
    return frames[110] if key == "light_tracer" else frames[90]


def seal_comparison(key, reference_image):
    lua = world_runtime()
    reference = Image.open(Path(Wiki.WIKI_IMAGES) / reference_image).convert("RGB").resize((480,480))
    page = Image.new("RGB", (480,480), "white")
    draw = ImageDraw.Draw(page)
    for stroke in Wiki.page(lua, lua.eval("GRIMOIRE_BY_KEY")[key]):
        pts = [((x-90)*218.4/70+240, (y-90)*218.4/70+240) for x,y in stroke]
        if len(pts) > 1:
            draw.line(pts, fill=(119,0,0), width=5, joint="curve")
        elif pts:
            x,y = pts[0]
            draw.ellipse((x-2,y-2,x+2,y+2), fill=(119,0,0))
    sheet = Image.new("RGB", (980,520), (246,241,232))
    sheet.paste(reference, (5,30))
    sheet.paste(page, (495,30))
    draw = ImageDraw.Draw(sheet)
    draw.text((15,6), "Wiki redraw", fill=(65,44,32), font=FONT)
    draw.text((505,6), "Corrected book page", fill=(65,44,32), font=FONT)
    sheet.save(OUT / (key + "_seal.png"))


def flower_seal():
    seal_comparison("flowers_of_light", "Flowers_of_Light_Redraw.png")


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    sheet = Image.new("RGB", (1440,2300), (17,20,29))
    for i,key in enumerate(KEYS):
        sheet.paste(render(key), ((i % 2)*720, (i // 2)*460))
    sheet.save(OUT / "light_spells.png")
    flower_seal()
    seal_comparison("ancient_light_beacon", "Ancient_Light_Beacon_Redraw.png")
    print(OUT / "light_spells.png")
