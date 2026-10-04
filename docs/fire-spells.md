# Fire spell audit

The reference pages below are saved copies of the Witch Hat Atelier wiki in
`reference/wha-wiki/pages/`. This review compares their descriptions with the
mod's manifestations; it does not claim an in-game visual check.

| Spell | Finding and resulting behavior |
| --- | --- |
| Spiraling Flame | Hold Fire to release three strands of independent particles that move along expanding helices around their saved launch axes. Each particle travels 1.5 turns, supplies short-lived native `FIRE` with Pyreball's buoyancy, airflow and fading, and carries warm light. Aim steers only newly released particles. The saved flight range is independent of cursor distance; release, item/page changes or disabled controls stop births while old particles expire naturally. Curved motion is swept in four sections per frame against walls/liquids, and only a sparse subset supplies grid fire. Damage comes from native fire, without a separate beam aura. Scripted casts still release a finite flying column. |
| Pyreball | A suspended orange 2D fluid plume shares Forbidden Flames' Gaussian inlet, buoyancy, circulation and density renderer. Size and strengthening scale its injection and bounded native fire supply. It stays near the cursor, lights the surroundings and renews one source on recast. |
| Flame Shot | The large column and two groups of five region signs release a decelerating hot-gas puff with two strong counter-rotating front vortices. A moving Lua grid evolves velocity, pressure and density; overlapping emissive sprites reconstruct continuous gas and pooled native emitters provide fire interactions. The launch axis stays fixed. Hot gas gates scripted fire damage, while walls/liquids block the head, transport and fire sources. The complete seal can also be recognized when its small region signs are ambiguous. |
| Flame Burst | A small fluid ring opens at the book; a fireball travels forward and creates a larger fluid blast at its target or first wall/liquid collision. The fireball is a round white-hot head with a wavering tail that cools to orange and narrows to a point, shedding cosmetic embers (previously a flat, saturated bar). The fireball and both rings evolve density and velocity in independent grids, with bounded native fire for material interactions. The seal remains marked as an interpretation: the wiki only shows part of the two-paper assembly. |
| Ring of Fire | An expanding gas annulus receives outward momentum and eight initial vortices, then rises, rolls up and cools after injection ends. Overlapping emissive sprites render continuous hot sheets with visible curls. Its actual density supplies native fire and gates the original one-hit expansion damage. Terrain/liquids block transport, sources and damage. |
| Phantasmal Fireball | The moving light was harmless as intended but consisted of a few blue dots. It now shares the living flame silhouette in a cold blue palette. It still creates no physical fire cells and inflicts no damage. |
| Forbidden Flames | A persistent violet inlet now feeds a small 2D fluid plume. Its original scripted damage is gated by actual density and wall/liquid visibility. The source survives temporary obstruction and resumes when clear. Persistence and color remain interpretations of the wiki's small forbidden flame. |
| Snugstone | Its warmth, drying and thawing already fit the description. No flame or burning damage was added. |
| Snowfending | Its lasting conversion now covers every vanilla snow/ice material, including dense snow, snow-covered rock and physical ice. Ordinary snow and ice become water; snowy rock and cold/toxic/meteor ice become ordinary stone. Blood/slime ice thaw into their original liquids, and frozen grass becomes grass. This broader terrain conversion applies specifically to Snowfending. |

The separate Forbidden Flames implementation is a persistent violet flame. The
wiki only confirms a small fire and explicitly leaves forbidden properties
unknown; its persistence and color are therefore the mod's interpretation.
It now uses the violet fluid preset described in
[the shared fire integration](fluid-fire-presets.md). Boilfire Dragon already
uses the steam dragon manifestation and retains its existing behavior.

All five custom damaging fire seals also support pages saved before their
manifestation keys were added. Unnamed player-created fire seals retain their
ordinary elemental carriers.
Recasting Pyreball at the same point or Phantasmal Fireball on the same caster
renews its duration instead of accumulating overlapping particle emitters.

Pyreball now shares Forbidden Flames' persistent gas simulation, with a
24 by 28 grid at two world pixels per cell, 12 pressure iterations and 15 Hz
solver updates. A Gaussian inlet scales with the seal radius and bounded spell
power. Buoyancy, pressure, vorticity and advection evolve its orange plume;
at most 256 overlapping emissive gas samples render actual density each frame.
The original fixed location, 60 px cursor reach, warm light, normal duration
and renewal at the same point are retained.

Four saved child emitters provide subdued native `FIRE`, with one moving
particle per source every two frames. They inherit fluid velocity and are born
at hot, nonsolid cells. A separate ignition supply remains capped at four grid
fire cells every six world frames (40 per second at 60 FPS), scaled by size and
power. Native fire obeys the game's material damage/burning rules, including
danger to the caster; Pyreball does not add a scripted damage aura. Strengthening
increases gas injection and ignition supply, not the native material temperature.

Terrain/liquid masks refresh every frame and inlet rays prevent injection
across thin obstacles. Water suppresses gas, emission and crackle; the magical
source persists for its normal duration and resumes when clear. Expiry destroys
its field and saved emitters while existing physical fire can continue burning.
Invisible ink dims the fluid renderer, native sources and source light.
Phantasmal Fireball retains its harmless blue cosmetic animation.

A saved `fluid_born` separates simulation time from the duration renewed on
recast. Renewal preserves density, velocity, solver cadence and native-emitter
ownership; it cannot accelerate ignition supply. Size/power changes adjust the
inlet while keeping the grid and existing gas. Reload reuses the saved field
and children. Older saves replace the tagged native-only Pyreball plume so it
cannot emit alongside the new pool. See [the fluid presets](fluid-fire-presets.md).

Fire audio reuses vanilla Noita banks. Pyreball, Spiraling Flame, Flame Shot,
Phantasmal Fireball, Forbidden Flames and ordinary fire carriers use the torch's
`player_projectiles/torch/loop` crackle. Each loop belongs to its source, follows
its movement and ends with its destruction; renewal reuses the same component.
Pyreball and held Spiraling Flame disable the loop while walls/liquids suppress
emission, then resume it when clear. Individual spiral embers stay silent.
Held Spiraling Flame repeats the short `player_projectiles/flamethrower/create`
sound every 12 frames (five times per second at 60 FPS) at the moving nozzle while
it emits. Blocking pauses the repeats; unblocking resumes immediately. Release
and other channel cancellation stop new sounds, with only a short existing tail.
Scripted Spiraling Flame launches with the same sound once. Flame
Shot and Flame Burst use `player_projectiles/bullet_fire_heavy/create`, and rings
use `player_projectiles/circle_of/create`. Flame Burst's final ring plays
`explosions/magic_rocket_big` once at the impact point. Warmth and thawing have no
fire loop. Offline checks cover component reuse, suppression/resumption, release,
expiry and impact sound calls; actual playback and mixing require an in-game check.

Flame Shot uses an original CPU/Lua fluid solver in
`files/effects/fluid.lua` and its integration in
`files/effects/flame_shot.lua`. The force, pressure, velocity and dye
stages follow the approach of
[Pavel Dobryakov's WebGL Fluid Simulation](https://github.com/PavelDoGreat/WebGL-Fluid-Simulation/blob/master/script.js);
this mod does not run its WebGL shaders.

The moving grid is 48 by 28 cells. The source is twelve cells inside its front edge,
leaving open air ahead of the flame. Its boundaries use ambient pressure and
allow outgoing gas; only actual local walls/liquids constrain the normal velocity.
Terrain masks probe each cell along both axes, without a visibility ray from the
muzzle. Gas can therefore flow into an obstacle's shadow. The window's movement,
advection backtraces and source footprint are swept against terrain, preventing
thin walls from being crossed by moving the frame or by interpolating heat.
Heat/damage inside solid cells is always zero.

At launch, one stream-function impulse seeds a strong counter-rotating vortex
pair around the front of the packet. The pair is not an animated outline or a
continuing forcing field. It rolls up a brief Gaussian hot-gas supply, then
advects, rises and decays naturally. The initial eddy scale is 160 pixels/second,
core radius is 1.2 times the seal radius, and core separation from the axis is
1.5 times that radius. A forward impulse of 55 pixels/second applies only at age
zero. The inlet supplies heat at 72 units/second for the first eight frames.

`FlameFluid.tuning` centralizes these parameters. Vorticity confinement is 5
and fades at 1.2 per second; heat/velocity decay are 1.4/0.35 per second.
Ambient drift is 0.06 times the actual window speed, becoming zero when a wall
stops the head. Each solver tick covers two world frames and splits into at most
six substeps, aiming for a maximum two-cell displacement per substep in the
optimized fire preset (the reusable factory still defaults to 0.65).
Each substep projects velocity with 24 Jacobi iterations, advects velocity with
midpoint backtraces, projects again, and transports density with limited
MacCormack correction. The correction is disabled at terrain/open edges.
Density bounds and integrated heat/light limits prevent overshoot and renewed
brightness after launch.

The visible flame is reconstructed every world frame from hot dye with
overlapping soft RGBA kernels, so it forms continuous sheets and curls.
At most 512 gas samples per shot use reusable native SpriteComponents, with a
translucent colored body and a weak additive glow per sample. Linear filtering,
wider kernels and opacity normalized by covered area suppress the dark cell
lattice without pure additive overexposure. One visual child owns the pool.
Larger fields sample the full footprint within that budget. The body is drawn
behind the world grid (`z_index` 0.3), so terrain cuts it pixel by pixel. Each
sprite fits the exact free runs of its pixel rows (`F.span`) and may reach
`FlameFluidDraw.spill` pixels under terrain at least that thick, never through
a thinner wall. Independent X/Y scales retain overlap along the wall; clipped
kernels receive no brightness boost. `tests/render_fluid_cave.py` previews it.
Tiny isolated corner kernels and fallback pixels fade to avoid glowing beads.
The new shared renderer also covers
Burst, Ring, Pyreball and Forbidden Flames; see [fluid-fire-presets.md](fluid-fire-presets.md).
This is CPU density reconstruction with native emissive rendering.

A pool of at most 12 saved child emitters supplies subdued native `FIRE`
particles for material interaction. Sources follow fluid trajectories every
frame, including between solver ticks. Cold/blocked sources are reseeded from
hot density. The pool emits one to two real moving particles per source every
two frames (at most 720/second per shot), inheriting the actual window movement
and fluid velocity. Native fire has its own airflow, fading and terrain collision;
it is not the primary visual representation of the velocity field. A separate
ignition supply remains capped at two grid fire cells every six frames
(20/second). Scripted fire damage requires hot gas at the victim's hitbox center.

Flame Shot retains its fixed launch direction, decelerating carrier, caster
attribution, power, muzzle clearance and cursor-independent range. It launches at
`360 + 35 * min(2, range)` pixels/second with drag 1.6 per second. Lifetime,
light/audio ownership, emitter reuse and cleanup are preserved. The versioned
saved field records dimensions and the last masked window position; old 32 by 18
fields are migrated in world space with converted velocity units.

Performance work preserves the grid, pressure iterations, solver cadence and
cosmetic particle budget. Each frame first scans the world pixel rows across the
window and its swept movement. A completely empty area bypasses per-cell and
per-particle rays. Near terrain, a per-frame cache scans all pixel rows in guarded
8 by 8 world tiles; segments in empty tiles bypass the engine, while occupied
tiles retain the original exact ray test. Liquid/terrain changes invalidate the
cache on every frame. Empty density cells skip unused reverse dye traces.

Native source/component IDs and parent variable IDs are cached in Lua and rebuilt
on reload. Static emitter settings are written only when needed, and sources
saved by the 48-emitter version are trimmed to twelve. The native fire supply is
smaller; the cosmetic flame and sparse ignition budget remain unchanged. Large
field snapshots are saved on solver ticks and on any intervening collision that
changes the field. A separate saved window-head float preserves exact reload
behavior between ticks without formatting the full field again.

`python tests/bench_flame_shot.py --output tests/output/flame_perf.json` measures
one shot, three shots and a wall scene for 60 frames with the offline Lua world.
In the before/after comparison, ray calls per frame fell from 9,413 to 67 in
open air and from 8,109 to about 1,127 near a wall. Component value reads/writes
fell from about 1,526 to 282 per frame, and open-air field snapshots from 60 to
30 per second. Captured density/velocity fields at frames 6, 18, 36 and 60 were
identical in all three scenes. These are mock/API-call measurements; actual
Noita FPS and native particle cost still require an in-game check.

The next optimization reuses per-state pressure/advection/dye buffers and the
boundary stencil until terrain changes, samples both velocity components with
one set of interpolation donors, and passes already-read effect parameters to
the light visibility helper. The latter lowers component reads/writes again,
from 282 to about 208 per shot/frame. The grid, pressure count, snapshots and
cosmetic budget stay unchanged. In the isolated five-run solver benchmark,
paired median times fell from 1.22-1.24 to 1.06-1.09 ms/step (about 10-15%);
memory allocated over 60 solver steps
with GC stopped fell from about 39 MiB to 0.27 MiB. Full-game FPS is not measured
by this benchmark. Density/velocity snapshots still match the previous version.

Other spells can create independent models, choose grid/physics settings and
replace the fire source with arbitrary density/velocity injection. See
[the reusable solver API and example](fluid-solver.md). Scratch fields are owned
by individual states, so interleaved spells never share changing data.

`python tests/render_flame_shot.py` generates
`tests/output/flame_shot_fluid.{png,gif}` and the six-frame contact sheet
`tests/output/flame_shot_vortices.png`. Panels show actual Lua density/flow,
captured sprite/particle calls with approximated glow, and a wall collision.
Native Noita particle appearance, material interactions and frame cost still
require an in-game check.

Verification:

- `python tests/test_flame_fields.py`: independent Burst/ring/violet fields,
  evolving velocity and cooling, cadence, budgets, thin walls and new liquids,
  density-gated damage, liquid impact and both Burst rings, reload between
  ticks, emitter reuse, moving-origin sweeps, old ring saves, profiling and expiry.
  Ring/blast no-flow controls check meaningful density transport, and seeded
  circulation must remain a one-time impulse.
- `python tests/test_fluid_draw.py`: continuous hot sheets without pinholes,
  emissive linear filtering, entire sprite footprints blocked by walls,
  immediate suppression by new water, invisible ink and cooling intensity.
- `python tests/test_flame_fluid.py`: pressure reduces divergence, gas advects
  and cools without injection, positive/negative evolving curl, finite fields,
  native emitter/fire budgets, liquid occlusion, reload between solver ticks,
  emitter reuse, cleanup, cursor-independent range/muzzle, source
  advection on every frame, a dense resolved nozzle, one-time forward impulse, packet deceleration,
  post-launch cooling without a permanent inlet, open-edge heat loss and
  fading without renewed density or light in four launch directions,
  launch independence from later aim/caster movement, open-edge velocity,
  retained heat in obstacle shadows, swept window collisions, two hot front
  vortex cores in all four directions, a fixed cosmetic pixel budget, and
  migration/truncation handling for saved fields. Performance regressions cover
  engine-call budgets, new liquids invalidating the empty-tile cache, collision
  snapshots between solver ticks and trimming/reusing older emitter pools.
- `python tests/test_fire_spells.py`: manifestations and old saved pages, floating
  bonfire lifetime, native fire supply and budgets, liquid/wall occlusion,
  recast cadence and renewal, straight jet and wall collisions, two-stage burst, ring damage
  and occlusion, harmless warmth/cold flame, recognition, and preservation of
  unrelated pages when rebuilding selected seals.
- `python tests/test_spiraling_flame.py`: held emission, rotating individual particles and reversed spin, independent trajectories on turns/movement/release, widening, cursor-independent range, bounded ignition, curved wall/water collision, lighting and the original scripted-flight regressions. The mock validates emitter configuration and simulated particle motion, not native fire rendering or material damage.
- `python tests/effects_smoke.py`: every manifestation and grimoire page; unknown
  component fields, materials, missing files and Lua runtime errors.
- Existing casting, carrier, ink, behavior, balance, sheet-ranking and grimoire
  selection checks in `tests/run_tests.py`.
- `python tests/render_fire_spells.py`: `tests/output/fire_spells.png` and animated
  previews of actual Lua sprite/particle calls, including Pyreball's fluid
  sheets; the offline renderer cannot simulate native fire
  cells. The game's particle glow and material simulation remain to be verified
  in Noita (open air, wood/oil, water, walls, several sources and source expiry).
