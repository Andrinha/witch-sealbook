"""Offline tests for the witch_notebook mod: runs the mod's Lua code in LuaJIT with stubbed Noita API.
Seals are generated from the mod's own templates (a ring, a sigil, signs around it) and parsed back.

Usage (from the mod folder):  python tests/run_tests.py        (needs: pip install lupa)
"""
import json
import math
import os
import random
import re
import sys
import time

from lupa import luajit21

from harness import (MOD, DATA, STUBS, CAST_STUBS, MOD_FILES, SEAL_FILES, DOFILE, read_game_file, bare_runtime,  # noqa: F401
                     load_mod, load_cast)

SAMPLES = 100

# ---- synthetic hand-drawn seals: strokes of (x, y) in page coordinates (the page is 180x180) ----

def poly(corners, n=20):
    out = []
    for (ax, ay), (bx, by) in zip(corners, corners[1:]):
        out += [(ax + (bx - ax) * t / n, ay + (by - ay) * t / n) for t in range(n)]
    return out + [corners[-1]]


TEMPLATES = {}


def templates(lua):
    """sigil and sign shapes from the mod's templates.lua, as lists of strokes of (x, y)"""
    if not TEMPLATES:
        for kind, table in [("sigil", "TEMPLATES_SIGILS"), ("sign", "TEMPLATES_SIGNS")]:
            for key, shapes in lua.eval(table).items():
                TEMPLATES[(kind, key)] = [[(p[1], p[2]) for p in st.values()] for st in shapes[1].values()]
    return TEMPLATES


def hand(strokes):
    """A hand's version of a template: slightly stretched, sheared and wobbly"""
    sx, sy, shear = random.uniform(0.88, 1.12), random.uniform(0.88, 1.12), random.uniform(-0.1, 0.1)
    out = []
    for s in strokes:
        phase, freq = random.uniform(0, 6.3), random.uniform(1, 3)
        out.append([(x * sx + y * shear + 0.012 * math.sin(phase + i * freq / len(s) * 6.3), y * sy + 0.012 * math.cos(phase + i * freq / len(s) * 6.3))
                    for i, (x, y) in enumerate(s)])
    return out


def densify(stroke, step=1.0):
    """Points every 'step' gui units along the stroke, like the notebook records the mouse"""
    out = [stroke[0]]
    for a, b in zip(stroke, stroke[1:]):
        n = max(1, int(math.dist(a, b) / step))
        out += [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(1, n + 1)]
    return out


def place(strokes, cx, cy, size, angle=0.0, tilt=0.15, noise=0.25):
    """Center at cx, cy, scale the larger side to size, turn by angle (+ a hand's tilt); points every
    gui unit with a hand's tremor (smooth) and a little jitter"""
    a = angle + random.uniform(-tilt, tilt)
    xs = [x for s in strokes for x, _ in s]; ys = [y for s in strokes for _, y in s]
    mx, my = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    k = size / max(max(xs) - min(xs), max(ys) - min(ys), 1e-6)
    out = []
    for s in strokes:
        pts = densify([(cx + (x - mx) * k * math.cos(a) - (y - my) * k * math.sin(a),
                        cy + (x - mx) * k * math.sin(a) + (y - my) * k * math.cos(a)) for x, y in s])
        phase, amp = random.uniform(0, 6.3), random.uniform(0.2, 0.6)
        out.append([(x + amp * math.sin(phase + i / 7) + random.gauss(0, noise), y + amp * math.cos(phase + i / 9) + random.gauss(0, noise))
                    for i, (x, y) in enumerate(pts)])
    return out


def ring(share=None, r=None):
    share = share or random.uniform(1.0, 1.08)
    r = r or random.uniform(64, 76); ar = random.uniform(0.95, 1.05); a0 = random.uniform(0, 2 * math.pi); d = random.choice([1, -1])
    cx, cy = 90 + random.uniform(-3, 3), 90 + random.uniform(-3, 3)
    return [(cx + r * math.cos(a0 + d * t * share * 2 * math.pi) + random.gauss(0, 0.8),
             cy + ar * r * math.sin(a0 + d * t * share * 2 * math.pi) + random.gauss(0, 0.8)) for t in [i / 160 for i in range(161)]], (cx, cy, r)


def prepared_ring():
    """A ring drawn with a gap, and the short stroke that closes it: (arc, closing stroke, (cx, cy, r))"""
    r = random.uniform(64, 72); a0 = random.uniform(0, 2 * math.pi); d = random.choice([1, -1]); share = random.uniform(0.8, 0.88)
    cx, cy = 90 + random.uniform(-3, 3), 90 + random.uniform(-3, 3)
    point = lambda t: (cx + r * math.cos(a0 + d * t * 2 * math.pi) + random.gauss(0, 0.6), cy + r * math.sin(a0 + d * t * 2 * math.pi) + random.gauss(0, 0.6))
    arc = [point(share * i / 140) for i in range(141)]
    closing = [point(share - 0.02 + (1.03 - share) * i / 30) for i in range(31)]
    return arc, closing, (cx, cy, r)


def prepared_seal(lua):
    """A fire sigil and two columns in a ring with a gap: (strokes without the closing stroke, with it)"""
    arc, closing, (cx, cy, r) = prepared_ring()
    t = templates(lua)
    symbols = place(hand(t[("sigil", "fire")]), cx, cy, r * 0.45)
    for deg in (0, 180):
        a = math.radians(deg)
        symbols += place(hand(t[("sign", "column")]), cx + 0.7 * r * math.cos(a), cy + 0.7 * r * math.sin(a), r * 0.23, a - math.pi / 2)
    return [arc] + symbols, [arc] + symbols + [closing]


def close_ring(strokes):
    """Draw arcs over the gaps of the ring made by the two longest strokes, as a player would"""
    ring = sorted(strokes, key=lambda st: -length([st]))[:2]
    xs = [x for st in ring for x, _ in st]; ys = [y for st in ring for _, y in st]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    r = sum(math.dist(p, (cx, cy)) for st in ring for p in st) / sum(len(st) for st in ring)
    angs = sorted(math.atan2(y - cy, x - cx) for st in ring for x, y in st)
    gaps = [(b - a, a) for a, b in zip(angs, angs[1:])] + [(angs[0] + 2 * math.pi - angs[-1], angs[-1])]
    return strokes + [[(cx + r * math.cos(start - 0.05 + (gap + 0.1) * i / 20), cy + r * math.sin(start - 0.05 + (gap + 0.1) * i / 20)) for i in range(21)]
                      for gap, start in gaps if gap > 0.15]


def seal(lua, sigils=(), signs=(), closed=True, extra=(), sign_dist=(0.66, 0.74)):
    """sigils: keys (one in the center, two side by side); signs: (key, angle in degrees, inverted[, turned
    sideways by degrees])"""
    t = templates(lua)
    rstroke, (cx, cy, r) = ring() if closed else ring(random.uniform(0.6, 0.8))
    strokes = [rstroke]
    spots = {1: [(0, 0)], 2: [(-0.27, 0), (0.27, 0)]}.get(len(sigils), [(-0.3, -0.15), (0.3, -0.15), (0, 0.25)])
    for key, (ox, oy) in zip(sigils, spots):
        strokes += place(hand(t[("sigil", key)]), cx + ox * r, cy + oy * r, r * random.uniform(0.4, 0.5) / (1 if len(sigils) == 1 else 1.6))
    for key, deg, inverted, *turn in signs:
        a = math.radians(deg + random.uniform(-5, 5)); dist = random.uniform(*sign_dist) * r
        strokes += place(hand(t[("sign", key)]), cx + dist * math.cos(a), cy + dist * math.sin(a), r * random.uniform(0.2, 0.26),
                         a - math.pi / 2 + (math.pi if inverted else 0) + math.radians(turn[0] if turn else 0))
    strokes += list(extra)
    random.shuffle(strokes)
    return strokes


def scribble():
    x, y = random.uniform(80, 100), random.uniform(80, 100); pts = []
    for _ in range(30):
        x += random.gauss(0, 4); y += random.gauss(0, 4); pts.append((x, y))
    return [pts]


def clean_ring():
    return [(90 + 68 * math.cos(t / 90 * 2 * math.pi), 90 + 68 * math.sin(t / 90 * 2 * math.pi)) for t in range(91)]


def wobbly_ring():
    return [(90 + 68 * (1 + 0.28 * math.sin(5 * a)) * math.cos(a), 90 + 68 * (1 + 0.28 * math.sin(5 * a)) * math.sin(a))
            for a in [t / 90 * 2 * math.pi for t in range(91)]]


def lua_strokes(lua, strokes):
    t = lua.table()
    for i, s in enumerate(strokes):
        t[i + 1] = lua.table_from([lua.table_from({"x": x, "y": y}) for x, y in s])
    return t


def length(strokes):
    return sum(math.dist(a, b) for s in strokes for a, b in zip(s, s[1:]))


def run(lua, strokes):
    """-> (serialized spell without precision, spell) or (error text, None)"""
    res = lua.eval("parse_seal")(lua_strokes(lua, strokes))
    tree, err = (res[0], res[1]) if isinstance(res, tuple) else (res, None)
    if not tree:
        return err, None
    res = lua.eval("compile_spell")(tree)
    spell, err = res if isinstance(res, tuple) else (res, None)
    if not spell:
        return err, None
    return f"{spell['element']}:{spell['form']}", spell


PAIR = [0, 180]
CROSS = [0, 90, 180, 270]


def invertible(lua, key):
    """does drawing the sign facing outwards mean something else?"""
    d = lua.eval("DICTIONARY_SIGNS")[key]
    if (d["symmetry"] or 1) % 2 == 0 or d["invertible"] is False:
        return False
    inv = d["inverted"]
    if not inv:
        return True
    return any(inv[f] != d[f] for f in ("behavior", "form", "vote", "heavy", "condense"))


def element_sigils(lua):
    """{element: the sigil that stands for it} - the element sigils (the Sigil of Aeriforms for air)"""
    out = {}
    sigils = lua.eval("DICTIONARY_SIGILS")
    order = list(lua.eval("DICTIONARY_CENTER_ORDER").values())
    for pure in (True, False):
        for key in order:
            d = sigils[key]
            if d["element"] and pure == (not (d["manifest"] or d["behavior"] or d["shape"])):
                out.setdefault(d["element"], key)
    return out


def test_symbols(lua):
    """Every sigil in the center of a ring, every sign in pairs around a sigil, upright and inverted (80% each: with the
    wiki's 31 sigils and 36 signs a few look much alike - the Sign of Expansion is two arrows of Regions)"""
    random.seed(1)
    parse = lua.eval("parse_seal"); ok = True; n = SAMPLES // 2; started = time.perf_counter()
    for key in lua.eval("DICTIONARY_CENTER_ORDER").values():
        got = {}
        for _ in range(n):
            res = parse(lua_strokes(lua, seal(lua, [key])))
            tree = res[0] if isinstance(res, tuple) else res
            k = ",".join(f"{s['kind']}:{s['key']}" for s in tree["symbols"].values()) if tree else "-"
            if tree:
                compiled = lua.eval("compile_spell")(tree)
                if isinstance(compiled, tuple) and compiled[0] is None:
                    k += " (rejected: " + compiled[1] + ")"
            got[k] = got.get(k, 0) + 1
        right = got.get(f"sigil:{key}", 0)
        print(f"  sigil {key:12s} {right:3d}/{n}  {({k: v for k, v in got.items() if k != 'sigil:' + key}) or ''}")
        ok &= right >= n * 0.8
    for key in lua.eval("DICTIONARY_SIGN_ORDER").values():
        symmetric = not invertible(lua, key)  # looks the same turned around, or means the same
        for inverted in (False,) if symmetric else (False, True):
            right = 0; other = {}
            for _ in range(n):
                base = random.uniform(0, 360)
                res = parse(lua_strokes(lua, seal(lua, ["fire"], [(key, base, inverted), (key, base + 180, inverted)])))
                tree = res[0] if isinstance(res, tuple) else res
                signs = [s for s in tree["symbols"].values() if s["kind"] == "sign"] if tree else []
                compiled = lua.eval("compile_spell")(tree) if tree else None
                accepted = compiled is not None and not (isinstance(compiled, tuple) and compiled[0] is None)
                good = accepted and len(signs) == 2 and all(s["key"] == key and (symmetric or bool(s["inverted"]) == inverted) for s in signs)
                right += good
                if not good:
                    k = ",".join(f"{s['key']}{'~' if s['inverted'] else ''}" for s in signs) if tree else res[1]
                    if tree and not accepted:
                        k += " (rejected: " + compiled[1] + ")"
                    other[k] = other.get(k, 0) + 1
            print(f"  sign  {key + (' inverted' if inverted else ''):20s} {right:3d}/{n}  {other or ''}")
            ok &= right >= n * 0.8
    count = len(lua.eval("DICTIONARY_CENTER_ORDER")) + sum(2 if invertible(lua, k) else 1 for k in lua.eval("DICTIONARY_SIGN_ORDER").values())
    print(f"  parse time: {(time.perf_counter() - started) / (n * count) * 1000:.0f} ms per seal")
    return ok


def test_seals(lua):
    cases = [
        ("fire alone", lambda: seal(lua, ["fire"]), "fire:burst"),
        ("water + 2 columns", lambda: seal(lua, ["water"], [("column", 0, False), ("column", 180, False)]), "water:column"),
        ("water + 4 levitation (Water Orb)", lambda: seal(lua, ["water"], [("levitation", a, False) for a in CROSS]), "water:levitation"),
        ("water + 2 convergence + 2 columns", lambda: seal(lua, ["water"], [("convergence", 90, False), ("convergence", 270, False), ("column", 0, False), ("column", 180, False)]), "ice:column"),
        ("wind + 2 convergence", lambda: seal(lua, ["wind"], [("convergence", 0, False), ("convergence", 180, False)]), "vacuum:burst"),
        ("earth + 2 dispersion", lambda: seal(lua, ["earth"], [("dispersion", 90, False), ("dispersion", 270, False)]), "earth:dispersion"),
        ("light + 2 inverted columns", lambda: seal(lua, ["light"], [("column", 0, True), ("column", 180, True)]), "light:dispersion"),
        ("two fire sigils", lambda: seal(lua, ["fire", "fire"], [("column", 90, False), ("column", 270, False)]), "fire:column"),
        ("fire + 2 columns close to it", lambda: seal(lua, ["fire"], [("column", 0, False), ("column", 180, False)], sign_dist=(0.46, 0.52)), "fire:column"),
        ("water + 2 levitation close to it", lambda: seal(lua, ["water"], [("levitation", 90, False), ("levitation", 270, False)], sign_dist=(0.48, 0.54)), "water:levitation"),
        ("fire + water (steam)", lambda: seal(lua, ["fire", "water"]), "steam:burst"),
        ("wind + light + 2 columns (lightning)", lambda: seal(lua, ["wind", "light"], [("column", 90, False), ("column", 270, False)]), "thunder:column"),
        ("fire + water + 2 convergence", lambda: seal(lua, ["fire", "water"], [("convergence", 90, False), ("convergence", 270, False)]), "steamblast:burst"),
        # A hand drawing may be refused as unreadable too; exact element limits are checked on trees below.
        ("fire + earth + light", lambda: seal(lua, ["fire", "earth", "light"]), "reject"),
        ("only signs", lambda: seal(lua, [], [("column", 0, False), ("column", 180, False)]), "No element sigil"),
        ("empty ring", lambda: seal(lua, []), "shockwave:burst"),
        ("unclosed ring", lambda: seal(lua, ["fire"], closed=False), "The ring is not closed"),
        ("ring with a small gap (prepared)", lambda: prepared_seal(lua)[0], "The ring is not closed"),
        ("the same ring closed", lambda: prepared_seal(lua)[1], "fire:column"),
        ("no ring", lambda: place(hand(templates(lua)[("sigil", "fire")]), 90, 90, 60), "No ring - the seal does nothing"),
        ("scribble in the ring", lambda: seal(lua, [], extra=scribble()), "reject"),
    ]
    ok = True
    for i, (name, make, expected) in enumerate(cases):
        random.seed(200 + i)
        passed = 0; seen = {}
        for _ in range(SAMPLES // 2):
            got, spell = run(lua, make())
            seen[got] = seen.get(got, 0) + 1
            passed += (spell is None if expected == "reject" else got == expected)
        other = seen if expected == "reject" else {k: v for k, v in seen.items() if k != expected}
        print(f"  {name:36s} {passed:3d}/{SAMPLES // 2}  {('other: ' + str(other)) if other else ''}")
        ok &= passed >= SAMPLES // 2 * 0.8
    return ok


def test_mixes(lua):
    """Every pair of different sigils side by side mixes into its element; the order doesn't matter"""
    mixes = {k: v for k, v in lua.eval("DICTIONARY_MIXES").items()}
    ok = True; n = SAMPLES // 5; results = []
    sigil = element_sigils(lua)
    for i, (pair, mix) in enumerate(sorted(mixes.items())):
        random.seed(300 + i)
        a, b = (sigil[e] for e in pair.split("+"))
        right = sum(run(lua, seal(lua, [a, b] if j % 2 else [b, a]))[0] == f"{mix}:burst" for j in range(n))
        results.append(f"{mix} {right}/{n}")
        ok &= right >= n * 0.8
    print("  " + ", ".join(results))
    random.seed(9)
    _, one = run(lua, seal(lua, ["fire", "water"]))
    _, doubled = run(lua, seal(lua, ["fire", "fire", "water"]))
    print(f"  steam force: fire + water {one['force'] if one else None}, fire + fire + water {doubled['force'] if doubled else None}")
    return ok and one and doubled and doubled["force"] > one["force"] and doubled["element"] == "steam"


def test_carriers():
    """init builds every element's projectiles from the templates: well-formed XML, nothing left unfilled"""
    import xml.dom.minidom
    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    lua.globals().MOD = MOD.replace("\\", "/") + "/"
    lua.execute(r'''
        files = {}
        function ModTextFileGetContent(f)
            local path = f:gsub("^mods/witch_notebook/", MOD)
            if f:find("^data/") then return '<Entity><ParticleEmitterComponent emitted_material_name="water" /></Entity>' end
            local h = io.open(path, "rb"); local c = h:read("*a"); h:close(); return c
        end
        function ModTextFileSetContent(f, c) files[f] = c end
    ''')
    for f in ["files/dictionary.lua", "files/carriers.lua"]:
        lua.execute(open(os.path.join(MOD, f), encoding="utf-8").read())
    lua.eval("carriers_create")()
    files = dict(lua.eval("files").items())
    bad = [f for f, c in files.items() if "{{" in c]
    for f, c in files.items():
        try:
            xml.dom.minidom.parseString(c.encode("utf-8"))
        except Exception as e:  # noqa: BLE001
            bad.append(f"{f}: {e}")
    looks = list(lua.eval("DICTIONARY_LOOKS").keys())
    need = [f"mods/witch_notebook/files/entities/carriers/{c}_{k}.xml" for k in looks for c in ("bolt", "orb", "field", "splash")]
    missing = [f for f in need if f not in files]
    names = lua.eval("names")
    sprites = all(names[f"mods/witch_notebook/files/gfx/{c}_{k}.png"] for k in looks for c in ("bolt", "orb"))
    # a splash's drop: short-lived, a share of the shot's damage of each kind
    base = lua.eval("DICTIONARY_CARRIER_BASE")

    def projectile(f):
        c = files[f"mods/witch_notebook/files/entities/carriers/{f}.xml"]
        life = int(re.search(r'lifetime="(\d+)"', c).group(1))
        kinds = dict((k, float(v)) for k, v in re.findall(r'(\w+)="([\d.]+)"', re.search(r"<damage_by_type([^>]*)>", c).group(1)))
        return life, kinds
    drop, shot = projectile("splash_fire"), projectile("bolt_fire")
    splash_ok = (drop[0] == base["splash_lifetime"] < shot[0] and drop[1].keys() == shot[1].keys()
                 and all(abs(drop[1][k] - shot[1][k] * base["splash_damage"]) < 1e-6 for k in shot[1]))
    print(f"  {len(files)} carriers for {len(looks)} elements, broken {bad or 'none'}, missing {missing or 'none'}, sprites {sprites}; "
          f"a fire splash's drop {drop}, a fire shot {shot}")
    # every effect of every element and form resolves to a carrier that exists or a game file
    effect = lua.eval("dictionary_effect")
    elements = [k for k in lua.eval("DICTIONARY_ELEMENTS").keys()]
    # a wave out from the seal and a ring are the seal's own magic (manifest.lua), not projectiles
    unresolved = [f"{e}:{f}" for e in elements for f in ("column", "dispersion", "levitation", "burst", "field")
                  if not effect(e, f) or (effect(e, f)["carrier"] not in ("nova", "ring") and effect(e, f)["file"].startswith("mods/")
                                          and effect(e, f)["file"] not in files)]
    print(f"  effects of {len(elements)} elements x 5 forms, unresolved: {unresolved or 'none'}")
    return not bad and not missing and sprites and not unresolved and splash_ok


def test_behaviors(lua):
    """Signs add up: each adds its behavior to the spell, the form comes from the signs that shape it"""
    cases = [
        ("fire + 2 pull", ["fire"], [("pull", 0, False), ("pull", 180, False)], "fire:burst", {"pull"}),
        ("fire + 2 inverted pull", ["fire"], [("pull", 0, True), ("pull", 180, True)], "fire:burst", {"push"}),
        ("earth + 2 columns + 2 crush", ["earth"], [("column", 0, False), ("column", 180, False), ("crush", 90, False), ("crush", 270, False)],
         "earth:column", {"thrust", "crush"}),
        ("earth + 2 inverted crush", ["earth"], [("crush", 90, True), ("crush", 270, True)], "earth:burst", {"build"}),
        ("light + 2 columns + 2 pierce", ["light"], [("column", 90, False), ("column", 270, False), ("pierce", 0, False), ("pierce", 180, False)],
         "light:column", {"thrust", "pierce"}),
        ("water + 2 columns + 2 crosshair", ["water"], [("column", 0, False), ("column", 180, False), ("crosshair", 90, False), ("crosshair", 270, False)],
         "water:column", {"thrust", "homing"}),
        ("fire + 2 expansion", ["fire"], [("expansion", 90, False), ("expansion", 270, False)], "fire:burst", {"grow"}),
        ("fire + 2 inverted expansion", ["fire"], [("expansion", 90, True), ("expansion", 270, True)], "fire:burst", {"shrink"}),
        ("wind + 2 columns + 2 stability", ["wind"], [("column", 0, False), ("column", 180, False), ("stability", 90, False), ("stability", 270, False)],
         "wind:column", {"thrust", "still"}),
        ("water + 2 levitation + 2 columns (rising platform)", ["water"],
         [("levitation", 0, False), ("levitation", 180, False), ("column", 90, False), ("column", 270, False)], None, {"thrust", "float"}),
        ("earth + 4 columns turned the same way (spin)", ["earth"], [("column", a, False, 30) for a in CROSS], "earth:column", {"thrust", "spin"}),
        ("fire + pull + inverted pull (cancel out)", ["fire"], [("pull", 0, False), ("pull", 180, True)], "fire:burst", set()),
        ("fire + 2 pierce (more drops in the splash)", ["fire"], [("pierce", 0, False), ("pierce", 180, False)], "fire:burst", {"pierce"}),
        ("fire + 2 crosshair (the splash's drops home in)", ["fire"], [("crosshair", 0, False), ("crosshair", 180, False)], "fire:burst", {"homing"}),
        # Dispersion held by Stability: a field round the caster; it can't pierce
        ("fire + dispersion + stability (a field)", ["fire"], [("dispersion", 90, False), ("stability", 0, False), ("dispersion", 270, False),
                                                              ("stability", 180, False)], "fire:field", set()),
        ("fire + dispersion + stability + 2 pierce (a field can't pierce)", ["fire"],
         [("dispersion", 90, False), ("stability", 0, False), ("pierce", 45, False), ("dispersion", 270, False), ("stability", 180, False),
          ("pierce", 225, False)], "fire:field", set()),
    ]
    ok = True
    for i, (name, sigils, signs, form, want) in enumerate(cases):
        random.seed(500 + i)
        n = SAMPLES // 5; right = 0; seen = {}
        for _ in range(n):
            got, spell = run(lua, seal(lua, sigils, signs))
            have = set(spell["behaviors"].keys()) if spell else set()
            good = spell is not None and have == want and (form is None or got == form)
            right += good
            if not good:
                k = f"{got} {sorted(have)}"
                seen[k] = seen.get(k, 0) + 1
        print(f"  {name:52s} {right:3d}/{n}  {seen or ''}")
        ok &= right >= n * 0.8
    random.seed(7)
    _, spell = run(lua, seal(lua, ["light"], [("column", 90, False), ("column", 270, False), ("pierce", 0, False), ("pierce", 180, False)]))
    data = lua.eval("serialize_spell")(spell)
    print(f"  '{spell['summary']}': {data}")
    ok &= spell["behaviors"]["pierce"] == 2 and "pierces x2" in spell["summary"] and ";b=thrust:" in data and "pierce:2" in data
    # a seal whose signs point straight to the center doesn't spin; the way they turn is the spin's
    spins = []
    for turn in (0, 30, -30, 55):
        random.seed(40)
        _, sp = run(lua, seal(lua, ["earth"], [("column", a, False, turn) for a in CROSS]))
        spins.append(sp["behaviors"]["spin"] if sp and "spin" in sp["behaviors"] else 0)
    print(f"  spin of 4 columns turned 0, 30, -30, 55 degrees: {spins}")
    ok &= spins[0] == 0 and spins[1] * spins[2] < 0 and spins[3] > spins[1]
    random.seed(42)
    _, one_arrow = run(lua, seal(lua, ["earth"], [("column", 90, False, 45)]))
    random.seed(42)
    _, two_arrows = run(lua, seal(lua, ["earth"], [("column", 90, False, 45), ("column", 270, False, 45)]))
    one_spins = one_arrow and "spin" in one_arrow["behaviors"]
    two_spins = two_arrows and "spin" in two_arrows["behaviors"]
    print(f"  one turned arrow spins {one_spins}, two turned arrows spin {two_spins}")
    ok &= one_spins is False and two_spins is True
    # the price of complexity
    random.seed(41)
    four = [run(lua, seal(lua, ["fire"], [("column", a, False) for a in CROSS]))[1]["precision"] for _ in range(10)]
    random.seed(41)
    eight = [run(lua, seal(lua, ["fire"], [("column", a, False) for a in CROSS] + [("pierce", a + 45, False) for a in CROSS]))[1]["precision"]
             for _ in range(10)]
    print(f"  precision with 4 signs {sum(four) / 10:.2f}, with 8 signs {sum(eight) / 10:.2f}")
    return ok and sum(eight) < sum(four)


def sign_variants(lua):
    """every sign, and every sign that can be inverted inverted: [(key, inverted)]"""
    order = list(lua.eval("DICTIONARY_SIGN_ORDER").values())
    return [(k, False) for k in order] + [(k, True) for k in order if invertible(lua, k)]


def seal_tree(lua, sigils, signs):
    """a seal tree as parse_seal returns it: sigils in the middle, signs evenly around"""
    syms = [lua.table_from({"kind": "sigil", "key": k, "angle": 0, "dist": 0.1, "size": 0.45 / (1 if len(sigils) == 1 else 1.6),
                            "score": 0.8, "inverted": False}) for k in sigils]
    for i, (k, inverted) in enumerate(signs):
        syms.append(lua.table_from({"kind": "sign", "key": k, "angle": 2 * math.pi * i / len(signs), "dist": 0.7, "size": 0.25,
                                    "score": 0.8, "inverted": inverted, "turn": 0}))
    return lua.table_from({"ring": lua.table_from({"x": 0, "y": 0, "r": 70, "roundness": 0.02}), "symbols": lua.table_from(syms),
                           "layers": lua.table(), "frames": lua.table(), "subs": lua.table(), "links": lua.table(), "glaives": 0})


def test_all_combinations(lua):
    """Every seal of 1-2 sigils and up to 4 signs compiles; opposite behaviors never stay together, every
    behavior left works on the spell's carrier; then every distinct spell is cast (stubbed world)"""
    import itertools
    started = time.perf_counter()
    # the five first elements with up to four of the basic signs; every element and special sigil with any one or two signs
    basic = ["fire", "water", "wind", "earth", "light"]
    everything = list(lua.eval("DICTIONARY_CENTER_ORDER").values())
    basic_signs = set(lua.eval("DICTIONARY_BASIC_SIGNS").values())
    plans = []
    for n in range(5):
        for signs in itertools.combinations_with_replacement([v for v in sign_variants(lua) if v[0] in basic_signs], n):
            for sigils in [[a] for a in basic] + [[a, a] for a in basic] + [list(p) for p in itertools.combinations(basic, 2)]:
                plans.append((sigils, signs))
    for n in (1, 2):
        for signs in itertools.combinations_with_replacement(sign_variants(lua), n):
            for key in everything:
                plans.append(([key], signs))
    compile_, serialize = lua.eval("compile_spell"), lua.eval("serialize_spell")
    effect, works = lua.eval("dictionary_effect"), lua.eval("dictionary_behavior_works")
    opposites = [(b["key"], b["opposite"]) for b in lua.eval("DICTIONARY_BEHAVIORS").values() if b["opposite"]]
    recipes, failed, spells = 0, [], {}
    for sigils, signs in plans:
        recipes += 1
        res = compile_(seal_tree(lua, sigils, signs))
        spell = res[0] if isinstance(res, tuple) else res
        if not spell:
            failed.append(f"{sigils} {signs}: {res[1] if isinstance(res, tuple) else '?'}")
            continue
        have = set(spell["behaviors"].keys())
        carrier = effect(spell["element"], spell["form"], spell["floats"])["carrier"]
        special = spell["manifest"] or spell["shape"]  # a way of manifesting of its own takes what the signs give
        if any(a in have and b in have for a, b in opposites) or not (special or all(works(k, carrier) for k in have)) or not spell["summary"]:
            failed.append(f"{sigils} {signs}: {sorted(have)} on {carrier}")
        key = (spell["element"], spell["form"], spell["manifest"], spell["shape"], tuple(sorted(have)))
        spells.setdefault(key, serialize(spell))
    compiled = time.perf_counter() - started
    # cast each distinct spell once
    cast_lua = load_cast(); G = cast_lua.globals(); errors = []
    for key, data in spells.items():
        if key[2] or key[3]:
            continue  # the seal's own ways of manifesting: tests/effects_smoke.py casts them in a world of their own
        G.shots = cast_lua.table()
        book = G.make_book(data)
        controls, holder = G.make_controls(1, 0, 100, 0)
        try:
            made = G.spellbook_use(book, holder, controls, 100)
            if not list(G.shots.values()) and not (made and list(made.values())):
                errors.append(f"{key}: nothing cast")
        except Exception as e:  # noqa: BLE001
            errors.append(f"{key}: {e}")
    print(f"  {recipes} seals compiled in {compiled:.0f} s: {len(failed)} wrong {failed[:3] or ''}; "
          f"{len(spells)} distinct spells cast: {len(errors)} errors {errors[:3] or ''}")
    return not failed and not errors


COMPLEX_PALETTES = [
    ["column", "column", "column", "pierce", "pierce", "crosshair", "stability", "strengthen", "entwine", "detection"],
    ["dispersion", "dispersion", "dispersion", "expansion", "expansion", "pull", "crush", "stability", "strengthen", "binding"],
    ["levitation", "levitation", "levitation", "orb", "orb", "collection", "stillness", "detection", "strengthen", "envelop"],
]


def complex_spell_cases(lua):
    """Build the composite seal trees exercised by the complex-spell test."""
    sigils = lua.eval("DICTIONARY_SIGILS")
    pure = [(element, key) for element, key in element_sigils(lua).items()
            if not (sigils[key]["manifest"] or sigils[key]["shape"] or sigils[key]["behavior"])]
    pure.sort()
    if len(pure) < 10:
        return pure, []
    cases = []
    for variant, palette in enumerate(COMPLEX_PALETTES):
        ordered = pure[variant:] + pure[:variant]
        make_part = lambda key: seal_tree(lua, [key], [(sign, False) for sign in palette])
        tree = make_part(ordered[0][1])
        tree["subs"] = lua.table_from([make_part(key) for _, key in ordered[1:]])
        cases.append((ordered, palette, tree))
    return pure, cases


def test_complex_spells(lua):
    """Cast composite spells with 10+ distinct elements and many signs on every component.

    One ring cannot hold that many element sigils. A main seal with smaller seals inside it can,
    so exercise compilation, serialization, reading the page, and casting all of its parts.
    """
    pure, cases = complex_spell_cases(lua)
    if len(pure) < 10:
        print(f"  only {len(pure)} independent element sigils; need at least 10")
        return False
    compile_, serialize = lua.eval("compile_spell"), lua.eval("serialize_spell")
    cast_lua = load_cast()
    G = cast_lua.globals()

    def cast_result(data):
        G.shots = cast_lua.table()
        book = G.make_book(data)
        controls, holder = G.make_controls(1, 0, 100, 0)
        made = G.spellbook_use(book, holder, controls, 100)
        if made is None:
            raise AssertionError("the book did not cast")
        return (sorted(shot["file"] for shot in G.shots.values()),
                sorted(effect if isinstance(effect, str) else "<entity>" for effect in made.values()))

    errors, signatures, forms = [], set(), set()
    for variant, (ordered, palette, tree) in enumerate(cases):
        result = compile_(tree)
        spell = result[0] if isinstance(result, tuple) else result
        if not spell:
            errors.append(f"variant {variant}: {result[1] if isinstance(result, tuple) else 'no spell'}")
            continue
        data = serialize(spell)
        restored = G.parse_spell_data(data)
        parts = [restored] + list(restored["subs"].values())
        elements = [part["element"] for part in parts]
        forms.add(restored["form"])
        signatures.add(data)
        if len(parts) != len(pure) or len(set(elements)) != len(pure) or set(elements) != {e for e, _ in pure}:
            errors.append(f"variant {variant}: lost elements in serialization: {elements}")
            continue
        actual_files, actual_effects = [], []
        try:
            component_data = [data.split("&", 1)[0]] + [serialize(part) for part in spell["subs"].values()]
            individual = [cast_result(part) for part in component_data]
            expected_files = sorted(file for files, _ in individual for file in files)
            expected_effects = sorted(effect for _, effects in individual for effect in effects)
            actual_files, actual_effects = cast_result(data)
            if not (actual_files or actual_effects) or actual_files != expected_files or actual_effects != expected_effects:
                errors.append(f"variant {variant}: cast {len(actual_effects)} effects and {len(actual_files)} projectiles; "
                              f"expected {len(expected_effects)} effects and {len(expected_files)} projectiles")
        except Exception as exc:  # noqa: BLE001
            errors.append(f"variant {variant}: {exc}")
        print(f"  variant {variant + 1}: {len(elements)} elements, {len(palette)} signs per seal, "
              f"{restored['form']}, {len(actual_effects)} effects")

    # Many different elements in one ring must fail cleanly even when a special sigil is present.
    crowded = seal_tree(lua, [key for _, key in pure], [])
    crowded["symbols"][len(pure) + 1] = lua.table_from({"kind": "sigil", "key": "sword", "size": 0.5, "score": 0.8})
    result = compile_(crowded)
    rejected = isinstance(result, tuple) and result[0] is None and result[1] == "Too many elements - the ring will not hold"
    print(f"  {len(pure)} elements in one ring: {'rejected' if rejected else 'accepted unexpectedly'}; "
          f"{len(signatures)} unique composite spells, {len(forms)} forms; errors {errors[:3]}")
    return rejected and len(signatures) == len(cases) and len(forms) == len(cases) and not errors


def test_balance(lua):
    """Balanced signs keep the spell straight and stable; signs on one side tilt it and make it unstable"""
    random.seed(9)
    _, even = run(lua, seal(lua, ["earth"], [("column", a, False) for a in CROSS]))
    _, lopsided = run(lua, seal(lua, ["earth"], [("column", a, False) for a in [150, 180, 210]]))
    _, big = run(lua, seal(lua, ["fire"], [("column", 0, False), ("column", 180, False)]))
    _, two = run(lua, seal(lua, ["fire", "fire"], [("column", 0, False), ("column", 180, False)]))
    print(f"  4 columns crosswise: tilt {even['tilt']}, stability {even['stability']}, '{even['summary']}'")
    print(f"  3 columns on the left: tilt {lopsided['tilt']}, stability {lopsided['stability']}, '{lopsided['summary']}', '{lopsided['quality']}'")
    print(f"  fire force: one sigil {big['force']}, two sigils {two['force']}")
    # piling up one sign gives less and less
    force = {n: lua.eval("compile_spell")(seal_tree(lua, ["fire"], [("column", False)] * n))["force"] for n in (2, 4, 8, 12)}
    print(f"  force of 2, 4, 8, 12 columns: {list(force.values())}")
    capped = force[4] > 1.8 * force[2] and force[8] < 1.4 * force[4] and force[12] - force[8] < 0.1
    # three columns pointing one way aim the seal on purpose (Flame Shot): it flies straight, but is unstable
    return capped and (even["tilt"] < 0.2 and even["stability"] > 0.9 and lopsided["tilt"] > 0.6 and lopsided["stability"] < 0.7
            and ("lopsided" in lopsided["summary"] or "directed" in lopsided["summary"]) and two["force"] > big["force"])


def test_wiki_seals(lua):
    """Complete seals from wha-spell-simulator's samples (drawn by hand there), scaled onto the page"""
    samples = json.load(open(os.path.join(MOD, "tests", "data", "wha_sample_spells.json"), encoding="utf-8"))
    expected = {"fire-column": "fire:column", "water-orb": "water:levitation"}
    ok = True
    for s in samples:
        strokes = [[(10 + p["x"] * 160, 10 + p["y"] * 160) for p in st] for st in s["strokes"]]
        as_drawn, _ = run(lua, strokes)
        # their rings are left with a gap (29 and 45 degrees): close it like a player would
        got, spell = run(lua, close_ring(strokes))
        print(f"  {s['displayName']:12s} as drawn: {as_drawn}; closed -> {got} {spell['summary'] + ', ' + spell['quality'] if spell else ''}")
        ok &= as_drawn == "The ring is not closed" and got == expected[s["id"]]
    return ok


def test_player_seals(lua):
    """Drawings from the game that once went wrong, kept with what they must give or reject (debug_sigil.py --keep)"""
    path = os.path.join(MOD, "tests", "data", "player_seals.json")
    ok = True
    for s in json.load(open(path, encoding="utf-8")) if os.path.exists(path) else []:
        strokes = [[tuple(map(float, p.split(","))) for p in st.split()] for st in s["strokes"]]
        if s.get("named") or s.get("grimoire"):  # the wiki's seal it must be named after (or none): only with the grimoire loaded
            lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
        got, spell = run(lua, strokes)
        named = spell and spell["named"]
        if s.get("named") or s.get("grimoire"):
            lua.execute("GRIMOIRE = nil; GRIMOIRE_BY_KEY = nil")
        have = set(spell["behaviors"].keys()) if spell else set()
        good = (spell is None if s["expected"] == "reject" else got == s["expected"] and set(s["behaviors"]) <= have
                and not (set(s.get("absent", [])) & have) and named == s.get("named"))
        print(f"  {s['name']:36s} -> {got}{' ' + named if named else ''} {sorted(have)}"
              f"{'' if good else '   <-- expected ' + s['expected'] + ' ' + str(s['behaviors']) + ' ' + str(s.get('named'))}")
        ok &= good
    return ok


def test_noise_rejection(lua):
    """A real sigil does not excuse substantial stray ink, and random marks must not make a spell."""
    random.seed(409)
    fire = place(hand(templates(lua)[("sigil", "fire")]), 90, 90, 32, tilt=0, noise=0.1)
    clean = [clean_ring()] + fire
    stray = [[(45 + i * 22, 5), (65 + i * 22, 5)] for i in range(4)]
    clean_result, _ = run(lua, clean)
    stray_result, stray_spell = run(lua, clean + stray)
    accepted, attempts = [], 40
    for seed in range(40):
        rng = random.Random(20000 + seed)
        marks = []
        for _ in range(30):
            angle, radius = rng.random() * 2 * math.pi, rng.uniform(5, 54)
            x, y = 90 + radius * math.cos(angle), 90 + radius * math.sin(angle)
            marks.append([(x, y), (x + rng.uniform(-9, 9), y + rng.uniform(-9, 9))])
        _, spell = run(lua, [clean_ring()] + marks)
        if spell: accepted.append(seed)
    for seed in range(20):
        attempts += 1
        rng = random.Random(50000 + seed)
        marks = []
        for _ in range(20):
            angle, radius = rng.random() * 2 * math.pi, rng.uniform(10, 52)
            x, y = 90 + radius * math.cos(angle), 90 + radius * math.sin(angle)
            points = [(x, y)]
            for _ in range(4):
                x, y = x + rng.uniform(-5, 5), y + rng.uniform(-5, 5)
                points.append((x, y))
            marks.append(points)
        _, spell = run(lua, [clean_ring()] + marks)
        if spell: accepted.append(f"zigzags {seed}")
    # A genuine sigil surrounded by many unrelated short marks must not be read as a clean spell.
    for seed in range(30):
        attempts += 1
        rng = random.Random(30000 + seed)
        marks = []
        for _ in range(25):
            angle, radius = rng.random() * 2 * math.pi, rng.uniform(23, 55)
            x, y = 90 + radius * math.cos(angle), 90 + radius * math.sin(angle)
            marks.append([(x, y), (x + rng.uniform(-6, 6), y + rng.uniform(-6, 6))])
        _, spell = run(lua, clean + marks)
        if spell: accepted.append(f"cluttered sigil {seed}")
    captured = json.load(open(os.path.join(MOD, "tests", "data", "player_seals.json"), encoding="utf-8"))
    for example in captured:
        if example["name"] not in ("random strokes inside accidental ring", "random words and lines inside ring",
                                   "single continuous scribble mistaken for light", "open central loop mistaken for flicker",
                                   "lightning with ambiguous peripheral remnants"):
            continue
        strokes = [[tuple(map(float, p.split(","))) for p in stroke.split()] for stroke in example["strokes"]]
        for seed in range(8):
            attempts += 1
            shuffled = list(strokes)
            random.Random(seed).shuffle(shuffled)
            _, spell = run(lua, shuffled)
            if spell: accepted.append(f"{example['name']} order {seed}")
        if example["name"] == "single continuous scribble mistaken for light":
            # Even a perfect ring cannot rescue the scribble. Check different sizes and pen directions.
            for scale in (0.6, 0.8, 1.0):
                for reverse in (False, True):
                    attempts += 1
                    mark = [(90 + (x - 82) * scale, 90 + (y - 93) * scale) for x, y in strokes[0]]
                    _, spell = run(lua, [clean_ring(), list(reversed(mark)) if reverse else mark])
                    if spell: accepted.append(f"continuous scribble scale {scale} reverse {reverse}")
        if example["name"] == "open central loop mistaken for flicker":
            # The game records tenths of a pixel; nearby unrounded inputs used to cross the score gate.
            for seed in range(30):
                attempts += 1
                rng = random.Random(seed)
                jittered = [[(x + rng.uniform(-0.049, 0.049), y + rng.uniform(-0.049, 0.049)) for x, y in st] for st in strokes]
                _, spell = run(lua, jittered)
                if spell: accepted.append(f"open flicker loop rounding {seed}")
            for scale in (0.5, 0.75, 1.25):
                for reverse in (False, True):
                    attempts += 1
                    scaled = [[(90 + (x - 120) * scale, 90 + (y - 124) * scale) for x, y in st] for st in strokes]
                    if reverse: scaled = [list(reversed(st)) for st in reversed(scaled)]
                    _, spell = run(lua, scaled)
                    if spell: accepted.append(f"open flicker loop scale {scale} reverse {reverse}")
    print(f"  clean sigil {clean_result}, with outside ink {stray_result}; "
          f"random marks accepted {len(accepted)}/{attempts} {accepted[:5]}")
    return clean_result == "fire:burst" and stray_spell is None and not accepted


def test_precision(lua):
    t = templates(lua)
    random.seed(4)
    fire = [densify([(90 + (x - 0.5) * 32, 90 + (y - 0.5) * 32) for x, y in st]) for st in t[("sigil", "fire")]]
    _, clean = run(lua, [clean_ring()] + fire)
    _, sloppy = run(lua, [wobbly_ring()] + fire)
    print(f"  clean seal: precision {clean['precision']}, '{clean['quality']}'")
    print(f"  wobbly ring: precision {sloppy['precision']}, '{sloppy['quality']}'")
    hand_drawn = sorted(sp["precision"] for _, sp in (run(lua, seal(lua, ["fire"])) for _ in range(30)) if sp)
    print(f"  hand-drawn fire seal: precision median {hand_drawn[len(hand_drawn) // 2]}")
    compile_ = lua.eval("compile_spell")
    weak_sigil = seal_tree(lua, ["fire"], [("column", False), ("column", False)])
    weak_sigil["symbols"][1]["score"] = 0.4
    rejected = compile_(weak_sigil)
    sigil_rejected = isinstance(rejected, tuple) and rejected[0] is None
    weak_signs = seal_tree(lua, ["fire"], [("crosshair", False), ("crosshair", False)])
    weak_signs["symbols"][2]["score"] = weak_signs["symbols"][3]["score"] = 0.45
    accepted = compile_(weak_signs)
    signs_accepted = accepted is not None and not (isinstance(accepted, tuple) and accepted[0] is None)
    weak_pair = seal_tree(lua, ["fire", "water"], [("column", False), ("column", False)])
    weak_pair["symbols"][1]["score"] = weak_pair["symbols"][2]["score"] = 0.4
    rejected_pair = compile_(weak_pair)
    pair_rejected = isinstance(rejected_pair, tuple) and rejected_pair[0] is None
    uneven_pair = seal_tree(lua, ["fire", "water"], [("column", False), ("column", False)])
    uneven_pair["symbols"][1]["score"] = 0.5
    accepted_pair = compile_(uneven_pair)
    pair_accepted = accepted_pair is not None and not (isinstance(accepted_pair, tuple) and accepted_pair[0] is None)
    crowded = seal_tree(lua, ["fire"], [("crosshair", False)] * 12)
    for symbol in crowded["symbols"].values():
        if symbol["kind"] == "sign": symbol["score"] = 0.5
    rejected_crowded = compile_(crowded)
    crowded_rejected = isinstance(rejected_crowded, tuple) and rejected_crowded[0] is None
    for symbol in crowded["symbols"].values(): symbol["score"] = 0.8
    accepted_crowded = compile_(crowded)
    crowded_accepted = accepted_crowded is not None and not (isinstance(accepted_crowded, tuple) and accepted_crowded[0] is None)
    print(f"  weak sigil with strong modifiers rejected {sigil_rejected}; clear sigil with rough modifiers accepted {signs_accepted}")
    print(f"  weak element pair rejected {pair_rejected}; uneven but clear pair accepted {pair_accepted}")
    print(f"  many weak modifiers rejected {crowded_rejected}; many clear modifiers accepted {crowded_accepted}")
    return (clean["precision"] >= lua.eval("SEAL_FLAWLESS") and sloppy["precision"] < clean["precision"] - 0.25
            and sigil_rejected and signs_accepted and pair_rejected and pair_accepted and crowded_rejected and crowded_accepted)


# the open book on the test screen (853.5 x 360): two pages of 180 with a spine of 8
LEFT_X, PAGE_Y = math.floor((853.5 - 2 * 180 - 8) / 2), (360 - 180) // 2
RIGHT_X = LEFT_X + 180 + 8


def seal_count(G):
    pages = int(G.globals["witch_notebook.seals"] or 0)
    return sum(G.globals[f"witch_notebook.seal_{i}_draft"] != "1" for i in range(1, pages + 1))


def toggle_book(G):
    G.key_b = True; G.notebook_update(); G.key_b = False


def open_book(G, to_blank=True):
    """Open with B and turn to the blank page with D (opened the first time, the book turns there by itself), then wait
    for the pages to finish turning"""
    toggle_book(G)
    for _ in range(10 if to_blank else 0):
        G.pressed[7] = True; G.notebook_update(); G.pressed[7] = False
    for _ in range(150): G.notebook_update()


def draw(G, strokes):
    """Draw on the blank page: page 3 (left) with no seals, the next ones in turn"""
    page_x = LEFT_X if seal_count(G) % 2 == 0 else RIGHT_X
    for stroke in strokes:
        G.left_down = True
        for x, y in stroke:
            G.mouse[1], G.mouse[2] = page_x + x, PAGE_Y + y
            G.notebook_update()
        G.left_down = False; G.notebook_update()
        for _ in range(20): G.notebook_update()  # short pause between strokes must not finish the seal


def draw_on_blank(G, strokes, pause=20):
    """Draw strokes made for a 180 page on the open book's blank page (any book: notebook_view), scaled to its page"""
    view, side = G.notebook_view()
    pos = view[side]
    k = view.size / 180
    for stroke in strokes:
        G.left_down = True
        for x, y in stroke:
            G.mouse[1], G.mouse[2] = pos.x + x * k, pos.y + y * k
            G.notebook_update()
        G.left_down = False; G.notebook_update()
        for _ in range(pause): G.notebook_update()


# the witch carries all three books: entities 11 (the Spellbook), 12 (the Palm Quire), 13 (the Great Tome)
CARRY_ALL = r'''
books_carried = { 11, 12, 13 }
book_keys[11], book_keys[12], book_keys[13] = "book", "quire", "tome"
local tag_get = EntityGetWithTag
function EntityGetWithTag( t ) if t == "witch_spellbook" then return books_carried end return tag_get( t ) end
held_item = 0
local get = ComponentGetValue2
function ComponentGetValue2( c, f ) if f == "mActiveItem" then return held_item end return get( c, f ) end
function EntityHasTag( e, t ) return t == "witch_spellbook" and book_keys[e] ~= nil end
'''


def click(G, x, y):
    """Returns whether the controls were enabled while the button was held"""
    G.mouse[1], G.mouse[2] = x, y
    G.left_down = G.left_just_down = True; G.notebook_update(); G.left_just_down = False
    held = G.controls_enabled
    G.notebook_update(); G.left_down = False; G.notebook_update()
    return held


def press_button(G, button):
    r = G.notebook_button_rects[button]
    if r is not None:  # a panel button counts only a press begun on it, as a player clicks
        G.mouse[1], G.mouse[2] = r[1] + r[3] / 2, r[2] + r[4] / 2
        G.left_down = G.left_just_down = True; G.notebook_update(); G.left_just_down = G.left_down = False
    G.buttons[button] = True; G.notebook_update(); G.buttons[button] = False


def circle():
    return ring()[0]


def column_seal(lua, sigil):
    """A ring with the sigil and two columns: its gap is closed by the last stroke"""
    arc, closing, (cx, cy, r) = prepared_ring()
    t = templates(lua)
    symbols = place(hand(t[("sigil", sigil)]), cx, cy, r * 0.45)
    for deg in (0, 180):
        a = math.radians(deg)
        symbols += place(hand(t[("sign", "column")]), cx + 0.7 * r * math.cos(a), cy + 0.7 * r * math.sin(a), r * 0.23, a - math.pi / 2)
    return [arc] + symbols + [closing]


def test_notebook_flow(lua):
    """Draw a ring with a gap, a fire sigil and two columns inside on the book's blank page: nothing happens
    until the gap is closed, then the seal stays on its page and becomes the book's active spell."""
    G = lua.globals()
    open_book(G)
    random.seed(3)
    strokes = column_seal(lua, "fire")
    draw(G, strokes[:-1])
    for _ in range(120): G.notebook_update()  # no timer: an open seal waits
    before = seal_count(G)
    draw(G, strokes[-1:])
    data = G.globals["witch_notebook.seal_1_spell"] or ""
    name = G.globals["witch_notebook.seal_1_name"] or ""
    kept = (G.globals["witch_notebook.seal_1_strokes"] or "").count("|") + 1
    # the book only draws inside the page's margin
    inside = lambda p: 6 <= p[0] <= 174 and 6 <= p[1] <= 174
    drawn = sum(math.dist(a, b) for st in strokes for a, b in zip(st, st[1:]) if inside(a) and inside(b))
    spent = 1000 - G.flask.witch_ink; expected = drawn * G.INK_PER_UNIT
    print(f"  seals before closing the ring: {before}, after: {seal_count(G)} '{name}' with {kept} strokes, active {G.globals['witch_notebook.active']}")
    print(f"  stored spell '{data[:60]}...', the book is named '{G.component_values['item_name']}'")
    print(f"  ink spent {spent} (line length x cost = {expected:.0f})")
    # the book skips sub-pixel moves, the jittery test lines are a little longer
    return (abs(spent - expected) <= 0.06 * expected and before == 0 and seal_count(G) == 1 and data.startswith("element=fire;form=column;")
            and G.globals["witch_notebook.active_spell"] == data and G.globals["witch_notebook.active"] == "1"
            and name.startswith("Fire") and G.component_values["item_name"] == "Spellbook: " + name
            and kept == len(strokes) and G.globals["witch_notebook.page"] == "" and not list(G.loaded.values())
            and G.controls_enabled is False)


def test_layer_ring(lua):
    """A seal with a layer: the ring is drawn with its gap, then a closed ring inside it, the sigil and the signs - the
    inner ring must not awaken the seal; closing the outer ring does, and the inner one is its layer."""
    G = lua.globals()
    open_book(G)
    random.seed(21)
    arc, closing, (cx, cy, r) = prepared_ring()
    inner = [(cx + 0.8 * r * math.cos(t / 100 * 2 * math.pi) + random.gauss(0, 0.4), cy + 0.8 * r * math.sin(t / 100 * 2 * math.pi) + random.gauss(0, 0.4))
             for t in range(103)]
    t = templates(lua)
    symbols = place(hand(t[("sigil", "water")]), cx, cy, r * 0.4)
    for deg in (0, 180):
        a = math.radians(deg)
        symbols += place(hand(t[("sign", "column")]), cx + 0.6 * r * math.cos(a), cy + 0.6 * r * math.sin(a), r * 0.2, a - math.pi / 2)
    before = seal_count(G)
    draw(G, [arc, inner] + symbols)
    early = seal_count(G) - before
    draw(G, [closing])
    data = G.globals[f"witch_notebook.seal_{before + 1}_spell"] or ""
    print(f"  seals after the inner ring and the symbols: {early}, after closing the outer ring: {seal_count(G) - before}, '{data[:50]}'")
    return early == 0 and seal_count(G) - before == 1 and "layers=1" in data and data.startswith("element=water")


def test_book_pages():
    """A run starts with one spellbook. Seals stay on their pages: the next seal goes on the next page and
    becomes active, a click on a page picks it, "tear out" asks once more and removes the page, and the
    book is the same after the game is reloaded."""
    lua = load_mod(); G = lua.globals()
    G.settings["witch_notebook.books_at_spawn"] = False
    G.notebook_on_player_spawned(1); G.notebook_on_player_spawned(1)
    given = [f.split("/")[-1] for f in G.loaded.values()]
    T = load_mod().globals()  # the settings for testing: the Palm Quire, the Great Tome and the Test Book lie beside the witch, once
    T.settings["witch_notebook.books_at_spawn"] = True
    T.settings["witch_notebook.test_book_at_spawn"] = True
    T.notebook_on_player_spawned(1); T.notebook_on_player_spawned(1)
    testing = sorted(f.split("/")[-1] for f in T.loaded.values())
    O = load_mod().globals()  # the Test Book's own setting alone
    O.settings["witch_notebook.test_book_at_spawn"] = True
    O.notebook_on_player_spawned(1)
    test_only = sorted(f.split("/")[-1] for f in O.loaded.values())
    F = load_mod().globals()  # a fresh install: the game never stores the default false, the setting reads nil
    F.notebook_on_player_spawned(1)
    fresh = [f.split("/")[-1] for f in F.loaded.values()]
    random.seed(3)
    open_book(G)
    draw(G, column_seal(lua, "fire"))   # page 3, on the left
    draw(G, column_seal(lua, "water"))  # page 4, on the right of the same spread
    spells = [G.globals[f"witch_notebook.seal_{i}_spell"] or "" for i in (1, 2)]
    drawn_active = G.globals["witch_notebook.active"]
    click(G, LEFT_X + 90, PAGE_Y + 90)
    picked = G.globals["witch_notebook.active"] == "1" and G.globals["witch_notebook.active_spell"] == spells[0]
    picked_name = G.component_values["item_name"]
    press_button(G, 900005)  # "tear out" under the left page
    asked = seal_count(G)
    press_button(G, 900005)
    torn = (seal_count(G) == 1 and G.globals["witch_notebook.seal_1_spell"] == spells[1] and G.globals["witch_notebook.seal_2_spell"] == ""
            and G.globals["witch_notebook.active"] == "0" and G.globals["witch_notebook.active_spell"] == "")
    toggle_book(G)
    # the game is saved and loaded: a fresh Lua state with the same globals
    R = load_mod().globals()
    for k, v in G.globals.items(): R.globals[k] = v
    open_book(R, to_blank=False)  # the book opens where it was left: the water seal and the blank page
    click(R, LEFT_X + 90, PAGE_Y + 90)
    reloaded = R.globals["witch_notebook.active_spell"] == spells[1] and seal_count(R) == 1
    print(f"  books given: {given}, setting unset: {fresh}, with the settings for testing: {testing}, the Test Book's alone: {test_only}; seals {[sp[:24] for sp in spells]}, active after drawing {drawn_active}, "
          f"after a click on page 3: '{picked_name}'")
    print(f"  tear out: {asked} seals after the first click, torn out {torn}; after reload a click picks the water seal: {reloaded}")
    return (given == ["spellbook.xml"] and fresh == ["spellbook.xml"] and testing == ["great_tome.xml", "palm_quire.xml", "spellbook.xml", "test_book.xml"]
            and test_only == ["spellbook.xml", "test_book.xml"]
            and spells[0].startswith("element=fire") and spells[1].startswith("element=water")
            and drawn_active == "2" and picked and picked_name.startswith("Spellbook: Fire") and asked == 2 and torn and reloaded)


def test_wiki_pages():
    """The book's other part, the wiki's grimoire: the button over the book opens it, a click on a page makes that seal
    the active one (its spell and its drawing go to the run's globals, the book is named after it), a section's tab
    turns to its first page, and the button brings the drawn seals back."""
    lua = load_mod()
    lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
    G = lua.globals()
    G.settings["witch_notebook.full_grimoire"] = True  # the setting for testing: all the wiki's seals, cast from the book
    G.notebook_on_player_spawned(1)
    open_book(G, to_blank=False)
    press_button(G, 900007)  # [Grimoire]
    for _ in range(30): G.notebook_update()
    click(G, LEFT_X + 90, PAGE_Y + 90)
    first = G.GRIMOIRE[1]
    picked = G.globals["witch_notebook.active_wiki"] == first["key"]
    spell = G.globals["witch_notebook.active_spell"] or ""
    drawing = G.globals["witch_notebook.active_strokes"] or ""
    named = G.component_values["item_name"] == "Spellbook: " + first["name"]
    # the second section's tab
    sections = []
    for entry in G.GRIMOIRE.values():
        if entry["category"] not in [c for c, _ in sections]:
            sections.append((entry["category"], len(sections) and 0))
    press_button(G, 900010 + 2)
    for _ in range(90): G.notebook_update()  # several sheets turn, one after another
    click(G, LEFT_X + 90, PAGE_Y + 90)
    click(G, RIGHT_X + 90, PAGE_Y + 90)
    second = G.GRIMOIRE_BY_KEY[G.globals["witch_notebook.active_wiki"] or ""]
    jumped = second is not None and second["category"] == sections[1][0]
    press_button(G, 900007)  # back to the drawn seals
    for _ in range(30): G.notebook_update()
    print(f"  grimoire page 1 active: {picked}, spell '{spell[:40]}...', drawing kept {len(drawing) > 100}, book named {named}; "
          f"the tab of '{sections[1][0]}' -> '{second['name'] if second else None}'")
    return picked and spell.startswith("element=") and "named=" + first["key"] in spell and len(drawing) > 100 and named and jumped


def test_unfinished_page():
    """An unfinished drawing stays on the page after closing the book, and after the game is reloaded
    (the run's globals); closing the ring later still awakens the seal. A finished seal leaves the page."""
    lua = load_mod(); G = lua.globals()
    random.seed(3)
    strokes = column_seal(lua, "fire")
    open_book(G)
    draw(G, strokes[:-1])
    toggle_book(G)  # close
    saved = G.globals["witch_notebook.seal_1_strokes"] or ""
    blank_added = G.globals["witch_notebook.seal_1_draft"] == "1" and G.globals["witch_notebook.page"] == ""
    toggle_book(G); toggle_book(G)  # open again and close
    kept = (G.globals["witch_notebook.seal_1_strokes"] or "").count("|") + 1 if G.globals["witch_notebook.seal_1_strokes"] else 0
    # the game is saved and loaded: a fresh Lua state with the same globals
    R = load_mod().globals()
    for k, v in G.globals.items(): R.globals[k] = v
    open_book(R, to_blank=False)
    draw(R, strokes[-1:])
    toggle_book(R)
    after = R.globals["witch_notebook.page"]
    legacy = load_mod().globals()
    legacy.globals["witch_notebook.page"] = saved
    legacy.globals["witch_notebook.seals"] = "0"
    legacy.globals["witch_notebook.spread"] = "2"
    open_book(legacy, to_blank=False)
    migrated = (legacy.globals["witch_notebook.seal_1_draft"] == "1"
                and legacy.globals["witch_notebook.seal_1_strokes"] == saved
                and legacy.globals["witch_notebook.page"] == "")
    print(f"  draft on its own page {blank_added}, strokes saved on closing: {saved.count('|') + 1 if saved else 0} "
          f"of {len(strokes) - 1}, after reopening: {kept}; after reload + closing the ring: {seal_count(R)} seal")
    return blank_added and migrated and saved.count("|") + 1 == len(strokes) - 1 and kept == len(strokes) - 1 and seal_count(R) == 1 and after == ""


def test_failed_page_editing():
    """A failed seal retries on each completed stroke, survives reload, and stays idle between strokes. The eraser
    removes only the touched part of a line without spending ink."""
    lua = load_mod(); G = lua.globals()
    random.seed(8)
    strokes = column_seal(lua, "fire")
    sigil_count = len(templates(lua)[("sigil", "fire")])
    missing = strokes[1:1 + sigil_count]
    bad = strokes[:1] + strokes[1 + sigil_count:]
    open_book(G)
    draw(G, bad)
    attempts = int(G.globals["witch_notebook.debug_next"] or 0)
    G.left_down = True  # first correction starts before the failure message fades
    for x, y in missing[0]:
        G.mouse[1], G.mouse[2] = LEFT_X + x, PAGE_Y + y
        G.notebook_update()
    no_midstroke_retry = int(G.globals["witch_notebook.debug_next"] or 0) == attempts
    G.left_down = False; G.notebook_update()
    auto_retry = int(G.globals["witch_notebook.debug_next"] or 0) == attempts + 1 and seal_count(G) == 0
    for _ in range(150): G.notebook_update()
    no_idle_retry = int(G.globals["witch_notebook.debug_next"] or 0) == attempts + 1
    toggle_book(G)
    saved = G.globals["witch_notebook.seal_1_strokes"] or ""
    first_correction_saved = saved.count("|") + 1 == len(bad) + 1
    failed_saved = G.globals["witch_notebook.seal_1_draft"] == "1"
    R = load_mod().globals()
    for k, v in G.globals.items(): R.globals[k] = v
    R.flask.witch_ink = G.flask.witch_ink
    open_book(R, to_blank=False)
    draw(R, missing[1:2])
    retry_after_reload = int(R.globals["witch_notebook.debug_next"] or 0) == attempts + 2 and seal_count(R) == 0
    draw(R, missing[2:])
    fixed = seal_count(R) == 1 and (R.globals["witch_notebook.active_spell"] or "").startswith("element=fire;form=column;")

    E = load_mod().globals()
    open_book(E)
    draw(E, [[(30, 90), (150, 90)]])
    ink_before = E.flask.witch_ink
    E.mouse[1], E.mouse[2] = LEFT_X + 90, PAGE_Y + 90
    E.right_down = True; E.notebook_update(); E.right_down = False; E.notebook_update()
    toggle_book(E)
    pieces = (E.globals["witch_notebook.seal_1_strokes"] or "").count("|") + 1
    toggle_book(E)
    press_button(E, 900009)  # select the eraser
    click(E, LEFT_X + 50, PAGE_Y + 90)
    toggle_book(E)
    more_pieces = (E.globals["witch_notebook.seal_1_strokes"] or "").count("|") + 1
    no_ink = E.flask.witch_ink == ink_before
    toggle_book(E)  # a line begun on the page and let go over Clear leaves the page alone
    r = E.notebook_button_rects[900099]
    E.mouse[1], E.mouse[2] = LEFT_X + 100, PAGE_Y + 120
    E.left_down = E.left_just_down = True; E.notebook_update(); E.left_just_down = False
    E.mouse[1], E.mouse[2] = r[1] + r[3] / 2, r[2] + r[4] / 2; E.notebook_update()
    E.left_down = False; E.buttons[900099] = True; E.notebook_update(); E.buttons[900099] = False
    toggle_book(E)
    kept = (E.globals["witch_notebook.seal_1_strokes"] or "") != ""
    toggle_book(E)
    press_button(E, 900099)  # clear page explicitly
    toggle_book(E)
    empty = E.globals["witch_notebook.seal_1_strokes"] == "" and E.globals["witch_notebook.seals"] == "2"
    print(f"  failed seal retries after release {no_midstroke_retry and auto_retry}, idle without retry {no_idle_retry}, "
          f"correction saved {first_correction_saved and failed_saved}, retries and completes after reload {retry_after_reload and fixed}; "
          f"eraser pieces {pieces} -> {more_pieces}, "
          f"ink unchanged {no_ink}, release over Clear keeps the page {kept}, clear page {empty}")
    return (no_midstroke_retry and auto_retry and no_idle_retry and first_correction_saved and failed_saved
            and retry_after_reload and fixed and pieces == 2 and more_pieces == 3 and no_ink and kept and empty)


def test_retry_requires_closed_ring():
    """Opening a failed ring suspends retries; closing it after correction awakens the seal."""
    lua = load_mod(); G = lua.globals()
    random.seed(8)
    strokes = column_seal(lua, "fire")
    count = len(templates(lua)[("sigil", "fire")])
    open_book(G)
    draw(G, strokes[:1] + strokes[1 + count:])
    attempts = int(G.globals["witch_notebook.debug_next"] or 0)
    G.witch_notebook_erase_at(*strokes[0][77], *strokes[0][65])
    G.witch_notebook_finish_erase()
    draw(G, strokes[1:1 + count])
    suspended = int(G.globals["witch_notebook.debug_next"] or 0) == attempts and seal_count(G) == 0
    draw(G, [strokes[0][60:84]])
    closed = int(G.globals["witch_notebook.debug_next"] or 0) == attempts + 1 and seal_count(G) == 1
    print(f"  retries suspended while ring is open {suspended}, corrected seal awakens on closing {closed}")
    return suspended and closed


def test_multiple_drafts():
    """Two unfinished seals occupy separate pages; either survives reload and can be edited independently."""
    lua = load_mod(); G = lua.globals()
    random.seed(8)
    strokes = column_seal(lua, "fire")
    sigil_count = len(templates(lua)[("sigil", "fire")])
    missing = strokes[1:1 + sigil_count]
    bad = strokes[:1] + strokes[1 + sigil_count:]
    open_book(G)
    draw(G, bad)
    first = G.globals["witch_notebook.seal_1_strokes"] or ""
    first_draft = G.globals["witch_notebook.seal_1_draft"] == "1" and first.count("|") + 1 == len(bad)
    press_button(G, 900004)  # the next pair is already ready
    for _ in range(150): G.notebook_update()
    draw_on_blank(G, [[(30, 55), (85, 60), (145, 55)]])
    second = G.globals["witch_notebook.seal_3_strokes"] or ""
    separate = G.globals["witch_notebook.seal_3_draft"] == "1" and bool(second)
    toggle_book(G)

    R = load_mod().globals()
    for k, v in G.globals.items(): R.globals[k] = v
    R.flask.witch_ink = G.flask.witch_ink
    open_book(R, to_blank=False)
    press_button(R, 900003)
    for _ in range(150): R.notebook_update()
    draw(R, missing)  # left page: finish the first draft
    completed_first = (R.globals["witch_notebook.active"] == "1"
                       and R.globals["witch_notebook.seal_1_draft"] == "")
    second_untouched = R.globals["witch_notebook.seal_3_strokes"] == second

    # Draw on the other draft on the next spread, then save and check both pages.
    press_button(R, 900004)
    for _ in range(150): R.notebook_update()
    R.left_down = True
    for x, y in [(35, 90), (55, 92), (75, 90)]:
        R.mouse[1], R.mouse[2] = LEFT_X + x, PAGE_Y + y
        R.notebook_update()
    R.left_down = False; R.notebook_update()
    toggle_book(R)
    second_edited = (R.globals["witch_notebook.seal_3_draft"] == "1"
                     and (R.globals["witch_notebook.seal_3_strokes"] or "").count("|") == second.count("|") + 1)
    print(f"  two drafts {first_draft and separate}, first completed after reload {completed_first}, "
          f"second unchanged until edited {second_untouched}, second edited {second_edited}")
    return first_draft and separate and completed_first and second_untouched and second_edited


def test_blank_page_pairs():
    """Both faces are editable before drawing; either face exposes another prepared pair on the next spread."""
    lua = load_mod(); G = lua.globals()
    open_book(G)
    initial = int(G.globals["witch_notebook.seals"] or 0) == 0
    lua.execute('''page_images, page_digits = {}, {}
        function GuiImage(g, id, x, y, file, alpha, sx, sy)
            if file:find("page_spine_", 1, true) and file:sub(-8) == "page.png" then
                page_images[#page_images + 1] = { file = file, x = x }
            end
            if file:find("digit_", 1, true) then page_digits[#page_digits + 1] = { file = file, x = x } end
        end''')
    G.notebook_update()
    frames_before = sorted((d["file"], d["x"]) for d in G.page_images.values())
    digits_before = sorted((d["file"], d["x"]) for d in G.page_digits.values())
    G.left_down = True
    for x, y in [(35, 65), (55, 67), (75, 65)]:
        G.mouse[1], G.mouse[2] = RIGHT_X + x, PAGE_Y + y
        G.notebook_update()
    G.left_down = False; G.notebook_update()
    lua.execute("page_images, page_digits = {}, {}")
    G.notebook_update()
    frames_after = sorted((d["file"], d["x"]) for d in G.page_images.values())
    digits_after = sorted((d["file"], d["x"]) for d in G.page_digits.values())
    frames_stable = (len(frames_before) == 2 and frames_before == frames_after
                     and len(digits_before) >= 2 and digits_before == digits_after)
    right_edited = (G.globals["witch_notebook.seals"] == "2"
                    and G.globals["witch_notebook.seal_1_draft"] == "1"
                    and G.globals["witch_notebook.seal_1_strokes"] == ""
                    and G.globals["witch_notebook.seal_2_draft"] == "1"
                    and bool(G.globals["witch_notebook.seal_2_strokes"]))
    press_button(G, 900004)
    for _ in range(150): G.notebook_update()
    view, side = G.notebook_view()
    next_pair = side == "back" and view is not None
    draw_on_blank(G, [[(35, 65), (75, 65)]])
    another_pair = G.globals["witch_notebook.seals"] == "4" and G.globals["witch_notebook.seal_3_draft"] == "1"
    print(f"  initial blank pair {initial}, page frames stable {frames_stable}, right page edited {right_edited}, next pair available {next_pair}, "
          f"another pair generated {another_pair}")
    return initial and frames_stable and right_edited and next_pair and another_pair


def test_ink():
    """Running out of ink cuts the line; an empty flask draws nothing; Esc (pause) closes the book."""
    lua = load_mod(); G = lua.globals()
    G.flask.witch_ink = 40
    open_book(G)
    random.seed(5)
    draw(G, [circle(), poly([(90, 72), (104, 98), (76, 98), (90, 72)], 30)])
    for _ in range(60): G.notebook_update()
    dry = G.flask.witch_ink
    print(f"  40 cells of ink: {seal_count(G)} seals, ink left {dry}")
    ok = dry == 0 and seal_count(G) == 0
    for _ in range(60): G.notebook_update()  # the failure message fades
    draw(G, [circle()])
    for _ in range(60): G.notebook_update()
    print(f"  empty flask: {seal_count(G)} seals")
    ok &= seal_count(G) == 0 and G.flask.witch_ink == 0
    G.notebook_on_pause()
    print(f"  pause closes the book: controls enabled {G.controls_enabled}")
    ok &= G.controls_enabled is True
    G.flask.witch_ink = 1000; G.notebook_update(); G.left_down = True; G.notebook_update(); G.left_down = False
    ok &= G.flask.witch_ink == 1000  # the book stays closed
    return ok


def test_book_in_inventory():
    """B opens the book only while it is in the inventory; dropped, it closes."""
    lua = load_mod(); G = lua.globals()
    G.book_owner = 0
    toggle_book(G); G.notebook_update()
    dropped = G.controls_enabled is not False
    G.book_owner = 1
    toggle_book(G); G.notebook_update()
    carried = G.controls_enabled is False
    G.book_owner = 0
    G.notebook_update()
    closed = G.controls_enabled is True
    print(f"  B with the book on the ground stays shut: {dropped}; in the inventory opens: {carried}; dropped while open closes: {closed}")
    return dropped and carried and closed


def test_open_book_controls():
    """The configured key toggles the book; an empty book opens on click without drawing."""
    lua = load_mod(); G = lua.globals()
    G.settings["witch_notebook.open_key"] = 20  # Q
    G.key_b = True; G.notebook_update(); G.key_b = False
    old_key_ignored = G.controls_enabled is not False
    G.pressed[20] = True; G.notebook_update(); G.pressed[20] = False
    custom_key_opens = G.controls_enabled is False
    G.pressed[20] = True; G.notebook_update(); G.pressed[20] = False
    custom_key_closes = G.controls_enabled is True

    G.globals["witch_notebook.open_request"] = "book"
    G.left_down = True; G.left_just_down = True
    G.notebook_update()
    clicked_open = G.controls_enabled is False
    no_drawing = (G.globals["witch_notebook.page"] or "") == "" and G.flask.witch_ink == 1000
    consumed = G.globals["witch_notebook.open_request"] == ""
    G.left_just_down = False; G.left_down = False; G.notebook_update()
    print(f"  custom key: B ignored {old_key_ignored}, Q opens {custom_key_opens}, Q closes {custom_key_closes}; "
          f"empty book click opens {clicked_open}, no drawing {no_drawing}, request consumed {consumed}")
    return old_key_ignored and custom_key_opens and custom_key_closes and clicked_open and no_drawing and consumed


def test_right_click_open():
    """RMB opens only the held book; the opening press cannot erase an existing draft."""
    lua = load_mod(); lua.execute(CARRY_ALL); G = lua.globals()
    for held in (0, 99):  # books carried, but an empty hand or another item selected
        G.held_item = held
        G.right_down = G.right_just_down = True; G.notebook_update()
        G.right_down = G.right_just_down = False; G.notebook_update()
        if G.notebook_view() is not None: return False
    G.held_item = 11
    lua.execute("function GameIsInventoryOpen() return true end")
    G.right_down = G.right_just_down = True; G.notebook_update()
    inventory_ignored = G.notebook_view() is None
    lua.execute("function GameIsInventoryOpen() return false end")
    G.right_down = G.right_just_down = False; G.notebook_update()
    G.book_owner = 99
    G.right_down = G.right_just_down = True; G.notebook_update()
    dropped_ignored = G.notebook_view() is None
    G.book_owner = 1
    G.right_down = G.right_just_down = False; G.notebook_update()
    all_books = True
    for item, key in ((11, "book"), (12, "quire"), (13, "tome")):
        G.held_item = item
        G.right_down = G.right_just_down = True; G.notebook_update()
        G.right_just_down = False
        for _ in range(5): G.notebook_update()
        view, _ = G.notebook_view()
        all_books &= view["def"].key == key and G.controls_enabled is False
        G.right_down = False; G.notebook_update()
        toggle_book(G)

    G.held_item = 11
    open_book(G)
    draw(G, [[(30, 90), (150, 90)]])
    G.mouse[1], G.mouse[2] = LEFT_X + 90, PAGE_Y + 90
    toggle_book(G)
    saved = G.globals["witch_notebook.seal_1_strokes"]
    G.right_down = G.right_just_down = True; G.notebook_update()
    G.right_just_down = False
    for _ in range(5): G.notebook_update()
    toggle_book(G)  # closing while RMB is held must keep controls frozen until release
    preserved = G.globals["witch_notebook.seal_1_strokes"] == saved
    frozen = G.controls_enabled is False
    G.right_down = False; G.notebook_update()
    released = G.controls_enabled is True
    toggle_book(G)
    G.right_down = G.right_just_down = True; G.notebook_update()
    G.right_down = G.right_just_down = False; G.notebook_update()
    still_open = G.notebook_view() is not None
    toggle_book(G)
    erased = G.globals["witch_notebook.seal_1_strokes"] != saved
    print(f"  RMB opens each held book {all_books}, ignores inventory {inventory_ignored} and dropped books {dropped_ignored}; "
          f"opening preserves draft {preserved}, waits for release {frozen and released}, subsequent RMB erases {still_open and erased}")
    return all_books and inventory_ignored and dropped_ignored and preserved and frozen and released and still_open and erased


def test_open_rmb_and_ad_binds():
    """RMB can be switched off; A or D assigned as the open key closes the book without turning a page."""
    lua = load_mod(); lua.execute(CARRY_ALL); G = lua.globals()
    G.held_item = 11
    G.settings["witch_notebook.open_rmb"] = False
    G.right_down = G.right_just_down = True; G.notebook_update()
    G.right_down = G.right_just_down = False; G.notebook_update()
    rmb_off = G.notebook_view() is None
    G.settings["witch_notebook.open_rmb"] = True
    G.right_down = G.right_just_down = True; G.notebook_update()
    G.right_down = G.right_just_down = False; G.notebook_update()
    rmb_on = G.notebook_view() is not None
    toggle_book(G)
    open_book(G, to_blank=False)
    G.settings["witch_notebook.open_key"] = 7  # D
    G.pressed[7] = True; G.notebook_update(); G.pressed[7] = False
    d_closes = G.notebook_view() is None
    print(f"  RMB off ignores the click {rmb_off}, on opens {rmb_on}; D as open key closes {d_closes}")
    return rmb_off and rmb_on and d_closes


def test_open_key_setting():
    """The mod settings button captures a key, supports cancellation and resets to B."""
    lua = bare_runtime()
    lua.execute(STUBS)
    lua.execute(r'''
        next_settings, right_buttons = {}, {}
        function ModSettingGetNextValue(k) return next_settings[k] end
        function ModSettingSetNextValue(k, v) next_settings[k] = v; settings[k] = v end
        function GuiTooltip() end
        function GuiButton(g, id) return buttons[id] == true, right_buttons[id] == true end
    ''')
    lua.execute(open(os.path.join(MOD, "settings.lua"), encoding="utf-8").read())
    G = lua.globals()
    setting = next(s for s in G.mod_settings.values() if s.id == "open_key")
    draw = lambda: setting.ui_fn("witch_notebook", lua.table(), False, 1, setting)
    G.buttons[1] = True; draw(); G.buttons[1] = False
    G.pressed[20] = True; draw(); G.pressed[20] = False
    assigned = G.next_settings["witch_notebook.open_key"] == 20
    G.buttons[1] = True; draw(); G.buttons[1] = False
    G.pressed[41] = True; draw(); G.pressed[41] = False
    cancelled = G.next_settings["witch_notebook.open_key"] == 20
    G.right_buttons[1] = True; draw(); G.right_buttons[1] = False
    reset = G.next_settings["witch_notebook.open_key"] == 5
    print(f"  setting captures Q {assigned}, Esc cancels {cancelled}, right-click resets to B {reset}")
    return assigned and cancelled and reset


def test_click_outside():
    """A click on the hints keeps the book open, a click outside closes it without firing the wand."""
    lua = load_mod(); G = lua.globals()
    open_book(G, to_blank=False)
    click(G, RIGHT_X + 60, PAGE_Y + 40)  # the page of signs
    hints_open = G.controls_enabled is False
    held = click(G, LEFT_X - 40, PAGE_Y + 90)  # left of the book
    print(f"  click on the hints keeps it open: {hints_open}; click outside: controls while held {held}, after release {G.controls_enabled}")
    return hints_open and held is False and G.controls_enabled is True


def test_spawn_hooks():
    """potion.lua append: some world flasks hold ink."""
    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        materials = {}; added = {}; loaded = {}; fixed = false
        function init(e) materials[e] = "water" end
        function EntityGetComponent(e, t) if fixed then return {1} end end
        function ComponentGetValue2() return "potion_material" end
        function EntityGetTransform(e) return e * 37, e * 11 end
        function SetRandomSeed(a, b) math.randomseed(a * 7919 + b) end
        function Random(a, b) return math.random(a, b) end
        function GlobalsGetValue(k, d) return d end
        function RemoveMaterialInventoryMaterial(e) materials[e] = nil end
        function AddMaterialInventoryMaterial(e, m, n) materials[e] = m end
        function EntityLoad(f, x, y) loaded[#loaded + 1] = f; return 99 end
        function EntityAddComponent(e, t, v) added[t] = v end
    ''')
    lua.execute(open(os.path.join(MOD, "files/potion_append.lua"), encoding="utf-8").read())
    G = lua.globals()
    for e in range(1, 2001): G.init(e)
    ink = sum(1 for m in G.materials.values() if m and m.startswith("witch_ink"))
    G.fixed = True; G.materials[5000] = None; G.init(5000)
    print(f"  world flasks with ink: {ink}/2000, fixed-material flask kept '{G.materials[5000]}'")
    return 120 <= ink <= 280 and G.materials[5000] == "water"


def test_cast():
    """Cast with the spellbook in a stubbed entity world."""
    lua = load_cast(); G = lua.globals()
    steady = ";force=0.5;focus=0.3;spread=0;range=0.2;lifetime=0;heavy=0;tilt=0;stability=1;precision=0.9"
    ok = True

    def cast(data, aim=(1, 0), mouse=(300, 0), frame=100):
        G.shots = lua.table()
        book = G.make_book(data)
        controls, holder = G.make_controls(aim[0], aim[1], mouse[0], mouse[1])
        G.spellbook_use(book, holder, controls, frame)
        return book, controls, holder, [dict(file=s_["file"].split("/")[-1], x=s_["x"], y=s_["y"], e=s_["entity"]) for s_ in G.shots.values()]

    for data, want in [("element=fire;form=column", ["bolt_fire.xml"]), ("element=ice;form=levitation", ["orb_ice.xml"]),
                       ("element=steam;form=burst", ["splash_steam.xml"] * 3), ("element=steam;form=field", ["field_steam.xml"]),
                       ("element=wind;form=rain", ["bolt_wind.xml"] * 7),
                       ("element=vacuum;form=column", ["black_hole.xml"]), ("element=nonsense;form=column", ["light_bullet.xml"])]:
        _, _, _, shots = cast(data + steady)
        print(f"  {data:30s} -> {[s_['file'] for s_ in shots]}")
        ok &= [s_["file"] for s_ in shots] == want

    _, _, _, shots = cast("element=water;form=rain" + steady, mouse=(1000, 0))
    print(f"  cloud appears at the cursor, at most 180 away: x {shots[0]['x']:.0f}")
    ok &= shots[0]["file"] == "cloud_water.xml" and "carriers" in [s_ for s_ in G.shots.values()][0]["file"] and abs(shots[0]["x"] - 180) < 1
    _, _, _, shots = cast("element=fire;form=field" + steady)
    print(f"  fire circle around the caster: x {shots[0]['x']:.0f}, y {shots[0]['y']:.0f}")
    ok &= abs(shots[0]["x"]) < 1
    # a sigil alone splashes from the hand: a few drops, short-lived and weaker than a shot
    _, _, _, drops = cast("element=fire;form=burst" + steady)
    _, _, _, shot = cast("element=fire;form=column" + steady)
    life = lambda s_: G.ComponentGetValue2(G.EntityGetFirstComponentIncludingDisabled(s_["e"], "ProjectileComponent"), "lifetime")
    hit = lambda s_: G.ComponentGetValue2(G.EntityGetFirstComponentIncludingDisabled(s_["e"], "ProjectileComponent"), "damage")
    print(f"  fire splash: {len(drops)} drops from x {drops[0]['x']:.0f}, life {life(drops[0])} (a shot {life(shot[0])}), "
          f"damage {hit(drops[0]):.2f} (a shot {hit(shot[0]):.2f})")
    ok &= len(drops) == 3 and drops[0]["x"] > 4 and life(drops[0]) < life(shot[0]) and hit(drops[0]) < hit(shot[0])

    _, _, _, shots = cast("element=earth;form=column;force=1;focus=0;spread=0;range=1;lifetime=0.5;heavy=0;tilt=0;stability=1;precision=1")
    e = shots[0]["e"]
    proj = G.EntityGetFirstComponentIncludingDisabled(e, "ProjectileComponent"); vel = G.EntityGetFirstComponentIncludingDisabled(e, "VelocityComponent")
    damage, radius, life = G.ComponentGetValue2(proj, "damage"), G.ComponentGetValue2(proj, "explosion_radius"), G.ComponentGetValue2(proj, "lifetime")
    vx, vy = G.ComponentGetValue2(vel, "mVelocity")
    print(f"  strong seal: damage {damage:.2f}, blast {radius:.0f}, lifetime {life}, speed {math.hypot(vx, vy):.0f}")
    ok &= damage > 1.5 and radius > 20 and life > 100 and math.hypot(vx, vy) > 150
    _, _, _, shots = cast("element=water;form=levitation" + steady)
    vel = G.EntityGetFirstComponentIncludingDisabled(shots[0]["e"], "VelocityComponent")
    vx, vy = G.ComponentGetValue2(vel, "mVelocity")
    print(f"  levitation: speed {math.hypot(vx, vy):.0f}, gravity {G.ComponentGetValue2(vel, 'gravity_y')}")
    ok &= math.hypot(vx, vy) < 50 and G.ComponentGetValue2(vel, "gravity_y") < 400

    # behaviors: added to every projectile, piercing makes copies
    def comps_of(e, t):
        return [c for c in G.entities[e].values() if G.comps[c]["type"] == t]

    _, _, _, shots = cast("element=light;form=column" + steady + ";b=thrust:2,pierce:2,homing:1")
    homing = all(comps_of(s_["e"], "HomingComponent") for s_ in shots)
    pierce = all(G.ComponentGetValue2(comps_of(s_["e"], "ProjectileComponent")[0], "penetrate_entities") for s_ in shots)
    print(f"  2 piercing + crosshair: {len(shots)} shots, homing {homing}, penetrate {pierce}")
    ok &= len(shots) == 2 and homing and pierce
    _, _, _, shots = cast("element=earth;form=column" + steady + ";b=crush:1,pull:1.5,spin:-0.8")
    e = shots[0]["e"]
    convert = comps_of(e, "MagicConvertMaterialComponent"); script = comps_of(e, "LuaComponent"); pull = comps_of(e, "VariableStorageComponent")
    print(f"  crush + pull + spin: converts {G.comps[convert[0]]['values']['from_material_array'].split(',')[0] if convert else None}, "
          f"script {G.comps[script[0]]['values']['script_source_file'].split('/')[-1] if script else None}, "
          f"pull {G.ComponentGetValue2(pull[0], 'value_float') if pull else None}, "
          f"spin {[G.comps[c]['values']['value_float'] for c in pull if G.comps[c]['values']['name'] == 'witch_spin']}, scripts {len(script)}")
    ok &= bool(convert) and bool(script) and pull and G.ComponentGetValue2(pull[0], "value_float") == 1.5 and len(script) == 2
    ok &= [G.comps[c]["values"]["value_float"] for c in pull if G.comps[c]["values"]["name"] == "witch_spin"] == [-0.8]
    _, _, _, plain = cast("element=fire;form=column" + steady)
    _, _, _, big = cast("element=fire;form=column" + steady + ";b=grow:2")
    _, _, _, still = cast("element=fire;form=column" + steady + ";b=still:1")
    radius = lambda sh: G.ComponentGetValue2(comps_of(sh[0]["e"], "ProjectileComponent")[0], "explosion_radius")
    still_vel = comps_of(still[0]["e"], "VelocityComponent")[0]
    print(f"  expansion: blast {radius(plain):.0f} -> {radius(big):.0f}; stability: gravity {G.ComponentGetValue2(still_vel, 'gravity_y')}, "
          f"friction {G.ComponentGetValue2(still_vel, 'air_friction')}")
    ok &= radius(big) > radius(plain) * 1.5 and G.ComponentGetValue2(still_vel, "gravity_y") == 0 and G.ComponentGetValue2(still_vel, "air_friction") >= 4
    # columns with levitation: floats, but faster than levitation alone; an old sheet without behaviors still floats
    speed = lambda sh: math.hypot(*G.ComponentGetValue2(comps_of(sh[0]["e"], "VelocityComponent")[0], "mVelocity"))
    _, _, _, orb = cast("element=water;form=levitation" + steady + ";b=float:2")
    _, _, _, rising = cast("element=water;form=levitation" + steady + ";b=float:2,thrust:2")
    _, _, _, old = cast("element=water;form=levitation" + steady)
    print(f"  levitation {speed(orb):.0f}, with columns {speed(rising):.0f}, old seal {speed(old):.0f}")
    ok &= speed(orb) < speed(rising) and abs(speed(old) - speed(orb)) < 1

    _, _, _, shots = cast("element=fire;form=field" + steady + ";b=homing:1", mouse=(120, 0))
    print(f"  field with a crosshair: at x {shots[0]['x']:.0f} (the cursor is at 120), homing component {bool(comps_of(shots[0]['e'], 'HomingComponent'))}")
    ok &= abs(shots[0]["x"] - 120) < 1 and not comps_of(shots[0]["e"], "HomingComponent")

    # the book casts without limit, only the delay between casts holds it back
    book, controls, holder, _ = cast("element=fire;form=column" + steady, frame=100)
    G.shots = lua.table(); G.spellbook_use(book, holder, controls, 110)
    too_soon = len(list(G.shots.values()))
    for frame in range(140, 140 + 30 * 100, 30): G.spellbook_use(book, holder, controls, frame)
    many = len(list(G.shots.values()))
    G.globals["witch_notebook.active_spell"] = ""; G.shots = lua.table()
    printed_before = len(list(G.printed.values()))
    next_cast = G.ComponentGetValue2(G.EntityGetFirstComponentIncludingDisabled(book, "VariableStorageComponent"), "value_int")
    G.spellbook_use(book, holder, controls, next_cast - 1)  # even during the cast delay
    print(f"  cast again too soon -> {too_soon} shots, 100 more casts -> {many} shots, book kept {not list(G.killed.values())}; "
          f"no active page -> {len(list(G.shots.values()))} shots, open request {G.globals['witch_notebook.open_request']}")
    ok &= (too_soon == 0 and many == 100 and not list(G.killed.values()) and not list(G.shots.values())
           and G.globals["witch_notebook.open_request"] == "book" and len(list(G.printed.values())) == printed_before)

    # each book casts its own active page, with its own delay: the Palm Quire quickly, the Great Tome slowly
    books = {}
    for key, element in (("book", "fire"), ("quire", "water"), ("tome", "earth")):
        books[key] = G.make_book(f"element={element};form=column" + steady, key)
    delays = {}
    for key, book in books.items():
        G.shots = lua.table()
        controls, holder = G.make_controls(1, 0, 300, 0)
        G.spellbook_use(book, holder, controls, 5000)
        shots = [s_["file"].split("/")[-1] for s_ in G.shots.values()]
        delays[key] = (G.ComponentGetValue2(G.EntityGetFirstComponentIncludingDisabled(book, "VariableStorageComponent"), "value_int") - 5000, shots)
    print(f"  each book casts its own page: {({k: v[1] for k, v in delays.items()})}, delays {({k: v[0] for k, v in delays.items()})}")
    ok &= (delays["book"][1] == ["bolt_fire.xml"] and delays["quire"][1] == ["bolt_water.xml"] and delays["tome"][1] == ["bolt_earth.xml"]
           and delays["quire"][0] < delays["book"][0] < delays["tome"][0])

    # the more a seal makes, the longer it recharges: a splash or a shot only waits for the book, a field longer, a
    # creature longer still, a wiki seal by its tier (the Water Dragon is VII); the book keeps how long it waits
    w = {name: G.seal_cast_delay(G.BOOKS.book, G.parse_spell_data(data)) for name, data in (
        ("splash", "element=fire;form=burst" + steady), ("shot", "element=fire;form=column" + steady),
        ("field", "element=fire;form=field" + steady), ("creature", "element=water;form=burst;shape=dragon" + steady),
        ("tier I", "element=water;form=burst;named=watershot" + steady), ("tier VII", "element=water;form=burst;named=water_dragon" + steady),
        ("swift field", "element=fire;form=field;ink=swift:1" + steady))}
    book_delay = G.BOOKS.book.cast_delay
    book, controls, holder, _ = cast("element=fire;form=field" + steady, frame=5000)
    var = G.EntityGetFirstComponentIncludingDisabled(book, "VariableStorageComponent")
    kept = (G.ComponentGetValue2(var, "value_int") - 5000, G.ComponentGetValue2(var, "value_float"))
    # clicked while it recharges, the seal only fizzles
    G.shots = lua.table()
    G.spellbook_use(book, holder, controls, 5000 + w["field"] - 1)
    fizzled = not list(G.shots.values())
    # a wait left from another session (the frame count started again) is over: the book casts
    G.ComponentSetValue2(var, "value_int", 90000)
    G.shots = lua.table()
    G.spellbook_use(book, holder, controls, 6000)
    fizzled = fizzled and len(list(G.shots.values())) == 1
    print(f"  recharge (frames, the book's own {book_delay}): {w}; a field cast keeps {kept}, clicked too soon it fizzles {fizzled}")
    ok &= (w["splash"] == w["shot"] == w["tier I"] == book_delay < w["swift field"] < w["field"] < w["creature"] < w["tier VII"]
           and kept == (w["field"], w["field"]) and fizzled)

    def misfires(tail):
        return sum(cast("element=fire;form=column;force=0;focus=0;spread=0;range=0;lifetime=0;heavy=0" + tail, frame=f)[3][0]["file"] != "bolt_fire.xml"
                   for f in range(1000, 1400))
    sloppy = misfires(";tilt=0;stability=1;precision=0")
    lopsided = misfires(";tilt=0.8;stability=0.5;precision=0.9")
    clean = misfires(";tilt=0;stability=1;precision=0.9")
    print(f"  misfires of 400: precision 0 -> {sloppy}, stability 0.5 -> {lopsided}, clean -> {clean}")
    ok &= 120 <= sloppy <= 280 and 20 <= lopsided <= 110 and clean == 0
    return ok


def test_pull_script():
    """behaviors/pull.lua: an enemy to the right of the projectile is pulled left, pushed right when
    inverted; physics bodies likewise; the caster is left alone"""
    results = []
    for strength in (1.5, -1.5):
        lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
        lua.globals().strength = strength
        lua.execute(r'''
            vel = { [7] = { 0, 0 }, [5] = { 0, 0 } }
            function GetUpdatedEntityID() return 1 end
            function EntityGetTransform(e) if e == 1 then return 0, 0 end return 20, 0 end
            function EntityGetComponent(e, t) if t == "VariableStorageComponent" then return { 11 } end end
            function EntityGetFirstComponent(e, t)
                if t == "ProjectileComponent" then return 12 end
                if t == "CharacterDataComponent" then return e end
            end
            function ComponentGetValue2(c, f)
                if f == "name" then return "witch_pull" end
                if f == "value_float" then return strength end
                if f == "mWhoShot" then return 5 end
                if f == "mVelocity" then return vel[c][1], vel[c][2] end
            end
            function ComponentSetValue2(c, f, a, b) vel[c] = { a, b } end
            function EntityGetInRadiusWithTag() return { 7, 5 } end
            function PhysicsApplyForceOnArea(fn) force = { fn(0, 2, 10, 0) } end
        ''')
        lua.execute(open(os.path.join(MOD, "files", "behaviors", "pull.lua"), encoding="utf-8").read())
        results.append((lua.eval("vel[7][1]"), lua.eval("vel[5][1]"), lua.eval("force[3]")))
    (pull_enemy, pull_caster, pull_body), (push_enemy, _, push_body) = results
    print(f"  pull: enemy {pull_enemy:.1f}, caster {pull_caster}, body {pull_body:.1f}; push: enemy {push_enemy:.1f}, body {push_body:.1f}")
    return pull_enemy < 0 and pull_caster == 0 and pull_body < 0 and push_enemy > 0 and push_body > 0


def spin_path(spin, speed=250, frames=90, gravity=0):
    """Positions of a projectile flying right with behaviors/spin.lua, one per frame"""
    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().spin = spin
    lua.execute(r'''
        values = { [11] = { name = "witch_spin", value_float = spin, value_string = "" }, [12] = { mVelocity = { 0, 0 } } }
        function GetUpdatedEntityID() return 1 end
        function EntityGetComponent(e, t) if t == "VariableStorageComponent" then return { 11 } end end
        function EntityGetFirstComponent(e, t) if t == "VelocityComponent" then return 12 end end
        function ComponentGetValue2(c, f) local v = values[c][f]; if type(v) == "table" then return v[1], v[2] end; return v end
        function ComponentSetValue2(c, f, a, b) if b ~= nil then values[c][f] = { a, b } else values[c][f] = a end end
    ''')
    script = open(os.path.join(MOD, "files", "behaviors", "spin.lua"), encoding="utf-8").read()
    vel = lua.eval("values[12]")
    vel["mVelocity"] = lua.table_from([speed, 0])
    x = y = 0.0; path = []
    for _ in range(frames):
        lua.execute(script)
        vx, vy = vel["mVelocity"][1], vel["mVelocity"][2]
        x += vx / 60; y += vy / 60; path.append((x, y))
        vel["mVelocity"] = lua.table_from([vx, vy + gravity / 60])
    return path


def test_spin_script():
    """behaviors/spin.lua: the projectile keeps its course but loops around it, the way of the spin"""
    right, left = spin_path(1), spin_path(-1)
    progress = right[-1][0] / (250 * 90 / 60)
    width = max(y for _, y in right) - min(y for _, y in right)
    backwards = sum(1 for a, b in zip(right, right[1:]) if b[0] < a[0])  # loops go back for a moment
    # which way it turns: the cross product of successive steps
    def turning(path):
        return sum((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) for a, b, c in zip(path, path[1:], path[2:]))
    drift = abs(sum(y for _, y in right) / len(right))  # the loops' middle line against the aimed line
    print(f"  spin: course kept {progress:.2f}, loops {width:.0f} px wide, drift {drift:.0f} px, frames going back {backwards}, "
          f"turns {'+' if turning(right) > 0 else '-'} / {'+' if turning(left) > 0 else '-'}")
    return 0.8 < progress < 1.2 and 15 < width < 60 and drift < 8 and backwards > 5 and turning(right) * turning(left) < 0


# the ink bottles beside the book (notebook.lua draw_ink_panel): the first one's top left, one under another
INK_X, INK_Y, INK_STEP = LEFT_X - 7 - 6 - 13, PAGE_Y + 8, 24


def pick_ink(G, index):
    """A click on the index-th ink bottle (0: conjuring ink, 1: blood, ...)"""
    click(G, INK_X + 6, INK_Y + index * INK_STEP + 9)


def test_ink_choice():
    """Only carried inks appear beside the book; a click picks one to draw with. A seal
    drawn partly in blood spends each ink by its line, keeps each stroke's ink on its page and the blood's share in its
    spell (cast.lua applies it); after a reload the page's strokes still know their inks."""
    lua = load_mod(); G = lua.globals()
    G.flask.witch_ink = 1000; G.flask.witch_ink_blood = 1000
    open_book(G)
    pick_ink(G, 1)
    picked = G.globals["witch_notebook.ink"]
    pick_ink(G, 2)  # no third bottle
    kept = G.globals["witch_notebook.ink"]
    random.seed(3)
    strokes = column_seal(lua, "fire")
    pick_ink(G, 0)
    draw(G, strokes[:-3])
    pick_ink(G, 1)
    draw(G, strokes[-3:])
    data = G.globals["witch_notebook.seal_1_spell"] or ""
    inks = (G.globals["witch_notebook.seal_1_inks"] or "").split(",")
    share = float(data.split("ink=blood:")[1].split(";")[0]) if "ink=blood:" in data else 0
    inside = lambda p: 6 <= p[0] <= 174 and 6 <= p[1] <= 174
    line = lambda sts: sum(math.dist(a, b) for st in sts for a, b in zip(st, st[1:]) if inside(a) and inside(b))
    blood_line, all_line = line(strokes[-3:]), line(strokes)
    spent_blood, spent_ink = 1000 - G.flask.witch_ink_blood, 1000 - G.flask.witch_ink
    # the game is saved and loaded
    R = load_mod().globals()
    for k, v in G.globals.items(): R.globals[k] = v
    R.flask.witch_ink = 1000; R.flask.witch_ink_blood = 1000
    open_book(R, to_blank=False)
    R.pressed[7] = True; R.notebook_update(); R.pressed[7] = False
    reloaded = R.globals["witch_notebook.seal_1_inks"] == G.globals["witch_notebook.seal_1_inks"]
    F = load_mod().globals()
    F.flask.witch_ink = 100; F.flask.witch_ink_gold = 100
    open_book(F)
    pick_ink(F, 1)  # gold moves up to the second row when the empty inks are hidden
    filtered = F.globals["witch_notebook.ink"] == "gold"
    print(f"  picked '{picked}', no third bottle leaves '{kept}', filtered gold at row 2: {filtered}; seal inks {inks[:2]}..{inks[-2:]}, blood share {share} "
          f"(its line {blood_line / all_line:.2f}); spent ink {spent_ink}, blood {spent_blood}; reloaded {reloaded}")
    return (picked == "blood" and kept == "blood" and filtered and inks[0] == "ink" and inks[-1] == "blood" and len(inks) == len(strokes)
            and abs(share - blood_line / all_line) < 0.06 and spent_blood > 5 and spent_ink > 30 and reloaded)


def load_sheets(extra=""):
    """sheets.lua in a fresh Lua state with the list sheets_create made, as the spawning scripts have it"""
    lua = load_mod()
    lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
    G = lua.globals()
    rows = G.sheets_create()
    spawn = bare_runtime()
    spawn.execute(STUBS)
    spawn.execute(r"""
        made = {}
        local nid = 5000
        function EntityLoad(f, x, y) nid = nid + 1; made[nid] = { file = f, x = x, y = y, comps = {} }; return nid end
        function EntityAddComponent2(e, t, v) table.insert(made[e].comps, { type = t, values = v }); return 1 end
        function SetRandomSeed(a, b) math.randomseed(math.floor(a * 7919 + b)) end
        function Random(a, b) return math.random(a, b) end
        biome = "$biome_coalmine"
        function BiomeMapGetName(x, y) return biome end
    """ + extra)
    spawn.execute(G.virtual["mods/witch_notebook/files/sheet_list.lua"])
    spawn.execute(open(os.path.join(MOD, "files", "sheets.lua"), encoding="utf-8").read())
    return G, rows, spawn


def sheet_of(S, e):
    """What a spawned sheet carries: key, ink, name, picture, price, tier (from the list)"""
    out = {"file": S.made[e]["file"]}
    for c in S.made[e]["comps"].values():
        v = c["values"]
        if c["type"] == "VariableStorageComponent":
            out[v["name"]] = v["value_string"]
        elif c["type"] == "ItemComponent":
            out["name"] = v["item_name"]
        elif c["type"] == "SpriteComponent" and not v["is_text_sprite"]:
            out["picture"] = v["image_file"]
        elif c["type"] == "ItemCostComponent":
            out["cost"] = v["cost"]
    tiers = {r["key"]: r for r in S.SHEET_LIST.values()}
    if out.get("witch_sheet_key"):
        out["tier"] = tiers[out["witch_sheet_key"]]["tier"]
        out["forbidden"] = bool(tiers[out["witch_sheet_key"]]["forbidden"])
    return out


def test_sheets_ranking():
    """Every wiki seal has a tier I-VII set by hand (SHEET_TIER); the forbidden ones are tier VII. Deeper places give
    stronger sheets; the forbidden come only in Hell and Heaven, and there mostly them, drawn in blood."""
    G, rows, L = load_sheets()
    S = L.globals()
    rows = list(rows.values())
    expected_keys = {entry["key"] for entry in G.GRIMOIRE.values()}
    sheet_keys = {row["key"] for row in rows}
    complete = len(rows) == len(expected_keys) and sheet_keys == expected_keys
    on_disk = open(os.path.join(MOD, "files", "sheet_list.lua"), encoding="utf-8").read() == G.virtual["mods/witch_notebook/files/sheet_list.lua"]
    if not on_disk:
        print("  files/sheet_list.lua is out of date: python tools/make_sheet_list.py")
    tiers = [sum(1 for r in rows if r["tier"] == t and not r["forbidden"]) for t in range(1, 8)]
    forbidden = [r["key"] for r in rows if r["forbidden"]]
    # every seal that is not forbidden is in the hand table, and the table names no seal the grimoire lacks
    hand = set(G.SHEET_TIER.keys())
    allowed = {r["key"] for r in rows if not r["forbidden"]}
    unlisted, stale = sorted(allowed - hand), sorted(hand - allowed)
    if unlisted or stale:
        print(f"  SHEET_TIER: missing {unlisted}, not in the grimoire or forbidden {stale}")
    tier = {r["key"]: r["tier"] for r in rows}
    # the Great Tome comes from the fourth Holy Mountain or the first boss: no tome seal before tier IV
    tome_late = all(r["tier"] >= 4 for r in rows if r["book"] == "tome")
    order_ok = (tier["time_stop"] == tier["water_dragon"] == 7 and tier["water_rose"] == 1 and tier["pyreball"] == 2
                and not unlisted and not stale and tome_late)

    def picks(x, y, hell=False, n=300):
        S.biome = "$biome_boss_victoryroom" if hell else "$biome_coalmine"
        out = []
        for k in range(n):
            e = S.sheet_spawn_found(x + k * 37, y + k * 11)
            out.append(sheet_of(S, e))
        return out
    shallow, deep, hell = picks(200, 600), picks(200, 11000), picks(200, 16000, hell=True)
    mean = lambda l: sum(p["tier"] for p in l) / len(l)
    forbidden_share = lambda l: sum(p["forbidden"] for p in l) / len(l)
    blood = all(p["witch_sheet_ink"] == "blood" for p in hell if p["forbidden"])
    pictures = all(p["picture"].endswith(p["witch_sheet_key"] + ".png") and p["name"].startswith("Seal Sheet") for p in shallow + hell)
    print(f"  tiers I..VII: {tiers}, forbidden {len(forbidden)} (all VII: {all(r['tier'] == 7 for r in rows if r['forbidden'])}); "
          f"tome seals from tier IV: {tome_late}")
    print(f"  mean tier of the sheets found: in the Mines {mean(shallow):.1f}, in the Temple of the Art {mean(deep):.1f}, in Hell {mean(hell):.1f}; "
          f"forbidden: {forbidden_share(shallow):.0%} / {forbidden_share(deep):.0%} / {forbidden_share(hell):.0%}, in blood {blood}")
    return (on_disk and complete and all(t >= 5 for t in tiers) and len(forbidden) == 8 and order_ok
            and mean(shallow) < 1.8 and mean(deep) > 5.5 and forbidden_share(shallow) == 0 and forbidden_share(deep) == 0
            and forbidden_share(hell) > 0.6 and blood and pictures)


def test_sheet_spawns():
    """Where sheets come from: some of the flasks' places in the world (item_spawnlists.lua), opened chests
    (chest_random.lua), Hell's and Heaven's chests (the_end.lua), and the Holy Mountain's shop (temple_altar.lua): now and
    then a sheet or a flask of ink stands in place of a spell, as high as the shop's cards lie on the shelf, half price
    if that one was on sale; now and then a book the witch doesn't have stands second in the lower row, in place of a
    spell or a wand (books.lua) - no other wand is replaced."""
    G, rows, L = load_sheets(r"""
        dofile("data/scripts/item_spawnlists.lua") -- the game's spawn lists, then the mod's addition to them
    """)
    S = L.globals()
    potion = S.spawnlists.potion_spawnlist
    before = potion.rnd_max
    L.execute(open(os.path.join(MOD, "files", "spawnlist_append.lua"), encoding="utf-8").read())
    entry = potion.spawns[1]
    L.execute("made = {}")
    entry.load_entity_func(entry, 300, 2000)
    found = [sheet_of(S, e) for e in S.made.keys()]
    # chests
    L.execute(r"""
        opened = 0
        function drop_random_reward(x, y) opened = opened + 1; return true end
    """)
    L.execute(open(os.path.join(MOD, "files", "chest_append.lua"), encoding="utf-8").read())
    L.execute("made = {}")
    for k in range(400): S.drop_random_reward(100 + k * 53, 3000 + k * 7, 1, 0, 0)
    chest = [sheet_of(S, e) for e in S.made.keys()]
    S.biome = "$biome_boss_victoryroom"
    L.execute("made = {}")
    for k in range(400): S.drop_random_reward(100 + k * 53, 16000 + k * 7, 1, 0, 0)
    chest_hell = [sheet_of(S, e) for e in S.made.keys()]
    # Heaven
    L.execute(r"""
        chests = 0
        function spawn_chest(x, y) chests = chests + 1 end
        function spawn_items(x, y) end
    """)
    L.execute(open(os.path.join(MOD, "files", "the_end_append.lua"), encoding="utf-8").read())
    L.execute("made = {}")
    for k in range(200): S.spawn_chest(-3000 + k * 61, -6500 + k * 3)
    heaven = [sheet_of(S, e) for e in S.made.keys()]
    # the shops of 200 fourth Holy Mountains, as spawn_all_shopitems fills them: 5 spells and 5 over them (one on
    # sale), or 5 wands
    S.biome = "$biome_holymountain"
    L.execute(r"""
        vanilla, wands = 0, 0
        function generate_shop_item(x, y, cheap) vanilla = vanilla + 1 end
        function generate_shop_wand(x, y, cheap) wands = wands + 1 end
        function spawn_all_shopitems(x, y)
            for i = 1, 5 do
                if wand_shop then generate_shop_wand(x + (i - 1) * 26.4, y, i == 3)
                else
                    generate_shop_item(x + (i - 1) * 26.4, y, i == 3, nil, true)
                    generate_shop_item(x + (i - 1) * 26.4, y - 30, false, nil, true)
                end
            end
        end
    """)
    L.execute(open(os.path.join(MOD, "files", "temple_append.lua"), encoding="utf-8").read())
    L.execute("made = {}")
    for k in range(200): S.spawn_all_shopitems(181 + k * 1013, 6300)
    shop = [dict(sheet_of(S, e), y=S.made[e]["y"]) for e in S.made.keys()]
    S.wand_shop = True
    L.execute("made = {}")
    for k in range(200): S.spawn_all_shopitems(181 + k * 1013, 6300)
    # a flask or a book stands on the shelf as its picture, with no body to roll or break (shop.lua shop_stand)
    is_book = lambda p: p.get("witch_shop_book") in ("quire", "tome") and p["file"].endswith("shop_stand.xml")
    in_wand_shops = [sheet_of(S, e) for e in S.made.keys()]
    wand_books = sum(1 for p in in_wand_shops if is_book(p))
    wand_shops = S.wands + wand_books == 1000 and wand_books == len(in_wand_shops)
    slots = 2000
    things = [p for p in shop if p.get("cost")]
    books = [p for p in things if is_book(p)]
    sheets = [p for p in things if p.get("witch_sheet_key")]
    flasks = [p for p in things if p.get("witch_shop_ink") and "potion_ink" in p.get("witch_shop_file", "")
              and p["file"].endswith("shop_stand.xml") and p.get("picture", "").endswith(f"shop_flask_{p['witch_shop_ink']}.png")]
    on_sale = sum(1 for p in shop if p["file"].endswith("sale_indicator.xml"))
    replaced = slots - S.vanilla
    # the shelf: 11 under the first row, 8 under the second; a card stands with its middle 12 over it, a flask 6, a book
    # half its picture's height (the quire 6, the tome 7)
    heights = {(p["y"], "book" if is_book(p) else "sheet" if p.get("witch_sheet_key") else "flask") for p in things}
    heights_ok = heights <= {(6300 + 11 - 12, "sheet"), (6270 + 8 - 12, "sheet"), (6300 + 11 - 6, "flask"), (6270 + 8 - 6, "flask"),
                             (6300 + 11 - 6, "book"), (6300 + 11 - 7, "book")}
    print(f"  flask places: rnd_max {before} -> {potion.rnd_max}, the mod's entry {entry.value_min}..{entry.value_max} made "
          f"{[p.get('witch_sheet_key') for p in found]}")
    print(f"  chests: {len(chest)}/400 with a sheet ({sum(p['forbidden'] for p in chest)} forbidden), in Hell {len(chest_hell)}/400 "
          f"({sum(p['forbidden'] for p in chest_hell)} forbidden), the chests' own rewards {S.opened}/800; Heaven's chests: "
          f"{len(heaven)}/200 sheets, {sum(p['forbidden'] for p in heaven)} forbidden")
    print(f"  200 shops of spells at depth 6300: {replaced}/{slots} replaced ({len(sheets)} sheets, {len(flasks)} flasks of ink, "
          f"{len(books)} books, {on_sale} on sale), prices {sorted(set(p['cost'] for p in things))}, heights {sorted(heights)}; "
          f"200 shops of wands: {wand_books} books in place of a wand, the other wands untouched: {wand_shops}")
    return (potion.rnd_max == before + 6 and entry.value_min == before + 1 and len(found) == 1 and found[0]["witch_sheet_key"]
            and 80 <= len(chest) <= 160 and not any(p["forbidden"] for p in chest) and 170 <= len(chest_hell) <= 270
            and sum(p["forbidden"] for p in chest_hell) > len(chest_hell) * 0.6 and S.opened == 800
            and 70 <= len(heaven) <= 130 and sum(p["forbidden"] for p in heaven) > len(heaven) * 0.6
            and replaced == len(things) and 0.06 * slots <= replaced - len(books) <= 0.14 * slots and sheets and flasks
            and 50 <= len(books) <= 115 and 50 <= wand_books <= 115
            and all(not p.get("forbidden") for p in sheets) and 0 < on_sale < replaced / 3
            and heights_ok and wand_shops)


def test_sheet_pickup():
    """A sheet picked up goes into the book: the next frame it is a page of its own, after the seals, with the wiki's
    seal drawn in the sheet's ink, cast as the wiki's spell with that ink; the seal is learned - the grimoire shows it,
    and only the learned ones (unless the setting opens all). A click on a learned seal in the grimoire doesn't make
    it active: it is there to study and redraw."""
    lua = load_mod()
    lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
    G = lua.globals()
    G.settings["witch_notebook.books_at_spawn"] = False
    G.notebook_on_player_spawned(1)
    lua.execute("sheets_create()")
    lua.execute(r"""
        sheet_vars = { witch_sheet_key = "water_dragon", witch_sheet_ink = "azure", witch_sheet_name = "Water Dragon" }
        function EntityGetComponentIncludingDisabled(e, t) local l = {} for k in pairs(sheet_vars) do l[#l + 1] = k end return l end
        local real_get = ComponentGetValue2
        function ComponentGetValue2(c, f)
            if type(c) == "string" then if f == "name" then return c else return sheet_vars[c] end end
            return real_get(c, f)
        end
        function GamePrintImportant(a, b) important = a .. " - " .. b end
        function GameCreateCosmeticParticle() end
        function EntityKill(e) killed_sheet = e end
    """)
    lua.execute(open(os.path.join(MOD, "files", "sheet_pickup.lua"), encoding="utf-8").read())
    G.item_pickup(777, 1, "")
    pending = G.globals["witch_notebook.pending_sheets"]
    G.notebook_update()
    count = seal_count(G)
    spell = G.globals["witch_notebook.seal_1_spell"] or ""
    learned = G.globals["witch_notebook.learned"]
    # the grimoire shows the learned seal only; a click on it leaves the active seal as it is
    open_book(G, to_blank=False)
    press_button(G, 900007)
    for _ in range(30): G.notebook_update()
    click(G, LEFT_X + 90, PAGE_Y + 90)
    active_wiki = G.globals["witch_notebook.active_wiki"] or ""
    G.settings["witch_notebook.full_grimoire"] = True
    press_button(G, 900007); press_button(G, 900007)
    for _ in range(30): G.notebook_update()
    click(G, LEFT_X + 90, PAGE_Y + 90)
    full_active = G.globals["witch_notebook.active_wiki"] or ""
    print(f"  pending '{pending}', sheet taken {G.killed_sheet == 777}, message '{G.important}'; pages {count}: sheet "
          f"'{G.globals['witch_notebook.seal_1_sheet']}' ink '{G.globals['witch_notebook.seal_1_inks']}', spell ...{spell[-36:]}; "
          f"learned '{learned}'; a click in the grimoire -> active '{active_wiki}', with the whole grimoire open -> '{full_active}'")
    return (pending == "water_dragon:azure;" and G.killed_sheet == 777 and count == 1 and G.globals["witch_notebook.seal_1_sheet"] == "water_dragon"
            and "Spellbook" in (G.important or "")
            and "named=water_dragon" in spell and "ink=azure:1" in spell and learned == "water_dragon"
            and G.globals["witch_notebook.pending_sheets"] == "" and active_wiki == "" and full_active == G.GRIMOIRE[1]["key"])



def test_grimoire_remembers():
    """A seal learned in one run stays in the grimoire in the next (a hidden mod setting keeps them), unless the setting
    grimoire_remembers is off; the next run still counts it as not learned, so sheets of it come as often as before."""
    A = load_mod().globals()
    A.book_learn_seal("water_dragon"); A.book_learn_seal("pyreball"); A.book_learn_seal("water_dragon")
    ever = A.settings["witch_notebook.learned_ever"]
    B = load_mod().globals()  # a new run: new globals, the same mod settings
    for k, v in A.settings.items(): B.settings[k] = v
    known, learned = B.book_seal_known("water_dragon"), B.book_seal_learned("water_dragon")
    B.settings["witch_notebook.grimoire_remembers"] = False
    known_off = B.book_seal_known("water_dragon")
    print(f"  kept '{ever}'; next run: in the grimoire {known}, learned in this run {learned}, with the setting off {known_off}")
    return ever == "water_dragon,pyreball" and known and not learned and not known_off


def test_cast_inks():
    """What the inks do to a cast: blood - more damage and a bigger blast (varying), azure - longer, gold - a light on the
    magic, the clear ink - no flare in the air and the Knights Moralis don't come for a forbidden seal, swift - faster and
    a shorter delay between casts; a wet caster's ink runs unless it is oily."""
    lua = load_cast(); G = lua.globals()
    lua.execute("function EntityInflictDamage() hurt = (hurt or 0) + 1 end; function GameGetGameEffectCount(e, n) return (wet and n == 'WET') and 1 or 0 end")
    steady = "element=fire;form=column;force=0.5;focus=0.3;spread=0;range=0.2;lifetime=0;heavy=0;tilt=0;stability=1;precision=0.9"

    def cast(data, frame=100):
        G.shots = lua.table()
        book = G.make_book(data)
        controls, holder = G.make_controls(1, 0, 300, 0)
        G.spellbook_use(book, holder, controls, frame)
        shots = list(G.shots.values())
        if not shots:
            return None
        e = shots[0]["entity"]
        proj = G.EntityGetFirstComponentIncludingDisabled(e, "ProjectileComponent")
        vel = G.EntityGetFirstComponentIncludingDisabled(e, "VelocityComponent")
        light = G.EntityGetFirstComponentIncludingDisabled(e, "LightComponent")
        next_cast = G.ComponentGetValue2(G.EntityGetFirstComponentIncludingDisabled(book, "VariableStorageComponent"), "value_int")
        return dict(damage=G.ComponentGetValue2(proj, "damage"), radius=G.ComponentGetValue2(proj, "explosion_radius"),
                    life=G.ComponentGetValue2(proj, "lifetime"), speed=math.hypot(*G.ComponentGetValue2(vel, "mVelocity")),
                    light=light is not None, delay=next_cast - frame)
    plain = cast(steady)
    blood = [cast(steady + ";ink=blood:1", frame=f) for f in range(200, 260)]
    azure, gold, swift = cast(steady + ";ink=azure:1"), cast(steady + ";ink=gold:1"), cast(steady + ";ink=swift:1")
    half = [cast(steady + ";ink=blood:0.5", frame=f)["damage"] for f in range(200, 260)]
    # the clear ink hides a forbidden seal from the Knights, and doesn't flare up in the air
    G.globals["witch_notebook.knights_next"] = "0"
    lua.execute("particles = 0; function GameCreateCosmeticParticle(...) particles = particles + 1 end")
    cast("element=light;form=column;precision=1;stability=1;forbidden=true;ink=clear:1", frame=300)
    hidden = G.globals["witch_notebook.knights_next"] == "0" and G.particles == 0
    cast("element=light;form=column;precision=1;stability=1;forbidden=true", frame=400)
    seen = G.globals["witch_notebook.knights_next"] != "0" and G.particles > 0
    G.wet = True
    wet = cast(steady, frame=100)
    wet_oil = cast(steady + ";ink=oil:1", frame=100)
    G.wet = False
    dmg = [b["damage"] for b in blood]
    mean = lambda l: sum(l) / len(l)
    print(f"  damage: plain {plain['damage']:.2f}, blood {min(dmg):.2f}..{max(dmg):.2f} (half blood: mean {mean(half):.2f}), blast "
          f"{plain['radius']:.0f} -> {blood[0]['radius']:.0f}; lifetime {plain['life']} -> azure {azure['life']}; gold light {gold['light']}; "
          f"swift: speed {plain['speed']:.0f} -> {swift['speed']:.0f}, delay {plain['delay']} -> {swift['delay']}")
    print(f"  clear ink: no flare, no Knights {hidden}; without it the Knights come {seen}; a wet caster: damage {wet['damage']:.2f}, "
          f"with oily ink {wet_oil['damage']:.2f}; blood hurt the caster {G.hurt or 0} times in {len(blood)} casts")
    return (min(dmg) > plain["damage"] * 1.15 and max(dmg) - min(dmg) > 0.2 and plain["damage"] < mean(half) < mean(dmg)
            and blood[0]["radius"] > plain["radius"] and azure["life"] > plain["life"] + 60 and gold["light"] and not plain["light"]
            and swift["speed"] > plain["speed"] * 1.3 and swift["delay"] < plain["delay"] and hidden and seen
            and wet["damage"] < plain["damage"] and abs(wet_oil["damage"] - plain["damage"]) < 1e-6 and 1 <= (G.hurt or 0) <= 20)


def test_flip():
    """A page turning over is drawn strip by strip along a curve: at every frame of the turn the strips lie within the
    open book (a little over its edges where the paper rises), both its faces show, and the paper is darker where it
    turns away from the light."""
    lua = load_mod(); G = lua.globals()
    lua.execute(r"""
        drawn = {}
        local nz, nc
        function GuiZSetForNextWidget(g, z) nz = z end
        function GuiColorSetForNextWidget(g, r, gg, b, a) nc = r end
        function GuiImage(g, id, x, y, file, alpha, sx, sy)
            if file:find("strip_", 1, true) then
                drawn[#drawn + 1] = { x = x, y = y, w = 3 * sx, h = 180 * ((sy and sy ~= 0) and sy or sx), file = file, light = nc or 1, z = nz }
            end
            nz, nc = nil, nil
        end
    """)
    open_book(G, to_blank=False)
    G.pressed[4] = True; G.notebook_update(); G.pressed[4] = False  # back from the blank page
    frames = []
    for _ in range(30):
        lua.execute("drawn = {}")
        G.notebook_update()
        frames.append([dict(d) for d in G.drawn.values()])
    right = RIGHT_X + 180
    inside = all(LEFT_X - 2 <= d["x"] and d["x"] + d["w"] <= right + 2 and PAGE_Y - 20 <= d["y"] for f in frames for d in f)
    mid = frames[len(frames) // 2]
    darkest = min(d["light"] for d in mid) if mid else 1
    widths = [sum(d["w"] for d in f) for f in frames]
    over_left = sum(1 for f in frames for d in f if d["x"] + d["w"] < LEFT_X + 180)
    over_right = sum(1 for f in frames for d in f if d["x"] > RIGHT_X)
    turning = len([f for f in frames if f])
    print(f"  {turning} frames with the turning page, strips inside the book {inside}, strips over the right page {over_right}, "
          f"over the left {over_left}; darkest strip at mid-turn {darkest:.2f}; seen width {widths[1]:.0f} -> {min(w for w in widths if w):.0f} "
          f"-> {widths[turning - 2]:.0f}")
    return inside and turning >= 20 and darkest < 0.85 and over_left > 50 and over_right > 50 and not frames[-1]


def test_three_books():
    """The witch's three books: each keeps its own pages and active seal, the names over the book switch between the
    ones the witch carries, B opens the one in hand. A wiki seal too great for the book doesn't awaken in it. A sheet goes into
    the book opened last if it holds the seal, one too great for their books waits until they have a book big enough."""
    lua = load_mod()
    lua.execute(open(os.path.join(MOD, "files", "grimoire.lua"), encoding="utf-8").read())
    lua.execute(CARRY_ALL)
    G = lua.globals()
    G.settings["witch_notebook.books_at_spawn"] = False
    G.notebook_on_player_spawned(1)
    G.book_set_owned("quire")
    random.seed(3)
    open_book(G)
    draw_on_blank(G, column_seal(lua, "fire"))
    book_spell = G.globals["witch_notebook.active_spell"] or ""
    # the quire: its name over the book opens it; a seal on its first leaf
    press_button(G, 900101)
    for _ in range(40): G.notebook_update()
    view, side = G.notebook_view()
    opened_quire = G.globals["witch_notebook.open_book"] == "quire" and view["def"]["key"] == "quire" and side == "front"
    draw_on_blank(G, column_seal(lua, "water"))
    quire_spell = G.globals["witch_notebook.quire.active_spell"] or ""
    kept = G.globals["witch_notebook.active_spell"] == book_spell
    # the Watershot is too great for the quire: drawn on its next leaf, it doesn't awaken
    press_button(G, 900004)  # pass the other empty draft leaf
    for _ in range(40): G.notebook_update()
    press_button(G, 900004)  # [D] flip up to the prepared blank pair
    for _ in range(40): G.notebook_update()
    page = [[(p["x"], p["y"]) for p in st.values()] for st in G.grimoire_strokes(G.GRIMOIRE_BY_KEY["watershot"]).values()]
    draw_on_blank(G, page[1:] + page[:1], pause=2)  # the ring last: it closes the seal
    record = G.globals["witch_notebook.debug_" + G.globals["witch_notebook.debug_next"]] or ""
    refused = ("Too great for the Palm Quire" in record and G.globals["witch_notebook.quire.seals"] == "4"
               and G.globals["witch_notebook.quire.seal_3_draft"] == "1")
    # sheets: a small one goes into the quire (opened last), one for the Great Tome waits for it
    G.globals["witch_notebook.pending_sheets"] = "pyreball:ink;petrification:blood;"
    G.notebook_update()
    small = G.globals["witch_notebook.quire.seal_5_sheet"] == "pyreball"
    waiting = G.globals["witch_notebook.waiting_sheets"]
    G.book_set_owned("tome")
    G.notebook_update()
    great = G.globals["witch_notebook.tome.seal_1_sheet"] == "petrification" and G.globals["witch_notebook.waiting_sheets"] == ""
    # B opens the book in hand
    toggle_book(G)
    G.held_item = 13
    toggle_book(G)
    in_hand = G.globals["witch_notebook.open_book"] == "tome"
    print(f"  the Spellbook's seal '{book_spell[:24]}', the quire's '{quire_spell[:24]}', the Spellbook's kept {kept}; "
          f"the quire opened from the names over the book {opened_quire}; the Watershot refused in the quire {refused}")
    print(f"  a small sheet into the quire {small}, Petrification waits '{waiting}' and goes into the tome once the witch has one "
          f"{great}; B opens the book in hand {in_hand}")
    return (book_spell.startswith("element=fire") and quire_spell.startswith("element=water") and kept and opened_quire and refused
            and small and waiting == "petrification:blood;" and great and in_hand)


def test_quire_flip():
    """The Palm Quire's leaf flips up over the hinge at its top onto the lid: drawn in flat strips along a curve, within
    the quire - both of its faces show, the paper darker mid-turn."""
    lua = load_mod()
    lua.execute(CARRY_ALL)
    G = lua.globals()
    G.settings["witch_notebook.books_at_spawn"] = False
    G.notebook_on_player_spawned(1)
    G.globals["witch_notebook.open_book"] = "quire"
    random.seed(4)
    open_book(G, to_blank=False)
    draw_on_blank(G, column_seal(lua, "fire"))
    view, _ = G.notebook_view()
    lua.execute(r"""
        drawn = {}
        local nz, nc
        function GuiZSetForNextWidget(g, z) nz = z end
        function GuiColorSetForNextWidget(g, r, gg, b, a) nc = r end
        function GuiImage(g, id, x, y, file, alpha, sx, sy)
            if file:find("strip_", 1, true) then
                drawn[#drawn + 1] = { x = x, y = y, w = 120 * sx, h = 3 * ((sy and sy ~= 0) and sy or sx), file = file, light = nc or 1 }
            end
            nz, nc = nil, nil
        end
    """)
    G.pressed[7] = True; G.notebook_update(); G.pressed[7] = False
    frames = []
    for _ in range(26):
        lua.execute("drawn = {}")
        G.notebook_update()
        frames.append([dict(d) for d in G.drawn.values()])
    x0, x1 = view.back.x - 9, view.back.x + 129
    top, bottom = view.back.y - 16, view.front.y + 122
    inside = all(x0 <= d["x"] and d["x"] + d["w"] <= x1 and top <= d["y"] and d["y"] + d["h"] <= bottom for f in frames for d in f)
    flat = all("quire_strip_" in d["file"] for f in frames for d in f)
    over_lid = sum(1 for f in frames for d in f if d["y"] + d["h"] < view.hinge)
    over_pad = sum(1 for f in frames for d in f if d["y"] > view.hinge)
    backs = sum(1 for f in frames for d in f if "strip_back_" in d["file"])
    mid = frames[len(frames) // 2]
    darkest = min(d["light"] for d in mid) if mid else 1
    turning = len([f for f in frames if f])
    print(f"  {turning} frames with the leaf in the air, flat strips {flat}, within the quire {inside}; strips over the pad {over_pad}, "
          f"over the lid {over_lid}, its back shown {backs}; darkest strip mid-turn {darkest:.2f}")
    return inside and flat and turning >= 16 and over_lid > 50 and over_pad > 50 and backs > 50 and darkest < 0.85 and not frames[-1]


def test_book_sources():
    """Where the books come from: every boss gets a death script, in the root entity of its file; the
    first boss killed leaves a Great Tome, once, and none when the witch has one; the Holy Mountains sell the Palm
    Quire now and then while the witch has none, the tome only from the fourth mountain on."""
    lua = load_mod()
    G = lua.globals()
    lua.execute("""
        function SetRandomSeed(a, b) math.randomseed(math.floor(a * 7919 + b)) end
        function Random(a, b) return math.random(a, b) end
        function EntityGetTransform() return 100, 200 end
    """)
    G.books_patch_bosses()
    patched, parsed = 0, 0
    for path, text in G.virtual.items():
        if path.startswith("data/entities/animals/") and "boss_death.lua" in text:
            patched += 1
            # in the root entity: after the death script only the root's end (the game's files aren't all strict XML)
            tail = text[text.rfind("boss_death.lua"):]
            if tail.count("</Entity>") == 1 and tail.rstrip().endswith("</Entity>") and "<Entity" not in tail:
                parsed += 1
    G.books_patch_bosses()  # a second time adds nothing
    twice = sum(text.count("boss_death.lua") for path, text in G.virtual.items() if path.startswith("data/entities/animals/"))
    G.book_boss_drop(1); G.book_boss_drop(1)
    dropped = [f.split("/")[-1] for f in G.loaded.values()].count("great_tome.xml")
    offers = {}
    for tier in (1, 4):
        for owned in (False, True):
            G.run_flags = lua.table()
            if owned: G.run_flags["witch_notebook_has_quire"] = True
            picks = []
            for seed in range(400):
                G.SetRandomSeed(seed, tier)
                picks.append(G.book_for_shop(tier))
            offers[(tier, owned)] = {k: picks.count(k) for k in ("quire", "tome")}
    G.run_flags = lua.table()
    G.run_flags["witch_notebook_has_tome"] = True
    before = len(list(G.loaded.values()))
    G.book_boss_drop(1)
    none_owned = len(list(G.loaded.values())) == before
    print(f"  bosses patched {patched}, the script in their root {parsed}, patched twice {twice}; tomes left by two bosses {dropped}, "
          f"by a boss when the witch has one {0 if none_owned else 1}; shop offers of 400: {offers}")
    q1, q4 = offers[(1, False)], offers[(4, False)]
    return (patched == 10 and parsed == 10 and twice == 10 and dropped == 1 and none_owned and 80 <= q1["quire"] <= 160 and q1["tome"] == 0
            and 30 <= q4["tome"] <= 90 and offers[(1, True)]["quire"] == 0 and offers[(4, True)]["quire"] == 0)


def main():
    from test_recognizer import run_checks
    from test_seal_structure import run_checks as run_structure_checks

    ok_recognizer = run_checks()
    ok_structure = run_structure_checks()
    lua = load_mod()
    names = lua.eval("names")
    ok_icons = all(names[f"mods/witch_notebook/files/gfx/{f}.png"] for f in ("book/page_page", "book/page_plain", "book/page_sheet", "book/cover",
                                                                          "book/strip_page_0", "book/bottle", "ink", "legend_fire", "legend_column"))
    print(f"book images exist: {ok_icons}")
    print("symbols:")
    ok_symbols = test_symbols(lua)
    print("seals:")
    ok_seals = test_seals(lua)
    print("mixes:")
    ok_seals &= test_mixes(lua)
    print("carriers:")
    ok_seals &= test_carriers()
    print("behaviors:")
    ok_seals &= test_behaviors(lua)
    print("every combination:")
    ok_seals &= test_all_combinations(lua)
    print("complex multi-element spells:")
    ok_seals &= test_complex_spells(lua)
    print("balance:")
    ok_balance = test_balance(lua)
    print("seals from wha-spell-simulator:")
    ok_wiki = test_wiki_seals(lua)
    print("drawings from the game:")
    ok_wiki &= test_player_seals(lua)
    print("random ink:")
    ok_wiki &= test_noise_rejection(lua)
    print("precision:")
    ok_precision = test_precision(lua)
    print("notebook flow:")
    ok_flow = test_notebook_flow(load_mod())
    print("a seal with a layer:")
    ok_flow &= test_layer_ring(load_mod())
    print("book pages:")
    ok_flow &= test_book_pages()
    print("the wiki's grimoire in the book:")
    ok_flow &= test_wiki_pages()
    print("ink:")
    ok_ink = (test_ink() and test_spawn_hooks() and test_unfinished_page() and test_failed_page_editing()
              and test_retry_requires_closed_ring() and test_multiple_drafts() and test_blank_page_pairs())
    print("the book in the inventory:")
    ok_ink &= test_book_in_inventory()
    ok_ink &= test_open_book_controls()
    ok_ink &= test_right_click_open()
    ok_ink &= test_open_key_setting()
    ok_ink &= test_open_rmb_and_ad_binds()
    print("click outside:")
    ok_ink &= test_click_outside()
    print("inks:")
    ok_ink &= test_ink_choice()
    print("sheets with seals:")
    ok_sheets = test_sheets_ranking() & test_sheet_spawns() & test_sheet_pickup() & test_grimoire_remembers()
    print("inks in a cast:")
    ok_sheets &= test_cast_inks()
    print("a page turning over:")
    ok_sheets &= test_flip()
    print("the three books:")
    ok_books = test_three_books()
    print("the quire's leaf flipping up:")
    ok_books &= test_quire_flip()
    print("where the books come from:")
    ok_books &= test_book_sources()
    print("casting:")
    ok_cards = test_cast() and test_pull_script() and test_spin_script()
    ok = ok_recognizer and ok_structure and ok_icons and ok_symbols and ok_seals and ok_balance and ok_wiki and ok_precision and ok_flow and ok_ink and ok_cards and ok_sheets and ok_books
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
