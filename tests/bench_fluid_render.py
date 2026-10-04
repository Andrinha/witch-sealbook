"""Alternate the committed sprite renderer and the working gas renderer.

python tests/bench_fluid_render.py --interpreter --repeats 3
Includes Lua/mock calls; excludes the game's sprite/GPU and native-fire costs.
Comparisons use the same active window (40 frames for Ring, 60 for the others).
Full new lifetimes are also measured (60 Ring, 104 Burst).
"""
import argparse
import json
from pathlib import Path
import statistics
import subprocess

import bench_flame_shot as Bench

ROOT = Path(__file__).resolve().parents[1]
FILES = ("files/effects/fluid_draw.lua", "files/effects/flame_shot.lua", "files/effects/flame_fields.lua", "files/effects/flame.lua", "files/manifest.lua")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", default="292063a")
    parser.add_argument("--draw-baseline", type=Path, help="Compare this saved renderer with current code, keeping all physics identical")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--interpreter", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error("--repeats must be positive")
    baseline = {}
    for path in (() if args.draw_baseline else FILES):
        source = subprocess.run(["git", "show", f"{args.baseline}:{path}"], cwd=ROOT,
                                text=True, encoding="utf-8", capture_output=True)
        if source.returncode and path == "files/effects/fluid_draw.lua":
            continue  # Older pixel renderers did not use this module.
        source.check_returncode()
        baseline[path] = source.stdout
    if args.draw_baseline:
        baseline[FILES[0]] = args.draw_baseline.read_text(encoding="utf-8")
    create_runtime = Bench.runtime

    def run(spell, frames, shots=1, barrier=None, before=False):
        def runtime():
            lua = create_runtime()
            for path in FILES:
                lua.execute(f'dofile_once("mods/witch_notebook/{path}")')
                if before and path in baseline:
                    lua.execute(baseline[path])
            return lua

        Bench.runtime = runtime
        try:
            return Bench.benchmark(shots, barrier, frames, interpreter=args.interpreter, spell=spell)
        finally:
            Bench.runtime = create_runtime

    results = []
    for spell, frames, wall in (("flame_shot", 60, 145), ("ring_of_fire", 40, 25),
                               ("flame_burst", 60, 145), ("forbidden_flames", 60, 142), ("pyreball", 60, 58)):
        for shots, barrier in ((1, None), (3, None), (1, wall)):
            rows = {"before": [], "after": []}
            for repeat in range(args.repeats):
                order = ("before", "after") if repeat % 2 == 0 else ("after", "before")
                for name in order:
                    rows[name].append(run(spell, frames, shots, barrier, before=name == "before"))
            result = {"spell": spell, "frames": frames, "shots": shots, "wall": barrier,
                      "baseline": str(args.draw_baseline) if args.draw_baseline else args.baseline,
                      "repeats": args.repeats, "interpreter": args.interpreter}
            for name, samples in rows.items():
                result[name] = {"mock_ms_per_frame": statistics.median(r["mock_ms_per_frame"] for r in samples),
                                "calls_per_frame": samples[0]["calls_per_frame"],
                                "stage_ms_per_frame": {stage: statistics.median(r["stage_ms_per_frame"][stage] for r in samples)
                                                       for stage in samples[0]["stage_ms_per_frame"]}}
            results.append(result)
            print(f'{spell}, {shots}, wall={barrier}: {result["before"]["mock_ms_per_frame"]:.3f} -> {result["after"]["mock_ms_per_frame"]:.3f} ms', flush=True)
    full = []
    for spell, frames, wall in (("ring_of_fire", 60, 25), ("flame_burst", 104, 145)):
        for shots, barrier in ((1, None), (3, None), (1, wall)):
            samples = [run(spell, frames, shots, barrier) for _ in range(args.repeats)]
            full.append({"spell": spell, "frames": frames, "shots": shots, "wall": barrier,
                         "mock_ms_per_frame": statistics.median(r["mock_ms_per_frame"] for r in samples)})
            print(f'Full {spell}, {shots}, wall={barrier}: {full[-1]["mock_ms_per_frame"]:.3f} ms', flush=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({"comparison": results, "full_new_lifetimes": full}, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
