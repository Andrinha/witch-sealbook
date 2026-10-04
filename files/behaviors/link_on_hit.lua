-- The Sign of Link (cast.lua): from whoever the projectile hits, it jumps on to the next enemy, a thread of light
-- between them. "witch_link": jumps left.
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local jumps = math.floor( hit_var( e, "witch_link" ) or 0 )
local element = hit_var( e, "witch_link_element" ) or "light"
if jumps <= 0 then return end
local hit, x, y = hit_target( e, 16 )
local shooter = hit_shooter( e )
local best, best_d
for _, id in ipairs( creatures_in( x, y, 110, shooter ) ) do
	if id ~= hit then
		local ex, ey = EntityGetTransform( id )
		local d = ( ex - x ) ^ 2 + ( ey - y ) ^ 2
		if not best_d or d < best_d then best, best_d = id, d end
	end
end
if not best then return end
local tx, ty = EntityGetTransform( best )
ty = ty - 4
local look = DICTIONARY_LOOKS[element] and element or "light"
local next_one = EntityLoad( carrier_file( look, "bolt" ), x, y )
GameShootProjectile( shooter, x, y, tx, ty, next_one, true )
EntityAddComponent2( next_one, "VariableStorageComponent", { name = "witch_link", value_float = jumps - 1 } )
EntityAddComponent2( next_one, "VariableStorageComponent", { name = "witch_link_element", value_string = look } )
EntityAddComponent2( next_one, "LuaComponent", { script_source_file = "mods/witch_notebook/files/behaviors/link_on_hit.lua",
	execute_on_removed = true, execute_every_n_frame = -1 } )
fx_line( x, y, tx, ty, effect_color( look, 0.8 ), 3, 0.3, 1.5 )
