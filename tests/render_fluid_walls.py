"""Actual gas sprite/cosmetic calls beside terrain; no extra bloom or native fire."""
import argparse
from pathlib import Path
import subprocess

from PIL import Image, ImageChops, ImageDraw, ImageFont

from test_fluid_draw import wall_strip
from harness import world_runtime, cast_page
from fluid_render_capture import Sprite, sprites, draw_sprites

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests/output"
FONT = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 16)


def preview(scene, old=None):
    lua = wall_strip("floor") if scene == "strip" else world_runtime()
    if scene != "strip":
        lua.execute('''
            function RaytraceSurfacesAndLiquiform(x1,y1,x2,y2)
                if y1<=-78 or y1>=-2 then return true,x1,y1 end
                local wall=y2<=-78 and -78 or y2>=-2 and -2
                if wall then local t=(wall-y1)/(y2-y1);return true,x1+(x2-x1)*t,wall end
                return false,x2,y2
            end
            for _,e in ipairs(ENEMIES) do EntityKill(e) end
            dofile_once("mods/witch_notebook/files/effects/flame_fields.lua")
        ''')
    if old:
        lua.execute(old)
    pixels, transient = [], []
    lua.globals().GameCreateCosmeticParticle = lambda m,x,y,n,vx,vy,c,*args: pixels.append((x,y,int(c)&0xFFFFFFFF))
    lua.globals().GameCreateSpriteForXFrames = lambda path,x,y,*args: transient.append(Sprite(path,x,y))
    if scene == "strip":
        lua.execute('FlameFluidDraw.draw(S,{},P,{pixels=512})')
        image, ox, oy = Image.new("RGB", (128, 64), (14, 18, 24)), 64, 28
        ImageDraw.Draw(image).rectangle((0, oy, 128, 64), fill=(42, 39, 44))
    else:
        cast_page(lua, "ring_of_fire")
        for _ in range(23):
            pixels.clear(); transient.clear()
            lua.eval("simulate")(1)
        image, ox, oy = Image.new("RGB", (192, 96), (14, 18, 24)), 96, 86
        draw = ImageDraw.Draw(image)
        draw.rectangle((0, 0, 192, oy-78), fill=(42, 39, 44))
        draw.rectangle((0, oy-2, 192, 96), fill=(42, 39, 44))
    draw_sprites(image, transient + sprites(lua, layer=None), ox, oy)
    light = Image.new("RGB", image.size)
    draw = ImageDraw.Draw(light)
    for x,y,c in pixels:
        alpha = (c >> 24)/255
        draw.point((round(x+ox),round(y+oy)), fill=tuple(round(((c>>shift)&255)*alpha) for shift in (0,8,16)))
    return ImageChops.add(image, light)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, help="Saved renderer source; otherwise use commit 292063a")
    args = parser.parse_args()
    old = args.baseline.read_text(encoding="utf-8") if args.baseline else subprocess.check_output(
        ["git", "show", "292063a:files/effects/fluid_draw.lua"], cwd=ROOT, text=True, encoding="utf-8")
    OUT.mkdir(exist_ok=True)
    sheet = Image.new("RGB", (1280, 720), (14, 18, 24))
    for row, scene in enumerate(("strip", "ring")):
        for col, source in enumerate((old, None)):
            view = preview(scene, source).resize((640, 320), Image.Resampling.NEAREST)
            sheet.paste(view, (col*640, row*360+30))
            draw = ImageDraw.Draw(sheet)
            title = ("Uniform hot row / " if scene=="strip" else "Ring of Fire in a low cave / ")
            draw.text((col*640+12,row*360+7), title + ("Before" if col==0 else "After"), font=FONT, fill=(235,215,180))
    ImageDraw.Draw(sheet).text((12,700), "Offline preview; no added bloom; native fire omitted", font=FONT, fill=(150,160,180))
    sheet.save(OUT / "fluid_walls.png")
    print(OUT / "fluid_walls.png")


if __name__ == "__main__":
    main()
