-- Binding, Immobility (cast.lua): whoever the projectile hits is held in place
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local target = hit_target( e )
if target then
	local element = hit_var( e, "witch_hold_element" ) or ""
	hold_creature( target, hit_var( e, "witch_hold" ) or 90, HIT_LOOK[element] or "time", element, hit_shooter( e ) )
end
