-- Solidification (cast.lua): where the projectile ends, its element sets solid - a foothold that lasts a while; a
-- Pillar (resonances.lua) is "witch_solid_count" blocks one over another
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local element = hit_var( e, "witch_solid" ) or "earth"
local count = math.floor( hit_var( e, "witch_solid_count" ) or 1 )
for i = 0, count - 1 do
	local py = y - i * 9
	-- up to the ceiling, not into it
	if i > 0 and RaytraceSurfaces( x, py + 3, x, py - 5 ) then break end
	solid_piece( SOLID_PIECES[element] or "stone_block", x, py, 60 * 20 )
end
fx_burst( x, y, effect_color( element, 0.5 ), 12, 40, 0.4 )
