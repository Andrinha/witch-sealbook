"""Continuous emissive gas reconstruction, visibility and full-sprite occlusion."""
import unittest

from PIL import Image

from harness import world_runtime, cast_page, wall
from fluid_render_capture import sprites, texture, draw_sprites


def wall_strip(kind):
    """A single uniformly hot row/column in air, six pixels from solid terrain."""
    lua = world_runtime()
    lua.globals().TEST_WALL = kind
    lua.execute('''
        local nx,ny=0,1
        if TEST_WALL=="ceiling" then ny=-1
        elseif TEST_WALL=="vertical" then nx,ny=1,0
        elseif TEST_WALL=="slope" then nx=0.5 end
        if TEST_WALL~="air" then
            function RaytraceSurfacesAndLiquiform(x1,y1,x2,y2)
                local a,b=nx*x1+ny*y1,nx*x2+ny*y2
                if a>=0 then return true,x1,y1 end
                if b>=0 then local t=-a/(b-a);return true,x1+(x2-x1)*t,y1+(y2-y1)*t end
                return false,x2,y2
            end
        end
        dofile_once("mods/witch_notebook/files/effects/flame_fields.lua")
        F=FlameFields.presets.ring.model
        P={ox=0,oy=0,head=0,dx=1,dy=0,speed=0,cell=4}
        S=F.new(P,1);S.entity=EntityCreateNew("wall strip");F.mask(S,P)
        for y=5,28 do for x=5,28 do
            local i=(y-1)*32+x
            local wx,wy=F.world(S,P,x,y)
            local distance=nx*wx+ny*wy
            if not S.solid[i] and distance>=-8 and distance<=-4 then S.d[i]=1.8 end
        end end
    ''')
    return lua


class FluidDraw(unittest.TestCase):
    def test_uniform_hot_gas_is_continuous_with_a_fixed_draw_budget(self):
        lua = world_runtime()
        count = lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/flame_fields.lua")
            local F=FlameFields.presets.ring.model
            local p={ox=0,oy=0,head=0,dx=1,dy=0,speed=0,cell=2}
            local s=F.new(p,1);s.entity=EntityCreateNew("test gas");F.mask(s,p)
            for y=5,28 do for x=5,28 do s.d[(y-1)*32+x]=1.1 end end
            return FlameFluidDraw.draw(s,{},p,{pixels=512})
        ''')
        samples = sprites(lua)
        self.assertEqual(count, len(samples))
        self.assertLessEqual(count, 512)
        self.assertGreater(count, 0)
        canvas = draw_sprites(Image.new("RGB", (96, 96)), samples, 48, 48)
        for sample in samples:
            values = lua.globals().W.comps[sample.component]["values"]
            self.assertFalse(values.additive)
            self.assertGreater(values.z_index, 0, "The world grid must hide the body")
            self.assertTrue(values.emissive)
            self.assertTrue(values.smooth_filtering)
        # An interior solid sheet must have no pinholes or disconnected dots.
        red = list(canvas.crop((29, 29, 67, 67)).getchannel("R").getdata())
        self.assertGreater(min(red), 180)
        self.assertLess(max(red) - min(red), 35)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_glowing_sprite_footprints_fit_before_a_thin_wall(self):
        for key in ("flame_shot", "flame_burst", "ring_of_fire", "forbidden_flames", "pyreball"):
            with self.subTest(spell=key):
                lua = world_runtime()
                barrier = {"flame_shot": 145, "flame_burst": 100, "ring_of_fire": 18,
                           "forbidden_flames": 92, "pyreball": 62}[key]
                wall(lua, barrier)
                samples = []
                cast_page(lua, key, 90 if key == "forbidden_flames" else 500)
                for _ in range(24):
                    lua.eval("simulate")(1)
                    samples.extend(sprites(lua, layer=None))
                self.assertTrue(samples)
                # A kernel may touch the wall's face; it must never reach past it.
                self.assertTrue(all(s.x + texture(s.path).width * s.scale / 2 <= barrier for s in samples))
                self.assertFalse(list(lua.eval("W.errors").values()))

    def test_new_water_removes_the_entire_visible_field_on_the_next_frame(self):
        lua = world_runtime()
        samples = []
        lua.globals().GameCreateCosmeticParticle = lambda *args: samples.append(args)
        cast_page(lua, "ring_of_fire")
        lua.eval("simulate")(1)
        self.assertTrue(samples or sprites(lua))
        samples.clear()
        lua.execute('''
            function RaytraceSurfacesAndLiquiform(x,y) return true,x,y end
            simulate(1)
        ''')
        self.assertFalse(samples)
        self.assertFalse(sprites(lua, layer=None))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_invisible_ink_and_ring_tail_reduce_visible_radiance(self):
        lua = world_runtime()
        lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/flame_fields.lua")
            F=FlameFields.presets.ring.model
            P={ox=0,oy=0,head=0,dx=1,dy=0,speed=0,cell=2}
            S=F.new(P,1);S.entity=EntityCreateNew("test gas");F.mask(S,P);S.d[500]=1.8
        ''')
        radiance = []
        for hidden, alpha in ((0, 1), (1, 1), (0, 0.25)):
            lua.globals().TEST_HIDDEN, lua.globals().TEST_ALPHA = hidden, alpha
            lua.execute('FlameFluidDraw.draw(S,{hidden=TEST_HIDDEN},P,{pixels=512},TEST_ALPHA)')
            radiance.append(sum(sample.alpha * sum((r + g + b) * a for r, g, b, a in texture(sample.path).getdata())
                                for sample in sprites(lua, layer=None)))
        self.assertGreater(radiance[0], 0)
        self.assertLess(radiance[1], radiance[0] * 0.3)
        self.assertLess(radiance[2], radiance[0] * 0.4)

    def test_cold_glow_never_darkens_hot_gas_or_bright_sky(self):
        lua = world_runtime()
        lua.execute('''
            dofile_once("mods/witch_notebook/files/effects/flame_fields.lua")
            local F=FlameFields.presets.ring.model
            local p={ox=0,oy=0,head=0,dx=1,dy=0,speed=0,cell=4}
            local s=F.new(p,1);s.entity=EntityCreateNew("test gas");F.mask(s,p)
            for y=5,28 do for x=5,28 do
                s.d[(y-1)*32+x]=(x%2==0 and 0.12 or 1.8)
            end end
            FlameFluidDraw.draw(s,{},p,{pixels=1024})
        ''')
        samples = sprites(lua, layer="glow")
        sky = Image.new("RGB", (192, 192), (91, 169, 204))
        hot = [s for s in samples if "_7.png" in s.path]
        self.assertTrue(hot)
        heated = draw_sprites(sky.copy(), hot, 96, 96)
        all_gas = draw_sprites(sky.copy(), samples, 96, 96)
        reverse = draw_sprites(sky.copy(), list(reversed(samples)), 96, 96)
        self.assertEqual(all_gas.tobytes(), reverse.tobytes())
        self.assertTrue(all(a >= b for a, b in zip(all_gas.tobytes(), heated.tobytes())))
        self.assertTrue(all(a >= b for a, b in zip(all_gas.tobytes(), sky.tobytes())))

    def test_visual_pool_is_bounded_reused_and_removed_with_its_owner(self):
        lua = world_runtime()
        e = cast_page(lua, "ring_of_fire")
        lua.eval("simulate")(10)
        visual = [v for v in lua.globals().W.entities.values() if v.alive and v.tags["witch_fluid_fire_visual"]]
        self.assertEqual(len(visual), 1)
        first = {s.component for s in sprites(lua)}
        self.assertTrue(first)
        lua.execute("FlameFields.states={}")
        lua.eval("simulate")(1)
        self.assertTrue(first.intersection(s.component for s in sprites(lua)))
        visual = [v for v in lua.globals().W.entities.values() if v.alive and v.tags["witch_fluid_fire_visual"]]
        self.assertEqual(len(visual), 1)
        self.assertLessEqual(len(list(visual[0].comps.values())), 1024)
        lua.eval("EntityKill")(e)
        self.assertFalse(sprites(lua))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_glow_energy_does_not_grow_with_kernel_overlap_or_cell_size(self):
        for cell, budget in ((2, 1024), (2, 256), (5, 512), (7, 256)):
            with self.subTest(cell=cell, budget=budget):
                lua = world_runtime()
                lua.globals().TEST_CELL, lua.globals().TEST_BUDGET = cell, budget
                count = lua.execute('''
                    dofile_once("mods/witch_notebook/files/effects/flame_fields.lua")
                    local F=FlameFields.presets.ring.model
                    P={ox=0,oy=0,head=0,dx=1,dy=0,speed=0,cell=TEST_CELL}
                    S=F.new(P,1);S.entity=EntityCreateNew("test gas");F.mask(S,P)
                    for y=5,28 do for x=5,28 do S.d[(y-1)*32+x]=1.1 end end
                    return FlameFluidDraw.draw(S,{},P,{pixels=TEST_BUDGET})
                ''')
                samples = sprites(lua, layer="glow")
                self.assertEqual(len(samples), count)
                self.assertLessEqual(count, budget)
                energy = sum(s.alpha * s.scale * s.scale_y * sum(texture(s.path).getchannel("A").getdata()) / 255
                             for s in samples)
                self.assertAlmostEqual(energy / (576 * cell ** 2), 0.12 * 0.95, delta=0.01)
                # A static field can be drawn again without rebuilding sprites.
                lua.execute('''
                    function EntityCreateNew() error("Steady drawing allocated an entity") end
                    function EntityAddComponent2() error("Steady drawing allocated a component") end
                    FlameFluidDraw.draw(S,{},P,{pixels=TEST_BUDGET})
                ''')
                self.assertFalse(list(lua.eval("W.errors").values()))

    def test_loading_a_field_already_submerged_hides_saved_visuals(self):
        lua = world_runtime()
        cast_page(lua, "ring_of_fire")
        lua.eval("simulate")(4)
        self.assertTrue(sprites(lua, layer=None))
        lua.execute('''
            FlameFields.states={}
            function RaytraceSurfacesAndLiquiform(x,y) return true,x,y end
            simulate(1)
        ''')
        self.assertFalse(sprites(lua, layer=None))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_hot_wall_strip_keeps_a_continuous_tangent_and_no_brightness_boost(self):
        air = wall_strip("air")
        air.execute('FlameFluidDraw.draw(S,{},P,{pixels=512})')
        reference = sprites(air)[0].alpha
        for kind in ("floor", "ceiling", "vertical"):
            with self.subTest(wall=kind):
                lua = wall_strip(kind)
                before = list(lua.globals().S.d.values())
                lua.execute('FlameFluidDraw.draw(S,{},P,{pixels=512})')
                samples = sprites(lua)
                self.assertTrue(samples)
                self.assertEqual(before, list(lua.globals().S.d.values()))
                # Thick terrain hides the body, which may reach this far under it.
                spill = lua.eval("FlameFluidDraw.spill")
                for s in samples:
                    width, height = texture(s.path).width*s.scale, texture(s.path).height*s.scale_y
                    if kind == "vertical":
                        self.assertGreater(height, 12)
                        self.assertLessEqual(width, height)
                        self.assertLessEqual(s.x + width/2, spill)
                    else:
                        self.assertGreater(width, 12)
                        self.assertLessEqual(height, width)
                        if kind == "floor":
                            self.assertLessEqual(s.y + height/2, spill)
                        else:
                            self.assertGreaterEqual(s.y-height/2, -spill)
                    self.assertLessEqual(s.alpha, reference + 1e-9)
                canvas = draw_sprites(Image.new("RGB", (128, 128)), samples, 64, 64)
                row = ((58, 32, 59, 96) if kind == "vertical" else
                       (32, 70, 96, 71) if kind == "ceiling" else (32, 58, 96, 59))
                red = list(canvas.crop(row).getchannel("R").getdata())
                self.assertGreater(min(red), 100)
                self.assertGreater(min(red)/max(red), 0.9, "A uniformly hot wall edge must not form bright beads")
                self.assertFalse(list(lua.eval("W.errors").values()))

    def test_diagonal_wall_does_not_leak_through_rectangle_corners(self):
        lua = wall_strip("slope")
        lua.execute('FlameFluidDraw.draw(S,{},P,{pixels=512})')
        spill = lua.eval("FlameFluidDraw.spill")
        samples = sprites(lua, layer=None)
        self.assertTrue(samples)
        for s in samples:
            w, h = texture(s.path).width*s.scale/2, texture(s.path).height*s.scale_y/2
            # Rows are proved along their center line; this analytic slope is
            # not pixel-aligned, so allow half a pixel row beyond the hidden
            # reach under thick terrain and nothing more.
            self.assertLessEqual(0.5*(s.x+w)+s.y+h, 0.5 + 1.5*spill)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_unproved_narrow_gap_pixels_do_not_concentrate_sheet_radiance(self):
        lua = wall_strip("air")
        alpha = []
        lua.globals().GameCreateCosmeticParticle = lambda m,x,y,n,vx,vy,c,*args: alpha.append((int(c)>>24)&255)
        lua.execute('''
            S.open_air=false
            F.clear=function() return false end
            F.span=function() return nil end
            FlameFluidDraw.draw(S,{},P,{pixels=512})
        ''')
        self.assertTrue(alpha)
        self.assertLess(max(alpha), 16)
        self.assertFalse(sprites(lua, layer=None))
        self.assertFalse(list(lua.eval("W.errors").values()))


if __name__ == "__main__":
    unittest.main()
