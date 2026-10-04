"""Build the compact RGBA kernels used to reconstruct a continuous gas field.

python tools/make_fluid_flame_sprites.py
These are interpolation kernels, not animated flames: motion comes from Lua gas.
"""
from pathlib import Path
import math

from PIL import Image

OUT = Path(__file__).resolve().parents[1] / "files/gfx/fluid_flame"
SIZES = (4, 6, 8, 12, 16, 24, 32, 48)
HEAT = (0.06, 0.12, 0.24, 0.42, 0.7, 1.1, 1.8, 3.0)


def kernel(size, heat, violet=False):
    image = Image.new("RGBA", (size, size))
    hot = min(1, heat / 2.4)
    rgb = (255, int(65 + hot * 185), int(8 + hot * hot * 145))
    if violet:
        rgb = (int(180 + hot * 65), int(60 + hot * 150), 255)
    opacity = min(0.95, heat ** 0.65)
    cutoff = math.exp(-2)
    for y in range(size):
        for x in range(size):
            radius2 = ((x + 0.5 - size / 2) ** 2 + (y + 0.5 - size / 2) ** 2) / (size / 4) ** 2
            weight = max(0, (math.exp(-radius2 / 2) - cutoff) / (1 - cutoff))
            image.putpixel((x, y), (*rgb, round(255 * opacity * weight)))
    return image


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    for palette, violet in (("orange", False), ("violet", True)):
        for size in SIZES:
            for band, heat in enumerate(HEAT, 1):
                kernel(size, heat, violet).save(OUT / f"{palette}_{size}_{band}.png", optimize=True)


if __name__ == "__main__":
    build()
    print(OUT)
