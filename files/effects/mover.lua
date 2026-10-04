-- Magic that moves on its own (manifest.lua): sculptures of the element in a creature's shape - a dragon, a horse, a
-- bird, fish, an owlcat, a leech and four more decorative species - and a whirlwind, a
-- rolling wave, the Capture Pennant's ribbon, doubles of smoke and puppets that draw enemies to themselves, the
-- Sasaran cloak, a golem. The state that must survive is kept in the effect's variables; trails live in TRAILS.

local MODES = {}
dofile_once( "mods/witch_notebook/files/effects/sculpture_visuals.lua" )
TRAILS = TRAILS or {}
local CLIMB = 18 -- how high a step or slope the magic running on the ground climbs

local function finish( e )
	TRAILS[e] = nil
	EntityKill( e )
end

local function done( e, p, age )
	if age >= p.frames then
		finish( e )
		return true
	end
end

-- enemies take the effect for one of the caster's: something to attack instead of them
local function decoy( e, hp, w, h )
	EntityAddTag( e, "witch_decoy" ) -- the caster's own: their magic leaves it be (lib.lua creatures_in)
	EntityAddTag( e, "mortal" )
	EntityAddTag( e, "hittable" )
	EntityAddComponent2( e, "GenomeDataComponent", { herd_id = StringToHerdId( "player" ), food_chain_rank = 20 } )
	EntityAddComponent2( e, "DamageModelComponent", { hp = hp, max_hp = hp, air_needed = false, falling_damages = false,
		fire_probability_of_ignition = 0, materials_damage = false, blood_material = "", blood_spray_material = "",
		ragdoll_filenames_file = "", create_ragdoll = false, ui_report_damage = false, drop_items_on_death = false } )
	EntityAddComponent2( e, "HitboxComponent", { aabb_min_x = -w, aabb_max_x = w, aabb_min_y = -h, aabb_max_y = 2 } )
end

local function pos( e, p, x, y )
	return p.px or x, p.py or y
end

-- the Sign of Mimicry: the caster's cursor instead of where the magic was cast
local function target_of( p, tx, ty )
	if p.mimic ~= 1 then return tx, ty end
	local owner = effect_owner( p )
	local controls = owner and EntityGetFirstComponent( owner, "ControlsComponent" )
	if not controls then return tx, ty end
	return ComponentGetValue2( controls, "mMousePosition" )
end

local function move_to( e, x, y, vx, vy )
	EntitySetTransform( e, x, y )
	effect_set( e, "px", x )
	effect_set( e, "py", y )
	if vx then
		effect_set( e, "vx", vx )
		effect_set( e, "vy", vy )
	end
end

-- steers velocity (vx, vy) towards (tx, ty) at 'speed', turning by 'turn' (0..1) a frame
local function steer( x, y, vx, vy, tx, ty, speed, turn )
	local dx, dy = tx - x, ty - y
	local d = math.max( 1, math.sqrt( dx * dx + dy * dy ) )
	local wx, wy = dx / d * speed, dy / d * speed
	return vx + ( wx - vx ) * turn, vy + ( wy - vy ) * turn
end

-- what the element does to whom it touches
local function strike( id, element, power, caster, x, y, dir_x, dir_y )
	if element == "light" then return end -- illumination does not wound or push creatures
	local kinds = { water = "DAMAGE_PROJECTILE", steam = "DAMAGE_FIRE", fire = "DAMAGE_FIRE", smoke = "DAMAGE_PROJECTILE",
		light = "DAMAGE_PROJECTILE", earth = "DAMAGE_PROJECTILE", sand = "DAMAGE_PROJECTILE", stone = "DAMAGE_PROJECTILE" }
	seal_damage( id, 0.25 * power, kinds[element] or "DAMAGE_PROJECTILE", caster, x, y )
	local look = DICTIONARY_LOOKS[element]
	if look and look.status and look.status ~= "" then give_effect( id, look.status ) end
	push_creature( id, ( dir_x or 0 ) * 120, ( dir_y or 0 ) * 120 - 60 )
end

---- sculptures ----

local GAIT_SPEED = { scalewolf = 1.2, liongoat = .85, frillram = .7 }

local function body_color( element, white, alpha )
	return effect_color( element, white, alpha )
end

-- the dragon: its head (the Dragon sigil) seeks enemies, its long body follows the path of the head
local function dragon( e, p, age, x, y )
	local big = p.big or 1
	local px, py = pos( e, p, x, y )
	local vx, vy = p.vx or 0, p.vy or -60
	local trail = TRAILS[e] or {}
	TRAILS[e] = trail
	if age >= p.frames then
		-- it ends in a lily: a flower of its element, then a splash
		if p.element == "water" or p.element == "storm" or p.element == "steam" then
			effect_spawn( "light", "bloom", px, py, { frames = 60, element = "water" } )
		else
			fx_burst( px, py, body_color( p.element, 0.4 ), 60, 90, 0.8 )
		end
		finish( e )
		return
	end
	-- seek: the nearest enemy near the target area, otherwise circle over it
	local target = p.element ~= "light" and nearest_creature( px, py, 160 * big, p.owner )
	local tx, ty
	if target then
		tx, ty = EntityGetTransform( target )
		ty = ty - 6
	else
		local a = age * 0.04
		local cx, cy = target_of( p, p.tx, p.ty )
		tx, ty = cx + math.cos( a ) * 50 * big, cy - 20 + math.sin( a * 2 ) * 20
	end
	if p.mimic == 1 then tx, ty = target_of( p, tx, ty ) end
	vx, vy = steer( px, py, vx, vy, tx, ty, 150 * big, 0.06 )
	-- it winds as it flies
	local speed = math.sqrt( vx * vx + vy * vy )
	local wig = math.sin( age * 0.18 ) * 0.9
	px, py = px + ( vx - vy / math.max( speed, 1 ) * 40 * wig ) / 60, py + ( vy + vx / math.max( speed, 1 ) * 40 * wig ) / 60
	move_to( e, px, py, vx, vy )
	table.insert( trail, 1, { px, py } )
	local length = math.floor( 34 * big )
	while #trail > length do table.remove( trail ) end
	-- the body: a thick line with a spine of brighter scales, thinning to the tail
	local main, bright = body_color( p.element, 0.25, 0.9 ), body_color( p.element, 0.75 )
	for i = 2, #trail, 1 do
		local a, b = trail[i - 1], trail[i]
		local t = i / length
		local w = ( 1 - t ) * 3.2 * big + 0.6
		local nx, ny = -( b[2] - a[2] ), b[1] - a[1]
		local n = math.max( 0.01, math.sqrt( nx * nx + ny * ny ) )
		nx, ny = nx / n, ny / n
		fx_dot( b[1] + nx * w, b[2] + ny * w, main, 0, 0, 0.05 )
		fx_dot( b[1] - nx * w, b[2] - ny * w, main, 0, 0, 0.05 )
		fx_line( b[1] - nx * w, b[2] - ny * w, b[1] + nx * w, b[2] + ny * w, main, 1.5, 0.06 )
		if i % 3 == 0 then fx_dot( b[1], b[2], bright, 0, 0, 0.05 ) end
		if i % 7 == 0 then -- little fins
			fx_dot( b[1] + nx * ( w + 2 ), b[2] + ny * ( w + 2 ), bright, 0, 0, 0.05 )
		end
	end
	sculpture_dragon_head( px, py, big, math.atan2( vy, vx ), p.element, math.min( 1, ( p.frames - age ) / 40 ) )
	if p.element == "water" or p.element == "storm" then
		if age % 3 == 0 then GameCreateParticle( "water", px, py, 1, vx * 0.2, vy * 0.2, false, false, true ) end
	elseif p.element == "steam" then
		if age % 2 == 0 then GameCreateParticle( "steam", px, py, 1, 0, -10, false, false, true ) end
	elseif p.element == "fire" then
		if age % 4 == 0 then GameCreateParticle( "fire", px, py, 1, 0, 0, false, false, true ) end
	end
	-- it strikes whoever its head meets
	if age % 8 == 0 then
		for _, id in ipairs( creatures_in( px, py, 10 * big, p.owner ) ) do
			strike( id, p.element, p.power or 1, p.owner, px, py, vx / math.max( speed, 1 ), vy / math.max( speed, 1 ) )
		end
	end
end

-- the horse: gallops along the ground where the caster aimed and knocks enemies over
local function horse( e, p, age, x, y )
	local px, py = pos( e, p, x, y )
	local dir = ( p.dx or 1 ) >= 0 and 1 or -1
	if done( e, p, age ) then return end
	local gait = GAIT_SPEED[p.shape] or 1
	local nx = px + dir * 2.6 * gait * ( p.speed or 1 )
	-- it runs up and down slopes: only a wall higher than its head stops it
	local blocked = RaytraceSurfaces( px, py - CLIMB, nx + dir * 6, py - CLIMB )
	if blocked then
		fx_burst( px, py - 8, body_color( p.element, 0.5 ), 30, 60, 0.6 )
		if p.element == "water" or p.element == "storm" then fx_material( "water", px, py - 8, 40, 6 ) end
		finish( e )
		return
	end
	local gx, gy = ground_below( nx, py - CLIMB, 60 + CLIMB )
	local ny = gy and ( gy - 1 ) or ( py + 3 )
	move_to( e, nx, ny )
	local gallop = math.abs( math.sin( age * ( p.shape == "frillram" and .2 or .3 ) ) ) * ( p.shape == "frillram" and 7 or 4 )
	sculpture_quadruped( p.shape or "horse", nx, ny - ( 12 + gallop ) * ( p.big or 1 ), p.big or 1,
		dir, age, p.element, math.min( 1, ( p.frames - age ) / 30 ) )
	if p.shape == "torchstag" and p.element == "fire" then
		-- Flickering antler tips and a rising plume make this a stag of flame.
		for i = 0, 2 do
			local ax, ay = nx + dir * ( 8 + i * 2 ) * p.big, ny - ( 28 + gallop + math.sin( age * .4 + i ) * 3 ) * p.big
			fx_dot( ax, ay, body_color( "fire", .85 ), -dir * 8, -20, .18 )
			if age % 4 == 0 then GameCreateParticle( "fire", ax, ay, 1, 0, -10, false, false, true ) end
		end
	end
	if p.element == "fire" then
		if age % 2 == 0 then GameCreateParticle( "fire", nx - dir * 4, ny - 2, 1, -dir * 20, -10, false, false, true ) end
	elseif p.element == "water" or p.element == "storm" then
		if age % 2 == 0 then GameCreateParticle( "water", nx - dir * 5, ny - 3, 1, -dir * 40, -30, false, false, true ) end
	else
		if age % 2 == 0 then fx_dot( nx - dir * 6, ny - 2, body_color( p.element, 0.6 ), -dir * 20, -10, 0.4 ) end
	end
	if age % 6 == 0 then
		for _, id in ipairs( creatures_in( nx, ny - 8, 12, p.owner ) ) do strike( id, p.element, p.power or 1, p.owner, nx, ny, dir, -0.3 ) end
	end
end

-- the bird: flies up and circles round the caster; enemies go for it while it shines
local function bird( e, p, age, x, y )
	local owner = effect_owner( p )
	if not owner or done( e, p, age ) then
		if not owner then finish( e ) end
		return
	end
	if age == 0 then
		decoy( e, 3, 5, 5 )
		EntityAddComponent2( e, "LightComponent", { radius = 70, r = 255, g = 240, b = 180, fade_out_time = 1 } )
	end
	local ox, oy = EntityGetTransform( owner )
	local r = math.min( 50, 10 + age * 0.5 )
	local a = age * 0.045
	local tx, ty = ox + math.cos( a ) * r, oy - 34 + math.sin( a * 2 ) * 10
	local px, py = pos( e, p, x, y )
	px, py = px + ( tx - px ) * 0.1, py + ( ty - py ) * 0.1
	move_to( e, px, py )
	local flip = math.cos( a + math.pi / 2 ) < 0
	sculpture_bird( px, py, p.big or 1, flip, age, p.element, math.min( 1, ( p.frames - age ) / 40 ) )
	if age % 3 == 0 then fx_dot( px, py, body_color( p.element, .8 ), flip and 8 or -8, 3, .4 ) end
end

-- the fish: swims through the air to the enemies near where it was cast and drenches them
local function fish( e, p, age, x, y )
	local px, py = pos( e, p, x, y )
	local vx, vy = p.vx or 0, p.vy or 0
	if done( e, p, age ) then return end
	local cx, cy = target_of( p, p.tx, p.ty )
	local target = p.element ~= "light" and nearest_creature( cx, cy, 140, p.owner )
	local tx, ty = cx + math.cos( age * 0.05 ) * 30, cy + math.sin( age * 0.08 ) * 12
	if target then
		tx, ty = EntityGetTransform( target )
		ty = ty - 5
	end
	vx, vy = steer( px, py, vx, vy, tx, ty, 140, 0.08 )
	px, py = px + vx / 60, py + vy / 60 + math.sin( age * 0.4 ) * 0.5
	move_to( e, px, py, vx, vy )
	sculpture_fish( px, py, p.big or 1, math.atan2( vy, vx ), age, p.element, math.min( 1, ( p.frames - age ) / 30 ) )
	if age % 4 == 0 then fx_dot( px, py, body_color( p.element, 0.8 ), 0, 5, 0.4 ) end
	if target and ( tx - px ) ^ 2 + ( ty - py ) ^ 2 < 64 then
		strike( target, p.element, p.power or 1, p.owner, px, py, vx / 140, vy / 140 )
		if p.element == "water" or p.element == "storm" then fx_material( "water", px, py, 30, 5 ) end
		fx_burst( px, py, body_color( p.element, 0.6 ), 16, 50, 0.4 )
		move_to( e, px - vx * 0.3, py - vy * 0.3, -vx, -vy - 60 )
	end
end

-- the owlcat: glows and flies after the caster, lighting the way, and pecks at enemies
local function owlcat( e, p, age, x, y )
	local owner = effect_owner( p )
	if not owner or done( e, p, age ) then
		if not owner then finish( e ) end
		return
	end
	if age == 0 then EntityAddComponent2( e, "LightComponent", { radius = 110, r = 255, g = 235, b = 170, fade_out_time = 1 } ) end
	local ox, oy = EntityGetTransform( owner )
	local px, py = pos( e, p, x, y )
	local tx, ty = ox - 14, oy - 26 + math.sin( age * 0.07 ) * 4
	local prey = math.floor( ( p.prey or 0 ) + 0.5 )
	if p.element ~= "light" and age % 40 == 0 then
		prey = nearest_creature( px, py, 70, owner ) or 0
		effect_set( e, "prey", prey )
	end
	if p.element ~= "light" and prey ~= 0 and EntityGetIsAlive( prey ) and age % 40 < 20 then
		tx, ty = EntityGetTransform( prey )
		ty = ty - 6
		if ( tx - px ) ^ 2 + ( ty - py ) ^ 2 < 50 and age % 40 == 12 then
			strike( prey, p.element, 0.8, owner, px, py, 0, 0 )
			fx_burst( px, py, body_color( "light", 0.7 ), 10, 40, 0.3 )
		end
	end
	px, py = px + ( tx - px ) * 0.12, py + ( ty - py ) * 0.12
	move_to( e, px, py )
	local face_left = tx < px
	sculpture_owlcat( px, py, p.big or 1, face_left, age, p.element, math.min( 1, ( p.frames - age ) / 40 ) )
	if age % 6 == 0 then fx_dot( px + Random( -4, 4 ), py + 6, body_color( p.element, 0.8 ), 0, 10, 0.5 ) end
end

-- the leech: crawls along the ground to the nearest enemy, latches on, blinds it and drains it
local function leech( e, p, age, x, y )
	local px, py = pos( e, p, x, y )
	if done( e, p, age ) then return end
	local host = math.floor( ( p.host or 0 ) + 0.5 )
	local c = body_color( p.element, 0.4 )
	if host ~= 0 and EntityGetIsAlive( host ) then
		local hx, hy = EntityGetTransform( host )
		move_to( e, hx, hy - 6 )
		sculpture_leech( hx, hy - 6, ( p.big or 1 ) * .65, age, p.element, math.min( 1, ( p.frames - age ) / 30 ) )
		if age % 20 == 0 then
			give_effect( host, MISC .. "effect_blindness.xml", 60 )
			seal_damage( host, 0.08 * ( p.power or 1 ), "DAMAGE_PROJECTILE", p.owner, hx, hy )
			fx_dot( hx, hy - 6, body_color( p.element, 0.9 ), 0, -20, 0.5 )
		end
		return
	end
	local target = nearest_creature( px, py, 220, p.owner )
	local dir = 1
	if target then
		local tx, ty = EntityGetTransform( target )
		dir = tx >= px and 1 or -1
		if ( tx - px ) ^ 2 + ( ty - py ) ^ 2 < 100 then
			effect_set( e, "host", target )
			fx_burst( px, py, c, 12, 40, 0.3 )
			return
		end
	else
		dir = ( p.dx or 1 ) >= 0 and 1 or -1
	end
	-- it inches along: stretch, then pull up
	local inch = ( math.sin( age * 0.25 ) + 1 ) * 0.9
	local nx = px + dir * inch
	local gx, gy = ground_below( nx, py - CLIMB, 40 + CLIMB )
	local ny = gy and gy - 2 or py + 1
	move_to( e, nx, ny )
	sculpture_leech( nx, ny - 5, ( p.big or 1 ) * .65, age, p.element, math.min( 1, ( p.frames - age ) / 30 ) )
end

MODES.sculpture = function( e, p, age, x, y )
	local shape = p.shape
	if age == 0 and p.element == "light" and shape ~= "bird" and shape ~= "owlcat" then
		EntityAddComponent2( e, "LightComponent", { radius = 75 * ( p.big or 1 ), r = 255, g = 240, b = 180,
			offset_y = ( shape == "horse" or shape == "scalewolf" or shape == "torchstag" or shape == "liongoat" or shape == "frillram" ) and -12 or 0,
			fade_out_time = 1 } )
	end
	if shape == "dragon" then dragon( e, p, age, x, y )
	elseif shape == "horse" or shape == "scalewolf" or shape == "torchstag" or shape == "liongoat" or shape == "frillram" then horse( e, p, age, x, y )
	elseif shape == "bird" then bird( e, p, age, x, y )
	elseif shape == "fish" then fish( e, p, age, x, y )
	elseif shape == "owlcat" then owlcat( e, p, age, x, y )
	elseif shape == "leech" then leech( e, p, age, x, y )
	else finish( e ) end
end

-- a sculpture flying straight to a point and splashing there (Fish Guidance)
MODES.dart = function( e, p, age, x, y )
	local px, py = pos( e, p, x, y )
	local dx, dy = p.tx - px, p.ty - py
	local d = math.sqrt( dx * dx + dy * dy )
	if d < 6 or age >= p.frames then
		if p.element == "water" then fx_material( "water", px, py, 25, 5 ) end
		fx_burst( px, py, body_color( p.element, 0.6 ), 14, 50, 0.4 )
		for _, id in ipairs( creatures_in( px, py, 24, p.owner ) ) do strike( id, p.element, 1, p.owner, px, py, dx / math.max( d, 1 ), 0 ) end
		finish( e )
		return
	end
	local step = math.min( d, ( p.speed or 150 ) / 60 )
	local wig = math.sin( age * 0.5 ) * 0.6
	px, py = px + dx / d * step - dy / d * wig, py + dy / d * step + dx / d * wig
	move_to( e, px, py )
	draw_shape( sigil_points( p.shape or "fish" ), px, py, 10, math.atan2( dy, dx ), dx < 0, body_color( p.element, 0.35 ), 0.06, 0.6 )
end

---- wind and water ----

-- Wayward Whorlwind: a whirlwind wanders about, catching up things and enemies
MODES.whirlwind = function( e, p, age, x, y )
	local px, py = pos( e, p, x, y )
	if done( e, p, age ) then return end
	local target = p.mimic ~= 1 and nearest_creature( px, py, 160, p.owner )
	local tx = target and select( 1, EntityGetTransform( target ) ) or ( p.tx + math.sin( age * 0.013 ) * 60 )
	if p.mimic == 1 then tx = target_of( p, tx, py ) end
	local vx = ( p.vx or 0 ) + ( ( tx > px and 1 or -1 ) * 50 - ( p.vx or 0 ) ) * 0.02
	local nx = px + vx / 60
	local gx, gy = ground_below( nx, py - 30, 90 )
	local ny = gy and gy - 2 or py
	if RaytraceSurfaces( px, py - CLIMB, nx + ( vx > 0 and 8 or -8 ), py - CLIMB ) then vx = -vx; nx = px end
	move_to( e, nx, ny, vx, 0 )
	-- the funnel: rings of wind, wider as they rise, turning fast
	local c = fx_color( "wind", 0.55, 0.75 )
	for k = 0, 9 do
		local h = k * 5
		local r = 3 + k * 1.6
		local sway = math.sin( age * 0.05 + k * 0.4 ) * k * 0.6
		for s = 0, 2 do
			local a = age * 0.35 + k * 0.7 + s * 2.1
			fx_dot( nx + sway + math.cos( a ) * r, ny - h + math.sin( a ) * r * 0.25, c, 0, 0, 0.06 )
		end
	end
	if age % 3 == 0 then fx_dot( nx + Random( -8, 8 ), ny - 1, fx_color( "earth", 0.4 ), Random( -30, 30 ), -Random( 20, 60 ), 0.5, 80 ) end
	for _, id in ipairs( creatures_in( nx, ny - 20, 24, p.owner ) ) do
		local ex, ey = EntityGetTransform( id )
		local side = ex > nx and -1 or 1
		push_creature( id, side * 12, -16, false )
		if age % 30 == 0 then seal_damage( id, 0.1, "DAMAGE_PROJECTILE", p.owner, nx, ny ) end
	end
	PhysicsApplyForceOnArea( function( body, mass, bx, by )
		local dx = bx - nx
		if math.abs( dx ) > 24 or by < ny - 60 or by > ny + 5 then return bx, by, 0, 0, 0 end
		return bx, by, -dx * mass * 2 + mass * 20 * ( dx > 0 and 1 or -1 ), -mass * 30, 0
	end, e, nx - 24, ny - 60, nx + 24, ny + 5 )
end

-- Rushing Wave, the Sigil of Undulation: a big wave rolls along the ground where the caster aimed
MODES.wave = function( e, p, age, x, y )
	local px, py = pos( e, p, x, y )
	local dir = ( p.dx or 1 ) >= 0 and 1 or -1
	if done( e, p, age ) then return end
	local nx = px + dir * 3.2
	if RaytraceSurfaces( px, py - CLIMB, nx + dir * 8, py - CLIMB ) then
		fx_material( p.material or "water", px, py - 10, 60, 8, -dir * 30, -40 )
		finish( e )
		return
	end
	local gx, gy = ground_below( nx, py - 30, 90 )
	local ny = gy and gy - 1 or py
	move_to( e, nx, ny )
	local h = 18 * math.min( 1, age / 15 ) * ( p.big or 1 )
	local c = effect_color( p.element, 0.3, 0.9 )
	-- the wave's face, curling over at the crest
	for k = 0, 12 do
		local t = k / 12
		local cx = nx - dir * ( 1 - t ) * 12 + dir * math.sin( t * math.pi ) * 4
		local cy = ny - t * h
		fx_dot( cx, cy, c, dir * 60, 0, 0.08 )
		if t > 0.7 then fx_dot( cx + dir * ( t - 0.7 ) * 18, cy - ( t - 0.7 ) * 5, effect_color( p.element, 0.9 ), dir * 60, 10, 0.1 ) end
	end
	if age % 2 == 0 then GameCreateParticle( p.material or "water", nx - dir * 6, ny - 4, 1, -dir * 20, -20, false, false, true ) end
	for _, id in ipairs( creatures_in( nx, ny - h / 2, h * 0.7 + 4, p.owner ) ) do
		push_creature( id, dir * 150, -80, true )
		if age % 10 == 0 then
			seal_damage( id, 0.2, "DAMAGE_PROJECTILE", p.owner, nx, ny )
			give_effect( id, MISC .. "effect_apply_wet.xml" )
		end
	end
end

-- Capture Pennant: a white ribbon flies to the enemy, winds round it and holds it
MODES.ribbon_flight = function( e, p, age, x, y )
	local px, py = pos( e, p, x, y )
	local target = math.floor( ( p.target or 0 ) + 0.5 )
	local tx, ty = p.tx, p.ty
	if target ~= 0 and EntityGetIsAlive( target ) then
		tx, ty = EntityGetTransform( target )
		ty = ty - 5
	end
	local dx, dy = tx - px, ty - py
	local d = math.sqrt( dx * dx + dy * dy )
	local trail = TRAILS[e] or {}
	TRAILS[e] = trail
	if d < 6 or age >= p.frames then
		if target ~= 0 and EntityGetIsAlive( target ) then
			hold_creature( target, p.hold, "ribbon", "light", p.owner )
		else
			fx_burst( px, py, fx_color( "light", 0.9 ), 16, 40, 0.5 )
		end
		finish( e )
		return
	end
	local step = math.min( d, 5 )
	px, py = px + dx / d * step, py + dy / d * step + math.sin( age * 0.4 ) * 0.8
	move_to( e, px, py )
	table.insert( trail, 1, { px, py } )
	while #trail > 22 do table.remove( trail ) end
	local c = fx_color( "light", 0.95 )
	for i, q in ipairs( trail ) do
		local wave = math.sin( i * 0.6 - age * 0.5 ) * 1.5
		fx_dot( q[1], q[2] + wave, c, 0, 0, 0.05 )
	end
end

---- doubles and puppets that draw enemies ----

-- a silhouette of smoke 'w' x 'h' at x, y
local function smoke_figure( x, y, w, h, alpha, element )
	for i = 1, 8 do
		local fx, fy = x + Random( -100, 100 ) / 100 * w, y - Random( 0, 100 ) / 100 * h
		fx_dot( fx, fy, effect_color( element or "smoke", Random( 0, 30 ) / 100, alpha ), Random( -4, 4 ), -Random( 2, 8 ), 0.35 )
	end
end

-- Smokesculpting: a copy of an enemy made of smoke beside it
MODES.copy = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	if age == 0 then decoy( e, 2, 4, 10 ) end
	local of = math.floor( ( p.of or 0 ) + 0.5 )
	local w, h = 4, 12
	if of ~= 0 and EntityGetIsAlive( of ) then
		local box = EntityGetFirstComponent( of, "HitboxComponent" )
		if box then
			w = math.max( 2, ( ComponentGetValue2( box, "aabb_max_x" ) - ComponentGetValue2( box, "aabb_min_x" ) ) / 2 )
			h = math.max( 4, ComponentGetValue2( box, "aabb_max_y" ) - ComponentGetValue2( box, "aabb_min_y" ) )
		end
	end
	smoke_figure( x, y + 2, w, h, 0.75 )
end

-- Smokesculpture: a double of the caster made of smoke walks beside them, a step behind
MODES.clone = function( e, p, age, x, y )
	local owner = effect_owner( p )
	if not owner or done( e, p, age ) then
		if not owner then finish( e ) end
		return
	end
	if age == 0 then decoy( e, 4, 3, 12 ) end
	local trail = TRAILS[e] or {}
	TRAILS[e] = trail
	local ox, oy = EntityGetTransform( owner )
	table.insert( trail, { ox, oy } )
	while #trail > 20 do table.remove( trail, 1 ) end
	local q = trail[1]
	local cx, cy = q[1] + ( p.side or 1 ) * 18, q[2]
	move_to( e, cx, cy )
	smoke_figure( cx, cy + 3, 3, 13, 0.7 )
	for k = 0, 5 do -- the head
		local a = k / 6 * 2 * math.pi
		fx_dot( cx + math.cos( a ) * 2.5, cy - 11 + math.sin( a ) * 2.5, fx_color( "smoke", 0.4, 0.8 ), 0, 0, 0.05 )
	end
end

-- Sprite Winged: a little winged fairy of smoke flutters round the caster and distracts enemies
MODES.fairy = function( e, p, age, x, y )
	local owner = effect_owner( p )
	if not owner or done( e, p, age ) then
		if not owner then finish( e ) end
		return
	end
	if age == 0 then decoy( e, 2, 3, 4 ) end
	local ox, oy = EntityGetTransform( owner )
	local a = age * 0.06
	local tx, ty = ox + math.cos( a ) * 24, oy - 18 + math.sin( a * 2.3 ) * 8
	local px, py = pos( e, p, x, y )
	px, py = px + ( tx - px ) * 0.15, py + ( ty - py ) * 0.15
	move_to( e, px, py )
	local flap = math.abs( math.sin( age * 0.6 ) )
	local c = fx_color( "smoke", 0.5, 0.85 )
	fx_dot( px, py, fx_color( "flicker", 0.8 ), 0, 0, 0.05 )
	for side = -1, 1, 2 do
		for k = 1, 3 do
			fx_dot( px + side * k * 1.3, py - k * flap * 1.2, c, 0, 0, 0.05 )
			fx_dot( px + side * k * 1.1, py + k * 0.5, c, 0, 0, 0.05 )
		end
	end
	if age % 5 == 0 then fx_dot( px, py, fx_color( "smoke", 0.8, 0.6 ), 0, 8, 0.8 ) end
end

-- Sasaran's Cloak: a cloak of shadow flies after the cursor; the book's next seals come out of it
MODES.cloak = function( e, p, age, x, y )
	local owner = effect_owner( p )
	if not owner or age >= p.frames then
		if tonumber( GlobalsGetValue( "witch_notebook.remote", "0" ) ) == e then GlobalsSetValue( "witch_notebook.remote", "0" ) end
		if owner then fx_burst( x, y, fx_color( "vacuum", 0.3 ), 20, 40, 0.5 ) end
		finish( e )
		return
	end
	if age == 0 then GlobalsSetValue( "witch_notebook.remote", tostring( e ) ) end
	local controls = EntityGetFirstComponent( owner, "ControlsComponent" )
	local mx, my = x, y
	if controls then mx, my = ComponentGetValue2( controls, "mMousePosition" ) end
	local px, py = pos( e, p, x, y )
	px, py = px + ( mx - px ) * 0.06, py + ( my - 20 - py ) * 0.06
	move_to( e, px, py )
	local dark = color_abgr_merge( 50, 30, 70, 230 )
	local edge = color_abgr_merge( 140, 90, 200, 230 )
	for k = 0, 8 do
		local t = k / 8
		local w = 2 + 6 * t
		local sway = math.sin( age * 0.15 + t * 3 ) * t * 2
		fx_dot( px - w + sway, py - 8 + t * 16, t > 0.9 and edge or dark, 0, 0, 0.05 )
		fx_dot( px + w + sway, py - 8 + t * 16, t > 0.9 and edge or dark, 0, 0, 0.05 )
	end
	fx_dot( px, py - 10, dark, 0, 0, 0.05 )
	fx_dot( px - 1, py - 7, edge, 0, 0, 0.05 )
	fx_dot( px + 1, py - 7, edge, 0, 0, 0.05 )
end

-- The Dancing Puppets frame: a puppet darts about in the air where it was cast - enemies chase it, light things fly up
MODES.puppet = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	if age == 0 then decoy( e, 4, 4, 10 ) end
	local t = age * 0.05
	local big = p.big or 1
	local cx, cy = target_of( p, p.tx, p.ty )
	if p.mimic == 1 then
		-- it drifts after the cursor rather than jumping to it
		cx = ( p.cx or p.tx ) + ( cx - ( p.cx or p.tx ) ) * 0.05
		cy = ( p.cy or p.ty ) + ( cy - ( p.cy or p.ty ) ) * 0.05
		effect_set( e, "cx", cx )
		effect_set( e, "cy", cy )
	end
	local px = cx + ( math.sin( t * 1.7 ) * 26 + math.sin( t * 4.1 ) * 8 ) * big
	local py = cy - 10 + ( math.sin( t * 2.3 ) * 14 + math.cos( t * 5.2 ) * 4 ) * big
	move_to( e, px, py )
	local c = effect_color( p.element, 0.35, 0.9 )
	-- a cloak with sleeves flapping and a round head
	local flap = math.sin( age * 0.4 )
	for k = 0, 6 do
		local s = k / 6
		fx_dot( px - ( 2 + 4 * s ) * big, py + ( s * 10 ) * big, c, 0, 0, 0.05 )
		fx_dot( px + ( 2 + 4 * s ) * big, py + ( s * 10 ) * big, c, 0, 0, 0.05 )
	end
	for side = -1, 1, 2 do
		for k = 1, 4 do fx_dot( px + side * k * 2 * big, py + ( 2 - flap * k ) * big, c, 0, 0, 0.05 ) end
	end
	for k = 0, 5 do
		local a = k / 6 * 2 * math.pi
		fx_dot( px + math.cos( a ) * 2.5 * big, py - 4 * big + math.sin( a ) * 2.5 * big, effect_color( p.element, 0.8 ), 0, 0, 0.05 )
	end
	if p.element == "water" and age % 3 == 0 then GameCreateParticle( "water", px, py + 8, 1, 0, 0, false, false, true ) end
	PhysicsApplyForceOnArea( function( body, mass, bx, by )
		if ( bx - px ) ^ 2 + ( by - py ) ^ 2 > 1600 then return bx, by, 0, 0, 0 end
		return bx, by, 0, -mass * 14, 0
	end, e, px - 40, py - 40, px + 40, py + 40 )
end

-- Pouch of Calling: a pouch runs about where it was cast and calls with a voice - enemies come running to it
MODES.lure = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	if age == 0 then decoy( e, 3, 3, 4 ) end
	local px, py = pos( e, p, x, y )
	local dir = math.sin( age * 0.02 ) >= 0 and 1 or -1
	local nx = px + dir * 0.9
	local gx, gy = ground_below( nx, py - CLIMB, 60 + CLIMB )
	local ny = gy and gy - 3 or py
	if RaytraceSurfaces( px, py - CLIMB, nx + dir * 4, py - CLIMB ) then nx = px end
	move_to( e, nx, ny )
	local hop = math.abs( math.sin( age * 0.3 ) ) * 2
	local c = color_abgr_merge( 170, 120, 70, 255 )
	for k = 0, 7 do
		local a = k / 8 * 2 * math.pi
		fx_dot( nx + math.cos( a ) * 3, ny - 3 - hop + math.sin( a ) * 3, c, 0, 0, 0.05 )
	end
	fx_dot( nx, ny - 7 - hop, color_abgr_merge( 220, 190, 90, 255 ), 0, 0, 0.05 ) -- its tie
	-- the call: rings going out
	if age % 40 == 0 then
		fx_ring( nx, ny - 4, 5, fx_color( "light", 0.8, 0.8 ), 16, 60, 0.4 )
		effect_sound( "magic", nx, ny )
	end
end

-- Golem (forbidden): the ground's own stones stand up as a hulk of brickwork and fight for the caster. It rises out
-- of the ground, walks after the caster - falling off ledges, climbing steps - and goes for whatever hostile comes
-- near: it rears a fist up and brings it down, striking all that stand before it. Enemies turn on it; broken, or its
-- time up, it falls apart into sand. Left far behind, it sinks into the ground and rises again beside the caster.
-- Its pictures are gfx/golem_<frame>.png (tools/make_gfx.py), 44 x 38, drawn facing right with the middle of its feet
-- at 18, 38: the effect's own sprite, mirrored by the entity's scale. p.up: the frame it began to rise, p.blow: the
-- frame its blow began (0: none), p.vy: how fast it falls.
local GOLEM = { rise = 48, sight = 220, reach = 22, swing = 40, hit = 14, speed = 0.8, near = 30, far = 320, hp = 20 }
local GOLEM_GFX = "mods/witch_notebook/files/gfx/golem_"

local function golem_show( e, frame, dir, x, y )
	local path = GOLEM_GFX .. frame .. ".png"
	EntitySetTransform( e, x, y, 0, dir, 1 )
	local sprite = ( EntityGetComponentIncludingDisabled( e, "SpriteComponent", "witch_golem" ) or {} )[1]
	if not sprite then
		EntityAddComponent2( e, "SpriteComponent", { _tags = "witch_golem", image_file = path, offset_x = 18, offset_y = 38,
			z_index = 0.8, update_transform = true, update_transform_rotation = false } )
	elseif ComponentGetValue2( sprite, "image_file" ) ~= path then
		ComponentSetValue2( sprite, "image_file", path )
		EntityRefreshSprite( e, sprite )
	end
end

-- bricks and dust flying from x, y
local function golem_dust( x, y, count, speed )
	for i = 1, count do
		fx_dot( x + Random( -10, 10 ), y - Random( 0, 4 ), fx_color( "stone", Random( 10, 40 ) / 100 ), Random( -speed, speed ), -Random( 10, speed ), 0.5, 200 )
	end
end

-- the fist comes down in front of it: all the hostile there are struck and thrown
local function golem_slam( p, px, py, dir )
	local hx, hy = px + dir * 18, py - 8
	for _, id in ipairs( creatures_in( hx, hy, 18, p.owner ) ) do
		local tx, ty = EntityGetTransform( id )
		seal_damage( id, 1.6 * ( p.power or 1 ), "DAMAGE_MELEE", p.owner, tx, ty )
		push_creature( id, dir * 220, -140 )
		fx_burst( tx, ty - 6, fx_color( "stone", 0.4 ), 10, 60, 0.4 )
	end
	golem_dust( hx, py, 12, 60 )
	GameScreenshake( 12, hx, py )
	effect_sound( "earth", hx, py )
end

MODES.golem = function( e, p, age, x, y )
	local px, py = pos( e, p, x, y )
	local dir = p.dir or 1
	if age == 0 then
		decoy( e, GOLEM.hp, 8, 30 )
		-- broken, it stays for this script to take apart rather than vanishing
		ComponentSetValue2( EntityGetFirstComponent( e, "DamageModelComponent" ), "wait_for_kill_flag_on_death", true )
		effect_sound( "statue", px, py )
		GameScreenshake( 8, px, py )
	end
	local model = EntityGetFirstComponent( e, "DamageModelComponent" )
	if age >= p.frames or ( model and ComponentGetValue2( model, "hp" ) <= 0 ) then
		fx_material( "sand", px, py - 14, 80, 9 )
		golem_dust( px, py - 14, 20, 70 )
		effect_sound( "earth", px, py )
		finish( e )
		return
	end
	local owner = effect_owner( p )
	local blow = ( p.blow or 0 ) > 0 and age - p.blow or nil
	if blow and blow >= GOLEM.swing then
		blow = nil
		effect_set( e, "blow", 0 )
	end
	-- left far behind: into the ground, and up again beside the caster
	if owner and not blow and age - ( p.up or 0 ) >= GOLEM.rise then
		local ox, oy = EntityGetTransform( owner )
		if ( ox - px ) ^ 2 + ( oy - py ) ^ 2 > GOLEM.far ^ 2 then
			local gx, gy = ground_below( ox - dir * 16, oy - 10, 80 )
			if gy then
				golem_dust( px, py - 14, 20, 70 )
				px, py, p.up = gx, gy, age
				effect_set( e, "up", age )
				effect_set( e, "vy", 0 )
				effect_sound( "statue", px, py )
			end
		end
	end
	-- rising: a heap of bricks, then the golem out of it
	local up = age - ( p.up or 0 )
	if up < GOLEM.rise then
		effect_set( e, "px", px )
		effect_set( e, "py", py )
		golem_show( e, up < 12 and "rise_1" or up < 26 and "rise_2" or up < 40 and "rise_3" or "stand", dir, px, py )
		if up % 3 == 0 then golem_dust( px, py, 2, 40 ) end
		return
	end
	local frame, nx = "stand", px
	if blow then
		frame = blow < GOLEM.hit and "windup" or blow < GOLEM.hit + 12 and "slam" or "stand"
		if blow == GOLEM.hit then golem_slam( p, px, py, dir ) end
	else
		local target = nearest_creature( px, py - 12, GOLEM.sight, p.owner )
		local goal
		if target then
			local tx, ty = EntityGetTransform( target )
			dir = tx >= px and 1 or -1
			if math.abs( tx - px ) > GOLEM.reach then
				goal = tx
			elseif math.abs( ty - ( py - 12 ) ) <= 30 then
				effect_set( e, "blow", age )
				frame = "windup"
			end
		elseif owner then
			local ox = EntityGetTransform( owner )
			if math.abs( ox - px ) > GOLEM.near then
				dir = ox >= px and 1 or -1
				goal = ox
			end
		end
		-- a wall higher than it can step over stops it
		if goal and not RaytraceSurfaces( px, py - CLIMB - 4, px + dir * 9, py - CLIMB - 4 ) then
			nx = px + dir * GOLEM.speed
			frame = math.floor( age / 9 ) % 2 == 0 and "walk_1" or "walk_2"
		end
	end
	-- its weight: it stands on the ground under it, steps up what it can climb, falls where there is none
	local vy, ny = p.vy or 0, py
	local gx, gy = ground_below( nx, py - CLIMB, CLIMB + 2 )
	if gy and gy <= py - CLIMB + 0.5 then
		nx, gy = px, py -- rock where it would step
	end
	if gy then
		if vy > 3 then
			golem_dust( nx, gy, 10, 50 )
			GameScreenshake( 8, nx, gy )
		end
		ny, vy = gy, 0
	else
		vy = math.min( vy + 0.35, 7 )
		local hx, hy = ground_below( nx, py, vy + 1 )
		ny = hy or py + vy
		frame = "stand"
	end
	effect_set( e, "px", nx )
	effect_set( e, "py", ny )
	effect_set( e, "vy", vy )
	effect_set( e, "dir", dir )
	golem_show( e, frame, dir, nx, ny )
end

EFFECT_MODES.mover = MODES
