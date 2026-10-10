-- Tether (resonances.lua): Link threads the hanging orb to the creatures nearest it - up to three within reach can get no
-- farther from it than their thread, and the thread stings them now and then. "witch_tether_r": its reach.
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local HELD = 3      -- creatures it holds at once
local THREAD = 36   -- how far from the orb they may go
local EVERY = 20    -- frames between the stings

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local r = hit_var( e, "witch_tether_r" ) or 90
local shooter = hit_shooter( e )
local element = hit_var( e, "witch_tether_element" ) or "light"
local near = {}
for _, id in ipairs( creatures_in( x, y, r, shooter ) ) do
	local ex, ey = EntityGetTransform( id )
	near[#near + 1] = { id = id, x = ex, y = ey + creature_body( id ), d = math.sqrt( ( ex - x ) ^ 2 + ( ey - y ) ^ 2 ) }
end
table.sort( near, function( a, b ) return a.d < b.d end )
local sting = GameGetFrameNum() % EVERY == 0
for i = 1, math.min( HELD, #near ) do
	local c = near[i]
	if c.d > THREAD then
		-- the thread is taut: it pulls them back towards the orb
		local k = math.min( 1, ( c.d - THREAD ) / 20 )
		push_creature( c.id, ( x - c.x ) / c.d * 140 * k, ( y - c.y ) / c.d * 140 * k, true )
	end
	if sting then seal_damage( c.id, 0.06, "DAMAGE_PROJECTILE", shooter, c.x, c.y ) end
	fx_line( x, y, c.x, c.y, effect_color( element, 0.85, 0.7 ), 5, 0.05, 0.5 )
end
