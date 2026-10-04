"""In-game instrumentation, VM transport, pause handling and bounded history."""
import unittest
from fluid_render_capture import sprites

from harness import world_runtime, cast_page, wall


def enable(lua):
    lua.execute('''
        function ModSettingGet(key) return key=="witch_notebook.performance_profiler" end
        W.clock=0
        function GameGetRealWorldTimeSinceStarted() W.clock=W.clock+0.00001;return W.clock end
    ''')


class EffectProfiler(unittest.TestCase):
    def test_disabled_profiler_never_uses_clock_or_exports_rows(self):
        lua=world_runtime()
        lua.execute('function GameGetRealWorldTimeSinceStarted() error("Disabled profiler used a clock") end')
        cast_page(lua,"flame_shot",500,-40)
        lua.eval("simulate")(10)
        self.assertEqual(lua.eval('GlobalsGetValue("witch_notebook.perf_frame","")'),"")
        self.assertIsNone(lua.globals().EffectProfiler.row)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_instrumentation_counts_real_rays_and_stages_in_air_and_at_a_wall(self):
        for barrier in (None,145):
            with self.subTest(wall=barrier):
                lua=world_runtime();enable(lua)
                lua.execute("for _,id in ipairs(ENEMIES) do EntityKill(id) end")
                if barrier is not None:
                    wall(lua,barrier)
                effects=[cast_page(lua,"flame_shot",500,-40) for _ in range(2)]
                lua.execute('''
                    W.rays,W.pixels=0,0
                    local ray=RaytraceSurfacesAndLiquiform
                    function RaytraceSurfacesAndLiquiform(...)
                        W.rays=W.rays+1;return ray(...)
                    end
                    local draw=GameCreateCosmeticParticle
                    function GameCreateCosmeticParticle(m,x,y,n,...)
                        W.pixels=W.pixels+n;return draw(m,x,y,n,...)
                    end
                    simulate(1)
                ''')
                profile=lua.globals().EffectProfiler
                row,index=profile.row,profile.index
                self.assertEqual(row[index["updates"]],2)
                self.assertEqual(row[index["solver_ticks"]],2)
                self.assertEqual(row[index["new_sources"]],24)
                self.assertEqual(row[index["rays"]],lua.eval("W.rays"))
                self.assertEqual(row[index["pixels"]],lua.eval("W.pixels") + len(sprites(lua)))
                self.assertGreater(row[index["snapshot_bytes"]],50000)
                for stage in ("params","restore","mask","pressure","density","emitters","draw","save","lua"):
                    self.assertGreater(row[index[stage]],0,stage)
                self.assertTrue(all(lua.globals().FlameShot.states[e].meter is None for e in effects))
                self.assertFalse(list(lua.eval("W.errors").values()))

    def test_world_callback_receives_another_vms_row_and_skips_stale_frames(self):
        producer,consumer=world_runtime(),world_runtime()
        enable(producer);enable(consumer)
        cast_page(producer,"flame_shot",500,-40)
        producer.eval("simulate")(1)
        consumer.globals().GlobalsGetValue=lambda key,default="": producer.eval("GlobalsGetValue")(key,default)
        consumer.globals().W.frame=producer.eval("GameGetFrameNum")()
        consumer.execute('dofile_once("mods/witch_notebook/files/effects/profiler.lua");EffectProfiler.world_update()')
        profile=consumer.globals().EffectProfiler
        self.assertEqual(profile.samples[1][profile.index["updates"]],1)
        consumer.execute("W.frame=W.frame+1;EffectProfiler.world_update()")
        self.assertEqual(profile.samples[2][profile.index["updates"]],0)
        self.assertGreater(profile.samples[2].dt,0)

    def test_history_is_bounded_and_pause_does_not_become_a_stutter(self):
        lua=world_runtime();enable(lua)
        lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/profiler.lua")
            function GameGetRealWorldTimeSinceStarted() return W.clock end
            for frame=1,301 do
                W.frame=frame;W.clock=W.clock+1/60;EffectProfiler.world_update()
            end
            EffectProfiler.pause();W.clock=W.clock+20
            W.frame=302;EffectProfiler.world_update()
        ''')
        profile=lua.globals().EffectProfiler
        self.assertEqual(len(profile.samples),300)
        self.assertEqual(profile.samples[profile.cursor].dt,0)
        self.assertLess(max(row.dt for row in profile.samples.values()),17)
        self.assertIn("Frames ms",lua.eval('GlobalsGetValue("witch_notebook.perf_report","")'))
        lua.execute('''
            function ModSettingGet() return false end
            EffectProfiler.next_check=nil;EffectProfiler.world_update()
        ''')
        self.assertIsNone(profile.samples)

    def test_new_game_clears_the_previous_runs_history(self):
        lua=world_runtime();enable(lua)
        lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/profiler.lua")
            EffectProfiler.world_update()
            W.frame=W.frame+1;W.clock=W.clock+1;EffectProfiler.world_update()
            W.frame=0;EffectProfiler.world_update()
        ''')
        profile=lua.globals().EffectProfiler
        self.assertEqual(len(profile.samples),1)
        self.assertEqual(profile.samples[1].dt,0)
        self.assertEqual(profile.next_summary,30)

    def test_first_cast_is_retained_after_it_leaves_the_rolling_window(self):
        lua=world_runtime();enable(lua)
        cast_page(lua,"flame_shot",500,-40)
        lua.eval("simulate")(1)
        lua.execute('''
            local frame=W.frame
            EffectProfiler.world_update()
            for i=1,301 do W.frame=frame+i;EffectProfiler.world_update() end
        ''')
        profile=lua.globals().EffectProfiler
        self.assertEqual(profile.first_cast[profile.index.starts],1)
        self.assertLess(profile.first_cast[1],min(row[1] for row in profile.samples.values()))
        self.assertIn("First cast:","\n".join(profile.summary().values()))

    def test_unavailable_heap_is_not_reported_as_zero_memory(self):
        lua=world_runtime();enable(lua)
        lua.execute('function collectgarbage() return 0 end')
        cast_page(lua,"flame_shot",500,-40)
        lua.eval("simulate")(1)
        lua.execute("EffectProfiler.world_update()")
        self.assertIn("heap=n/a","\n".join(lua.globals().EffectProfiler.summary().values()))

    def test_profiling_does_not_change_the_simulation(self):
        off,on=world_runtime(),world_runtime();enable(on)
        a,b=cast_page(off,"flame_shot",500,-40),cast_page(on,"flame_shot",500,-40)
        off.eval("simulate")(40);on.eval("simulate")(40)
        for field in ("d","u","v"):
            self.assertEqual(list(off.globals().FlameShot.states[a][field].values()),
                             list(on.globals().FlameShot.states[b][field].values()))


if __name__=="__main__":
    unittest.main()
