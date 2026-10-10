-- Sunburst (resonances.lua): where the swollen shot of light ends it bursts in a flash that blinds every creature within
-- "witch_sunburst_r"
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local r = hit_var( e, "witch_sunburst_r" ) or 50
local element = hit_var( e, "witch_sunburst_element" ) or "light"
local blind = RESONANCE_AMOUNTS.sunburst( 1 ).blind
for _, id in ipairs( creatures_in( x, y, r, hit_shooter( e ) ) ) do
	local ex, ey = EntityGetTransform( id )
	if not RaytraceSurfaces( x, y, ex, ey - 4 ) then give_effect( id, MISC .. "effect_blindness.xml", blind ) end
end
fx_flash( x, y, element, r * 3, 20 )
fx_ring( x, y, r, effect_color( element, 0.95 ), math.floor( r ), 60, 0.3 )
