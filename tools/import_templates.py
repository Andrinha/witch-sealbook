"""Generates files/templates.lua: stroke templates of the sigils and signs the notebook recognizes.

Sigil shapes and the column, levitation and convergence signs come from the MIT-licensed
wha-spell-simulator dictionary (https://github.com/ytnrvdf/wha-spell-simulator, (c) 2026 Nervadof).
Dispersion follows the Independent Witch Hat Atelier Wiki drawing: a column with an arc under its base;
the other signs (OWN_SIGNS) are simplified from the wiki's pictures.

Usage (from the mod folder):  python tools/import_templates.py [path to wha-spell-simulator json folder]
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shapes  # noqa: E402

MOD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(MOD, "..", "reference", "wha-spell-simulator")
POINTS_PER_STROKE = 24
SIGIL_IDS = {"fire": "fire", "water": "water", "wind-directs-air": "wind", "earth": "earth", "light": "light"}


def resample(stroke, n=POINTS_PER_STROKE):
    pts = [(p["x"], p["y"]) if isinstance(p, dict) else p for p in stroke]
    dedup = [pts[0]] + [p for a, p in zip(pts, pts[1:]) if p != a]
    if len(dedup) < 2:
        return dedup
    lengths = [0.0]
    for a, b in zip(dedup, dedup[1:]):
        lengths.append(lengths[-1] + math.dist(a, b))
    total = lengths[-1]
    out, j = [], 0
    for i in range(n):
        target = total * i / (n - 1)
        while j < len(lengths) - 2 and lengths[j + 1] < target:
            j += 1
        seg = lengths[j + 1] - lengths[j] or 1e-9
        t = (target - lengths[j]) / seg
        (ax, ay), (bx, by) = dedup[j], dedup[j + 1]
        out.append((ax + (bx - ax) * t, ay + (by - ay) * t))
    return out


def load(name):
    return {e["id"]: e for e in json.load(open(os.path.join(SRC, name), encoding="utf-8"))}


def stroke_length(stroke):
    pts = [(p["x"], p["y"]) if isinstance(p, dict) else p for p in stroke]
    return sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))


def merge_fragments(strokes, gap=0.035, min_length=0.04):
    """The source templates are traced from images: lines come in fragments and with stray dots.
    Chains fragments whose ends meet into whole lines, then drops what is left too short."""
    lines = [[(p["x"], p["y"]) if isinstance(p, dict) else p for p in s] for s in strokes]
    lines = [l for l in lines if l]
    merged = True
    while merged:
        merged = False
        for i in range(len(lines)):
            for j in range(len(lines)):
                if i == j:
                    continue
                a, b = lines[i], lines[j]
                for a_, b_ in [(a, b), (a, b[::-1]), (a[::-1], b), (a[::-1], b[::-1])]:
                    if math.dist(a_[-1], b_[0]) <= gap:
                        lines[i] = a_ + b_
                        del lines[j]
                        merged = True
                        break
                if merged:
                    break
            if merged:
                break
    return [l for l in lines if stroke_length(l) >= min_length]


def lua_shape(strokes, traced=True):
    """strokes -> Lua table text; traced strokes (the simulator's) are joined from fragments first. A
    one-point stroke is a dot and stays one point."""
    parts = []
    dots = [] if traced else [s for s in strokes if len(s) == 1]  # traced strokes: stray points aren't dots
    lines = merge_fragments(strokes) if traced else [s for s in strokes if len(s) > 1]
    for s in lines:
        pts = resample(s)
        parts.append("{ " + ", ".join(f"{{ {x:.3f}, {y:.3f} }}" for x, y in pts) + " }")
    for d in dots:
        x, y = d[0]
        parts.append(f"{{ {{ {x:.3f}, {y:.3f} }} }}")
    return "{\n\t\t\t" + ",\n\t\t\t".join(parts) + ",\n\t\t}"


def line(*pts, n=12):
    """a polyline through pts, n points per segment"""
    out = []
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        out += [(ax + (bx - ax) * i / n, ay + (by - ay) * i / n) for i in range(n)]
    return out + [pts[-1]]


def wave(x, amp=0.1, n=24):
    """a vertical S-curve at x"""
    return [(x + amp * math.sin(2 * math.pi * i / n), 0.05 + 0.9 * i / n) for i in range(n + 1)]


# Signs drawn after the wiki's pictures (Signs Explained), in the bottom-of-ring pose: the center is up.
# Directional and semi-directional ones point to the center; drawn turned around, they are inverted.
OWN_SIGNS = {
    # Pulling: a line with an arrowhead and a chevron pointing to the center (the wiki: pulls when it
    # points inwards)
    "pull": [line((0.5, 1.0), (0.5, 0.05)), line((0.32, 0.62), (0.5, 0.32), (0.68, 0.62), (0.32, 0.62)),
             line((0.25, 0.3), (0.5, 0.05), (0.75, 0.3))],
    # Crushing: a zigzag whose two peaks point outwards (the Wall Breaker's M on top of the ring, W under it);
    # peaks pointing to the center: inverted (Integration)
    "crush": [line((0.0, 0.3), (0.25, 0.75), (0.5, 0.3), (0.75, 0.75), (1.0, 0.3))],
    # Piercing ("Bolt"): a line through a small diamond
    "pierce": [line((0.5, 0.0), (0.5, 1.0)), line((0.5, 0.33), (0.62, 0.5), (0.5, 0.67), (0.38, 0.5), (0.5, 0.33))],
    # Crosshair: four strokes of a cross with an empty middle
    "crosshair": [line((0.5, 0.0), (0.5, 0.4)), line((0.5, 0.6), (0.5, 1.0)), line((0.0, 0.5), (0.4, 0.5)),
                  line((0.6, 0.5), (1.0, 0.5))],
    # Expansion: a corner of the wiki's Enlarge sign - two nested corners pointing outwards (grow);
    # pointing to the center they shrink
    "expansion": [line((0.1, 0.2), (0.5, 0.6), (0.9, 0.2)), line((0.1, 0.5), (0.5, 0.9), (0.9, 0.5))],
    # Stability and Level Planes: two parallel waves
    "stability": [wave(0.3), wave(0.7)],
}


def levitation(arrow, base=1.0):
    """the levitation sign with an arrowhead and a base of 'arrow' and 'base' times the simulator's size"""
    a, b = 0.26 * arrow, 0.32 * base
    return [line((0.5 - a, 0.1 + a), (0.5, 0.1), (0.5 + a, 0.1 + a)), line((0.5, 0.1), (0.5, 0.78)), line((0.5 - b, 0.78), (0.5 + b, 0.78))]


# More ways the same sign gets drawn: hands draw levitation as an arrow, its head and base much smaller
# than the simulator's (seal.lua wants these with all three strokes)
VARIANTS = {
    "levitation": [levitation(0.5), levitation(0.5, 0.4)],
    # a long stem on a short base: without a head it is still a column, not an arrow-like levitation
    "column": [[line((0.5, 0.1), (0.5, 0.78)), line((0.36, 0.78), (0.64, 0.78))]],
}

# ... and sigils: fire with long horns standing apart from the sides of the triangle
SIGIL_VARIANTS = {
    "fire": [[line((0.5, 0.1), (0.9, 0.72), (0.1, 0.72), (0.5, 0.1)), line((0.5, 0.72), (0.5, 0.95)),
              line((0.25, 0.46), (0.07, 0.28)), line((0.75, 0.46), (0.93, 0.28))]],
}


# Sigils whose own drawing comes before the simulator's: the first drawing is the one shown on the book's pages,
# in its legend and in the air, so it should be the manga's. Both are still recognized.
PRIMARY_VARIANTS = {"earth"}


def main():
    sigils = load("sigils.json")
    signs = load("signs.json")
    lines = [
        "-- Generated by tools/import_templates.py - do not edit by hand.",
        "-- Stroke templates in unit coordinates (y down); a one-point stroke is a dot. Sigils and frames are",
        "-- drawn upright; signs in the pose they have at the bottom of the ring, facing the center (up); the",
        "-- glaive outside the ring at its bottom. The five element sigils and the column, levitation and",
        "-- convergence signs: wha-spell-simulator (MIT, (c) 2026 Nervadof); the rest after the Independent",
        "-- Witch Hat Atelier Wiki drawings (tools/shapes.py).",
        "",
        "TEMPLATES_SIGILS = {",
    ]
    for src_id, key in SIGIL_IDS.items():
        variants = SIGIL_VARIANTS.get(key, []) + shapes.SIGIL_VARIANTS.get(key, [])
        forms = [lua_shape(sigils[src_id]["strokeTemplate"]["strokes"])] + [lua_shape(v, traced=False) for v in variants]
        if key in PRIMARY_VARIANTS:
            forms = forms[1:] + forms[:1]
        lines.append(f"\t{key} = {{ {', '.join(forms)} }},")
    for key, strokes in shapes.SIGILS.items():
        lines.append(f"\t{key} = {{ {lua_shape(strokes, traced=False)} }},")
    lines.append("}")
    lines.append("")
    lines.append("TEMPLATES_SIGNS = {")
    for key in ["column", "levitation", "convergence"]:
        forms = [lua_shape(signs[key]["strokeTemplate"]["strokes"])] + [lua_shape(v, traced=False) for v in VARIANTS.get(key, [])]
        lines.append(f"\t{key} = {{ {', '.join(forms)} }},")
    column = [resample(s) for s in signs["column"]["strokeTemplate"]["strokes"]]
    ys = [y for s in column for _, y in s]
    base = max(ys)
    arc = [(0.5 + 0.28 * math.cos(a), base + 0.06 + 0.16 * math.sin(a)) for a in [math.pi * i / 20 for i in range(21)]]
    lines.append(f"\tdispersion = {{ {lua_shape(column + [arc[::-1]])} }},")
    for key, strokes in OWN_SIGNS.items():
        lines.append(f"\t{key} = {{ {lua_shape(strokes, traced=False)} }},")
    for key, strokes in shapes.SIGNS.items():
        lines.append(f"\t{key} = {{ {lua_shape(strokes, traced=False)} }},")
    lines.append("}")
    lines.append("")
    lines.append(f"TEMPLATES_GLAIVE = {lua_shape(shapes.GLAIVE, traced=False)}")
    lines.append("")
    lines.append("TEMPLATES_FRAMES = {")
    for key, strokes in shapes.FRAMES.items():
        lines.append(f"\t{key} = {{ {lua_shape(strokes, traced=False)} }},")
    lines.append("}")
    out = os.path.join(MOD, "files", "templates.lua")
    open(out, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    print("written", out)


if __name__ == "__main__":
    main()
