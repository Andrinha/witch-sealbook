"""Turns line art (the wiki's redraws of seals) into strokes: thresholds the image, scales it so its lines
are several pixels thick, thins them to one pixel (Zhang-Suen), walks the skeleton between its ends and
junctions, and puts the lines back together where they meet: thinning bends thick lines towards each other
at a junction, so the skeleton near one is thrown away, the lines that continue each other are joined
straight across it and the others are run on up to them; ends are run on to where the round caps ended.
Small filled blobs (dots) become one-point strokes.

    strokes, w, h, scale = trace("path/to/image.png")      # [[(x, y), ...], ...] in the scaled image's pixels

Used by grimoire.py for the wiki's seals whose signs aren't in the book's vocabulary (needs numpy, pillow).
"""
import math

import numpy as np
from PIL import Image

INK = 0.5  # darker than this share of white is ink
NB = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]  # P2..P9 clockwise from north


def _gray(path, crop=None):
    im = Image.open(path).convert("RGBA")
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
    bg.alpha_composite(im)
    im = bg.convert("L")
    if crop:
        im = im.crop(crop)
    return im


def _mask(im):
    """the ink of a gray image: a bool array [y, x] with a clear rim"""
    return np.pad(np.asarray(im) < 255 * INK, 1)


def _thickness(ink):
    """Mean line thickness: twice the ink area over its outline's length"""
    inside = ink[1:-1, 1:-1]
    edge = inside & ~(ink[:-2, 1:-1] & ink[2:, 1:-1] & ink[1:-1, :-2] & ink[1:-1, 2:])
    return 2 * int(inside.sum()) / max(1, int(edge.sum()))


def thickness(path, crop=None):
    """Mean line thickness of an image in its own pixels"""
    return _thickness(_mask(_gray(path, crop)))


def thin(ink):
    """Guo-Hall thinning of a bool array with a clear rim (Zhang-Suen's eats diagonal lines two pixels thick), then
    the corners of its staircases are taken out, so that a line is one pixel thick diagonally too. Returns the set
    of (x, y) left."""
    img = ink.copy()
    changed = True
    while changed:
        changed = False
        for step in (0, 1):
            p2, p3, p4, p5 = img[:-2, 1:-1], img[:-2, 2:], img[1:-1, 2:], img[2:, 2:]
            p6, p7, p8, p9 = img[2:, 1:-1], img[2:, :-2], img[1:-1, :-2], img[:-2, :-2]
            u8 = np.uint8
            c = ((~p2 & (p3 | p4)).astype(u8) + (~p4 & (p5 | p6)).astype(u8)
                 + (~p6 & (p7 | p8)).astype(u8) + (~p8 & (p9 | p2)).astype(u8))
            n1 = (p9 | p2).astype(u8) + (p3 | p4).astype(u8) + (p5 | p6).astype(u8) + (p7 | p8).astype(u8)
            n2 = (p2 | p3).astype(u8) + (p4 | p5).astype(u8) + (p6 | p7).astype(u8) + (p8 | p9).astype(u8)
            n = np.minimum(n1, n2)
            m = ((p2 | p3 | ~p5) & p4) if step == 0 else ((p6 | p7 | ~p9) & p8)
            cond = img[1:-1, 1:-1] & (c == 1) & (n >= 2) & (n <= 3) & ~m
            if cond.any():
                img[1:-1, 1:-1][cond] = False
                changed = True
    ys, xs = np.nonzero(img)
    skel = {(int(x) - 1, int(y) - 1) for x, y in zip(xs, ys)}
    for (x, y) in sorted(skel):
        n, e, s, w = (x, y - 1) in skel, (x + 1, y) in skel, (x, y + 1) in skel, (x - 1, y) in skel
        if ((n and e and (x - 1, y + 1) not in skel) or (e and s and (x - 1, y - 1) not in skel)
                or (s and w and (x + 1, y - 1) not in skel) or (w and n and (x + 1, y + 1) not in skel)):
            skel.discard((x, y))
    return skel


def _grow(a, n, shrink=False):
    """a bool array with a clear rim grown (or shrunk) by about n pixels all around"""
    for i in range(n):
        b = a.copy()
        inner = b[1:-1, 1:-1]
        sides = [a[:-2, 1:-1], a[2:, 1:-1], a[1:-1, :-2], a[1:-1, 2:]]
        if i % 2:
            sides += [a[:-2, :-2], a[:-2, 2:], a[2:, :-2], a[2:, 2:]]
        for side in sides:
            if shrink:
                inner &= side
            else:
                inner |= side
        a = b
    return a


def _hull(points):
    """the convex hull of pixels, closed"""
    pts = sorted(set(points))
    if len(pts) < 3:
        return [(float(x), float(y)) for x, y in pts]

    def half(seq):
        out = []
        for p in seq:
            while len(out) >= 2 and ((out[-1][0] - out[-2][0]) * (p[1] - out[-2][1])
                                     - (out[-1][1] - out[-2][1]) * (p[0] - out[-2][0])) <= 0:
                out.pop()
            out.append(p)
        return out

    hull = half(pts)[:-1] + half(pts[::-1])[:-1]
    return [(float(x), float(y)) for x, y in hull + hull[:1]]


def neighbours(p, pixels):
    x, y = p
    return [(x + dx, y + dy) for dx, dy in NB if (x + dx, y + dy) in pixels]


def blobs(ink):
    """the connected pieces of a set of pixels"""
    seen, out = set(), []
    for p in ink:
        if p in seen:
            continue
        comp, stack = [], [p]
        seen.add(p)
        while stack:
            q = stack.pop()
            comp.append(q)
            for n in neighbours(q, ink):
                if n not in seen:
                    seen.add(n)
                    stack.append(n)
        out.append(comp)
    return out


def walk_skeleton(skel):
    """Polylines between nodes (ends and junctions) of a one-pixel skeleton, plus closed loops"""
    degree = {p: len(neighbours(p, skel)) for p in skel}
    nodes = {p for p, d in degree.items() if d != 2}
    used = set()
    lines = []

    def follow(start, nxt):
        line = [start, nxt]
        used.add(frozenset((start, nxt)))
        prev, cur = start, nxt
        while cur not in nodes:
            options = [n for n in neighbours(cur, skel) if n != prev and frozenset((cur, n)) not in used]
            if not options:
                break
            options.sort(key=lambda n: abs(n[0] - cur[0]) + abs(n[1] - cur[1]))
            n = options[0]
            used.add(frozenset((cur, n)))
            line.append(n)
            prev, cur = cur, n
            if cur == start:
                break
        return line

    for p in sorted(nodes):
        for n in neighbours(p, skel):
            if frozenset((p, n)) not in used:
                lines.append(follow(p, n))
    for p in sorted(skel):
        for n in neighbours(p, skel):
            if frozenset((p, n)) not in used:
                lines.append(follow(p, n))
    return [l for l in lines if len(l) >= 2]


def rdp(points, eps):
    if len(points) < 3:
        return points
    (ax, ay), (bx, by) = points[0], points[-1]
    dx, dy = bx - ax, by - ay
    norm = math.hypot(dx, dy)
    best, index = -1, 0
    for i in range(1, len(points) - 1):
        px, py = points[i]
        d = abs(dy * px - dx * py + bx * ay - by * ax) / norm if norm > 1e-9 else math.hypot(px - ax, py - ay)
        if d > best:
            best, index = d, i
    if best <= eps:
        return [points[0], points[-1]]
    return rdp(points[:index + 1], eps)[:-1] + rdp(points[index:], eps)


def _length(line):
    return sum(math.dist(a, b) for a, b in zip(line, line[1:]))


def _heading(line, skip, span):
    """unit direction a line runs at its last point, measured over 'span' of it, the last 'skip' left out (it is
    bent by the junction there)"""
    walked, far, near = 0.0, None, line[-1]
    for i in range(len(line) - 1, 0, -1):
        walked += math.dist(line[i], line[i - 1])
        if walked <= skip:
            near = line[i - 1]
        if walked >= skip + span:
            far = line[i - 1]
            break
    if far is None:
        far = line[0]
    if far == near:
        near = line[-1]
    d = math.dist(far, near) or 1.0
    return ((near[0] - far[0]) / d, (near[1] - far[1]) / d)


def _cut(line, length):
    """the line without the last 'length' of it (two points at least are left)"""
    walked = 0.0
    for i in range(len(line) - 1, 1, -1):
        walked += math.dist(line[i], line[i - 1])
        if walked >= length:
            return line[:i]
    return line[:2]


def _hit(p, d, a, b):
    """how far along the ray from p towards d the segment a-b is crossed, or None"""
    ex, ey = b[0] - a[0], b[1] - a[1]
    den = d[0] * ey - d[1] * ex
    if abs(den) < 1e-9:
        return None
    t = ((a[0] - p[0]) * ey - (a[1] - p[1]) * ex) / den
    u = ((a[0] - p[0]) * d[1] - (a[1] - p[1]) * d[0]) / den
    return t if -0.25 <= u <= 1.25 else None


def assemble(lines, t, max_turn=math.radians(40)):
    """Strokes of the skeleton's lines (pixel paths between its ends and junctions) for lines 't' thick"""
    lines = [[(float(x), float(y)) for x, y in l] for l in lines]
    alive = [True] * len(lines)
    ends = [(i, e) for i in range(len(lines)) for e in (0, 1)]
    root = {end: end for end in ends}

    def find(a):
        while root[a] != a:
            root[a] = root[root[a]]
            a = root[a]
        return a

    def point(end):
        return lines[end[0]][-1 if end[1] else 0]

    # the ends that meet (the pixels of a junction are neighbours)
    grid = {}
    for end in ends:
        p = point(end)
        grid.setdefault((int(p[0] // 2), int(p[1] // 2)), []).append(end)
    for (gx, gy), items in grid.items():
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for other in grid.get((gx + dx, gy + dy), []):
                    for end in items:
                        if end < other and math.dist(point(end), point(other)) <= 1.5:
                            root[find(end)] = find(other)

    def clusters():
        out = {}
        for end in ends:
            if alive[end[0]]:
                out.setdefault(find(end), []).append(end)
        return out

    # a short line between two junctions is one junction (two thick lines crossing), a short line that ends
    # freely is a spur of the thinning
    short = sorted((i for i in range(len(lines)) if _length(lines[i]) < 1.3 * t), key=lambda i: _length(lines[i]))
    for i in short:
        if find((i, 0)) == find((i, 1)):
            alive[i] = False  # between the pixels of one junction
    while True:
        groups = clusters()
        size = {end: len(groups[find(end)]) for end in ends if alive[end[0]]}
        victim = None
        for i in short:
            if not alive[i]:
                continue
            if find((i, 0)) == find((i, 1)):
                alive[i] = False
                continue
            n0, n1 = size[(i, 0)], size[(i, 1)]
            if (n0 >= 3 and n1 >= 3) or (min(n0, n1) == 1 and max(n0, n1) >= 3 and _length(lines[i]) < 1.2 * t):
                victim = (i, n0 >= 3 and n1 >= 3)
                break
        if not victim:
            break
        alive[victim[0]] = False
        if victim[1]:
            root[find((victim[0], 0))] = find((victim[0], 1))

    link = {}
    tails = {}  # end -> points to add after it
    for members in clusters().values():
        if len(members) == 1:
            # a free end: the round cap reached half the thickness further
            end = members[0]
            line = lines[end[0]] if end[1] else lines[end[0]][::-1]
            if _length(line) > t:
                d = _heading(line, 0, 2 * t)
                tails[end] = [(line[-1][0] + d[0] * t * 0.5, line[-1][1] + d[1] * t * 0.5)]
            continue
        if len(members) == 2:
            a, b = members
            if a[0] != b[0] or len(lines[a[0]]) > 3:
                link[a], link[b] = b, a
            continue
        cx = sum(point(e)[0] for e in members) / len(members)
        cy = sum(point(e)[1] for e in members) / len(members)
        # every line cut back from the junction, and the way it was running towards it
        heading, cut = {}, {}
        for end in members:
            line = lines[end[0]] if end[1] else lines[end[0]][::-1]
            heading[end] = _heading(line, 0.9 * t, 2.5 * t)
            cut[end] = _cut(line, 0.9 * t)[-1] if _length(line) > 2.2 * t else None
        pairs = []
        for i, a in enumerate(members):
            for b in members[i + 1:]:
                da, db = heading[a], heading[b]
                turn = math.acos(max(-1.0, min(1.0, -(da[0] * db[0] + da[1] * db[1]))))
                if turn <= max_turn:
                    pairs.append((turn, a, b))
        through = []
        for _, a, b in sorted(pairs):
            if a in link or b in link:
                continue
            link[a], link[b] = b, a
            through.append((cut[a] or point(a), cut[b] or point(b)))
        for end in members:
            line = lines[end[0]] if end[1] else lines[end[0]][::-1]
            if cut[end]:
                kept = _cut(line, 0.9 * t)
                lines[end[0]] = kept if end[1] else kept[::-1]
            if end in link:
                continue
            # it stops at the junction: run on to the line that passes through, or to the junction's middle
            start = cut[end] or point(end)
            best = None
            for a, b in through:
                hit = _hit(start, heading[end], a, b)
                if hit is not None and 0 <= hit <= 3 * t and (best is None or hit < best):
                    best = hit
            if best is not None:
                tails[end] = [(start[0] + heading[end][0] * best, start[1] + heading[end][1] * best)]
            else:
                tails[end] = [(cx, cy)]

    # walk the chains from their free ends
    out, seen = [], set()

    def chain_from(i, end):
        chain, cur, cur_end, closed = [], i, end, False
        while True:
            if cur in seen:
                closed = True
                break
            seen.add(cur)
            pts = lines[cur] if cur_end == 0 else lines[cur][::-1]
            if not chain and (cur, cur_end) in tails:
                chain += tails[(cur, cur_end)]
            chain += pts
            nxt = link.get((cur, 1 - cur_end))
            if not nxt:
                chain += tails.get((cur, 1 - cur_end), [])
                break
            cur, cur_end = nxt
        if closed and chain:
            chain.append(chain[0])
        return chain

    for start in range(len(lines)):
        if not alive[start] or start in seen:
            continue
        i, end, steps = start, 0, 0
        while (i, end) in link and steps <= len(lines):
            j, ej = link[(i, end)]
            i, end = j, 1 - ej
            steps += 1
        out.append(chain_from(i, end))
    return out


def trace(path, crop=None, target_thickness=7.0, max_size=1000, eps=0.45):
    """Strokes of an image in the pixels of the scaled image: [[(x, y), ...], ...]; a dot is a
    one-point stroke. Returns (strokes, width, height, scale) - scale: scaled pixels per source pixel"""
    im = _gray(path, crop)
    scale = min(target_thickness / max(_thickness(_mask(im)), 0.5), max_size / max(im.size), 3.0)
    im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS)
    ink = _mask(im)
    t = _thickness(ink)
    size = max(im.size)
    ys, xs = np.nonzero(ink)
    pixels = {(int(x) - 1, int(y) - 1) for x, y in zip(xs, ys)}
    strokes = []
    lined = np.zeros_like(ink)
    for comp in blobs(pixels):
        cx = [p[0] for p in comp]
        cy = [p[1] for p in comp]
        bw, bh = max(cx) - min(cx) + 1, max(cy) - min(cy) + 1
        if len(comp) < max(3, 0.3 * t * t):
            continue
        # a small compact blob is a dot (filled circles in the drawings)
        if max(bw, bh) <= max(2.8 * t, size * 0.03) and len(comp) >= 0.45 * bw * bh:
            strokes.append([(sum(cx) / len(cx), sum(cy) / len(cy))])
            continue
        for x, y in comp:
            lined[y + 1, x + 1] = True
    # a filled shape (wider than a line) is drawn as its outline; the lines that run into it end at it
    depth = max(2, int(round(t)))
    core = _grow(lined, depth, shrink=True)
    if core.any():
        fat = _grow(core, depth + 2) & lined
        ys, xs = np.nonzero(fat)
        for comp in blobs({(int(x) - 1, int(y) - 1) for x, y in zip(xs, ys)}):
            if sum(1 for x, y in comp if core[y + 1, x + 1]) < 0.6 * t * t:
                continue
            for x, y in comp:
                lined[y + 1, x + 1] = False
            cx = [p[0] for p in comp]
            cy = [p[1] for p in comp]
            if max(max(cx) - min(cx), max(cy) - min(cy)) + 1 <= max(2.8 * t, size * 0.03):
                strokes.append([(sum(cx) / len(cx), sum(cy) / len(cy))])
            else:
                strokes.append(rdp(_hull(comp), 0.8))
    for l in assemble(walk_skeleton(thin(lined)), t):
        if _length(l) >= 0.8 * t:
            strokes.append(rdp(l, eps))
    return strokes, im.width, im.height, scale


if __name__ == "__main__":
    import sys
    s, w, h, k = trace(sys.argv[1])
    print(w, h, round(k, 3), len(s), "strokes")
