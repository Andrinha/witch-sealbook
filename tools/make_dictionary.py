"""Builds docs/dictionary.html, the illustrated dictionary of sigils and signs.
Sigil shapes come from the MIT-licensed wha-spell-simulator dictionary (../reference/wha-spell-simulator),
sign shapes from the mod's own templates.lua (the simulator's and the Independent Witch Hat Atelier Wiki
drawings, see tools/import_templates.py).

Usage (from the mod folder):  python tools/make_dictionary.py"""
import html
import json
import math
import os

MOD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(MOD, "..", "reference", "wha-spell-simulator")
OUT = os.path.join(MOD, "docs", "dictionary.html")


def load(name):
    d = json.load(open(os.path.join(SRC, name), encoding="utf-8"))
    return {e["id"]: e for e in d}


SIGILS = load("sigils.json")
SIGNS = load("signs.json")
SAMPLES = load("sample-spells.json")


def thin(stroke, step=3):
    return stroke[::step] + [stroke[-1]]


def svg_strokes(strokes, size=120, pad=10, cls="ink"):
    """strokes: lists of (x, y) in 0..1"""
    out = [f'<svg viewBox="0 0 {size} {size}" aria-hidden="true">']
    for s in strokes:
        pts = " ".join(f"{pad + x * (size - 2 * pad):.1f},{pad + y * (size - 2 * pad):.1f}" for x, y in s)
        out.append(f'<polyline class="{cls}" points="{pts}"/>')
    out.append("</svg>")
    return "".join(out)


def template(entry):
    t = entry["strokeTemplate"]
    return [[(p["x"], p["y"]) for p in thin(s)] for s in t["strokes"]]


def poly(*pts):
    return list(pts)


def arc(cx, cy, r, a0, a1, n=24):
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n), cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


def mod_signs():
    """sign shapes the notebook recognizes, from the mod's templates.lua (bottom-of-ring pose, center is up)"""
    from lupa import luajit21
    lua = luajit21.LuaRuntime()
    lua.execute(open(os.path.join(MOD, "files", "templates.lua"), encoding="utf-8").read())
    return {key: [[(p[1], p[2]) for p in st.values()] for st in shapes[1].values()] for key, shapes in lua.eval("TEMPLATES_SIGNS").items()}


MOD_SIGNS = mod_signs()

ELEMENTS = [
    ("fire", "Fire", "a triangle with two \"horns\" at the sides and a line down from the base",
     "fireball", "circle of fire", "rain of liquid fire", "floating flame", "plasma: a narrow searing beam"),
    ("water", "Water", "a drop, an S-shaped wave and an upside-down drop",
     "a jet of water, as from a hose", "circle of water", "rain cloud", "a water orb hangs and drifts", "ice: an ice ball"),
    ("wind-directs-air", "Wind", "a double spiral (S) with three short rays on each side",
     "air projectile, knocks back", "whirlwind around", "gusts in every direction", "levitation field", "vacuum: a black hole"),
    ("earth", "Earth", "a crossbar on top, a vertical line and a \"tick\" under it",
     "ball of earth", "earth crumbles around", "rain of stones", "floating boulder", "hard boulder, pierces"),
    ("light", "Light", "a diamond in a square with a cross of rays",
     "glowing projectile", "flash", "a scatter of sparks, blinds", "a glowing lantern orb", "laser"),
]

# key, name, source, shape, in the manga, in the game
SIGN_ROWS = [
    ("column", "Column", True, "a perpendicular to a base line; the base outside, the line towards the center",
     "The magic strikes as a column or a beam. If the signs are unbalanced, the flow goes from the side with more of them to the opposite one.",
     "The projectile flies where the witch aims."),
    ("levitation", "Levitation", True, "an arrow on a base line, tip towards the center",
     "The magic floats above the seal or moves the object it is drawn on.",
     "The effect drifts slowly and hangs: a floating orb."),
    ("convergence", "Convergence", True, "an upside-down triangle, flat side towards the center",
     "The magic is compressed into one point; loose matter turns solid.",
     "Narrow and strong: less spread, more damage; water hardens into ice, air is compressed into vacuum."),
    ("dispersion", "Dispersion", "wiki", "a column with an arc under the base",
     "The magic spills out in every direction, as from an overflowing bucket.",
     "A cloud or rain over the target."),
    ("pull", "Pulling", "wiki", "a line with a triangle arrowhead and a \"tick\", tip towards the center",
     "Pulls an object to the seal; turned outwards it apparently pushes away.",
     "The projectile pulls enemies and items around to itself; inverted it pushes them away."),
    ("crush", "Crushing", "wiki", "a zigzag with two peaks, peaks towards the center",
     "Crushes an object into sand or powder (Wall Breaker); inverted it puts it back together (the Integration seal).",
     "The projectile drills rock, turning it into sand; inverted it binds sand and snow around into stone."),
    ("pierce", "Piercing", "wiki", "a line through a small diamond",
     "Turns the magic into projectiles, as many as there are signs.",
     "The projectiles go through enemies; as many signs, as many projectiles."),
    ("crosshair", "Crosshair", "wiki", "a cross of four lines with an empty middle",
     "Directs the magic at what the sign points to.",
     "Homing in on enemies."),
    ("expansion", "Expansion", "wiki", "two nested chevrons, point outwards (the corner of the Enlarge sign)",
     "Enlarges an object; chevrons inwards - shrinks it (Seal of Expansion and Spell of Reduction).",
     "Bigger, stronger and slower; inverted - smaller and faster."),
    ("stability", "Stability", "wiki", "two parallel waves",
     "Keeps an object balanced in the air.",
     "The projectile slows down and hangs in place like a mine."),
]

RULES = [
    ("Ring", "A seal works only when its ring is closed. The ring's roundness gives precision: power, charges, no misfires."),
    ("Element sigil in the center", "One element sigil in the middle of the ring sets what the seal creates. The sigil's size is the effect's size."),
    ("Signs around", "Modifier signs are drawn around between the center and the ring, tip or stem towards the center. Their shape sets how the element manifests."),
    ("Symmetry", "Signs are placed symmetrically: 2 facing each other or 4 in a cross. An asymmetric seal works but is unstable - misfires and a skewed direction."),
    ("Count", "More identical signs - a stronger effect. Different signs add up: column + convergence - a narrow powerful beam."),
    ("No signs", "The element simply appears in place: a flash, a circle of fire or water around the target."),
]


def fit(strokes):
    """template strokes -> centered at 0,0, largest side 1"""
    xs = [x for s in strokes for x, _ in s]; ys = [y for s in strokes for _, y in s]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    k = 1 / max(max(xs) - min(xs), max(ys) - min(ys))
    return [[((x - cx) * k, (y - cy) * k) for x, y in s] for s in strokes]


def put(strokes, cx, cy, size, angle=0.0):
    c, s_ = math.cos(angle), math.sin(angle)
    return [[(cx + (x * c - y * s_) * size, cy + (x * s_ + y * c) * size) for x, y in st] for st in fit(strokes)]


def ring(r, cx=0.5, cy=0.5):
    return [arc(cx, cy, r, 0, 2 * math.pi, 72)]


def sigil(key):
    return template(SIGILS[key])


def sign(key):
    return MOD_SIGNS[key]


def signs_around(key, r, angles, size=0.09, cx=0.5, cy=0.5):
    """signs on a circle of radius r, each turned so its bottom-of-ring pose faces the center"""
    out = []
    for deg in angles:
        a = math.radians(deg)
        out += put(sign(key), cx + r * math.cos(a), cy + r * math.sin(a), size, a - math.pi / 2)
    return out


def sigils_around(key, r, angles, size=0.13, cx=0.5, cy=0.5):
    out = []
    for deg in angles:
        a = math.radians(deg)
        out += put(sigil(key), cx + r * math.cos(a), cy + r * math.sin(a), size)
    return out


CROSS, PAIR_SIDES, PAIR_VERT = [0, 90, 180, 270], [0, 180], [90, 270]

COMPLEX = [
    ("Ice Spear", "signs add up",
     ring(0.46) + put(sigil("water"), 0.5, 0.5, 0.2) + signs_around("convergence", 0.33, PAIR_VERT) + signs_around("column", 0.33, PAIR_SIDES),
     "Water in the center; two convergences above and below turn it into ice, two columns at the sides make it a fast piercing projectile.",
     "a high-speed ice projectile that pierces enemies"),
    ("Steam Blast", "two elements mix",
     ring(0.46) + put(sigil("fire"), 0.39, 0.5, 0.17) + put(sigil("water"), 0.61, 0.5, 0.17) + signs_around("convergence", 0.35, CROSS),
     "Fire and water side by side in the center give steam; four convergences compress it into a point, and the steam explodes.",
     "a clot of steam; on hit an explosion and a cloud of scalding steam"),
    ("Funnel", "signs add up",
     ring(0.46) + put(sigil("wind-directs-air"), 0.5, 0.5, 0.2) + signs_around("levitation", 0.33, PAIR_SIDES) + signs_around("pull", 0.33, PAIR_VERT),
     "Wind in the center, two levitations make it a slow floating orb, two pullings draw enemies to it.",
     "a floating clot of wind that pulls enemies to itself"),
    ("Drill", "signs add up",
     ring(0.46) + put(sigil("earth"), 0.5, 0.5, 0.2) + signs_around("column", 0.33, PAIR_SIDES) + signs_around("crush", 0.33, PAIR_VERT),
     "Earth with columns flies as a projectile, crushing at the sides turns the rock in its way into sand.",
     "a stone projectile drills a tunnel, the rock crumbles into sand"),
    ("Crooked Column", "asymmetry",
     ring(0.46) + put(sigil("earth"), 0.5, 0.5, 0.2) + signs_around("column", 0.33, [150, 180, 210]),
     "Earth and three columns on the left only: the seal is unbalanced, the flow goes off right and up in an arc. It works, but unstably - more misfires.",
     "an earth projectile flies in a high arc; a higher chance of misfire"),
]


SYSTEM = [
    ("A seal is a tree", "The recognizer turns a drawing not into one sign but into a structure: rings → layers → element sigils and modifiers, each with its place on the ring and its turn to the center."),
    ("Rings - layers and satellites", "A ring around a ring strengthens the inner spell or adds an effect to it; a small ring at the side is a satellite seal that prepares material for the center (as in the manga: Vapor Bubble, Serpent's Bed of Sand). Stage 9."),
    ("Linked seals", "A line between seals links them: the effects combine, one seal sets off another. Stage 10."),
    ("Elements in one layer mix", "Two different elements in one layer give a third by the mixing table. One element twice - strength. More than two - the ring will not hold."),
    ("Signs add up", "Every sign adds to the parameters (force, focus, spread, range, lifetime) and adds its behavior: pulling, crushing, piercing, homing, size, hanging still. The form - projectile, orb, cloud - is set by column, levitation and dispersion."),
    ("The dictionary is data", "Elements, signs, mixes and effects are described by tables. A new sign is a new line and a shape template, without touching the recognizer or the compiler."),
    ("Cost of complexity", "Every sign spends ink and lowers precision; an asymmetric or overloaded seal misfires more often. A strong spell needs a careful drawing."),
]
PIPELINE = ["drawing", "strokes", "ring", "signs: place and turn", "seal tree", "spell: parameters and behaviors", "Noita projectiles"]


def seal_svg(sample):
    strokes = [[(p["x"], p["y"]) for p in thin(s, 2)] for s in sample["strokes"]]
    return svg_strokes(strokes, size=220, pad=8)


def card(svg, title, badge, lines):
    body = "".join(f"<p>{html.escape(x)}</p>" if not x.startswith("<") else x for x in lines)
    b = f'<span class="badge {"own" if badge == "our shape" else "src"}">{badge}</span>'
    return f'<figure class="card">{svg}<figcaption><div class="head"><b>{html.escape(title)}</b>{b}</div>{body}</figcaption></figure>'


def main():
    sigil_cards = []
    for key, name, shape, *_ in ELEMENTS:
        sigil_cards.append(card(svg_strokes(template(SIGILS[key])), name, "from the manga", [f"Shape: {shape}."]))
    sign_cards = []
    for key, name, manga, shape, lore, game in SIGN_ROWS:
        strokes = MOD_SIGNS[key]
        badge = {True: "from the manga", "wiki": "from the wiki"}.get(manga, "our shape")
        sign_cards.append(card(svg_strokes(strokes), name, badge,
                               [f"Shape: {shape}.", f"In the manga: {lore}", f'<p class="game">In the game: {html.escape(game)}</p>']))
    # the effects table straight from the mod's dictionary.lua
    from lupa import luajit21
    lua = luajit21.LuaRuntime()
    lua.execute(open(os.path.join(MOD, "files", "dictionary.lua"), encoding="utf-8").read())
    effect, elements = lua.eval("dictionary_effect"), lua.eval("DICTIONARY_ELEMENTS")
    forms = ["burst", "column", "dispersion", "levitation"]
    head = "".join(f"<th>{n}</th>" for n in ["No signs", "Column", "Dispersion", "Levitation"])
    rows = []
    for base in ["fire", "water", "wind", "earth", "light"]:
        for key in [base, elements[base]["condensed"]]:
            name = elements[key]["name"] + ("" if key == base else " (convergence)")
            cells = [effect(key, f)["text"] for f in forms]
            rows.append(f"<tr><th>{html.escape(name)}</th>" + "".join(f"<td>{html.escape(c)}</td>" for c in cells) + "</tr>")
    samples = "".join(
        f'<figure class="seal">{seal_svg(SAMPLES[k])}<figcaption><b>{t}</b><p>{d}</p></figcaption></figure>'
        for k, t, d in [("fire-column", "Fire Column", "Fire in the center, four column signs in a cross: fire strikes as a column up over the seal."),
                        ("water-orb", "Water Orb", "Water in the center, levitation signs in a cross: the water hangs as a ball.")])
    rules = "".join(f"<div class='rule'><b>{html.escape(t)}</b><p>{html.escape(d)}</p></div>" for t, d in RULES)
    complex_cards = "".join(
        f'<figure class="seal">{svg_strokes(st, size=240, pad=6)}<figcaption><div class="head"><b>{html.escape(t)}</b>'
        f'<span class="badge own">{html.escape(tag)}</span></div><p>{html.escape(how)}</p>'
        f'<p class="game">In the game: {html.escape(game)}</p></figcaption></figure>'
        for t, tag, st, how, game in COMPLEX)
    mix_rows = []
    for pair, mix in lua.eval("DICTIONARY_MIXES").items():
        a, b = pair.split("+")
        name = f"{elements[a]['name']} + {elements[b]['name'].lower()}"
        texts = "; ".join(f"{n}: {effect(mix, f)['text']}" for n, f in [("no signs", "burst"), ("column", "column")])
        mix_rows.append(f"<tr><th>{html.escape(name)}</th><td><b>{html.escape(elements[mix]['name'])}</b> — {html.escape(texts)}</td></tr>")
    mixes = "".join(sorted(mix_rows))
    system = "".join(f"<div class='rule'><b>{html.escape(t)}</b><p>{html.escape(d)}</p></div>" for t, d in SYSTEM)
    pipeline = "".join(f"<li>{html.escape(x)}</li>" for x in PIPELINE)

    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sign Dictionary</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Philosopher:wght@700&family=PT+Sans:wght@400;700&display=swap">
<style>
:root {{ --ground:#e9ebef; --text:#1d1b26; --muted:#5d5a6c; --rule:#cfd2da; --paper:#ece0c0; --edge:#6e5037; --ink:#231c3a; --accent:#5b45c8; --warm:#9a5a1c; }}
@media (prefers-color-scheme: dark) {{ :root {{ color-scheme: dark; --ground:#15141b; --text:#e8e6ef; --muted:#a09cb2; --rule:#2d2b38; --accent:#9d8cf0; --warm:#e0a15a; }} }}
body {{ margin:0; background:var(--ground); color:var(--text); font:15px/1.55 "PT Sans","Segoe UI",sans-serif; }}
main {{ max-width:1120px; margin:0 auto; padding-inline:16px; padding-block:32px 64px; display:grid; gap:36px; }}
h1,h2 {{ font-family:"Philosopher",Georgia,serif; margin:0; text-wrap:balance; }}
h1 {{ font-size:34px; }} h2 {{ font-size:22px; }}
header, section {{ display:grid; gap:12px; }}
section {{ border-top:1px solid var(--rule); padding-top:20px; }}
header p, section > p {{ margin:0; color:var(--muted); max-width:72ch; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(190px,1fr)); gap:18px; }}
.card, .seal {{ margin:0; display:grid; gap:8px; align-content:start; }}
svg {{ width:100%; max-width:100%; aspect-ratio:1; display:block; background:var(--paper); border:2px solid var(--edge); border-radius:3px; box-sizing:border-box; }}
polyline {{ fill:none; stroke:var(--ink); stroke-width:2.2; stroke-linecap:round; stroke-linejoin:round; }}
figcaption {{ display:grid; gap:4px; }} figcaption p {{ margin:0; color:var(--muted); font-size:14px; }}
.head {{ display:flex; flex-wrap:wrap; gap:6px 10px; align-items:baseline; }}
.badge {{ font-size:12px; letter-spacing:.03em; padding:1px 7px; border-radius:10px; border:1px solid currentColor; }}
.badge.src {{ color:var(--accent); }} .badge.own {{ color:var(--warm); }}
p.game {{ color:var(--text); }}
.seals {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(240px,1fr)); gap:18px; }}
.rules {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(260px,1fr)); gap:14px 24px; }}
.rule p {{ margin:2px 0 0; color:var(--muted); }}
.table {{ overflow-x:auto; }}
table {{ border-collapse:collapse; min-width:720px; width:100%; font-size:14px; }}
th, td {{ text-align:left; vertical-align:top; padding:8px 10px; border-bottom:1px solid var(--rule); }}
thead th {{ color:var(--muted); font-weight:700; }}
ul {{ margin:0; padding-left:20px; color:var(--muted); }} li {{ margin:4px 0; }}
.pipeline {{ list-style:none; margin:0; padding:0; display:flex; flex-wrap:wrap; gap:6px; }}
.pipeline li {{ margin:0; padding:3px 10px; border:1px solid var(--rule); border-radius:12px; font-size:14px; }}
.pipeline li + li::before {{ content:"→ "; color:var(--muted); }}
table.mix {{ min-width:0; max-width:560px; }}
a {{ color:var(--accent); }}
</style>
</head>
<body>
<main>
<header>
<h1>Sign Dictionary</h1>
<p>A proposal for rebuilding the mod's seals by the rules of "Witch Hat Atelier": an element sigil in the center, modifier signs around it, the ring closes the seal. Signs marked "from the manga" are drawn after the fan simulator's templates, the missing ones are our own shapes in the same style.</p>
</header>

<section><h2>How a seal works</h2>
<div class="rules">{rules}</div>
<div class="seals">{samples}</div>
</section>

<section><h2>Element sigils</h2><p>Drawn in the center of the ring. The manga's five elements; in it light counts as a kind of fire.</p>
<div class="grid">{"".join(sigil_cards)}</div></section>

<section><h2>Modifier signs</h2><p>Drawn around the element sigil. Shown in the position at the bottom of the ring: the seal's center is above. Elsewhere a sign turns together with the ring. A sign drawn facing outwards acts the other way round; symmetric ones (piercing, crosshair, stability) have no inverted form. At least two directional signs turned sideways the same way spin the spell: it twists and flies shorter. One arrow only directs it.</p>
<div class="grid">{"".join(sign_cards)}</div></section>

<section><h2>What you get in Noita</h2><p>The element and the signs most numerous around it. Convergence compresses the element into a dense variant. The effects are built from ready-made Noita projectiles; the table comes from the mod's dictionary.</p>
<div class="table"><table><thead><tr><th></th>{head}</tr></thead><tbody>{"".join(rows)}</tbody></table></div></section>

<section><h2>Complex seals</h2><p>How compound spells are built from five elements and ten signs. Drawn from the same templates.</p>
<div class="seals">{complex_cards}</div></section>

<section><h2>How the flexible system works</h2>
<ol class="pipeline">{pipeline}</ol>
<div class="rules">{system}</div></section>

<section><h2>Mixing elements</h2><p>Two different elements in one layer. The result behaves like an element: the same signs apply to it.</p>
<div class="table"><table class="mix"><tbody>{mixes}</tbody></table></div></section>

<section><h2>What the mod already has</h2>
<ul>
<li>Basic version (stage 6): five element sigils, column, dispersion, levitation and convergence, inverted signs, strength from the number and size of signs, tilt and stability, empty ring - a shockwave.</li>
<li>Stage 7: mixing elements - two different elements in one ring give a third (the table below). The effects are built from the mod's own projectiles after the element's look: material, color, damage, status.</li>
<li>Stage 8: signs add up - each adds a behavior: pulling, crushing, piercing, crosshair, expansion, stability; turning the signs spins the spell. Every sign beyond four lowers precision a little.</li>
<li>Next: layer rings and satellite seals (stage 9), linked seals (stage 10), repetition and decorative sigils (stage 11).</li>
<li>The old signs (triangle, wave, lightning, ice, spiral, arrow, two lines, dots) and the stage 5 marks are gone: lightning and ice come back through convergence and mixes.</li>
</ul></section>

<section><h2>Sources</h2>
<ul>
<li><a href="https://github.com/ytnrvdf/wha-spell-simulator">wha-spell-simulator</a> (MIT, © 2026 Nervadof) - sign templates, descriptions of column, levitation and convergence, example seals.</li>
<li><a href="https://witch-hat-atelier.fandom.com/wiki/Signs_Explained">Witch Hat Atelier Wiki: Signs Explained</a>, <a href="https://witch-hat-atelier.fandom.com/wiki/Magic">Magic</a> - how a seal works: element sigil, signs, ring.</li>
<li><a href="https://witchhatatelierspellmaker.com/">Witch Hat Atelier Spell Maker</a> - dispersion and repetition, light as a kind of fire.</li>
<li><a href="https://hub-anime.com/anime/witch-hat-atelier-sistema-magia-explicado/">Hub Anime: sistema de magia</a> - symmetry and nested rings.</li>
</ul></section>
</main>
</body>
</html>
"""
    open(OUT, "w", encoding="utf-8", newline="\n").write(page)
    print("written", OUT)


main()
