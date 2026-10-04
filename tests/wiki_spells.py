"""The wiki's seals: every page of the book's grimoire (files/grimoire.lua, made by tools/make_grimoire.py from
tools/grimoire.py) is drawn again and read back: the book must recognize it as that seal. Two ways to draw it again:
as the grimoire has it, stroke by stroke, shaken, turned and scaled a little; and as a player copies it with the mouse -
long lines where the grimoire has many short pieces (a traced picture), the ring a little bigger or smaller than the
rest, the elements a little off their places, the specks tapped or left out, the strokes in any order. Seals drawn from
the book's vocabulary must not be mistaken for the wiki's. Then the check sheet for the game is written:
tests/wiki_sheet.html - every seal with the wiki's picture, the mod's drawing, what it must do in the game and a place
to mark how it went.

    python tests/wiki_spells.py            (needs: pip install lupa)
    python tests/wiki_spells.py --quick    (fewer drawings per seal)
"""
import html
import math
import os
import random
import sys
import time

from harness import HERE, MOD, load_reader as load  # noqa: F401 (load: what the spell tests read drawings with)

WIKI_IMAGES = os.path.normpath(os.path.join(MOD, "..", "reference", "wha-wiki", "images"))
SHEET = os.path.join(HERE, "wiki_sheet.html")
import grimoire as G  # tools/, on the path with harness

DRAWINGS = 4  # of each way to draw
FALSE_TRIES = 120


def page(lua, entry):
    """the entry's page: strokes of (x, y), a point about every unit as the book records the mouse"""
    out = []
    for stroke in lua.eval("grimoire_strokes")(entry).values():
        pts = [(p["x"], p["y"]) for p in stroke.values()]
        dense = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            n = max(1, int(math.dist(a, b)))
            dense += [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(1, n + 1)]
        out.append(dense)
    return out


def by_hand(strokes, rng):
    """the drawing again: turned, scaled and moved a little, every stroke with a tremor of its own"""
    a = math.radians(rng.uniform(-7, 7))
    k = rng.uniform(0.9, 1.05)
    ox, oy = rng.uniform(-4, 4), rng.uniform(-4, 4)
    out = []
    for s in strokes:
        phase, amp = rng.uniform(0, 6.3), rng.uniform(0.2, 0.7)
        pts = []
        for i, (x, y) in enumerate(s):
            dx, dy = x - 90, y - 90
            px = 90 + ox + k * (dx * math.cos(a) - dy * math.sin(a)) + amp * math.sin(phase + i / 7) + rng.gauss(0, 0.25)
            py = 90 + oy + k * (dx * math.sin(a) + dy * math.cos(a)) + amp * math.cos(phase + i / 9) + rng.gauss(0, 0.25)
            pts.append((px, py))
        out.append(pts)
    return out


# ---- a player's copy ----

def length(s):
    return sum(math.dist(a, b) for a, b in zip(s, s[1:]))


def turn_between(line, cand):
    """how sharply a line turns where it runs on into 'cand', degrees"""
    if len(line) < 2 or len(cand) < 2:
        return 0
    a1 = math.atan2(line[-1][1] - line[-2][1], line[-1][0] - line[-2][0])
    b = cand[min(2, len(cand) - 1)]
    a2 = math.atan2(b[1] - cand[0][1], b[0] - cand[0][0])
    return abs((math.degrees(a2 - a1) + 180) % 360 - 180)


def join_strokes(strokes, rng, gap=5.0, turn=110, lift=0.15):
    """the grimoire's pieces joined into long lines where one ends near another's end and the line runs on - as a hand
    draws on without lifting the pen (and now and then lifts it anyway)"""
    pool = [list(s) for s in strokes if s]
    out = []
    while pool:
        pool.sort(key=length)
        line = pool.pop()
        if is_ring(line):  # the ring is drawn on its own
            out.append(line)
            continue
        for _ in range(2):  # on at the end, then at the start
            while rng.random() >= lift:
                best = None
                for i, s in enumerate(pool):
                    if is_ring(s):
                        continue
                    for cand in (s, s[::-1]):
                        d = math.dist(line[-1], cand[0])
                        if d <= gap and turn_between(line, cand) <= turn and (best is None or d < best[0]):
                            best = (d, i, cand)
                if not best:
                    break
                line = line + best[2]
                pool.pop(best[1])
            line.reverse()
        out.append(line)
    return out


def densify(s, step=1.0):
    """a point about every unit, as the book records the mouse"""
    if len(s) < 2:
        return list(s)
    out = [s[0]]
    for a, b in zip(s, s[1:]):
        n = max(1, int(math.dist(a, b) / step))
        out += [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(1, n + 1)]
    return out


def is_ring(s):
    if length(s) < 150:
        return False
    return sum(math.dist(p, (90, 90)) for p in s) / len(s) > 55


def as_player(strokes, rng, traced=True):
    """the seal copied by a player with the mouse. A traced seal's short pieces (tools/trace.py) are joined into the
    lines a hand draws; a seal made of the vocabulary's symbols is already drawn the way a hand draws them, a symbol at a
    time - its dots are tapped, never left out."""
    lines = join_strokes(strokes, rng) if traced else [list(s) for s in strokes if s]
    a = math.radians(rng.uniform(-6, 6))
    k = rng.uniform(0.92, 1.05)
    ring_k = rng.uniform(0.93, 1.07)  # the ring by eye, a little bigger or smaller than the rest
    ox, oy = rng.uniform(-4, 4), rng.uniform(-4, 4)
    wx, wy, fx, fy = rng.uniform(0, 6.3), rng.uniform(0, 6.3), rng.uniform(0.06, 0.12), rng.uniform(0.06, 0.12)
    warp = rng.uniform(0.6, 1.6)  # the elements a little off their places
    out = []
    for s in lines:
        ring = is_ring(s)
        if length(s) < 3:
            if traced and rng.random() < 0.5:
                continue  # a speck of the picture left out
            s = [s[0]]  # ... or tapped
        pts = densify(s)
        if len(pts) > 2 and rng.random() < 0.5:  # the line overshoots or stops short
            e = rng.uniform(-1.0, 1.5)
            (x1, y1), (x2, y2) = pts[-2], pts[-1]
            d = math.dist((x1, y1), (x2, y2)) or 1
            pts[-1] = (x2 + (x2 - x1) / d * e, y2 + (y2 - y1) / d * e)
        phase, amp = rng.uniform(0, 6.3), rng.uniform(0.3, 0.8)
        wob = []
        for i, (x, y) in enumerate(pts):
            dx, dy = x - 90, y - 90
            if ring:
                dx, dy = dx * ring_k, dy * ring_k
            else:
                dx += warp * math.sin(wx + y * fy)
                dy += warp * math.cos(wy + x * fx)
            px = 90 + ox + k * (dx * math.cos(a) - dy * math.sin(a)) + amp * math.sin(phase + i / 11) + rng.gauss(0, 0.2)
            py = 90 + oy + k * (dx * math.sin(a) + dy * math.cos(a)) + amp * math.cos(phase + i / 13) + rng.gauss(0, 0.2)
            wob.append((px, py))
        out.append(wob)
    rng.shuffle(out)
    return out


def lua_strokes(lua, strokes):
    t = lua.table()
    for i, s in enumerate(strokes):
        t[i + 1] = lua.table_from([lua.table_from({"x": x, "y": y}) for x, y in s])
    return t


def read(lua, strokes):
    """-> (named key or None, spell summary or error), as the book reads a finished drawing"""
    res = lua.eval("read_spell")(lua_strokes(lua, strokes))
    spell = res[0] if isinstance(res, tuple) else res
    if spell:
        return spell["named"], spell["summary"]
    return None, res[1] if isinstance(res, tuple) and len(res) > 1 and res[1] else "?"


def own_seal(lua, rng):
    """a seal of the book's own vocabulary: an element sigil and a few signs around it"""
    sigils = lua.eval("TEMPLATES_SIGILS")
    signs = lua.eval("TEMPLATES_SIGNS")
    elements = ["fire", "water", "wind", "earth", "light", "crystal", "smoke", "sand"]
    sign_keys = list(lua.eval("DICTIONARY_BASIC_SIGNS").values()) + ["regions", "binding", "pointing", "purify"]
    strokes = [[(90 + 68 * math.cos(t / 120 * 2 * math.pi), 90 + 68 * math.sin(t / 120 * 2 * math.pi)) for t in range(125)]]

    def put(shape, cx, cy, size, angle):
        xs = [p[1] for st in shape.values() for p in st.values()]
        ys = [p[2] for st in shape.values() for p in st.values()]
        mx, my = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        k = size / max(max(xs) - min(xs), max(ys) - min(ys), 1e-6)
        for st in shape.values():
            pts = [(cx + ((p[1] - mx) * math.cos(angle) - (p[2] - my) * math.sin(angle)) * k,
                    cy + ((p[1] - mx) * math.sin(angle) + (p[2] - my) * math.cos(angle)) * k) for p in st.values()]
            strokes.append(pts)
    put(sigils[rng.choice(elements)][1], 90, 90, rng.uniform(26, 34), rng.uniform(-0.15, 0.15))
    n = rng.choice([2, 3, 4, 4, 6, 8])
    kind = rng.choice(sign_keys)
    for i in range(n):
        ang = 2 * math.pi * i / n + rng.uniform(-0.1, 0.1)
        if rng.random() < 0.3:
            kind = rng.choice(sign_keys)
        put(signs[kind][1], 90 + 48 * math.cos(ang), 90 + 48 * math.sin(ang), rng.uniform(14, 19), ang - math.pi / 2)
    return by_hand(strokes, rng)


# ---------------------------------------------------------------- the sheet

def svg(strokes, size=180):
    lines = []
    for s in strokes:
        pts = " ".join(f"{x:.1f},{y:.1f}" for x, y in s[::2] + [s[-1]])
        lines.append(f'<polyline points="{pts}"/>')
    return (f'<svg viewBox="0 0 {size} {size}" class="seal"><g fill="none" stroke="currentColor" stroke-width="1.6" '
            f'stroke-linecap="round" stroke-linejoin="round">{"".join(lines)}</g></svg>')


def meaning(lua, data):
    """what the book casts, in words"""
    spell = {}
    for part in data.split("&")[0].split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            spell[k] = v
    elements = lua.eval("DICTIONARY_ELEMENTS")
    words = []
    e = spell.get("element")
    if e and elements[e]:
        words.append(elements[e]["name"])
    manifest = spell.get("manifest")
    names = lua.eval("MANIFEST_NAMES")
    if manifest:
        words.append(names[manifest] or manifest)
    elif spell.get("shape"):
        words.append("sculpture: " + (lua.eval("DICTIONARY_SIGILS")[spell["shape"]]["name"] or spell["shape"]).lower())
    else:
        forms = lua.eval("DICTIONARY_FORMS")
        words.append("floats in place" if spell.get("floats") else (forms[spell.get("form", "")] or spell.get("form", "")))
    texts = {b["key"]: b["text"] for b in lua.eval("DICTIONARY_BEHAVIORS").values()}
    for item in spell.get("b", "").split(","):
        key = item.split(":")[0]
        if texts.get(key):
            words.append(texts[key])
    if spell.get("forbidden"):
        words.append("forbidden")
    return ", ".join(words)


STATUS = {"works": ("works", "ok"), "interpreted": ("the mod's reading", "mid"), "whole": ("recognized as a whole", "whole")}


def write_sheet(lua, entries, results, false_named):
    spells = {s.key: s for s in G.SPELLS}
    cards = []
    categories = []
    for n, entry in enumerate(entries, 1):
        key = entry["key"]
        spell = spells.get(key)
        if entry["category"] not in categories:
            categories.append(entry["category"])
        status, css = STATUS.get(entry["status"], (entry["status"], "mid"))
        ok, total, misses = results[key]
        image = os.path.join(WIKI_IMAGES, spell.image) if spell else ""
        rel = os.path.relpath(image, HERE).replace("\\", "/") if image and os.path.exists(image) else ""
        wiki_img = f'<img src="{html.escape(rel)}" alt="" loading="lazy">' if rel else '<div class="noimg">no picture</div>'
        note = f'<p class="note">{html.escape(spell.note)}</p>' if spell and spell.note else ""
        miss = f'<span class="miss">{html.escape(", ".join(sorted(set(misses)))[:120])}</span>' if misses else ""
        badges = f'<span class="badge {css}">{status}</span>'
        if entry["forbidden"]:
            badges += '<span class="badge forbidden">forbidden: the Knights Moralis will come</span>'
        cards.append(f'''
<article class="card" data-cat="{html.escape(entry['category'])}" data-key="{key}">
  <header><span class="num">{n}</span><h2>{html.escape(entry['name'])}</h2><span class="en">{html.escape(entry['en'])}</span>{badges}</header>
  <div class="pics"><figure>{wiki_img}<figcaption>wiki</figcaption></figure><figure>{svg(page(lua, entry))}<figcaption>book page</figcaption></figure></div>
  <div class="text">
    <p class="effect"><b>In the game:</b> {html.escape(entry['effect'])}</p>
    <p><b>The book casts:</b> {html.escape(meaning(lua, entry['spell']))}</p>
    {note}
    <p class="rec"><b>Hand drawing recognized:</b> <span class="{'good' if ok == total else ('mid' if ok >= total * 0.6 else 'bad')}">{ok}/{total}</span> {miss}</p>
    <p class="how">Book [B] → "Grimoire" → section "{html.escape(entry['category'])}", p. {n} → LMB on the page → close → LMB</p>
    <div class="check"><label><input type="checkbox" data-k="{key}:ok"> works as described</label>
      <label><input type="checkbox" data-k="{key}:pretty"> looks nice</label>
      <textarea data-k="{key}:note" placeholder="notes: what you see in the game, what is wrong"></textarea></div>
  </div>
</article>''')
    recognized = sum(r[0] for r in results.values())
    total = sum(r[1] for r in results.values())
    tabs = "".join(f'<button data-cat="{html.escape(c)}">{html.escape(c)}</button>' for c in categories)
    doc = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Wiki Seals Check</title>
<style>
:root {{ --bg: #f4efe4; --paper: #fffaf0; --ink: #2a2140; --muted: #7a6e5c; --line: #d8ccb4; --ok: #2f7d4f; --mid: #a8741a;
  --bad: #b3372e; --accent: #7b3fbf; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg: #1d1a24; --paper: #27232f; --ink: #e9e2f5; --muted: #a79eb5; --line: #3c3548;
  --ok: #6fcf97; --mid: #e0b45a; --bad: #ef7d73; --accent: #b98cf0; }} }}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--ink); font: 15px/1.45 system-ui, sans-serif; }}
main {{ max-width: 1100px; margin: 0 auto; padding: 16px; }}
h1 {{ font-size: 1.6em; margin: .2em 0; }}
.intro {{ color: var(--muted); }}
.stats span {{ display: inline-block; margin-right: 1.2em; }}
nav {{ position: sticky; top: 0; background: var(--bg); padding: 8px 0; z-index: 2; display: flex; flex-wrap: wrap; gap: 6px; }}
nav button {{ border: 1px solid var(--line); background: var(--paper); color: var(--ink); border-radius: 14px; padding: 3px 10px; cursor: pointer; }}
nav button.on {{ background: var(--accent); color: #fff; border-color: var(--accent); }}
.card {{ background: var(--paper); border: 1px solid var(--line); border-radius: 10px; margin: 12px 0; padding: 12px;
  display: grid; grid-template-columns: 360px 1fr; gap: 14px; }}
.card header {{ grid-column: 1 / -1; display: flex; flex-wrap: wrap; align-items: baseline; gap: 8px; }}
.card h2 {{ font-size: 1.15em; margin: 0; }}
.num {{ color: var(--muted); font-variant-numeric: tabular-nums; }}
.en {{ color: var(--muted); font-style: italic; }}
.badge {{ font-size: .78em; border-radius: 10px; padding: 1px 8px; border: 1px solid currentColor; }}
.badge.ok {{ color: var(--ok); }} .badge.mid {{ color: var(--mid); }} .badge.whole {{ color: var(--accent); }} .badge.forbidden {{ color: var(--bad); }}
.pics {{ display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }}
figure {{ margin: 0; text-align: center; }}
figure img, .seal, .noimg {{ width: 100%; aspect-ratio: 1; object-fit: contain; background: #fff; border-radius: 6px; border: 1px solid var(--line); }}
.seal {{ color: #2a2140; }}
.noimg {{ display: grid; place-items: center; color: var(--muted); }}
figcaption {{ font-size: .8em; color: var(--muted); }}
.text p {{ margin: .35em 0; }}
.note {{ color: var(--muted); font-size: .92em; }}
.how {{ color: var(--muted); font-size: .88em; }}
.good {{ color: var(--ok); font-weight: 600; }} .mid {{ color: var(--mid); font-weight: 600; }} .bad {{ color: var(--bad); font-weight: 600; }}
.miss {{ color: var(--muted); font-size: .85em; }}
.check {{ display: flex; flex-wrap: wrap; gap: 6px 16px; align-items: center; margin-top: 6px; }}
.check textarea {{ width: 100%; min-height: 2.4em; background: var(--bg); color: var(--ink); border: 1px solid var(--line); border-radius: 6px; padding: 4px 6px; font: inherit; }}
.card.done {{ border-color: var(--ok); }}
@media (max-width: 760px) {{ .card {{ grid-template-columns: 1fr; }} }}
</style></head><body><main>
<h1>The wiki's seals in the game: check sheet</h1>
<p class="intro">Every spell from the Spells page of the Witch Hat Atelier wiki: the wiki's picture, how the seal is drawn in the mod's book,
what it should do in the game. In the game: book [B] → the "Grimoire" button above the book → the seal's page → LMB on it makes it
active → close the book → LMB with the book in hand casts it. You can also draw the seal yourself on a blank page - the book recognizes it
as a whole. Check marks and notes are saved in this browser.</p>
<p class="stats"><span>Seals: <b>{len(entries)}</b></span><span>Hand drawings recognized: <b>{recognized}/{total}</b></span>
<span>Own seals taken for a wiki seal: <b>{false_named}/{FALSE_TRIES}</b></span><span id="done"></span></p>
<nav><button data-cat="" class="on">All</button>{tabs}</nav>
{"".join(cards)}
</main>
<script>
const KEY = "witch_notebook.wiki_sheet";
let saved = {{}};
try {{ saved = JSON.parse(localStorage.getItem(KEY) || "{{}}"); }} catch (e) {{}}
function save() {{ try {{ localStorage.setItem(KEY, JSON.stringify(saved)); }} catch (e) {{}} count(); }}
function count() {{
  const cards = document.querySelectorAll(".card");
  let done = 0;
  cards.forEach(c => {{ const ok = saved[c.dataset.key + ":ok"] === true; c.classList.toggle("done", ok); if (ok) done++; }});
  document.getElementById("done").textContent = "Checked in the game: " + done + "/" + cards.length;
}}
document.querySelectorAll("[data-k]").forEach(el => {{
  const k = el.dataset.k;
  if (el.type === "checkbox") {{ el.checked = saved[k] === true; el.addEventListener("change", () => {{ saved[k] = el.checked; save(); }}); }}
  else {{ el.value = saved[k] || ""; el.addEventListener("input", () => {{ saved[k] = el.value; save(); }}); }}
}});
document.querySelectorAll("nav button").forEach(b => b.addEventListener("click", () => {{
  document.querySelectorAll("nav button").forEach(x => x.classList.toggle("on", x === b));
  document.querySelectorAll(".card").forEach(c => {{ c.style.display = !b.dataset.cat || c.dataset.cat === b.dataset.cat ? "" : "none"; }});
}}));
count();
</script></body></html>
'''
    open(SHEET, "w", encoding="utf-8").write(doc)


def main():
    quick = "--quick" in sys.argv
    drawings = 3 if quick else DRAWINGS
    lua = load()
    entries = list(lua.eval("GRIMOIRE").values())
    names = {e["key"]: e["name"] for e in entries}
    rng = random.Random(7)
    results = {}
    started = time.perf_counter()
    by_way = {"stroke by stroke": [0, 0], "as a player": [0, 0]}
    for entry in entries:
        key = entry["key"]
        base = page(lua, entry)
        ok, misses = 0, []
        traced = not entry["recipe"]
        for way, draw in (("stroke by stroke", by_hand), ("as a player", lambda b, r: as_player(b, r, traced))):
            for _ in range(drawings):
                named, what = read(lua, draw(base, rng))
                by_way[way][1] += 1
                # a seal drawn twice in the wiki (Water Bolt, Pouch of Calling) is the same seal either way
                if named == key or (named and names.get(named) == entry["name"]):
                    ok += 1
                    by_way[way][0] += 1
                else:
                    misses.append(named or str(what))
        results[key] = (ok, 2 * drawings, misses)
        mark = "" if ok == 2 * drawings else "   <-- " + ", ".join(sorted(set(misses)))[:100]
        print(f"  {key:28s} {ok}/{2 * drawings}{mark}", flush=True)
    false_named = 0
    for i in range(FALSE_TRIES if not quick else 40):
        named, what = read(lua, own_seal(lua, rng))
        if named:
            false_named += 1
            print(f"  own seal {i} taken for {named} ({what})")
    recognized = sum(r[0] for r in results.values())
    total = sum(r[1] for r in results.values())
    print(f"recognized {recognized}/{total} drawings of {len(entries)} seals ("
          + ", ".join(f"{way}: {ok}/{n}" for way, (ok, n) in by_way.items())
          + f"); own seals named as the wiki's: {false_named}; {time.perf_counter() - started:.0f} s")
    write_sheet(lua, entries, results, false_named)
    print(f"written {SHEET}")
    player_ok, player_n = by_way["as a player"]
    good = recognized >= total * 0.9 and player_ok >= player_n * 0.88 and false_named <= (FALSE_TRIES if not quick else 40) * 0.03
    print("PASS" if good else "FAIL")
    sys.exit(0 if good else 1)


if __name__ == "__main__":
    main()
