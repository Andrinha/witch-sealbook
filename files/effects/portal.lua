-- Windows through space (manifest.lua): the Windowway's pair of windows - step into one, come out of the other; the
-- Handheld Windowway's small pair that projectiles fly through; the Doorknob's door back to a remembered place.

local MODES = {}
PORTAL_COOLDOWN = PORTAL_COOLDOWN or {}

local function partner( p )
	local id = math.floor( ( p.partner or 0 ) + 0.5 )
	if id ~= 0 and EntityGetIsAlive( id ) then return id end
end

-- an oval window frame of light, w x h, its glass shimmering
local function window( x, y, w, h, age, element, open )
	local c = effect_color( element, 0.55 )
	local n = math.floor( 10 + w + h )
	for i = 0, n - 1 do
		if ( i + age ) % 2 == 0 then
			local a = i / n * 2 * math.pi
			fx_dot( x + math.cos( a ) * w * open, y + math.sin( a ) * h * open, c, 0, 0, 0.05 )
		end
	end
	if age % 3 == 0 then
		fx_dot( x + Random( -w, w ) * 0.6 * open, y + Random( -h, h ) * 0.6 * open, effect_color( element, 0.9, 0.6 ), 0, 0, 0.3 )
	end
end

-- The Windowway: two windows; whoever steps into one comes out of the other
MODES.window = function( e, p, age, x, y )
	if age >= p.frames then
		EntityKill( e )
		return
	end
	local other = partner( p )
	local open = math.min( 1, age / 20 )
	window( x, y, 7, 12, age, p.element, open )
	if not other then
		-- waiting for its pair: a thread of light rises from it
		if age % 4 == 0 then fx_dot( x, y - 12 - ( age % 40 ) * 0.5, effect_color( p.element, 0.8 ), 0, -10, 0.4 ) end
		return
	end
	local ox, oy = EntityGetTransform( other )
	local now = GameGetFrameNum()
	for _, id in ipairs( creatures_in( x, y, 9, 0, true ) ) do
		if ( PORTAL_COOLDOWN[id] or 0 ) <= now then
			PORTAL_COOLDOWN[id] = now + 50
			local ex, ey = EntityGetTransform( id )
			EntitySetTransform( id, ox + ( ex - x ), oy + ( ey - y ) )
			fx_burst( x, y, effect_color( p.element, 0.8 ), 20, 50, 0.4 )
			fx_burst( ox, oy, effect_color( p.element, 0.8 ), 20, 50, 0.4 )
			effect_sound( "teleport", ox, oy )
		end
	end
end

-- The Handheld Windowway: a small window by the hand and its twin by the cursor; projectiles that fly into either
-- come out of the other
MODES.hand = function( e, p, age, x, y )
	if age >= p.frames then
		EntityKill( e )
		return
	end
	local other = partner( p )
	window( x, y, 4, 6, age, p.element, math.min( 1, age / 12 ) )
	if not other then return end
	local ox, oy = EntityGetTransform( other )
	for _, id in ipairs( EntityGetInRadiusWithTag( x, y, 7, "projectile" ) or {} ) do
		local now = GameGetFrameNum()
		if ( PORTAL_COOLDOWN[id] or 0 ) <= now then
			local px, py = EntityGetTransform( id )
			EntitySetTransform( id, ox + ( px - x ), oy + ( py - y ) )
			fx_burst( ox, oy, effect_color( p.element, 0.8 ), 8, 40, 0.3 )
		end
		-- it has to leave the window it came out of before a window takes it again
		PORTAL_COOLDOWN[id] = now + 10
	end
end

-- The Doorknob: a door opens by the caster; they step through it back to the remembered place
MODES.door = function( e, p, age, x, y )
	local owner = effect_owner( p )
	if not owner then
		EntityKill( e )
		return
	end
	local open = math.min( 1, age / 25 )
	local wood = color_abgr_merge( 170, 120, 70, 255 )
	local glow = effect_color( "light", 0.7 )
	-- the door frame, and the door swinging open onto light
	for k = 0, 9 do
		local t = k / 9
		fx_dot( x - 6, y + 4 - t * 20, wood, 0, 0, 0.05 )
		fx_dot( x + 6, y + 4 - t * 20, wood, 0, 0, 0.05 )
		fx_dot( x - 6 + t * 12, y - 16, wood, 0, 0, 0.05 )
		fx_dot( x - 6 + 12 * ( 1 - open ) * 0.8, y + 4 - t * 20, wood, 0, 0, 0.05 )
		if open > 0.3 and ( k + age ) % 2 == 0 then fx_dot( x - 4 + Random( 0, 8 ) * open, y + 2 - t * 18, glow, 0, 0, 0.1 ) end
	end
	fx_dot( x - 6 + 12 * ( 1 - open ) * 0.8 + 2, y - 6, color_abgr_merge( 255, 220, 120, 255 ), 0, 0, 0.05 ) -- the knob
	if age == 30 then
		EntitySetTransform( owner, p.tx, p.ty )
		fx_burst( x, y - 6, glow, 30, 60, 0.5 )
		fx_burst( p.tx, p.ty - 6, glow, 30, 60, 0.5 )
		effect_sound( "teleport", p.tx, p.ty )
	end
	if age >= 40 then EntityKill( e ) end
end

-- The Doorknob remembers a place: a small door glyph shines there
MODES.mark = function( e, p, age, x, y )
	if age >= p.frames then
		EntityKill( e )
		return
	end
	if age % 4 == 0 then
		local c = color_abgr_merge( 255, 220, 140, 200 )
		for k = 0, 4 do
			fx_dot( x - 3, y - k * 2, c, 0, 0, 0.1 )
			fx_dot( x + 3, y - k * 2, c, 0, 0, 0.1 )
		end
		fx_dot( x, y - 10, c, 0, 0, 0.1 )
	end
end

EFFECT_MODES.portal = MODES
