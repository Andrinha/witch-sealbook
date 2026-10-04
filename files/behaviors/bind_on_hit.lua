-- Entwining (cast.lua): a ribbon winds round whoever the projectile hits and holds them
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local target = hit_target( e )
if target then hold_creature( target, hit_var( e, "witch_bind" ) or 120, "ribbon", "light", hit_shooter( e ) ) end
