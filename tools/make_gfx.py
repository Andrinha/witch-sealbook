"""Images and entities for the seals' solid magic (files/effects/build.lua): walls, platforms, bridges, roads, clouds made
of pieces - static physics bodies you can stand on, like the game's temporary platform. Each piece is an image whose
opaque pixels are the body (drawn in their own colors) and an entity file (files/entities/solid/<kind>.xml).
Also the sprites the effects draw (the flying book, the sealchair, the Floatglow Lamp, the Sand Cage's bands), the
Water Cage's sphere (pictures for the game's emitters, and their entities) and the books' items (files/books.lua): the Palm
Quire and the Great Tome in the world and in hand, and their icons.

    python tools/make_gfx.py      (needs pillow)
"""
import colorsys
import math
import os
import random
import zlib

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GFX = os.path.join(ROOT, "files", "gfx", "solid")
SPRITES = os.path.join(ROOT, "files", "gfx")
ENTITIES = os.path.join(ROOT, "files", "entities", "solid")
MOD = "mods/witch_notebook/files/"

# look: base color, grain (how much the pixels vary), alpha, highlight on the top edge
LOOKS = {
    "stone": dict(color=(118, 108, 96), grain=22, alpha=255, top=(150, 140, 126), crack=(70, 64, 58), material="rock_box2d_hard", crumble="sand"),
    "sand": dict(color=(214, 180, 110), grain=26, alpha=255, top=(236, 208, 146), crack=(176, 140, 80), material="rock_box2d", crumble="sand"),
    "ice": dict(color=(170, 220, 245), grain=14, alpha=215, top=(235, 250, 255), crack=(120, 180, 220), material="ice_glass_b2", crumble="snow"),
    "crystal": dict(color=(190, 170, 255), grain=10, alpha=200, top=(255, 255, 255), crack=(140, 120, 230), material="glass_box2d", crumble="glass_broken", rainbow=True),
    "water": dict(color=(70, 140, 235), grain=12, alpha=170, top=(170, 215, 255), crack=(50, 110, 210), material="ice_glass_b2", crumble="water"),
    "cloud": dict(color=(236, 240, 246), grain=8, alpha=235, top=(255, 255, 255), crack=(205, 212, 225), material="rock_box2d", crumble="snow"),
    "light": dict(color=(255, 236, 150), grain=10, alpha=200, top=(255, 255, 230), crack=(240, 200, 100), material="glass_box2d", crumble="spark_yellow"),
}

# kind: (look, shape, width, height)
PIECES = {
    "stone_block": ("stone", "block", 6, 6), "stone_slab": ("stone", "slab", 12, 4), "stone_plank": ("stone", "plank", 8, 3),
    # Wall Bend's brickwork: a brick and a half brick, each with its joint in shadow at the right and below
    "stone_brick": ("stone", "brick", 8, 4), "stone_brick_half": ("stone", "brick", 4, 4),
    # Sand Cage's panels: slanted slabs that overlap up the cage's side
    "sand_panel": ("sand", "panel", 9, 9),
    "sand_block": ("sand", "block", 6, 6), "sand_slab": ("sand", "slab", 12, 4), "sand_plank": ("sand", "plank", 8, 3),
    "ice_block": ("ice", "block", 6, 6), "ice_plank": ("ice", "plank", 8, 3),
    "crystal_plank": ("crystal", "plank", 8, 3), "crystal_block": ("crystal", "gem", 7, 7),
    "light_plank": ("light", "plank", 8, 3),
    "water_disc": ("water", "disc", 28, 5),
    "cloud": ("cloud", "cloud", 36, 13), "sand_cloud": ("sand", "cloud", 36, 13),
    # the Serpent's Bed of Sand: the billows its cloud is heaped up from, in three sizes
    "sand_puff_l": ("sand", "puff", 18, 13), "sand_puff_m": ("sand", "puff", 14, 11), "sand_puff_s": ("sand", "puff", 9, 8),
    "sand_flower": ("sand", "flower", 15, 15), "sand_castle": ("sand", "castle", 48, 36),
    "stone_hand": ("stone", "hand", 13, 11),
}

LATER_PIECES = {"stone_brick", "stone_brick_half", "sand_panel", "sand_puff_l", "sand_puff_m", "sand_puff_s"}  # see main(): seeded by name


def noise(rng, look, x, y, w, h):
    c = look["color"]
    g = look["grain"]
    k = rng.uniform(-1, 1) * g
    col = [max(0, min(255, int(v + k))) for v in c]
    if look.get("rainbow"):
        hue = (x / max(1, w) + y / max(1, h) * 0.3) % 1.0
        r, gg, b = hsv(hue, 0.35, 1.0)
        col = [int(0.5 * col[0] + 0.5 * r), int(0.5 * col[1] + 0.5 * gg), int(0.5 * col[2] + 0.5 * b)]
    return tuple(col) + (look["alpha"],)


def hsv(h, s, v):
    i = int(h * 6) % 6
    f = h * 6 - int(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    r, g, b = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
    return int(r * 255), int(g * 255), int(b * 255)


def recolor(src, lo, hi, hue):
    """The image 'src' with its colours of hue lo..hi (degrees) turned to 'hue': the cover, not the gilt or the paper"""
    img = Image.open(src).convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if a and s > 0.25 and lo <= h * 360 <= hi:
                r, g, b = colorsys.hsv_to_rgb(hue / 360, s, v)
                px[x, y] = (round(r * 255), round(g * 255), round(b * 255), a)
    return img


def draw_test_book():
    """The Test Book (books.lua): the Spellbook bound in red, its sprite and its icon"""
    recolor(os.path.join(SPRITES, "spellbook.png"), 150, 200, 2).save(os.path.join(SPRITES, "test_book.png"))
    recolor(os.path.join(SPRITES, "spellbook_icon.png"), 150, 200, 2).save(os.path.join(SPRITES, "test_book_icon.png"))


def mask(shape, w, h):
    """-> set of (x, y) that are solid"""
    pts = set()
    if shape == "panel":
        # a parallelogram leaning like "/": five pixels wide, shifted a pixel every two rows
        for y in range(h):
            shift = (h - 1 - y) // 2
            for x in range(shift, shift + w - (h - 1) // 2):
                pts.add((x, y))
    elif shape in ("block", "slab", "plank", "brick"):
        for y in range(h):
            for x in range(w):
                # rounded corners on blocks
                if shape == "block" and (x, y) in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
                    continue
                pts.add((x, y))
    elif shape == "gem":
        c = (w - 1) / 2
        for y in range(h):
            for x in range(w):
                if abs(x - c) + abs(y - c) <= c + 0.3:
                    pts.add((x, y))
    elif shape == "disc":
        for y in range(h):
            for x in range(w):
                u = (x - (w - 1) / 2) / (w / 2)
                v = (y - (h - 1) / 2) / (h / 2)
                if u * u + v * v <= 1.0:
                    pts.add((x, y))
    elif shape == "puff":
        # one billow: three round lobes side by side, the middle one higher (a small one is a single lobe)
        lobes = [(w * 0.5, h * 0.5, h * 0.5)] if w < 12 else [
            (w * 0.27, h * 0.62, h * 0.4), (w * 0.5, h * 0.46, h * 0.48), (w * 0.73, h * 0.62, h * 0.4)]
        for y in range(h):
            for x in range(w):
                if any((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r for cx, cy, r in lobes):
                    pts.add((x, y))
    elif shape == "cloud":
        puffs = [(w * 0.2, h * 0.62, h * 0.42), (w * 0.4, h * 0.45, h * 0.52), (w * 0.62, h * 0.4, h * 0.56),
                 (w * 0.8, h * 0.6, h * 0.42), (w * 0.5, h * 0.72, h * 0.4)]
        for y in range(h):
            for x in range(w):
                for (cx, cy, r) in puffs:
                    if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                        pts.add((x, y))
                        break
        # a flat bottom to stand on is not needed: the top is what one stands on
    elif shape == "flower":
        c = (w - 1) / 2
        for y in range(h):
            for x in range(w):
                dx, dy = x - c, y - c
                r = math.hypot(dx, dy)
                a = math.atan2(dy, dx)
                petal = c * (0.55 + 0.45 * abs(math.cos(2.5 * a)))
                if r <= petal:
                    pts.add((x, y))
    elif shape == "castle":
        # walls, three towers with battlements, an arch in the middle
        base = int(h * 0.55)
        for y in range(base, h):
            for x in range(2, w - 2):
                pts.add((x, y))
        for (tx, tw, th) in ((2, 9, h - 7), (w // 2 - 5, 10, h), (w - 11, 9, h - 7)):
            y0 = h - th + 3  # the tower's body; battlements above it
            for y in range(y0, h):
                for x in range(tx, tx + tw):
                    pts.add((x, y))
            for x in range(tx, tx + tw, 3):
                for y in range(y0 - 3, y0):
                    pts.add((x, y))
                    if x + 1 < tx + tw:
                        pts.add((x + 1, y))
        # arches: gates through the wall
        for (ax, aw) in ((w // 2 - 3, 7), (w // 4 - 2, 5), (3 * w // 4 - 2, 5)):
            for y in range(h - 9, h):
                for x in range(ax, ax + aw):
                    cy = h - 9 + aw / 2
                    if y >= cy or (x - (ax + (aw - 1) / 2)) ** 2 + (y - cy) ** 2 <= (aw / 2) ** 2:
                        pts.discard((x, y))
    elif shape == "hand":
        # a palm and four fingers pointing right, a thumb up
        for y in range(3, h - 1):
            for x in range(0, 6):
                pts.add((x, y))
        for i, fy in enumerate((3, 5, 7, 9)):
            for x in range(6, w - (1 if i in (0, 3) else 0)):
                pts.add((x, fy))
        for y in range(0, 4):
            pts.add((4, y))
            pts.add((5, y))
    return pts


def draw_piece(kind, look_key, shape, w, h, seed):
    look = LOOKS[look_key]
    rng = random.Random(seed)
    pts = mask(shape, w, h)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for (x, y) in pts:
        col = noise(rng, look, x, y, w, h)
        if (x, y - 1) not in pts:  # lit from above
            col = look["top"] + (look["alpha"],)
        elif rng.random() < 0.06:
            col = look["crack"] + (look["alpha"],)
        if shape == "brick" and (x == w - 1 or y == h - 1):
            col = look["crack"] + (look["alpha"],)  # the joint between bricks
        if shape == "puff":
            # a soft billow: no cracks; a bright crown two pixels deep, its underside in shadow, so that the billows
            # read as heaped up and not as one flat mass
            base = noise(rng, look, x, y, w, h)
            if (x, y - 1) not in pts:
                col = (255, 238, 190, look["alpha"])
            elif (x, y - 2) not in pts:
                col = look["top"] + (look["alpha"],)
            elif (x, y + 1) not in pts:
                col = look["crack"] + (look["alpha"],)
            elif (x, y + 2) not in pts:
                col = tuple((a + b) // 2 for a, b in zip(base[:3], look["crack"])) + (look["alpha"],)
            else:
                col = base
        if shape == "panel":
            # a slab seen edge on: its upper face lit, its lower edge in shadow
            if (x - 1, y) not in pts:
                col = look["top"] + (look["alpha"],)
            elif (x + 1, y) not in pts:
                col = look["crack"] + (look["alpha"],)
        img.putpixel((x, y), col)
    return img


# The Sand Cage's outline (effects/build.lua CAGE, the same numbers): half its width at a share 's' of its height
CAGE_R, CAGE_H, CAGE_BOTTOM = 16, 52, 17


def cage_half_width(s):
    if s < 0.3:
        return CAGE_R * math.sqrt(max(0.0, 1 - ((s - 0.3) / 0.3) ** 2))
    return CAGE_R * (1 - ((s - 0.3) / 0.7) ** 1.7)


def draw_cage_bands(share):
    """the panels of sand that cross in front of the caged one, as far up as 'share' of the cage: diagonal bands
    inside its outline. A picture only - the solid panels are the cage's sides (sand_panel)."""
    look = LOOKS["sand"]
    rng = random.Random(5)
    w, h = 2 * CAGE_R + 2, CAGE_H + 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    thick, gap, slope = 4, 6, 0.7
    for py in range(h):
        y = CAGE_BOTTOM + 1 - (h - 1 - py)  # relative to the cage's middle; the last row lies just under the cage
        s = (CAGE_BOTTOM - y) / CAGE_H
        if not 0 <= s <= share:
            continue
        half = cage_half_width(s) - 2
        for px in range(w):
            x = px - w / 2 + 0.5
            d = (x * slope + y) % (thick + gap)
            if abs(x) <= half and d < thick:
                k = rng.uniform(-1, 1) * look["grain"] * 0.4
                col = tuple(max(0, min(255, int(v + k))) for v in look["color"])
                if d < 1:
                    col = look["crack"]
                elif d >= thick - 1:
                    col = look["top"]
                img.putpixel((px, py), col + (255,))
    return img


def entity_xml(kind, look_key, w, h):
    look = LOOKS[look_key]
    return f"""<!-- Generated by tools/make_gfx.py. A piece of the seals' solid magic (effects/build.lua): a static body you can
     stand on; effects/crumble.lua scatters it into {look["crumble"]} when it ends. -->
<Entity tags="witch_solid,teleportable_NOT">
	<PhysicsBody2Component
		allow_sleep="1"
		angular_damping="0"
		linear_damping="0"
		is_static="1"
		fixed_rotation="1"
		kill_entity_after_initialized="0"
		destroy_body_if_entity_destroyed="1"
		auto_clean="0"
	></PhysicsBody2Component>

	<PhysicsImageShapeComponent
		is_root="1"
		centered="1"
		image_file="{MOD}gfx/solid/{kind}.png"
		material="{look["material"]}"
	></PhysicsImageShapeComponent>

	<VariableStorageComponent
		name="crumble"
		value_string="{look["crumble"]}"
		value_int="{max(w, h) // 2}"
	></VariableStorageComponent>

	<LuaComponent
		script_source_file="{MOD}effects/crumble.lua"
		execute_on_removed="1"
		execute_every_n_frame="-1"
	></LuaComponent>
</Entity>
"""


# The Water Cage's sphere (effects/water_cage.lua, the same numbers): its radii, and the frames it takes to swell
WATER_CAGE_SIZES, WATER_CAGE_GROW = (16, 21, 27, 34), 24


def draw_water_cage(r):
    """The sphere of radius r as the two pictures its emitters read (the game's image emitters, like
    data/particles/image_emitters/circle_128.png): a pixel's red is the chance that a cell is put there, its green
    the moment, 0..255; black puts nothing. The moment grows from the middle out in WATER_CAGE_GROW steps, so the
    sphere swells. 'fill' is the body of the sphere; 'rim' its skin, two cells thick, and the gleam on it up and
    to the left - a brighter material. No pixel is in both."""
    size = 2 * r + 3
    c = r + 1
    fill, rim = Image.new("RGB", (size, size)), Image.new("RGB", (size, size))
    for py in range(size):
        for px in range(size):
            dx, dy = px - c, py - c
            d = math.hypot(dx, dy)
            if d > r + 0.5:
                continue
            step = min(WATER_CAGE_GROW, round(d / (r + 0.5) * WATER_CAGE_GROW))
            turn = abs((math.degrees(math.atan2(dy, dx)) + 135 + 180) % 360 - 180)  # degrees from up-left
            skin = d > r - 1.5
            gleam = r * 0.62 <= d <= r * 0.62 + max(1.6, r * 0.09) and turn <= 30
            glint = math.hypot(dx - r * 0.45, dy - r * 0.45) <= max(0.8, r * 0.05)
            (rim if skin or gleam or glint else fill).putpixel((px, py), (255, int(step * 255 / WATER_CAGE_GROW), 0))
    return fill, rim


def water_cage_xml(r):
    def emitter(part, material):
        return f"""	<ParticleEmitterComponent
		emitted_material_name="{material}"
		create_real_particles="1"
		emit_cosmetic_particles="0"
		count_min="1"
		count_max="1"
		x_vel_min="0"
		x_vel_max="0"
		y_vel_min="0"
		y_vel_max="0"
		emission_interval_min_frames="1"
		emission_interval_max_frames="1"
		image_animation_file="{MOD}gfx/water_cage_{r}_{part}.png"
		image_animation_speed="{255 / WATER_CAGE_GROW}"
		image_animation_loop="1"
		image_animation_raytrace_from_center="1"
		collide_with_gas_and_fire="0"
		render_on_grid="1"
		is_emitting="1"
	></ParticleEmitterComponent>
"""
    return f"""<!-- Generated by tools/make_gfx.py. The body of a Water Cage of radius {r} (effects/water_cage.lua): two picture
     emitters put real cells of standing water in the sphere's shape, from its middle out and never through a wall,
     and keep mending it. -->
<Entity tags="witch_water_cage_body">
{emitter("fill", "witch_cage_water")}
{emitter("rim", "witch_cage_rim")}</Entity>
"""


BOOK_W, BOOK_H, BOOK_SPINE = 34, 20, 13  # the flying book's frames: their size and the row its spine lies on


def draw_book(lift=0.0):
    """The flying book of the Seal of Expansion and Levitation, 34 x 20: a big open book seen from its fore-edge,
    its two halves spread like wings. 'lift' raises (or, negative, drops) their tips: the frames of its wingbeat.
    Each half is a block of pages on its cover, arched a little; lines of writing show on the open pages."""
    img = Image.new("RGBA", (BOOK_W, BOOK_H), (0, 0, 0, 0))
    cover, edge = (112, 44, 58, 255), (62, 24, 34, 255)
    paper, shade, ink = (240, 230, 202, 255), (198, 184, 150, 255), (70, 58, 120, 255)
    gilt = (226, 186, 92, 255)
    mid = (BOOK_W - 1) / 2
    for x in range(BOOK_W):
        t = abs(x - mid) / mid  # 0 at the spine, 1 at the tip of a half
        if t < 0.06:
            continue  # the gutter between the halves is drawn with the spine below
        top = BOOK_SPINE - 3 - lift * t ** 1.3 - 1.6 * math.sin(math.pi * t)  # the page's surface
        top = int(round(top))
        thick = 3 if t < 0.85 else 2  # the block of pages thins towards the fore-edge
        for k in range(thick):
            img.putpixel((x, top + k), paper if k == 0 else shade if k == thick - 1 else paper)
        img.putpixel((x, top + thick), cover)
        img.putpixel((x, top + thick + 1), edge)
        if t > 0.92:
            img.putpixel((x, top + thick), gilt)  # the cover's metal corner
        # writing on the open page: short strokes with gaps, none by the gutter or the edge
        if 0.16 < t < 0.84 and int(abs(x - mid)) % 4 in (1, 2):
            img.putpixel((x, top), ink)
    # the spine: a dark ridge between the halves, hanging a little below them
    for x in (int(mid), int(mid) + 1):
        for y in range(BOOK_SPINE - 3, BOOK_SPINE + 3):
            img.putpixel((x, y), edge if y > BOOK_SPINE - 2 else cover)
    return img


def draw_book_small(scale):
    """the book while it grows from the size it has in hand: the level frame, smaller"""
    full = draw_book(0)
    box = full.getbbox()
    cut = full.crop(box)
    return cut.resize((max(3, round(cut.width * scale)), max(2, round(cut.height * scale))), Image.NEAREST)


def draw_chair():
    """the sealchair: a stone armchair on four short legs, 16 x 18"""
    w, h = 16, 18
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    stone = (132, 122, 110, 255)
    dark = (86, 78, 70, 255)
    light = (170, 160, 146, 255)
    glow = (150, 230, 255, 255)
    for y in range(0, 12):  # the back
        for x in range(1, 5):
            img.putpixel((x, y), light if x == 1 else stone)
    for y in range(9, 12):  # the seat
        for x in range(1, 15):
            img.putpixel((x, y), light if y == 9 else stone)
    for y in range(6, 9):  # the armrest
        for x in range(10, 15):
            img.putpixel((x, y), light if y == 6 else stone)
    for y in range(12, h):  # legs
        for x in (2, 3, 12, 13):
            img.putpixel((x, y), dark)
    img.putpixel((3, 4), glow)  # a small seal on the back
    img.putpixel((2, 5), glow)
    img.putpixel((3, 6), glow)
    return img


# The Golem (effects/mover.lua): a hulk of brickwork - the ground's own stones stood up. Hunched, a small head sunk
# between its shoulders with one lit eye, long arms with fists that reach the ground, short legs. It faces right;
# the effect mirrors it. Every frame is GOLEM_W x GOLEM_H with its feet's middle at (GOLEM_X, GOLEM_H).
GOLEM_W, GOLEM_H, GOLEM_X = 44, 38, 18
GOLEM_POSES = {
    # legs: how far the front and the back foot are set forwards; bob: the body sinks; lean: it tips forwards;
    # front / back: where the fists are, from the feet's middle
    "stand": dict(legs=(0, 0), bob=0, lean=0, front=(11, -7), back=(-10, -6)),
    "walk_1": dict(legs=(3, -2), bob=0, lean=1, front=(8, -8), back=(-7, -7)),
    "walk_2": dict(legs=(-2, 3), bob=1, lean=1, front=(13, -8), back=(-12, -7)),
    "windup": dict(legs=(1, -1), bob=0, lean=-1, front=(7, -33), back=(-11, -7)),
    "slam": dict(legs=(3, -2), bob=2, lean=3, front=(21, -4), back=(-8, -10)),
}
GOLEM_RISE = {"rise_1": 30, "rise_2": 19, "rise_3": 8}  # how deep in the ground it still stands


def golem_brick(x, y, shade):
    """the color of the brickwork at x, y: courses three pixels high, joints staggered, every brick its own tone"""
    course = y // 3
    along = x + (course % 2) * 3
    if y % 3 == 2 or along % 6 == 5:
        tone = 58  # a joint
    else:
        rng = random.Random(course * 131 + along // 6)
        tone = rng.choice((104, 112, 120, 128, 138)) + (6 if y % 3 == 0 else 0)
    warm = random.Random(course * 131 + along // 6 + 7).random() < 0.25  # a paving brick among the stones
    r, g, b = (tone + 16, tone, tone - 14) if warm else (tone + 4, tone - 2, tone - 10)
    return tuple(max(0, min(255, int(v * shade))) for v in (r, g, b)) + (255,)


def draw_golem(pose):
    img = Image.new("RGBA", (GOLEM_W, GOLEM_H), (0, 0, 0, 0))
    edge = (40, 36, 34, 255)

    def part(cells, shade):
        """one part of the body over what is drawn already: brickwork with a dark rim and a lit top"""
        cells = {(x, y) for x, y in cells if 0 <= x < GOLEM_W and 0 <= y < GOLEM_H}
        for x, y in cells:
            rim = any((x + dx, y + dy) not in cells for dx, dy in ((1, 0), (-1, 0), (0, 1)))
            top = (x, y - 1) not in cells
            color = golem_brick(x, y, shade * (1.25 if top else 1))
            img.putpixel((x, y), edge if rim and not top else color)

    def block(x0, y0, x1, y1):
        return [(x, y) for x in range(round(x0), round(x1) + 1) for y in range(round(y0), round(y1) + 1)]

    def limb(x0, y0, x1, y1, thick):
        cells = []
        steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(steps + 1):
            t = i / steps
            cells += block(x0 + (x1 - x0) * t - thick / 2, y0 + (y1 - y0) * t - thick / 2,
                           x0 + (x1 - x0) * t + thick / 2 - 1, y0 + (y1 - y0) * t + thick / 2 - 1)
        return cells

    def fist(x, y):
        return [c for c in block(x - 3, y - 3, x + 3, y + 3) if abs(c[0] - x) + abs(c[1] - y) < 6]

    cx, ground = GOLEM_X, GOLEM_H - 1
    bob, lean = pose["bob"], pose["lean"]
    hip = ground - 8 + bob
    shoulder = hip - 15
    # the arm behind, the leg behind
    bx, by = pose["back"]
    part(limb(cx - 7 + lean, shoulder + 3, cx + bx, ground + by, 4) + fist(cx + bx, ground + by), 0.72)
    part(block(cx - 6 + pose["legs"][1], hip - 1, cx - 2 + pose["legs"][1], ground)
         + block(cx - 7 + pose["legs"][1], ground - 1, cx - 1 + pose["legs"][1], ground), 0.78)
    # the leg in front
    part(block(cx + 2 + pose["legs"][0], hip - 1, cx + 6 + pose["legs"][0], ground)
         + block(cx + 2 + pose["legs"][0], ground - 1, cx + 8 + pose["legs"][0], ground), 0.92)
    # the body: broad at the shoulders, a hump of loose courses on its back
    body = []
    for y in range(shoulder, hip + 1):
        t = (y - shoulder) / (hip - shoulder)
        tip = lean * (1 - t)
        body += block(cx - 9 + 3 * t + tip, y, cx + 9 - 3 * t + tip, y)
    body += block(cx - 8 + lean, shoulder - 3, cx + 1 + lean, shoulder - 1) + block(cx - 6 + lean, shoulder - 5, cx - 2 + lean, shoulder - 4)
    part(body, 1.0)
    # the head, low between the shoulders, its jaw forwards
    hx, hy = cx + 5 + lean * 2, shoulder - 4
    part(block(hx - 3, hy, hx + 3, hy + 5) + block(hx - 1, hy + 6, hx + 4, hy + 7), 1.08)
    img.putpixel((hx + 2, hy + 2), (150, 235, 255, 255))  # its eye
    img.putpixel((hx + 1, hy + 2), (70, 150, 190, 255))
    # the arm in front
    fx_, fy = pose["front"]
    part(limb(cx + 7 + lean, shoulder + 3, cx + fx_, ground + fy, 5) + fist(cx + fx_, ground + fy), 1.12)
    return img


def draw_golem_rising(depth):
    """the golem standing 'depth' pixels deep in the ground it rises from, loose bricks heaped at its foot"""
    whole = draw_golem(GOLEM_POSES["stand"])
    img = Image.new("RGBA", (GOLEM_W, GOLEM_H), (0, 0, 0, 0))
    img.paste(whole.crop((0, 0, GOLEM_W, GOLEM_H - depth)), (0, depth))
    rng = random.Random(depth)
    for i in range(9):  # the heap: bricks lying anyhow
        x = GOLEM_X - 13 + i * 3 + rng.randint(-1, 1)
        top = GOLEM_H - 2 - rng.randint(0, 2) - (2 if 2 < i < 6 else 0)
        for xx in range(x, x + 4):
            for yy in range(top, GOLEM_H):
                img.putpixel((xx, yy), (40, 36, 34, 255) if xx == x + 3 or yy == GOLEM_H - 1 else golem_brick(xx + i, yy, 1.1 if yy == top else 0.9))
    return img


def paint(rows, colors):
    """an image from rows of characters; '.' is transparent"""
    img = Image.new("RGBA", (len(rows[0]), len(rows)), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c != ".":
                img.putpixel((x, y), colors[c])
    return img


# the Floatglow Lamp (effects/light.lua): dark metal lit from inside by its seal
LAMP = {"d": (46, 38, 40, 255), "m": (84, 68, 58, 255), "h": (136, 110, 82, 255), "b": (196, 156, 76, 255),
        "l": (236, 204, 124, 255), "g": (255, 244, 190, 255)}


def draw_lamp_cone():
    """the lamp's conical top, 7 x 9: holes let the light through, the rim catches it from below"""
    return paint(["...d...",
                  "...m...",
                  "..dmd..",
                  "..dgm..",
                  ".dmhmd.",
                  ".dghmd.",
                  "dmmhgmd",
                  "dmhhmmd",
                  "lbbbbbl"], LAMP)


def draw_lamp_tray():
    """the lamp's shallow tray on its foot, 13 x 5: the seal's page lines it, so its inside glows"""
    return paint(["l...........l",
                  "blllggggglllb",
                  ".mbbbbbbbbbm.",
                  "...dmmmmmd...",
                  ".....dmd....."], LAMP)


def draw_lamp_plate():
    """the wall plate of an anchored lamp's bracket, 2 x 7"""
    return paint(["dm", "mh", "mh", "hb", "mh", "mh", "dm"], LAMP)


# the books' colors
BRASS, BRASS_LIGHT, BRASS_DARK = (196, 156, 76, 255), (236, 204, 124, 255), (122, 90, 40, 255)
QUIRE_LEATHER, QUIRE_DARK = (92, 54, 36, 255), (62, 36, 26, 255)
GILT = (240, 196, 96, 255)
TOME_LEATHER, TOME_DARK, TOME_LIGHT = (50, 34, 30, 255), (30, 20, 18, 255), (78, 56, 48, 255)
IRON, IRON_LIGHT = (110, 102, 94, 255), (170, 160, 146, 255)
PAGES, PAGES_DARK = (232, 214, 172, 255), (176, 156, 118, 255)


def line_pixels(x0, y0, x1, y1):
    """the pixels of a line (Bresenham)"""
    out = []
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        out.append((x0, y0))
        if x0 == x1 and y0 == y1:
            return out
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def draw_quire(w, h, cx, cy, r, tab, sigil):
    """the Palm Quire closed, seen from its lid: a brass-rimmed disc of leather with the gilt sigil (a triangle, lines
    from its corners to the rim) and a pointed tab with a hole over it"""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - cx, y - cy)
            if d <= r + 0.3:
                if d > r - 1:
                    # the rim, lit from the upper left
                    lit = (x - cx) + (y - cy) < -0.5
                    img.putpixel((x, y), BRASS_LIGHT if lit else (BRASS if (x - cx) + (y - cy) < 1.5 else BRASS_DARK))
                else:
                    # the leather, in the rim's shadow at the lower right
                    shade = d > r - 2 and (x - cx) + (y - cy) > 0.5
                    img.putpixel((x, y), QUIRE_DARK if shade else QUIRE_LEATHER)
    # the tab: a leather point over the lid, rimmed in brass, with a hole
    top = int(math.floor(cy - r))
    for k in range(1, tab + 1):
        half = max(0, round((tab - k) * 0.6 + 0.4))
        y = top - k + 1
        for x in range(int(cx - half), int(cx + half) + 1):
            if 0 <= y < h:
                edge = abs(x - cx) >= half - 0.5
                img.putpixel((x, y), BRASS_DARK if edge else QUIRE_LEATHER)
    if tab >= 3:
        img.putpixel((int(cx), top - tab // 2), (0, 0, 0, 0))
    # the sigil
    tr, reach = sigil
    corners = []
    for i in range(3):
        a = -math.pi / 2 + i * 2 * math.pi / 3
        corners.append((round(cx + math.cos(a) * tr), round(cy + math.sin(a) * tr), a))
    for i in range(3):
        (x0, y0, a), (x1, y1, _) = corners[i], corners[(i + 1) % 3]
        for p in line_pixels(x0, y0, x1, y1):
            img.putpixel(p, GILT)
        ex, ey = round(cx + math.cos(a) * reach), round(cy + math.sin(a) * reach)
        for p in line_pixels(x0, y0, ex, ey):
            img.putpixel(p, GILT)
    return img


def draw_tome(w, h, eye, corners=True):
    """the Great Tome closed, a little turned: black leather with iron corners, the spine's raised bands on the left,
    the page block and a brass clasp on the right, a gilt eye in the middle of the cover"""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    right = w - 3  # the cover's right edge; the pages and the back board show past it
    for y in range(h):
        for x in range(w):
            if x <= right:
                c = TOME_LEATHER
                if x == 0 or y == 0 or y == h - 1:
                    c = TOME_DARK
                elif x == 1:
                    c = TOME_DARK if y % 4 == 2 else TOME_LIGHT  # the spine's raised bands
                elif x == right:
                    c = TOME_DARK
                img.putpixel((x, y), c)
            elif x == right + 1 and 1 <= y <= h - 2:
                img.putpixel((x, y), PAGES if y % 2 else PAGES_DARK)
            elif x == right + 2 and 1 <= y <= h - 1:
                img.putpixel((x, y), TOME_DARK)
    if corners:
        for (x, y) in ((right, 0), (right - 1, 0), (right, 1), (right, h - 1), (right - 1, h - 1), (right, h - 2)):
            img.putpixel((x, y), IRON)
        img.putpixel((right - 1, 1), IRON_LIGHT)
        img.putpixel((right - 1, h - 2), IRON_LIGHT)
    # the clasp across the fore-edge
    mid = h // 2
    for x in range(right - 1, w):
        img.putpixel((x, mid), BRASS)
    img.putpixel((right - 1, mid), BRASS_LIGHT)
    # the eye
    ex, ey, ew = eye
    for dx in range(-ew, ew + 1):
        lid = 1 if abs(dx) < ew else 0
        img.putpixel((ex + dx, ey - lid), GILT)
        img.putpixel((ex + dx, ey + lid), GILT)
    img.putpixel((ex, ey), (150, 30, 30, 255))
    return img


def main():
    os.makedirs(GFX, exist_ok=True)
    os.makedirs(ENTITIES, exist_ok=True)
    # The first pieces were seeded by their place in the sorted list. Pieces added later take a seed from their
    # name instead, so that a new piece never changes the grain of the ones already in the game.
    first = sorted(kind for kind in PIECES if kind not in LATER_PIECES)
    for kind, (look, shape, w, h) in sorted(PIECES.items()):
        seed = zlib.crc32(kind.encode()) if kind in LATER_PIECES else 1000 + first.index(kind)
        draw_piece(kind, look, shape, w, h, seed).save(os.path.join(GFX, kind + ".png"))
        with open(os.path.join(ENTITIES, kind + ".xml"), "w", encoding="utf-8", newline="\n") as f:
            f.write(entity_xml(kind, look, w, h))
    # the flying book's wingbeat: tips up, level, down (the effect plays 1 2 3 2), and two sizes for its growing
    for i, lift in enumerate((5, 0, -4), 1):
        draw_book(lift).save(os.path.join(SPRITES, f"flying_book_{i}.png"))
    draw_book_small(0.4).save(os.path.join(SPRITES, "flying_book_small.png"))
    draw_book_small(0.7).save(os.path.join(SPRITES, "flying_book_mid.png"))
    draw_chair().save(os.path.join(SPRITES, "sealchair.png"))
    draw_quire(9, 12, 4, 7, 4.3, 3, (1.4, 3.4)).save(os.path.join(SPRITES, "palm_quire.png"))
    draw_quire(16, 16, 7.5, 9, 6.6, 3, (2.6, 5.6)).save(os.path.join(SPRITES, "palm_quire_icon.png"))
    draw_tome(12, 14, (5, 6, 2)).save(os.path.join(SPRITES, "great_tome.png"))
    draw_tome(16, 16, (7, 7, 3)).save(os.path.join(SPRITES, "great_tome_icon.png"))
    draw_test_book()
    for i in (1, 2, 3):
        draw_cage_bands(i / 3).save(os.path.join(SPRITES, f"sand_cage_bands_{i}.png"))
    draw_lamp_cone().save(os.path.join(SPRITES, "floatglow_cone.png"))
    draw_lamp_tray().save(os.path.join(SPRITES, "floatglow_tray.png"))
    draw_lamp_plate().save(os.path.join(SPRITES, "floatglow_plate.png"))
    paint(["h"], LAMP).save(os.path.join(SPRITES, "floatglow_link.png"))  # a chain link, a pixel of the bracket's arm
    for name, pose in GOLEM_POSES.items():
        draw_golem(pose).save(os.path.join(SPRITES, f"golem_{name}.png"))
    for name, depth in GOLEM_RISE.items():
        draw_golem_rising(depth).save(os.path.join(SPRITES, f"golem_{name}.png"))
    for r in WATER_CAGE_SIZES:
        for part, img in zip(("fill", "rim"), draw_water_cage(r)):
            img.save(os.path.join(SPRITES, f"water_cage_{r}_{part}.png"))
        with open(os.path.join(ENTITIES, "..", f"water_cage_{r}.xml"), "w", encoding="utf-8", newline="\n") as f:
            f.write(water_cage_xml(r))
    print(f"{len(PIECES)} pieces, 27 sprites, {len(WATER_CAGE_SIZES)} water cages")


if __name__ == "__main__":
    main()
