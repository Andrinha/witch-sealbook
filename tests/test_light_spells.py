"""Light seal regressions: harmless illumination, pressure stones and linked items."""
import random
import unittest
import xml.etree.ElementTree as ET

from fluid_render_capture import texture
from harness import world_runtime, cast_page, freeze_enemies, real_path
import wiki_spells as Wiki

KEYS = ("floatglow", "floatglow_anchored", "light_beam", "glowstone_path",
        "bird_of_light", "ancient_light_beacon", "light_tracer", "flowers_of_light",
        "leech_of_light", "carousel")


def still_player(lua, x=-100, y=-40):
    lua.execute('EntityRemoveComponent(PLAYER, EntityGetFirstComponent(PLAYER, "CharacterDataComponent"))')
    lua.eval("EntitySetTransform")(lua.eval("PLAYER"), x, y)


def item(lua, name, x, y, group=None):
    e = lua.eval("EntityCreateNew")(name)
    lua.eval("EntitySetTransform")(e, x, y)
    lua.eval("EntityAddTag")(e, "item_pickup")
    if group:
        lua.eval("effect_set")(e, "witch_fragment_group", group)
        lua.eval("EntityAddTag")(e, "witch_light_fragment")
    return e


def hold_book(lua):
    e = lua.eval("EntityCreateNew")("held book")
    lua.eval("EntityAddTag")(e, "witch_spellbook")
    lua.eval("EntityAddChild")(lua.eval("PLAYER"), e)
    inv = lua.eval("EntityGetFirstComponent")(lua.eval("PLAYER"), "Inventory2Component")
    lua.eval("ComponentSetValue2")(inv, "mActiveItem", e)
    return e


class LightSpells(unittest.TestCase):
    def fog_sprites(self, lua, e):
        return [c for c in (lua.eval("EntityGetComponent")(e, "SpriteComponent") or {}).values()
                if lua.eval("ComponentGetValue2")(c, "fog_of_war_hole")]

    def test_all_light_spells_reveal_at_their_sources_and_clean_up(self):
        for key in KEYS:
            with self.subTest(key=key):
                lua = world_runtime()
                still_player(lua)
                if key == "glowstone_path":
                    lua.execute("GROUND = 10")
                if key == "light_tracer":
                    item(lua, "fragment", 200, -40)
                e = cast_page(lua, key)
                lua.execute("simulate(24)")
                lights = list(lua.eval("EntityGetComponent")(e, "LightComponent").values())
                masks = self.fog_sprites(lua, e)
                self.assertEqual(len(masks), len(lights))
                for light, mask in zip(lights, masks):
                    self.assertTrue(lua.eval("ComponentGetValue2")(light, "update_properties"))
                    radius = lua.eval("ComponentGetValue2")(light, "radius")
                    self.assertEqual(lua.eval("ComponentGetValue2")(mask, "visible"), radius > 0)
                    self.assertAlmostEqual(lua.eval("ComponentGetValue2")(mask, "special_scale_x"), max(.001, radius / 64))
                    dx = lua.eval("ComponentGetValue2")(light, "offset_x")
                    dy = lua.eval("ComponentGetValue2")(light, "offset_y")
                    self.assertEqual(lua.eval("ComponentGetValue2")(mask, "transform_offset"), (dx, dy))
                lua.eval("EntityKill")(e)
                lua.execute("simulate(1)")
                self.assertFalse(lua.eval("EntityGetIsAlive")(e))
                self.assertFalse(list(lua.eval("W.errors").values()))
                # Local fog masks are on the light entity, not a perk on the player.
                self.assertFalse(self.fog_sprites(lua, lua.eval("PLAYER")))

    def test_beacon_reveal_centers_follow_lit_height_below_ceiling(self):
        lua = world_runtime()
        lua.execute('''
            function RaytraceSurfaces(x1,y1,x2,y2)
                if y2 <= -110 and y1 > -110 then return true,x1,-110 end
                return false,x2,y2
            end
        ''')
        e = cast_page(lua, "ancient_light_beacon", tx=0, ty=-200)
        lua.execute("simulate(30)")
        masks = self.fog_sprites(lua, e)
        self.assertGreater(len(masks), 1)
        active = [c for c in masks if lua.eval("ComponentGetValue2")(c, "visible")]
        self.assertEqual(len(active), 2)
        for c in active:
            dx, dy = lua.eval("ComponentGetValue2")(c, "transform_offset")
            self.assertEqual(dx, 0)
            self.assertGreaterEqual(-40 + dy, -110)

    def test_fog_follows_bird_and_remote_fragments_and_turns_off_on_unlink(self):
        lua = world_runtime()
        still_player(lua)
        bird = cast_page(lua, "bird_of_light")
        lua.execute("simulate(25)")
        self.assertTrue(self.fog_sprites(lua, bird))
        before = lua.eval("EntityGetTransform")(bird)[:2]
        lua.execute("simulate(25)")
        self.assertNotEqual(lua.eval("EntityGetTransform")(bird)[:2], before)
        item(lua, "first", 80, -40)
        other = item(lua, "second", 150, -40)
        e = cast_page(lua, "light_tracer", 80)
        cast_page(lua, "light_tracer", 150)
        lua.execute("simulate(2)")
        self.assertEqual(len(self.fog_sprites(lua, e)), 2)
        lua.eval("EntitySetTransform")(other, 170, -50)
        lua.execute("simulate(1)")
        masks = self.fog_sprites(lua, e)
        self.assertIn((90, -10), [lua.eval("ComponentGetValue2")(c, "transform_offset") for c in masks])
        lua.eval("EntityKill")(other)
        lua.execute("simulate(1)")
        self.assertEqual(sum(bool(lua.eval("ComponentGetValue2")(c, "visible")) for c in masks), 1)

    def test_new_and_saved_pages_are_harmless_and_expire(self):
        for key in KEYS:
            for legacy in (False, True):
                with self.subTest(key=key, legacy=legacy):
                    lua = world_runtime()
                    still_player(lua, 0, -20)
                    freeze_enemies(lua, ((20, -40), (100, -40), (150, -40)))
                    if key == "light_tracer":
                        item(lua, "fragment", 200, -40)
                    e = cast_page(lua, key, legacy=legacy)
                    self.assertIsNotNone(e)
                    self.assertFalse(lua.eval("EntityGetFirstComponent")(e, "ProjectileComponent"))
                    lua.eval("effect_set")(e, "frames", 160)
                    lua.execute("simulate(180)")
                    self.assertFalse(lua.eval("EntityGetIsAlive")(e))
                    self.assertFalse(list(lua.eval("W.hits").values()))
                    self.assertEqual(lua.eval("W.real_fire"), 0)
                    self.assertFalse(list(lua.eval("W.errors").values()))

    def test_beams_follow_mouse_and_terrain_blocks_particles(self):
        for key in ("light_beam", "ancient_light_beacon"):
            for tx, ty in ((200, -40), (-200, -40), (120, -200), (0, 200)):
                with self.subTest(key=key, target=(tx, ty)):
                    lua = world_runtime()
                    still_player(lua)
                    # A wall perpendicular to the aim vector at distance 80.
                    dx, dy = tx, ty + 40
                    d = (dx * dx + dy * dy) ** .5
                    dx, dy = dx / d, dy / d
                    lua.globals().DX, lua.globals().DY = dx, dy
                    lua.execute('''
                        function RaytraceSurfaces(x1,y1,x2,y2)
                            local a = x1*DX + (y1+40)*DY
                            local b = x2*DX + (y2+40)*DY
                            if a < 80 and b >= 80 then
                                local t = (80-a)/(b-a)
                                return true,x1+(x2-x1)*t,y1+(y2-y1)*t
                            end
                            return false,x2,y2
                        end
                    ''')
                    e = cast_page(lua, key, tx=tx, ty=ty)
                    dots = []
                    lua.globals().GameCreateCosmeticParticle = lambda material,x,y,*args: dots.append((x,y))
                    lua.execute("simulate(35)")
                    self.assertTrue(dots)
                    along = [x*dx+(y+40)*dy for x,y in dots]
                    across = [-x*dy+(y+40)*dx for x,y in dots]
                    self.assertGreater(max(along), 75)
                    self.assertLessEqual(max(along), 80)
                    self.assertLessEqual(max(abs(v) for v in across), 10.01)
                    for c in self.fog_sprites(lua, e):
                        if lua.eval("ComponentGetValue2")(c, "visible"):
                            x,y = lua.eval("ComponentGetValue2")(c, "transform_offset")
                            self.assertLessEqual(x*dx+y*dy, 80)
                    self.assertFalse(list(lua.eval("W.errors").values()))

    def test_recasting_turns_beam_and_blocking_hides_old_fog(self):
        lua = world_runtime()
        still_player(lua)
        e = cast_page(lua, "light_beam", tx=200, ty=-40)
        lua.execute("simulate(30)")
        self.assertEqual(cast_page(lua, "light_beam", tx=0, ty=-200), e)
        lua.execute("simulate(1)")
        masks = self.fog_sprites(lua, e)
        self.assertTrue(any(lua.eval("ComponentGetValue2")(c, "transform_offset")[1] < -50 for c in masks))
        self.assertTrue(all(lua.eval("ComponentGetValue2")(c, "transform_offset")[0] == 0 for c in masks))
        lua.execute('''
            function RaytraceSurfaces(x1,y1,x2,y2)
                return true,x1,y1
            end
        ''')
        lua.execute("simulate(1)")
        self.assertFalse(any(lua.eval("ComponentGetValue2")(c, "visible") for c in masks))

    def test_glowstones_only_light_under_feet_and_fade(self):
        lua = world_runtime()
        still_player(lua)
        freeze_enemies(lua, ((400, -40), (450, -40), (500, -40)))
        lua.execute("GROUND = 10")
        e = cast_page(lua, "glowstone_path")
        lua.execute("simulate(5)")
        lights = list(lua.eval("EntityGetComponent")(e, "LightComponent").values())
        radii = lambda: [lua.eval("ComponentGetValue2")(c, "radius") for c in lights]
        self.assertEqual(len(lights), 12)
        self.assertEqual(radii(), [0] * 12)
        self.assertFalse(any(lua.eval("ComponentGetValue2")(c, "visible") for c in self.fog_sprites(lua, e)))
        # Passing overhead does not press a stone.
        lua.eval("EntitySetTransform")(lua.eval("PLAYER"), 11, -10)
        lua.execute("simulate(8)")
        self.assertEqual(radii(), [0] * 12)
        lua.eval("EntitySetTransform")(lua.eval("PLAYER"), 11, 7)
        lua.execute("simulate(8)")
        self.assertEqual(sum(r > 0 for r in radii()), 1)
        self.assertEqual(sum(bool(lua.eval("ComponentGetValue2")(c, "visible")) for c in self.fog_sprites(lua, e)), 1)
        lua.eval("EntitySetTransform")(lua.eval("PLAYER"), -100, -40)
        lua.execute("simulate(190)")
        self.assertEqual(radii(), [0] * 12)
        self.assertFalse(any(lua.eval("ComponentGetValue2")(c, "visible") for c in self.fog_sprites(lua, e)))

    def test_tracer_links_selected_items_and_follows_pickup(self):
        lua = world_runtime()
        still_player(lua, 0, -20)
        hold_book(lua)
        first = item(lua, "first", 80, -40)
        other = item(lua, "second", 150, -40)
        treasure = item(lua, "unmarked", 40, -40)
        e = cast_page(lua, "light_tracer", 80)
        lua.execute("simulate(5)")
        self.assertEqual(cast_page(lua, "light_tracer", 150), e)
        self.assertTrue(lua.eval("EntityHasTag")(other, "witch_light_fragment"))
        self.assertFalse(lua.eval("EntityHasTag")(treasure, "witch_light_fragment"))
        dots = []
        lua.globals().GameCreateCosmeticParticle = lambda material,x,y,*args: dots.append((x,y))
        lua.execute("simulate(35)")
        self.assertLessEqual(max(x for x,y in dots), 152.5)
        self.assertLess(min(x for x,y in dots), 5)
        self.assertGreaterEqual(min(x for x,y in dots), 0)
        lua.eval("EntityAddChild")(lua.eval("PLAYER"), first)
        lua.eval("EntitySetTransform")(lua.eval("PLAYER"), -30, -20)
        lua.execute("simulate(1)")
        self.assertEqual(lua.eval("EntityGetTransform")(e)[:2], (-30, -20))
        lua.eval("EntityKill")(first)
        lua.execute("simulate(1)")
        self.assertTrue(lua.eval("EntityGetIsAlive")(e))
        self.assertEqual(lua.eval("effect_params")(e)["source"], other)
        lua.eval("EntityKill")(other)
        lua.execute("simulate(1)")
        self.assertFalse(lua.eval("EntityGetIsAlive")(e))

    def test_tracer_shows_first_target_and_can_select_third_and_fourth(self):
        lua = world_runtime()
        still_player(lua, 0, -34)
        hold_book(lua)
        targets = [item(lua, str(x), x, -40) for x in (80, 150, 310, 420)]
        dots = []
        lua.globals().GameCreateCosmeticParticle = lambda material,x,y,*args: dots.append((x,y))
        e = None
        for target, x in zip(targets, (80, 150, 310, 420)):
            with self.subTest(x=x):
                chosen = cast_page(lua, "light_tracer", tx=x, ty=-40)
                if e is None:
                    e = chosen
                self.assertEqual(chosen, e)
                self.assertEqual(lua.eval("effect_params")(e)["focus"], target)
                dots.clear()
                lua.execute("simulate(1)")
                self.assertTrue(any(abs(px - x/2) <= 1 and abs(py+40) <= .1 for px,py in dots))
                self.assertTrue(any(abs(px-x) <= 1 for px,py in dots))
                self.assertTrue(lua.eval("EntityHasTag")(target, "witch_light_fragment"))
        # Moving the latest target and caster updates the guidance ray.
        lua.eval("EntitySetTransform")(targets[-1], 500, -60)
        lua.eval("EntitySetTransform")(lua.eval("PLAYER"), 100, -54)
        dots.clear()
        lua.execute("simulate(1)")
        self.assertTrue(any(abs(px-300) <= 1 and abs(py+60) <= .1 for px,py in dots))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_tracer_does_not_clamp_cursor_or_reuse_dead_source(self):
        lua = world_runtime()
        first = item(lua, "first", 80, -40)
        e = cast_page(lua, "light_tracer", 80)
        lua.eval("EntityKill")(first)
        other = item(lua, "second", 310, -40)
        self.assertEqual(cast_page(lua, "light_tracer", 310), e)
        lua.execute("simulate(1)")
        self.assertTrue(lua.eval("EntityGetIsAlive")(e))
        self.assertEqual(lua.eval("effect_params")(e)["source"], other)
        near_edge = item(lua, "edge", 445, -40)
        self.assertIsNone(cast_page(lua, "light_tracer", 700))
        self.assertFalse(lua.eval("EntityHasTag")(near_edge, "witch_light_fragment"))

    def test_tracer_repeated_clicks_through_spellbook_controls(self):
        lua = world_runtime()
        still_player(lua, 0, -36)
        lua.execute('''
            TEST_BOOK = EntityCreateNew("book")
            EntityAddComponent2(TEST_BOOK, "VariableStorageComponent", {
                name = SPELLBOOK_NEXT_CAST_VAR, value_int = 0 })
            GlobalsSetValue(book_var("book", "active_spell"),
                seal_page_data({named = "light_tracer", precision = 1, stability = 1}))
        ''')
        controls = lua.eval("EntityGetFirstComponent")(lua.eval("PLAYER"), "ControlsComponent")
        e = None
        for x in (80, 150, 310, 420):
            target = item(lua, str(x), x, -40)
            lua.eval("ComponentSetValue2")(controls, "mMousePosition", x, -40)
            made = lua.eval("spellbook_use")(lua.eval("TEST_BOOK"), lua.eval("PLAYER"), controls, lua.eval("W.frame"))
            self.assertIsNotNone(made)
            if e is None:
                e = made[1]
            self.assertEqual(made[1], e)
            self.assertEqual(lua.eval("effect_params")(e)["focus"], target)
            # the seal recharges by its tier (cast.lua seal_cast_delay)
            lua.execute('simulate( seal_cast_delay( BOOKS.book, parse_spell_data( GlobalsGetValue( book_var( "book", "active_spell" ) ) ) ) )')
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_tracer_respects_fragment_lineage_and_empty_aim(self):
        lua = world_runtime()
        a = item(lua, "a", 80, -40, "broken:A")
        item(lua, "b", 120, -40, "broken:A")
        item(lua, "c", -200, -40, "broken:B")
        e = cast_page(lua, "light_tracer", 80)
        lua.execute("simulate(1)")
        self.assertEqual(lua.eval("effect_params")(e)["group"], "broken:A")
        self.assertEqual(lua.eval("effect_params")(e)["source"], a)
        self.assertIsNone(cast_page(lua, "light_tracer", 200))

    def test_tracer_selects_vanilla_crates_barrels_and_stones(self):
        lua = world_runtime()
        still_player(lua)
        # EntityLoad's stub does not inherit Base tags. Apply the actual XML
        # tags recursively, as Noita does, rather than inventing pickup tags.
        def inherited_tags(path):
            root = ET.parse(real_path(path)).getroot()
            tags = set(filter(None, root.get("tags", "").split(",")))
            for base in root.findall("Base"):
                tags.update(inherited_tags(base.get("file")))
            return tags

        names = ("physics_box_explosive", "physics_box_harmless", "physics_crate",
                 "physics_barrel_oil", "physics_barrel_water", "physics_barrel_radioactive",
                 "physics_barrel_burning", "physics_stone_01")
        e = None
        selected = []
        for i, name in enumerate(names):
            with self.subTest(prop=name):
                path = "data/entities/props/" + name + ".xml"
                x = 50 + 40 * i
                prop = lua.eval("EntityLoad")(path, x, -40)
                for tag in inherited_tags(path):
                    lua.eval("EntityAddTag")(prop, tag)
                self.assertTrue(lua.eval("EntityHasTag")(prop, "prop_physics"))
                self.assertFalse(lua.eval("EntityHasTag")(prop, "item_pickup"))
                chosen = cast_page(lua, "light_tracer", x)
                self.assertIsNotNone(chosen)
                if e is None:
                    e = chosen
                self.assertEqual(chosen, e)
                self.assertEqual(lua.eval("effect_params")(e)["focus"], prop)
                selected.append(prop)
                lua.execute("simulate(1)")
        self.assertTrue(all(lua.eval("EntityGetIsAlive")(prop) for prop in selected))
        self.assertFalse(list(lua.eval("W.hits").values()))
        self.assertEqual(lua.eval("W.real_fire"), 0)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_tracer_physics_items_exclude_inventory_and_mortal_only_entities(self):
        lua = world_runtime()
        still_player(lua)
        prop = lua.eval("EntityCreateNew")("physics item")
        lua.eval("EntitySetTransform")(prop, 80, -40)
        lua.eval("EntityAddTag")(prop, "item_physics")
        self.assertIsNotNone(cast_page(lua, "light_tracer", 80))
        lua.eval("EntityAddChild")(lua.eval("PLAYER"), prop)
        self.assertIsNone(cast_page(lua, "light_tracer", 80))
        enemy = lua.eval("EntityCreateNew")("creature")
        lua.eval("EntitySetTransform")(enemy, 310, -40)
        for tag in ("mortal", "hittable"):
            lua.eval("EntityAddTag")(enemy, tag)
        self.assertIsNone(cast_page(lua, "light_tracer", 310))
        self.assertFalse(lua.eval("EntityHasTag")(enemy, "witch_light_fragment"))

    def test_tracer_selects_untagged_carts_with_either_physics_component(self):
        lua = world_runtime()
        still_player(lua)
        e = None
        for i, name in enumerate(("physics_cart", "physics_minecart", "physics/minecart")):
            x = 80 + 80*i
            cart = lua.eval("EntityLoad")("data/entities/props/" + name + ".xml", x, -40)
            self.assertFalse(lua.eval("EntityGetTags")(cart))
            chosen = cast_page(lua, "light_tracer", x)
            self.assertIsNotNone(chosen)
            e = chosen if e is None else e
            self.assertEqual(chosen, e)
            self.assertEqual(lua.eval("effect_params")(e)["focus"], cart)
        lua.execute("simulate(1)")
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_tracer_tracks_body_without_entity_reuses_marker_and_cleans_up(self):
        lua = world_runtime()
        still_player(lua)
        # No entity represents this body, as with the current biome minecart.
        # API coordinates are Box2D units, not pixels; use a nontrivial scale.
        lua.execute('''
            TEST_BODIES = { [16909061] = { x = 4, y = -2 } }
            function PhysicsBodyIDQueryBodies(x1,y1,x2,y2)
                local ids = {}
                for id,b in pairs(TEST_BODIES) do
                    if b.x*20 >= x1 and b.x*20 <= x2 and b.y*20 >= y1 and b.y*20 <= y2 then ids[#ids+1] = id end
                end
                return ids
            end
            function PhysicsBodyIDGetWorldCenter(id)
                local b = TEST_BODIES[id]
                if b then return b.x,b.y end
            end
            function PhysicsPosToGamePos(x,y) return x*20,y*20 end
        ''')
        item(lua, "item", 200, -40)
        e = cast_page(lua, "light_tracer", 200)
        self.assertEqual(cast_page(lua, "light_tracer", 80), e)
        markers = list(lua.eval('EntityGetWithTag("witch_light_body_marker")').values())
        self.assertEqual(len(markers), 1)
        marker = markers[0]
        self.assertEqual(lua.eval("effect_params")(marker)["witch_tracer_body"], "16909061")
        self.assertEqual(lua.eval("EntityGetParent")(marker), e)
        lua.execute("simulate(1)")
        self.assertEqual(lua.eval("EntityGetTransform")(marker)[:2], (80, -40))
        self.assertEqual(cast_page(lua, "light_tracer", 80), e)
        self.assertEqual(len(list(lua.eval('EntityGetWithTag("witch_light_body_marker")').values())), 1)
        lua.execute("TEST_BODIES[16909061].x = 6; TEST_BODIES[16909061].y = -3; simulate(1)")
        self.assertEqual(lua.eval("EntityGetTransform")(marker)[:2], (120, -60))
        offsets = [lua.eval("ComponentGetValue2")(c, "transform_offset") for c in self.fog_sprites(lua, e)]
        self.assertIn((-80,-20), offsets)
        lua.execute("TEST_BODIES[16909061] = nil; simulate(1)")
        self.assertFalse(lua.eval("EntityGetIsAlive")(marker))
        self.assertTrue(lua.eval("EntityGetIsAlive")(e))
        lua.execute("TEST_BODIES[16909061] = {x=4,y=-2}")
        self.assertEqual(cast_page(lua, "light_tracer", 80), e)
        marker = list(lua.eval('EntityGetWithTag("witch_light_body_marker")').values())[0]
        lua.eval("effect_set")(e, "frames", 1)
        lua.execute("simulate(1)")
        self.assertFalse(lua.eval("EntityGetIsAlive")(marker))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_tracer_renews_base_25_seconds_and_expires_after_last_cast(self):
        lua = world_runtime()
        still_player(lua)
        a = item(lua, "a", 80, -40)
        b = item(lua, "b", 200, -40)
        # power=1, lifetime=0 is the base duration; normal modifiers still apply.
        lua.globals().TEST_A, lua.globals().TEST_B = a,b
        lua.execute('''
            function tracer_at(x)
                return MANIFESTS.tracer({shooter=PLAYER, spell={behaviors={}}, power=1,
                    x=0,y=-40,tx=x,ty=-40})[1]
            end
            TEST_TRACER = tracer_at(80)
        ''')
        e = lua.eval("TEST_TRACER")
        self.assertEqual(lua.eval("effect_params")(e)["frames"], 1500)
        lua.execute("simulate(1); W.frame = W.frame+1400")
        self.assertEqual(lua.eval("tracer_at")(200), e)
        lua.execute("simulate(1)")
        born = lua.eval("effect_params")(e)["born"]
        renewed_until = born + lua.eval("effect_params")(e)["frames"]
        self.assertEqual(renewed_until, lua.eval("W.frame") + 1499)
        lua.globals().W.frame = renewed_until - 2
        lua.execute("simulate(1)")
        self.assertTrue(lua.eval("EntityGetIsAlive")(e))
        lua.execute("simulate(1)")
        self.assertFalse(lua.eval("EntityGetIsAlive")(e))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_tracer_body_fallback_excludes_carried_objects(self):
        lua = world_runtime()
        still_player(lua)
        carried = lua.eval("EntityCreateNew")("carried physics object")
        lua.eval("EntitySetTransform")(carried, 80, -40)
        lua.eval("EntityAddComponent2")(carried, "PhysicsBodyComponent", lua.table())
        lua.eval("EntityAddChild")(lua.eval("PLAYER"), carried)
        lua.globals().TEST_CARRIED = carried
        lua.execute('''
            function PhysicsBodyIDGetFromEntity(id)
                return id == TEST_CARRIED and {37} or {}
            end
            function PhysicsBodyIDQueryBodies() return {37} end
            function PhysicsBodyIDGetWorldCenter(id) return 4,-2 end
            function PhysicsPosToGamePos(x,y) return x*20,y*20 end
        ''')
        self.assertIsNone(cast_page(lua, "light_tracer", 80))
        self.assertFalse(list(lua.eval('EntityGetWithTag("witch_light_body_marker")').values()))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_tracer_connects_every_pair_and_book_controls_caster_rays(self):
        lua = world_runtime()
        still_player(lua, 0, -34)
        positions = ((80, -40), (160, -110), (240, -10))
        targets = [item(lua, str(i), *pos) for i, pos in enumerate(positions)]
        e = None
        for x,y in positions:
            chosen = cast_page(lua, "light_tracer", x, y)
            e = chosen if e is None else e
            self.assertEqual(chosen, e)
        dots = []
        lua.globals().GameCreateCosmeticParticle = lambda material,x,y,*args: dots.append((x,y))

        def near(x, y):
            return any((px-x)**2+(py-y)**2 < 2.5**2 for px,py in dots)

        def frame():
            dots.clear()
            lua.execute("simulate(1)")

        # No book: all three target pairs, including the pair excluding the first.
        frame()
        for i, (x,y) in enumerate(positions):
            for tx,ty in positions[i+1:]:
                self.assertTrue(near((x+tx)/2, (y+ty)/2))
        self.assertFalse(near(40, -40))
        self.assertFalse(near(80, -75))
        self.assertFalse(near(120, -25))

        book = hold_book(lua)
        frame()
        # Book: the caster connects to every target, not only the latest.
        for x,y in positions:
            self.assertTrue(near(x/2, (y-40)/2))
        inv = lua.eval("EntityGetFirstComponent")(lua.eval("PLAYER"), "Inventory2Component")
        for active in (lua.eval("INVENTORY[3]"), 0, book):
            lua.eval("ComponentSetValue2")(inv, "mActiveItem", active)
            frame()
            self.assertEqual(near(40, -40), active == book)
            self.assertTrue(near(200, -60))
        # Destroying the original target leaves the other pair intact.
        lua.eval("EntityKill")(targets[0])
        frame()
        self.assertTrue(lua.eval("EntityGetIsAlive")(e))
        self.assertTrue(near(200, -60))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_tracer_marks_enemies_and_follows_motion_without_damage(self):
        lua = world_runtime()
        still_player(lua)
        freeze_enemies(lua, ((80, -40), (200, -40), (300, -100)))
        enemies = list(lua.eval("ENEMIES").values())
        a = item(lua, "item", 150, -100)
        e = cast_page(lua, "light_tracer", 150, -100)
        for enemy in enemies:
            x,y = lua.eval("EntityGetTransform")(enemy)[:2]
            self.assertEqual(cast_page(lua, "light_tracer", x, y), e)
            self.assertTrue(lua.eval("EntityHasTag")(enemy, "witch_light_fragment"))
        dots = []
        lua.globals().GameCreateCosmeticParticle = lambda material,x,y,*args: dots.append((x,y))
        lua.execute("simulate(1)")
        self.assertTrue(any(abs(x-140) < 2 and abs(y+40) < 2 for x,y in dots))
        lua.eval("EntitySetTransform")(enemies[1], 200, -160)
        dots.clear()
        lua.execute("simulate(1)")
        self.assertTrue(any(abs(x-140) < 2 and abs(y+100) < 2 for x,y in dots))
        self.assertFalse(list(lua.eval("W.hits").values()))
        for enemy in enemies:
            hp = lua.eval("ComponentGetValue2")(lua.eval("EntityGetFirstComponent")(enemy, "DamageModelComponent"), "hp")
            self.assertEqual(hp, 2)
        self.assertIsNone(cast_page(lua, "light_tracer", -100, -40))
        self.assertFalse(lua.eval("EntityHasTag")(lua.eval("PLAYER"), "witch_light_fragment"))
        lua.eval("EntityKill")(a)
        lua.execute("simulate(1)")
        self.assertTrue(lua.eval("EntityGetIsAlive")(e))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_tracer_keeps_groups_separate_and_has_no_first_target_range_filter(self):
        lua = world_runtime()
        still_player(lua)
        item(lua, "a", -300, -40, "A")
        item(lua, "b", 100, -40, "A")
        item(lua, "c", 250, -40, "A")
        item(lua, "other group", -100, -200, "B")
        cast_page(lua, "light_tracer", -300)
        dots = []
        lua.globals().GameCreateCosmeticParticle = lambda material,x,y,*args: dots.append((x,y))
        lua.execute("simulate(1)")
        self.assertTrue(any(abs(x-175) < 2 and abs(y+40) < .1 for x,y in dots))
        self.assertTrue(all(abs(y+40) < 3 for x,y in dots))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_tracer_large_group_keeps_every_pair_with_reduced_particle_density(self):
        lua = world_runtime()
        still_player(lua)
        freeze_enemies(lua, ((600, -40), (650, -40), (700, -40)))
        for row in range(4):
            for col in range(4):
                x,y = 70 + 55*col, -180 + 55*row
                item(lua, str((row,col)), x,y)
                self.assertIsNotNone(cast_page(lua, "light_tracer", x,y))
        core = []
        dots = []
        def particle(material,x,y,count,vx,vy,packed,*args):
            dots.append((x,y))
            if int(packed) & 0xFFFFFFFF == 0xE5FFFFFF:
                core.append((x,y))
        lua.globals().GameCreateCosmeticParticle = particle
        lua.execute("simulate(1)")
        # All 120 unique pairs receive core samples, beyond the former limit
        # of twelve links. Sparse samples share the frame's particle budget.
        self.assertEqual(len(core), 1800)
        self.assertLess(len(dots), 3500)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_leech_stays_decorative_and_recasting_renews_sources(self):
        lua = world_runtime()
        still_player(lua)
        freeze_enemies(lua, ((140, -40), (140, -40), (140, -40)))
        e = cast_page(lua, "leech_of_light")
        lua.execute("simulate(60)")
        self.assertEqual(lua.eval("EntityGetTransform")(e)[:2], (140, -40))
        self.assertFalse(lua.eval("effect_params")(e)["host"])
        self.assertEqual(cast_page(lua, "leech_of_light"), e)
        self.assertEqual(len(list(lua.eval("EntityGetComponent")(e, "LightComponent").values())), 1)
        self.assertFalse(list(lua.eval("W.hits").values()))
        # A short beam, a lamp and an ancient beacon are distinct sources.
        beam = cast_page(lua, "light_beam")
        lamp = cast_page(lua, "floatglow", 0)
        ancient = cast_page(lua, "ancient_light_beacon")
        self.assertEqual(len({beam, lamp, ancient}), 3)

    def lamp(self, key, wall=None, tx=100):
        """A world with a lamp cast at tx, an optional wall, and its captured sprites and sounds."""
        lua = world_runtime()
        still_player(lua)
        if wall:
            lua.globals().WALL_X = wall
            lua.execute('''
                function RaytraceSurfaces(x1, y1, x2, y2)
                    if WALL_X and (x1 - WALL_X) * (x2 - WALL_X) <= 0 and x1 ~= x2 then
                        return true, WALL_X, y1 + (y2 - y1) * (WALL_X - x1) / (x2 - x1)
                    end
                    return false, x2, y2
                end
            ''')
        drawn, sounds = [], []
        lua.globals().GameCreateSpriteForXFrames = lambda path, x, y, *rest: drawn.append((path, x, y))
        lua.globals().GamePlaySound = lambda bank, event, *rest: sounds.append(event)
        e = cast_page(lua, key, tx)
        self.assertEqual(lua.eval("effect_params")(e)["mode"], "lamp")
        lua.eval("effect_set")(e, "frames", 120)
        return lua, e, drawn, sounds

    def parts(self, drawn):
        """name -> [(left, top, size)], checking every part lands on whole pixels (or it would blur)."""
        parts = {}
        for path, x, y in drawn:
            image = texture(path)
            left, top = x - image.width / 2, y - image.height / 2
            self.assertEqual((left, top), (round(left), round(top)))
            parts.setdefault(path.split("floatglow_")[-1][:-4], []).append((round(left), round(top), image.size))
        drawn.clear()
        return parts

    def trays(self, lua):
        return list(lua.eval("EntityGetWithTag")("witch_lamp_tray").values())

    def test_floatglow_lantern_flies_after_its_caster_and_is_renewed_not_doubled(self):
        lua, e, drawn, sounds = self.lamp("floatglow", wall=112)
        player = lua.eval("PLAYER")
        gaps = []
        for frame in range(119):
            if frame == 60:
                lua.eval("EntitySetTransform")(player, 60, -80)
            lua.execute("simulate(1)")
            self.assertTrue(lua.eval("EntityGetIsAlive")(e))
            parts = self.parts(drawn)
            self.assertEqual((len(parts["tray"]), len(parts["cone"])), (1, 1))
            # A lantern has no wall bracket and no body in the world.
            self.assertNotIn("plate", parts)
            (tray_x, tray_y, _), (cone_x, cone_y, cone) = parts["tray"][0], parts["cone"][0]
            self.assertEqual(cone_x + 3, tray_x + 6)
            gaps.append(tray_y - (cone_y + cone[1] - 1))
            if frame == 59:
                # It hangs beside the caster's head: the cursor does not place it.
                x, y = lua.eval("EntityGetTransform")(e)[:2]
                px, py = lua.eval("EntityGetTransform")(player)[:2]
                self.assertLessEqual(abs(x - px), 16.5)
                self.assertGreaterEqual(abs(x - px), 11.5)
                self.assertAlmostEqual(y, py - 24, delta=1)
                before = (x, y)
            if frame == 61:
                # It flies there, at most six pixels a frame; it does not jump.
                x, y = lua.eval("EntityGetTransform")(e)[:2]
                moved = ((x - before[0]) ** 2 + (y - before[1]) ** 2) ** 0.5
                self.assertGreater(moved, 2)
                self.assertLessEqual(moved, 12.01)
        x, y = lua.eval("EntityGetTransform")(e)[:2]
        self.assertLessEqual(abs(x - 60), 16.5)
        self.assertAlmostEqual(y, -104, delta=1)
        self.assertFalse(self.trays(lua))
        # Shut when lit and when going out; open in between.
        self.assertEqual(gaps[0], 0)
        self.assertLessEqual(gaps[-1], 2)
        self.assertGreaterEqual(min(gaps[30:90]), 14)
        # A lamp lights quietly, and a second cast renews the one lantern.
        self.assertEqual(sounds, [])
        self.assertEqual(cast_page(lua, "floatglow", -300), e)
        self.assertGreater(lua.eval("effect_params")(e)["frames"], 120)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_lantern_stops_at_walls_and_reappears_when_left_far_behind(self):
        lua, e, drawn, sounds = self.lamp("floatglow", wall=40)
        lua.eval("effect_set")(e, "frames", 1000)
        lua.execute("simulate(60)")
        player = lua.eval("PLAYER")
        lua.eval("EntitySetTransform")(player, 150, -40)
        lua.execute("simulate(90)")
        # The wall at x = 40 stands between them.
        self.assertLess(lua.eval("EntityGetTransform")(e)[0], 40)
        lua.eval("EntitySetTransform")(player, 600, -40)
        lua.execute("simulate(2)")
        x, y = lua.eval("EntityGetTransform")(e)[:2]
        self.assertLessEqual(abs(x - 600), 16.5)
        self.assertAlmostEqual(y, -64, delta=1)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_anchored_lamp_hangs_on_a_wall_bracket_until_the_wall_is_gone(self):
        for wall in (112, -112):
            with self.subTest(wall=wall):
                lua, e, drawn, sounds = self.lamp("floatglow_anchored", wall, 100 if wall > 0 else -100)
                gaps = []
                for frame in range(60):
                    lua.execute("simulate(1)")
                    parts = self.parts(drawn)
                    (tray,) = self.trays(lua)
                    # The tray is a body in the world, not a sprite, held still on its bracket.
                    self.assertNotIn("tray", parts)
                    self.assertIsNone(lua.eval("W.entities")[tray].static)
                    tx, ty = lua.eval("EntityGetTransform")(tray)[:2]
                    left, rim = round(tx - 6.5), round(ty - 2.5)
                    (cone_x, cone_y, cone), = parts["cone"]
                    self.assertEqual(cone_x + 3, left + 6)
                    gaps.append(rim - (cone_y + cone[1] - 1))
                    (plate, _, _), = parts["plate"]
                    # The plate lies against the wall's face, never inside it.
                    self.assertEqual(plate + 2 if wall > 0 else plate, wall)
                    # An unbroken arm joins the tray's foot to the plate.
                    arm = sorted(x for x, y, _ in parts["link"] if y == rim + 4)
                    self.assertEqual(arm, list(range(arm[0], arm[-1] + 1)))
                    self.assertEqual(arm[0] if wall > 0 else arm[-1], left + (8 if wall > 0 else 4))
                    self.assertEqual(arm[-1] + 1 if wall > 0 else arm[0] - 2, plate)
                self.assertEqual(gaps[0], 0)
                self.assertGreaterEqual(min(gaps[30:]), 14)
                # Dig the wall away: within half a second the tray is let go, for good.
                lua.execute("WALL_X = nil; simulate(31)")
                self.assertIs(lua.eval("W.entities")[tray].static, False)
                self.assertNotIn("plate", self.parts(drawn))
                lua.globals().WALL_X = wall
                lua.execute("simulate(31)")
                self.assertNotIn("plate", self.parts(drawn))
                self.assertEqual(sounds, [])
                self.assertFalse(list(lua.eval("W.errors").values()))

    def test_anchored_lamp_without_a_wall_drops_its_tray_and_floats_over_it(self):
        lua, e, drawn, sounds = self.lamp("floatglow_anchored")
        lua.execute("simulate(2)")
        (tray,) = self.trays(lua)
        self.assertIs(lua.eval("W.entities")[tray].static, False)
        self.assertEqual(lua.eval("EntityGetTransform")(tray)[:2], (100.5, -29.5))
        lua.execute("simulate(40)")
        self.parts(drawn)
        # The tray falls and is kicked aside: the top and the light go with it.
        lua.eval("EntitySetTransform")(tray, 131.5, 7.5)
        lua.execute("simulate(1)")
        parts = self.parts(drawn)
        (cone_x, cone_y, cone), = parts["cone"]
        # The top floats sixteen or seventeen pixels over the rim as it bobs.
        self.assertEqual(cone_x, 128)
        self.assertIn(cone_y + cone[1] - 1, (5 - 16, 5 - 17))
        self.assertNotIn("plate", parts)
        x, y = lua.eval("EntityGetTransform")(e)[:2]
        self.assertEqual(x, 131)
        self.assertAlmostEqual(y, 5 - 8, delta=1.6)
        # A reload forgets entity ids: the lamp finds its own tray by its key and lets it go again.
        other = cast_page(lua, "floatglow_anchored", 60)
        lua.execute("simulate(2)")
        self.assertEqual(len(self.trays(lua)), 2)
        lua.eval("W.entities")[tray].static = None
        lua.execute('dofile("mods/witch_notebook/files/effects/light.lua"); simulate(1)')
        self.assertEqual(len(self.trays(lua)), 2)
        self.assertIs(lua.eval("W.entities")[tray].static, False)
        self.assertEqual(lua.eval("EntityGetTransform")(e)[0], 131)
        # The tray goes with the lamp when the seal runs out...
        lua.eval("effect_set")(other, "frames", 3)
        lua.execute("simulate(3)")
        self.assertFalse(lua.eval("EntityGetIsAlive")(other))
        self.assertEqual(self.trays(lua), [tray])
        # ...and the lamp goes out when its tray is destroyed.
        lua.eval("EntityKill")(tray)
        lua.execute("simulate(1)")
        self.assertFalse(lua.eval("EntityGetIsAlive")(e))
        self.assertEqual(sounds, [])
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_lamp_saved_before_it_had_a_tray_gets_one_where_it_hangs(self):
        lua = world_runtime()
        still_player(lua)
        e = lua.execute('''
            local e = effect_spawn("light", "lamp", 100, -40, {owner = PLAYER, frames = 600, y0 = -40, element = "light", reveal = 1})
            EntityAddTag(e, "witch_light_source")
            simulate(50)
            return e
        ''')
        (tray,) = self.trays(lua)
        self.assertEqual(lua.eval("EntityGetTransform")(tray)[:2], (100.5, -29.5))
        self.assertTrue(lua.eval("EntityGetIsAlive")(e))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_light_pages_recognize_and_flower_redraw_survives_hand_copy(self):
        lua = Wiki.load()
        rng = random.Random(710)
        for key in KEYS:
            with self.subTest(key=key):
                entry = lua.eval("GRIMOIRE_BY_KEY")[key]
                base = Wiki.page(lua, entry)
                self.assertEqual(Wiki.read(lua, base)[0], key)
                if key in ("flowers_of_light", "ancient_light_beacon"):
                    self.assertEqual(entry["symbols"], "")
                    self.assertNotIn(";b=", entry["spell"])
                    if key == "flowers_of_light":
                        self.assertEqual(lua.eval("MANIFEST_NAMES.bloom"), "flowers")
                    drawings = [Wiki.by_hand(base, rng) for _ in range(8)]
                    drawings += [Wiki.as_player(base, rng, False) for _ in range(8)]
                    good = sum(Wiki.read(lua, d)[0] == key for d in drawings)
                    self.assertGreaterEqual(good, 14)

    def test_renewal_before_first_update_uses_duration_not_world_age(self):
        lua = world_runtime()
        lua.execute("W.frame = 100000")
        e = cast_page(lua, "carousel")
        duration = lua.eval("effect_params")(e)["frames"]
        self.assertEqual(cast_page(lua, "carousel"), e)
        self.assertEqual(lua.eval("effect_params")(e)["frames"], duration)
        lua.execute("simulate(30)")
        self.assertEqual(cast_page(lua, "carousel"), e)
        self.assertAlmostEqual(lua.eval("effect_params")(e)["frames"], duration + 29)


if __name__ == "__main__":
    unittest.main()
