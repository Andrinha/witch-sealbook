-- Boomerang (resonances.lua): the shot flies out curving to one side, and after "witch_boomerang" frames turns back to
-- the caster; caught, it is gone without bursting. "witch_boomerang_turn": the way it curves.
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local TURN = 0.012   -- radians a frame it curves on the way out
local STEER = 0.12   -- how quickly it turns to the caster on the way back
local SPEED = 140    -- at least this fast coming back, pixels a second (and as fast as it was cast)

local e = GetUpdatedEntityID()
local vel = EntityGetFirstComponent( e, "VelocityComponent" )
local proj = EntityGetFirstComponent( e, "ProjectileComponent" )
if not vel or not proj then return end
local now = run_frame() -- the run's clock, which goes on across Save & Quit (run_clock.lua)
local vx, vy = ComponentGetValue2( vel, "mVelocity" )
local born = hit_var( e, "witch_boomerang_born" )
if not born or born == 0 then
	born = now
	effect_set( e, "witch_boomerang_born", now )
	effect_set( e, "witch_boomerang_speed", math.sqrt( vx * vx + vy * vy ) )
elseif born > now then
	born = now -- counted before the run's clock (a game saved by an older version): it flies out anew
	effect_set( e, "witch_boomerang_born", now )
end
local out = hit_var( e, "witch_boomerang" ) or 30
local turn = hit_var( e, "witch_boomerang_turn" ) or 1
if now - born < out then
	local c, s = math.cos( TURN * turn ), math.sin( TURN * turn )
	ComponentSetValue2( vel, "mVelocity", vx * c - vy * s, vx * s + vy * c )
	return
end
local shooter = ComponentGetValue2( proj, "mWhoShot" )
if not shooter or shooter == 0 or not EntityGetIsAlive( shooter ) then return end
local x, y = EntityGetTransform( e )
local sx, sy = EntityGetTransform( shooter )
sy = sy - 4
local dx, dy = sx - x, sy - y
local d = math.sqrt( dx * dx + dy * dy )
if d < 10 then
	-- caught: no burst at the caster's hand
	ComponentSetValue2( proj, "on_death_explode", false )
	ComponentSetValue2( proj, "on_lifetime_out_explode", false )
	ComponentSetValue2( proj, "on_death_emit_particle", false )
	EntityKill( e )
	return
end
local speed = math.max( SPEED, hit_var( e, "witch_boomerang_speed" ) or 0 )
ComponentSetValue2( vel, "mVelocity", vx + ( dx / d * speed - vx ) * STEER, vy + ( dy / d * speed - vy ) * STEER )
