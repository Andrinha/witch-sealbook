# Flame Shot CPU performance, 2026-10-01

The optimized implementation reduces complete mock Flame Shot update time by
2.0-2.5x without JIT, and 1.5-2.0x with JIT. These are Lua/API-stub timings,
not measurements of Noita's frame time or FPS. Native terrain calls, particles,
rendering, save/component copies and GPU work must be measured in game.

Baseline: `47dd32b057335745cfb6f0aeb6b307d3454676bc`,
`files/effects/fluid.lua`, copied before editing to
`tests/output/fluid_baseline.lua`. Python 3.14 and Lupa LuaJIT 2.1 on this
workspace's Windows machine. Each scenario runs 60 frames; the table shows
medians of five alternating before/after runs, including the first update.
Shots use the existing staggered scheduling in both versions.

These measurements precede the continuous emissive gas renderer. The current
renderer keeps the solver and 512-sample budget, replacing scattered pixels
with overlapping RGBA kernels. A subsequent paired interpreter comparison
against `b7b3628` measures 2.51→2.22 ms for one shot, 7.54→6.52 ms for three,
and 3.16→2.92 ms at the wall over the same 60 frames. The engine-ray budget
regression still passes. See [the current measurements](fluid-fire-presets.md)
for the sprite-area clearance tradeoff and other spells. The subsequent dark-grid
fix uses filtered, area-normalized sprite pairs; its current paired timings
against `292063a` are documented there separately.

| Scenario | Before, ms/frame | After, ms/frame | Speedup | Before p95, ms | After p95, ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 shot, interpreter | 6.465 | 2.599 | 2.49x | 14.76 | 4.67 |
| 3 shots, interpreter | 19.542 | 7.742 | 2.52x | 29.34 | 10.11 |
| 1 shot at wall, interpreter | 6.480 | 3.213 | 2.02x | 16.15 | 6.33 |
| 6 shots, interpreter | 38.991 | 15.350 | 2.54x | 49.21 | 22.14 |
| 1 shot, JIT | 1.294 | 0.760 | 1.70x | 2.79 | 1.18 |
| 3 shots, JIT | 3.155 | 1.904 | 1.66x | 4.84 | 2.93 |
| 1 shot at wall, JIT | 1.389 | 0.935 | 1.48x | 3.38 | 1.88 |
| 6 shots, JIT | 6.529 | 3.209 | 2.03x | 8.71 | 4.32 |

For three shots without JIT, solver time drops from 17.135 to 5.915 ms per
frame, and snapshot packing from 0.693 to 0.291 ms. With JIT, those stages
drop from 1.732 to 0.722 ms and 0.572 to 0.200 ms respectively. Wall masking
still costs about the same; this is not an optimization of native terrain.

The isolated, warmed 60-tick kernel benchmark measures 0.809 -> 0.408 ms per
solver tick with JIT, and 8.312 -> 3.776 ms without JIT. Allocation over
60 ticks with GC stopped stays around 290 KiB in both versions; this kernel
benchmark excludes snapshots, entities and drawing.

The 48x28 grid, solver update frequency, Jacobi pressure operator and
24 iterations per projection remain the same. The fire preset permits a
two-cell characteristic displacement per substep, replacing the old 0.65-cell
bound. This reduces repeated complete force/pressure/advection passes.
New general-purpose models retain 0.65 unless configured otherwise.

Semi-Lagrangian transport with a limited MacCormack correction supports
testing a larger timestep; see
[Selle et al., An Unconditionally Stable MacCormack Method](https://andyselle.com/papers/7/).
The tradeoff is different numerical trajectories and local peak brightness.
At the sampled 6/18/36/60 frames, total heat differs from the old bound by less
than 2% and the heat centroid by less than one grid cell. The existing
visible-vortex, monotonic-fading, terrain, damage and reload regressions pass.
This is a visual fire preset, not a validation of arbitrary fluid parameters.

Snapshot version 3 stores scaled integers with one numeric `table.concat`,
replacing 1,344 floating-point formatting calls. Absolute roundtrip error
within fire caps is <= 4.55e-13 for density and <= 1.46e-11 for velocity.
Live fields are not rounded. Old version 1/2 saves remain readable.
Open-air interpolation skips redundant collision-donor checks, direct donor
index arithmetic avoids repeated min calls, and maximum-speed selection uses
one square root per tick. Details and configuration are in
[fluid-solver.md](fluid-solver.md).

Validation: all 131 tests from `python -m unittest discover -s tests -p
'test_*.py'` pass. The 38 fluid tests also pass with JIT disabled, including
the new snapshot precision/truncation tests and the comparison against the
old displacement bound. `git diff --check` passes. The existing test helpers
emit unclosed-file ResourceWarnings; they do not fail the tests.

Reproduce the comparison from the mod directory, with no other benchmark or
test process running:

```powershell
python tests/bench_flame_shot.py --compare tests/output/fluid_baseline.lua --interpreter --output tests/output/fluid_comparison_interpreter.json
python tests/bench_flame_shot.py --compare tests/output/fluid_baseline.lua --output tests/output/fluid_comparison_jit.json
python tests/bench_flame_shot.py --solver --source tests/output/fluid_baseline.lua
python tests/bench_flame_shot.py --solver
```

To reconstruct the baseline in a fresh checkout:

```powershell
python -c "from pathlib import Path; import subprocess; p=Path('tests/output/fluid_baseline.lua'); p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(subprocess.check_output(['git','show','47dd32b:files/effects/fluid.lua']))"
```

For the actual game, compare the same single-cast and burst scene with the
Performance profiler enabled. Check `Effects Lua`, `save`, `pressure`,
`velocity`, `density`, `sub` and frame p95/max. The supplied screenshot's
7 ms save stage includes native component storage, which the stub benchmark
does not reproduce. A reduction in that stage or in total game frame time
must not be inferred by multiplying the offline numbers.

## Between-tick terrain work, 2026-10-02

Solver ticks still take the full terrain mask. On the frames between them a
field beside terrain no longer rebuilds it:

- a moving window (`F.sweep`) casts one real ray per hot cell along that
  frame's displacement, so gas is never carried across terrain;
- a resting window (`F.settle`) probes its visible cells and rebuilds the mask
  only when one of them is covered;
- open air and restored fields keep the full mask (a few row scans).

`F.mask` scans `p.lead` ahead so spans stay valid for the moved window. The
renderer reuses sprite footprints until the next mask and thins crowded fields
on a fixed cell lattice instead of counting candidates in scan order, which
rebuilt most sprites every tick.

Engine calls per frame in the uneven test cave (`tests/render_fluid_cave.py`
terrain), one cast, mock world:

| Spell | Rays before | Rays after |
| --- | ---: | ---: |
| Flame Shot | 1167 | 853 |
| Ring of Fire | 2526 | 1386 |
| Flame Burst (with its rings) | 2569 | 1481 |
| Pyreball | 384 | 146 |

Open-air ray counts are unchanged. Ring/Burst sprite component writes in open
air drop by about a fifth (838 -> 654 and 663 -> 533 per frame). These are
call counts, not game frame times; the in-game profiler has not been run on
this version.
