-- The Sign of Mimicry on a seal projectile (cast.lua): it follows the caster's cursor while it flies.
-- "witch_mimic": how strongly.

local e = GetUpdatedEntityID()
local strength = 1
for _, comp in ipairs( EntityGetComponent( e, "VariableStorageComponent" ) or {} ) do
	if ComponentGetValue2( comp, "name" ) == "witch_mimic" then strength = ComponentGetValue2( comp, "value_float" ) end
end
local proj = EntityGetFirstComponent( e, "ProjectileComponent" )
local vel = EntityGetFirstComponent( e, "VelocityComponent" )
local shooter = proj and ComponentGetValue2( proj, "mWhoShot" ) or 0
local controls = shooter ~= 0 and EntityGetFirstComponent( shooter, "ControlsComponent" )
if not vel or not controls then return end
local mx, my = ComponentGetValue2( controls, "mMousePosition" )
local x, y = EntityGetTransform( e )
local dx, dy = mx - x, my - y
local d = math.max( 1, math.sqrt( dx * dx + dy * dy ) )
local vx, vy = ComponentGetValue2( vel, "mVelocity" )
local speed = math.max( 60, math.sqrt( vx * vx + vy * vy ) )
local k = math.min( 0.5, 0.08 * strength )
ComponentSetValue2( vel, "mVelocity", vx + ( dx / d * speed - vx ) * k, vy + ( dy / d * speed - vy ) * k )
