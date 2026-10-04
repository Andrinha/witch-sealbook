-- The Sign of Pulling on a seal projectile (cast.lua): every frame it draws creatures and loose
-- objects around it in, or pushes them away when the sign was drawn inverted. Strength: the
-- "witch_pull" variable on the projectile, negative to push.

local PULL_VAR = "witch_pull"
local RADIUS = 40          -- reach of a single ordinary sign
local RADIUS_PER_SIGN = 25
local PULL = 8             -- velocity change per frame next to the projectile, for one sign

local entity = GetUpdatedEntityID()
local x, y = EntityGetTransform( entity )
local strength = 1
for _, comp in ipairs( EntityGetComponent( entity, "VariableStorageComponent" ) or {} ) do
	if ComponentGetValue2( comp, "name" ) == PULL_VAR then strength = ComponentGetValue2( comp, "value_float" ) end
end
local radius = RADIUS + RADIUS_PER_SIGN * math.abs( strength )
local shooter = 0
local projectile = EntityGetFirstComponent( entity, "ProjectileComponent" )
if projectile then shooter = ComponentGetValue2( projectile, "mWhoShot" ) end

-- creatures: nudge their own velocity (the caster is never pulled)
for _, id in ipairs( EntityGetInRadiusWithTag( x, y, radius, "enemy" ) or {} ) do
	local character = EntityGetFirstComponent( id, "CharacterDataComponent" )
	if id ~= shooter and character then
		local ex, ey = EntityGetTransform( id )
		local dx, dy = x - ex, y - ey
		local d = math.sqrt( dx * dx + dy * dy )
		if d > 2 then
			local f = PULL * strength * ( 1 - d / radius ) / d
			local vx, vy = ComponentGetValue2( character, "mVelocity" )
			ComponentSetValue2( character, "mVelocity", vx + dx * f, vy + dy * f )
		end
	end
end

-- physics objects (rocks, crates, items): a force towards the projectile
function witch_pull_force( body, mass, bx, by )
	local dx, dy = x - bx, y - by
	local d = math.sqrt( dx * dx + dy * dy )
	if d < 2 or d > radius then return bx, by, 0, 0, 0 end
	local f = 3 * PULL * strength * mass * ( 1 - d / radius ) / d
	return bx, by, dx * f, dy * f, 0
end
PhysicsApplyForceOnArea( witch_pull_force, entity, x - radius, y - radius, x + radius, y + radius )
