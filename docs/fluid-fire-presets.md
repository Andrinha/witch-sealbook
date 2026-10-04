# Fluid fire presets

`files/effects/flame_fields.lua` integrates four small models of the optimized
`FlameFluid` solver. Spell timing, sounds, damage and impact handling remain in
`flame.lua` and `zone.lua`. Each effect owns its density, velocity, pressure
buffers, terrain cache, snapshot, saved native-emitter children and a visual child.

| Effect | Grid | Jacobi iterations per projection | Solver cadence at 60 FPS | Gas samples/frame (2 sprite layers) | Native sources | Grid-fire supply |
| --- | --- | --- | --- | --- | --- | --- |
| Flame Burst jet | 28 × 18 | 16 | 30 Hz | 256 | 4 | 1 cell/6 frames |
| Opening/impact ring and Ring of Fire | 32 × 32 | 16 | 30 Hz | 512 | 6 | 4 cells/3 frames |
| Forbidden Flames | 20 × 24 | 12 | 15 Hz | 160 | 3 | 1 cell/12 frames |
| Pyreball | 24 × 28 | 12 | 15 Hz | 256 | 4 | 1–4 cells/6 world frames |

The models use midpoint velocity advection, limited MacCormack density
transport, two pressure projections per substep, buoyancy, vorticity confinement
and decay. The accuracy bound is two cells/substep, with up to six substeps,
as in the optimized Flame Shot preset. All terrain/liquid segments still use
the solver's exact-ray fallback where empty-space proofs cannot skip them.

Flame Burst retains its fixed launch axis, 280 px/s travel, opening ring,
impact radius, damage, push and caster attribution. Its projectile is a
fireball: a round Gaussian head two cells behind the tip is heated (70/s,
pulsing ±35%) and pushed forward against a relative wind of 0.36 times the
travel speed, so gas wraps around it into a tail. The tail cools at 3/s and
loses heat to its coldest neighbor at 12/s, which narrows it into a pointed
tongue; an uneven sideways sway at the head makes it waver. Cells are at least
2 px (a 56 × 36 px window). One cosmetic ember leaves the tail every two frames
and falls behind; embers burn nothing. The tip sweeps walls
and liquids every frame, creating the larger blast at the first hit or the
saved target distance. Both of its rings use the same fluid ring preset as
Ring of Fire, with their original smaller/larger radii and expansion timing.
The opening ring remains 22 frames long. The impact ring now lasts 48 frames
(16 expanding, 32 cooling); Ring of Fire lasts 60 (28 expanding, 32 cooling).
The longer cooling phase lets transported gas roll up visibly. It also keeps
the existing bounded native fire supply alive longer.

The ring source injects a Gaussian annulus at the original eased expansion
radius, with outward momentum and uneven seed-dependent inlet heat. At launch,
eight alternating stream-function vortices seed circulation around the ring.
The impulse is 260 px/s for ordinary rings and 320 px/s for the final blast;
velocity components retain the 40 cells/s solver cap. The impulse is applied
once, including when bootstrapping an old save. Its centers never animate.
Vorticity confinement is now 12, with heat/velocity decay 3.5/0.35 per second
(previously 4 and 9/1). Confinement counters the damping of small vortices on
a coarse grid; see [GPU Gems, chapter 38](https://developer.nvidia.com/gpugems/gpugems/part-vi-beyond-triangles/chapter-38-fast-fluid-dynamics-simulation-gpu).
The velocity field transports the inlet's hot sheets into curls.
Injection ends after expansion; the remaining gas rises, advects and cools.
The original one-hit expansion sweep additionally requires density at the
victim and an unobstructed segment from the center. Fire/blast damage type,
power and push are preserved. Native fire can continue interacting with the
world while residual hot gas remains.

Forbidden Flames gains a small violet plume from a persistent Gaussian inlet.
Buoyancy and an asymmetric inlet let its vorticity roll up. Its original
duration, violet light, crackle, 14 px damage search radius, 20-frame damage
cadence and 0.15 fire damage remain. Scripted damage now requires hot gas and
a clear segment to the victim. Water or terrain suppresses emission and
damage; the magical source survives for its normal duration and resumes when
clear. Its resistance to extinguishing and violet color remain the
mod's interpretation of the wiki's small forbidden flame.

Pyreball shares that persistent inlet and gas physics, with an orange palette
and two world pixels per cell. Its Gaussian width scales with seal radius;
bounded power scales heat injection and ignition supply. The source remains
fixed at its original location and retains warm light and torch crackle.
Material fire supplies ordinary burning/damage rather than a scripted radius
attack. Masks suppress the plume in water or terrain and allow it to resume.
Its four native sources emit at most 120 moving particles per second; grid
ignition remains capped at 40 cells per second at 60 FPS. The world-frame
ignition cadence and saved `fluid_born` survive lifetime renewal, preserving
the field, simulation clock, pressure buffers and children. Recasting with
changed size/power adjusts the inlet without resizing/resetting the field.
Older saved `witch_pyreball_plume` children are removed when initializing the
new pool, preventing duplicate emission.

`fluid_draw.lua` reconstructs continuous gas with overlapping RGBA sprites.
Flame Shot uses this renderer too. One `witch_fluid_fire_visual` child owns a
bounded, reusable pool of `SpriteComponent` pairs. Each sampled cell has a
translucent colored body behind the world grid and a weak additive glow in front.
Both use native emissive rendering and `smooth_filtering=true`. Positions and
intensity come from live density; there is no independently animated silhouette.
The eight
temperature/intensity bands and eight diameters (4–48 pixels), in orange and
violet, are generated by `tools/make_fluid_flame_sprites.py`. The 128 tiny PNGs
total about 47 KB and need no runtime image editing. At most twice the sample
budget in components belong to the one visual child; there are no per-frame
entity/component allocations once the pool has reached the required capacity.

The previous one-frame sprite API used pixel-art filtering and unnormalized
alpha overlap, making the cell lattice conspicuous when magnified. Wider kernels
(3.4 cell widths times the square root of the sampling stride), linear filtering
and area normalization smooth the reconstructed body. Special scale gives the
selected PNG the exact requested world diameter. Kernel opacity is proportional
to represented cell area divided by the truncated Gaussian's integrated area.
Body gain is 1.4, glow gain 0.12. This keeps brightness consistent across sizes
and budgets; pure additive reconstruction overexposed the hot sheets on sky.
The separate glow only adds light and cannot darken hotter gas underneath it.
Component changes and texture refreshes are cached, and translating a field
moves its visual child instead of rewriting every cell offset.

Fixed draw budgets sample the whole hot footprint. Ring rendering suppresses
gas below 0.3 heat units so cool interior dots do not hide the rolled sheets.
Invisible ink and the ring's cooling opacity dim both layers. A sprite's entire
rectangle must be proved empty this frame. Near walls/liquids, independent X/Y
scales keep the kernel long along a free wall edge while compressing its blocked
axis. The bounded rectangle search tests both extensions separately and chooses
one proved rectangle; combining independent maxima could cover a corner.
The proof already guards pixel rows and wall endpoints, so no second margin
excludes the last free row. Open air reuses its existing window proof without
scanning beyond the packet. This preserves the engine-ray budget.

Opacity uses the original kernel area, rather than compensating for its smaller
collision-clipped area. Removed visible gas cannot become a bright bead. Kernels
too small to overlap neighboring samples even along their longer axis fade out;
fallback collision-aware pixels are also dimmed in proportion to their tiny
visible area. Density, velocity, native fire supply and damage are unchanged.
The profiler's existing `pixels` column counts logical gas samples/fallback
pixels, with two native sprite layers per gas sample.
Each native
source emits at most one moving `FIRE` particle every two frames, with a zero
birth radius to keep births within the sampled fluid cell. Native fire obeys
Noita's own particle and material physics; it is separate from the gas renderer.

Terrain masks refresh every game frame, including between solver updates.
Inlets clip against source-to-cell wall/liquid rays. Moving burst windows sweep
their displacement; a translated stationary source (Mimicry) also sweeps gas
from its previous origin. Native fire, cosmetic pixels and damage all use the
masked field. No heat is supplied to cells across a thin wall from an inlet.

New effects alternate global solver slots; the persistent presets distribute them
across four slots. All fields appear on their first frame. A saved `fluid_phase`
keeps cadence stable across reload. Version-three snapshots save fields only
when they change. Separate `fluid_head`, `fluid_cell`, `fluid_ox` and `fluid_oy`
variables preserve the collision sweep and scale between ticks. Restoring a
field reuses its tagged emitters and visual components. Old ring
saves without a field get one bootstrap injection, including in their fading
tail. Expiry destroys the parent and its children; stale Lua states are removed
periodically. Background Flame Shot preparation pauses while any of these
fluid effects is alive.

## Filtering measurements (before wall adaptation)

Paired comparisons against `292063a`, three runs with alternating order and
identical active windows: 40 frames for Ring, 60 for other spells. Startup is
included; both API paths validate each texture once. These measure Lua plus the
mock API, excluding native renderer/GPU, material fire and Noita's real API cost.

| One source, open air | Before / after, interpreter | Before / after, JIT |
| --- | ---: | ---: |
| Flame Shot | 2.36 / 2.47 ms | 0.66 / 0.80 ms |
| Ring of Fire | 1.51 / 1.77 ms | 0.52 / 0.87 ms |
| Flame Burst | 2.01 / 2.18 ms | 0.60 / 0.81 ms |
| Forbidden Flames | 0.36 / 0.39 ms | 0.24 / 0.30 ms |
| Pyreball | 0.47 / 0.50 ms | 0.26 / 0.31 ms |

The extra native layer and cached component updates cost more mock CPU time
than the transient sprite API. The engine-ray and component-call budget
regressions still pass. Those interpreter means were 7.24 ms for three
Shots and 3.17 ms for one beside the wall, compared with 6.91 and 3.11 ms at
`292063a` in the same paired run. Two layers can also increase native GPU work;
these results do not measure game FPS.

```powershell
python tests/bench_fluid_render.py --interpreter --repeats 3 --output tests/output/fluid_seams_interpreter.json
python tests/bench_fluid_render.py --repeats 3 --output tests/output/fluid_seams_jit.json
python tests/render_fluid_seams.py
```

## Wall-edge measurements

Three alternating, paired runs with the previous working renderer saved to
`tests/output/fluid_wall_baseline.lua`. Only the renderer changes; all physics,
sources, timings and lifetimes are identical. Frame windows and wall positions
match the preceding comparison. These are interpreter/mock CPU timings and do
not include native rendering, material fire or GPU work.

| One source | Before / after, open air | Before / after, beside wall |
| --- | ---: | ---: |
| Flame Shot | 2.42 / 2.45 ms | 3.07 / 3.13 ms |
| Ring of Fire | 1.71 / 1.71 ms | 2.56 / 2.63 ms |
| Flame Burst | 2.12 / 2.10 ms | 2.76 / 2.83 ms |
| Forbidden Flames | 0.38 / 0.39 ms | 0.70 / 0.74 ms |
| Pyreball | 0.48 / 0.48 ms | 0.81 / 0.85 ms |

```powershell
python tests/bench_fluid_render.py --draw-baseline tests/output/fluid_wall_baseline.lua --interpreter --repeats 3 --output tests/output/fluid_wall_interpreter.json
python tests/render_fluid_walls.py --baseline tests/output/fluid_wall_baseline.lua
```

The saved baseline is a local comparison artifact from before this patch.
Without `--baseline`, the wall preview uses the older renderer at `292063a`.
The preview draws actual sprite properties and fallback particle calls, with
independent X/Y scaling and no extra bloom. It shows a uniformly hot strip and
Ring of Fire between a ceiling and floor; native material fire is omitted.

## Previous renderer measurements (commit `292063a`)

These historical measurements were made at `292063a`.

Three sequential runs per scenario, medians of mean frame times. Ring of Fire
runs for 60 frames, Burst for 104 to cover its longer blast, the other spells
for 60. Enemies are removed. Wall
positions are x=145 for Burst, x=25 for Ring, and x=142 beside the violet
source at x=150. Pyreball runs for 60 frames, with a wall at x=58 and origins
eight pixels apart for multiple casts to avoid renewal. Startup is included. These measure Lua plus the mock API,
excluding Noita's rendering, GPU, native fire and material simulation. Texture
paths are validated once in the mock, matching the engine's asset caching.

| Spell | One, JIT | One, interpreter | Three, interpreter | One near wall, interpreter |
| --- | --- | --- | --- | --- |
| Flame Burst (jet and rings) | 0.46 ms | 1.69 ms | 5.12 ms | 1.83 ms |
| Ring of Fire | 0.43 ms | 1.48 ms | 4.42 ms | 2.31 ms |
| Forbidden Flames | 0.27 ms | 0.34 ms | 1.02 ms | 0.67 ms |
| Pyreball | 0.23 ms | 0.45 ms | 1.32 ms | 0.77 ms |

The paired comparison against `b7b3628` uses equal active windows, alternating
before/after order over three runs: 40 frames for Ring, 60 for the others.
It preloads both versions' Lua handlers outside the timed interval.

| One source, open air, interpreter | Committed pixel renderer | Continuous gas renderer |
| --- | ---: | ---: |
| Flame Shot | 2.51 ms | 2.22 ms |
| Ring of Fire | 1.85 ms | 1.47 ms |
| Flame Burst | 2.24 ms | 1.88 ms |
| Forbidden Flames | 0.45 ms | 0.34 ms |
| Pyreball | 0.62 ms | 0.45 ms |

Interpreter timings improve in all measured one/three/wall cases. The JIT wall
case for Ring costs more in the paired 40-frame window, 1.41→1.66 ms, due to
the full sprite-area clearance work; other paired JIT scenarios improve.
These host timings vary and do not predict the new sprites' GPU cost.

Cold starts and simultaneous creation of Burst's child rings can still exceed
steady update cost. These figures do not establish a 16 ms full-game frame
budget. The in-game profiler covers the new models, including solver stages,
sources, particles, snapshot size, restores and Burst's head ray.

```powershell
python tests/test_flame_fields.py
python tests/bench_flame_shot.py --spell flame_burst --interpreter
python tests/bench_flame_shot.py --spell ring_of_fire --interpreter
python tests/bench_flame_shot.py --spell forbidden_flames --interpreter
python tests/bench_flame_shot.py --spell pyreball --interpreter
python tests/bench_flame_shot.py --spell ring_of_fire --burst --interpreter
python tests/render_fire_spells.py
python tests/test_fluid_draw.py
python tests/render_ring_turbulence.py
python tests/render_fluid_seams.py
python tests/bench_fluid_render.py --baseline b7b3628 --interpreter --repeats 3 --output tests/output/fluid_render_interpreter.json
python tests/bench_fluid_render.py --baseline b7b3628 --repeats 3 --output tests/output/fluid_render_jit.json
```

The 18 shared regressions cover finite evolving fields, cooling, independent
buffers, cadence distribution, particle/ignition budgets, thin walls, liquid
arrival between ticks, suppression/resumption, density-gated damage, liquid
impact, both Burst rings, reload/pool reuse, moving-origin sweeps, old saves,
profiling equivalence, Pyreball migration/size renewal and expiry. They also
pass with JIT disabled. A no-flow control with the same source/seed/decay verifies
that transport changes the actual density, rather than merely showing inlet
texture. At seed 23, radius/grow/age 55/28/34, normalized density difference
versus this control rises from 6.9% to 79.1%; for blast 80/16/24 it rises from
3.2% to 66.7%. Heat-weighted absolute curl rises 0.49→7.35 and 0.22→6.79 s⁻¹.
These are two deterministic regression scenes, not a general fluid validation.
Eleven renderer regressions check continuous sheets without pinholes, emissive
linear filtering, clearance for both layers, new water, dimming, additive glow
independent of draw order, normalized energy across sizes/budgets, allocation
reuse and hiding saved sprites when loading a submerged field. Wall regressions
check continuous floor/ceiling/vertical strips, no clipping-induced brightness
boost, unchanged gas, diagonal rectangle corners and subdued fallback pixels.
The fire spell suite additionally checks orange sprite colors,
native births in hot gas, Pyreball growth/strengthening, repeated renewal,
unchanged gas/cadence and reload after renewal. The offline
sprite/particle previews approximate glow and cannot reproduce native Noita
fire or material damage. `render_ring_turbulence.py` compares the committed
renderer/source with the new version at equal ages, using the new lifetime
in both previews, and exports the no-flow-control measurements.
Check open air, walls, water, wood/oil and concurrent casts in the game.

`render_fluid_seams.py` compares `292063a` with the working renderer on bright
sky using identical density fields and no extra bloom. It captures actual
component properties, scale and layer order. These previews approximate native
blending and do not execute Noita's shaders or material-fire simulation.

See [the reusable solver API](fluid-solver.md) and
[the Flame Shot performance measurements](fluid-performance.md).
