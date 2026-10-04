"""Preview the actual Lua fluid density and velocity, not Noita's native render.

python tests/render_flame_shot.py -> tests/output/flame_shot_fluid.{png,gif}
Native fire appearance/material interactions still require an in-game check.
"""
from pathlib import Path
import math

from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

from harness import world_runtime, cast_page, wall
from fluid_render_capture import sprites as visible_sprites, draw_sprites

OUT = Path(__file__).resolve().parent / "output"
FONT = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 16)


def frame(lua, effect, tick, label, zoom=False, trails=None):
    image = Image.new("RGB", (720, 280), (16, 19, 26))
    draw = ImageDraw.Draw(image)
    draw.text((14, 10), label, font=FONT, fill=(240, 215, 180))
    draw.text((14, 253), "Lua gas + source paths; native fire appearance: check in Noita", font=FONT, fill=(130, 140, 155))
    if not lua.eval("EntityGetIsAlive")(effect):
        return image
    state = lua.globals().FlameShot.states[effect]
    if state is None:
        return image
    params = lua.eval("effect_params")(effect)
    heat = Image.new("RGB", image.size)
    hd = ImageDraw.Draw(heat)
    scale = 4 if zoom else 2
    origin = 340 - params["head"] * scale if zoom else 45
    width, height = lua.globals().FlameFluid.width, lua.globals().FlameFluid.height
    for i, density in state.d.items():
        if density <= 0.01 or state.solid[i]:
            continue
        gx, gy = (i - 1) % width + 1, (i - 1) // width + 1
        x, y, _ = lua.globals().FlameFluid.world(state, params, gx, gy)
        x, y = origin + x * scale, 140 + (y + 40) * scale
        radius = state.cell * scale * 0.65
        alpha = min(1, density * 1.4)
        hot = min(1, density / 1.5)
        rgb = tuple(round(v * alpha) for v in (255, 65 + hot * 190, 12 + hot * 150))
        hd.ellipse((x-radius, y-radius, x+radius, y+radius), fill=rgb)
    image = ImageChops.add(image, heat.filter(ImageFilter.GaussianBlur(2)))
    draw = ImageDraw.Draw(image)
    if trails is not None:
        for child in lua.eval("EntityGetAllChildren")(effect).values():
            if not lua.eval("EntityHasTag")(child, "witch_flame_shot_fire"):
                continue
            trace = lua.eval("effect_params")(child)
            point = (trace["fluid_x"], trace["fluid_y"])
            history = trails.setdefault(child, [])
            if history and math.dist(point, history[-1]) > 6:
                history.clear()  # Re-seeding starts a new path, not a connecting line.
            if not history or history[-1] != point:
                history.append(point)
            del history[:-10]
            if len(history) < 2:
                continue
            path = []
            for gx, gy in history:
                x, y, _ = lua.globals().FlameFluid.world(state, params, gx, gy)
                path.append((origin+x*scale, 140+(y+40)*scale))
            draw.line(path, fill=(190, 205, 170), width=1)
    for gy in range(3, height, 2):
        for gx in range(2, width, 2):
            i = (gy-1)*width+gx
            if state.solid[i] or state.d[i] < 0.045:
                continue
            x, y, _ = lua.globals().FlameFluid.world(state, params, gx, gy)
            x, y = origin+x*scale, 140+(y+40)*scale
            vx, vy = state.u[i], state.v[i]
            length = math.hypot(vx, vy) + 1e-6
            dx, dy = 8*vx/length, 8*vy/length
            draw.line((x, y, x+dx, y+dy), fill=(130, 210, 230), width=1)
            draw.line((x+dx, y+dy, x+dx-dx*.3-dy*.2, y+dy-dy*.3+dx*.2), fill=(130, 210, 230))
    return image


def render():
    OUT.mkdir(exist_ok=True)
    worlds = []
    for label, barrier in (("Flame Shot: fluid vortices (4x, camera follows packet)", None), ("Flame Shot: wall blocks hot gas", 145)):
        lua = world_runtime()
        lua.execute("for _, id in ipairs(ENEMIES) do EntityKill(id) end")
        if barrier is not None:
            wall(lua, barrier)
        worlds.append((lua, cast_page(lua, "flame_shot", 285, -40), label, barrier, {}))
    pixels, clock = [], [0]
    def particle(material, x, y, count, vx, vy, color, lmin, lmax, *args):
        color = int(color) & 0xFFFFFFFF
        rgb = (color & 255, (color >> 8) & 255, (color >> 16) & 255)
        pixels.append((clock[0], x, y, vx, vy, rgb, (color >> 24) / 255, (lmin+lmax)/2))
    worlds[0][0].globals().GameCreateCosmeticParticle = particle

    frames = []
    for tick in range(156):
        clock[0] = tick
        panel = Image.new("RGB", (720, 840))
        for row, (lua, effect, label, barrier, trails) in enumerate(worlds):
            lua.execute("simulate(1)")
            view = frame(lua, effect, tick, label, zoom=row == 0, trails=trails)
            if barrier is not None:
                ImageDraw.Draw(view).rectangle((45+barrier*2, 50, 51+barrier*2, 242), fill=(80, 88, 100))
            panel.paste(view, (0, (0 if row == 0 else 2)*280))
        cosmetic = Image.new("RGB", (720, 280), (16, 19, 26))
        heat = Image.new("RGB", cosmetic.size)
        hd = ImageDraw.Draw(heat)
        lua, effect = worlds[0][:2]
        p = lua.eval("effect_params")(effect)
        origin = 340 - (p["head"] or 0)*4
        pixels[:] = [pixel for pixel in pixels if (tick-pixel[0])/60 < pixel[-1]]
        for born, x, y, vx, vy, rgb, alpha, life in pixels:
            age = (tick-born)/60
            px, py = origin+(x+vx*age)*4, 140+(y+vy*age+40)*4
            color = tuple(round(v*alpha*(1-age/life)) for v in rgb)
            hd.rectangle((px-1, py-1, px+2, py+2), fill=color)
        cosmetic = ImageChops.add(cosmetic, heat)
        samples = visible_sprites(lua, layer=None)
        draw_sprites(cosmetic, samples, origin, 300, scale=4)
        draw_sprites(heat, samples, origin, 300, scale=4)
        cosmetic = ImageChops.add(cosmetic, heat.filter(ImageFilter.GaussianBlur(3)))
        draw = ImageDraw.Draw(cosmetic)
        draw.text((14, 10), "Actual additive gas sprites (4x); glow approximated", font=FONT, fill=(240, 215, 180))
        draw.text((14, 253), "Emissive gas sprites; native fire omitted", font=FONT, fill=(130, 140, 155))
        panel.paste(cosmetic, (0, 280))
        frames.append(panel)
    frames[23].save(OUT / "flame_shot_fluid.png")
    contact = Image.new("RGB", (720 * 3, 560 * 2))
    for slot, tick in enumerate((5, 11, 17, 23, 35, 47)):
        view = frames[tick].crop((0, 0, 720, 560))
        ImageDraw.Draw(view).text((14, 35), f"{(tick+1)/60:.2f} s", font=FONT, fill=(210, 220, 235))
        contact.paste(view, ((slot % 3) * 720, (slot // 3) * 560))
    contact.save(OUT / "flame_shot_vortices.png")
    frames[0].save(OUT / "flame_shot_fluid.gif", save_all=True, append_images=frames[1:],
                   duration=[17]*155+[800], loop=0)
    print(OUT / "flame_shot_fluid.png")


if __name__ == "__main__":
    render()
