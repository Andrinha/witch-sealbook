-- Magic that takes hold of a place (manifest.lua): warmth and cold, water that swirls, boils or clears, a mist, time
-- that stops or runs back, pillars that ward off beasts, and the forbidden seals' curses. p.r is its radius.

local MODES = {}

local done = effect_done

-- a dome or ring of dots marking the zone's edge
local function edge( x, y, r, color, count, turn, half )
	for i = 0, count - 1 do
		local a = turn + ( half and math.pi + math.pi * i / ( count - 1 ) or i / count * 2 * math.pi )
		fx_dot( x + math.cos( a ) * r, y + math.sin( a ) * r, color, 0, 0, 0.06 )
	end
end

local function light( e, r, g, b, radius ) return effect_glow( e, r, g, b, radius, 1 ) end

-- Snowfending also thaws dense terrain and physical ice, not just loose snow.
-- Cold/toxic ice and snow-covered rock leave ordinary stone instead of releasing
-- another freezing or hazardous material. Frozen grass loses its icy appearance.
local SNOWFEND_THAWS = {
	snow = "water", snow_sticky = "water", snow_static = "water", snow_b2 = "water",
	ice = "water", ice_static = "water", ice_glass = "water", ice_glass_b2 = "water",
	ice_melting_perf_killer = "water", water_ice = "water",
	ice_blood_static = "blood", ice_blood_glass = "blood",
	ice_slime_static = "slime", ice_slime_glass = "slime",
	snowrock_static = "rock_static", ice_ceiling = "rock_static", ice_b2 = "rock_static",
	ice_acid_static = "rock_static", ice_acid_glass = "rock_static",
	ice_cold_static = "rock_static", ice_cold_glass = "rock_static",
	ice_radioactive_static = "rock_static", ice_radioactive_glass = "rock_static",
	ice_poison_static = "rock_static", ice_poison_glass = "rock_static",
	ice_meteor_static = "rock_static", grass_ice = "grass",
}
local snowfend_from, snowfend_to = {}, {}
for material, thawed in pairs( SNOWFEND_THAWS ) do
	snowfend_from[#snowfend_from + 1] = material
	snowfend_to[#snowfend_to + 1] = thawed
end
local SNOWFEND_FROM, SNOWFEND_TO = table.concat( snowfend_from, "," ), table.concat( snowfend_to, "," )

-- Snowfending: a warm dome - frozen matter thaws, falling drops turn to steam
MODES.snowfend = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	if age == 0 then
		convert_around( e, SNOWFEND_FROM, SNOWFEND_TO, p.r, 3 )
		convert_around( e, "water", "steam", p.r * 0.8, 1 )
		light( e, 255, 180, 110, p.r * 2 )
	end
	if age % 3 == 0 then edge( x, y, p.r, fx_color( "fire", 0.6, 0.5 ), 20, age * 0.004, true ) end
	if age % 4 == 0 then fx_dot( x + Random( -p.r, p.r ), y - Random( 0, p.r ), fx_color( "fire", 0.5, 0.7 ), 0, -10, 0.8 ) end
end

-- Warmth Retention: an even warmth - nothing freezes here and ice slowly melts
MODES.warmth_zone = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	if age == 0 then
		convert_around( e, MELTS.from, MELTS.to, p.r, 1 )
		light( e, 255, 170, 100, p.r * 2.5 )
	end
	if age % 3 == 0 then
		local a = Random( 0, 628 ) / 100
		local r = Random( 0, math.floor( p.r ) )
		fx_dot( x + math.cos( a ) * r, y + math.sin( a ) * r * 0.5, fx_color( "fire", 0.5, 0.6 ), 0, -8, 1.2 )
	end
	if age % 30 == 0 then
		for _, id in ipairs( creatures_in( x, y, p.r, 0, true ) ) do clear_effects( id, { "FROZEN" } ) end
	end
end

-- Torrential Flow: water swirls into a whirlpool that spins and drags enemies in
MODES.whirlpool = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	local r = p.r
	for i = 1, 3 do
		local a = Random( 0, 628 ) / 100
		local rr = Random( 4, math.floor( r ) )
		local speed = 60 + 1200 / rr
		GameCreateParticle( "water", x + math.cos( a ) * rr, y + math.sin( a ) * rr * 0.6, 1, -math.sin( a ) * speed, math.cos( a ) * speed * 0.6, false, false, true )
	end
	for i = 0, 2 do
		local t = ( age * 0.02 + i / 3 ) % 1
		fx_spiral( x, y, r * ( 1 - t ), r * ( 1 - t ) * 0.2, 0.8, fx_color( "water", 0.5, 0.8 ), 10, age * 0.15 + i * 2, 0.06 )
	end
	for _, id in ipairs( creatures_in( x, y, r, p.owner ) ) do
		local ex, ey = EntityGetTransform( id )
		local dx, dy = ex - x, ey - y
		local d = math.max( 1, math.sqrt( dx * dx + dy * dy ) )
		push_creature( id, ( -dy / d * 30 - dx / d * 12 ) * 0.3, ( dx / d * 30 - dy / d * 12 ) * 0.3 )
		if age % 30 == 0 then
			give_effect( id, MISC .. "effect_apply_wet.xml" )
			seal_damage( id, 0.1, "DAMAGE_DROWNING", p.owner, x, y )
		end
	end
end

-- Time Stop: inside, enemies and projectiles freeze for a few seconds
MODES.time_stop = function( e, p, age, x, y )
	local r = p.r
	if age >= p.frames then
		-- time goes on: the projectiles fly on as they were
		for _, id in ipairs( EntityGetInRadiusWithTag( x, y, r + 40, "projectile" ) or {} ) do
			for _, comp in ipairs( EntityGetComponent( id, "VariableStorageComponent" ) or {} ) do
				if ComponentGetValue2( comp, "name" ) == "witch_stopped" then
					local vx, vy = ( ComponentGetValue2( comp, "value_string" ) or "" ):match( "([-%d.e]+),([-%d.e]+)" )
					local vel = EntityGetFirstComponent( id, "VelocityComponent" )
					if vel and vx then ComponentSetValue2( vel, "mVelocity", tonumber( vx ), tonumber( vy ) ) end
					EntityRemoveComponent( id, comp )
				end
			end
		end
		fx_ring( x, y, r, fx_color( "air", 0.8 ), 40, 60, 0.5 )
		EntityKill( e )
		return
	end
	if age % 10 == 0 then
		for _, id in ipairs( creatures_in( x, y, r, p.owner ) ) do
			local held = false
			for _, child in ipairs( EntityGetAllChildren( id ) or {} ) do
				if EntityGetName( child ) == "witch_held_time" then held = true end
			end
			if not held then hold_creature( id, p.frames - age, "time", "air", p.owner ) end
		end
	end
	for _, id in ipairs( EntityGetInRadiusWithTag( x, y, r, "projectile" ) or {} ) do
		local vel = EntityGetFirstComponent( id, "VelocityComponent" )
		local proj = EntityGetFirstComponent( id, "ProjectileComponent" )
		if vel and proj and ComponentGetValue2( proj, "mWhoShot" ) ~= p.owner then
			local stopped = false
			for _, comp in ipairs( EntityGetComponent( id, "VariableStorageComponent" ) or {} ) do
				if ComponentGetValue2( comp, "name" ) == "witch_stopped" then stopped = true end
			end
			if not stopped then
				local vx, vy = ComponentGetValue2( vel, "mVelocity" )
				EntityAddComponent2( id, "VariableStorageComponent", { name = "witch_stopped", value_string = vx .. "," .. vy } )
			end
			ComponentSetValue2( vel, "mVelocity", 0, 0 )
			-- its time doesn't run out either
			ComponentSetValue2( proj, "lifetime", ComponentGetValue2( proj, "lifetime" ) + 1 )
		end
	end
	if age % 3 == 0 then edge( x, y, r, fx_color( "air", 0.7, 0.6 ), 28, -age * 0.002 ) end
	if age % 6 == 0 then fx_dot( x + Random( -r, r ) * 0.7, y + Random( -r, r ) * 0.7, fx_color( "air", 1, 0.8 ), 0, 0, 1 ) end
end

-- Rainflinger: a warm wind dries everything - water turns to steam, the caster dries and warms up
MODES.dry = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	if age == 0 then convert_around( e, "water,water_salt,water_swamp,mud", "steam,steam,steam,sand", p.r, 3 ) end
	for i = 1, 3 do
		local a = age * 0.2 + Random( 0, 628 ) / 100
		local rr = Random( 4, math.floor( p.r ) )
		fx_dot( x + math.cos( a ) * rr, y + math.sin( a ) * rr * 0.6, fx_color( "firestorm", 0.5, 0.7 ), -math.sin( a ) * 50, math.cos( a ) * 30, 0.3 )
	end
	if age % 20 == 0 then
		for _, id in ipairs( creatures_in( x, y, p.r + 20, 0, true ) ) do
			if EntityHasTag( id, "player_unit" ) then
				clear_effects( id, { "WET" } )
				give_effect( id, MISC .. "effect_protection_freeze.xml", 60 )
			end
		end
	end
end

-- Waterflinger: the liquid boils away into steam
MODES.boil = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	if age == 0 then convert_around( e, BOILS.from, BOILS.to, p.r, 5 ) end
	for i = 1, 3 do
		fx_dot( x + Random( -p.r, p.r ), y + Random( -p.r, p.r ) * 0.5, fx_color( "steam", 0.9, 0.8 ), Random( -5, 5 ), -Random( 20, 50 ), 0.6 )
	end
end

-- Wash Spring: everything around shines clean - water clears, poison and slime turn to water, stains wash off
MODES.wash_spring = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	if age == 0 then
		convert_around( e, FOULS.from, FOULS.to, p.r, 6 )
		EntityAddComponent2( e, "MagicConvertMaterialComponent", { radius = math.floor( p.r ), is_circle = true, clean_stains = true,
			loop = true, kill_when_finished = false, steps_per_frame = 6 } )
		for _, id in ipairs( creatures_in( x, y, p.r, 0, true ) ) do
			if EntityHasTag( id, "player_unit" ) then clear_effects( id, DIRT ) end
		end
		light( e, 200, 240, 255, p.r * 2 )
	end
	local grow = math.min( 1, age / 40 ) * p.r
	if age < 60 and age % 2 == 0 then edge( x, y, grow, fx_color( "shimmer", 0.7, 1 - age / 60 ), 24, 0 ) end
	for i = 1, 2 do fx_dot( x + Random( -p.r, p.r ), y + Random( -p.r, p.r ) * 0.6, fx_color( "shimmer", 0.9 ), 0, -8, 0.5 ) end
end

-- Purify: a wave of purification spreads from the seal - acid, poison, sludge and other foul liquid inside it turns
-- into clean water, cell for cell. It makes no water of its own and leaves clean water, stains and creatures alone.
MODES.purify = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	if age == 0 then convert_around( e, PURIFIES.from, PURIFIES.to, p.r, 6 ) end
	local grow = math.min( 1, age / 40 ) * p.r
	if age < 60 and age % 2 == 0 then edge( x, y, grow, fx_color( "water", 0.8, 1 - age / 60 ), 28, age * 0.02 ) end
	local a, d = Random( 0, 628 ) / 100, math.sqrt( Random( 0, 100 ) / 100 ) * grow
	fx_dot( x + math.cos( a ) * d, y + math.sin( a ) * d, fx_color( "shimmer", 0.9, 0.8 ), 0, -8, 0.5 )
end

-- Integration: the loose sand and earth inside the circle set into stone, snow into packed snow. It turns what
-- lies there, cell for cell, and makes no stone of its own. The ring closes in as the grains come together.
MODES.integrate = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	if age == 0 then
		convert_around( e, INTEGRATES.from, INTEGRATES.to, p.r, 6 )
		effect_sound( "earth", x, y )
	end
	local close = 1 - math.min( 1, age / 45 )
	if age < 45 and age % 2 == 0 then edge( x, y, p.r * ( 0.25 + 0.75 * close ), fx_color( "earth", 0.5, 0.4 + 0.6 * close ), 28, -age * 0.03 ) end
	if age < 60 then
		local a, d = Random( 0, 628 ) / 100, p.r * ( 0.4 + 0.6 * Random( 0, 100 ) / 100 )
		fx_dot( x + math.cos( a ) * d, y + math.sin( a ) * d, fx_color( "sand", 0.4, 0.8 ), -math.cos( a ) * d * 2, -math.sin( a ) * d * 2, 0.4 )
	end
end

-- Mist Basin: a thick fog - enemies lose sight of whoever is in it
MODES.mist = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	local fade = math.min( 1, age / 30, ( p.frames - age ) / 60 )
	for i = 1, 7 do
		local a = Random( 0, 628 ) / 100
		local rr = p.r * math.sqrt( Random( 0, 1000 ) / 1000 )
		GameCreateCosmeticParticle( FX_SPARK, x + math.cos( a ) * rr, y + math.sin( a ) * rr * 0.6, 1, Random( -6, 6 ), Random( -3, 3 ),
			color_abgr_merge( 220, 225, 235, math.floor( 140 * fade ) ), 1.5, 2.5, true, true, false, false, 0, 0 )
	end
	if age % 45 == 0 then
		for _, id in ipairs( creatures_in( x, y, p.r, 0, true ) ) do
			if EntityHasTag( id, "player_unit" ) then give_effect( id, MISC .. "effect_invisibility.xml", 60 ) end
		end
	end
end

-- Beastwarding: pillars of light rise round the caster - beasts are pushed out of the circle and keep away
MODES.beastward = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	local n = p.strong == 1 and 8 or 6
	if age == 0 then light( e, 255, 245, 200, p.r * 1.5 ) end
	for k = 0, n - 1 do
		local a = k / n * 2 * math.pi
		local px, py = x + math.cos( a ) * p.r, y + math.sin( a ) * p.r * 0.35
		local gx, gy = ground_below( px, py - 20, 60 )
		gy = gy or py
		if ( age + k ) % 2 == 0 then
			fx_dot( px + Random( -1, 1 ), gy - Random( 0, 28 ), effect_color( "light", 0.6 ), 0, -25, 0.4 )
		end
	end
	if age % 3 == 0 then
		for _, id in ipairs( creatures_in( x, y, p.r, p.owner ) ) do
			push_from( id, x, y, p.strong == 1 and 110 or 70 )
			if age % 30 == 0 then
				local ex, ey = EntityGetTransform( id )
				fx_burst( ex, ey - 4, effect_color( "light", 0.8 ), 6, 30, 0.3 )
			end
		end
	end
end

-- Dragon's Labyrinth (forbidden): space closes on itself - whoever leaves over the edge comes back from the other side
MODES.labyrinth = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	local r = p.r
	local inside = {}
	for id in effect_text( p.inside ):gmatch( "%d+" ) do inside[tonumber( id )] = true end
	local now = {}
	for _, id in ipairs( creatures_in( x, y, r + 30, 0, true ) ) do
		local ex, ey = EntityGetTransform( id )
		local dx, dy = ex - x, ey - y
		local d = math.sqrt( dx * dx + dy * dy )
		if d <= r then
			now[#now + 1] = id
		elseif inside[id] and d <= r + 30 then
			-- out over the edge: back in on the opposite side
			local k = ( r - 4 ) / d
			EntitySetTransform( id, x - dx * k, y - dy * k )
			fx_burst( ex, ey, fx_color( "vacuum", 0.6 ), 12, 40, 0.4 )
			fx_burst( x - dx * k, y - dy * k, fx_color( "vacuum", 0.6 ), 12, 40, 0.4 )
			now[#now + 1] = id
		end
	end
	effect_set( e, "inside", table.concat( now, "," ) )
	if age % 2 == 0 then
		for i = 0, 23 do
			local a = i / 24 * 2 * math.pi + age * 0.005
			local rune = ( i % 3 == 0 ) and 2 or 0
			fx_dot( x + math.cos( a ) * ( r + rune ), y + math.sin( a ) * ( r + rune ), fx_color( "vacuum", 0.4, 0.8 ), 0, 0, 0.05 )
		end
	end
end

-- Leech Counterclock: time runs backwards for the creatures here - they walk back the way they came, the polymorphed
-- turn back into what they were
REWIND = REWIND or {}
MODES.rewind = function( e, p, age, x, y )
	local record = REWIND[e] or {}
	REWIND[e] = record
	local half = math.floor( p.frames * 0.6 )
	if age < half then
		if age % 3 == 0 then
			local snap = {}
			for _, id in ipairs( creatures_in( x, y, p.r, p.owner ) ) do
				local ex, ey = EntityGetTransform( id )
				snap[id] = { ex, ey }
			end
			record[#record + 1] = snap
		end
	elseif age < p.frames then
		if age == half then
			for _, id in ipairs( creatures_in( x, y, p.r, p.owner, true ) ) do
				for _, name in ipairs( { "POLYMORPH", "POLYMORPH_RANDOM", "POLYMORPH_UNSTABLE" } ) do
					local comp = GameGetGameEffect( id, name )
					if comp and comp ~= 0 then ComponentSetValue2( comp, "frames", 1 ) end
				end
			end
			effect_sound( "magic", x, y )
		end
		-- back through the recorded positions, twice as fast
		local k = #record - math.floor( ( age - half ) * #record / math.max( 1, p.frames - half ) )
		local snap = record[math.max( 1, k )]
		for id, pos in pairs( snap or {} ) do
			if EntityGetIsAlive( id ) then
				EntitySetTransform( id, pos[1], pos[2] )
				push_creature( id, 0, 0, true )
				if age % 2 == 0 then fx_dot( pos[1], pos[2] - 5, fx_color( "crystal", 0.5, 0.7 ), 0, 0, 0.5 ) end
			end
		end
	else
		REWIND[e] = nil
		EntityKill( e )
		return
	end
	-- a clock whose hands run backwards
	if age % 2 == 0 then edge( x, y, p.r, fx_color( "crystal", 0.5, 0.5 ), 12, 0 ) end
	local speed = age < half and 0.05 or -0.4
	for k = 1, 8 do
		fx_dot( x + math.cos( age * speed ) * k * 2, y + math.sin( age * speed ) * k * 2, fx_color( "crystal", 0.7 ), 0, 0, 0.04 )
	end
end

-- Loop Chalice: the liquid around rises and swirls in the air in a cone, then flows back down
MODES.chalice = function( e, p, age, x, y )
	local gather = math.floor( p.frames * 0.3 )
	if age == 0 then
		EntityAddComponent2( e, "MaterialInventoryComponent", { drop_as_item = false, on_death_spill = true, leak_on_damage_percent = 0 } )
		EntityAddComponent2( e, "MaterialSuckerComponent", { material_type = 0, barrel_size = 1024, num_cells_sucked_per_frame = 5 } )
	end
	if age >= p.frames then
		fx_burst( x, y - 20, fx_color( "water", 0.6 ), 20, 50, 0.5 )
		EntityKill( e ) -- it spills what it holds
		return
	end
	if age < gather then
		-- it sweeps the pool in a widening spiral, drinking
		local t = age / gather
		local a = t * 6 * math.pi
		EntitySetTransform( e, p.x0 + math.cos( a ) * p.r * t, p.y0 + math.sin( a ) * p.r * 0.4 * t )
		return
	end
	EntitySetTransform( e, p.x0, p.y0 - 24 )
	local main = GetMaterialInventoryMainMaterial( e )
	local material = main ~= 0 and CellFactory_GetName( main ) or "water"
	local t = age - gather
	-- a cone of liquid spinning round, wide at the top
	for i = 1, 10 do
		local h = Random( 0, 1000 ) / 1000
		local a = t * 0.25 + h * 10 + i
		local rr = 3 + h * 16
		GameCreateCosmeticParticle( material, p.x0 + math.cos( a ) * rr, p.y0 - 4 - h * 34, 1, -math.sin( a ) * 30, 0, 0, 0.1, 0.2,
			true, false, false, false, 0, 0 )
	end
end

-- Vapor Bubble: a ball of clean fresh water gathers out of the air and grows, then falls
MODES.vapor = function( e, p, age, x, y )
	if age >= p.frames then
		fx_material( "water", x, y, math.floor( 60 + 200 * ( p.power or 1 ) ), 9 )
		EntityKill( e )
		return
	end
	local grow = 2 + 9 * age / p.frames
	for i = 1, 3 do
		local a = Random( 0, 628 ) / 100
		local rr = Random( 25, 45 )
		fx_dot( x + math.cos( a ) * rr, y + math.sin( a ) * rr, fx_color( "water", 0.8, 0.7 ), -math.cos( a ) * rr * 1.6, -math.sin( a ) * rr * 1.6, 0.6 )
	end
	for i = 0, 13 do
		local a = i / 14 * 2 * math.pi + age * 0.03
		fx_dot( x + math.cos( a ) * grow, y + math.sin( a ) * grow, fx_color( "water", 0.3, 0.9 ), 0, 0, 0.05 )
	end
	fx_dot( x - grow * 0.4, y - grow * 0.4, fx_color( "water", 1 ), 0, 0, 0.05 )
end

-- Forbidden Flames: a small violet flame that can't be put out - it burns far longer than fire
MODES.forbidden_fire = function( e, p, age, x, y, profile )
	dofile_once( "mods/witch_notebook/files/effects/flame_fields.lua" )
	if age >= p.frames then FlameFields.clear( e ); EntityKill( e ); return end
	if age == 0 then light( e, 200, 90, 255, 70 ) end
	local frame = { ox = x, oy = y, dx = 1, dy = 0, head = 0, speed = 0, frame_velocity = 0, cell = 1.5 }
	local s, preset = FlameFields.advance( e, p, age, frame, "violet", profile )
	local total = FlameFields.finish( e, s, p, frame, age, preset, 1, profile )
	effect_fire_loop( e, total > 0 )
	local started = profile and profile:begin()
	if age % 20 == 0 then
		for _, id in ipairs( creatures_in( x, y, 14, p.owner ) ) do
			local ex, ey = EntityGetTransform( id )
			if s.model.density( s, frame, ex, ey ) > 0.08 and not s.model.blocked( s, x, y, ex, ey ) then
				give_effect( id, MISC .. "effect_apply_on_fire.xml" )
				seal_damage( id, 0.15, "DAMAGE_FIRE", p.owner, x, y )
			end
		end
	end
	if profile then profile:finish( "damage", started ) end
	s.meter = nil
end

-- The Spell of Reduction: the creatures here shrink - small and weak for a while
MODES.reduction = function( e, p, age, x, y )
	if age == 0 then
		for _, id in ipairs( creatures_in( x, y, p.r, p.owner ) ) do
			local ex, ey = EntityGetTransform( id )
			local child = effect_spawn( "held", "shrunk", ex, ey, { frames = p.hold, owner = id, scale = 0.5, hx = ex, hy = ey } )
			EntityAddChild( id, child )
		end
		effect_sound( "curse", x, y )
	end
	if done( e, p, age ) then return end
	local r = p.r * ( 1 - age / p.frames )
	edge( x, y, r, fx_color( "flicker", 0.5 ), 20, age * 0.1 )
end

-- the creatures of a forbidden seal: not the caster, not bosses
local function victims( x, y, r, owner )
	local out = {}
	for _, id in ipairs( creatures_in( x, y, r, owner ) ) do
		if not EntityHasTag( id, "boss" ) then out[#out + 1] = id end
	end
	return out
end

local function wave( e, p, age, x, y, color )
	if done( e, p, age ) then return end
	edge( x, y, p.r * math.min( 1, age / 20 ), color, 30, 0 )
end

-- Petrification (forbidden; Coco's mother turned to stone): an aura grows slowly from where the seal falls, and all it
-- covers turns to grey stone - rock, sand and water (entities/petrify_aura.xml: the game's own conversion, as when the
-- world turns to gold at the end, a ring every few pixels of its growth), the creatures the front reaches, and the witch
-- too if they stay inside: the stone creeps over them. Bosses withstand it. p.grow: frames the aura takes to reach its
-- size p.r; p.stone: how far the stone has spread.
local PETRIFIED = "rock_static_grey"
local PETRIFY_RING = "mods/witch_notebook/files/entities/petrify_aura.xml"
local PETRIFY_STEP = 8     -- the stone spreads in rings this wide
local PETRIFY_BITE = 0.025 -- of the witch's health, every 5 frames inside the aura
MODES.petrify = function( e, p, age, x, y )
	if age == 0 then effect_sound( "statue", x, y ) end
	if done( e, p, age ) then return end
	local r = p.r * math.min( 1, ( age + 1 ) / math.max( 1, p.grow ) )
	local stone = p.stone or 0
	if r >= stone + PETRIFY_STEP or ( r >= p.r and stone < p.r ) then
		local ring = EntityLoad( PETRIFY_RING, x, y )
		local convert = EntityGetFirstComponentIncludingDisabled( ring, "MagicConvertMaterialComponent" )
		if convert then
			ComponentSetValue2( convert, "radius", math.ceil( r ) )
			ComponentSetValue2( convert, "min_radius", math.max( 0, math.floor( stone ) - 2 ) )
		end
		effect_set( e, "stone", r )
	end
	if age % 5 == 0 then
		for _, id in ipairs( victims( x, y, r, p.owner ) ) do
			local ex, ey = EntityGetTransform( id )
			EntityConvertToMaterial( id, PETRIFIED )
			EntityKill( id )
			fx_burst( ex, ey - 4, fx_color( "stone", 0.6 ), 10, 25, 0.5 )
		end
		for _, id in ipairs( EntityGetInRadiusWithTag( x, y, r, "player_unit" ) or {} ) do
			local health = EntityGetFirstComponent( id, "DamageModelComponent" )
			local ex, ey = EntityGetTransform( id )
			if health then
				EntityInflictDamage( id, ( ComponentGetValue2( health, "max_hp" ) or 4 ) * PETRIFY_BITE, "DAMAGE_CURSE", "Turned to stone",
					"NONE", 0, 0, e, ex, ey, 0 )
			end
			fx_burst( ex, ey - 6, fx_color( "stone", 0.4 ), 5, 12, 0.5 )
		end
	end
	-- the front: a ring of grey glitter, crystals shooting out of it; dust rises from the stone inside
	edge( x, y, r, fx_color( "stone", 0.55 ), math.floor( 10 + r * 0.5 ), age * 0.01 )
	if age % 3 == 0 then
		local a, len = Random( 0, 628 ) / 100, Random( 4, 11 )
		local c, s = math.cos( a ), math.sin( a )
		fx_line( x + c * r, y + s * r, x + c * ( r + len ), y + s * ( r + len ), fx_color( "stone", 0.85 ), 1.5, 0.35 )
	end
	if age % 2 == 0 and r > 4 then
		local a, d = Random( 0, 628 ) / 100, Random( 0, math.floor( r ) )
		fx_dot( x + math.cos( a ) * d, y + math.sin( a ) * d, fx_color( "stone", 0.3, 0.6 ), 0, -6, 1.0 )
	end
end

-- Memory Erasure: the creatures here forget the caster and stop attacking
MODES.oblivion = function( e, p, age, x, y )
	if age == 0 then
		local ids = {}
		for _, id in ipairs( victims( x, y, p.r, p.owner ) ) do
			give_effect( id, MISC .. "effect_charm.xml", p.hold )
			ids[#ids + 1] = id
		end
		effect_set( e, "ids", table.concat( ids, "," ) )
		p.ids = table.concat( ids, "," )
	end
	if done( e, p, age ) then return end
	if age % 12 == 0 then
		for id in effect_text( p.ids ):gmatch( "%d+" ) do
			id = tonumber( id )
			if EntityGetIsAlive( id ) then
				local ex, ey = EntityGetTransform( id )
				fx_dot( ex + Random( -3, 3 ), ey - 14, fx_color( "smoke", 0.5, 0.7 ), Random( -5, 5 ), -8, 0.8 )
			end
		end
	end
	if age < 30 then edge( x, y, p.r * age / 30, fx_color( "smoke", 0.4, 0.7 ), 30, 0 ) end
end

-- Scalewolf Curse (forbidden): the creature turns into a wolf
MODES.wolf_curse = function( e, p, age, x, y )
	if age == 0 then
		local id = nearest_creature( x, y, p.r, p.owner )
		if id and not EntityHasTag( id, "boss" ) then
			local ex, ey = EntityGetTransform( id )
			EntityKill( id )
			EntityLoad( "data/entities/animals/wolf.xml", ex, ey )
			fx_burst( ex, ey - 6, fx_color( "vacuum", 0.4 ), 40, 60, 0.7 )
			effect_sound( "curse", ex, ey )
		end
	end
	wave( e, p, age, x, y, fx_color( "vacuum", 0.4 ) )
end

-- Anti-Scalewolf Curse: the polymorphed around turn back into themselves
MODES.unpolymorph = function( e, p, age, x, y )
	if age == 0 then
		for _, id in ipairs( creatures_in( x, y, p.r, 0, true ) ) do
			for _, name in ipairs( { "POLYMORPH", "POLYMORPH_RANDOM", "POLYMORPH_UNSTABLE" } ) do
				local comp = GameGetGameEffect( id, name )
				if comp and comp ~= 0 then ComponentSetValue2( comp, "frames", 1 ) end
			end
		end
	end
	wave( e, p, age, x, y, fx_color( "air", 0.8 ) )
end

-- Slime Rendering (forbidden): the creature melts into slime
MODES.slime = function( e, p, age, x, y )
	if age == 0 then
		local id = nearest_creature( x, y, p.r, p.owner )
		local dm = id and EntityGetFirstComponent( id, "DamageModelComponent" )
		if dm and not EntityHasTag( id, "boss" ) then
			local ex, ey = EntityGetTransform( id )
			if ComponentGetValue2( dm, "max_hp" ) <= 20 then
				EntityConvertToMaterial( id, "slime" )
				EntityKill( id )
			else
				give_effect( id, MISC .. "effect_slimy.xml", 600 )
				seal_damage( id, ComponentGetValue2( dm, "max_hp" ) * 0.3, "DAMAGE_CURSE", p.owner, ex, ey )
			end
			fx_material( "slime", ex, ey - 4, 60, 6 )
		end
	end
	wave( e, p, age, x, y, fx_color( "mud", 0.3 ) )
end

-- Spike: stone spikes burst out of the ground and fly every way
MODES.spikes = function( e, p, age, x, y )
	if age == 0 then
		local gx, gy = ground_below( x, y - 10, 80 )
		gy = gy or y
		local n = math.floor( 5 + 2 * ( p.power or 1 ) )
		for i = 1, n do
			local a = math.rad( -160 + 140 * ( i - 1 ) / ( n - 1 ) ) + Random( -10, 10 ) / 100
			local sx, sy = x + math.cos( a ) * 4, gy - 3
			local shard = EntityLoad( carrier_file( "stone", "bolt" ), sx, sy )
			GameShootProjectile( p.owner or 0, sx, sy, sx + math.cos( a ) * 100, sy + math.sin( a ) * 100, shard, true )
		end
		fx_material( "sand", x, gy - 3, 40, 6, 0, -60 )
		effect_sound( "earth", x, gy )
	end
	done( e, p, age )
end

-- Wallwarding: the walls around the caster give way - a roomy hollow is carved out
MODES.wallward = function( e, p, age, x, y )
	if age == 0 then
		EntityAddComponent2( e, "CellEaterComponent", { radius = p.r, eat_probability = 70, eat_dynamic_physics_bodies = false } )
		effect_sound( "earth", x, y )
	end
	if done( e, p, age ) then return end
	for i = 1, 6 do
		local a = Random( 0, 628 ) / 100
		fx_dot( x + math.cos( a ) * p.r, y + math.sin( a ) * p.r, fx_color( "earth", 0.3 ), -math.cos( a ) * 30, -math.sin( a ) * 30, 0.5, 60 )
	end
end

-- Smokesculpting: copies of the enemies made of smoke stand beside them - they get confused and strike at them
MODES.smoke_copies = function( e, p, age, x, y )
	if age == 0 then
		local n = 0
		for _, id in ipairs( creatures_in( x, y, p.r, p.owner ) ) do
			if n < 6 then
				n = n + 1
				local ex, ey = EntityGetTransform( id )
				local side = Random( 0, 1 ) == 0 and -1 or 1
				effect_spawn( "mover", "copy", ex + side * 12, ey, { frames = p.hold, owner = p.owner or 0, of = id, side = side } )
			end
		end
		if n == 0 then GamePrint( "No enemies nearby to sculpt smoke copies of" ) end
	end
	done( e, p, age )
end

-- Pouch Guidance: at the guiding mark gold and small things gather, sliding towards it
MODES.guidance_items = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	local c = fx_color( "wind", 0.7 )
	for i = 0, 3 do
		local a = age * 0.05 + i / 4 * 2 * math.pi
		fx_dot( x + math.cos( a ) * 5, y + math.sin( a ) * 5, c, 0, 0, 0.06 )
	end
	for _, tag in ipairs( { "gold_nugget", "item_pickup" } ) do
		for _, id in ipairs( EntityGetInRadiusWithTag( x, y, p.r, tag ) or {} ) do
			if EntityGetRootEntity( id ) == id then
				local ix, iy = EntityGetTransform( id )
				local vel = EntityGetFirstComponent( id, "VelocityComponent" )
				if vel then
					local dx, dy = x - ix, y - iy
					local d = math.max( 1, math.sqrt( dx * dx + dy * dy ) )
					ComponentSetValue2( vel, "mVelocity", dx / d * 80, dy / d * 80 - 20 )
				end
				if age % 4 == 0 then fx_dot( ix, iy, c, ( x - ix ) * 0.5, ( y - iy ) * 0.5, 0.4 ) end
			end
		end
	end
	PhysicsApplyForceOnArea( function( body, mass, bx, by )
		local dx, dy = x - bx, y - by
		local d = math.sqrt( dx * dx + dy * dy )
		if d < 3 or d > p.r then return bx, by, 0, 0, 0 end
		return bx, by, dx / d * mass * 40, dy / d * mass * 40 - mass * 10, 0
	end, e, x - p.r, y - p.r, x + p.r, y + p.r )
end

-- Fish Guidance: a guiding mark; fish of water fly to it from the caster and drench the enemies round it
MODES.guidance_fish = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	local c = fx_color( "water", 0.6 )
	for i = 0, 5 do
		local a = age * 0.04 + i / 6 * 2 * math.pi
		fx_dot( x + math.cos( a ) * 7, y + math.sin( a ) * 7, c, 0, 0, 0.06 )
	end
	local owner = effect_owner( p )
	if owner and age % 30 == 10 then
		local ox, oy = EntityGetTransform( owner )
		effect_spawn( "mover", "dart", ox, oy - 8, { frames = 120, owner = owner, shape = "fish", element = "water", tx = x, ty = y,
			speed = 180 } )
	end
end

-- Stream Crossing Ferry: a long even wind blows where the caster aimed, carrying enemies and things along
MODES.gale = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	local dx, dy, len, width = p.dx, p.dy, p.len or 220, 24
	local nx, ny = -dy, dx
	for i = 1, 5 do
		local t = Random( 0, 1000 ) / 1000 * len
		local s = Random( -width, width )
		fx_dot( x + dx * t + nx * s, y + dy * t + ny * s, fx_color( "wind", 0.6, 0.6 ), dx * 160, dy * 160, 0.3 )
	end
	local cx, cy = x + dx * len / 2, y + dy * len / 2
	for _, id in ipairs( creatures_in( cx, cy, len / 2 + width, p.owner ) ) do
		local ex, ey = EntityGetTransform( id )
		local t = ( ex - x ) * dx + ( ey - y ) * dy
		local s = ( ex - x ) * nx + ( ey - y ) * ny
		if t > 0 and t < len and math.abs( s ) < width then push_creature( id, dx * 18, dy * 18 - 3 ) end
	end
	PhysicsApplyForceOnArea( function( body, mass, bx, by )
		local t = ( bx - x ) * dx + ( by - y ) * dy
		local s = ( bx - x ) * nx + ( by - y ) * ny
		if t < 0 or t > len or math.abs( s ) > width then return bx, by, 0, 0, 0 end
		return bx, by, dx * mass * 30, dy * mass * 30, 0
	end, e, math.min( x, x + dx * len ) - width, math.min( y, y + dy * len ) - width, math.max( x, x + dx * len ) + width,
		math.max( y, y + dy * len ) + width )
end

EFFECT_MODES.zone = MODES
