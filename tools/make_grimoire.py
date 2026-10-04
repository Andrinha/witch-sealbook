"""Draws the wiki's seals (tools/grimoire.py) on book pages and writes files/grimoire.lua: the pages of the book's
wiki section and the seals the book recognizes as a whole. Every seal is parsed and compiled by the mod's own Lua
(needs: pip install lupa pillow) and the spell is stored with it, so the book casts exactly what a drawing of the
page would give.

Usage (from the mod folder):  python tools/make_grimoire.py [--only key,key]
"""
import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grimoire as G  # noqa: E402
import trace as T  # noqa: E402

MOD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(MOD, "files", "grimoire.lua")
PAGE = 180
CENTER = 90.0
RADIUS = 70.0


def lua_runtime():
    """what reads a drawing, without the grimoire this makes (tests/harness.py)"""
    sys.path.insert(0, os.path.join(MOD, "tests"))
    import harness
    return harness.load_reader(grimoire=False)


_templates = {}


def templates(lua):
    if not _templates:
        for kind, table in (("sigil", "TEMPLATES_SIGILS"), ("sign", "TEMPLATES_SIGNS"), ("frame", "TEMPLATES_FRAMES")):
            for key, shapes in lua.eval(table).items():
                _templates[(kind, key)] = [[(p[1], p[2]) for p in st.values()] for st in shapes[1].values()]
        _templates[("glaive", "glaive")] = [[(p[1], p[2]) for p in st.values()] for st in lua.eval("TEMPLATES_GLAIVE").values()]
    return _templates


def dense(stroke, step=1.0):
    if len(stroke) < 2:
        return list(stroke)
    out = [stroke[0]]
    for a, b in zip(stroke, stroke[1:]):
        n = max(1, int(math.dist(a, b) / step))
        out += [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(1, n + 1)]
    return out


def place(strokes, cx, cy, size, rot_deg, hand=None):
    """template strokes (unit square) -> centered at cx, cy, the larger side 'size', turned by rot_deg; 'hand': a
    random.Random that makes it look drawn by hand (stretch, shear, tilt, tremor)"""
    pts = [p for s in strokes for p in s]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    mx, my = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    k = size / max(max(xs) - min(xs), max(ys) - min(ys), 1e-6)
    a = math.radians(rot_deg)
    sx = sy = 1.0
    shear = 0.0
    if hand:
        a += math.radians(hand.uniform(-7, 7))
        sx, sy, shear = hand.uniform(0.9, 1.1), hand.uniform(0.9, 1.1), hand.uniform(-0.08, 0.08)
    c, s = math.cos(a), math.sin(a)
    out = []
    for st in strokes:
        line = []
        for x, y in st:
            u, v = (x - mx) * k * sx + (y - my) * k * shear, (y - my) * k * sy
            line.append((cx + u * c - v * s, cy + u * s + v * c))
        line = dense(line)
        if hand and len(line) > 1:
            ph, amp = hand.uniform(0, 6.3), hand.uniform(0.15, 0.45)
            line = [(x + amp * math.sin(ph + i / 6) + hand.gauss(0, 0.2), y + amp * math.cos(ph + i / 8) + hand.gauss(0, 0.2))
                    for i, (x, y) in enumerate(line)]
        out.append(line)
    return out


def circle(cx, cy, r, gap=0.0, start=None, hand=None):
    n = max(24, int(2 * math.pi * r / 1.0))
    a0 = start if start is not None else -math.pi / 2
    share = 1.0 - gap
    pts = []
    ar = hand.uniform(0.97, 1.03) if hand else 1.0
    for i in range(n + 1):
        t = a0 + 2 * math.pi * share * i / n
        pts.append((cx + r * math.cos(t) + (hand.gauss(0, 0.35) if hand else 0), cy + r * ar * math.sin(t) + (hand.gauss(0, 0.35) if hand else 0)))
    return pts


def render_symbols(lua, symbols, cx, cy, R, hand=None):
    t = templates(lua)
    out = []
    jitter = (lambda: hand.uniform(-0.025, 0.025)) if hand else (lambda: 0.0)
    for s in symbols:
        kind = s[0]
        if kind in ("sigil", "sign", "frame"):
            _, key, x, y, size, rot = s
            shape = t[(kind, key)]
            if kind == "sign":
                rot = rot + 90  # the template points up
            out += place(shape, cx + (x + jitter()) * R, cy + (y + jitter()) * R, size * R * (hand.uniform(0.92, 1.08) if hand else 1), rot, hand)
        elif kind == "layer":
            out.append(circle(cx, cy, s[1] * R, hand=hand))
        elif kind == "glaive":
            a = math.radians(s[1])
            d = R * 1.15
            out += place(t[("glaive", "glaive")], cx + d * math.cos(a), cy + d * math.sin(a), 0.3 * R, s[1] - 90, hand)
        elif kind == "band":
            _, n, r_in = s
            zig = []
            steps = n * 2
            for i in range(steps + 1):
                a = 2 * math.pi * i / steps - math.pi / 2
                r = (r_in + 0.03 if i % 2 == 0 else 0.97) * R
                zig.append((cx + r * math.cos(a), cy + r * math.sin(a)))
            out.append(dense(zig))
        elif kind == "raw":
            out.append(dense([(cx + x * R, cy + y * R) for x, y in s[1]]))
        elif kind in ("sub", "link"):
            _, x, y, r, inner = s
            scx, scy, sr = cx + x * R, cy + y * R, r * R
            out.append(circle(scx, scy, sr, hand=hand))
            out += render_symbols(lua, inner, scx, scy, sr, hand)
            if kind == "link":
                # a line from the ring to the small seal
                d = math.dist((cx, cy), (scx, scy))
                ux, uy = (scx - cx) / d, (scy - cy) / d
                out.append(dense([(cx + ux * R, cy + uy * R), (scx - ux * sr, scy - uy * sr)]))
    return out


def render_recipe(lua, spell, hand=None):
    symbols = spell.symbols
    has_link = any(s[0] == "link" for s in symbols)
    cx, cy, R = (CENTER, CENTER, RADIUS) if not has_link else (62.0, CENTER, 50.0)
    rng = hand
    strokes = [circle(cx, cy, R, hand=rng)]
    strokes += render_symbols(lua, symbols, cx, cy, R, rng)
    return strokes


def find_ring(strokes, size):
    """(cx, cy, r) of the seal's ring among traced strokes: the radius around a center near the middle of the drawing
    where most of the ink lies"""
    pts = [p for s in strokes for p in dense(s, 1.0)]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    bx, by = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    span = max(max(xs) - min(xs), max(ys) - min(ys))
    best = None
    step = span * 0.01
    for dx in range(-6, 7):
        for dy in range(-6, 7):
            cx, cy = bx + dx * step, by + dy * step
            hist = {}
            for x, y in pts:
                r = math.hypot(x - cx, y - cy)
                if r >= span * 0.3:
                    b = int(r / (span * 0.006))
                    hist[b] = hist.get(b, 0) + 1
            for b, c in hist.items():
                score = c + hist.get(b - 1, 0) * 0.5 + hist.get(b + 1, 0) * 0.5
                if not best or score > best[0]:
                    best = (score, cx, cy, (b + 0.5) * span * 0.006)
    return best[1], best[2], best[3]


def render_traced(spell):
    path = os.path.join(G.WIKI, "images", spell.image)
    strokes, w, h, scale = T.trace(path, spell.crop, max_size=spell.trace_size or 1000)
    if spell.ring:
        rcx, rcy, rr = (v * scale for v in spell.ring)
    else:
        rcx, rcy, rr = find_ring(strokes, max(w, h))
    k = RADIUS / rr
    page = []
    for s in strokes:
        pts = [(CENTER + (x - rcx) * k, CENTER + (y - rcy) * k) for x, y in s]
        if len(pts) == 1:
            if abs(math.dist(pts[0], (CENTER, CENTER)) - RADIUS) > 4:
                page.append(pts)
            continue
        # the ring itself is redrawn clean and closed: drop what runs along it (a line that only ends on it stays whole)
        pts = dense(pts, 1.0)
        on = [abs(math.dist(p, (CENTER, CENTER)) - RADIUS) <= 3.0 for p in pts]
        keep = [True] * len(pts)
        i = 0
        while i < len(pts):
            j = i
            while j < len(pts) and on[j] == on[i]:
                j += 1
            if on[i] and j - i >= 8:
                keep[i:j] = [False] * (j - i)
            i = j
        run = []
        for p, kept in zip(pts, keep):
            if kept:
                run.append(p)
            else:
                if len(run) >= 3:
                    page.append(run)
                run = []
        if len(run) >= 3:
            page.append(run)
    # specks outside the ring are not the seal's (a caption under the picture)
    def speck(st):
        return (all(math.dist(p, (CENTER, CENTER)) > RADIUS + 4 for p in st)
                and sum(math.dist(a, b) for a, b in zip(st, st[1:])) < 5)
    page = [st for st in page if not speck(st)]
    # what lies far outside the page is cut off (texts, glaives too long)
    page = [[(min(max(x, 3), PAGE - 3), min(max(y, 3), PAGE - 3)) for x, y in s] for s in page]
    return [circle(CENTER, CENTER, RADIUS)] + page


def jitter_traced(strokes, rng):
    """a hand's version of a traced page: a bit turned, stretched and shaky"""
    a = math.radians(rng.uniform(-6, 6))
    k = rng.uniform(0.94, 1.06)
    c, s = math.cos(a), math.sin(a)
    out = []
    for st in strokes:
        out.append([(CENTER + ((x - CENTER) * c - (y - CENTER) * s) * k + rng.gauss(0, 0.5),
                     CENTER + ((x - CENTER) * s + (y - CENTER) * c) * k + rng.gauss(0, 0.5)) for x, y in st])
    return out


def thin(stroke, step=1.4):
    kept = [stroke[0]]
    for i, p in enumerate(stroke[1:], 1):
        if i == len(stroke) - 1 or math.dist(p, kept[-1]) >= step:
            kept.append(p)
    return kept


ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


def encode(strokes):
    """strokes -> 'xxyy..|..': every coordinate in tenths of a gui unit as two base-64 digits"""
    parts = []
    for st in strokes:
        s = []
        for x, y in thin(st):
            for v in (x, y):
                n = max(0, min(4095, int(round(v * 10))))
                s.append(ALPHABET[n // 64] + ALPHABET[n % 64])
        parts.append("".join(s))
    return "|".join(parts)


def lua_strokes(lua, strokes):
    t = lua.table()
    for i, s in enumerate(strokes):
        t[i + 1] = lua.table_from([lua.table_from({"x": x, "y": y}) for x, y in s])
    return t


def compile_page(lua, strokes):
    """-> (spell table or None, serialized or error text, seal tree or None)"""
    res = lua.eval("parse_seal")(lua_strokes(lua, strokes))
    seal = res[0] if isinstance(res, tuple) else res
    err = res[1] if isinstance(res, tuple) and len(res) > 1 else None
    if not seal:
        return None, err, None
    res = lua.eval("compile_spell")(seal)
    spell = res[0] if isinstance(res, tuple) else res
    if not spell:
        return None, res[1] if isinstance(res, tuple) else "?", seal
    return spell, lua.eval("serialize_spell")(spell), seal


# How big a book a seal needs (files/books.lua): a sigil and a few signs, nothing else, drawn simply, fit the Palm
# Quire's round page; the most intricate drawings need the Great Tome; the rest the Spellbook
QUIRE_SYMBOLS = 6
QUIRE_POINTS = 480
TOME_POINTS = 1400


def points(encoded):
    """how intricate a page is: the points of its encoded strokes (as sheets.lua counts them)"""
    return (len(encoded) - encoded.count("|")) / 4


def book_size(spell, encoded):
    if spell.book:
        return spell.book
    n = points(encoded)
    if n >= TOME_POINTS:
        return "tome"
    simple = spell.symbols is not None and all(s[0] in ("sigil", "sign") for s in spell.symbols)
    if simple and len(spell.symbols) <= QUIRE_SYMBOLS and n <= QUIRE_POINTS:
        return "quire"
    return "book"


def recipe_signature(spell):
    """the symbols a recipe draws (seal_canon.lua seal_symbols_key): "sigil:fire=1,sign:column=4" (the main seal's only)"""
    if spell.symbols is None:
        return ""
    counts = {}
    for item in spell.symbols:
        if item[0] in ("sigil", "sign"):
            k = f"{item[0]}:{item[1]}"
            counts[k] = counts.get(k, 0) + 1
    return ",".join(f"{k}={counts[k]}" for k in sorted(counts))


def apply_cast(data, cast):
    """the page's serialized spell with the seal's own meaning over it (Spell.cast)"""
    if not cast:
        return data
    main, sep, rest = data.partition("&")
    fields, order = {}, []
    for part in main.split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            fields[k] = v
            order.append(k)
    behaviors = {}
    if "b" in fields:
        for item in fields.pop("b").split(","):
            name, w = item.split(":")
            behaviors[name] = w
        order.remove("b")
    for k, v in cast.items():
        if k == "b":
            # Unknown signs on a whole seal may resemble unrelated behaviors.
            # An explicit behavior set replaces that accidental reading.
            behaviors = {name: str(w) for name, w in v.items()}
        elif k == "b+":
            for name, w in v.items():
                behaviors[name] = str(w)
        elif v is False:
            if k in fields:
                del fields[k]
                order.remove(k)
        else:
            if k not in fields:
                order.append(k)
            fields[k] = "true" if v is True else str(v)
    out = ";".join(f"{k}={fields[k]}" for k in order)
    if behaviors:
        out += ";b=" + ",".join(f"{k}:{w}" for k, w in behaviors.items())
    return out + (sep + rest if sep else "")


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def write_lua(entries, path=None):
    path = path or OUT  # read when called: a test points OUT at a file of its own
    lines = [
        "-- Generated by tools/make_grimoire.py from tools/grimoire.py - do not edit by hand.",
        "-- The spells of the Independent Witch Hat Atelier Wiki as seals on the book's pages: the book shows them in",
        "-- its wiki section, and a drawing close enough to one of them is that seal (seal_canon.lua, seal_canonical).",
        "--   key, name, en (the wiki's name), category, manifest (cast.lua MANIFESTS), forbidden, status,",
        "--   effect (what it does in the game), spell (serialize_spell of the page), symbols (what the page reads as:",
        "--   seal_symbols_key; empty: the book knows it only as a whole), recipe (the symbols it is drawn of),",
        "--   book (the smallest book it fits in, books.lua: none - the Spellbook), middle and middle_reach (the sigil in",
        "--   the middle of a seal that takes any sigil, and how far it reaches: seal_canon.lua middle_sigil), strokes",
        "--   (grimoire_strokes)",
        "",
        "GRIMOIRE = {",
    ]
    for e in entries:
        fields = [f"key = {lua_string(e['key'])}", f"name = {lua_string(e['name'])}", f"en = {lua_string(e['en'])}",
                  f"category = {lua_string(e['category'])}", f"status = {lua_string(e['status'])}",
                  f"effect = {lua_string(e['effect'])}", f"spell = {lua_string(e['spell'])}"]
        if e.get("manifest"):
            fields.append(f"manifest = {lua_string(e['manifest'])}")
        if e.get("forbidden"):
            fields.append("forbidden = true")
        fields.append(f"symbols = {lua_string(e.get('symbols', ''))}")
        if e.get("recipe"):
            fields.append(f"recipe = {lua_string(e['recipe'])}")
        if e.get("book", "book") != "book":
            fields.append(f"book = {lua_string(e['book'])}")
        if e.get("middle"):
            fields.append(f"middle = {lua_string(e['middle'])}, middle_reach = {e['middle_reach']}")
        fields.append(f"strokes = {lua_string(e['strokes'])}")
        lines.append("\t{ " + ", ".join(fields) + " },")
    lines += [
        "}",
        "",
        "GRIMOIRE_BY_KEY = {}",
        "for _, entry in ipairs( GRIMOIRE ) do GRIMOIRE_BY_KEY[entry.key] = entry end",
        "",
        "-- An entry's strokes: { { { x = , y = }, ... }, ... } on the Spellbook's page (180 x 180, the ring around 90, 90);",
        "-- the other books scale them to their pages",
        "local DIGITS = \"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"",
        "local VALUE = {}",
        "for i = 1, #DIGITS do VALUE[DIGITS:sub( i, i )] = i - 1 end",
        "function grimoire_strokes( entry )",
        "\tif entry.decoded then return entry.decoded end",
        "\tlocal strokes = {}",
        "\tfor part in entry.strokes:gmatch( \"[^|]+\" ) do",
        "\t\tlocal stroke = {}",
        "\t\tfor i = 1, #part - 3, 4 do",
        "\t\t\tlocal x = VALUE[part:sub( i, i )] * 64 + VALUE[part:sub( i + 1, i + 1 )]",
        "\t\t\tlocal y = VALUE[part:sub( i + 2, i + 2 )] * 64 + VALUE[part:sub( i + 3, i + 3 )]",
        "\t\t\tstroke[#stroke + 1] = { x = x / 10, y = y / 10 }",
        "\t\tend",
        "\t\tif #stroke > 0 then strokes[#strokes + 1] = stroke end",
        "\tend",
        "\tentry.decoded = strokes",
        "\treturn strokes",
        "end",
    ]
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


def page_strokes(lua, spell, rng=None):
    if spell.symbols is not None:
        return render_recipe(lua, spell, rng)
    strokes = render_traced(spell)
    return jitter_traced(strokes, rng) if rng else strokes


SPELL_BY_KEY = {s.key: s for s in G.SPELLS}


def build(only=None, verbose=True, keep_spells=False):
    lua = lua_runtime()
    preserved = {}
    if only and os.path.exists(OUT):
        # Rebuild selected seals without retracing or recompiling unrelated pages.
        with open(OUT, encoding="utf-8") as source:
            lua.execute(source.read())
        for entry in lua.eval("GRIMOIRE").values():
            preserved[entry["key"]] = {k: v for k, v in entry.items() if k != "decoded"}
    entries = []
    pages = {}
    for spell in G.SPELLS:
        if only and spell.key not in only:
            if spell.key in preserved:
                entries.append(preserved[spell.key])
            continue
        strokes = page_strokes(lua, spell)
        pages[spell.key] = strokes
        encoded = encode(strokes)
        entries.append({"key": spell.key, "name": spell.name, "en": spell.en, "category": spell.category, "status": spell.status,
                        "effect": spell.effect, "manifest": spell.manifest, "forbidden": spell.forbidden,
                        "strokes": encoded, "spell": "", "recipe": recipe_signature(spell), "book": book_size(spell, encoded),
                        "middle": spell.middle and spell.middle[0], "middle_reach": spell.middle and spell.middle[1]})
    # first without the spells, so the canonical matcher can see every page; then compile each page
    write_lua(entries)
    lua = lua_runtime()
    lua.execute(open(OUT, encoding="utf-8").read())
    report = []
    for e in entries:
        if e["key"] not in pages:
            continue
        # the page as drawn (dense, a point about every gui unit, like the book records the mouse): the stored strokes
        # are thinned for the page, which is enough to show it and to compare whole seals
        strokes = pages[e["key"]]
        spell, data, seal = compile_page(lua, strokes)
        # what the page reads as, symbol by symbol: a drawing is this seal only with the same symbols (seal_name)
        # (a seal traced from the wiki's picture reads as whatever its lines look like: the book knows it only as a whole)
        definition = SPELL_BY_KEY[e["key"]]
        e["symbols"] = lua.eval("seal_symbols_key")(seal["symbols"]) if spell is not None and definition.symbols is not None and not definition.whole_only else ""
        if spell is None:
            # a seal whose symbols the book can't read (traced from the wiki): only its whole shape names it
            named = lua.eval("seal_named_fallback")(lua_strokes(lua, strokes))
            named_key = named[0] if isinstance(named, tuple) else named
            data = f"element=light;form=burst;named={e['key']}" + (f";manifest={e['manifest']}" if e.get("manifest") else "")
            report.append((e["key"], "whole" if named_key == e["key"] else f"UNREAD ({data})", named_key))
        else:
            report.append((e["key"], spell["summary"], spell["named"]))
        # forbidden or not is the wiki's word, not what the page's symbols happen to read as
        cast = dict(SPELL_BY_KEY[e["key"]].cast)
        cast["forbidden"] = bool(e.get("forbidden"))
        e["spell"] = apply_cast(data, cast)
        # a page only redrawn casts what it cast and fits the book it fitted
        old = preserved.get(e["key"])
        if keep_spells and old:
            e["spell"], e["symbols"] = old["spell"], old.get("symbols") or ""
            e["book"] = old.get("book") or "book"
    write_lua(entries)
    if verbose:
        books = {e["key"]: e.get("book", "book") for e in entries}
        for key, what, named in report:
            flag = "" if named == key else "   <-- named " + str(named)
            print(f"{key:28s} {books[key]:5s} {what}{flag}")
    return entries, pages


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="comma separated keys")
    ap.add_argument("--keep-spells", action="store_true",
                    help="with --only: the pages are redrawn, their stored spell, symbols and book stay as they were")
    args = ap.parse_args()
    only = set(args.only.split(",")) if args.only else None
    entries, _ = build(only, keep_spells=args.keep_spells)
    print(f"written {OUT}: {len(entries)} seals")


if __name__ == "__main__":
    main()
