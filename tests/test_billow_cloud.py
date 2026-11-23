"""The Billow's cloud: what is drawn round the sigil shapes it. The element gives the cloud a temper (embers that
scorch, rain, snow, a storm that strikes), the signs feed it: Collection gathers it bigger billow by billow, its
inverse scatters it, Expansion heaps up more billows, Binding holds whoever climbs onto it, Mimicry makes it flow
after the cursor.

python tests/test_billow_cloud.py
"""
import unittest

from harness import world_runtime, cast_page, freeze_enemies
from fluid_render_capture import texture
from render_earth_builds import pieces


def boxes(lua):
    """every standing piece as (kind, left, top, right, bottom)"""
    out = []
    for path, x, y in pieces(lua):
        image = texture(path)
        kind = path.split("/")[-1][:-4]
        out.append((kind, x - image.width / 2, y - image.height / 2, x + image.width / 2, y + image.height / 2))
    return out


class Billow(unittest.TestCase):
    def cloud(self, extra="", tx=120, ty=-40):
        """the Billow's seal cast with 'extra' spell data (an element's sigil, signs); returns lua, the effect"""
        lua = world_runtime()
        lua.execute("GROUND = 10000")
        lua.globals().TEST_EXTRA, lua.globals().TEST_TX, lua.globals().TEST_TY = extra, tx, ty
        effect = lua.execute('''
            local data = "manifest=cloud;precision=1;stability=1" .. TEST_EXTRA
            return cast_spell(PLAYER, parse_spell_data(data), 0, -40, 1, 0, TEST_TX, TEST_TY, W.frame, nil)[1]
        ''')
        return lua, effect

    def held(self, lua, creature):
        """names of the held effects on a creature"""
        names = [lua.eval("EntityGetName")(child) for child in (lua.eval("EntityGetAllChildren")(creature) or {}).values()
                 if lua.eval("EntityGetIsAlive")(child)]
        return [name for name in names if name.startswith("witch_held_")]

    def test_a_lone_billow_is_one_white_cloud_that_grows_back(self):
        lua, effect = self.cloud()
        params = lua.eval("effect_params")(effect)
        self.assertEqual(params["mode"], "cloud")
        self.assertEqual(params["temper"], "plain")
        lua.execute("simulate(60)")
        built = boxes(lua)
        # One wide white cloud, no boulder: it hangs in the air where the cursor was.
        self.assertEqual([b[0] for b in built], ["cloud"])
        self.assertAlmostEqual((built[0][1] + built[0][3]) / 2, 120, delta=1)
        self.assertAlmostEqual((built[0][2] + built[0][4]) / 2, -40, delta=1)
        # A billow that is dug or blown away grows again.
        lua.execute('''
            for id, entity in pairs(W.entities) do
                if entity.alive and entity.file and entity.file:find("solid/cloud.xml") then EntityKill(id) end
            end
        ''')
        self.assertEqual(boxes(lua), [])
        lua.execute("simulate(61)")
        self.assertEqual([b[0] for b in boxes(lua)], ["cloud"])
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_expansion_heaps_up_billows_round_the_middle(self):
        lua, effect = self.cloud(extra=";b=grow:2")
        lua.execute("simulate(80)")
        built = boxes(lua)
        self.assertEqual(len(built), 5)
        self.assertEqual({b[0] for b in built}, {"cloud", "cloud_puff_l", "cloud_puff_m"})
        for kind, left, top, right, bottom in built:
            self.assertLessEqual(abs((left + right) / 2 - 120), 31)
        # the inverse sign leaves one lone wide cloud
        lua, effect = self.cloud(extra=";b=shrink:2")
        lua.execute("simulate(80)")
        self.assertEqual({b[0] for b in boxes(lua)}, {"cloud"})
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_collection_gathers_the_cloud_bigger_billow_by_billow(self):
        lua, effect = self.cloud(extra=";b=gather:2")
        lua.execute("simulate(60)")
        self.assertEqual(len(boxes(lua)), 1)
        # every four seconds another billow heaps up, until the heap is full
        lua.execute("simulate(240)")
        self.assertEqual(len(boxes(lua)), 2)
        lua.execute("simulate(2 * 240)")
        self.assertEqual(len(boxes(lua)), 4)
        lua.execute("simulate(2 * 240)")
        built = boxes(lua)
        self.assertEqual(len(built), 6)
        self.assertEqual({b[0] for b in built}, {"cloud", "cloud_puff_l", "cloud_puff_m", "cloud_puff_s"})
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_the_inverted_collection_and_the_gust_scatter_it_into_nothing(self):
        for extra in (";b=scatter:1", ";b=gust:1"):
            with self.subTest(extra=extra):
                lua, effect = self.cloud(extra=extra)
                lua.execute("simulate(60)")
                self.assertEqual(boxes(lua), [])
                self.assertFalse(lua.eval("EntityGetIsAlive")(effect))
                self.assertFalse(list(lua.eval("W.errors").values()))

    def test_an_ember_cloud_scorches_what_lies_on_and_beneath_it(self):
        lua, effect = self.cloud(extra=";element=fire")
        freeze_enemies(lua, ((120, -20), (120, -48), (400, -40)))
        lua.execute("simulate(200)")
        # its body is its own: a dark cloud of embers, not the plain white one
        self.assertEqual({b[0] for b in boxes(lua)}, {"ember_cloud"})
        self.assertEqual(lua.eval("effect_params")(effect)["temper"], "ember")
        # the beast beneath it smolders, the beast on top of it too, and catches fire
        hits = list(lua.eval("W.hits").values())
        beast, rider = lua.eval("ENEMIES[1]"), lua.eval("ENEMIES[2]")
        player = lua.eval("PLAYER")
        self.assertTrue(hits)
        self.assertTrue(all(h["kind"] == "DAMAGE_FIRE" and h["who"] == player for h in hits), hits)
        self.assertTrue(any(h["id"] == beast for h in hits) and any(h["id"] == rider for h in hits), hits)
        # the rider catches fire: the on-fire effect is on it
        children = list((lua.eval("EntityGetAllChildren")(rider) or {}).values())
        files = [lua.eval("W.entities")[c]["file"] for c in children]
        self.assertTrue(any("effect_apply_on_fire" in (f or "") for f in files), files)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_an_ember_cloud_crumbles_into_real_fire(self):
        lua, effect = self.cloud(extra=";element=fire")
        lua.execute("simulate(80)")
        lua.execute('''
            for id, entity in pairs(W.entities) do
                if entity.alive and entity.file and entity.file:find("ember_cloud") then EntityKill(id) end
            end
        ''')
        self.assertGreater(lua.eval("W.real_fire"), 0)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_a_rain_cloud_pours_real_water_and_hurts_no_one(self):
        lua, effect = self.cloud(extra=";element=water")
        freeze_enemies(lua, ((120, -20), (120, -48), (400, -40)))
        lua.execute('''
            RAINED = {}
            local particle = GameCreateParticle
            function GameCreateParticle(m, x, y, n, vx, vy, a, b, c)
                RAINED[#RAINED + 1] = m
                return particle(m, x, y, n, vx, vy, a, b, c)
            end
        ''')
        lua.execute("simulate(200)")
        # its body is its own: a grey rain cloud
        self.assertEqual({b[0] for b in boxes(lua)}, {"rain_cloud"})
        self.assertIn("water", list(lua.eval("RAINED").values()))
        # the rain only puts out fire, on whoever is under the cloud and on it; it strikes no one
        self.assertFalse(list(lua.eval("W.hits").values()))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_a_snow_cloud_is_a_slippery_cloud_of_ice(self):
        lua, effect = self.cloud(extra=";element=crystal")
        lua.execute('''
            RAINED = {}
            local particle = GameCreateParticle
            function GameCreateParticle(m, x, y, n, vx, vy, a, b, c)
                RAINED[#RAINED + 1] = m
                return particle(m, x, y, n, vx, vy, a, b, c)
            end
        ''')
        lua.execute("simulate(200)")
        built = boxes(lua)
        self.assertEqual({b[0] for b in built}, {"frost_cloud"})
        # the air round it freezes the water in it, and its body is ice: a cloud too slippery to keep one's footing on
        self.assertIn("snow", list(lua.eval("RAINED").values()))
        materials = set()
        for entity in lua.eval("W.entities").values():
            if entity.alive and entity.file and entity.file.endswith("frost_cloud.xml"):
                for cid in entity.comps.values():
                    comp = lua.eval("W.comps")[cid]
                    if comp["type"] == "PhysicsImageShapeComponent":
                        materials.add(comp["values"]["material"])
        self.assertEqual(materials, {"ice_glass_b2"})
        comps = lua.eval('EntityGetComponentIncludingDisabled')(effect, "MagicConvertMaterialComponent")
        values = lua.eval("W.comps")[list(comps.values())[0]]["values"]
        self.assertIn("water", values["from_material_array"])
        self.assertIn("ice_static", values["to_material_array"])
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_a_storm_cloud_strikes_what_comes_under_it(self):
        lua, effect = self.cloud(extra=";element=thunder")
        freeze_enemies(lua, ((120, -16), (400, -40), (500, -40)))
        lua.execute("simulate(300)")
        # its body is its own: a dark storm cloud
        self.assertEqual({b[0] for b in boxes(lua)}, {"storm_cloud"})
        hits = list(lua.eval("W.hits").values())
        beast = lua.eval("ENEMIES[1]")
        self.assertTrue(hits)
        self.assertTrue(all(h["id"] == beast and h["kind"] == "DAMAGE_ELECTRICITY" for h in hits), hits)
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_binding_holds_whoever_climbs_onto_the_cloud(self):
        lua, effect = self.cloud(extra=";b=hold:1")
        freeze_enemies(lua, ((120, -48), (400, -40), (500, -40)))
        lua.execute("simulate(200)")
        beast = lua.eval("ENEMIES[1]")
        self.assertEqual(self.held(lua, beast), ["witch_held_time"])
        # the witch who cast it is not held by their own cloud
        self.assertFalse(self.held(lua, lua.eval("PLAYER")))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_mimicry_makes_the_cloud_flow_after_the_cursor(self):
        lua, effect = self.cloud(extra=";b=mimic:1", tx=120, ty=-40)
        lua.execute("simulate(60)")
        self.assertEqual(len(boxes(lua)), 1)
        # the cursor has gone far away: the cloud dissolves and flows together again there
        controls = lua.eval('EntityGetFirstComponent(PLAYER, "ControlsComponent")')
        lua.eval("ComponentSetValue2")(controls, "mMousePosition", 260, -110)
        lua.execute("simulate(80)")
        built = boxes(lua)
        self.assertEqual(len(built), 1)
        self.assertAlmostEqual((built[0][1] + built[0][3]) / 2, 260, delta=1)
        self.assertAlmostEqual((built[0][2] + built[0][4]) / 2, -110, delta=1)
        self.assertTrue(lua.eval("EntityGetIsAlive")(effect))
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_the_drawn_seal_carries_the_element_to_the_cloud(self):
        """The path the player takes: a seal drawn stroke by stroke, read, cast - not data fed by hand"""
        from test_sign_effects import seal_tree
        lua = world_runtime()
        lua.execute("GROUND = 10000")
        compile = lua.eval("compile_spell")
        # the billow sigil alone: a soft white cloud of air, that crumbles into snow
        spell = compile(seal_tree(lua, ["billow"], []))
        self.assertEqual(spell["element"], "air")
        self.assertEqual(spell["manifest"], "cloud")
        # drawn round the fire sigil: a cloud of embers, its own body. Cast as the book would keep it, a
        # clean drawing's precision (a sloppy one misfires - that is the drawing's doing, not the reading's)
        spell = compile(seal_tree(lua, ["billow", "fire"], []))
        self.assertEqual(spell["element"], "fire")
        lua.globals().TEST_SPELL = spell
        lua.execute('''
            TEST_SPELL.precision, TEST_SPELL.stability = 1, 1
            TEST_DATA = serialize_spell(TEST_SPELL)
            for _, id in ipairs(ENEMIES) do EntityKill(id) end
            TEST_EFFECT = cast_spell(PLAYER, parse_spell_data(TEST_DATA), 0, -40, 1, 0, 120, -40, W.frame, nil)[1]
        ''')
        lua.execute("simulate(80)")
        self.assertEqual({b[0] for b in boxes(lua)}, {"ember_cloud"})
        self.assertFalse(list(lua.eval("W.errors").values()))

    def test_the_billow_cluster_page_gathers_a_sandy_heap(self):
        lua = world_runtime()
        lua.execute("GROUND = 10000")
        effect = cast_page(lua, "billow_cluster", 120, -40)
        self.assertEqual(lua.eval("effect_params")(effect)["temper"], "sand")
        lua.execute("simulate(80)")
        built = boxes(lua)
        # the page's own billows: one sandy cloud first
        self.assertEqual([b[0] for b in built], ["sand_cloud"])
        # its Collection signs gather it bigger, billow by billow
        lua.execute("simulate(5 * 240)")
        built = boxes(lua)
        self.assertEqual(len(built), 6)
        self.assertEqual({b[0] for b in built}, {"sand_cloud", "sand_puff_l", "sand_puff_m", "sand_puff_s"})
        self.assertFalse(list(lua.eval("W.errors").values()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
