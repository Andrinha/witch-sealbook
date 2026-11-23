"""Render the Lua particles of four Sword seals. Run with python tests/render_blades.py."""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

from harness import DATA, cast_page, world_runtime
from test_sign_effects import seal_tree

OUT = Path(__file__).resolve().parent / "output"
SIZE = (108, 92)
ORIGIN = (43, 48)
SCALE = 3
FONT = ImageFont.load_default(size=16)
CASES = [
    ("Fire", ["fire"], []),
    ("Ice / Column", ["water", "crystal"], ["column", "column"]),
    ("Lightning / Spiraling Wind", ["lightning"], ["windsign", "windsign"]),
    ("Raincleaver", [], []),
]


def capture(title, elements, signs, player):
    lua = world_runtime()
    lua.execute("""
        EntitySetTransform(PLAYER, 0, -36)
        EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent"))
        for _, id in ipairs(ENEMIES) do EntityKill(id) end
    """)
    if title == "Raincleaver":
        blade = cast_page(lua, "raincleaver", ty=-40)
    else:
        tree = seal_tree(lua, ["sword", *elements], [(sign, False) for sign in signs])
        result = lua.eval("compile_spell")(tree)
        spell = result[0] if isinstance(result, tuple) else result
        blade = lua.eval("""function(data)
            return cast_spell(PLAYER, parse_spell_data(data), 0, -40, 1, 0, 200, -40, W.frame, nil)[1]
        end""")(lua.eval("seal_page_data")(spell))

    # The awakening flash precedes this hook. The blade and its water are emitted in the following updates.
    particles, frames = [], []

    def cosmetic(material, x, y, count, vx, vy, color, lmin, lmax, force, front, collide, randomize, gx, gy):
        rgb = tuple((int(color) >> shift) & 255 for shift in (0, 8, 16))
        alpha = ((int(color) >> 24) & 255) / 255
        particles.append((tick, x, y, vx, vy, gy or 0, rgb, alpha, (lmin + lmax) / 2))

    def water(material, x, y, count, vx, vy, *flags):
        if material == "water":
            particles.append((tick, x, y, vx, vy, 150, (62, 131, 223), 0.8, 0.19))

    lua.globals().GameCreateCosmeticParticle = cosmetic
    lua.globals().GameCreateParticle = water
    active = 0
    for tick in range(90):
        lua.eval("simulate")(1)
        alive = lua.eval("EntityGetIsAlive")(blade)
        active += int(alive)
        scene = Image.new("RGB", SIZE, (15, 19, 29))
        scene.paste(player, (ORIGIN[0] - 6, ORIGIN[1] - 14), player)
        light = Image.new("RGB", SIZE)
        pixels = light.load()
        for born, x, y, vx, vy, gravity, rgb, alpha, life in particles:
            dt = (tick - born) / 60
            if dt >= life:
                continue
            px = round(ORIGIN[0] + x + vx * dt)
            py = round(ORIGIN[1] + y + 36 + vy * dt + 0.5 * gravity * dt * dt)
            if 0 <= px < SIZE[0] and 0 <= py < SIZE[1]:
                fade = alpha * (1 - dt / life)
                pixels[px, py] = tuple(max(old, round(c * fade)) for old, c in zip(pixels[px, py], rgb))
        scene = ImageChops.add(ImageChops.add(scene, light.filter(ImageFilter.GaussianBlur(1.2))), light)
        scene = scene.resize((SIZE[0] * SCALE, SIZE[1] * SCALE), Image.Resampling.NEAREST)
        ImageDraw.Draw(scene).text((10, 8), title, font=FONT, fill=(226, 224, 213))
        frames.append(scene)
        if not alive and tick >= active + 11:
            break
    errors = list(lua.eval("W.errors").values())
    if errors or not particles or not active:
        raise RuntimeError(f"{title}: {errors or 'no active blade'}")
    return frames, active


def main():
    player = Image.open(Path(DATA) / "data/enemies_gfx/player.png").convert("RGBA").crop((0, 1, 12, 20))
    rows = [capture(*case, player) for case in CASES]
    w, h = rows[0][0][0].size
    animation = []
    for tick in range(max(len(row) for row, _ in rows)):
        frame = Image.new("RGB", (w * 2, h * 2))
        for i, (row, _) in enumerate(rows):
            frame.paste(row[min(tick, len(row) - 1)], (i % 2 * w, i // 2 * h))
        animation.append(frame)
    OUT.mkdir(exist_ok=True)
    animation[0].save(OUT / "blades.gif", save_all=True, append_images=animation[1:], duration=45, loop=0)
    sheet = Image.new("RGB", (w * 3, h * len(rows)))
    for i, (row, active) in enumerate(rows):
        for j, fraction in enumerate((0.2, 0.5, 0.8)):
            sheet.paste(row[round((active - 1) * fraction)], (j * w, i * h))
    sheet.save(OUT / "blades_contact.png")


if __name__ == "__main__":
    main()
