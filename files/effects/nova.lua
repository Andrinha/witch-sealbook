-- Waves and blades (manifest.lua): the Sign of Dispersion's wave - a ring of the element running out from the seal
-- (or, with pulling signs, rushing in) - and the Sigil of the Sword's cut, a blade of the element in the caster's
-- hand that moves as the seal's signs said (columns stab it ahead, the wind's signs whirl it round, a seal with
-- neither cuts a wide arc) and strikes whoever the edge passes over with the element's own touch. The wave's signs:
-- 'hold' and 'bind' hold whom it strikes for that many frames, 'chill' freezes them, 'reflect' turns enemies'
-- projectiles back as it passes; what it does to the ground is the conversion cast.lua gives it (wave_converts).
-- The blade's look is blade_draw.lua's, told every tick where the blade now is (wn_blade_draw).

local MODES = {}

-- elements that burst into shards flying outwards (Crystal Shard)
local SHARDS = { crystal = true, ice = true, stone = true, frost = true }

-- what a wave of the element sounds like as it bursts out: burning matter roars like the game's own circle of fire, and plasma, fire condensed, hums like its laser
local WAVE_SOUNDS = { fire = "fire_ring", firestorm = "fire_ring", lava = "fire_ring", sunfire = "fire_ring", plasma = "laser" }

MODES.nova = function( e, p, age, x, y )
	local grow = p.grow or 22
	local R = p.r or 60
	local inward = p.inward == 1
	if age == 0 then
		effect_sound( WAVE_SOUNDS[p.element] or "magic", x, y )
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
	if look.glow then
		-- an element with a glow of its own shines with it in place of its matter (Plasma: no fire to see there)
		for i = 1, 8 do
			local a = Random( 0, 628 ) / 100
			GameCreateCosmeticParticle( look.glow, x + math.cos( a ) * r, y + math.sin( a ) * r, 1, math.cos( a ) * 40, math.sin( a ) * 40,
				0, 0.2, 0.5, true, true, false, true, 0, 0 )
		end
	elseif look.material and age % 2 == 0 then
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

-- The Sigil of the Sword (manifest.lua M.blade): a blade of the seal's element with its hilt in the caster's hand.
-- The seal's signs said how it moves: the Spiraling Wind, or signs turned sideways, whirl it once round the caster the
-- way they turn; columns stab it straight ahead; a seal with neither cuts a wide arc through the aim. However it
-- moves, the edge alone cuts: whoever it passes over this tick is struck, once a stroke, with the cut of the conjured
-- steel and the element's own touch - the kinds of damage, the status and the throw its carriers carry it with.
-- the element's damage, as EntityInflictDamage names its kinds
local BLADE_KINDS = { fire = "DAMAGE_FIRE", ice = "DAMAGE_ICE", slice = "DAMAGE_SLICE",
	electricity = "DAMAGE_ELECTRICITY", explosion = "DAMAGE_EXPLOSION", projectile = "DAMAGE_PROJECTILE" }

-- Accelerate through the middle of a cut, with a brief wind-up and follow-through.
local function blade_pose( style, base, radius, turn, t )
	if style == "thrust" then
		local extension = t < 0.45 and t / 0.45 or ( 1 - t ) / 0.55
		return base, radius * ( 0.18 + 1.12 * math.sin( math.pi * 0.5 * extension ) )
	end
	local eased = t * t * ( 3 - 2 * t )
	if style == "spin" then return base + turn * 2 * math.pi * eased, radius end
	return base + turn * ( 2.4 * eased - 1.2 ), radius
end

-- Inside the swept blade, with a few pixels around its edge for a creature's body.
-- Measuring from the middle of this tick's arc also handles cuts facing across -pi.
local function stroke_contains( dx, dy, middle, half_arc, reach, width )
	local a = math.atan2( dy, dx )
	local delta = ( a - middle + math.pi ) % ( 2 * math.pi ) - math.pi
	local edge = middle + math.max( -half_arc, math.min( half_arc, delta ) )
	local c, s = math.cos( edge ), math.sin( edge )
	local along = math.max( 0, math.min( reach, dx * c + dy * s ) )
	return ( dx - along * c ) ^ 2 + ( dy - along * s ) ^ 2 <= width * width
end

-- Release a fan once, as the blade passes through the aim. A wall between the hand and point catches it.
local function blade_volley( e, p, x, y, angle, reach )
	effect_set( e, "released", 1 )
	local tx, ty = x + math.cos( angle ) * reach, y + math.sin( angle ) * reach
	if RaytraceSurfaces( x, y, tx, ty ) then return end
	-- Vacuum has no generated carrier of its own. Its gust uses the wind bolt.
	local element = DICTIONARY_LOOKS[p.element] and p.element or "wind"
	local shots = math.min( 3, p.volley )
	for i = 1, shots do
		local a = angle + ( i - ( shots + 1 ) / 2 ) * 0.18
		local bolt = EntityLoad( carrier_file( element, "bolt" ), tx, ty )
		local projectile = EntityGetFirstComponent( bolt, "ProjectileComponent" )
		if projectile then ComponentSetValue2( projectile, "penetrate_entities", true ) end
		GameShootProjectile( p.owner, tx, ty, tx + 100 * math.cos( a ), ty + 100 * math.sin( a ), bolt, true )
	end
	fx_burst( tx, ty, effect_color( element, 0.7 ), 9, 45, 0.12 )
end

MODES.slash = function( e, p, age )
	local frames = math.max( 2, p.frames or 12 )
	local owner = effect_owner( p )
	if age >= frames or not owner then EntityKill( e ); return end
	local base = math.atan2( p.dy or 0, p.dx or 1 )
	local x, y = EntityGetTransform( owner )
	x = x + ( p.ox or 0 ) + math.cos( base ) * 6
	y = y + ( p.oy or -2 ) + math.sin( base ) * 6
	local style, radius, turn = p.style or "sweep", p.r or 28, p.turn or 1
	-- Mirror an ordinary cut across the caster so the edge descends on either side.
	if style == "sweep" then turn = ( p.dx or 1 ) < 0 and -1 or 1 end
	local progress = age / ( frames - 1 )
	local angle, reach = blade_pose( style, base, radius, turn, progress )
	local tx, ty = x + math.cos( angle ) * reach, y + math.sin( angle ) * reach
	EntitySetTransform( e, tx, ty )
	local watery = p.element == "water" or p.element == "storm"
	if age == 0 then
		effect_sound( "magic", x, y ) -- the conjured blade rings as the stroke begins
		-- The effect entity follows the point. Raincleaver parts liquid here and a cold edge freezes the water it crosses.
		if watery then
			EntityAddComponent2( e, "LiquidDisplacerComponent", { radius = math.min( 8, math.max( 2, math.floor( radius / 7 ) ) ) } )
		elseif ( RESONANCE_NATURES[p.element] or {} ).cold then
			dofile_once( "mods/witch_notebook/files/element_traits.lua" )
			element_freeze_water_on( e )
		end
	end
	local prev, prev_reach = blade_pose( style, base, radius, turn, math.max( 0, age - 1 ) / ( frames - 1 ) )
	local middle, half_arc = ( angle + prev ) / 2, math.abs( angle - prev ) / 2
	local swept_reach = math.max( reach, prev_reach )
	local function cuts( px, py )
		return stroke_contains( px - x, py - y, middle, half_arc, swept_reach, 4 )
	end
	if ( p.reflect or 0 ) > 0 then reflect_projectiles( x, y, 0, swept_reach + 4, owner, cuts ) end
	local release = style == "spin" and 1 or style == "thrust" and 0.45 or 0.5
	if p.volley and p.released ~= 1 and progress >= release then blade_volley( e, p, x, y, angle, reach ) end

	local look = DICTIONARY_LOOKS[p.element] or {}
	local hit, struck = {}, false
	for id in effect_text( p.hit ):gmatch( "%d+" ) do hit[tonumber( id )] = true end
	for _, id in ipairs( creatures_in( x, y, swept_reach + 4, owner ) ) do
		local ex, ey = EntityGetTransform( id )
		if not hit[id] and cuts( ex, ey ) then
			hit[id], struck = true, true
			local power = p.power or 1
			local slice = math.max( 0.1, 0.35 + 0.2 * ( p.force or 0 ) )
			for kind, amount in pairs( look.damage or {} ) do
				if kind == "slice" then slice = slice + amount
				elseif amount > 0 then seal_damage( id, amount * power, BLADE_KINDS[kind], owner, ex, ey ) end
			end
			seal_damage( id, slice * power, "DAMAGE_SLICE", owner, ex, ey )
			if look.status and look.status ~= "" then give_effect( id, look.status ) end
			push_from( id, x, y, p.knock or 120 + ( look.knockback or 0 ) )
			if ( p.bind or 0 ) > 0 then hold_creature( id, p.bind, "ribbon", p.element, owner ) end
			fx_burst( ex, ey, effect_color( p.element, 0.8 ), 10, 50, 0.2 )
		end
	end
	if struck then
		local ids = {}
		for id in pairs( hit ) do ids[#ids + 1] = id end
		effect_set( e, "hit", table.concat( ids, "," ) )
	end
	if watery then
		local c, s = math.cos( angle ), math.sin( angle )
		local vx, vy = -s * turn, c * turn
		if style == "thrust" then vx, vy = c, s end
		GameCreateParticle( "water", tx, ty, 1, vx * 100, vy * 100, false, false, true )
	end
	dofile_once( EFFECTS .. "blade_draw.lua" )
	wn_blade_draw( e, p, age, x, y, angle, reach, progress, style, prev, turn )
end

EFFECT_MODES.nova = MODES
