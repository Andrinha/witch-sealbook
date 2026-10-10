-- Satellite (resonances.lua): Link ties the orb to its caster - it circles round them while it lasts, striking whoever it
-- passes. "witch_satellite_r": how far, "witch_satellite_turn": which way, "witch_satellite_a": where on the circle.
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local TURN = 0.09   -- radians a frame round the caster
local EVERY = 10    -- frames between the strikes on one passing creature

local e = GetUpdatedEntityID()
local vel = EntityGetFirstComponent( e, "VelocityComponent" )
local shooter = hit_shooter( e )
if not vel or shooter == 0 or not EntityGetIsAlive( shooter ) then return end
local r = hit_var( e, "witch_satellite_r" ) or 30
local a = ( hit_var( e, "witch_satellite_a" ) or 0 ) + TURN * ( hit_var( e, "witch_satellite_turn" ) or 1 )
effect_set( e, "witch_satellite_a", a )
local sx, sy = EntityGetTransform( shooter )
local x, y = EntityGetTransform( e )
local tx, ty = sx + math.cos( a ) * r, sy - 6 + math.sin( a ) * r
ComponentSetValue2( vel, "mVelocity", ( tx - x ) * 12, ( ty - y ) * 12 )
if GameGetFrameNum() % EVERY == 0 then
	local element = hit_var( e, "witch_satellite_element" ) or "light"
	local look = DICTIONARY_LOOKS[element] or {}
	local kind = ( look.damage and look.damage.fire ) and "DAMAGE_FIRE" or ( look.damage and look.damage.ice ) and "DAMAGE_ICE"
		or ( look.damage and look.damage.electricity ) and "DAMAGE_ELECTRICITY" or "DAMAGE_PROJECTILE"
	for _, id in ipairs( creatures_in( x, y, 9, shooter ) ) do
		seal_damage( id, 0.12 * ( hit_var( e, "witch_satellite_power" ) or 1 ), kind, shooter, x, y )
		if look.status and look.status ~= "" then give_effect( id, look.status ) end
		push_from( id, x, y, 50 )
	end
end
