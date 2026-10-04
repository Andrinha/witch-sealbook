"""Compare actual density samples on bright sky, without extra bloom."""
import subprocess

from PIL import Image

from render_fire_spells import render, OUT, HERE


def main():
    OUT.mkdir(exist_ok=True)
    old = subprocess.check_output(["git", "show", "292063a:files/effects/fluid_draw.lua"],
                                  cwd=HERE.parent, text=True, encoding="utf-8")
    sheet = Image.new("RGB", (1440, 880))
    for row, (key, age) in enumerate((("ring_of_fire", 24), ("flame_burst", 57))):
        for col, (name, source) in enumerate((("Before: alpha overlaps", old), ("After: smooth gas + glow", None))):
            preview = render(key, key + " / " + name, age, draw_source=source,
                             sky=(91, 169, 204), bloom=False)
            sheet.paste(preview, (col * 720, row * 440))
    sheet.save(OUT / "fluid_seams.png")
    print(OUT / "fluid_seams.png")


if __name__ == "__main__":
    main()
