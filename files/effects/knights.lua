-- The price of forbidden magic (cast.lua): after a while the Knights Moralis come for whoever cast it - here the
-- Holy Mountain's guardian (Stevari) stands in for them, stepping out of a flash of light near the caster.

local MODES = {}

MODES.come = function( e, p, age, x, y )
	local owner = effect_owner( p )
	if not owner then
		EntityKill( e )
		return
	end
	local ox, oy = EntityGetTransform( owner )
	local delay = p.delay or 240
	if age < delay then
		-- a warning: a pale seal turns in the sky over the caster, closer and closer
		if age % 3 == 0 then
			local r = 30 * ( 1 - age / delay ) + 8
			fx_ring( ox, oy - 60, r, color_abgr_merge( 230, 230, 255, 160 ), 18, 0, 0.1 )
		end
		return
	end
	local side = Random( 0, 1 ) == 0 and -1 or 1
	local kx, ky = ox + side * 90, oy - 20
	if RaytraceSurfaces( ox, oy - 20, kx, ky ) then kx = ox - side * 90 end
	fx_flash( kx, ky, "light", 160, 20 )
	fx_burst( kx, ky, fx_color( "light", 0.9 ), 60, 90, 0.8 )
	EntityLoad( "data/entities/animals/necromancer_shop.xml", kx, ky )
	GamePrintImportant( "The Knights Moralis have come", "For forbidden magic" )
	effect_sound( "angry", kx, ky )
	EntityKill( e )
end

EFFECT_MODES.knights = MODES
