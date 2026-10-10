-- The lasting magic of the resonances (resonances.lua, resonance_cast.lua): the Grapple's ribbon reeling the caster in
-- or dragging an enemy to them, the Quake's shaking ground, the Chain Storm's lightning, the Updraft, the Barrage from the
-- sky, the Fissure's crack, the Limpet stuck on. p.owner is the caster.

local MODES = {}

-- the ribbon between two points, waving a little
local function ribbon( x1, y1, x2, y2, age, element )
	local dx, dy = x2 - x1, y2 - y1
	local d = math.sqrt( dx * dx + dy * dy )
	local n = math.max( 2, math.floor( d / 4 ) )
	local c = effect_color( element or "light", 0.85, 0.9 )
	for i = 0, n do
		local t = i / n
		local wave = math.sin( t * 9 - age * 0.6 ) * 1.2 * math.sin( t * math.pi )
		fx_dot( x1 + dx * t - dy / math.max( d, 1 ) * wave, y1 + dy * t + dx / math.max( d, 1 ) * wave, c, 0, 0, 0.04 )
	end
end

-- Grapple, struck a wall: the ribbon reels the caster to where it holds (p.ax, p.ay), until they are there, can go no
-- further or the time is up
MODES.reel = function( e, p, age )
	local owner = effect_owner( p )
	if not owner or age >= p.frames then
		EntityKill( e )
		return
	end
	local x, y = EntityGetTransform( owner )
	y = y - 4
	local dx, dy = p.ax - x, p.ay - y
	local d = math.sqrt( dx * dx + dy * dy )
	-- stuck: no nearer than a few frames ago
	if age % 6 == 0 then
		if age > 0 and d > ( p.last or 1e9 ) - 2 then
			EntityKill( e )
			return
		end
		effect_set( e, "last", d )
	end
	if d < 10 then
		push_creature( owner, dx * 2, dy * 2 - 40, true )
		EntityKill( e )
		return
	end
	local speed = p.speed or 260
	push_creature( owner, dx / d * speed, dy / d * speed, true )
	local cd = EntityGetFirstComponent( owner, "CharacterDataComponent" )
	if cd then ComponentSetValue2( cd, "mFlyingTimeLeft", ComponentGetValue2( cd, "fly_time_max" ) ) end
	ribbon( x, y, p.ax, p.ay, age, p.element )
end

-- Grapple, struck an enemy: the ribbon drags it to the caster
MODES.tow = function( e, p, age )
	local owner = effect_owner( p )
	local target = math.floor( ( p.target or 0 ) + 0.5 )
	if not owner or target == 0 or not EntityGetIsAlive( target ) or age >= p.frames then
		EntityKill( e )
		return
	end
	local x, y = EntityGetTransform( owner )
	local tx, ty = EntityGetTransform( target )
	local dx, dy = x - tx, y - 4 - ty
	local d = math.sqrt( dx * dx + dy * dy )
	if d < 14 then
		push_creature( target, 0, 0, true )
		EntityKill( e )
		return
	end
	local speed = p.speed or 220
	push_creature( target, dx / d * speed, dy / d * speed, true )
	ribbon( x, y - 4, tx, ty - 4, age, p.element )
end

-- Quake: the ground round the wave shakes; creatures standing on it within p.r are thrown up and hurt, now and again
MODES.quake = function( e, p, age, x, y )
	if effect_done( e, p, age ) then return end
	if age % 6 ~= 0 then return end
	if GameScreenshake then GameScreenshake( 4 ) end
	local r = p.r or 80
	for _, id in ipairs( creatures_in( x, y, r, p.owner ) ) do
		local ex, ey = EntityGetTransform( id )
		-- on the ground: something solid just under its feet
		if ground_below( ex, ey - 2, 8 ) then
			seal_damage( id, 0.08 * ( p.power or 1 ), "DAMAGE_PHYSICS_HIT", p.owner, ex, ey )
			push_creature( id, Random( -30, 30 ), -110 )
		end
	end
	-- dust leaping up from the ground along the way
	for _ = 1, 6 do
		local gx = x + Random( -100, 100 ) / 100 * r
		local hx, hy = ground_below( gx, y - 20, 60 )
		if hy then fx_dot( gx, hy - 1, effect_color( "earth", 0.3, 0.9 ), Random( -10, 10 ), -Random( 30, 70 ), 0.4, 60 ) end
	end
end

-- the kind of damage an element deals most, as EntityInflictDamage names it
local KINDS = { fire = "DAMAGE_FIRE", ice = "DAMAGE_ICE", slice = "DAMAGE_SLICE", electricity = "DAMAGE_ELECTRICITY",
	explosion = "DAMAGE_EXPLOSION", projectile = "DAMAGE_PROJECTILE" }
local function damage_kind( element )
	local best, most = "DAMAGE_PROJECTILE", 0
	for kind, v in pairs( ( DICTIONARY_LOOKS[element] or {} ).damage or {} ) do
		if v > most then best, most = KINDS[kind] or best, v end
	end
	return best
end

-- a jagged line of lightning from one point to another
local function bolt_line( x1, y1, x2, y2, color )
	local n = math.max( 3, math.floor( math.sqrt( ( x2 - x1 ) ^ 2 + ( y2 - y1 ) ^ 2 ) / 6 ) )
	local px, py = x1, y1
	for i = 1, n do
		local t = i / n
		local jx, jy = i < n and Random( -3, 3 ) or 0, i < n and Random( -3, 3 ) or 0
		local qx, qy = x1 + ( x2 - x1 ) * t + jx, y1 + ( y2 - y1 ) * t + jy
		fx_line( px, py, qx, qy, color, 2, 0.12, 0 )
		px, py = qx, qy
	end
end

-- Chain Storm: every 12 frames lightning leaps from the caster to every enemy they can see within p.reach
MODES.arcs = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -6 )
	if not owner or effect_done( e, p, age ) then return end
	if age % 12 ~= 0 then return end
	local color = effect_color( p.element, 0.8 )
	for _, id in ipairs( creatures_in( x, y, p.reach or 90, owner ) ) do
		local ex, ey = EntityGetTransform( id )
		ey = ey + creature_body( id )
		if not RaytraceSurfaces( x, y, ex, ey ) then
			bolt_line( x, y, ex, ey, color )
			seal_damage( id, 0.25 * ( p.power or 1 ), "DAMAGE_ELECTRICITY", owner, ex, ey )
			give_effect( id, MISC .. "effect_electricity.xml", 30 )
		end
	end
end

-- Updraft: the wind rises round the caster - they fly without tiring, the creatures near them are blown up
MODES.updraft = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -4 )
	if not owner or effect_done( e, p, age ) then return end
	local cd = EntityGetFirstComponent( owner, "CharacterDataComponent" )
	if cd then ComponentSetValue2( cd, "mFlyingTimeLeft", ComponentGetValue2( cd, "fly_time_max" ) ) end
	if age % 3 == 0 then
		for _, id in ipairs( creatures_in( x, y, p.r or 40, owner ) ) do push_creature( id, 0, -40 ) end
	end
	for _ = 1, 2 do
		fx_dot( x + Random( -10, 10 ), y + Random( 2, 10 ), effect_color( p.element, 0.85, 0.7 ), Random( -5, 5 ), -Random( 50, 90 ), 0.3 )
	end
end

-- Barrage: from the sky over the cursor (where the effect stands) shots of the element fall, one every p.every frames,
-- scattered round it
MODES.barrage = function( e, p, age, x, y )
	if age % ( p.every or 5 ) ~= 0 then return end
	local fired = p.fired or 0
	if fired >= ( p.shots or 7 ) then
		EntityKill( e )
		return
	end
	effect_set( e, "fired", fired + 1 )
	local look = DICTIONARY_LOOKS[p.element] and p.element or "light"
	local sx = x + Random( -40, 40 )
	local shot = EntityLoad( carrier_file( look, "bolt" ), sx, y )
	GameShootProjectile( p.owner or 0, sx, y, sx + Random( -15, 15 ), y + 100, shot, true )
	fx_dot( sx, y, effect_color( look, 0.9 ), 0, 20, 0.3 )
end

-- what the crack grinds into sand: rock and earth (the Sign of Crushing's, cast.lua)
local GRINDS = { from = "rock_static,rock_static_intro,rock_static_noedge,sandstone,soil,soil_lush,soil_dead,soil_dark,fungisoil",
	to = "sand,sand,sand,sand,sand,sand,sand,sand,sand" }

-- Fissure: a crack runs along the ground, p.dx the way: the rock under it grinds into sand, whoever stands over it is
-- thrown up and hurt, once
MODES.fissure = function( e, p, age, x, y )
	local dir = ( p.dx or 1 ) >= 0 and 1 or -1
	local run = ( p.run or 0 ) + 3
	if run > ( p.length or 120 ) or age >= ( p.frames or 90 ) then
		EntityKill( e )
		return
	end
	local nx = x + dir * 3
	-- a wall ahead stops it
	if RaytraceSurfaces( x, y - 6, nx + dir * 3, y - 6 ) then
		EntityKill( e )
		return
	end
	local gx, gy = ground_below( nx, y - 12, 30 )
	if not gy then
		EntityKill( e )
		return
	end
	EntitySetTransform( e, nx, gy )
	effect_set( e, "run", run )
	if age == 0 then convert_around( e, GRINDS.from, GRINDS.to, 5, 3 ) end
	fx_dot( nx, gy - 1, effect_color( "earth", 0.2 ), -dir * 10, -Random( 30, 80 ), 0.4, 80 )
	local hit = {}
	for id in effect_text( p.hit ):gmatch( "%d+" ) do hit[tonumber( id )] = true end
	local struck = false
	for _, id in ipairs( creatures_in( nx, gy - 8, 12, p.owner ) ) do
		if not hit[id] then
			hit[id], struck = true, true
			local ex, ey = EntityGetTransform( id )
			seal_damage( id, 0.35 * ( p.power or 1 ), damage_kind( p.element ), p.owner, ex, ey )
			push_creature( id, dir * 30, -180 )
		end
	end
	if struck then
		local ids = {}
		for id in pairs( hit ) do ids[#ids + 1] = id end
		effect_set( e, "hit", table.concat( ids, "," ) )
	end
end

-- Limpet: stuck to a creature (p.target, at p.dx, p.dy from it) or where it ended, it ticks, then bursts in a wave of its
-- element
MODES.limpet = function( e, p, age, x, y )
	local target = math.floor( ( p.target or 0 ) + 0.5 )
	if target ~= 0 and EntityGetIsAlive( target ) then
		local tx, ty = EntityGetTransform( target )
		x, y = tx + ( p.dx or 0 ), ty + ( p.dy or 0 )
		EntitySetTransform( e, x, y )
	end
	if age >= ( p.frames or 75 ) then
		fx_flash( x, y, p.element, ( p.r or 40 ) * 2, 12 )
		effect_spawn( "nova", "nova", x, y, { owner = p.owner or 0, element = p.element, r = p.r or 40, grow = 12,
			damage = 0.9 * ( p.power or 1 ), power = 1 } )
		EntityKill( e )
		return
	end
	-- it ticks faster as it nears its end
	local left = ( p.frames or 75 ) - age
	if age % math.max( 3, math.floor( left / 6 ) ) == 0 then
		fx_ring( x, y, 4, effect_color( p.element, 0.9 ), 8, 25, 0.15 )
	end
end

-- Cyclone: the creature (p.target) is caught up in a whirl of wind, p.height into the air, round and round; then let fall
MODES.cyclone = function( e, p, age )
	local target = math.floor( ( p.target or 0 ) + 0.5 )
	if target == 0 or not EntityGetIsAlive( target ) or age >= p.frames then
		if target ~= 0 and EntityGetIsAlive( target ) then push_creature( target, 0, 60, true ) end
		EntityKill( e )
		return
	end
	local tx, ty = EntityGetTransform( target )
	local rise = math.min( 1, age / 30 )
	local a = age * 0.25
	local cx, cy = p.cx + math.cos( a ) * 10, p.cy - ( p.height or 40 ) * rise
	push_creature( target, ( cx - tx ) * 8, ( cy - ty ) * 8, true )
	if age % 20 == 0 then seal_damage( target, 0.05 * ( p.power or 1 ), "DAMAGE_PROJECTILE", p.owner, tx, ty ) end
	for k = 0, 2 do
		local b = a * 1.5 + k * 2.1
		fx_dot( tx + math.cos( b ) * 9, ty - 4 + math.sin( b ) * 4 + k * 3, effect_color( p.element, 0.8, 0.7 ), -math.sin( b ) * 40, 0, 0.12 )
	end
end

-- Meteor Shower: every half a second one to three of the game's meteors come down on the place from far up the sky (as
-- its Meteor Rain throws them); they don't hurt the caster
MODES.meteors = function( e, p, age, x, y )
	if effect_done( e, p, age ) then return end
	if age % 30 ~= 0 then return end
	for _ = 1, Random( 1, 3 ) do
		local a = math.pi * Random( 15, 165 ) / 180
		local sx, sy = x + math.cos( a ) * 300, y - math.sin( a ) * 300
		local meteor = EntityLoad( "data/entities/projectiles/deck/meteor_rain_meteor.xml", sx, sy )
		GameShootProjectile( p.owner or 0, sx, sy, x + Random( -30, 30 ), y, meteor, true )
		local proj = EntityGetFirstComponentIncludingDisabled( meteor, "ProjectileComponent" )
		if proj then
			ComponentSetValue2( proj, "explosion_dont_damage_shooter", true )
			ComponentSetValue2( proj, "friendly_fire", false )
		end
	end
	if GameScreenshake then GameScreenshake( 10 ) end
end

EFFECT_MODES.resonance = MODES
