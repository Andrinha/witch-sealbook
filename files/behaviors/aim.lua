-- The Sign of Sights Set on a seal projectile (cast.lua): it flies exactly to the point the caster aimed at and bursts
-- there. "witch_aim_x", "witch_aim_y": the point.

local e = GetUpdatedEntityID()
local ax, ay
for _, comp in ipairs( EntityGetComponent( e, "VariableStorageComponent" ) or {} ) do
	local name = ComponentGetValue2( comp, "name" )
	if name == "witch_aim_x" then ax = ComponentGetValue2( comp, "value_float" ) end
	if name == "witch_aim_y" then ay = ComponentGetValue2( comp, "value_float" ) end
end
local vel = EntityGetFirstComponent( e, "VelocityComponent" )
if not ax or not ay or not vel then return end
local x, y = EntityGetTransform( e )
local dx, dy = ax - x, ay - y
local d = math.sqrt( dx * dx + dy * dy )
local vx, vy = ComponentGetValue2( vel, "mVelocity" )
local speed = math.max( 80, math.sqrt( vx * vx + vy * vy ) )
if d < 5 or ( d < 16 and vx * dx + vy * dy < 0 ) then
	-- there: it bursts
	local proj = EntityGetFirstComponent( e, "ProjectileComponent" )
	if proj then ComponentSetValue2( proj, "lifetime", 1 ) end
	ComponentSetValue2( vel, "mVelocity", 0, 0 )
	return
end
local k = 0.3
ComponentSetValue2( vel, "mVelocity", vx + ( dx / d * speed - vx ) * k, vy + ( dy / d * speed - vy ) * k )
