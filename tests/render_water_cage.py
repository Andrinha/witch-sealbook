"""The Water Cage's sphere as its emitters build it: the cells of each picture whose moment has come.

python tests/render_water_cage.py [name] -> tests/output/<name>.png (default water_cage)
One row for each radius; left to right the sphere swells (the pictures' green is the moment, 0..255). The colors are
the two materials' (files/materials.xml) over a dark cave, without the game's glow. The figure is a stand-in for
the creature sealed in the middle.
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = Path(__file__).resolve().parent / "output"
SIZES = (16, 21, 27, 34)
MOMENTS = (0.25, 0.5, 0.75, 1)
SCALE, CELL = 5, 76
CAVE, BODY = (17, 20, 29), (150, 70, 60)
FILL, RIM = (0x4c, 0x9a, 0xe6, 0x8a), (0xc4, 0xea, 0xff, 0xd0)


def sphere(r, moment):
    panel = Image.new("RGB", (CELL, CELL), CAVE)
    for dy in range(-7, 5):  # the sealed creature, behind the water
        for dx in range(-3, 4):
            panel.putpixel((CELL // 2 + dx, CELL // 2 + dy), BODY)
    for part, color in (("fill", FILL), ("rim", RIM)):
        img = Image.open(ROOT / "files" / "gfx" / f"water_cage_{r}_{part}.png").convert("RGB")
        ox = (CELL - img.width) // 2
        for y in range(img.height):
            for x in range(img.width):
                red, green, _ = img.getpixel((x, y))
                if red and green <= moment * 255:
                    under = panel.getpixel((ox + x, ox + y))
                    k = color[3] / 255
                    panel.putpixel((ox + x, ox + y), tuple(int(u + (c - u) * k) for u, c in zip(under, color)))
    return panel.resize((CELL * SCALE, CELL * SCALE), Image.NEAREST)


if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "water_cage"
    OUT.mkdir(exist_ok=True)
    sheet = Image.new("RGB", (CELL * SCALE * len(MOMENTS), CELL * SCALE * len(SIZES)))
    for row, r in enumerate(SIZES):
        for col, moment in enumerate(MOMENTS):
            sheet.paste(sphere(r, moment), (col * CELL * SCALE, row * CELL * SCALE))
    sheet.save(OUT / (name + ".png"))
    print(OUT / (name + ".png"))
