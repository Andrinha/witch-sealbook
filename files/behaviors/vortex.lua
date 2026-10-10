-- Vortex (resonances.lua): the hanging orb draws in creatures, loose things and enemies' shots within "witch_vortex_r"
-- and sweeps them round itself ("witch_vortex_turn": which way)
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local IN, ROUND = 5, 7 -- velocity a frame towards it and round it, right beside it

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local r = hit_var( e, "witch_vortex_r" ) or 70
local turn = hit_var( e, "witch_vortex_turn" ) or 1
local shooter = hit_shooter( e )
for _, id in ipairs( creatures_in( x, y, r, shooter ) ) do
	local ex, ey = EntityGetTransform( id )
	local dx, dy = x - ex, y - ey
	local d = math.sqrt( dx * dx + dy * dy )
	if d > 3 then
		local k = 1 - d / r
		push_creature( id, ( dx / d * IN - turn * dy / d * ROUND ) * k, ( dy / d * IN + turn * dx / d * ROUND ) * k )
	end
end
-- enemies' shots are swept round
for _, id in ipairs( EntityGetInRadiusWithTag( x, y, r, "projectile" ) or {} ) do
	local proj = EntityGetFirstComponent( id, "ProjectileComponent" )
	local vel = EntityGetFirstComponent( id, "VelocityComponent" )
	if proj and vel and id ~= e and ComponentGetValue2( proj, "mWhoShot" ) ~= shooter then
		local px, py = EntityGetTransform( id )
		local dx, dy = x - px, y - py
		local d = math.max( 1, math.sqrt( dx * dx + dy * dy ) )
		local vx, vy = ComponentGetValue2( vel, "mVelocity" )
		ComponentSetValue2( vel, "mVelocity", vx * 0.96 + dx / d * 8 - turn * dy / d * 12, vy * 0.96 + dy / d * 8 + turn * dx / d * 12 )
	end
end
-- loose things: drawn in and round
function witch_vortex_force( body, mass, bx, by )
	local dx, dy = x - bx, y - by
	local d = math.sqrt( dx * dx + dy * dy )
	if d < 2 or d > r then return bx, by, 0, 0, 0 end
	local f = 20 * mass * ( 1 - d / r ) / d
	return bx, by, ( dx - turn * dy ) * f, ( dy + turn * dx ) * f, 0
end
PhysicsApplyForceOnArea( witch_vortex_force, e, x - r, y - r, x + r, y + r )
-- its look: wind spiralling in
local frame = GameGetFrameNum()
for k = 0, 3 do
	local a = frame * 0.15 * turn + k * math.pi / 2
	local rr = r * ( 0.3 + 0.6 * ( ( frame * 0.02 + k / 4 ) % 1 ) )
	fx_dot( x + math.cos( a ) * rr, y + math.sin( a ) * rr, effect_color( "wind", 0.6, 0.6 ), -turn * math.sin( a ) * 40,
		turn * math.cos( a ) * 40, 0.15 )
end
