"""Reads the drawings the notebook recorded in the game (notebook.lua, record_drawing) and explains how
the current code parses them: the ring, every group of strokes with its scores as a sigil and as a
sign (upright and inverted), and the spell it compiles to.

The game writes the records into the save when you quit (Save & Quit).

Usage (from the mod folder, needs: pip install lupa pillow):
    python tests/debug_sigil.py                 # the last drawing
    python tests/debug_sigil.py --list          # all kept drawings
    python tests/debug_sigil.py -n 12           # drawing number 12
    python tests/debug_sigil.py --png out.png   # also render it
    python tests/debug_sigil.py --source path   # another world_state.xml to read from
    python tests/debug_sigil.py --keep "wind with turned columns" wind:column spin
    python tests/debug_sigil.py --keep "false sigil" reject
    python tests/debug_sigil.py --keep "plain wind" wind:burst --named none
                                                # ... and the wiki's seal it must (or, 'none', must not) be named after
                                                # keep the drawing as a test (tests/data/player_seals.json):
                                                # what it must give (or reject) and the behaviors it must have
"""
import argparse
import html
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_tests as t  # noqa: E402

SAVE = os.path.expandvars(r"%USERPROFILE%\AppData\LocalLow\Nolla_Games_Noita\save00\world_state.xml")
# the book a drawing was made in (books.lua) is in the records since there are three
RECORD = re.compile(r"n=(\d+);frame=(\d+);(?:book=(\w+);)?result=(.*?);strokes=([-\d., |]*)")

# appended to seal.lua so it can reach its local functions: every group of strokes with its scores
SEAL_DEBUG = r'''
function debug_groups( strokes )
    local ring, parts = find_ring( strokes )
    if not ring then return nil end
    local inner, index = {}, {}
    for i, stroke in ipairs( strokes ) do
        if not parts[i] then
            local b = bbox( { stroke } )
            if ( b.cx - ring.x ) ^ 2 + ( b.cy - ring.y ) ^ 2 < ( ring.r * 0.95 ) ^ 2 then
                inner[#inner + 1] = stroke; index[stroke] = i
            end
        end
    end
    local out = { ring = ring, ring_parts = {}, groups = {} }
    for i in pairs( parts ) do out.ring_parts[#out.ring_parts + 1] = i end
    local sigils, signs = template_sets()
    for _, g in ipairs( group_strokes( inner ) ) do
        local ids = {}
        for _, st in ipairs( g.strokes ) do ids[#ids + 1] = index[st] end
        local dx, dy = g.box.cx - ring.x, g.box.cy - ring.y
        local angle = math.atan2( dy, dx )
        local sk, ss = recognizer_match( sigils, g.strokes )
        -- the best pose of every sign
        local by_key = {}
        for _, m in ipairs( recognizer_scores( signs, rotate( g.strokes, g.box.cx, g.box.cy, math.pi / 2 - angle ) ) ) do
            if not by_key[m.key] or m.score > by_key[m.key].score then by_key[m.key] = m end
        end
        local ranked = {}
        for _, m in pairs( by_key ) do ranked[#ranked + 1] = m end
        table.sort( ranked, function( a, b ) return a.score > b.score end )
        out.groups[#out.groups + 1] = { ids = ids, angle = angle, dist = math.sqrt( dx * dx + dy * dy ) / ring.r,
            size = g.box.size / ring.r, sigil = { sk, ss }, signs = { ranked[1], ranked[2] }, symbol = recognize_symbol( g.strokes, g.box, ring ) }
    end
    return out
end
'''


def read_records(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    records = {}
    for m in RECORD.finditer(html.unescape(text)):
        n = int(m.group(1))
        strokes = [[tuple(map(float, p.split(","))) for p in s.split()] for s in m.group(5).split("|") if s.strip()]
        records[n] = {"n": n, "frame": int(m.group(2)), "book": m.group(3) or "book", "result": m.group(4), "strokes": strokes}
    return records


def load(path_arg):
    path = path_arg or SAVE
    records = read_records(path) if os.path.exists(path) else {}
    for r in records.values():
        r["source"] = path
    return records


def load_lua():
    lua = t.luajit21.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(t.STUBS)
    for f in ["files/templates.lua", "files/dictionary.lua", "files/sigils.lua", "files/recognizer.lua"] + t.SEAL_FILES:
        src = open(os.path.join(t.MOD, f), encoding="utf-8").read()
        if f == "files/seal.lua":
            for name in ["find_ring", "bbox", "group_strokes", "template_sets", "rotate", "recognize_symbol"]:
                src = src.replace("local function " + name, "function " + name)
            src += SEAL_DEBUG
        lua.execute(src)
    # the wiki's pages too: a drawing is named after one of them, as in the game
    lua.execute(open(os.path.join(t.MOD, "files", "grimoire.lua"), encoding="utf-8").read())
    return lua


def explain(lua, rec):
    import math
    strokes = rec["strokes"]
    L = t.lua_strokes(lua, strokes)
    print(f"drawing #{rec['n']} (frame {rec['frame']}, in the {rec['book']}, from {rec['source']})")
    print(f"  in game: {rec['result']}")
    got, spell = t.run(lua, strokes)
    now = f"{spell['summary']} / {lua.eval('serialize_spell')(spell)}" if spell else got
    same = now.split(";force=")[0] == rec["result"].split(";force=")[0]  # recorded points are rounded
    print(f"  current code: {now}{'' if same else '   <-- differs'}")
    print(f"  {len(strokes)} strokes, {sum(len(s) for s in strokes)} points, ink ~{round(t.length(strokes) * 0.1)}")
    info = lua.eval("debug_groups")(L)
    if not info:
        print("  no closed ring among the strokes")
        return
    ring = info["ring"]
    print(f"  ring: strokes {sorted(info['ring_parts'].values())}, center {ring['x']:.0f},{ring['y']:.0f}, r {ring['r']:.1f}, roundness {ring['roundness']:.3f} (max 0.22)")
    min_score = lua.eval("SEAL_MIN_SCORE")
    for g in info["groups"].values():
        sym = g["symbol"]
        turn = f", turned {math.degrees(sym['turn']):+.0f} deg" if sym and sym["turn"] else ""
        verdict = (f"{sym['kind']} {sym['key']}{' (inverted)' if sym['inverted'] else ''} {sym['score']:.2f}{turn}" if sym else "UNRECOGNIZED")
        print(f"  strokes {list(g['ids'].values())}: at {math.degrees(g['angle']):.0f} deg, {g['dist']:.2f} r, size {g['size']:.2f} r -> {verdict}")
        signs = " | ".join(f"{m['key']} {m['score']:.2f} at {math.degrees(m['tilt']):.0f} deg" for m in g["signs"].values())
        print(f"      as sigil {g['sigil'][1]} {g['sigil'][2]:.2f} | best signs: {signs}  (min {min_score})")
    # the final reading: groups may have been split or peeled
    res = lua.eval("parse_seal")(L)
    tree = res[0] if isinstance(res, tuple) else res
    if tree:
        print("  symbols: " + ", ".join(
            f"{s['key']}{'~' if s['inverted'] else ''} {s['score']:.2f} at {math.degrees(s['angle']):.0f} deg"
            + (f" turned {math.degrees(s['turn']):+.0f}" if s["turn"] else "") for s in tree["symbols"].values()))
    if spell:
        print("  spell: " + ", ".join(f"{k} {spell[k]}" for k in ["element", "form", "force", "focus", "spread", "range", "lifetime", "tilt", "stability", "precision"])
              + ", behaviors " + (", ".join(f"{k}:{v}" for k, v in spell["behaviors"].items()) or "none"))


def render(rec, path):
    from PIL import Image, ImageDraw
    scale = 4
    img = Image.new("RGB", (180 * scale, 180 * scale), (236, 224, 192))
    d = ImageDraw.Draw(img)
    d.ellipse([(89.5 - 72) * scale, (89.5 - 72) * scale, (89.5 + 72) * scale, (89.5 + 72) * scale], outline=(214, 199, 166))
    colors = [(35, 28, 58), (180, 60, 40), (40, 110, 60), (60, 70, 170), (150, 90, 20), (120, 40, 140)]
    for i, s in enumerate(rec["strokes"]):
        c = colors[i % len(colors)]
        pts = [(x * scale, y * scale) for x, y in s]
        if len(pts) > 1:
            d.line(pts, fill=c, width=scale)
        d.text((pts[0][0] + 4, pts[0][1] - 12), str(i + 1), fill=c)
    img.save(path)
    print(f"  rendered to {path} (stroke numbers at their start points)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, help="drawing number (default: the last)")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--png")
    ap.add_argument("--source")
    ap.add_argument("--keep", nargs="+", metavar=("NAME", "EXPECTED"), help="name, element:form, behaviors...")
    ap.add_argument("--named", metavar="KEY", help="with --keep: the wiki's seal it must be named after; 'none': after no seal")
    args = ap.parse_args()
    records = load(args.source)
    if not records:
        sys.exit("no recorded drawings: draw a sigil in the game, then Save & Quit")
    if args.list:
        for n in sorted(records):
            r = records[n]
            print(f"#{n}: {len(r['strokes'])} strokes, {r['result']}")
        return
    rec = records[args.n if args.n else max(records)]
    explain(load_lua(), rec)
    if args.png:
        render(rec, args.png)
    if args.keep:
        path = os.path.join(t.MOD, "tests", "data", "player_seals.json")
        kept = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else []
        name, expected, behaviors = args.keep[0], args.keep[1], args.keep[2:]
        kept.append({"name": name, "expected": expected, "behaviors": behaviors,
                     "strokes": [" ".join(f"{x:.1f},{y:.1f}" for x, y in st) for st in rec["strokes"]]})
        if args.named:
            kept[-1]["named"] = None if args.named == "none" else args.named
            kept[-1]["grimoire"] = True
        json.dump(kept, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        print(f"  kept as a test: '{name}' -> {expected} {behaviors} ({len(kept)} in {path})")


if __name__ == "__main__":
    main()
