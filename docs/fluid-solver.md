# Reusing the fluid solver

`files/effects/fluid.lua` contains the numerical solver and terrain queries;
`files/effects/flame_shot.lua` supplies Flame Shot entities, particles, damage,
audio, lighting and lifetime. `files/effects/flame_fields.lua` supplies the
[Burst, Ring, violet and Pyreball presets](fluid-fire-presets.md). The solver itself creates no entities, particles,
damage or sound. Its default `FlameFluid` model preserves the fire preset.

Create an additional model once when loading a spell module. Models own grid
dimensions, neighbor indices and tuning. Every state created with `model.new`
owns its fields, collision cache, pressure stencil and scratch arrays. Multiple
states can share a model and update in any order. Independent models copy their
settings, so changing one does not change Flame Shot or another spell.

```lua
dofile_once( "mods/witch_notebook/files/effects/fluid.lua" )

local smoke = FlameFluid.create({
    width = 32, height = 24, iterations = 16, cell_size = 3,
    tuning = {
        front_cells = 8, drift = 0, heat_decay = 0.3,
        buoyancy = 2, vorticity = 2, max_velocity = 40,
    },
})

-- An example source for smoke rather than the default fire launch. The
-- callback runs once per solver step, after refreshing the terrain mask.
smoke.source = function( state, frame, age, dt )
    if age < 60 then
        smoke.splat( state, 16, 12, 2, 3 * dt, 0, -8 * dt )
    end
end

local frame = {
    ox = 100, oy = -40, dx = 1, dy = 0, head = 0,
    speed = 0, frame_velocity = 0,
}
local state = smoke.new( frame, 7 )
smoke.step( state, frame, 0, 1 / 60 )

local x, y = smoke.world( state, frame, 16, 12 )
local density = smoke.density( state, frame, x, y )
local vx, vy = smoke.flow( state, frame, 16, 12 )
-- The spell chooses its own rendering, material interactions and damage.

local saved = smoke.pack( state )
state = smoke.restore( frame, saved, 7 )
```

Keep `frame.dx, frame.dy` normalized. `ox, oy` describe a world-space origin;
`head` is displacement along this direction. Grid x runs along that direction,
grid y across it. Keep the origin and direction fixed for a state's lifetime;
move its window with `head` so the solver can sweep that motion against terrain.
Velocities are cells/second, `dt` is seconds, and `age` is game
frames. `frame_velocity` is the actual world-space motion in pixels/second;
`flow` subtracts the configured moving-window drift. `cell_size` is the world
size of a grid cell. Without it, `new` derives a cell size from `frame.length`;
`frame.cell` can override the model's cell size for one state.

| API | Purpose |
| --- | --- |
| `FlameFluid.create(options)` | Independent model: `width`, `height`, `iterations`, `cell_size`, `max_courant`, `tuning`, optional `source` callback. |
| `model.new(frame, seed, prepared)` | Allocate an independent state with fields `d`, `u`, `v`. An optional inactive numerical state transfers its buffers and is reset; it must belong to this model. |
| `model.step(state, frame, age, dt, source, meter)` | Refresh terrain, inject, project, advect and decay. An optional callback overrides the model's source for this step. An optional meter implements `begin()`, `finish(name, started)` and `count(name, amount)`; the solver has no dependency on the in-game profiler. |
| `model.splat(state, x, y, radius, density, u, v)` | Add a Gaussian density/velocity impulse in grid coordinates; skip solid cells and clamp to configured caps. Values are increments, so multiply rates by `dt`. |
| `model.mask(state, frame)` | Refresh collision data and erase gas swept into obstacles between solver ticks. Returns whether fields changed. |
| `model.project(state)` | Remove velocity divergence using the pressure solve. |
| `model.world(state, frame, x, y)` | Convert grid coordinates into world coordinates. |
| `model.density(state, frame, wx, wy)` | Sample density at a world position. |
| `model.heat(state, x, y)` | Sample the same scalar density field in grid coordinates. |
| `model.flow(state, frame, x, y)` | Sample velocity in grid coordinates. |
| `model.blocked(state, x1, y1, x2, y2)` | Query a world segment using the current collision cache; call `mask` or `step` first. |
| `model.pack(state)` / `model.restore(frame, text, seed, prepared)` | Serialize/restore density, velocity, seed, dimensions and last masked window position. Restore optionally uses a prepared numerical state. |

Supply a custom source to replace the fire nozzle completely. For an unforced
field, use a source that does nothing or set `tuning.emit_frames = 0`. General
settings include density/velocity decay, vorticity and its decay, buoyancy,
density cap, velocity cap and moving-window drift. Fire preset settings control
the nozzle, initial velocity impulse and the counter-rotating front pair. The
default source expects `frame.r`, plus the motion/origin values shown above.

Keep each state with the model that created it. Refresh masks through `mask` or
`step`, rather than editing `state.solid`, so cached pressure boundaries remain
valid. Grid dimensions and cell size stay fixed during a state's lifetime.
Restore a snapshot with the same model tuning, source and cell size; these are
spell configuration rather than serialized field data. For moving effects that
save less often than `mask` runs, also persist `state.mask_head` as a separate
float and restore it before the next step, as Flame Shot does with `fluid_head`.

Scratch buffers and cached stencils are reconstructed after reload. After their
first use, solver passes recycle storage and fully initialize outputs; stale
pressure and blocked advection cannot retain data from a previous step.

Density advection restricts its work to the nonzero field's bounding rectangle,
expanded by the current velocity extrema, timestep and bilinear donor support.
RK2 samples lie within those extrema, so the excluded cells remain exactly
zero. Empty donor/destination pairs skip collision queries. Velocity
components share their interpolation donors, and integer characteristic
origins read their grid cell directly. Pressure iteration uses cached runs of
ordinary fluid cells plus explicit boundary cells; open-edge ghosts and
terrain reflection preserve the original Jacobi operator and iteration count.

Each mask refresh scans horizontal world-pixel rows in both directions where
an obstacle is found. Clear prefixes/suffixes prove empty segment rectangles
without more engine calls. Rectangles include a one-pixel guard; uncertain
regions still use guarded tiles and exact rays. Proofs are rebuilt on every
mask, including between solver ticks, to detect liquid and terrain changes.

On player spawn, a preparation entity uses the same `run.lua` shared VM as
live effects. It loads the fire module, runs four small numerical ticks in a
state-local synthetic world, prepares serialization, then loads one disabled
native emitter per frame until twelve are ready. It disables its script when
finished and pauses preparation while any fluid fire effect is active. The first new
shot takes ownership of the prepared numerical state and emitter entities.
Preparation produces no particles, damage, sounds or engine terrain queries;
the first live mask returns to the actual terrain API. A cast before preparation
finishes uses the normal path immediately. Loading a saved game restarts
preparation and can reuse the saved disabled emitters.

Other spells can prepare numerical states through ordinary `new`/`step` calls
and later pass an inactive state to `new` or `restore`; never transfer an
active state or one carrying spell-specific entity ownership. Reset preserves
scratch buffers while clearing fields, seed-dependent state and boundaries.
A state-local `state.raycast` callback can supply a synthetic pixel world for
preparation; it follows the engine's `(x1,y1,x2,y2) -> hit, first_hit_x,
first_hit_y` contract. Reset removes this override. The solver creates no
engine entities; the disabled-emitter pool belongs specifically to Flame Shot.

Run `python tests/test_flame_fluid.py` to check independent models/states,
custom sources, terrain changes, save/reload, the fire preset and allocation
pressure. `python tests/bench_flame_shot.py --solver` reports median kernel time
and allocated memory over five runs with GC stopped during measurement.
`--source path/to/baseline/fluid.lua` measures another implementation. The default
benchmark covers complete mock Flame Shot updates and API-call counts instead.
`--spell flame_burst`, `--spell ring_of_fire`, `--spell forbidden_flames` and `--spell pyreball`
select the additional fire integrations for complete updates or `--burst`.
Ring scenarios cover its 40-frame lifetime; the other scenarios use 60 frames.
Each selected spell has a wall scenario placed beside its actual footprint.
`--source path/to/fluid.lua` also works with that complete effect benchmark.
`--interpreter` works with both complete updates and `--solver`, disabling JIT in the test harness to exercise both execution
modes, without making assumptions about the game's current Lua settings.
`--compare path/to/baseline/fluid.lua` alternates baseline/current complete
updates over five runs per scenario (one, three and six shots, plus a wall).
It reports median mean/p95/maximum timings, individual stages and API counts;
`--repeats` changes the run count. `steady_mock_ms_per_frame` excludes the first
frame, while `mock_ms_per_frame` includes startup. Keep performance runs
sequential so concurrent tests do not distort the comparison.
`--startup` compares a cold first cast with incremental preparation and counts
entity loads performed during the cast.
`python tests/bench_flame_shot.py --burst` compares six shots with synchronized
and staggered solver updates, reporting p95/max mock frame times and the number
of solver ticks per frame. These timings measure the Lua test harness, not game
FPS, native particles, rendering or GPU costs.

Flame Shot stores an age parity in `fluid_phase`, assigning alternating global
frame slots to new shots. Both slots still simulate at 30 Hz; all shots render,
check terrain and apply damage every frame. Opposite-slot shots start with a
half tick so they appear immediately. Launch injection is limited to its actual
remaining duration. Six simultaneous shots therefore run six initial solves,
then three solves per frame, rather than alternating six and zero. Reload
preserves the phase; older saved shots keep their original even-age cadence.
Effect components explicitly use `SHARED_BY_MANY_COMPONENTS` so scheduling,
cached modules and frame counters are shared within the effect script VM.

## CPU update and snapshot cost

The fire model keeps the 48x28 grid, 30 Hz solver cadence, RK2 characteristics,
limited MacCormack density correction and 24 Jacobi iterations per projection.
Its substep displacement bound is now two cells instead of 0.65 cells.
`max_courant` is a model setting; newly created general-purpose models keep
the conservative 0.65 default. Set it explicitly when configuring another
effect. Native tracer integration retains its separate 0.65-cell bound.

[Selle et al., An Unconditionally Stable MacCormack Method](https://andyselle.com/papers/7/)
describe semi-Lagrangian forward/backward transport with limiters, which does
not need an explicit-advection CFL below one for stability. This supports
testing a larger displacement bound here; it does not prove identical
trajectories or stability of every custom force configuration. The fire preset
still caps the substep count at six, checks characteristic segments against
terrain, masks moving windows every frame, and limits heat/glow increases.
The regression compares the faster preset with the old bound at frames
6/18/36/60: total heat differs by less than 2% and the density centroid by less
than one grid cell. Peak density and individual trajectories can change;
the existing visible vortex, fading, reload and wall tests also apply.

Confirmed open-air masks let interpolation skip solid-donor lookups. Donor
indices use direct row arithmetic, math functions use local references, and
the maximum-speed scan takes a single square root after comparing squared
speeds. The terrain path remains active when a mask finds an obstacle.

Snapshots use version 3 integer CSV, built with one numeric `table.concat`
instead of 1,344 floating-point `string.format` calls and per-cell strings.
Two power-of-two scales are stored in the header, so restore does not depend
on current caps. Values are rounded only while saving; live fields remain
double precision. For fire fields within the preset caps, the absolute
roundtrip error is at most 4.55e-13 for density and 1.46e-11 for velocity.
Smaller values can round to zero. Versions 1 and 2 remain readable, including
legacy grid migration. Partial version 3 snapshots retain complete triples
and initialize the missing cells to zero.

The implementation follows the array reuse, local references and allocation
advice in [Roberto Ierusalimschy's Lua Performance Tips](https://www.lua.org/gems/sample.pdf).
The [Lua 5.1 manual](https://www.lua.org/manual/5.1/manual.html#pdf-table.concat)
documents numeric elements in `table.concat`; no native extension is needed.

## In-game profiling

Enable **Options > Mod settings > Witch Notebook > Performance profiler**.
The setting is off by default and updates within 30 frames. Its HUD summarizes
the last 300 game frames: average, p95 and maximum frame intervals and effect
Lua time, plus the worst interval and worst Lua frame with their dominant
stage. A report is printed every 300 frames and retained in the global string
`witch_notebook.perf_report`. Capture a few seconds of idle play, single casts
and a burst of casts at the location where stutters occur, then disable it.

Timers cover parameter reads, restores, movement, terrain masks, injection,
forces, pressure, velocity/density advection, native emitter setup, cosmetic
drawing, damage, snapshots and effect visibility. Counts include solver ticks,
substeps, rays, cosmetic pixels, newly created emitter entities, restores and
snapshot bytes. Lua heap size and net heap drops help identify allocation/GC
patterns; a heap drop is not a measurement of collection duration.
If the sandbox returns no usable heap size, the report displays `heap=n/a`;
zero from an unavailable counter must not be interpreted as absence of GC.
Loading and preparation have their own timed stages. Reports include the
individual stages for the worst Lua frame, ray counts split across mask,
velocity and density work, and reused emitter counts. `First cast` retains
the first new Flame Shot update after profiling is enabled, even after it
leaves the rolling window. Disable/re-enable profiling to start a new capture.

The profiler uses the documented real-world clock and a numeric `Globals`
bridge between the effect VM and the world callback VM. Frame intervals include
work outside our Lua scripts, rendering and frame pacing; a long interval with
little measured effect Lua time does not identify the exact engine/GPU cause.
Clock intervals straddle consecutive world callbacks, so rendering costs may
belong to the preceding update. Pauses and nonconsecutive game frames are
excluded, and a restarted game clears the history. Profiling adds timer and
export overhead; compare behavior with it disabled. It does not change global
GC settings or use native extensions.

The [Realistic Particles Behavior mod](https://steamcommunity.com/sharedfiles/filedetails/?id=2584468574)
uses native particle controls in its author's older published XML sources.
Its [corrected continuation's flamethrower](https://github.com/LucaJakob/realistic_particles_fix/blob/master/files/entities/projectiles/flamethrower.lua)
sets emitter airflow, gravity and lifetime through XML patches at mod load.
The inspected sources contain no evolving fluid field or pressure solve.
These controls can produce an inexpensive moving trail, but do not by
themselves reproduce our two sustained front vortices. Longer particle lives
also increase the population during bursts, so copying those settings is not
an established performance improvement. The current Workshop package itself
was not downloaded or installed for this comparison.

Noita exposes `GameSetPostFxTextureParameter` and editable virtual images, which
allow GPU postprocessing of CPU-generated visual data. Its installed
`tools_modding/lua_api_documentation.txt` exposes no compute dispatch, custom
simulation render targets or GPU readback. A direct GPU port of the evolving
field therefore needs capabilities outside this documented Lua API. A shader
display would also need an atlas upload, camera transforms, multiple-shot
handling and terrain masking; it would not remove the CPU pressure/advection
work needed by scripted collisions and damage.
