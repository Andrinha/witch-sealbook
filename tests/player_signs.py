"""Signs drawn as players draw them, to test reading them (tests/bench_player_signs.py, test_player_signs.py).

A test that redraws a sign from the mod's own template measures the template against itself (tests/run_tests.py
test_symbols does that). Players draw from the wiki's pictures (Signs Explained), the manga's seals and the book's legend,
in any stroke order, lifting the pen at any corner, with a hand's proportions. So here a sign is
  - the wiki's picture, measured off it (units: the picture's bigger side) in the picture's own pose, then turned into
    the pose a sign has at the bottom of the ring - the center of the seal up ("wiki", and a few more ways the wiki or the
    manga draw it);
  - the book's legend: the sign's first template, as the book shows it ("book"), and the legend players learned before
    the template was redrawn ("old");
drawn as a graph of lines: every corner is a node where the pen may stop or turn; a stroke runs on along the lines from
node to node, or the pen lifts. Then the hand: the corners a little off, ends that miss their joint, the whole stretched,
sheared and tilted, a tremor (run_tests.place).
"""
import math
import os
import random
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_tests as fx  # noqa: E402

# ---- shape helpers (y down) ----


def spline(pts, per=8):
    """a smooth curve through pts (Catmull-Rom)"""
    out = []
    p = [pts[0]] + list(pts) + [pts[-1]]
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for k in range(per):
            t = k / per
            out.append(tuple(0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t ** 3) for j in (0, 1)))
    out.append(pts[-1])
    return out


def arc_pts(cx, cy, rx, a0, a1, ry=None, n=16):
    ry = ry or rx
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n)))
            for i in range(n + 1)]


def P(*pts):
    """a polyline: each of its corners is a place the pen may stop or turn at"""
    return {"pts": list(pts), "curve": False}


def C(pts):
    """a curve: the pen stops only at its ends"""
    return {"pts": list(pts), "curve": True}


def D(x, y):
    return {"pts": [(x, y)], "curve": False, "dot": True}


def circle(cx, cy, rx, ry=None, start=-90):
    return C(arc_pts(cx, cy, rx, start, start + 360, ry, n=24))


# ---- the wiki's pictures, in their own pose: { sign: { variant: lines } } ----

WIKI_POSE = {
    "column": {"wiki": [P((0.5, 0.0), (0.5, 0.93)), P((0.03, 0.93), (0.96, 0.93))]},
    "dispersion": {"wiki": [P((0.36, 0.0), (0.36, 0.67)), P((0.02, 0.67), (0.68, 0.67)), C(arc_pts(0.345, 0.5, 0.45, 140, 40, 0.45))]},
    "levitation": {"wiki": [P((0.03, 0.43), (0.32, 0.02), (0.6, 0.42)), P((0.32, 0.02), (0.32, 0.95)), P((0.03, 0.95), (0.67, 0.95))],
                   # the arrow players draw: a small head
                   "small": [P((0.2, 0.15), (0.32, 0.02), (0.44, 0.15)), P((0.32, 0.02), (0.32, 0.95)), P((0.1, 0.95), (0.54, 0.95))]},
    "convergence": {"wiki": [P((0.02, 0.05), (0.98, 0.05), (0.5, 0.85), (0.02, 0.05))]},
    # the picture points down: away from the middle
    "pull": {"wiki": [P((0.34, 0.02), (0.34, 0.99)), P((0.14, 0.51), (0.54, 0.51), (0.34, 0.78), (0.14, 0.51)),
                      P((0.03, 0.66), (0.34, 0.99), (0.62, 0.65))]},
    # the picture is the sign at the top of the ring: its peaks point outwards, up
    "crush": {"wiki": [P((0.0, 0.33), (0.27, 0.03), (0.51, 0.33), (0.75, 0.03), (1.0, 0.33))]},
    "pierce": {"wiki": [P((0.16, 0.02), (0.16, 0.98)), P((0.16, 0.36), (0.28, 0.5), (0.16, 0.66), (0.03, 0.5), (0.16, 0.36))]},
    "crosshair": {"wiki": [P((0.38, 0.02), (0.38, 0.4)), P((0.38, 0.58), (0.38, 0.98)), P((0.02, 0.5), (0.3, 0.5)), P((0.47, 0.5), (0.76, 0.5))]},
    # one corner of the Enlarge picture (the top left one, pointing up and left: outwards)
    "expansion": {"wiki": [P((0.42, 0.03), (0.03, 0.03), (0.03, 0.4)), P((0.42, 0.13), (0.12, 0.13), (0.12, 0.4)),
                           P((0.42, 0.22), (0.22, 0.22), (0.22, 0.4))],
                  "two": [P((0.42, 0.03), (0.03, 0.03), (0.03, 0.42)), P((0.42, 0.18), (0.18, 0.18), (0.18, 0.42))]},
    "stability": {"wiki": [C(spline([(0.21, 0.03), (0.09, 0.2), (0.1, 0.38), (0.24, 0.52), (0.26, 0.7), (0.14, 0.97)])),
                           C(spline([(0.43, 0.03), (0.31, 0.2), (0.32, 0.38), (0.46, 0.52), (0.48, 0.7), (0.36, 0.97)]))]},
    "regions": {"wiki": [P((0.02, 0.67), (0.51, 0.03), (1.0, 0.67))]},
    "sights": {"wiki": [P((0.18, 0.0), (0.18, 0.7), (0.18, 0.98)), P((0.03, 0.17), (0.18, 0.0), (0.33, 0.17)),
                        P((0.18, 0.7), (0.33, 0.84), (0.18, 0.98), (0.03, 0.84), (0.18, 0.7))]},
    "strengthen": {"wiki": [P((0.52, 0.02), (0.97, 0.82), (0.04, 0.82), (0.52, 0.02)), P((0.0, 0.48), (1.0, 0.48))]},
    "entwine": {"wiki": [P((0.03, 0.02), (0.03, 0.28), (0.57, 0.28), (0.57, 0.02)), P((0.3, 0.28), (0.3, 0.95)),
                         P((0.03, 0.7), (0.03, 0.95), (0.57, 0.95), (0.57, 0.7))]},
    "detection": {"wiki": [P((0.04, 0.35), (0.04, 0.68)), P((0.3, 0.23), (0.3, 0.8)), P((0.55, 0.02), (0.55, 0.98))]},
    "partition": {"wiki": [P((0.03, 0.4), (0.17, 0.2), (0.84, 0.2), (0.98, 0.4)), P((0.08, 0.57), (0.2, 0.37), (0.82, 0.37), (0.97, 0.57)),
                           P((0.43, 0.2), (0.51, 0.05), (0.6, 0.2))]},
    "refuse": {"wiki": [P((0.36, 0.02), (0.7, 0.33), (0.36, 0.67), (0.08, 0.97)), P((0.36, 0.02), (0.03, 0.33), (0.36, 0.67), (0.64, 0.97))]},
    "solidify": {"wiki": [circle(0.17, 0.17, 0.15, start=90), P((0.17, 0.32), (0.17, 0.68)), circle(0.17, 0.83, 0.15, start=-90)]},
    "binding": {"wiki": [C(arc_pts(0.5, 0.6, 0.58, 214, 326)), C(arc_pts(0.525, 0.59, 0.21, 194, 346))]},
    "envelop": {"wiki": [P((0.5, 0.28), (0.27, 0.02), (0.27, 0.97), (0.02, 0.7))]},
    "immobility": {"wiki": [C(arc_pts(0.5, 0.45, 0.47, 241, 119, 0.32)), C(arc_pts(0.5, 0.45, 0.47, -61, 61, 0.32)),
                            P((0.5, 0.02), (0.5, 0.97)), P((0.02, 0.97), (0.98, 0.97))]},
    "pointing": {"wiki": [P((0.26, 0.42), (0.5, 0.01), (0.74, 0.42)),
                          C(spline([(0.05, 0.21), (0.02, 0.1), (0.1, 0.03), (0.19, 0.06), (0.17, 0.23), (0.5, 0.23), (0.83, 0.23),
                                    (0.81, 0.06), (0.9, 0.03), (0.98, 0.1), (0.95, 0.21)]))]},
    "mimicry": {"wiki": [P((0.16, 0.01), (0.16, 0.99)), C(spline([(0.29, 0.07), (0.12, 0.05), (0.03, 0.13), (0.1, 0.22), (0.29, 0.24)])),
                         circle(0.16, 0.45, 0.1), C(spline([(0.05, 0.87), (0.07, 0.72), (0.16, 0.63), (0.25, 0.72), (0.27, 0.86)]))]},
    # the picture has its bar up: its open side faces down, away from the middle
    "collection": {"wiki": [P((0.03, 0.03), (0.84, 0.95)), P((0.85, 0.03), (0.03, 0.95)), P((0.03, 0.03), (0.85, 0.03))]},
    # an arrow on legs: the stem runs from the arrow's tip down to where the legs part
    "gathering": {"wiki": [P((0.03, 0.4), (0.42, 0.02), (0.8, 0.38)), P((0.42, 0.02), (0.42, 0.52)), P((0.04, 0.97), (0.42, 0.52), (0.8, 0.97))],
                  # the Vapor Bubble seal's: a big arrowhead, a small fork at the stem's end
                  "vapor": [P((0.0, 0.64), (0.49, 0.0), (0.98, 0.64)), P((0.49, 0.0), (0.49, 0.68)), P((0.17, 1.0), (0.49, 0.68), (0.81, 1.0))]},
    "diamond": {"wiki": [P((0.35, 0.03), (0.67, 0.5), (0.35, 0.97), (0.03, 0.5), (0.35, 0.03))]},
    "orb": {"wiki": [circle(0.41, 0.5, 0.38, 0.37), P((0.41, 0.02), (0.41, 0.98))]},
    "purify": {"wiki": [C(spline([(0.25, 0.03), (0.42, 0.22), (0.51, 0.45), (0.5, 0.65), (0.42, 0.84), (0.27, 0.95), (0.12, 0.94),
                                  (0.04, 0.84), (0.07, 0.72), (0.16, 0.66), (0.27, 0.68)]))]},
    "link": {"wiki": [P((0.02, 0.25), (0.26, 0.47), (0.5, 0.21), (0.78, 0.49), (1.0, 0.28)), P((0.3, 0.02), (0.73, 0.02), (0.5, 0.21), (0.3, 0.02)),
                      P((0.16, 0.14), (0.37, 0.32)), P((0.86, 0.14), (0.64, 0.32))]},
    "stillness": {"wiki": [P((0.31, 0.02), (0.31, 0.98)), C(spline([(0.04, 0.03), (0.04, 0.27), (0.12, 0.35), (0.5, 0.35), (0.58, 0.27), (0.58, 0.03)])),
                           P((0.12, 0.5), (0.5, 0.5)), C(spline([(0.04, 0.98), (0.04, 0.75), (0.12, 0.65), (0.5, 0.65), (0.58, 0.75), (0.58, 0.98)]))]},
    "projection": {"wiki": [P((0.03, 0.33), (0.03, 0.03), (0.98, 0.03), (0.98, 0.33))]},
    "cooling": {"wiki": [P((0.35, 0.02), (0.35, 0.98)), D(0.07, 0.22), D(0.65, 0.22), D(0.07, 0.78), D(0.65, 0.78)]},
    "coil": {"wiki": [C(spline([(0.02, 0.02), (0.11, 0.13), (0.2, 0.35), (0.2, 0.6), (0.11, 0.87), (0.02, 0.97)])),
                      C(spline([(0.22, 0.02), (0.11, 0.13), (0.02, 0.35), (0.02, 0.6), (0.11, 0.87), (0.22, 0.97)]))]},
    "reflection": {"wiki": [P((0.03, 0.03), (0.57, 0.03), (0.03, 0.97), (0.57, 0.97), (0.03, 0.03))]},
    "windsign": {"wiki": [C(spline([(0.1, 0.33), (0.3, 0.33), (0.37, 0.22), (0.3, 0.06), (0.18, 0.03), (0.06, 0.1), (0.04, 0.3), (0.08, 0.5),
                                    (0.2, 0.72), (0.37, 0.96)]))]},
    "aeriform": {"wiki": [P((0.43, 0.02), (0.43, 0.98)), P((0.03, 0.5), (0.2, 0.97)), P((0.83, 0.55), (0.65, 0.97))]},
}

# how a picture is turned into the bottom-of-ring pose: flipped upside down, or turned (degrees, clockwise on screen)
POSE = {"pull": "flip", "crush": "flip", "collection": "flip", "expansion": -135}


def _posed(lines, pose):
    if not pose:
        return lines
    xs = [x for l in lines for x, _ in l["pts"]]
    ys = [y for l in lines for _, y in l["pts"]]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    if pose == "flip":
        f = lambda p: (p[0], 2 * cy - p[1])
    else:
        a = math.radians(pose)
        f = lambda p: (cx + (p[0] - cx) * math.cos(a) - (p[1] - cy) * math.sin(a), cy + (p[0] - cx) * math.sin(a) + (p[1] - cy) * math.cos(a))
    return [dict(l, pts=[f(p) for p in l["pts"]]) for l in lines]


SHAPES = {key: {v: _posed(lines, POSE.get(key)) for v, lines in variants.items()} for key, variants in WIKI_POSE.items()}

# the book's legend before a sign was redrawn after the wiki (tools/shapes.py), where players who learned it still get
# the sign. Gone: Gathering's stem through two arrowheads (until 2026-10-12) - it is the wiki's Pulling, an arrow on a
# triangle, more than the wiki's Gathering
OLD = {
    "sights": [P((0.5, 0.08), (0.5, 0.66)), P((0.3, 0.3), (0.5, 0.08), (0.7, 0.3)), P((0.5, 0.66), (0.63, 0.8), (0.5, 0.94), (0.37, 0.8), (0.5, 0.66))],
    "strengthen": [P((0.5, 0.12), (0.83, 0.82), (0.17, 0.82), (0.5, 0.12)), P((0.0, 0.6), (1.0, 0.6))],
    "entwine": [P((0.2, 0.04), (0.2, 0.2), (0.8, 0.2), (0.8, 0.04)), P((0.5, 0.2), (0.5, 0.8)), P((0.2, 0.96), (0.2, 0.8), (0.8, 0.8), (0.8, 0.96))],
    "detection": [P((0.22, 0.4), (0.22, 0.85)), P((0.5, 0.05), (0.5, 0.95)), P((0.78, 0.25), (0.78, 0.75))],
    "partition": [P((0.02, 0.78), (0.24, 0.42), (0.76, 0.42), (0.98, 0.78)), P((0.14, 0.95), (0.32, 0.62), (0.68, 0.62), (0.86, 0.95)),
                  P((0.38, 0.42), (0.5, 0.22), (0.62, 0.42))],
    "binding": [C(arc_pts(0.5, 0.85, 0.45, 180, 360)), C(arc_pts(0.5, 0.85, 0.2, 195, 345))],
    "immobility": [circle(0.5, 0.42, 0.28), P((0.5, 0.06), (0.5, 0.88)), P((0.18, 0.88), (0.82, 0.88))],
    "pointing": [C(spline([(0.0, 0.62), (0.08, 0.48), (0.2, 0.56), (0.5, 0.56), (0.8, 0.56), (0.92, 0.48), (1.0, 0.62)])),
                 P((0.28, 0.92), (0.5, 0.24), (0.72, 0.92))],
    "mimicry": [P((0.5, 0.04), (0.5, 0.96)), C(spline([(0.64, 0.1), (0.44, 0.1), (0.4, 0.2), (0.56, 0.26), (0.6, 0.34), (0.4, 0.38)])),
                circle(0.5, 0.55, 0.1), C(spline([(0.28, 0.96), (0.34, 0.8), (0.5, 0.72), (0.66, 0.8), (0.72, 0.96)]))],
    "link": [P((0.02, 0.2), (0.3, 0.85), (0.5, 0.38), (0.7, 0.85), (0.98, 0.2)), P((0.36, 0.08), (0.64, 0.08), (0.5, 0.28), (0.36, 0.08))],
    "projection": [P((0.1, 0.85), (0.1, 0.25), (0.9, 0.25), (0.9, 0.85))],
    "aeriform": [P((0.5, 0.08), (0.5, 0.92)), P((0.16, 0.12), (0.38, 0.88)), P((0.84, 0.12), (0.62, 0.88))],
    "stability": [C([(0.3 + 0.1 * math.sin(2 * math.pi * i / 24), 0.05 + 0.9 * i / 24) for i in range(25)]),
                  C([(0.7 + 0.1 * math.sin(2 * math.pi * i / 24), 0.05 + 0.9 * i / 24) for i in range(25)])],
    "purify": [C(spline([(0.46, 0.04), (0.3, 0.2), (0.28, 0.45), (0.4, 0.7), (0.6, 0.8), (0.74, 0.66), (0.66, 0.52), (0.52, 0.56)]))],
}
for _key, _lines in OLD.items():
    SHAPES[_key]["old"] = _lines

# ---- a player's strokes ----


def graph(lines):
    """nodes and edges of a drawing: every corner of a polyline is a node, a curve is one edge"""
    nodes, edges, dots = [], [], []

    def node(p):
        for i, q in enumerate(nodes):
            if math.dist(p, q) < 1e-6:
                return i
        nodes.append(p)
        return len(nodes) - 1

    for line in lines:
        if line.get("dot"):
            dots.append(node(line["pts"][0]))
            continue
        pts = line["pts"]
        if line["curve"]:
            a, b = node(pts[0]), node(pts[-1])
            edges.append({"a": a, "b": b, "mid": pts[1:-1]})
        else:
            for p, q in zip(pts, pts[1:]):
                edges.append({"a": node(p), "b": node(q), "mid": []})
    return nodes, edges, dots


def strokes_of(lines, rng, keep=0.4, corner=0.85, junction=0.5):
    """the order and the pen lifts a player draws 'lines' with: as listed (keep), or edge by edge - from a free end mostly,
    on to an undrawn edge at a corner (a node of two edges) with probability 'corner', where more edges meet 'junction'"""
    nodes, edges, dots = graph(lines)
    if rng.random() < keep:
        out = [list(line["pts"]) for line in lines]
        rng.shuffle(out)
        return [list(reversed(s)) if rng.random() < 0.5 else s for s in out], nodes
    left = set(range(len(edges)))
    degree = [0] * len(nodes)
    for e in edges:
        degree[e["a"]] += 1
        degree[e["b"]] += 1
    out = []
    while left:
        ends = [i for i in left if degree[edges[i]["a"]] == 1 or degree[edges[i]["b"]] == 1]
        i = rng.choice(sorted(ends)) if ends and rng.random() < 0.7 else rng.choice(sorted(left))
        e = edges[i]
        forward = degree[e["a"]] == 1 if degree[e["a"]] != degree[e["b"]] else rng.random() < 0.5
        at = e["a"] if forward else e["b"]
        stroke = [nodes[at]]
        while True:
            left.discard(i)
            e = edges[i]
            mid = e["mid"] if at == e["a"] else list(reversed(e["mid"]))
            at = e["b"] if at == e["a"] else e["a"]
            stroke += mid + [nodes[at]]
            nxt = [j for j in left if at in (edges[j]["a"], edges[j]["b"])]
            if not nxt or rng.random() > (corner if degree[at] == 2 else junction):
                break
            i = rng.choice(sorted(nxt))
        out.append(stroke)
    for d in dots:
        out.append([nodes[d]])
    rng.shuffle(out)
    return out, nodes


def hand_shape(strokes, nodes, rng, wobble=0.03, miss=0.02, stretch=0.15, shear=0.1, tilt=10):
    """A hand's version: its corners a little off (joints shared by strokes may miss each other a little), the whole
    stretched, sheared and tilted"""
    moved = {i: (rng.gauss(0, wobble), rng.gauss(0, wobble)) for i in range(len(nodes))}

    def shift(p):
        for i, q in enumerate(nodes):
            if math.dist(p, q) < 1e-6:
                return moved[i]
        return None

    out = []
    for s in strokes:
        a, b = shift(s[0]) or (0, 0), shift(s[-1]) or (0, 0)
        line = []
        for k, p in enumerate(s):
            d = shift(p)
            if d is None:  # a curve's inside follows its ends
                t = k / max(1, len(s) - 1)
                d = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            line.append((p[0] + d[0], p[1] + d[1]))
        # the stroke's own ends miss the joint a little
        if len(line) > 1:
            line[0] = (line[0][0] + rng.gauss(0, miss), line[0][1] + rng.gauss(0, miss))
            line[-1] = (line[-1][0] + rng.gauss(0, miss), line[-1][1] + rng.gauss(0, miss))
        out.append(line)
    sx, sy = rng.uniform(1 - stretch, 1 + stretch), rng.uniform(1 - stretch, 1 + stretch)
    sh, a = rng.uniform(-shear, shear), math.radians(rng.uniform(-tilt, tilt))
    ca, sa = math.cos(a), math.sin(a)
    res = []
    for s in out:
        line = []
        for x, y in s:
            x, y = (x - 0.5) * sx + (y - 0.5) * sh, (y - 0.5) * sy
            line.append((0.5 + x * ca - y * sa, 0.5 + x * sa + y * ca))
        res.append(line)
    return res


def player_sign(key, variant, rng, **kw):
    lines = SHAPES[key][variant]
    strokes, nodes = strokes_of(lines, rng)
    return hand_shape(strokes, nodes, rng, **kw)


def add_book(lua):
    """the book's legend: each sign's first template, its strokes drawn whole (the template's resampling lost its corners)"""
    t = fx.templates(lua)
    for key in lua.eval("DICTIONARY_SIGN_ORDER").values():
        SHAPES.setdefault(key, {})["book"] = [C(s) if len(s) > 1 else D(*s[0]) for s in t[("sign", key)]]


# ---- seals with player signs, read ----


def player_seal(lua, key, variant, rng, count=2, sigil="fire", inverted=False, size=(0.18, 0.34), dist=(0.58, 0.76)):
    """a ring around 'sigil' (the mod's template, by hand) and 'count' of the sign evenly around it, facing the middle
    (turned around: 'inverted'), each drawn anew"""
    random.seed(rng.random())  # run_tests' hand and place draw from random
    t = fx.templates(lua)
    rstroke, (cx, cy, r) = fx.ring()
    strokes = [rstroke] + fx.place(fx.hand(t[("sigil", sigil)]), cx, cy, r * random.uniform(0.4, 0.5))
    base = rng.uniform(0, 360)
    for k in range(count):
        a = math.radians(base + 360 * k / count + rng.uniform(-6, 6))
        d = rng.uniform(*dist) * r
        strokes += fx.place(player_sign(key, variant, rng), cx + d * math.cos(a), cy + d * math.sin(a), r * rng.uniform(*size),
                            a - math.pi / 2 + (math.pi if inverted else 0) + math.radians(rng.uniform(-8, 8)), tilt=0)
    random.shuffle(strokes)
    return strokes


def read_signs(lua, strokes):
    """-> spell or None, why not, the signs read"""
    res = lua.eval("parse_seal")(fx.lua_strokes(lua, strokes))
    tree, err = (res[0], res[1]) if isinstance(res, tuple) else (res, None)
    if not tree:
        return None, err, []
    signs = [s for s in tree["symbols"].values() if s["kind"] == "sign"]
    res = lua.eval("compile_spell")(tree)
    spell, err = res if isinstance(res, tuple) else (res, None)
    return spell, err, signs


def trial(lua, key, variant, n, seed, count=2, inverted=False):
    """n seals with the sign: how many cast with all of them read right, what they were read as, why the others failed"""
    rng = random.Random(seed)
    same = not fx.invertible(lua, key)  # looks or means the same turned around
    right, read_as, failed = 0, Counter(), Counter()
    for _ in range(n):
        spell, err, signs = read_signs(lua, player_seal(lua, key, variant, rng, count=count, inverted=inverted))
        for s in signs:
            read_as[s["key"] + ("~" if s["inverted"] and not (s["key"] == key and same) else "")] += 1
        good = spell is not None and len(signs) == count and all(s["key"] == key and (same or bool(s["inverted"]) == inverted) for s in signs)
        right += good
        if not good:
            failed[err or "wrong signs"] += 1
    return right, read_as, failed
