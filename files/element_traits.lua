-- What an element is like beyond its damage and its look: on the mod's own shots, orbs and drops (cast.lua) its natures
-- (resonances.lua RESONANCE_NATURES; a mix is both its elements) show in how it flies and in what it leaves where it ends:
--   airy - it passes through creatures, knocking each one back
--   earthen - it bounces once before it breaks
--   cold - water it passes freezes
--   ghostly - it passes through walls
--   bright - where it ends it flares up, lighting the place for a while
--   wet - where it ends it puts out fire, and the creatures burning near it
--   murky - where it ends it bursts into a cloud of smoke that blinds whoever is in it
--   sparkling - where it ends it bursts into sparks
-- A splash's drops take only what is light (bouncing, freezing, walls): passing through is Piercing's there, and the
-- flares, clouds and sparks are a shot's and an orb's. A resonance's twist comes after them and may change them (Ricochet bounces more).
--   element_traits( element, splash ) -> { key = true } of what it has, in TRAIT_ORDER
--   element_traits_apply( projectile, element, splash ) - on a projectile just shot (cast.lua spawn)

dofile_once( "mods/witch_notebook/files/resonances.lua" )

-- the nature each trait comes from, the words the notes tell it in, and whether a splash's drops have it
ELEMENT_TRAITS = {
	{ key = "pass", nature = "airy", text = "passes through creatures, knocking each back" },
	{ key = "bounce", nature = "earthen", text = "bounces once before it breaks", drops = true },
	{ key = "freeze", nature = "cold", text = "freezes the water it passes", drops = true },
	{ key = "phase", nature = "ghostly", text = "passes through walls", drops = true },
	{ key = "flare", nature = "bright", text = "flares up where it ends, lighting the place" },
	{ key = "douse", nature = "wet", text = "puts out fire where it ends" },
	{ key = "puff", nature = "murky", text = "bursts into blinding smoke where it ends" },
	{ key = "sparks", nature = "sparkling", text = "bursts into sparks where it ends" },
}
TRAIT_AMOUNTS = { knock = 40, freeze_r = 3, flare_frames = 120, douse_r = 14, puff_r = 18, puff_frames = 150, sparks = 5 }
TRAIT_CARRIERS = { bolt = true, orb = true, hover = true } -- what they show on (a splash's drops are bolts)

function element_traits( element, splash )
	local natures, out = RESONANCE_NATURES[element] or {}, {}
	for _, t in ipairs( ELEMENT_TRAITS ) do
		if natures[t.nature] and ( t.drops or not splash ) then out[t.key] = true end
	end
	return out
end

local FREEZES_WATER = { from = "water,water_salt,water_swamp,swamp", to = "ice_static,ice_static,ice_static,ice_static" }

function element_traits_apply( projectile, element, splash )
	local traits = element_traits( element, splash )
	local proj = EntityGetFirstComponentIncludingDisabled( projectile, "ProjectileComponent" )
	if not proj or not next( traits ) then return traits end
	if traits.pass then
		ComponentSetValue2( proj, "penetrate_entities", true )
		ComponentSetValue2( proj, "knockback_force", ComponentGetValue2( proj, "knockback_force" ) + TRAIT_AMOUNTS.knock )
	end
	if traits.bounce and ComponentGetValue2( proj, "bounces_left" ) == 0 then
		ComponentSetValue2( proj, "bounces_left", 1 )
		ComponentSetValue2( proj, "bounce_energy", 0.5 )
		ComponentSetValue2( proj, "bounce_at_any_angle", true )
	end
	if traits.freeze then
		EntityAddComponent2( projectile, "MagicConvertMaterialComponent", { from_material_array = FREEZES_WATER.from,
			to_material_array = FREEZES_WATER.to, radius = TRAIT_AMOUNTS.freeze_r, is_circle = true, loop = true,
			kill_when_finished = false, steps_per_frame = 2 } )
	end
	if traits.phase then ComponentSetValue2( proj, "collide_with_world", false ) end
	local ends = {}
	for _, key in ipairs( { "flare", "douse", "puff", "sparks" } ) do if traits[key] then ends[#ends + 1] = key end end
	if #ends > 0 then
		EntityAddComponent2( projectile, "VariableStorageComponent", { name = "witch_trait_end", value_string = table.concat( ends, "," ) } )
		EntityAddComponent2( projectile, "VariableStorageComponent", { name = "witch_trait_element", value_string = element } )
		EntityAddComponent2( projectile, "LuaComponent", { script_source_file = "mods/witch_notebook/files/behaviors/trait_end.lua",
			execute_on_removed = true, execute_every_n_frame = -1 } )
	end
	return traits
end
