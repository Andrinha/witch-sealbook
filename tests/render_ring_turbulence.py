"""Before/after previews of actual gas rendering, with a no-flow control.

python tests/render_ring_turbulence.py [--baseline b7b3628]
Glow is approximated; these are not Noita screenshots or FPS measurements.
Both renderers use the new timing so the frames compare the same gas age.
"""
import argparse
import json
import subprocess

from PIL import Image

import render_fire_spells as Renderer
from harness import world_runtime


def circulation(source, radius, grow, age, still=False):
    lua = world_runtime()
    lua.execute('dofile_once("mods/witch_notebook/files/effects/flame_fields.lua")')
    if source is not None:
        lua.execute(source)
    lua.globals().RADIUS, lua.globals().GROW = radius, grow
    lua.globals().AGE, lua.globals().STILL = age, still
    lua.execute('''
        local F=FlameFields.presets.ring.model
        local source=F.source
        if STILL then
            F.tuning.vorticity,F.tuning.buoyancy=0,0
            F.source=function(s,p,age,dt)
                source(s,p,age,dt)
                for i=1,#s.u do s.u[i],s.v[i]=0,0 end
            end
        end
        P={ox=0,oy=-40,head=0,dx=1,dy=0,speed=0,r=RADIUS,grow=GROW,
            blast=GROW==16,cell=RADIUS*2.8/32}
        S=F.new(P,23)
        for age=0,AGE,2 do F.step(S,P,age,2/60) end
    ''')
    s = lua.globals().S
    density = list(s.d.values())
    curl = sum(abs(c) * d for c, d in zip(s.curl.values(), density)) / sum(density)
    return density, curl


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", default="b7b3628")
    args = parser.parse_args()
    source = subprocess.check_output(["git", "show", f"{args.baseline}:files/effects/flame_fields.lua"],
                                     cwd=Renderer.HERE.parent, text=True, encoding="utf-8")
    Renderer.OUT.mkdir(exist_ok=True)
    sheet = Image.new("RGB", (1440, 1320))
    for row, (key, name, tick) in enumerate((("ring_of_fire", "Ring of Fire", 19),
                                            ("flame_burst", "Flame Burst: explosion", 57))):
        for column, (label, baseline) in enumerate((("Before", source), ("After", None))):
            panel = Renderer.render(key, f"{label}: {name}", tick, field_source=baseline)
            sheet.paste(panel, (column * 720, row * 440))
    for column, (key, name, tick) in enumerate((("ring_of_fire", "Ring of Fire", 42),
                                                ("flame_burst", "Flame Burst", 75))):
        sheet.paste(Renderer.render(key, f"After: {name}, rolling flame", tick), (column * 720, 880))
    sheet.save(Renderer.OUT / "ring_turbulence.png")
    metrics = []
    for name, radius, grow, age in (("ring_of_fire", 55, 28, 34), ("flame_burst", 80, 16, 24)):
        result = {"spell": name, "radius": radius, "grow": grow, "age": age, "seed": 23}
        for label, baseline in (("before", source), ("after", None)):
            density, curl = circulation(baseline, radius, grow, age)
            control, _ = circulation(baseline, radius, grow, age, still=True)
            result[label] = {"heat_weighted_absolute_curl": curl,
                             "transport_vs_same_inlet_without_flow": sum(abs(a-b) for a, b in zip(density, control)) / sum(control)}
        metrics.append(result)
    (Renderer.OUT / "ring_turbulence.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(Renderer.OUT / "ring_turbulence.png")
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
