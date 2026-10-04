-- The Sign of the Crosshair on a rain cloud (cast.lua): the cloud drifts to hang over the enemy nearest to it.
-- "witch_follow": how strongly (the signs' size).
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local REACH = 120 -- how far from the cloud it notices an enemy
local ABOVE = 36  -- how high over the enemy it hangs
local SPEED = 30  -- pixels per second, for one sign

local e = GetUpdatedEntityID()
local vel = EntityGetFirstComponent( e, "VelocityComponent" )
if not vel then return end
local strength = hit_var( e, "witch_follow" ) or 1
local x, y = EntityGetTransform( e )
local enemy = nearest_creature( x, y + ABOVE, REACH, hit_shooter( e ) )
local vx, vy = 0, 0
if enemy then
	local ex, ey = EntityGetTransform( enemy )
	local dx, dy = ex - x, ey - ABOVE - y
	local d = math.sqrt( dx * dx + dy * dy )
	if d > 3 then
		local speed = math.min( d * 2, SPEED * ( 0.6 + 0.4 * strength ) )
		vx, vy = dx / d * speed, dy / d * speed
	end
end
ComponentSetValue2( vel, "mVelocity", vx, vy )
