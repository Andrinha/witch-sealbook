-- Envelopment (cast.lua): where the projectile hits, its element wraps round the target in a ring and keeps striking it
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local target, x, y = hit_target( e, 18 )
local element = hit_var( e, "witch_envelop" ) or "light"
local w = hit_var( e, "witch_envelop_w" ) or 1
if target then
	effect_spawn( "orbit", "envelop", x, y, { owner = target, caster = hit_shooter( e ), element = element, frames = math.floor( 90 + 60 * w ),
		power = w } )
else
	fx_ring( x, y, 10, effect_color( element, 0.5 ), 20, 30, 0.4 )
end
