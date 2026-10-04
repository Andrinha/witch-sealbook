"""Repeatable Lua/API-call benchmark; this does not measure Noita's FPS.

python tests/bench_flame_shot.py [--output tests/output/flame_perf.json]
"""
import argparse
import json
import math
from pathlib import Path
import statistics
import time

from harness import world_runtime, cast_page, wall


def benchmark(shots=1, barrier=None, frames=60, stagger=True, interpreter=False, source=None, spell="flame_shot"):
    lua = world_runtime()
    if interpreter:
        lua.execute("jit.off()")
    if source:
        lua.execute('dofile_once("mods/witch_notebook/files/effects/fluid.lua")')
        lua.execute(source.read_text(encoding="utf-8"))
    lua.execute("for _,id in ipairs(ENEMIES) do EntityKill(id) end")
    if barrier is not None:
        wall(lua, barrier)
    # Pyreball renews one source when cast at the same point. Separate origins
    # are required to measure three/six simultaneous fields.
    effects = [cast_page(lua, spell, 60 - 8 * (i % 6) if spell == "pyreball" else 500,
                         -40 + 12 * (i // 6) if spell == "pyreball" else -40) for i in range(shots)]
    if not stagger:
        for effect in effects:
            lua.eval("effect_set")(effect,"fluid_phase",0)
        # Burst creates its opening/impact rings later, during simulation.
        lua.execute('''
            local spawn=effect_spawn
            function effect_spawn(...)
                local entity=spawn(...)
                local p=effect_params(entity)
                if p.kind=="flame" and p.mode=="ring" then effect_set(entity,"fluid_phase",0) end
                return entity
            end
        ''')
    lua.globals().bench_clock = time.perf_counter
    lua.execute('''
        dofile_once("mods/witch_notebook/files/effects/flame_shot.lua")
        dofile_once("mods/witch_notebook/files/effects/flame_fields.lua")
        BENCH={calls={},times={},counts={}}
        for _,name in ipairs({"RaytraceSurfacesAndLiquiform","ComponentGetValue2",
            "ComponentSetValue2","EntityGetComponent","EntityGetAllChildren",
            "EntityGetFirstComponent","GameCreateCosmeticParticle","GameCreateSpriteForXFrames","EntityLoad",
            "EntityCreateNew","EntityAddComponent2","EntityRefreshSprite"}) do
            local original=_G[name]
            _G[name]=function(...)
                BENCH.calls[name]=(BENCH.calls[name] or 0)+1
                return original(...)
            end
        end
        local entries={{FlameShot,"draw"},{FlameFields,"draw"}}
        local models={FlameFluid}
        for _,preset in pairs(FlameFields.presets) do models[#models+1]=preset.model end
        for _,model in ipairs(models) do
            for _,name in ipairs({"step","mask","pack"}) do entries[#entries+1]={model,name} end
        end
        for _,entry in ipairs(entries) do
            local owner,name=entry[1],entry[2]
            local original=owner[name]
            owner[name]=function(...)
                local started=bench_clock()
                local result=original(...)
                BENCH.times[name]=(BENCH.times[name] or 0)+bench_clock()-started
                BENCH.counts[name]=(BENCH.counts[name] or 0)+1
                return result
            end
        end
    ''')
    snapshots, frame_times, solver_ticks = {}, [], []
    stats = lua.globals().BENCH
    previous_steps = 0
    for tick in range(1, frames+1):
        started = time.perf_counter()
        lua.eval("simulate")(1)
        frame_times.append((time.perf_counter()-started)*1000)
        steps = stats.counts["step"] or 0
        solver_ticks.append(steps-previous_steps)
        previous_steps = steps
        if tick in (6, 18, 36, 60):
            states = lua.globals().FlameShot.states if spell == "flame_shot" else lua.globals().FlameFields.states
            state = states[effects[0]]
            if state is not None:
                snapshots[tick] = {name: list(state[name].values()) for name in ("d", "u", "v")}
    return {
        "shots": shots, "wall": barrier, "frames": frames, "stagger": stagger,
        "spell": spell,
        "interpreter": interpreter,
        "mock_ms_per_frame": statistics.mean(frame_times),
        "steady_mock_ms_per_frame": statistics.mean(frame_times[1:] or frame_times),
        "mock_frame_ms": {
            "p95": sorted(frame_times)[max(0,math.ceil(frames*.95)-1)],
            "max": max(frame_times), "first": frame_times[0],
            "steady_max": max(frame_times[1:] or frame_times),
        },
        "solver_ticks_per_frame": solver_ticks,
        "peak_solver_ticks_after_startup": max(solver_ticks[1:] or solver_ticks),
        "calls_per_frame": {name: count/frames for name,count in stats.calls.items()},
        "stage_ms_per_frame": {name: value/frames*1000 for name,value in stats.times.items()},
        "stage_counts": dict(stats.counts.items()),
        "snapshots": snapshots,
    }


def benchmark_solver(source=None, repeats=5, steps=60, interpreter=False):
    """Isolate the Lua kernel and allocation pressure from the mock entities."""
    source = source or Path(__file__).resolve().parents[1]/"files/effects/fluid.lua"
    runs = []
    for _ in range(repeats):
        lua = world_runtime()
        if interpreter:
            lua.execute("jit.off()")
        lua.execute(source.read_text(encoding="utf-8"))
        lua.globals().bench_clock = time.perf_counter
        lua.globals().BENCH_STEPS = steps
        runs.append(lua.execute('''
            function RaytraceSurfacesAndLiquiform(x1,y1,x2,y2) return false,x2,y2 end
            local F=FlameFluid
            local p={length=88,speed=360,r=6,head=140,ox=0,oy=-40,dx=1,dy=0}
            local function run(s)
                for tick=0,BENCH_STEPS-1 do F.step(s,p,tick*2,2/60) end
            end
            run(F.new(p,1)) -- warm the JIT before measuring
            local s=F.new(p,1)
            collectgarbage("collect")
            collectgarbage("stop")
            local heap=collectgarbage("count")
            local started=bench_clock()
            run(s)
            local elapsed=bench_clock()-started
            local allocated=collectgarbage("count")-heap
            collectgarbage("restart")
            return elapsed/BENCH_STEPS*1000,allocated
        '''))
    return {
        "source": str(source), "steps": steps, "repeats": repeats,
        "interpreter": interpreter,
        "solver_ms_per_step": statistics.median(row[0] for row in runs),
        "allocated_kib_with_gc_stopped": statistics.median(row[1] for row in runs),
    }


def benchmark_comparison(baseline, repeats=5, interpreter=False):
    """Alternate old/new runs; retain medians instead of one noisy sample."""
    results = []
    for shots, barrier in ((1, None), (3, None), (1, 145), (6, None)):
        runs = {"before": [], "after": []}
        for repeat in range(repeats):
            order = ("before", "after") if repeat % 2 == 0 else ("after", "before")
            for name in order:
                runs[name].append(benchmark(shots, barrier, interpreter=interpreter,
                                           source=baseline if name == "before" else None))
        summary = {}
        for name, rows in runs.items():
            summary[name] = {
                key: statistics.median(row[key] for row in rows)
                for key in ("mock_ms_per_frame", "steady_mock_ms_per_frame")
            }
            summary[name]["mock_frame_ms"] = {
                key: statistics.median(row["mock_frame_ms"][key] for row in rows)
                for key in rows[0]["mock_frame_ms"]
            }
            summary[name]["stage_ms_per_frame"] = {
                key: statistics.median(row["stage_ms_per_frame"][key] for row in rows)
                for key in rows[0]["stage_ms_per_frame"]
            }
            summary[name]["calls_per_frame"] = rows[0]["calls_per_frame"]
        results.append({
            "shots": shots, "wall": barrier, "frames": 60,
            "repeats": repeats, "interpreter": interpreter,
            "baseline": str(baseline), **summary,
            "speedup": summary["before"]["mock_ms_per_frame"] / summary["after"]["mock_ms_per_frame"],
            "steady_speedup": summary["before"]["steady_mock_ms_per_frame"] / summary["after"]["steady_mock_ms_per_frame"],
        })
    return results


def benchmark_startup(prepared=False, interpreter=False, repeats=5):
    """Include lazy mode loading, first buffers and first emitter setup."""
    times, loads, preparation_peaks = [], [], []
    for _ in range(repeats):
        lua=world_runtime()
        if interpreter:
            lua.execute("jit.off()")
        lua.execute("for _,id in ipairs(ENEMIES) do EntityKill(id) end")
        if prepared:
            lua.execute('effect_spawn("prepare","fluid",0,-40,{})')
            frame_times=[]
            for _ in range(20):
                started=time.perf_counter();lua.eval("simulate")(1)
                frame_times.append((time.perf_counter()-started)*1000)
            preparation_peaks.append(max(frame_times))
        lua.execute('''
            W.first_loads=0
            local load=EntityLoad
            function EntityLoad(...) W.first_loads=W.first_loads+1;return load(...) end
        ''')
        started=time.perf_counter()
        cast_page(lua,"flame_shot",500,-40)
        lua.eval("simulate")(1)
        times.append((time.perf_counter()-started)*1000)
        loads.append(lua.eval("W.first_loads"))
    return {"prepared":prepared,"interpreter":interpreter,"repeats":repeats,
            "first_cast_mock_ms":statistics.median(times),
            "first_cast_entity_loads":statistics.median(loads),
            "preparation_peak_mock_ms":statistics.median(preparation_peaks) if prepared else 0}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--solver", action="store_true", help="Isolate the Lua solver and its allocation pressure")
    parser.add_argument("--burst", action="store_true", help="Compare six synchronized shots with staggered solver ticks")
    parser.add_argument("--startup", action="store_true", help="Compare cold first casts with incremental preparation")
    parser.add_argument("--interpreter", action="store_true", help="Disable JIT in the test harness; does not change Noita's Lua runtime")
    parser.add_argument("--source", type=Path, help="Solver source for a baseline comparison")
    parser.add_argument("--compare", type=Path, help="Alternate baseline/current complete effect benchmarks")
    parser.add_argument("--repeats", type=int, default=5, help="Runs per solver/startup/comparison scenario")
    parser.add_argument("--spell", choices=("flame_shot", "flame_burst", "ring_of_fire", "forbidden_flames", "pyreball"),
                        default="flame_shot", help="Spell for the complete effect benchmark")
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error("--repeats must be positive")
    if args.compare and (args.source or args.solver or args.burst or args.startup):
        parser.error("--compare cannot be combined with --source, --solver, --burst or --startup")
    if args.spell != "flame_shot" and (args.compare or args.solver or args.startup):
        parser.error("--spell applies to complete updates and --burst")
    if args.burst and args.solver:
        parser.error("--burst and --solver are separate benchmarks")
    if args.startup and (args.solver or args.burst or args.source):
        parser.error("--startup cannot be combined with --solver, --burst or --source")
    if args.compare:
        results = benchmark_comparison(args.compare, args.repeats, args.interpreter)
    elif args.startup:
        results = [benchmark_startup(interpreter=args.interpreter,repeats=args.repeats),
                   benchmark_startup(True,args.interpreter,repeats=args.repeats)]
    elif args.solver:
        results = [benchmark_solver(args.source,repeats=args.repeats,interpreter=args.interpreter)]
    elif args.burst:
        frames = 104 if args.spell == "flame_burst" else 60
        results = [benchmark(6,frames=frames,stagger=False,interpreter=args.interpreter,source=args.source,spell=args.spell),
                   benchmark(6,frames=frames,interpreter=args.interpreter,source=args.source,spell=args.spell)]
    else:
        frames = 104 if args.spell == "flame_burst" else 60
        barrier = {"ring_of_fire": 25, "forbidden_flames": 142, "pyreball": 58}.get(args.spell, 145)
        results = [benchmark(frames=frames,interpreter=args.interpreter,source=args.source,spell=args.spell),
                   benchmark(3,frames=frames,interpreter=args.interpreter,source=args.source,spell=args.spell),
                   benchmark(barrier=barrier,frames=frames,interpreter=args.interpreter,source=args.source,spell=args.spell)]
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(results), encoding="utf-8")
    for result in results:
        view = {key:value for key,value in result.items() if key != "snapshots"}
        print(json.dumps(view, indent=2))


if __name__ == "__main__":
    main()
