"""Shapes of the vocabulary the book recognizes, drawn after the Independent Witch Hat Atelier Wiki's pictures
(Signs Explained, Sigils Explained and the spells' redraws) the way a hand would draw them: simplified,
in a few strokes. import_templates.py writes them into files/templates.lua next to the shapes taken from
wha-spell-simulator.

Unit coordinates, y down. Signs are drawn in the pose they have at the bottom of the ring facing the center
(pointing up); sigils and frames upright. A dot is a one-point stroke.
"""
import math


def _dense(pts, step=0.03):
    out = [pts[0]]
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        n = max(1, int(math.dist((ax, ay), (bx, by)) / step))
        out += [(ax + (bx - ax) * i / n, ay + (by - ay) * i / n) for i in range(1, n + 1)]
    return out


def line(*pts):
    """a polyline through the points"""
    return _dense(list(pts))


def curve(*pts, per=8):
    """a smooth line through the points (Catmull-Rom)"""
    pts = list(pts)
    ext = [pts[0]] + pts + [pts[-1]]
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in (0, 1)))
    out.append(pts[-1])
    return _dense(out)


def arc(cx, cy, r, a0, a1, ry=None, n=None):
    """an arc of a circle (or an ellipse with ry) from angle a0 to a1, degrees: 0 - right, 90 - down"""
    ry = ry if ry is not None else r
    n = n or max(6, int(abs(a1 - a0) / 8))
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n)))
            for i in range(n + 1)]


def circle(cx, cy, r, ry=None, start=-90):
    return arc(cx, cy, r, start, start + 360, ry)


def spiral(cx, cy, r0, r1, a0, turns, n=None):
    """from radius r0 at angle a0, 'turns' times around (positive: clockwise on screen) to radius r1"""
    n = n or max(12, int(abs(turns) * 36))
    return [(cx + (r0 + (r1 - r0) * i / n) * math.cos(math.radians(a0 + 360 * turns * i / n)),
             cy + (r0 + (r1 - r0) * i / n) * math.sin(math.radians(a0 + 360 * turns * i / n))) for i in range(n + 1)]


def dot(x, y):
    return [(x, y)]


def mirror_x(strokes):
    return [[(1 - x, y) for x, y in s] for s in strokes]


def rotate(strokes, deg, cx=0.5, cy=0.5):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [[(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in st] for st in strokes]


def star(cx, cy, r_out, r_in, points, start=-90):
    pts = []
    for i in range(2 * points + 1):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(start + 180 * i / points)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return line(*pts)


def polygon(cx, cy, r, sides, start=-90):
    return line(*[(cx + r * math.cos(math.radians(start + 360 * i / sides)), cy + r * math.sin(math.radians(start + 360 * i / sides)))
                  for i in range(sides + 1)])


# ---------------------------------------------------------------- signs (bottom of the ring, facing up)

SIGNS = {
    # Regions: a chevron pointing where the magic manifests (the wiki's Direction); pointing outwards it is
    # also the Launch sign of the Bird of Light Beacon
    "regions": [line((0.12, 0.8), (0.5, 0.22), (0.88, 0.8))],
    # Sights Set: an arrow with a diamond at its tail
    "sights": [line((0.5, 0.08), (0.5, 0.66)), line((0.3, 0.3), (0.5, 0.08), (0.7, 0.3)),
               line((0.5, 0.66), (0.63, 0.8), (0.5, 0.94), (0.37, 0.8), (0.5, 0.66))],
    # Strengthening: a triangle crossed by a long bar
    "strengthen": [line((0.5, 0.12), (0.83, 0.82), (0.17, 0.82), (0.5, 0.12)), line((0.0, 0.6), (1.0, 0.6))],
    # Entwining: an I-beam whose bars turn up at the top and down at the bottom
    "entwine": [line((0.2, 0.04), (0.2, 0.2), (0.8, 0.2), (0.8, 0.04)), line((0.5, 0.2), (0.5, 0.8)),
                line((0.2, 0.96), (0.2, 0.8), (0.8, 0.8), (0.8, 0.96))],
    # Detection: three upright lines of different lengths
    "detection": [line((0.22, 0.4), (0.22, 0.85)), line((0.5, 0.05), (0.5, 0.95)), line((0.78, 0.25), (0.78, 0.75))],
    # Partition: a roof over a roof with a small triangle on top
    "partition": [line((0.02, 0.78), (0.24, 0.42), (0.76, 0.42), (0.98, 0.78)), line((0.14, 0.95), (0.32, 0.62), (0.68, 0.62), (0.86, 0.95)),
                  line((0.38, 0.42), (0.5, 0.22), (0.62, 0.42))],
    # Refuse: a diamond whose lower sides cross into legs
    "refuse": [line((0.5, 0.05), (0.78, 0.4), (0.2, 0.95)), line((0.5, 0.05), (0.22, 0.4), (0.8, 0.95))],
    # Solidification: a line with a circle at each end
    "solidify": [circle(0.5, 0.16, 0.13), line((0.5, 0.29), (0.5, 0.71)), circle(0.5, 0.84, 0.13)],
    # Binding: two arcs, a small one under a big one
    "binding": [arc(0.5, 0.85, 0.45, 180, 360), arc(0.5, 0.85, 0.2, 195, 345)],
    # Envelopment: a stem with a hook at the top and a slant at the bottom
    "envelop": [line((0.82, 0.32), (0.55, 0.05), (0.55, 0.95), (0.18, 0.6))],
    # Immobility: a circle split by a line standing on a base
    "immobility": [circle(0.5, 0.42, 0.28), line((0.5, 0.06), (0.5, 0.88)), line((0.18, 0.88), (0.82, 0.88))],
    # Pointing: a caret with a wavy line through it
    "pointing": [curve((0.0, 0.62), (0.08, 0.48), (0.2, 0.56), (0.5, 0.56), (0.8, 0.56), (0.92, 0.48), (1.0, 0.62)),
                 line((0.28, 0.92), (0.5, 0.24), (0.72, 0.92))],
    # Mimicry: a stem with an S-curl, a ring and a fork
    "mimicry": [line((0.5, 0.04), (0.5, 0.96)), curve((0.64, 0.1), (0.44, 0.1), (0.4, 0.2), (0.56, 0.26), (0.6, 0.34), (0.4, 0.38)),
                circle(0.5, 0.55, 0.1), curve((0.28, 0.96), (0.34, 0.8), (0.5, 0.72), (0.66, 0.8), (0.72, 0.96))],
    # Collection: a cross with a bar on its outer side, the open side faces the center
    "collection": [line((0.15, 0.1), (0.85, 0.9)), line((0.85, 0.1), (0.15, 0.9)), line((0.15, 0.9), (0.85, 0.9))],
    # Gathering: a stem with two chevrons
    "gathering": [line((0.5, 0.96), (0.5, 0.12)), line((0.2, 0.42), (0.5, 0.12), (0.8, 0.42)), line((0.2, 0.7), (0.5, 0.4), (0.8, 0.7))],
    # Diamond
    "diamond": [line((0.5, 0.05), (0.88, 0.5), (0.5, 0.95), (0.12, 0.5), (0.5, 0.05))],
    # Orb: a circle with a line through it
    "orb": [circle(0.5, 0.5, 0.32), line((0.5, 0.02), (0.5, 0.98))],
    # Purification: a hooked curl
    "purify": [curve((0.46, 0.04), (0.3, 0.2), (0.28, 0.45), (0.4, 0.7), (0.6, 0.8), (0.74, 0.66), (0.66, 0.52), (0.52, 0.56))],
    # Link: a W with a small triangle
    "link": [line((0.02, 0.2), (0.3, 0.85), (0.5, 0.38), (0.7, 0.85), (0.98, 0.2)), line((0.36, 0.08), (0.64, 0.08), (0.5, 0.28), (0.36, 0.08))],
    # Stillness: a stem through a cup, a bar and an arch
    "stillness": [line((0.5, 0.05), (0.5, 0.95)), line((0.22, 0.08), (0.22, 0.3), (0.78, 0.3), (0.78, 0.08)), line((0.25, 0.5), (0.75, 0.5)),
                  line((0.22, 0.95), (0.22, 0.72), (0.78, 0.72), (0.78, 0.95))],
    # Projection: a bracket
    "projection": [line((0.1, 0.85), (0.1, 0.25), (0.9, 0.25), (0.9, 0.85))],
    # Cooling: a line between four dots
    "cooling": [line((0.5, 0.05), (0.5, 0.95)), dot(0.22, 0.3), dot(0.78, 0.3), dot(0.22, 0.7), dot(0.78, 0.7)],
    # Coil: two curves crossing near their ends
    "coil": [curve((0.3, 0.0), (0.6, 0.25), (0.66, 0.5), (0.6, 0.75), (0.3, 1.0)), curve((0.7, 0.0), (0.4, 0.25), (0.34, 0.5), (0.4, 0.75), (0.7, 1.0))],
    # Reflection: an hourglass
    "reflection": [line((0.2, 0.08), (0.8, 0.08), (0.2, 0.92), (0.8, 0.92), (0.2, 0.08))],
    # Sign of Wind (spiraling wind): a stem curling into a loop, the curl is the way it spins
    "windsign": [curve((0.3, 0.95), (0.28, 0.7), (0.3, 0.45), (0.38, 0.25), (0.52, 0.12), (0.68, 0.14), (0.74, 0.3), (0.64, 0.42), (0.5, 0.4), (0.48, 0.28))],
    # Aeriforms Defined: three lines fanning out, as the rays of the wind sigil
    "aeriform": [line((0.5, 0.08), (0.5, 0.92)), line((0.16, 0.12), (0.38, 0.88)), line((0.84, 0.12), (0.62, 0.88))],
}

# Glaives are drawn outside the ring, their stem touching it: the pose at the bottom of the ring, outside
GLAIVE = [line((0.5, 0.0), (0.5, 0.95)), curve((0.15, 0.98), (0.17, 0.72), (0.32, 0.56), (0.5, 0.52), (0.68, 0.56), (0.83, 0.72), (0.85, 0.98))]

# ---------------------------------------------------------------- sigils (upright, in the center)


def _crystal():
    out = []
    u, v = (1 / math.sqrt(2), 1 / math.sqrt(2)), (1 / math.sqrt(2), -1 / math.sqrt(2))
    for a, b in ((u, v), (v, u)):
        for k in (-0.2, 0.0, 0.2):
            cx, cy = 0.5 + b[0] * k, 0.5 + b[1] * k
            out.append(line((cx - a[0] * 0.42, cy - a[1] * 0.42), (cx + a[0] * 0.42, cy + a[1] * 0.42)))
    return out


def _s_curve(cx=0.5, cy=0.5, h=0.8, w=0.34):
    """the S of the wind sigils"""
    return curve((cx + w * 0.55, cy - h * 0.42), (cx, cy - h * 0.5), (cx - w * 0.5, cy - h * 0.34), (cx - w * 0.3, cy - h * 0.1),
                 (cx + w * 0.3, cy + h * 0.1), (cx + w * 0.5, cy + h * 0.34), (cx, cy + h * 0.5), (cx - w * 0.55, cy + h * 0.42))


def _eye(cx, cy, w=0.1, h=0.05):
    return [line((cx - w, cy), (cx, cy - h), (cx + w, cy), (cx, cy + h), (cx - w, cy)), dot(cx, cy)]


SIGILS = {
    # Crystalize: a lattice of crossing lines (Crystal Shard, Icy Road, Frozen Path)
    "crystal": _crystal(),
    # Smoke: a cloud with a curl inside
    "smoke": [curve((0.62, 0.8), (0.3, 0.84), (0.1, 0.7), (0.1, 0.48), (0.22, 0.3), (0.38, 0.3), (0.46, 0.14), (0.66, 0.1), (0.8, 0.24),
                    (0.94, 0.36), (0.94, 0.56), (0.8, 0.66), (0.6, 0.6), (0.44, 0.62), (0.4, 0.74), (0.5, 0.8), (0.56, 0.72))],
    # Flickering Light: a six-pointed star
    "flicker": [star(0.5, 0.5, 0.48, 0.26, 6)],
    # Lightning: a zigzag
    "lightning": [line((0.74, 0.0), (0.32, 0.26), (0.68, 0.36), (0.3, 0.6), (0.66, 0.7), (0.24, 1.0))],
    # Aeriforms: the S between two arrows of three lines, dots above and below
    "aeriforms": [_s_curve(0.5, 0.5, 0.86, 0.32), line((0.04, 0.34), (0.3, 0.5)), line((0.0, 0.5), (0.3, 0.5)), line((0.04, 0.66), (0.3, 0.5)),
                  line((0.96, 0.34), (0.7, 0.5)), line((1.0, 0.5), (0.7, 0.5)), line((0.96, 0.66), (0.7, 0.5)),
                  dot(0.22, 0.18), dot(0.78, 0.18), dot(0.22, 0.82), dot(0.78, 0.82)],
    # Wind Underfoot: two spirals wound together in an oval
    "underfoot": [spiral(0.5, 0.3, 0.02, 0.26, 90, 1.25), spiral(0.5, 0.7, 0.02, 0.26, -90, 1.25),
                  arc(0.5, 0.5, 0.46, 0, 360, ry=0.5)],
    # Whorling Wind: a small triangle with rings at its corners and curls going out
    "whorl": [line((0.5, 0.36), (0.68, 0.66), (0.32, 0.66), (0.5, 0.36)), circle(0.5, 0.33, 0.04), circle(0.3, 0.68, 0.04), circle(0.7, 0.68, 0.04),
              curve((0.5, 0.29), (0.52, 0.12), (0.64, 0.06), (0.72, 0.14), (0.66, 0.22)),
              curve((0.26, 0.7), (0.12, 0.72), (0.04, 0.64), (0.1, 0.56), (0.18, 0.62)),
              curve((0.74, 0.7), (0.9, 0.76), (0.94, 0.9), (0.82, 0.96), (0.78, 0.86))],
    # Repetition: an eye in a circle, the lower lid crossing the circle
    "repetition": [circle(0.5, 0.5, 0.34), line((0.0, 0.3), (0.5, 0.74), (1.0, 0.3)), curve((0.26, 0.5), (0.42, 0.6), (0.6, 0.6), (0.7, 0.52)),
                   dot(0.5, 0.42)],
    # Guidance: a T whose stem winds into a spiral around an arrow pointing down
    "guidance": [line((0.3, 0.02), (0.7, 0.02)), line((0.5, 0.02), (0.5, 0.2)) + spiral(0.5, 0.6, 0.4, 0.2, -90, 0.95),
                 line((0.38, 0.52), (0.62, 0.52), (0.5, 0.72), (0.38, 0.52)), line((0.38, 0.62), (0.5, 0.74), (0.62, 0.62)), line((0.5, 0.44), (0.5, 0.74))],
    # Calling: a diamond between two half moons, two long curves through them
    "calling": [line((0.5, 0.34), (0.62, 0.5), (0.5, 0.66), (0.38, 0.5), (0.5, 0.34)),
                line((0.3, 0.3), (0.3, 0.7)) + arc(0.3, 0.5, 0.2, 90, 270), line((0.7, 0.3), (0.7, 0.7)) + arc(0.7, 0.5, 0.2, 90, -90),
                curve((0.2, 0.0), (0.34, 0.25), (0.36, 0.5), (0.34, 0.75), (0.2, 1.0)), curve((0.8, 0.0), (0.66, 0.25), (0.64, 0.5), (0.66, 0.75), (0.8, 1.0))],
    # Purification: a pinwheel of curling hooks
    "purification": [curve((0.5 + 0.1 * math.cos(math.radians(a)), 0.5 + 0.1 * math.sin(math.radians(a))),
                           (0.5 + 0.3 * math.cos(math.radians(a + 20)), 0.5 + 0.3 * math.sin(math.radians(a + 20))),
                           (0.5 + 0.46 * math.cos(math.radians(a + 55)), 0.5 + 0.46 * math.sin(math.radians(a + 55))),
                           (0.5 + 0.36 * math.cos(math.radians(a + 75)), 0.5 + 0.36 * math.sin(math.radians(a + 75))))
                     for a in range(0, 360, 72)],
    # Sword: two lines, one bending across the other
    "sword": [line((0.62, 0.0), (0.62, 1.0)), curve((0.38, 0.0), (0.38, 0.35), (0.5, 0.5), (0.62, 0.62), (0.7, 0.78), (0.72, 1.0))],
    # Bridging: three arches under a big arch
    "bridging": [arc(0.5, 0.62, 0.48, 190, 350, ry=0.4), arc(0.25, 0.62, 0.1, 180, 360, ry=0.2), arc(0.5, 0.62, 0.1, 180, 360, ry=0.24),
                 arc(0.75, 0.62, 0.1, 180, 360, ry=0.2)],
    # Sand: a stroke S on a line between two chevrons with dots
    "sand": [_s_curve(0.5, 0.5, 0.7, 0.26), line((0.5, 0.0), (0.5, 1.0)), line((0.14, 0.32), (0.3, 0.5), (0.14, 0.68)),
             line((0.86, 0.32), (0.7, 0.5), (0.86, 0.68)), dot(0.04, 0.5), dot(0.96, 0.5)],
    # Undulation: an S between two braces curling like waves
    "undulation": [_s_curve(0.5, 0.5, 0.7, 0.2), curve((0.3, 0.2), (0.22, 0.28), (0.26, 0.45), (0.16, 0.5), (0.26, 0.55), (0.22, 0.72), (0.3, 0.8)),
                   curve((0.7, 0.2), (0.78, 0.28), (0.74, 0.45), (0.84, 0.5), (0.74, 0.55), (0.78, 0.72), (0.7, 0.8)),
                   arc(0.1, 0.5, 0.06, 90, 270, ry=0.14), arc(0.9, 0.5, 0.06, 90, -90, ry=0.14), dot(0.0, 0.5), dot(1.0, 0.5)],
    # Unburning Flames (Phantasmal Fireball): a triangle in a triangle, squares on the inner one
    "unburning": [line((0.5, 0.04), (0.96, 0.84), (0.04, 0.84), (0.5, 0.04)), line((0.5, 0.36), (0.66, 0.66), (0.34, 0.66), (0.5, 0.36)),
                  line((0.32, 0.4), (0.4, 0.4), (0.4, 0.48), (0.32, 0.48), (0.32, 0.4)), line((0.6, 0.4), (0.68, 0.4), (0.68, 0.48), (0.6, 0.48), (0.6, 0.4)),
                  line((0.46, 0.72), (0.54, 0.72), (0.54, 0.8), (0.46, 0.8), (0.46, 0.72))],
    # Obliviation (Memory Erasure): circles around a dot
    "obliviation": [circle(0.5, 0.5, 0.46), circle(0.5, 0.5, 0.26), dot(0.5, 0.5)],
    # Concealment (Borrowshade): an asterisk with eyes at the ends of its cross
    "concealment": [line((0.5, 0.1), (0.5, 0.9)), line((0.1, 0.5), (0.9, 0.5)), line((0.2, 0.2), (0.8, 0.8)), line((0.8, 0.2), (0.2, 0.8))]
                   + _eye(0.5, 0.08, 0.08, 0.04) + _eye(0.5, 0.92, 0.08, 0.04) + _eye(0.08, 0.5, 0.04, 0.08) + _eye(0.92, 0.5, 0.04, 0.08),
    # Billow (Billow Cluster): four looping petals
    "billow": [curve((0.5, 0.5), (0.36, 0.3), (0.42, 0.08), (0.5, 0.04), (0.58, 0.08), (0.64, 0.3), (0.5, 0.5)),
               curve((0.5, 0.5), (0.36, 0.7), (0.42, 0.92), (0.5, 0.96), (0.58, 0.92), (0.64, 0.7), (0.5, 0.5)),
               curve((0.5, 0.5), (0.3, 0.36), (0.08, 0.42), (0.04, 0.5), (0.08, 0.58), (0.3, 0.64), (0.5, 0.5)),
               curve((0.5, 0.5), (0.7, 0.36), (0.92, 0.42), (0.96, 0.5), (0.92, 0.58), (0.7, 0.64), (0.5, 0.5))],
    # Selection (Seal of Expansion and Levitation): a square on a cross
    "selection": [line((0.25, 0.25), (0.75, 0.25), (0.75, 0.75), (0.25, 0.75), (0.25, 0.25)), line((0.5, 0.0), (0.5, 1.0)), line((0.0, 0.5), (1.0, 0.5))],
    # decorative sigils: the spell takes the creature's shape
    # Chapter 58 redraws and the anime primer's Frillram, in the wiki's upright pose.
    "scalewolf": [line((.42,.02),(.42,.13)), line((.58,.02),(.58,.13)),
                  line((.37,.13),(.63,.13),(.5,.29),(.37,.13)),
                  line((.29,.32),(.71,.32),(.5,.64),(.29,.32)),
                  line((.39,.48),(.5,.32),(.61,.48),(.39,.48)),
                  line((.22,.48),(.17,.55),(.22,.62),(.27,.55),(.22,.48)),
                  line((.78,.48),(.73,.55),(.78,.62),(.83,.55),(.78,.48)),
                  line((.33,.62),(.28,.69),(.33,.76),(.38,.69),(.33,.62)),
                  line((.62,.69),(.67,.62),(.72,.69),(.67,.76),(.62,.69)),
                  line((.5,.73),(.41,.85),(.5,.97),(.59,.85),(.5,.73)),
                  line((.13,.49),(.17,.53)), line((.17,.45),(.2,.49)),
                  line((.83,.49),(.87,.45)), line((.85,.53),(.91,.49)),
                  line((.22,.76),(.27,.72)), line((.26,.8),(.3,.76)),
                  line((.73,.72),(.78,.76)), line((.7,.76),(.74,.8))],
    "torchstag": [arc(.5,.06,.22,15,165,ry=.14), line((.5,.2),(.5,.42)),
                  line((.38,.25),(.2,.34),(.38,.41),(.38,.25)),
                  curve((.5,.42),(.7,.32),(.91,.33),(1,.44)),
                  line((.73,.32),(.45,.61)), line((1,.44),(.85,.61)),
                  line((.39,.67),(.46,.67)), line((.39,.72),(.46,.72)),
                  line((.81,.67),(.88,.67)), line((.81,.72),(.88,.72))],
    "liongoat": [arc(.5,.36,.23,170,370,ry=.26),
                 line((.27,.4),(.25,.42)), line((.73,.4),(.75,.42)),
                 curve((.16,.12),(.22,.06),(.32,.16),(.42,.31),(.5,.53)),
                 curve((.84,.12),(.78,.06),(.68,.16),(.58,.31),(.5,.53)),
                 curve((.16,.53),(.24,.57),(.34,.47),(.44,.31)),
                 curve((.84,.53),(.76,.57),(.66,.47),(.56,.31)),
                 line((.16,.33),(.84,.33)), line((.16,.3),(.18,.37)), line((.84,.3),(.82,.37)),
                 arc(.5,.64,.14,10,170,ry=.09),
                 line((.31,.71),(.35,.71)), line((.31,.76),(.35,.76)),
                 line((.65,.71),(.69,.71)), line((.65,.76),(.69,.76))],
    "frillram": [line((.05,.12),(.4,.12)),
                 curve((.16,.12),(.16,.24),(.13,.36),(.18,.44),(.32,.44),(.39,.37),(.42,.26)),
                 line((.42,.26),(.65,.26)),
                 curve((.61,.26),(.61,.43),(.68,.51),(.89,.51)),
                 curve((.25,.44),(.25,.58),(.3,.69),(.2,.78),(.14,.86),(.17,.91),(.86,.91)),
                 curve((.54,.71),(.58,.8),(.82,.8),(.87,.75),(.93,.12))],
    "dragon": [curve((0.14, 0.62), (0.04, 0.5), (0.1, 0.36), (0.22, 0.4)), line((0.16, 0.42), (0.62, 0.42)),
               line((0.3, 0.2), (0.8, 0.9)), line((0.44, 0.26), (0.62, 0.26), (0.5, 0.44)), line((0.5, 0.3), (0.64, 0.3)),
               line((0.6, 0.58), (0.74, 0.44)), line((0.66, 0.66), (0.82, 0.52)), line((0.76, 0.84), (0.98, 0.76), (0.88, 0.68), (0.76, 0.84))],
    "horse": [line((0.3, 0.02), (0.16, 0.0), (0.16, 0.95)), line((0.16, 0.3), (0.84, 0.3), (0.94, 0.9)), line((0.66, 0.3), (0.66, 0.9)),
              arc(0.16, 0.3, 0.2, 0, 90), arc(0.84, 0.3, 0.2, 90, 180), line((0.08, 0.98), (0.2, 0.9)), line((0.84, 0.98), (0.96, 0.9))],
    "bird": [arc(0.3, 0.72, 0.28, 180, 360, ry=0.3), arc(0.7, 0.72, 0.28, 180, 360, ry=0.3), arc(0.5, 0.72, 0.16, 180, 360, ry=0.26),
             line((0.5, 0.06), (0.5, 0.28)), line((0.34, 0.14), (0.42, 0.3)), line((0.66, 0.14), (0.58, 0.3))],
    "fish": [line((0.96, 0.34), (0.56, 0.5), (0.3, 0.2), (0.0, 0.5), (0.3, 0.8), (0.56, 0.5), (0.96, 0.66)), line((0.56, 0.5), (0.96, 0.5))],
    "owlcat": [circle(0.5, 0.58, 0.3), line((0.28, 0.08), (0.5, 0.5), (0.72, 0.08)), line((0.42, 0.5), (0.58, 0.5)),
               line((0.2, 0.52), (0.1, 0.5), (0.04, 0.72)), line((0.12, 0.54), (0.1, 0.72)), line((0.8, 0.52), (0.9, 0.5), (0.96, 0.72)),
               line((0.88, 0.54), (0.9, 0.72))],
    "leech": [line((0.3, 0.38), (0.62, 0.3), (0.78, 0.42), (0.68, 0.62), (0.36, 0.7), (0.24, 0.56), (0.3, 0.38)), line((0.3, 0.38), (0.2, 0.2)),
              line((0.62, 0.3), (0.7, 0.12)), line((0.78, 0.42), (0.98, 0.4)), line((0.68, 0.62), (0.82, 0.76)), line((0.36, 0.7), (0.32, 0.86)),
              line((0.24, 0.56), (0.04, 0.58)), line((0.12, 0.2), (0.3, 0.2)), line((0.2, 0.86), (0.44, 0.86))],
}

# Earth as the manga and the wiki draw it: with a base under the point and a dot at either side (the simulator's has
# neither, and rounds the corners). Measured from the wiki's Integration redraw, but for the two bars: the redraw's
# run from 0.166 to 0.834, and with bars that short a ring holding three element sigils was refused less often
# (77% of 300 against 89% with these, tests/run_tests.py "fire + earth + light"). It is the sigil's first drawing
# (import_templates.py PRIMARY_VARIANTS): the one the book's pages and legend show. The wind sigil's S alone,
# without its rays (Rainflinger, Vapor Bubble)
SIGIL_VARIANTS = {
    "wind": [[_s_curve(0.5, 0.5, 0.9, 0.36)]],
    "earth": [[line((0.14, 0.13), (0.86, 0.13)), line((0.5, 0.13), (0.5, 0.8)),
               line((0.343, 0.332), (0.153, 0.528), (0.5, 0.8), (0.846, 0.528), (0.655, 0.332)),
               line((0.14, 0.87), (0.86, 0.87)), dot(0.023, 0.41), dot(0.977, 0.41)]],
}

# ---------------------------------------------------------------- frames (big shapes around the sigil)


def _rain(outward=True):
    side = []
    k = 0.07  # sides bowed inwards
    sq = curve((0.18, 0.18), (0.5, 0.18 + k), (0.82, 0.18), (0.82 - k, 0.5), (0.82, 0.82), (0.5, 0.82 - k), (0.18, 0.82), (0.18 + k, 0.5), (0.18, 0.18))
    ticks = []
    d = 1 if outward else -1
    for off in (-0.06, 0.0, 0.06):
        ticks.append(line((0.5 + off, 0.18 + k - 0.02 * d), (0.5 + off, 0.18 + k - 0.16 * d)))
        ticks.append(line((0.5 + off, 0.82 - k + 0.02 * d), (0.5 + off, 0.82 - k + 0.16 * d)))
        ticks.append(line((0.18 + k - 0.02 * d, 0.5 + off), (0.18 + k - 0.16 * d, 0.5 + off)))
        ticks.append(line((0.82 - k + 0.02 * d, 0.5 + off), (0.82 - k + 0.16 * d, 0.5 + off)))
    return [sq] + side + ticks


FRAMES = {
    # Rain (Rainbringer): a square with bowed sides and three ticks through each side
    "rain": _rain(True),
    # inverted Rain (Rainwarding): the ticks turned inwards
    "rainward": _rain(False),
    # Holding (Wand of Water): brackets around the sigil, curling at the bottom, with dots
    "holding": [curve((0.3, 0.02), (0.12, 0.25), (0.08, 0.5), (0.18, 0.74), (0.3, 0.86), (0.26, 0.98), (0.16, 0.94)),
                curve((0.7, 0.02), (0.88, 0.25), (0.92, 0.5), (0.82, 0.74), (0.7, 0.86), (0.74, 0.98), (0.84, 0.94)),
                dot(0.24, 0.8), dot(0.76, 0.8)],
    # Stretch (Boulder Stretch Rope): an arch around the sigil with feet turned out
    "weave": [line((0.08, 0.96), (0.23, 0.82)) + arc(0.5, 0.5, 0.42, 130, 410) + line((0.77, 0.82), (0.92, 0.96))],
    # Dancing Puppets (Flying Puppet of Diversion): a ring with four small rings and tendrils
    "dancing": [circle(0.5, 0.5, 0.3), circle(0.5, 0.2, 0.06), circle(0.5, 0.8, 0.06), circle(0.2, 0.5, 0.06), circle(0.8, 0.5, 0.06),
                curve((0.3, 0.02), (0.4, 0.14), (0.5, 0.14), (0.6, 0.14), (0.7, 0.02)), curve((0.3, 0.98), (0.4, 0.86), (0.5, 0.86), (0.6, 0.86), (0.7, 0.98)),
                line((0.29, 0.29), (0.14, 0.14)), line((0.71, 0.29), (0.86, 0.14)), line((0.29, 0.71), (0.14, 0.86)), line((0.71, 0.71), (0.86, 0.86))],
    # Flower (decorative, Water Rose, Flowers of Light): a pentagon with five rays
    "flower": [polygon(0.5, 0.52, 0.2, 5)] + [line((0.5 + 0.2 * math.cos(math.radians(-90 + 72 * i)), 0.52 + 0.2 * math.sin(math.radians(-90 + 72 * i))),
                                                   (0.5 + 0.5 * math.cos(math.radians(-90 + 72 * i)), 0.52 + 0.5 * math.sin(math.radians(-90 + 72 * i))))
                                              for i in range(5)],
}
