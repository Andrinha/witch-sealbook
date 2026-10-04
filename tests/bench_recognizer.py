"""Speed of seal recognition: parses a fixed set of varied synthetic seals and reports the time per seal.
The results (every symbol's key, inversion and turn, and the spell) can be saved and compared, to prove
that a speed-up changes nothing.

Usage (from the mod folder):
    python tests/bench_recognizer.py                 # time it
    python tests/bench_recognizer.py --save base.json
    python tests/bench_recognizer.py --compare base.json
"""
import argparse
import json
import math
import os
import random
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_tests as t  # noqa: E402

SEALS = 60


def make_seals(lua):
    random.seed(12345)
    sigils = sorted(set(t.element_sigils(lua).values()))
    variants = t.sign_variants(lua)
    seals = []
    for i in range(SEALS):
        center = [random.choice(sigils)] if i % 3 else random.sample(sigils, 2)
        n = random.choice([0, 2, 2, 3, 4, 4, 6])
        key, inverted = random.choice(variants)
        other = random.choice(variants)
        turn = random.choice([0, 0, 0, 30, -45])
        base = random.uniform(0, 360)
        signs = [((key, inverted) if j % 2 == 0 else other) for j in range(n)]
        seals.append(t.seal(lua, center, [(k, base + 360 * j / n, inv, turn) for j, (k, inv) in enumerate(signs)]))
    return seals


def signature(lua, strokes):
    res = lua.eval("parse_seal")(t.lua_strokes(lua, strokes))
    tree, err = (res[0], res[1]) if isinstance(res, tuple) else (res, None)
    if not tree:
        return err
    symbols = sorted(f"{s['kind']}:{s['key']}{'~' if s['inverted'] else ''}@{round(math.degrees(s['turn'] or 0))}:{s['score']:.4f}"
                     for s in tree["symbols"].values())
    return " ".join(symbols)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--save")
    ap.add_argument("--compare")
    args = ap.parse_args()
    lua = t.load_mod()
    seals = make_seals(lua)
    parse = lua.eval("parse_seal")
    parse(t.lua_strokes(lua, seals[0]))  # build the template sets
    started = time.perf_counter()
    for strokes in seals:
        parse(t.lua_strokes(lua, strokes))
    ms = (time.perf_counter() - started) / len(seals) * 1000
    symbols = sum(len(s) for s in seals)
    print(f"{len(seals)} seals ({symbols} strokes): {ms:.1f} ms per seal")
    sigs = [signature(lua, s) for s in seals]
    if args.save:
        json.dump(sigs, open(args.save, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    if args.compare:
        base = json.load(open(args.compare, encoding="utf-8"))
        diff = [(i, a, b) for i, (a, b) in enumerate(zip(base, sigs)) if a != b]
        print(f"same results: {len(sigs) - len(diff)}/{len(sigs)}")
        # what was recognized, without the scores (an approximate method never gets them exactly)
        meaning = lambda sig: " ".join(sorted(x.split("@")[0] for x in sig.split())) if "@" in sig else sig
        turns = lambda sig: sorted(int(x.split("@")[1].split(":")[0]) for x in sig.split()) if "@" in sig else []
        same_meaning = sum(meaning(a) == meaning(b) for a, b in zip(base, sigs))
        same_turns = sum(turns(a) == turns(b) for a, b in zip(base, sigs))
        print(f"same symbols recognized: {same_meaning}/{len(sigs)}, same turns: {same_turns}/{len(sigs)}")
        for i, a, b in diff[:10]:
            print(f"  #{i}\n    was {a}\n    now {b}")


if __name__ == "__main__":
    main()
