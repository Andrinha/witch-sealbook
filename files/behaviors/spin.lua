-- Signs turned sideways spin the spell (cast.lua): the projectile keeps flying where it was going,
-- but circles around its own path, so its trail curls in loops. Every frame the circling part of the
-- velocity added last frame is taken out, and the next one - turned a little further - is added.
-- The "witch_spin" variable holds the spin (-1..1, its sign is the way it turns) and, as a string,
-- the phase and the circling velocity added last frame.

local SPIN_VAR = "witch_spin"
local TURN_PER_FRAME = 0.25     -- radians per frame at the least spin
local TURN_PER_SPIN = 0.15      -- ... and this much more at full spin
local LOOP_SPEED = 1.4          -- circling speed / flight speed at the least spin: above 1 it loops
local LOOP_SPEED_PER_SPIN = 0.6
local MIN_LOOP_SPEED = 60       -- pixels per second, for slow floating spells

local entity = GetUpdatedEntityID()
local var
for _, comp in ipairs( EntityGetComponent( entity, "VariableStorageComponent" ) or {} ) do
	if ComponentGetValue2( comp, "name" ) == SPIN_VAR then var = comp end
end
local velocity = EntityGetFirstComponent( entity, "VelocityComponent" )
if not var or not velocity then return end

local spin = ComponentGetValue2( var, "value_float" )
local phase, last_x, last_y = ( ComponentGetValue2( var, "value_string" ) or "" ):match( "^([-%d.e]+),([-%d.e]+),([-%d.e]+)$" )
last_x, last_y = tonumber( last_x ) or 0, tonumber( last_y ) or 0

local vx, vy = ComponentGetValue2( velocity, "mVelocity" )
vx, vy = vx - last_x, vy - last_y -- the flight itself (gravity, homing and the rest still act on it)

local strength = math.abs( spin )
local turn = ( TURN_PER_FRAME + TURN_PER_SPIN * strength ) * ( spin < 0 and -1 or 1 )
-- the first loop starts across the flight, so the loops stay centered on the aimed line
phase = ( tonumber( phase ) or ( math.atan2( vy, vx ) + math.pi / 2 - turn ) ) + turn
-- circling faster than it flies, so it goes round in loops like a spring seen from the side
local speed = math.max( MIN_LOOP_SPEED, math.sqrt( vx * vx + vy * vy ) * ( LOOP_SPEED + LOOP_SPEED_PER_SPIN * strength ) )
local cx, cy = math.cos( phase ) * speed, math.sin( phase ) * speed

ComponentSetValue2( velocity, "mVelocity", vx + cx, vy + cy )
ComponentSetValue2( var, "value_string", string.format( "%.4f,%.3f,%.3f", phase % ( 2 * math.pi ), cx, cy ) )
