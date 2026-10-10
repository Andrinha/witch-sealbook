-- Mine (resonances.lua): the small hanging orb waits; when a creature comes near it bursts in a wave of its element
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local shooter = hit_shooter( e )
local element = hit_var( e, "witch_mine_element" ) or "light"
local a = RESONANCE_AMOUNTS.mine()
if #creatures_in( x, y, a.near, shooter ) == 0 then
	if GameGetFrameNum() % 30 == 0 then fx_ring( x, y, 3, effect_color( element, 0.5, 0.5 ), 6, 0, 0.3 ) end
	return
end
effect_spawn( "nova", "nova", x, y, { owner = shooter, element = element, r = a.r, grow = 10,
	damage = 0.6 * ( hit_var( e, "witch_mine_power" ) or 1 ), power = 1 } )
EntityKill( e )
