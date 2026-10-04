"""Numerical fluid and native Flame Shot integration regressions.

python tests/test_flame_fluid.py
"""
import math
import unittest
from fluid_render_capture import sprites

from harness import world_runtime, cast_page, freeze_enemies


def sources(lua, effect):
    return [child for child in (lua.eval("EntityGetAllChildren")(effect) or {}).values()
            if lua.eval("EntityHasTag")(child, "witch_flame_shot_fire")]


class FlameFluid(unittest.TestCase):
    def test_compact_snapshots_bound_roundoff_and_preserve_live_fields(self):
        lua=world_runtime()
        result=lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local F=FlameFluid.create({width=17,height=11,
                tuning={density_cap=64,max_velocity=200,front_cells=4}})
            local p={length=50,head=-123.456789}
            local s=F.new(p,19)
            for i=1,#s.d do
                s.d[i]=(i%13)/12*64;s.u[i]=math.sin(i)*200;s.v[i]=math.cos(i)*200
            end
            s.d[1]=1e-13
            local before=s.d[1]
            local text=F.pack(s)
            F.tuning.density_cap,F.tuning.max_velocity=1,1 -- scales belong to the snapshot
            local restored=F.restore(p,text,1)
            local de,ve=0,0
            for i=1,#s.d do
                de=math.max(de,math.abs(s.d[i]-restored.d[i]))
                ve=math.max(ve,math.abs(s.u[i]-restored.u[i]),math.abs(s.v[i]-restored.v[i]))
            end
            local reused=F.new(p,1);F.pack(reused)
            local loaded=F.restore(p,text,1,reused)
            return text:sub(1,2),de,ve,s.d[1]-before,restored.seed,restored.mask_head,
                loaded.u[42]-restored.u[42],#loaded.packed_parts
        ''')
        self.assertEqual(result[0],"3:")
        self.assertLessEqual(result[1],2**(7-43)+1e-14)
        self.assertLessEqual(result[2],2**(8-43)+1e-13)
        self.assertEqual(result[3:5],(0,19))
        self.assertAlmostEqual(result[5],-123.456789,places=8)
        self.assertEqual(result[6:],(0,17*11*3))

    def test_compact_fire_snapshots_shrink_and_truncation_keeps_complete_cells(self):
        lua=world_runtime()
        new_size,old_size,first,missing=lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local F=FlameFluid
            local p={length=88,speed=360,r=6,head=140,ox=0,oy=-40,dx=1,dy=0}
            local s=F.new(p,1);F.step(s,p,0,2/60)
            local old={}
            for i=1,#s.d do old[i]=string.format("%.12g,%.12g,%.12g;",s.d[i],s.u[i],s.v[i]) end
            local partial=F.restore(p,"3:7:48:28:140:2:7;549755813888,68719476736,-103079215104,11,22",1)
            return #F.pack(s),#table.concat(old),partial.d[1]+partial.u[1]+partial.v[1],
                partial.d[2]+partial.u[2]+partial.v[2]+partial.d[1344]
        ''')
        self.assertLess(new_size,old_size*.85)
        self.assertEqual(first,-0.5)
        self.assertEqual(missing,0)

    def test_fast_fire_timestep_preserves_mass_and_packet_position(self):
        fast,reference=world_runtime(),world_runtime()
        reference.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            FlameFluid.max_courant=0.65
        ''')
        a,b=cast_page(fast,"flame_shot",500,-40),cast_page(reference,"flame_shot",500,-40)
        previous=0
        for tick in (6,18,36,60):
            fast.eval("simulate")(tick-previous);reference.eval("simulate")(tick-previous)
            previous=tick
            positions=[]
            for lua,effect in ((fast,a),(reference,b)):
                s=lua.globals().FlameShot.states[effect]
                d=[s.d[i] for i in range(1,48*28+1)]
                mass=sum(d)
                positions.append((mass,sum(v*(i%48+1) for i,v in enumerate(d))/mass,
                                  sum(v*(i//48+1) for i,v in enumerate(d))/mass))
            self.assertLess(abs(positions[0][0]/positions[1][0]-1),.02)
            self.assertLess(math.dist(positions[0][1:],positions[1][1:]),1)

    def test_preparation_is_incremental_inert_and_reused_by_first_cast(self):
        lua=world_runtime()
        lua.execute('''
            W.prep_loads={};W.prep_rays=0
            local load,ray=EntityLoad,RaytraceSurfacesAndLiquiform
            function EntityLoad(...)
                W.prep_loads[W.frame]=(W.prep_loads[W.frame] or 0)+1;return load(...)
            end
            function RaytraceSurfacesAndLiquiform(...)
                W.prep_rays=W.prep_rays+1;return ray(...)
            end
            PREP=effect_spawn("prepare","fluid",0,-40,{})
            simulate(20)
        ''')
        shot=lua.globals().FlameShot
        prepared=shot.prepared_state
        buffers=[prepared[name] for name in ("pressure_a","pressure_b","predicted","advected_d","advected_u")]
        spare=set(entry.entity for entry in shot.prepared_sources.values())
        self.assertEqual(len(spare),12)
        self.assertLessEqual(max(lua.eval("W.prep_loads").values()),1)
        self.assertEqual(lua.eval("W.prep_rays"),0)
        self.assertEqual(lua.eval("W.real_fire"),0)
        self.assertFalse(list(lua.eval("W.hits").values()))
        component=lua.eval("EntityGetFirstComponentIncludingDisabled")(lua.globals().PREP,"LuaComponent")
        self.assertFalse(lua.eval("ComponentGetIsEnabled")(component))
        for child in spare:
            emitter=lua.eval("EntityGetFirstComponent")(child,"ParticleEmitterComponent")
            self.assertFalse(lua.eval("ComponentGetValue2")(emitter,"is_emitting"))
        reference=world_runtime()
        a,b=cast_page(lua,"flame_shot",500,-40),cast_page(reference,"flame_shot",500,-40)
        lua.execute('function EntityLoad() error("Prepared first cast must not load new emitters") end')
        lua.eval("simulate")(1);reference.eval("simulate")(1)
        self.assertEqual(set(sources(lua,a)),spare)
        state=shot.states[a]
        self.assertTrue(lua.eval("rawequal")(state,prepared))
        for name,buffer in zip(("pressure_a","pressure_b","predicted","advected_d","advected_u"),buffers):
            # Advection fields ping-pong, so either side can own the buffer now.
            fields=(state[name],state.d,state.u,state.v)
            self.assertTrue(any(lua.eval("rawequal")(field,buffer) for field in fields),name)
        self.assertIsNone(state.raycast)
        self.assertIsNone(shot.prepared_state)
        for name in ("d","u","v"):
            self.assertEqual(list(state[name].values()),list(reference.globals().FlameShot.states[b][name].values()))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_prepared_state_can_be_reset_for_another_spell_without_stale_boundaries(self):
        lua=world_runtime()
        error=lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local F=FlameFluid.create({width=20,height=14,iterations=8,cell_size=3,tuning={front_cells=5}})
            local p={speed=0,r=4,head=0,ox=0,oy=0,dx=1,dy=0}
            local s=F.new(p,7)
            s.raycast=function(x1,y1,x2,y2) return true,x1,y1 end
            F.step(s,p,0,1/60)
            local u=F.new(p,8,s)
            local reference=F.new(p,8)
            F.step(u,p,0,1/60);F.step(reference,p,0,1/60)
            local error=0
            for i=1,#u.d do
                error=math.max(error,math.abs(u.d[i]-reference.d[i]),math.abs(u.u[i]-reference.u[i]),math.abs(u.v[i]-reference.v[i]))
            end
            return error
        ''')
        self.assertEqual(error,0)

    def test_direct_pressure_spans_match_jacobi_at_walls_and_open_edges(self):
        lua=world_runtime()
        error=lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local w,h=19,12
            local F=FlameFluid.create({width=w,height=h,iterations=11})
            local s=F.new({length=40},1)
            local u,v,div,a,b={},{},{},{},{}
            for y=1,h do for x=1,w do
                local i=(y-1)*w+x
                s.solid[i]=(x==8 and y>=3 and y<=9) or (x==15 and y<4) or y==h
                u[i],v[i]=s.solid[i] and 0 or math.sin(i)*4,s.solid[i] and 0 or math.cos(i)*3
                s.u[i],s.v[i],a[i],b[i]=u[i],v[i],0,0
            end end
            local function adjacent(x,y)
                return x>=1 and x<=w and y>=1 and y<=h and (y-1)*w+x or 0
            end
            local function velocity(field,i,j)
                if j==0 then return field[i] end
                return s.solid[j] and -field[i] or field[j]
            end
            for y=1,h do for x=1,w do
                local i=(y-1)*w+x
                div[i]=0.5*(velocity(u,i,adjacent(x+1,y))-velocity(u,i,adjacent(x-1,y))
                    +velocity(v,i,adjacent(x,y+1))-velocity(v,i,adjacent(x,y-1)))
            end end
            local function pressure(field,i,j)
                if j==0 then return 0 end
                return s.solid[j] and field[i] or field[j]
            end
            for tick=1,F.iterations do
                for y=1,h do for x=1,w do
                    local i=(y-1)*w+x
                    if not s.solid[i] then
                        b[i]=(pressure(a,i,adjacent(x-1,y))+pressure(a,i,adjacent(x+1,y))
                            +pressure(a,i,adjacent(x,y-1))+pressure(a,i,adjacent(x,y+1))-div[i])*0.25
                    end
                end end
                a,b=b,a
            end
            F.project(s)
            local error=0
            for y=1,h do for x=1,w do
                local i=(y-1)*w+x
                if not s.solid[i] then
                    local l,r,t,b=adjacent(x-1,y),adjacent(x+1,y),adjacent(x,y-1),adjacent(x,y+1)
                    local ru=u[i]-0.5*(pressure(a,i,r)-pressure(a,i,l))
                    local rv=v[i]-0.5*(pressure(a,i,b)-pressure(a,i,t))
                    if s.solid[l] or s.solid[r] then ru=0 end
                    if s.solid[t] or s.solid[b] then rv=0 end
                    error=math.max(error,math.abs(s.u[i]-ru),math.abs(s.v[i]-rv))
                end
            end end
            return error
        ''')
        self.assertEqual(error,0)

    def test_scanline_proofs_keep_exact_collisions_for_diagonal_segments(self):
        lua=world_runtime()
        collisions,error=lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            -- Pixel obstacles, with an independent fine-step segment query.
            local function ray(x1,y1,x2,y2)
                local steps=math.max(1,math.ceil(math.max(math.abs(x2-x1),math.abs(y2-y1))*64))
                for n=0,steps do
                    local x,y=x1+(x2-x1)*n/steps,y1+(y2-y1)*n/steps
                    local gx,gy=math.floor(x),math.floor(y)
                    if (gx>=8 and gx<=10 and gy>=-44 and gy<=-38)
                        or (gx==31 and gy>=-63 and gy<=-12) or (gy==-54 and gx>=-20 and gx<=5) then
                        return true,x,y
                    end
                end
                return false,x2,y2
            end
            RaytraceSurfacesAndLiquiform=ray
            local s=FlameFluid.new({length=88,head=40},1)
            FlameFluid.mask(s,{head=40,ox=0,oy=-40,dx=1,dy=0})
            local collisions,error=0,0
            for n=1,300 do
                local x,y=-25+(n*17)%80,-65+(n*7)%54
                local tx,ty=x+math.sin(n)*9,y+math.cos(n)*8
                local expected=not not ray(x,y,tx,ty)
                local actual=not not FlameFluid.blocked(s,x,y,tx,ty)
                if expected then collisions=collisions+1 end
                if actual~=expected then error=error+1 end
            end
            return collisions,error
        ''')
        self.assertGreater(collisions,10)
        self.assertEqual(error,0)

    def test_burst_solver_ticks_are_split_between_neighboring_frames(self):
        lua=world_runtime()
        lua.execute("for _,id in ipairs(ENEMIES) do EntityKill(id) end")
        effects=[cast_page(lua,"flame_shot",500,-40) for _ in range(6)]
        lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/flame_shot.lua")
            W.solver_frames={}
            local step=FlameFluid.step
            function FlameFluid.step(...)
                W.solver_frames[W.frame]=(W.solver_frames[W.frame] or 0)+1
                return step(...)
            end
            simulate(32)
        ''')
        ticks=lua.eval("W.solver_frames")
        first=min(ticks.keys())
        self.assertEqual(ticks[first],6,"All shots must become visible immediately")
        self.assertTrue(all(ticks[frame]==3 for frame in range(first+1,first+32)))
        self.assertTrue(all(lua.eval("EntityGetIsAlive")(effect) for effect in effects))
        self.assertEqual(sorted(lua.eval("effect_params")(e)["fluid_phase"] for e in effects),[0,0,0,1,1,1])

    def test_opposite_solver_phase_keeps_two_hot_vortices_and_survives_reload(self):
        live,loaded=world_runtime(),world_runtime()
        for lua in (live,loaded):
            cast_page(lua,"flame_shot",500,-40)
        a,b=cast_page(live,"flame_shot",500,-40),cast_page(loaded,"flame_shot",500,-40)
        for lua in (live,loaded):
            lua.eval("simulate")(20)
        state=live.globals().FlameShot.states[a]
        width,height=live.globals().FlameFluid.width,live.globals().FlameFluid.height
        cores=[]
        for side in (-1,1):
            candidates=[(abs(c),i,c) for i,c in state.curl.items()
                        if ((i-1)//width+1-(height+1)/2)*side>1 and (i-1)%width+1>width*.55]
            strength,index,curl=max(candidates)
            self.assertGreater(strength,10)
            gx,gy=(index-1)%width+1,(index-1)//width+1
            heat=sum(d for j,d in state.d.items()
                     if abs((j-1)%width+1-gx)<=2 and abs((j-1)//width+1-gy)<=2)
            self.assertGreater(heat,5)
            cores.append(curl)
        self.assertLess(cores[0]*cores[1],0)
        self.assertEqual(live.eval("effect_params")(a)["fluid_phase"],1)
        loaded.globals().FlameShot.states[b]=None
        live.eval("simulate")(8);loaded.eval("simulate")(8)
        left,right=live.globals().FlameShot.states[a],loaded.globals().FlameShot.states[b]
        for name in ("d","u","v"):
            self.assertLess(max(abs(x-y) for x,y in zip(left[name].values(),right[name].values())),1e-5)

    def test_solver_reuses_buffers_without_large_allocation_spikes(self):
        lua=world_runtime()
        allocated=lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            function RaytraceSurfacesAndLiquiform(x1,y1,x2,y2) return false,x2,y2 end
            local p={length=88,speed=360,r=6,head=140,ox=0,oy=-40,dx=1,dy=0}
            local s=FlameFluid.new(p,1)
            FlameFluid.step(s,p,0,2/60)
            collectgarbage("collect");collectgarbage("stop")
            local before=collectgarbage("count")
            for age=2,120,2 do FlameFluid.step(s,p,age,2/60) end
            local allocated=collectgarbage("count")-before
            collectgarbage("restart")
            return allocated
        ''')
        self.assertLess(allocated,1024,"60 solver ticks must allocate less than 1 MiB after warmup")

    def test_pressure_stencil_tracks_appearing_and_disappearing_walls(self):
        lua=world_runtime()
        error,walls=lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local F=FlameFluid
            local p={length=88,speed=0,head=70,ox=0,oy=-40,dx=1,dy=0}
            local wall
            function RaytraceSurfacesAndLiquiform(x1,y1,x2,y2)
                if wall and x1~=x2 and (x1-wall)*(x2-wall)<=0 then return true,wall,y1 end
                return false,x2,y2
            end
            local s=F.new(p,1)
            local error,walls=0,0
            for _,barrier in ipairs({false,30,false,80,false}) do
                wall=barrier;F.mask(s,p)
                local reference=F.new(p,1)
                for i=1,#s.u do
                    s.u[i],s.v[i]=math.sin(i)*3,math.cos(i)*2
                    if s.solid[i] then walls=walls+1;s.u[i],s.v[i]=0,0 end
                    reference.solid[i],reference.u[i],reference.v[i]=s.solid[i],s.u[i],s.v[i]
                end
                F.project(s);F.project(reference)
                for i=1,#s.u do error=math.max(error,math.abs(s.u[i]-reference.u[i]),math.abs(s.v[i]-reference.v[i])) end
            end
            return error,walls
        ''')
        self.assertEqual(error,0)
        self.assertGreater(walls,0)

    def test_configurable_models_and_interleaved_states_are_independent(self):
        lua=world_runtime()
        result=lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            function RaytraceSurfacesAndLiquiform(x1,y1,x2,y2) return false,x2,y2 end
            local options={width=24,height=16,iterations=10,cell_size=3,
                tuning={emit_frames=0,buoyancy=0,front_cells=6,heat_decay=0.3}}
            local gas=FlameFluid.create(options)
            options.tuning.heat_decay=100 -- the model owns a copy of its settings
            local other=FlameFluid.create({width=16,height=12,iterations=8,cell_size=2,
                tuning={emit_frames=0,buoyancy=0,front_cells=4}})
            local p={length=60,speed=0,r=3,head=60,ox=0,oy=-40,dx=1,dy=0}
            local a,b,reference=gas.new(p,1),gas.new(p,2),gas.new(p,1)
            gas.splat(a,8,8,2,1,12,-3);gas.splat(reference,8,8,2,1,12,-3)
            gas.splat(b,17,4,1,2,-10,7)
            local c=other.new(p,3)
            for age=0,18,2 do
                gas.step(a,p,age,2/60)
                gas.step(b,p,age,2/60)
                other.step(c,p,age,2/60)
            end
            for age=0,18,2 do gas.step(reference,p,age,2/60) end
            local error,mass,empty=0,0,0
            for i=1,#a.d do
                error=math.max(error,math.abs(a.d[i]-reference.d[i]),math.abs(a.u[i]-reference.u[i]),math.abs(a.v[i]-reference.v[i]))
                mass=mass+a.d[i]
            end
            for _,d in ipairs(c.d) do empty=empty+d end
            local restored=gas.restore(p,gas.pack(a),1)
            return error,mass,empty,#a.d,#c.d,gas.tuning.heat_decay,
                FlameFluid.tuning.heat_decay,restored.d[180],a.d[180],a.cell,c.cell
        ''')
        self.assertEqual(result[0],0)
        self.assertGreater(result[1],0)
        self.assertEqual(result[2],0)
        self.assertEqual(result[3:7],(24*16,16*12,0.3,1.4))
        self.assertAlmostEqual(result[7],result[8],places=10)
        self.assertEqual(result[9:],(3,2))

    def test_custom_spell_source_replaces_fire_nozzle_and_respects_solids(self):
        lua=world_runtime()
        calls,default_calls,custom_mass,solid_heat,empty=lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            function RaytraceSurfacesAndLiquiform(x1,y1,x2,y2) return false,x2,y2 end
            local gas,calls,default_calls
            calls,default_calls=0,0
            gas=FlameFluid.create({width=24,height=16,iterations=8,cell_size=3,
                tuning={buoyancy=0,front_cells=6},
                source=function(s,p,age,dt)
                    calls=calls+1;gas.splat(s,8,8,1,10*dt,0,5*dt)
                end})
            local p={length=60,speed=0,head=0,ox=0,oy=0,dx=1,dy=0}
            local a,b=gas.new(p,1),gas.new(p,2)
            gas.step(a,p,0,2/60) -- no fire-specific radius/launch parameters needed
            gas.step(b,p,0,2/60,function() default_calls=default_calls+1 end)
            local mass,empty=0,0
            for _,d in ipairs(a.d) do mass=mass+d end
            for _,d in ipairs(b.d) do empty=empty+d end
            local solid=gas.new(p,3)
            local i=(8-1)*gas.width+8;solid.solid[i]=true
            gas.splat(solid,8,8,1,1,12,8)
            return calls,default_calls,mass,solid.d[i]+math.abs(solid.u[i])+math.abs(solid.v[i]),empty
        ''')
        self.assertEqual((calls,default_calls),(1,1))
        self.assertGreater(custom_mass,0)
        self.assertEqual(solid_heat,0)
        self.assertEqual(empty,0)

    def test_air_fast_path_has_a_bounded_engine_call_budget(self):
        lua=world_runtime()
        lua.execute('''
            for _,id in ipairs(ENEMIES) do EntityKill(id) end
            W.ray_budget,W.component_budget=0,0
            local ray=RaytraceSurfacesAndLiquiform
            function RaytraceSurfacesAndLiquiform(...)
                W.ray_budget=W.ray_budget+1;return ray(...)
            end
            local get,set=ComponentGetValue2,ComponentSetValue2
            function ComponentGetValue2(...)
                W.component_budget=W.component_budget+1;return get(...)
            end
            function ComponentSetValue2(...)
                W.component_budget=W.component_budget+1;return set(...)
            end
        ''')
        effect=cast_page(lua,"flame_shot",500,-40)
        lua.execute("W.ray_budget,W.component_budget=0,0;simulate(60)")
        self.assertLess(lua.eval("W.ray_budget")/60, 128)
        self.assertLess(lua.eval("W.component_budget")/60, 350)
        self.assertLessEqual(len(sources(lua,effect)), 12)

    def test_cached_empty_tiles_detect_new_liquid_on_the_next_frame(self):
        lua=world_runtime()
        before,after=lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local p={length=88,speed=0,head=60,ox=0,oy=-40,dx=1,dy=0}
            local s=FlameFluid.new(p,1)
            local liquid=false
            function RaytraceSurfacesAndLiquiform(x1,y1,x2,y2)
                if liquid and y1>=-40 and y1<=-39 and y2>=-40 and y2<=-39
                    and math.min(x1,x2)<=31 and math.max(x1,x2)>=30 then return true,30,y1 end
                return false,x2,y2
            end
            FlameFluid.mask(s,p)
            local before=FlameFluid.blocked(s,10,-39.5,50,-39.5)
            liquid=true
            FlameFluid.mask(s,p)
            return before,FlameFluid.blocked(s,10,-39.5,50,-39.5)
        ''')
        self.assertFalse(before)
        self.assertTrue(after)

    def test_collision_snapshot_is_saved_between_solver_ticks(self):
        lua=world_runtime()
        effect=cast_page(lua,"flame_shot",500,-40)
        lua.eval("simulate")(1)
        previous=lua.eval("effect_params")(effect)["fluid_state"]
        lua.execute('''
            function RaytraceSurfacesAndLiquiform(x1,y1,x2,y2) return true,x1,y1 end
            simulate(1)
        ''')
        params=lua.eval("effect_params")(effect)
        self.assertNotEqual(params["fluid_state"], previous)
        restored=lua.globals().FlameFluid.restore(params,params["fluid_state"],effect)
        self.assertEqual(sum(restored.d.values()),0)
        # Between ticks only hot cells are swept; flow left in cold cells is
        # removed by the mask every restored field receives before its first use.
        lua.globals().RESTORED, lua.globals().PARAMS = restored, params
        lua.execute("FlameFluid.mask(RESTORED, PARAMS)")
        self.assertEqual(sum(abs(value) for value in restored.u.values()),0)

    def test_reload_trims_old_emitter_pools_and_reuses_retained_children(self):
        lua=world_runtime()
        effect=cast_page(lua,"flame_shot",500,-40)
        lua.eval("simulate")(20)
        retained=sources(lua,effect)
        lua.globals().POOL_EFFECT=effect
        excess=list(lua.execute('''
            local out={}
            for i=1,36 do
                local child=EntityLoad("mods/witch_notebook/files/entities/flame_shot_fire.xml",0,-40)
                EntityAddChild(POOL_EFFECT,child);out[#out+1]=child
            end
            FlameShot.states[POOL_EFFECT]=nil
            return out
        ''').values())
        lua.eval("simulate")(2)
        self.assertEqual(sources(lua,effect),retained)
        self.assertTrue(all(not lua.eval("EntityGetIsAlive")(child) for child in excess))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_open_edges_do_not_stop_uniform_flow(self):
        lua = world_runtime()
        error = lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local s = FlameFluid.new({length=88},1)
            for i=1,FlameFluid.width*FlameFluid.height do s.u[i],s.v[i]=7,-3 end
            FlameFluid.project(s)
            local error=0
            for i=1,#s.u do error=math.max(error,math.abs(s.u[i]-7),math.abs(s.v[i]+3)) end
            return error
        ''')
        self.assertEqual(error, 0)

    def test_empty_air_in_an_obstacles_shadow_is_not_solid(self):
        lua = world_runtime()
        solid, heat = lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local p={length=88,speed=0,r=6,head=70,ox=0,oy=-40,dx=1,dy=0}
            local s=FlameFluid.new(p,1)
            local i=(14-1)*FlameFluid.width+30
            s.d[i]=1
            function RaytraceSurfacesAndLiquiform(x1,y1,x2,y2)
                if x1~=x2 and (x1-30)*(x2-30)<=0 then
                    local y=y1+(y2-y1)*(30-x1)/(x2-x1)
                    if y>=-44 and y<=-36 then return true,30,y end
                end
                return false,x2,y2
            end
            FlameFluid.mask(s,p)
            return s.solid[i],s.d[i]
        ''')
        self.assertFalse(solid)
        self.assertEqual(heat, 1)

    def test_window_motion_cannot_carry_heat_through_a_thin_wall(self):
        lua = world_runtime()
        heat = lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local p={length=88,speed=0,r=6,head=70,ox=0,oy=-40,dx=1,dy=0}
            local s=FlameFluid.new(p,1)
            local i=(14-1)*FlameFluid.width+38
            s.d[i]=1
            function RaytraceSurfacesAndLiquiform(x1,y1,x2,y2)
                if x1~=x2 and (x1-75)*(x2-75)<=0 then return true,75,y1 end
                return false,x2,y2
            end
            p.head=80
            FlameFluid.mask(s,p)
            return s.d[i]
        ''')
        self.assertEqual(heat, 0)

    def test_two_front_vortex_cores_survive_in_all_launch_directions(self):
        for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
            with self.subTest(direction=(dx,dy)):
                lua = world_runtime()
                effect = cast_page(lua,"flame_shot",dx*500,-40+dy*500)
                elapsed = 0
                for tick in (6,18,36):
                    lua.eval("simulate")(tick-elapsed)
                    elapsed=tick
                    state=lua.globals().FlameShot.states[effect]
                    width,height=lua.globals().FlameFluid.width,lua.globals().FlameFluid.height
                    cores=[]
                    for side in (-1,1):
                        candidates=[(abs(c),i,c) for i,c in state.curl.items()
                                    if ((i-1)//width+1-(height+1)/2)*side>1
                                    and (i-1)%width+1>width*.55]
                        strength,index,curl=max(candidates)
                        self.assertGreater(strength, 10)
                        gx,gy=(index-1)%width+1,(index-1)//width+1
                        heat=sum(d for j,d in state.d.items()
                                 if abs((j-1)%width+1-gx)<=2 and abs((j-1)//width+1-gy)<=2)
                        self.assertGreater(heat, 5, "A velocity vortex must contain visible hot gas")
                        cores.append(curl)
                    self.assertLess(cores[0]*cores[1], 0)

    def test_visible_samples_follow_hot_gas_with_a_fixed_budget(self):
        lua=world_runtime()
        effect=cast_page(lua,"flame_shot",500,-40)
        lua.globals().PIXEL_EFFECT=effect
        lua.execute('''
            W.pixel_frames={}; W.pixel_error=false
            local original=GameCreateCosmeticParticle
            function GameCreateCosmeticParticle(m,x,y,n,vx,vy,color,lmin,lmax,force,front,collide,randomize,gx,gy)
                local s=FlameShot.states[PIXEL_EFFECT]
                local p=effect_params(PIXEL_EFFECT)
                if not s or FlameFluid.density(s,p,x,y)<0.035-1e-9
                    or lmax>2/60 or not collide or gx~=0 or gy~=0 then W.pixel_error=true end
                W.pixel_frames[W.frame]=(W.pixel_frames[W.frame] or 0)+n
                original(m,x,y,n,vx,vy,color,lmin,lmax,force,front,collide,randomize,gx,gy)
            end
        ''')
        counts = []
        for _ in range(40):
            lua.eval("simulate")(1)
            samples = sprites(lua)
            state = lua.globals().FlameShot.states[effect]
            p = lua.eval("effect_params")(effect)
            for sample in samples:
                self.assertGreaterEqual(state.model.density(state, p, sample.x, sample.y), 0.035-1e-9)
                self.assertTrue(lua.globals().W.comps[sample.component]["values"].emissive)
            counts.append(len(samples) + (lua.eval("W.pixel_frames")[lua.eval("W.frame")] or 0))
        self.assertFalse(lua.eval("W.pixel_error"))
        self.assertGreater(min(counts), 0)
        self.assertLessEqual(max(counts), lua.globals().FlameShot.pixels)

    def test_render_budget_keeps_both_sides_of_a_large_hot_field(self):
        lua=world_runtime()
        count, low, high=lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/flame_shot.lua")
            local p={length=88,head=140,speed=0,ox=0,oy=-40,dx=1,dy=0}
            local s=FlameFluid.new(p,1)
            s.entity=EntityCreateNew("test gas")
            for i=1,#s.d do s.d[i]=1 end
            FlameFluid.mask(s,p)
            local count,lo,hi=0,math.huge,-math.huge
            function GameCreateCosmeticParticle(m,x,y,n)
                count=count+n;lo=math.min(lo,y);hi=math.max(hi,y)
            end
            FlameShot.draw(s,p,0)
            return count,lo,hi
        ''')
        samples = sprites(lua)
        count += len(samples)
        low = min([low] + [s.y for s in samples])
        high = max([high] + [s.y for s in samples])
        self.assertGreater(count, 0)
        self.assertLessEqual(count, lua.globals().FlameShot.pixels)
        self.assertLess(low, -60)
        self.assertGreater(high, -20)

    def test_hot_grid_edge_cannot_act_as_a_second_inlet(self):
        lua = world_runtime()
        heat = lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local p = {length=88, speed=360, velocity=360, r=6, head=140,
                tail=0, ox=0, oy=-40, dx=1, dy=0}
            local s = FlameFluid.new(p,1)
            for y=1,FlameFluid.height do s.d[(y-1)*FlameFluid.width+FlameFluid.width]=1 end
            FlameFluid.step(s,p,60,2/60)
            local sum=0
            for _,d in ipairs(s.d) do sum=sum+d end
            return sum
        ''')
        self.assertLess(heat, lua.globals().FlameFluid.height)

    def test_post_launch_flame_fades_without_reigniting(self):
        for dx, dy in ((1, 0), (-1, 0), (0, -1), (0, 1)):
            with self.subTest(direction=(dx, dy)):
                lua = world_runtime()
                effect = cast_page(lua, "flame_shot", dx*1000, -40+dy*1000)
                lua.eval("simulate")(8)
                previous_peak, previous_glow = math.inf, math.inf
                for _ in range(90):
                    lua.eval("simulate")(1)
                    state = lua.globals().FlameShot.states[effect]
                    if state is None:
                        break
                    peak = max(state.d.values())
                    glow = sum(d**1.5 for d in state.d.values() if d>0.055)
                    self.assertLessEqual(peak, previous_peak+1e-9)
                    self.assertLessEqual(glow, previous_glow+1e-9)
                    previous_peak, previous_glow = peak, glow
                self.assertLess(previous_peak, 0.2)

    def test_launch_is_dense_and_spatially_compact(self):
        lua = world_runtime()
        peak, transverse_rms, depth = lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local p = {length=88, speed=360, velocity=360, r=6, head=140,
                tail=0, ox=0, oy=-40, dx=1, dy=0}
            local s = FlameFluid.new(p,1)
            FlameFluid.step(s,p,0,2/60)
            local mass, moment, peak, lo, hi = 0,0,0,FlameFluid.width,1
            for i,d in ipairs(s.d) do
                local x, y = (i-1)%FlameFluid.width+1, math.floor((i-1)/FlameFluid.width)+1
                mass=mass+d
                moment=moment+d*((y-(FlameFluid.height+1)/2)*s.cell)^2
                peak=math.max(peak,d)
                if d>0.055 then lo=math.min(lo,x); hi=math.max(hi,x) end
            end
            return peak,math.sqrt(moment/mass),(hi-lo+1)*s.cell
        ''')
        self.assertGreater(peak, 1)
        self.assertLess(transverse_rms, 8)
        self.assertLessEqual(depth, 20)

    def test_extra_forward_impulse_is_applied_only_at_launch(self):
        lua = world_runtime()
        launch_delta, later_delta = lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local p = {length=88, speed=360, velocity=360, r=6, head=140,
                tail=0, ox=0, oy=-40, dx=1, dy=0}
            local kick=FlameFluid.tuning.launch_impulse
            local function difference(age)
                local a,b=FlameFluid.new(p,1),FlameFluid.new(p,1)
                FlameFluid.tuning.launch_impulse=kick
                FlameFluid.step(a,p,age,2/60)
                FlameFluid.tuning.launch_impulse=0
                FlameFluid.step(b,p,age,2/60)
                local delta=0
                for i=1,FlameFluid.width*FlameFluid.height do delta=delta+a.u[i]-b.u[i] end
                return delta
            end
            local launch,later=difference(0),difference(2)
            FlameFluid.tuning.launch_impulse=kick
            return launch,later
        ''')
        self.assertGreater(launch_delta, 1)
        self.assertAlmostEqual(later_delta, 0)

    def test_packet_slows_after_its_launch(self):
        lua = world_runtime()
        effect = cast_page(lua, "flame_shot", 1000, -40)
        speeds, distances = [], []
        last_x = 8
        for _ in range(6):
            lua.execute("simulate(10)")
            self.assertTrue(lua.eval("EntityGetIsAlive")(effect))
            p = lua.eval("effect_params")(effect)
            x = lua.eval("EntityGetTransform")(effect)[0]
            speeds.append(p["velocity"])
            distances.append(x - last_x)
            last_x = x
        self.assertTrue(all(a > b for a,b in zip(speeds, speeds[1:])))
        self.assertLess(speeds[-1], speeds[0] * 0.3)
        self.assertLess(distances[-1], distances[0] * 0.3)

    def test_late_hot_gas_cools_without_a_permanent_inlet(self):
        lua = world_runtime()
        initial_heat, final_heat = lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local p = {length=88, speed=240, velocity=0, r=6, head=140,
                tail=0, ox=0, oy=-40, dx=1, dy=0}
            local s = FlameFluid.new(p,1)
            for i=1,FlameFluid.width*FlameFluid.height do s.d[i]=0.5 end
            FlameFluid.step(s,p,60,2/60)
            local sum=0
            for _,d in ipairs(s.d) do sum=sum+d end
            return FlameFluid.width*FlameFluid.height*0.5,sum
        ''')
        self.assertLess(final_heat, initial_heat * 0.98)

    def test_cursor_distance_changes_only_direction(self):
        for dx, dy in ((1, 0), (0, -1), (-0.8, 0.6)):
            for distance in (0.05, 1, 20, 1000):
                with self.subTest(direction=(dx, dy), distance=distance):
                    lua = world_runtime()
                    near = cast_page(lua, "flame_shot", dx * distance, -40 + dy * distance)
                    far = cast_page(lua, "flame_shot", dx * 2000, -40 + dy * 2000)
                    a, b = lua.eval("effect_params")(near), lua.eval("effect_params")(far)
                    for key in ("dx", "dy", "ox", "oy", "reach", "length", "frames"):
                        self.assertAlmostEqual(a[key], b[key])
                    lua.execute("simulate(20)")
                    self.assertTrue(lua.eval("EntityGetIsAlive")(near))
                    a = lua.eval("effect_params")(near)
                    self.assertGreater(a["head"], 30)
        lua = world_runtime()
        at_caster = cast_page(lua, "flame_shot", 0, -40)
        p = lua.eval("effect_params")(at_caster)
        self.assertEqual((p["dx"], p["dy"], p["ox"], p["oy"]), (1, 0, 8, -40))
        self.assertGreater(p["reach"], 100)

    def test_flame_source_follows_flow_instead_of_resampling(self):
        lua = world_runtime()
        effect = cast_page(lua, "flame_shot", 500, -40)
        lua.execute("simulate(20)")
        child = sources(lua, effect)[0]
        lua.eval("effect_set")(child, "fluid_x", 16)
        lua.eval("effect_set")(child, "fluid_y", 9)
        lua.eval("effect_set")(effect, "drag", 0)
        lua.execute('''
            function FlameFluid.step(s, p)
                for i=1,FlameFluid.width*FlameFluid.height do
                    s.solid[i], s.d[i] = false, 0.5
                    s.u[i] = (p.frame_velocity or p.velocity or p.speed) * FlameFluid.tuning.drift / s.cell - 3
                    s.v[i] = 4
                end
            end
            simulate(1)
        ''')
        trace = lua.eval("effect_params")(child)
        self.assertAlmostEqual(trace["fluid_x"], 16 - 3/60)
        self.assertAlmostEqual(trace["fluid_y"], 9 + 4/60)
        lua.eval("simulate")(1)
        trace = lua.eval("effect_params")(child)
        self.assertAlmostEqual(trace["fluid_x"], 16 - 3/30)
        self.assertAlmostEqual(trace["fluid_y"], 9 + 4/30)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_pressure_reduces_divergence(self):
        lua = world_runtime()
        before, after = lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local s = FlameFluid.new({length = 88, speed = 350}, 1)
            for y = 1, FlameFluid.height do for x = 1, FlameFluid.width do
                local i = (y-1)*FlameFluid.width+x
                s.u[i], s.v[i] = math.sin(x*0.3)*10, math.cos(y*0.4)*7
            end end
            local function divergence()
                local sum = 0
                for y = 3, FlameFluid.height - 2 do for x = 3, FlameFluid.width - 2 do
                    local i = (y-1)*FlameFluid.width+x
                    local d = (s.u[i+1]-s.u[i-1]+s.v[i+FlameFluid.width]-s.v[i-FlameFluid.width])/2
                    sum = sum + d*d
                end end
                return sum
            end
            local before = divergence()
            FlameFluid.project(s)
            return before, divergence()
        ''')
        self.assertLess(after, before * 0.7)

    def test_hot_gas_advects_and_cools_without_a_source(self):
        lua = world_runtime()
        before, after, initial_heat, heat = lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/fluid.lua")
            local p = {length=88, speed=350, r=6, head=140, tail=0,
                ox=0, oy=-40, dx=1, dy=0, stop=140}
            local s = FlameFluid.new(p, 1)
            s.d[(math.floor(FlameFluid.height/2)-1)*FlameFluid.width+16] = 1
            local function center()
                local sum, weighted = 0, 0
                for i,d in ipairs(s.d) do sum=sum+d; weighted=weighted+d*((i-1)%FlameFluid.width+1) end
                return weighted/sum, sum
            end
            local before, total = center()
            FlameFluid.step(s, p, 20, 2/60)
            local after, heat = center()
            return before, after, total, heat
        ''')
        self.assertLess(after, before - 0.1)
        self.assertGreater(heat, 0)
        self.assertLess(heat, initial_heat)

    def test_native_flame_is_bounded_and_has_evolving_vortices(self):
        lua = world_runtime()
        effect = cast_page(lua, "flame_shot", 500, -40)
        lua.execute("simulate(20)")
        first = list(lua.globals().FlameShot.states[effect].d.values())
        lua.execute("simulate(20)")
        state = lua.globals().FlameShot.states[effect]
        self.assertEqual(len(state.d), lua.globals().FlameFluid.width * lua.globals().FlameFluid.height)
        self.assertNotEqual(first, list(state.d.values()))
        self.assertGreater(max(state.curl.values()), 0.5)
        self.assertLess(min(state.curl.values()), -0.5)
        self.assertGreater(max(state.v.values()) - min(state.v.values()), 2)
        self.assertTrue(all(math.isfinite(v) for a in (state.d, state.u, state.v) for v in a.values()))
        self.assertLessEqual(len(sources(lua, effect)), 48)
        self.assertLessEqual(lua.eval("W.real_fire"), 16)
        for child in sources(lua, effect):
            c = lua.eval("EntityGetFirstComponent")(child, "ParticleEmitterComponent")
            get = lua.eval("ComponentGetValue2")
            self.assertEqual(get(c, "custom_style"), "FIRE")
            self.assertEqual(get(c, "emit_real_particles"), 1)
            self.assertEqual(get(c, "create_real_particles"), 0)
            self.assertEqual(get(c, "collide_with_grid"), 1)
            self.assertEqual(get(c, "count_min"), 1)
            self.assertLessEqual(get(c, "count_max"), 2)
        children = sources(lua, effect)
        lua.execute("simulate(160)")
        self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
        self.assertTrue(all(not lua.eval("EntityGetIsAlive")(c) for c in children))
        self.assertIsNone(lua.globals().FlameShot.states[effect])
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_liquid_blocks_motion_heat_sources_and_damage(self):
        lua = world_runtime()
        freeze_enemies(lua, ((50, -40), (105, -40), (150, -40)))
        lua.execute('''
            function RaytraceSurfacesAndLiquiform(x1,y1,x2,y2)
                if (x1-80)*(x2-80)<=0 and x1~=x2 then
                    return true,80,y1+(y2-y1)*(80-x1)/(x2-x1)
                end
                return false,x2,y2
            end
        ''')
        effect = cast_page(lua, "flame_shot", 220, -40)
        for _ in range(int(lua.eval("effect_params")(effect)["frames"]) + 2):
            lua.execute("simulate(1)")
            for child in sources(lua, effect):
                if lua.eval("EntityGetIsAlive")(child):
                    self.assertLess(lua.eval("EntityGetTransform")(child)[0], 80)
        self.assertNotIn(lua.eval("ENEMIES[2]"), {h["id"] for h in lua.eval("W.hits").values()})
        self.assertNotIn(lua.eval("ENEMIES[3]"), {h["id"] for h in lua.eval("W.hits").values()})
        self.assertFalse(lua.eval("EntityGetIsAlive")(effect))

    def test_reload_preserves_fluid_and_reuses_sources_between_ticks(self):
        for ticks in (20, 21):
            with self.subTest(ticks=ticks):
                live, restored = world_runtime(), world_runtime()
                a, b = cast_page(live, "flame_shot", 500), cast_page(restored, "flame_shot", 500)
                live.eval("simulate")(ticks)
                restored.eval("simulate")(ticks)
                pool = sources(restored, b)
                restored.globals().FlameShot.states[b] = None
                live.eval("simulate")(8)
                restored.eval("simulate")(8)
                left, right = live.globals().FlameShot.states[a], restored.globals().FlameShot.states[b]
                for field in ("d", "u", "v"):
                    self.assertLess(max(abs(x-y) for x,y in zip(left[field].values(), right[field].values())), 1e-5)
                self.assertEqual(sources(restored, b), pool)

    def test_aim_and_caster_movement_do_not_steer_existing_shot(self):
        live, baseline = world_runtime(), world_runtime()
        a, b = cast_page(live, "flame_shot", 500), cast_page(baseline, "flame_shot", 500)
        live.execute('EntitySetTransform(PLAYER, -100, -100); ComponentSetValue2(EntityGetFirstComponent(PLAYER, "ControlsComponent"), "mMousePosition", -300, 80)')
        live.eval("simulate")(20)
        baseline.eval("simulate")(20)
        self.assertEqual(live.eval("EntityGetTransform")(a), baseline.eval("EntityGetTransform")(b))
        self.assertEqual(list(live.globals().FlameShot.states[a].d.values()), list(baseline.globals().FlameShot.states[b].d.values()))


if __name__ == "__main__":
    unittest.main()
