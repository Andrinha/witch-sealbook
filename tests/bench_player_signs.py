"""How the signs read drawn as players draw them (tests/player_signs.py): for every sign and every way it is drawn - the
wiki's picture, the book's legend, the legend before it was redrawn - seals of a fire sigil with two of the sign facing the
middle; how many cast with both read right, and what the others were read as.

Usage (from the mod folder):
    python tests/bench_player_signs.py                       # every sign, every drawing (a few minutes, 8 processes)
    python tests/bench_player_signs.py gathering refuse -n 80
    python tests/bench_player_signs.py --variants wiki --inverted -j 12
"""
import argparse
import os
import sys
import time
import zlib
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import player_signs as ps  # noqa: E402

_lua = None


def _work(task):
    global _lua
    key, variant, n, count, inverted = task
    if _lua is None:
        _lua = ps.fx.load_mod()
        ps.add_book(_lua)
    seed = 1000 + zlib.crc32((key + variant).encode()) % 1000
    return task, ps.trial(_lua, key, variant, n, seed, count=count, inverted=inverted)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("keys", nargs="*")
    ap.add_argument("-n", type=int, default=40, help="seals per sign and drawing")
    ap.add_argument("--count", type=int, default=2, help="signs in a seal")
    ap.add_argument("--variants", default="", help="only these drawings (wiki,book,old,...)")
    ap.add_argument("--inverted", action="store_true", help="also turned around, where that means something else")
    ap.add_argument("-j", type=int, default=8, help="processes")
    args = ap.parse_args()
    lua = ps.fx.load_mod()
    ps.add_book(lua)
    keys = args.keys or list(lua.eval("DICTIONARY_SIGN_ORDER").values())
    want = set(args.variants.split(",")) if args.variants else None
    tasks = [(key, variant, args.n, args.count, inverted) for key in keys for variant in ps.SHAPES[key]
             if not want or variant in want
             for inverted in ([False, True] if args.inverted and ps.fx.invertible(lua, key) else [False])]
    started, total = time.perf_counter(), 0
    with Pool(min(args.j, len(tasks))) as pool:
        for (key, variant, n, _, inverted), (right, read_as, failed) in pool.imap(_work, tasks):
            name = key + ("~" if inverted else "")
            other = {k: v for k, v in read_as.most_common(5) if k != name}
            print(f"  {name:12s} {variant:6s} {right:3d}/{n}  {other or ''}  {dict(failed) if failed else ''}", flush=True)
            total += right
    print(f"  total {total}/{args.n * len(tasks)} ({100 * total / max(1, args.n * len(tasks)):.0f}%), {time.perf_counter() - started:.0f} s")


if __name__ == "__main__":
    main()
