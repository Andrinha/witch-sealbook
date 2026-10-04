-- The Sign of Partition or Regions pointing inwards (cast.lua) on a field: its edge keeps creatures on their side of
-- it - out of the circle round the caster, in the one at the target. "witch_bound_r": its radius, "witch_owner": the
-- caster (never held).
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local EDGE = 8  -- how deep the edge is on either side of the circle
local PUSH = 30 -- velocity it gives a creature at the edge, every other frame

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local r = hit_var( e, "witch_bound_r" ) or 32
local owner = hit_var( e, "witch_owner" ) or 0
for _, id in ipairs( creatures_in( x, y, r + EDGE, owner ) ) do
	local ex, ey = EntityGetTransform( id )
	local d = math.sqrt( ( ex - x ) ^ 2 + ( ey - y ) ^ 2 )
	if d > r - EDGE then push_from( id, x, y, d < r and -PUSH or PUSH ) end
end
if GameGetFrameNum() % 6 == 0 then
	for i = 0, 15 do
		local a = i / 16 * 2 * math.pi + GameGetFrameNum() * 0.01
		fx_dot( x + math.cos( a ) * r, y + math.sin( a ) * r, fx_color( "light", 0.5, 0.5 ), 0, 0, 0.12 )
	end
end
