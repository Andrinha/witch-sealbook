-- An element's nature where its shot ends (element_traits.lua): a flare of light, the fire round it put out, a cloud of
-- smoke, sparks. "witch_trait_end": which of them, "witch_trait_element": the element.
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )
dofile_once( "mods/witch_notebook/files/element_traits.lua" )

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local element = hit_var( e, "witch_trait_element" ) or "light"
local shooter = hit_shooter( e )
local A = TRAIT_AMOUNTS
for key in ( hit_var( e, "witch_trait_end" ) or "" ):gmatch( "%a+" ) do
	if key == "flare" then
		effect_spawn( "trait", "flare", x, y, { frames = A.flare_frames, element = element } )
	elseif key == "douse" then
		-- the fire round it goes out, and the creatures burning near it
		local douse = EntityCreateNew( "witch_douse" )
		EntitySetTransform( douse, x, y )
		EntityAddComponent2( douse, "MagicConvertMaterialComponent", { from_material_array = "fire,fire_blue", to_material_array = "steam,steam",
			radius = A.douse_r, is_circle = true, loop = false, kill_when_finished = true, steps_per_frame = 7 } )
		EntityAddComponent2( douse, "LifetimeComponent", { lifetime = 10 } )
		for _, id in ipairs( creatures_in( x, y, A.douse_r, 0, true ) ) do clear_effects( id, { "ON_FIRE" } ) end
	elseif key == "puff" then
		effect_spawn( "trait", "puff", x, y, { frames = A.puff_frames, r = A.puff_r, owner = shooter } )
	elseif key == "sparks" and DICTIONARY_LOOKS[element] then
		for i = 1, A.sparks do
			local a = ( i + Random( 0, 100 ) / 100 ) / A.sparks * 2 * math.pi
			local spark = EntityLoad( carrier_file( element, "splash" ), x, y )
			GameShootProjectile( shooter, x, y, x + math.cos( a ) * 100, y + math.sin( a ) * 100, spark, true )
		end
	end
end
