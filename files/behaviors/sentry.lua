-- Sentry (resonances.lua): the hanging orb shoots a shot of its element at the nearest enemy it can see within reach,
-- every "witch_sentry_every" frames
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local now = GameGetFrameNum()
if now < ( hit_var( e, "witch_sentry_next" ) or 0 ) then return end
local reach = RESONANCE_AMOUNTS.sentry( 0 ).reach
local x, y = EntityGetTransform( e )
local shooter = hit_shooter( e )
local best_d, bx, by
for _, id in ipairs( creatures_in( x, y, reach, shooter ) ) do
	local ex, ey = EntityGetTransform( id )
	ey = ey + creature_body( id )
	local d = ( ex - x ) ^ 2 + ( ey - y ) ^ 2
	if ( not best_d or d < best_d ) and not RaytraceSurfaces( x, y, ex, ey ) then best_d, bx, by = d, ex, ey end
end
if not best_d then return end
local element = hit_var( e, "witch_sentry_element" ) or "light"
if not DICTIONARY_LOOKS[element] then element = "light" end
local shot = EntityLoad( carrier_file( element, "bolt" ), x, y )
GameShootProjectile( shooter, x, y, bx, by, shot, true )
effect_set( e, "witch_sentry_next", now + ( hit_var( e, "witch_sentry_every" ) or 45 ) )
fx_ring( x, y, 4, effect_color( element, 0.8 ), 8, 20, 0.2 )
