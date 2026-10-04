-- LuaComponent of an end of the Palm Quire's strap (entities/quire_strap.xml), now and then: it goes when its book is
-- gone, no longer keeps it, or is in the inventory (quire_strap_world.lua) - should that update have missed it.
dofile_once( "mods/witch_notebook/files/quire_strap_world.lua" )

local strap = GetUpdatedEntityID()
local v = EntityGetFirstComponentIncludingDisabled( strap, "VariableStorageComponent" )
local book = v and ComponentGetValue2( v, "value_int" ) or 0
if book == 0 or not quire_strap_kept( book, strap ) or not quire_strap_state( book ) then EntityKill( strap ) end
