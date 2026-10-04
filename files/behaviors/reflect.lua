-- The Sign of Reflection (cast.lua) on a field or a sphere hanging in place: enemies' projectiles that come into it
-- turn back the way they came, as the caster's own. "witch_reflect_r": its radius, "witch_owner": the caster.
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local r = hit_var( e, "witch_reflect_r" ) or 14
local owner = hit_var( e, "witch_owner" ) or 0
reflect_projectiles( x, y, 0, r + 4, owner )
