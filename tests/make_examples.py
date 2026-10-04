"""Draws example seals with the test generators, keeps only those the mod's own parser accepts, and
writes an HTML cheat sheet: what to draw in the notebook and what should happen in the game.

Usage (from the mod folder):  python tests/make_examples.py [output.html]     (needs: pip install lupa)
"""
import html
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_tests as t  # noqa: E402

ELEMENTS = ["fire", "water", "wind", "earth", "light"]
PAIR_SIDES, PAIR_VERT, CROSS = [0, 180], [90, 270], [0, 90, 180, 270]


def case(make, expected, note=None, need=None):
    """expected: 'element:form' or an error text; need: a behavior the spell must have"""
    return {"make": make, "expected": expected, "note": note, "need": need}


def s(sigils, signs=(), **kw):
    return lambda lua: t.seal(lua, sigils, signs, **kw)


def pair(key, angles=PAIR_SIDES, inverted=False):
    return [(key, a, inverted) for a in angles]


SECTIONS = [
    ("Elements without signs", "A ring and an element sigil in the center. Without signs around, the element appears in place.",
     [case(s([k]), f"{k}:burst") for k in ELEMENTS]),
    ("Column", "Two column signs at the sides, stem towards the center: the element flies as a projectile where the witch aims.",
     [case(s([k], pair("column")), f"{k}:column") for k in ELEMENTS]),
    ("Dispersion", "Two dispersion signs above and below: the element spills out as a cloud or a fan.",
     [case(s([k], pair("dispersion", PAIR_VERT)), f"{k}:dispersion") for k in ELEMENTS]),
    ("Levitation", "Four levitation signs in a cross, arrows towards the center: the effect drifts slowly and floats (the manga's Water Orb).",
     [case(s([k], pair("levitation", CROSS)), f"{k}:levitation") for k in ELEMENTS]),
    ("Convergence", "Convergence compresses the element: water into ice, wind into vacuum, fire into plasma, earth into stone, light into a beam. With a column - a compressed projectile.",
     [case(s(["water"], pair("convergence", PAIR_VERT) + pair("column")), "ice:column", "ice spear"),
      case(s(["wind"], pair("convergence")), "vacuum:burst"),
      case(s(["fire"], pair("convergence", PAIR_VERT) + pair("column")), "plasma:column"),
      case(s(["earth"], pair("convergence", PAIR_VERT) + pair("column")), "stone:column"),
      case(s(["light"], pair("convergence", PAIR_VERT) + pair("column")), "beam:column")]),
    ("Inverted signs", "A sign drawn facing outwards acts the other way round: an inverted column strikes sideways, like dispersion.",
     [case(s(["light"], pair("column", inverted=True)), "light:dispersion", "inverted columns - a fan of sparks"),
      case(s(["fire"], pair("column", inverted=True)), "fire:dispersion")]),
    ("Strength and balance", "Two identical element sigils - stronger. Signs on one side send the spell in an arc and make the seal unstable.",
     [case(s(["fire", "fire"], pair("column", PAIR_VERT)), "fire:column", "two fire sigils - more damage"),
      case(s(["earth"], pair("column", CROSS)), "earth:column", "4 columns in a cross - straight and stable"),
      case(s(["earth"], [("column", a, False) for a in [150, 180, 210]]), "earth:column", "3 columns on the left - a high arc, more misfires")]),
    ("Mixing elements", "Two different element sigils side by side in the center mix into a third element. The same signs around apply to the mix.",
     [case(s(pair.split("+")), f"{mix}:burst") for pair, mix in [
         ("fire+water", "steam"), ("fire+wind", "firestorm"), ("fire+earth", "lava"), ("fire+light", "sunfire"), ("water+wind", "storm"),
         ("water+earth", "mud"), ("water+light", "shimmer"), ("wind+earth", "sandstorm"), ("wind+light", "thunder"), ("earth+light", "crystal")]]
     + [case(s(["fire", "water"], pair("convergence", PAIR_VERT)), "steamblast:burst", "steam with convergence"),
        case(s(["wind", "light"], pair("column", PAIR_VERT)), "thunder:column", "lightning as a column")]),
    ("Signs add up", "Every sign adds its behavior to the spell, and they act together. "
     "The form (projectile, orb, cloud) is set by column, levitation and dispersion, the other signs change what comes out.",
     [case(s(["fire"], pair("column") + pair("pull", PAIR_VERT)), "fire:column", "pulling: the projectile pulls enemies to itself"),
      case(s(["wind"], pair("column") + pair("pull", PAIR_VERT, inverted=True)), "wind:column", "pulling facing outwards - pushes away"),
      case(s(["earth"], pair("column") + pair("crush", PAIR_VERT)), "earth:column", "crushing: drills rock, turning it into sand"),
      case(s(["earth"], pair("column") + pair("crush", PAIR_VERT, inverted=True)), "earth:column", "inverted crushing: the sand around hardens - a bridge"),
      case(s(["light"], pair("column", PAIR_VERT) + pair("pierce")), "light:column", "two piercings - two projectiles going through"),
      case(s(["water"], pair("column") + pair("crosshair", PAIR_VERT)), "water:column", "crosshair - homing"),
      case(s(["fire"], pair("column") + pair("expansion", PAIR_VERT)), "fire:column", "expansion, chevrons outwards - bigger and stronger"),
      case(s(["fire"], pair("column") + pair("expansion", PAIR_VERT, inverted=True)), "fire:column", "chevrons inwards - smaller and faster"),
      case(s(["fire"], pair("column") + pair("stability", PAIR_VERT)), "fire:column", "stability - the projectile stops and hangs like a mine"),
      case(s(["water"], pair("levitation") + pair("column", PAIR_VERT)), "water:levitation", "levitation with a column: the orb flies faster"),
      case(s(["wind"], [("column", a, False, 30) for a in CROSS]), "wind:column", "signs turned sideways the same way - the projectile twists",
           "spin")]),
    ("Empty ring", "A closed ring without signs - a shockwave, as in the manga.",
     [case(s([]), "shockwave:burst")]),
    ("Should not work", "The notebook rejects these drawings with a message.",
     [case(s(["fire"], closed=False), "The ring is not closed"),
      case(lambda lua: t.place(t.hand(t.templates(lua)[("sigil", "fire")]), 90, 90, 60), "No ring - the seal does nothing"),
      case(s([], pair("column")), "No element sigil"),
      case(s(["fire", "earth", "light"]), "Too many elements - the ring will not hold")]),
]


# remember which template each drawn stroke came from, to color sigils and signs
ROLE = {}
_hand, _place = t.hand, t.place


class Tagged(list):
    kind = None


def hand_tagged(strokes):
    out = Tagged(_hand(strokes))
    for (kind, _), shape in t.TEMPLATES.items():
        if shape is strokes:
            out.kind = kind
    return out


def place_tagged(strokes, *args, **kwargs):
    out = _place(strokes, *args, **kwargs)
    for st in out:
        ROLE[id(st)] = getattr(strokes, "kind", None) or "sigil"
    return out


t.hand, t.place = hand_tagged, place_tagged


def pick(lua, c, seed):
    """The cleanest of the first accepted drawings"""
    random.seed(seed)
    best, found = None, 0
    for _ in range(200):
        ROLE.clear()
        strokes = c["make"](lua)
        got, spell = t.run(lua, strokes)
        if got != c["expected"] or (c["need"] and c["need"] not in spell["behaviors"]):
            continue
        found += 1
        precision = spell["precision"] if spell else 0
        if best is None or precision > best[2]:
            best = (strokes, spell, precision, got, dict(ROLE))
        if found >= 15:
            break
    if best is None:
        raise SystemExit(f"no accepted drawing for {c['expected']}")
    return best


def svg(strokes, roles):
    parts = ['<svg viewBox="0 0 180 180" role="img" aria-hidden="true">',
             '<rect class="page" x="0.5" y="0.5" width="179" height="179" rx="2"/>',
             '<circle class="guide" cx="89.5" cy="89.5" r="72"/>']
    for st in strokes:
        pts = " ".join(f"{x:.1f},{y:.1f}" for x, y in st)
        parts.append(f'<polyline class="{roles.get(id(st), "ring")}" points="{pts}"/>')
    parts.append("</svg>")
    return "".join(parts)


def effect_text(lua, spell):
    return lua.eval("dictionary_effect")(spell["element"], spell["form"])["text"]


def card(lua, c, seed):
    strokes, spell, precision, got, roles = pick(lua, c, seed)
    ink = round(t.length(strokes) * lua.eval("INK_PER_UNIT"))
    if spell:
        title = spell["summary"]
        text = effect_text(lua, spell) + (f" — {c['note']}" if c["note"] else "")
        meta = (f'<span>precision {round(precision * 100)}%</span><span>stability {round(spell["stability"] * 100)}%</span>'
                f'<span>~{ink} ink</span>')
        cls = "card"
    else:
        title, text = got, "the seal will not stay in the book"
        meta = f'<span>~{ink} ink wasted</span>'
        cls = "card card-fail"
    return (f'<figure class="{cls}">{svg(strokes, roles)}<figcaption>'
            f'<b>{html.escape(title)}</b><p>{html.escape(text)}</p><div class="meta">{meta}</div>'
            f'</figcaption></figure>')


def reference_cards(lua):
    """The complete seals from wha-spell-simulator's samples"""
    out = []
    for sample in json.load(open(os.path.join(t.MOD, "tests", "data", "wha_sample_spells.json"), encoding="utf-8")):
        strokes = [[(10 + p["x"] * 160, 10 + p["y"] * 160) for p in st] for st in sample["strokes"]]
        got, spell = t.run(lua, strokes)
        text = effect_text(lua, spell) if spell else "not recognized"
        out.append(f'<figure class="card">{svg(strokes, {})}<figcaption><b>{html.escape(spell["summary"] if spell else got)}</b>'
                   f'<p>{html.escape(sample["displayName"])}: {html.escape(text)}</p></figcaption></figure>')
    return out


STYLE = """
:root {
  --ground: #e9ebef; --text: #1d1b26; --muted: #5d5a6c; --rule: #cfd2da;
  --paper: #ece0c0; --paper-edge: #6e5037; --guide: #d6c7a6;
  --ink: #231c3a; --mark: #5b45c8; --fail: #a4402a;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    color-scheme: dark;
    --ground: #15141b; --text: #e8e6ef; --muted: #a09cb2; --rule: #2d2b38; --fail: #e0785f;
  }
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --ground: #15141b; --text: #e8e6ef; --muted: #a09cb2; --rule: #2d2b38; --fail: #e0785f;
}
body { margin: 0; background: var(--ground); color: var(--text); font: 15px/1.55 "PT Sans", "Segoe UI", sans-serif; }
main { max-width: 1120px; margin: 0 auto; padding-inline: 16px; padding-block: 32px 64px; display: grid; gap: 40px; }
h1, h2 { font-family: "Philosopher", Georgia, serif; font-weight: 700; text-wrap: balance; margin: 0; }
h1 { font-size: 34px; line-height: 1.15; }
h2 { font-size: 22px; }
header { display: grid; gap: 12px; max-width: 68ch; }
header p, section > p { margin: 0; color: var(--muted); }
.legend { display: flex; flex-wrap: wrap; gap: 8px 20px; font-size: 14px; color: var(--muted); }
.legend span { display: inline-flex; align-items: center; gap: 8px; }
.legend i { width: 22px; height: 3px; border-radius: 2px; background: var(--ink); }
.legend i.m { background: var(--mark); }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) .legend i:not(.m) { background: var(--paper); } }
:root[data-theme="dark"] .legend i:not(.m) { background: var(--paper); }
section { display: grid; gap: 14px; border-top: 1px solid var(--rule); padding-top: 20px; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 18px; }
.card { margin: 0; display: grid; gap: 10px; align-content: start; }
.card svg { width: 100%; max-width: 100%; aspect-ratio: 1; display: block; }
.page { fill: var(--paper); stroke: var(--paper-edge); stroke-width: 3; }
.guide { fill: none; stroke: var(--guide); stroke-width: 1; }
polyline { fill: none; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
.ring, .sigil { stroke: var(--ink); }
.sign { stroke: var(--mark); stroke-width: 2.4; }
figcaption { display: grid; gap: 4px; }
figcaption b { font-weight: 700; }
figcaption p { margin: 0; color: var(--muted); font-size: 14px; }
.card-fail figcaption b { color: var(--fail); }
.meta { display: flex; flex-wrap: wrap; gap: 4px 12px; font: 12px/1.4 "JetBrains Mono", Consolas, monospace;
        color: var(--muted); font-variant-numeric: tabular-nums; }
"""


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "examples.html")
    lua = t.load_mod()
    t.templates(lua)
    body = []
    for i, (title, hint, cases) in enumerate(SECTIONS):
        cards = [card(lua, c, 1000 * i + j) for j, c in enumerate(cases)]
        body.append(f'<section><h2>{html.escape(title)}</h2><p>{html.escape(hint)}</p><div class="grid">{"".join(cards)}</div></section>')
        print(f"{title}: {len(cards)}")
    body.append('<section><h2>References</h2><p>Seals from the wha-spell-simulator examples, drawn by hand by its author.</p>'
                f'<div class="grid">{"".join(reference_cards(lua))}</div></section>')
    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Witch Notebook Seals</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Philosopher:wght@700&family=PT+Sans:wght@400;700&family=JetBrains+Mono&display=swap">
<style>{STYLE}</style>
</head>
<body>
<main>
<header>
<h1>Witch Notebook Seals</h1>
<p>The drawings are made by the offline tests' generators and went through the mod's recognizer: every seal here gives exactly the stated result. The page is as in the notebook: 180×180, the pale circle is a guide for the ring. The element sigil is drawn in the center, the signs around it with the stem or tip towards the center. A seal activates the moment its ring closes: draw a ring with a gap, write the signs in and close the gap with the last stroke. Open the notebook with B, repeat the drawing and compare the effect in the game.</p>
<div class="legend"><span><i></i>ring and element sigil</span><span><i class="m"></i>signs around</span></div>
</header>
{"".join(body)}
</main>
</body>
</html>
"""
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(page)
    print(f"written {out_path}")


if __name__ == "__main__":
    main()
