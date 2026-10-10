-- Waves and blades (manifest.lua): the Sign of Dispersion's wave - a ring of the element running out from the seal
-- (or, with pulling signs, rushing in) - and the Sigil of the Sword's cut. The wave's signs: 'hold' and 'bind' hold
-- whom it strikes for that many frames, 'chill' freezes them, 'reflect' turns enemies' projectiles back as it passes;
-- what it does to the ground is the conversion cast.lua gives it (wave_converts).

local MODES = {}

-- elements that burst into shards flying outwards (Crystal Shard)
local SHARDS = { crystal = true, ice = true, stone = true, frost = true }

MODES.nova = function( e, p, age, x, y )
	local grow = p.grow or 22
	local R = p.r or 60
	local inward = p.inward == 1
	if age == 0 then
		if SHARDS[p.element] then
			local n = 8
			for i = 1, n do
				local a = ( i + Random( 0, 100 ) / 200 ) / n * 2 * math.pi
				local shard = EntityLoad( carrier_file( p.element, "bolt" ), x, y )
				GameShootProjectile( p.owner or 0, x, y, x + math.cos( a ) * 100, y + math.sin( a ) * 100, shard, true )
			end
		end
		fx_flash( x, y, p.element, R * 2, 12 )
	end
	if age > grow then
		if p.element == "smoke" or p.element == "smog" then
			effect_spawn( "zone", "mist", x, y, { frames = 300, r = R * 0.8, owner = p.owner or 0 } )
		end
		-- Collapse (resonances.lua): drawn in to the middle, the wave bursts out again, wider and harder
		if inward and ( p.rebound or 0 ) > 1 then
			local k = p.rebound
			fx_flash( x, y, p.element, R * 2 * k, 16 )
			effect_spawn( "nova", "nova", x, y, { owner = p.owner or 0, element = p.element, r = R * k, grow = grow,
				force = p.force or 0, power = p.power or 1, damage = ( p.damage or ( 0.3 + 0.25 * ( p.force or 0 ) ) ) * k,
				push = ( p.push or 80 ) * 1.5, chill = p.chill, hold = p.hold, bind = p.bind, reflect = p.reflect } )
		end
		EntityKill( e )
		return
	end
	local t = age / grow
	local ease = 1 - ( 1 - t ) * ( 1 - t )
	local r0 = inward and R * ( 1 - ( ( age - 1 ) / grow ) ) or R * ( 1 - ( 1 - ( age - 1 ) / grow ) ^ 2 )
	local r = inward and R * ( 1 - t ) or R * ease
	local look = DICTIONARY_LOOKS[p.element] or {}
	local c1, c2 = effect_color( p.element, 0.25, 1 - 0.5 * t ), effect_color( p.element, 0.8, 1 - 0.6 * t )
	local n = math.floor( 16 + r * 0.9 )
	for i = 0, n - 1 do
		local a = i / n * 2 * math.pi + Random( -5, 5 ) / 100
		local c, s = math.cos( a ), math.sin( a )
		fx_dot( x + c * r, y + s * r, c1, c * 40, s * 40, 0.12 )
		if i % 3 == 0 then fx_dot( x + c * ( r - 3 ), y + s * ( r - 3 ), c2, c * 20, s * 20, 0.1 ) end
	end
	if look.material and age % 2 == 0 then
		for i = 1, 6 do
			local a = Random( 0, 628 ) / 100
			GameCreateParticle( look.material, x + math.cos( a ) * r, y + math.sin( a ) * r, 1, math.cos( a ) * 50, math.sin( a ) * 50, false, false, true )
		end
	end
	-- whoever the ring passes over is struck, once
	local hit = {}
	for id in effect_text( p.hit ):gmatch( "%d+" ) do hit[tonumber( id )] = true end
	local lo, hi = math.min( r0, r ) - 4, math.max( r0, r ) + 4
	local struck = false
	for _, id in ipairs( creatures_in( x, y, hi, p.owner ) ) do
		local ex, ey = EntityGetTransform( id )
		local d = math.sqrt( ( ex - x ) ^ 2 + ( ey - y ) ^ 2 )
		if d >= lo and not hit[id] then
			hit[id] = true
			struck = true
			local kind = "DAMAGE_PROJECTILE"
			for k, v in pairs( look.damage or {} ) do
				if v > 0 then kind = ( { fire = "DAMAGE_FIRE", ice = "DAMAGE_ICE", slice = "DAMAGE_SLICE", electricity = "DAMAGE_ELECTRICITY",
					explosion = "DAMAGE_EXPLOSION" } )[k] or kind end
			end
			seal_damage( id, ( p.damage or ( 0.3 + 0.25 * ( p.force or 0 ) ) ) * ( p.power or 1 ), kind, p.owner, x, y )
			if look.status and look.status ~= "" then give_effect( id, look.status ) end
			if p.chill == 1 then give_effect( id, MISC .. "effect_frozen_short.xml" ) end
			local push = ( inward and -1 or 1 ) * ( p.push or ( 80 + ( look.knockback or 0 ) ) )
			push_from( id, x, y, push )
			if ( p.hold or 0 ) > 0 then hold_creature( id, p.hold, HIT_LOOK[p.element] or "time", p.element, p.owner ) end
			if ( p.bind or 0 ) > 0 then hold_creature( id, p.bind, "ribbon", "light", p.owner ) end
		end
	end
	if p.reflect == 1 then reflect_projectiles( x, y, lo, hi, p.owner or 0 ) end
	if ( p.push_objects or 0 ) > 0 then
		PhysicsApplyForceOnArea( function( body, mass, bx, by )
			local dx, dy = bx - x, by - y
			local d = math.sqrt( dx * dx + dy * dy )
			if d < 2 or d < lo or d > hi then return bx, by, 0, 0, 0 end
			local force = mass * p.push_objects * ( 1 - 0.4 * d / R ) / d
			return bx, by, dx * force, dy * force, 0
		end, e, x - hi, y - hi, x + hi, y + hi )
	end
	if struck then
		local ids = {}
		for id in pairs( hit ) do ids[#ids + 1] = id end
		effect_set( e, "hit", table.concat( ids, "," ) )
	end
end

-- The Sigil of the Sword (Raincleaver): the caster cuts the air with a blade of the element in a wide arc
MODES.slash = function( e, p, age, x, y )
	local frames = 10
	if age > frames then
		EntityKill( e )
		return
	end
	local base = math.atan2( p.dy, p.dx )
	local a0 = base - 1.2 + 2.4 * ( math.max( 0, age - 1 ) / frames )
	local a1 = base - 1.2 + 2.4 * ( age / frames )
	local r = p.r or 28
	local c1, c2 = effect_color( p.element, 0.3 ), effect_color( p.element, 0.95 )
	for k = 0, 6 do
		local a = a0 + ( a1 - a0 ) * k / 6
		for s = 0, 5 do
			local rr = r * ( 0.35 + 0.65 * s / 5 )
			fx_dot( x + math.cos( a ) * rr, y + math.sin( a ) * rr, s == 5 and c2 or c1, -math.sin( a ) * 60, math.cos( a ) * 60, 0.15 )
		end
	end
	if p.element == "water" or p.element == "storm" then
		GameCreateParticle( "water", x + math.cos( a1 ) * r, y + math.sin( a1 ) * r, 1, -math.sin( a1 ) * 120, math.cos( a1 ) * 120, false, false, true )
	end
	local hit = {}
	for id in effect_text( p.hit ):gmatch( "%d+" ) do hit[tonumber( id )] = true end
	for _, id in ipairs( creatures_in( x, y, r + 6, p.owner ) ) do
		if not hit[id] then
			local ex, ey = EntityGetTransform( id )
			local a = math.atan2( ey - y, ex - x )
			local diff = math.abs( ( a - base + math.pi ) % ( 2 * math.pi ) - math.pi )
			if diff <= 1.25 then
				hit[id] = true
				seal_damage( id, 0.8 * ( p.power or 1 ), "DAMAGE_SLICE", p.owner, ex, ey )
				push_from( id, x, y, 120 )
				fx_burst( ex, ey - 4, c2, 10, 50, 0.3 )
			end
		end
	end
	local ids = {}
	for id in pairs( hit ) do ids[#ids + 1] = id end
	effect_set( e, "hit", table.concat( ids, "," ) )
end

EFFECT_MODES.nova = MODES
