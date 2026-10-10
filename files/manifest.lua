-- The seals that manifest in a way of their own (cast.lua): the wiki's named seals, the special sigils and frames,
-- the decorative sigils' sculptures, and the wave and ring forms. MANIFESTS[key] = function( ctx ) - ctx: shooter,
-- spell, x, y (the caster), aim_x, aim_y, tx, ty (the cursor), power (0.5 + precision, twice with the Amplification
-- Scroll). Each makes one or more effects (effects/*.lua) and returns what it made (for tests).

dofile_once( "mods/witch_notebook/files/effects/lib.lua" )

MANIFESTS = {}
local M = MANIFESTS

WINDOW_VAR = "witch_notebook.window" -- the Windowway's first window, waiting for its pair
DOOR_VAR = "witch_notebook.door"     -- the place the Doorknob remembers
BUSY_VAR = "witch_notebook.busy_until" -- the book doesn't cast while the quill of water draws

-- The signs work on every way of manifesting too, not only on projectiles: Expansion makes it bigger, its inverse
-- smaller, Strengthening stronger, Stability and Stillness make it last, Piercing makes more of it (sculptures, lights),
-- Mimicry makes it follow the cursor.
local function mod( ctx, key )
	return ( ctx.spell.behaviors or {} )[key] or 0
end

-- how long: 's' seconds, longer with lifetime, a clean seal and the signs that hold it
local function secs( ctx, s )
	local lifetime = math.max( -0.6, math.min( 2, ctx.spell.lifetime or 0 ) )
	local hold = 1 + 0.4 * math.min( 2, mod( ctx, "still" ) )
	return math.floor( 60 * s * ( 1 + 0.5 * lifetime ) * ( 0.75 + 0.25 * math.min( ctx.power, 2 ) ) * hold )
end

-- how much Expansion (its inverse: less) makes it bigger
local function grown( ctx )
	return ( 1 + 0.35 * math.min( 2, mod( ctx, "grow" ) ) ) / ( 1 + 0.35 * math.min( 2, mod( ctx, "shrink" ) ) )
end

-- how big: 'v', bigger with force, layers and Expansion
local function size( ctx, v )
	return v * grown( ctx ) * math.max( 0.7, math.min( 2, 1 + 0.25 * ( ctx.spell.force or 0 ) + 0.2 * ( ctx.spell.layers or 0 ) ) )
end
-- the same, for spell_notes.lua to tell (ctx: { spell, power })
MANIFEST_SCALE = { secs = secs, grown = grown, size = size }

-- the cursor, but not farther than 'max' from the caster
local function reach( ctx, max )
	local dx, dy = ctx.tx - ctx.x, ctx.ty - ctx.y
	local d = math.sqrt( dx * dx + dy * dy )
	if d > max then dx, dy = dx / d * max, dy / d * max end
	return ctx.x + dx, ctx.y + dy
end

-- the spell's element, or 'default' when it has none of its own (a seal with no element sigil)
local function el( ctx, default )
	local e = ctx.spell.element
	if not e or e == "" or e == "shockwave" or not DICTIONARY_ELEMENTS[e] then return default end
	return e
end

local function spawn( kind, mode, x, y, params )
	return effect_spawn( kind, mode, x, y, params )
end

local function mine( ctx, t )
	t.owner = ctx.shooter
	t.power = ctx.power * ( 1 + 0.3 * math.min( 2, mod( ctx, "strong" ) ) )
	if mod( ctx, "mimic" ) > 0 then t.mimic = 1 end
	-- drawn with golden ink: the magic shines (effect_spawn gives it a light)
	if ( ctx.glow or 0 ) > 0 then t.glow = ctx.glow end
	return t
end

-- a creature near the cursor for the seals that take hold of one
local function victim( ctx, near )
	local x, y = reach( ctx, 220 )
	return nearest_creature( x, y, near or 40, ctx.shooter ), x, y
end

---- fire, light, guidance ----

M.spiraling_flame = function( ctx )
	local dx, dy = ctx.tx - ctx.x, ctx.ty - ctx.y
	local distance = math.sqrt( dx * dx + dy * dy )
	if distance < 0.001 then
		dx, dy = ctx.aim_x, ctx.aim_y
		local d = math.sqrt( dx * dx + dy * dy )
		if d < 0.001 then dx, dy, d = 1, 0, 1 end
		dx, dy, distance = dx / d, dy / d, 240
	else
		dx, dy = dx / distance, dy / distance
	end
	local offset = math.min( 8, distance )
	local x, y = ctx.x + dx * offset, ctx.y + dy * offset
	local speed = 230 + 45 * math.min( 2, ctx.spell.range or 0 )
	local length = size( ctx, 58 )
	local reach = math.min( distance - offset, speed * secs( ctx, 1.6 ) / 60 )
	local e = spawn( "flame", "spiral", x, y, mine( ctx, { dx = dx, dy = dy, ox = x, oy = y,
		speed = speed, length = length, r = size( ctx, 8 ), reach = reach,
		spin = mod( ctx, "whirl" ) < 0 and -1 or 1, frames = math.ceil( ( reach + length ) / speed * 60 ) + 16,
		hidden = ctx.hidden == true } ) )
	EntityAddComponent2( e, "LightComponent", { radius = ctx.hidden and 12 or 65, r = 255, g = 135, b = 40, fade_out_time = 0.15 } )
	return { e }
end

local function fire_effect( ctx, mode, x, y, params )
	params.hidden = ctx.hidden == true
	local e = spawn( "flame", mode, x, y, mine( ctx, params ) )
	EntityAddComponent2( e, "LightComponent", { radius = ctx.hidden and 12 or 80, r = 255, g = 145, b = 45, fade_out_time = 0.2 } )
	return e
end

local function fire_aim( ctx )
	local dx, dy = ctx.tx - ctx.x, ctx.ty - ctx.y
	local d = math.sqrt( dx * dx + dy * dy )
	if d < 0.001 then
		dx, dy = ctx.aim_x, ctx.aim_y
		local n = math.sqrt( dx * dx + dy * dy )
		if n < 0.001 then dx, dy, n = 1, 0, 1 end
		return dx / n, dy / n, 240
	end
	return dx / d, dy / d, d
end

M.pyreball = function( ctx )
	local x, y = reach( ctx, 60 )
	-- Keep the floating flame on the caster's side of a wall.
	local hit, hx, hy = RaytraceSurfaces( ctx.x, ctx.y, x, y )
	if hit then
		local dx, dy = fire_aim( ctx )
		x, y = hx - dx * 2, hy - dy * 2
	end
	-- Recasting at the same spot renews one source instead of stacking fire supplies.
	for _, e in ipairs( EntityGetInRadiusWithTag( x, y, 3, "witch_pyreball" ) or {} ) do
		if effect_params( e ).owner == ctx.shooter then
			effect_set( e, "born", 0 )
			effect_set( e, "frames", secs( ctx, 20 ) )
			effect_set( e, "r", size( ctx, 10 ) )
			effect_set( e, "power", ctx.power * ( 1 + 0.3 * math.min( 2, mod( ctx, "strong" ) ) ) )
			effect_set( e, "hidden", ctx.hidden and 1 or 0 )
			effect_set( e, "reveal", 1 )
			return { e }
		end
	end
	local e = fire_effect( ctx, "ball", x, y, { frames = secs( ctx, 20 ), r = size( ctx, 10 ), ox = x, oy = y, reveal = 1 } )
	EntityAddTag( e, "witch_pyreball" )
	return { e }
end

M.flame_shot = function( ctx )
	dofile_once( "mods/witch_notebook/files/effects/fluid.lua" )
	local dx, dy = fire_aim( ctx )
	local offset = 8
	local x, y = ctx.x + dx * offset, ctx.y + dy * offset
	local hit, hx, hy = RaytraceSurfacesAndLiquiform( ctx.x, ctx.y, x, y )
	if hit then x, y = hx - dx, hy - dy end
	local speed = 360 + 35 * math.min( 2, ctx.spell.range or 0 )
	local length = size( ctx, 88 )
	-- Mouse distance selects neither the muzzle nor the range of the packet.
	local duration = secs( ctx, 1.8 ) / 60
	local drag = FlameFluid.tuning.packet_drag
	local reach = speed * ( 1 - math.exp( -drag * duration ) ) / drag
	return { fire_effect( ctx, "shot", x, y, { dx = dx, dy = dy, ox = x, oy = y,
		speed = speed, drag = drag, length = length, r = size( ctx, 6 ), reach = reach,
		frames = math.ceil( duration * 60 + length / speed * 60 ) + 16, reveal = 1 } ) }
end

M.flame_burst = function( ctx )
	local dx, dy, distance = fire_aim( ctx )
	local offset = math.min( 8, distance )
	local x, y = ctx.x + dx * offset, ctx.y + dy * offset
	return { fire_effect( ctx, "burst", x, y, { dx = dx, dy = dy, ox = x, oy = y,
		speed = 280, length = size( ctx, 30 ), r = size( ctx, 5 ), reach = math.min( distance - offset, 260 ),
		blast_r = size( ctx, 80 ), frames = 100, force = ctx.spell.force or 0 } ) }
end

M.ring_of_fire = function( ctx )
	return { fire_effect( ctx, "ring", ctx.x, ctx.y, { r = size( ctx, 55 ), grow = 28, frames = 60,
		damage = 0.35 + 0.25 * ( ctx.spell.force or 0 ), push = 90 } ) }
end

M.warmth = function( ctx ) return { spawn( "aura", "warmth", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 45 ) } ) ) } end
M.phantasm = function( ctx )
	for _, e in ipairs( EntityGetWithTag( "witch_phantasm" ) or {} ) do
		if effect_params( e ).owner == ctx.shooter then
			effect_set( e, "born", 0 )
			effect_set( e, "frames", secs( ctx, 40 ) )
			effect_set( e, "power", ctx.power * ( 1 + 0.3 * math.min( 2, mod( ctx, "strong" ) ) ) )
			return { e }
		end
	end
	local e = spawn( "aura", "phantasm", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 40 ) } ) )
	EntityAddTag( e, "witch_phantasm" )
	return { e }
end
M.snowfend = function( ctx )
	local x, y = reach( ctx, 160 )
	return { spawn( "zone", "snowfend", x, y, mine( ctx, { frames = secs( ctx, 30 ), r = size( ctx, 40 ) } ) ) }
end
-- Renew nearby sources instead of stacking persistent particle emitters.
local function renew_light( e, frames )
	local p = effect_params( e )
	local age = p.born and p.born > 0 and effect_age( p ) or 0
	effect_set( e, "frames", age + frames )
	effect_set( e, "reveal", 1 )
end
local function light_source( ctx, mode, x, y, params )
	params.reveal = 1
	for _, e in ipairs( EntityGetInRadiusWithTag( x, y, 8, "witch_light_source" ) or {} ) do
		local p = effect_params( e )
		if p.owner == ctx.shooter and p.mode == mode and ( p.suspended or 0 ) == ( params.suspended or 0 )
			and ( p.ancient or 0 ) == ( params.ancient or 0 ) and ( p.lantern or 0 ) == ( params.lantern or 0 )
			and p.element == params.element then
			renew_light( e, params.frames )
			if params.dy then
				effect_set( e, "dx", params.dx )
				effect_set( e, "dy", params.dy )
			end
			return { e }
		end
	end
	local e = spawn( "light", mode, x, y, mine( ctx, params ) )
	EntityAddTag( e, "witch_light_source" )
	return { e }
end
M.floatglow = function( ctx )
	-- The lantern flies after its caster: another cast renews it, wherever it
	-- is, instead of lighting a second one.
	for _, e in ipairs( EntityGetWithTag( "witch_light_source" ) or {} ) do
		local p = effect_params( e )
		if p.owner == ctx.shooter and p.mode == "lamp" and p.lantern == 1 then
			renew_light( e, secs( ctx, 180 ) )
			return { e }
		end
	end
	return light_source( ctx, "lamp", ctx.x, ctx.y - 6, { frames = secs( ctx, 180 ), element = el( ctx, "light" ), lantern = 1 } )
end
M.light_beam = function( ctx )
	local dx, dy = fire_aim( ctx )
	return light_source( ctx, "column", ctx.x, ctx.y, { frames = secs( ctx, 4 ), height = size( ctx, 180 ), dx = dx, dy = dy } )
end
M.lamp = function( ctx )
	local x, y = reach( ctx, 100 )
	return light_source( ctx, "lamp", x, y, { frames = secs( ctx, 180 ), element = el( ctx, "light" ) } )
end
M.glowpath = function( ctx )
	return light_source( ctx, "glowpath", ctx.x, ctx.y, { frames = secs( ctx, 120 ), dx = ctx.aim_x } )
end
M.beacon_pillar = function( ctx )
	local dx, dy = fire_aim( ctx )
	return light_source( ctx, "column", ctx.x, ctx.y, { frames = secs( ctx, 12 ), height = 320, ancient = 1, dx = dx, dy = dy } )
end
M.light_leech = function( ctx )
	local x, y = reach( ctx, 140 )
	return light_source( ctx, "leech", x, y, { frames = secs( ctx, 20 ), big = size( ctx, 1 ) } )
end
M.light_bird = function( ctx )
	return { spawn( "mover", "sculpture", ctx.x, ctx.y - 8, mine( ctx,
		{ frames = secs( ctx, 15 ), shape = "bird", element = "light", big = size( ctx, 1 ), reveal = 1 } ) ) }
end
-- A fragment may already carry a witch_fragment_group. For ordinary Noita items
-- the caster explicitly marks a linked set with successive casts at the cursor.
-- Physics props use prop_physics (including mortal explosive boxes/barrels),
-- while carts can have no tags at all, or no surviving entity.
M.tracer = function( ctx )
	-- The actual cursor, not clamped to the reach: clamping would pick a different item.
	if ( ctx.tx - ctx.x ) ^ 2 + ( ctx.ty - ctx.y ) ^ 2 > 450 ^ 2 then
		GamePrint( "Light Tracer: target is out of reach" ); return {}
	end
	local x, y = ctx.tx, ctx.ty
	local target, distance
	local carried_bodies = {}
	for _, id in ipairs( EntityGetInRadius( x, y, 18 ) or {} ) do
		if id ~= ctx.shooter and EntityGetRootEntity( id ) == id and ( EntityHasTag( id, "wand" ) or EntityHasTag( id, "potion" )
			or EntityHasTag( id, "item_pickup" ) or EntityHasTag( id, "prop_physics" )
			or EntityHasTag( id, "item_physics" ) or EntityHasTag( id, "enemy" )
			or EntityHasTag( id, "witch_light_fragment" )
			or EntityGetFirstComponentIncludingDisabled( id, "PhysicsBodyComponent" )
			or EntityGetFirstComponentIncludingDisabled( id, "PhysicsBody2Component" ) ) then
			local ix, iy = EntityGetTransform( id )
			local d = ( ix - x ) ^ 2 + ( iy - y ) ^ 2
			if not distance or d < distance then target, distance = id, d end
		elseif PhysicsBodyIDGetFromEntity and ( id == ctx.shooter or EntityGetRootEntity( id ) ~= id ) then
			for _, body in ipairs( PhysicsBodyIDGetFromEntity( id ) or {} ) do carried_bodies[body] = true end
		end
	end
	if not target and PhysicsBodyIDQueryBodies and PhysicsBodyIDGetWorldCenter and PhysicsPosToGamePos then
		local selected_body, bx, by
		for _, body in ipairs( PhysicsBodyIDQueryBodies( x - 9, y - 9, x + 9, y + 9 ) or {} ) do
			local px, py = PhysicsBodyIDGetWorldCenter( body )
			if px and not carried_bodies[body] then
				local gx, gy = PhysicsPosToGamePos( px, py )
				local d = ( gx - x ) ^ 2 + ( gy - y ) ^ 2
				if not distance or d < distance then selected_body, bx, by, distance = body, gx, gy, d end
			end
		end
		if selected_body then
			for _, id in ipairs( EntityGetWithTag( "witch_light_body_marker" ) or {} ) do
				local marker = effect_params( id )
				if tonumber( marker.witch_tracer_body ) == selected_body and marker.owner == ctx.shooter then target = id; break end
			end
			if not target then
				target = EntityCreateNew( "witch_light_body_marker" )
				EntityAddTag( target, "witch_light_body_marker" )
				EntitySetTransform( target, bx, by )
				-- Preserve the full body ID; VariableStorage's float can round it.
				effect_set( target, "witch_tracer_body", tostring( selected_body ) )
				effect_set( target, "owner", ctx.shooter )
			end
		end
	end
	if not target then GamePrint( "Aim Light Tracer at an item, a loose thing or an enemy to mark it" ); return {} end
	local p = effect_params( target )
	local group = effect_text( p.witch_fragment_group )
	if group == "" then
		group = "caster:" .. tostring( ctx.shooter )
		effect_set( target, "witch_fragment_group", group )
	end
	EntityAddTag( target, "witch_light_fragment" )
	local ox, oy = EntityGetTransform( ctx.shooter )
	for _, e in ipairs( EntityGetWithTag( "witch_light_tracer" ) or {} ) do
		local old = effect_params( e )
		if old.group == group and old.owner == ctx.shooter then
			effect_set( e, "focus", target )
			effect_set( e, "book_dx", ctx.x - ox )
			effect_set( e, "book_dy", ctx.y - oy )
			if not EntityGetIsAlive( math.floor( old.source or 0 ) ) then effect_set( e, "source", target ) end
			renew_light( e, secs( ctx, 25 ) )
			if EntityHasTag( target, "witch_light_body_marker" ) and EntityGetParent( target ) == 0 then EntityAddChild( e, target ) end
			return { e }
		end
	end
	local e = spawn( "light", "tracer", x, y, mine( ctx, { frames = secs( ctx, 25 ), source = target, focus = target,
		book_dx = ctx.x - ox, book_dy = ctx.y - oy, group = group, reveal = 1 } ) )
	EntityAddTag( e, "witch_light_tracer" )
	if EntityHasTag( target, "witch_light_body_marker" ) then EntityAddChild( e, target ) end
	return { e }
end
M.tracking = function( ctx ) return { spawn( "light", "tracking", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 40 ) } ) ) } end
M.beacon = function( ctx )
	local x, y = reach( ctx, 250 )
	return { spawn( "light", "beacon", x, y, mine( ctx, { frames = secs( ctx, 60 ), element = el( ctx, "wind" ) } ) ) }
end
M.bloom = function( ctx )
	local x, y = reach( ctx, 150 )
	local element = el( ctx, "light" )
	local seconds = ( { water = 1.8, storm = 1.8, ice = 1.8, shimmer = 1.8, fire = 8, plasma = 8, lava = 8 } )[element] or 60
	local params = { frames = seconds >= 60 and secs( ctx, seconds ) or math.floor( 60 * seconds ), element = element }
	if element == "light" then return light_source( ctx, "bloom", x, y, params ) end
	return { spawn( "light", "bloom", x, y, mine( ctx, params ) ) }
end
M.carousel = function( ctx )
	for _, e in ipairs( EntityGetWithTag( "witch_light_carousel" ) or {} ) do
		if effect_params( e ).owner == ctx.shooter then renew_light( e, secs( ctx, 25 ) ); return { e } end
	end
	local e = spawn( "orbit", "carousel", ctx.x, ctx.y, mine( ctx,
		{ frames = secs( ctx, 25 ), count = 6 + 2 * math.min( 4, math.floor( mod( ctx, "pierce" ) ) ), reveal = 1 } ) )
	EntityAddTag( e, "witch_light_carousel" )
	return { e }
end
-- the resonance a seal of the witch's own holds (resonances.lua), if it is this one
local function resonates( ctx, key ) return ctx.spell.resonance == key and not ctx.spell.named end

-- the ring of lights; Halo: they turn enemy shots back; Blade Dance: they are blades; Guardian Lights: they fly at
-- enemies that come near
M.orbit_ring = function( ctx, x, y )
	return { spawn( "orbit", "ring", x or ctx.x, y or ctx.y, mine( ctx, { frames = secs( ctx, 10 ), element = el( ctx, "light" ),
		count = 10 + 2 * math.min( 4, math.floor( mod( ctx, "pierce" ) ) ), radius = 24 * grown( ctx ),
		reflect = resonates( ctx, "halo" ) and 1 or nil, blades = resonates( ctx, "blades" ) and 1 or nil,
		guard = resonates( ctx, "guardian" ) and 1 or nil } ) ) }
end
M.amplify = function( ctx )
	GlobalsSetValue( AMPLIFY_VAR or "witch_notebook.amplify", "3" )
	GamePrint( "The next three seals will be stronger" )
	return { spawn( "aura", "amplify", ctx.x, ctx.y, mine( ctx, { frames = 60 } ) ) }
end

-- The Sign of Dispersion: a wave of the element out from the seal (with pulling signs it rushes in, with pushing ones
-- and gusts it throws harder). Binding and Entwining hold whom it strikes, Cooling freezes them, Reflection turns
-- projectiles back; cast.lua gives it what it does to the ground (wave_converts).
-- The wave's resonances: Collapse rushes in and bursts out again wider, Quake shakes the ground round it, Tide sends
-- rolling waves of its water out either way (the gust that drives them throws no harder itself), Chain Storm leaps as
-- lightning to the enemies round the caster, Rampart sets a ring of blocks of its element where it stops.
local TIDE_MATTER = { ice = "water", frost = "water", steam = "water", steamblast = "water" }
M.nova = function( ctx, x, y )
	local b = ctx.spell.behaviors or {}
	local element = el( ctx, "light" )
	local tide = resonates( ctx, "tide" )
	local throw = ( b.push or 0 ) + ( tide and 0 or ( b.gust or 0 ) )
	local r = size( ctx, 55 )
	x, y = x or ctx.x, y or ctx.y
	local made = { spawn( "nova", "nova", x, y, mine( ctx, { element = element, r = r,
		force = ctx.spell.force or 0, inward = ( b.pull or 0 ) > 0 and 1 or 0, grow = 22,
		push = throw > 0 and ( 80 + ( ( DICTIONARY_LOOKS[element] or {} ).knockback or 0 ) ) * ( 1 + 0.6 * math.min( 2, throw ) ) or nil,
		hold = b.hold and math.floor( SIGN_AMOUNTS.hold( b.hold ).frames ) or nil,
		bind = b.bind and math.floor( SIGN_AMOUNTS.bind( b.bind ).frames ) or nil,
		chill = b.cool and 1 or nil, reflect = b.reflect and 1 or nil,
		rebound = resonates( ctx, "collapse" ) and RESONANCE_AMOUNTS.collapse( b.grow or 1 ).wider or nil } ) ) }
	if resonates( ctx, "quake" ) then
		made[#made + 1] = spawn( "resonance", "quake", x, y, mine( ctx, { r = r * 1.5,
			frames = RESONANCE_AMOUNTS.quake( b.crush or 1 ).frames } ) )
	elseif resonates( ctx, "chain_storm" ) then
		local a = RESONANCE_AMOUNTS.chain_storm( b.link or 1 )
		made[#made + 1] = spawn( "resonance", "arcs", x, y, mine( ctx, { element = element, frames = 12 * a.pulses, reach = a.reach } ) )
	elseif resonates( ctx, "rampart" ) then
		local a = RESONANCE_AMOUNTS.rampart( b.grow )
		local piece = SOLID_PIECES[element] or "stone_block"
		for i = 0, a.pieces - 1 do
			local angle = i / a.pieces * 2 * math.pi
			local px, py = x + math.cos( angle ) * a.r, y + math.sin( angle ) * a.r
			-- where the wave can reach: not inside the rock round it
			if not RaytraceSurfaces( x, y, px, py ) then made[#made + 1] = solid_piece( piece, px, py, a.frames ) end
		end
	elseif tide then
		local material = TIDE_MATTER[element] or ( DICTIONARY_LOOKS[element] or {} ).material or "water"
		local _, gy = ground_below( ctx.x, ctx.y - 4, 40 )
		for dir = -1, 1, 2 do
			made[#made + 1] = spawn( "mover", "wave", ctx.x + dir * 6, ( gy or ctx.y + 4 ) - 1, mine( ctx, { frames = 90, dx = dir,
				element = element, material = material, big = size( ctx, 1 ) } ) )
		end
	end
	return made
end
-- An empty ring vents its energy where it was drawn. It pushes nearby creatures,
-- but has no element to burn them or break the terrain.
M.shockwave = function( ctx )
	return { spawn( "nova", "nova", ctx.x, ctx.y, mine( ctx, { element = "shockwave", r = 48,
		grow = 14, damage = 0.08, push = 160, push_objects = 16 } ) ) }
end
M.blade = function( ctx )
	return { spawn( "nova", "slash", ctx.x, ctx.y - 2, mine( ctx, { element = el( ctx, "water" ), r = size( ctx, 28 ), dx = ctx.aim_x, dy = ctx.aim_y } ) ) }
end

---- sculptures ----

local SCULPT_SECONDS = { dragon = 12, horse = 6, bird = 15, fish = 8, owlcat = 60, leech = 20,
	scalewolf = 8, torchstag = 8, liongoat = 10, frillram = 10 }
local GROUND_SHAPES = { horse = true, leech = true, scalewolf = true, torchstag = true, liongoat = true, frillram = true }
local SCHOOL = { torchstag = 3, flying_watersculptures = 4 }
local DRAGON_TAG = "witch_dragon"

local function sculpture( ctx, shape, element, big, seconds )
	local tx, ty = reach( ctx, 200 )
	local out = {}
	local count = ( SCHOOL[ctx.spell.named or ""] or ( shape == "fish" and 3 or 1 ) ) + math.min( 4, math.floor( mod( ctx, "pierce" ) ) )
	if shape == "dragon" then
		-- one dragon in the world, whatever it is made of: the one before it ends as the new one rises
		for _, old in ipairs( EntityGetWithTag( DRAGON_TAG ) or {} ) do effect_set( old, "frames", 0 ) end
		count = 1
	end
	for i = 1, count do
		local sx, sy = ctx.x + ctx.aim_x * 10, ctx.y - 6 + ctx.aim_y * 10
		if GROUND_SHAPES[shape] then
			local gx, gy = ground_below( ctx.x + ctx.aim_x * 12, ctx.y - 8, 40 )
			sy = ( gy or ctx.y + 4 ) - 1
			sx = ctx.x + ( ctx.aim_x >= 0 and 1 or -1 ) * ( 10 + ( i - 1 ) * 14 )
		elseif shape == "owlcat" or shape == "bird" then
			sy = ctx.y - 20
		end
		out[#out + 1] = spawn( "mover", "sculpture", sx + ( i - 1 ) * 3, sy - ( i - 1 ) * 4, mine( ctx, {
			shape = shape, element = element, frames = secs( ctx, seconds or SCULPT_SECONDS[shape] or 10 ) + ( i - 1 ) * 20,
			tx = tx + ( i - 1 ) * 8, ty = ty, dx = ctx.aim_x, vx = ctx.aim_x * 120 + ( i - 1 ) * 10, vy = ctx.aim_y * 120 - ( i - 1 ) * 20,
			big = big or size( ctx, 1 ), speed = 1 + 0.2 * ( ctx.spell.range or 0 ),
			reveal = element == "light" and 1 or 0,
		} ) )
		if shape == "dragon" then EntityAddTag( out[#out], DRAGON_TAG ) end
	end
	effect_sound( "magic", ctx.x, ctx.y )
	return out
end

M.sculpture = function( ctx )
	-- A freely drawn light leech is the same harmless luminous lattice as the named seal.
	if ctx.spell.shape == "leech" and el( ctx, "light" ) == "light" then return M.light_leech( ctx ) end
	return sculpture( ctx, ctx.spell.shape, el( ctx, "light" ) )
end
M.dragon_water = function( ctx ) return sculpture( ctx, "dragon", "water", size( ctx, 1.5 ), 14 ) end
M.dragon_steam = function( ctx ) return sculpture( ctx, "dragon", "steam", size( ctx, 1.3 ), 12 ) end

---- water ----

-- Watershot: water pours out of the book, as from the manga's round flasks, and never runs dry. Cast with a book
-- it pours for as long as fire is held (cast.lua spellbook_use, effects/aura.lua pour); cast any other way, for a
-- couple of seconds the way it was aimed. Expansion and force make the stream thicker.
M.water_pour = function( ctx )
	local dx, dy = fire_aim( ctx )
	return { spawn( "aura", "pour", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 2 ), dx = dx, dy = dy,
		cells = math.max( 2, math.min( 8, math.floor( size( ctx, 4 ) + 0.5 ) ) ) } ) ) }
end
-- Water Rose: a rose of standing water grows from the nearest surface by the cursor, as the game's roots grow
-- (effects/rose.lua), stands for a while and falls as water. Expansion and force make its stem longer.
M.water_rose = function( ctx )
	local x, y = reach( ctx, 160 )
	return { spawn( "rose", "grow", x, y, mine( ctx, { frames = secs( ctx, 25 ), length = size( ctx, 46 ) } ) ) }
end
M.geyser = function( ctx ) return { spawn( "aura", "geyser", ctx.x, ctx.y, mine( ctx, { frames = 50 } ) ) } end
M.wave_ride = function( ctx ) return { spawn( "aura", "wave_ride", ctx.x, ctx.y, mine( ctx, { frames = 45, dx = ctx.aim_x } ) ) } end
M.disc = function( ctx )
	local x, y = reach( ctx, 120 )
	return { spawn( "build", "disc", x, y, mine( ctx, { frames = secs( ctx, 25 ) } ) ) }
end
M.whirlpool = function( ctx )
	local x, y = reach( ctx, 160 )
	return { spawn( "zone", "whirlpool", x, y, mine( ctx, { frames = secs( ctx, 8 ), r = size( ctx, 36 ) } ) ) }
end
-- Water Cage: a sphere of standing water (effects/water_cage.lua) round the creature nearest the cursor, big enough
-- to hold it, or at the cursor when no one is near. It seals whoever is in it or comes up to it for as long as it
-- stands. Expansion and force make it bigger.
M.water_cage = function( ctx )
	local id, x, y = victim( ctx, 45 )
	local r = size( ctx, 21 )
	if id then
		local middle, half = creature_body( id )
		x, y = EntityGetTransform( id )
		y = y + middle
		r = math.max( r, half + 4 )
	end
	return { spawn( "water_cage", "sphere", math.floor( x + 0.5 ), math.floor( y + 0.5 ), mine( ctx, { frames = secs( ctx, 8 ), r = r } ) ) }
end
M.vapor = function( ctx )
	local x, y = reach( ctx, 120 )
	return { spawn( "zone", "vapor", x, y, mine( ctx, { frames = 150 } ) ) }
end
M.dry = function( ctx )
	local x, y = reach( ctx, 150 )
	return { spawn( "zone", "dry", x, y, mine( ctx, { frames = 240, r = size( ctx, 34 ) } ) ) }
end
M.boil = function( ctx )
	local x, y = reach( ctx, 160 )
	return { spawn( "zone", "boil", x, y, mine( ctx, { frames = 180, r = size( ctx, 40 ) } ) ) }
end
-- Purify, Sewer Grate: they clean the foul liquid around the seal and pour out no water themselves. Expansion and
-- force widen the wave.
M.purify = function( ctx ) return { spawn( "zone", "purify", ctx.x, ctx.y, mine( ctx, { frames = 150, r = size( ctx, 60 ) } ) ) } end
M.wash_spring = function( ctx ) return { spawn( "zone", "wash_spring", ctx.x, ctx.y, mine( ctx, { frames = 180, r = size( ctx, 70 ) } ) ) } end
M.wave = function( ctx )
	local element = el( ctx, "water" )
	local look = DICTIONARY_LOOKS[element] or {}
	local gx, gy = ground_below( ctx.x, ctx.y - 4, 40 )
	return { spawn( "mover", "wave", ctx.x, ( gy or ctx.y + 4 ) - 1, mine( ctx, { frames = 90, dx = ctx.aim_x, element = element,
		material = look.material or "water", big = size( ctx, 1 ) } ) ) }
end
M.guidance_fish = function( ctx )
	local x, y = reach( ctx, 200 )
	return { spawn( "zone", "guidance_fish", x, y, mine( ctx, { frames = 360 } ) ) }
end
M.chalice = function( ctx )
	local x, y = reach( ctx, 120 )
	return { spawn( "zone", "chalice", x, y, mine( ctx, { frames = 360, r = 45, x0 = x, y0 = y } ) ) }
end
M.mist = function( ctx ) return { spawn( "zone", "mist", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 15 ), r = size( ctx, 70 ) } ) ) } end
M.wand = function( ctx )
	local element = el( ctx, "water" )
	local look = DICTIONARY_LOOKS[element] or {}
	local frames = secs( ctx, 10 )
	GlobalsSetValue( BUSY_VAR, tostring( ctx.frame + frames ) )
	GamePrint( "Wand of Water: hold LMB to draw" )
	return { spawn( "aura", "quill", ctx.tx, ctx.ty, mine( ctx, { frames = frames, element = element, material = look.material or "water" } ) ) }
end

---- earth and sand ----

-- Integration: loose sand and earth at the cursor set into stone (effects/zone.lua). The Sigil of Earth shapes
-- what is there; it never makes matter of its own. Expansion and force widen the circle.
M.integration = function( ctx )
	local x, y = reach( ctx, 160 )
	return { spawn( "zone", "integrate", x, y, mine( ctx, { frames = 90, r = size( ctx, 40 ) } ) ) }
end

M.stone_wall = function( ctx ) return { spawn( "build", "wall", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 15 ), dx = ctx.aim_x } ) ) } end
M.sand_cage = function( ctx )
	local x, y = reach( ctx, 200 )
	return { spawn( "build", "cage", x, y, mine( ctx, { frames = secs( ctx, 10 ) } ) ) }
end
M.lift = function( ctx )
	return { spawn( "build", "lift", ctx.x, ctx.y + 4, mine( ctx, { frames = 200, life = secs( ctx, 20 ), steps = math.floor( 5 + ctx.power * 2 ) } ) ) }
end
M.bridge = function( ctx )
	local element = el( ctx, "sand" )
	local piece = ( element == "earth" or element == "stone" ) and "stone_plank" or "sand_plank"
	return { spawn( "build", "bridge", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 40 ), dx = ctx.aim_x,
		len = size( ctx, 100 ) * ( 1 + 0.2 * math.max( 0, ctx.spell.range or 0 ) ), piece = piece } ) ) }
end
M.ribbon = function( ctx )
	local x, y = reach( ctx, 160 )
	return { spawn( "build", "ribbon", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 30 ), tx = x, ty = y, element = el( ctx, "earth" ) } ) ) }
end
M.cloud = function( ctx )
	local x, y = reach( ctx, 150 )
	local element = el( ctx, "sand" )
	local piece = ( element == "sand" or element == "earth" or element == "sandstorm" ) and "sand_cloud" or "cloud"
	return { spawn( "build", "cloud", x, y, mine( ctx, { frames = secs( ctx, 30 ), piece = piece } ) ) }
end
M.sand_cloud = function( ctx )
	local x, y = reach( ctx, 150 )
	return { spawn( "build", "bed", x, y, mine( ctx, { frames = secs( ctx, 40 ) } ) ) }
end
M.sandcastle = function( ctx )
	local x, y = reach( ctx, 150 )
	return { spawn( "build", "castle", x, y, mine( ctx, { frames = secs( ctx, 60 ) } ) ) }
end
M.stone_arm = function( ctx )
	local x, y = reach( ctx, 150 )
	return { spawn( "build", "arm", x, y, mine( ctx, { frames = secs( ctx, 30 ), dx = ctx.aim_x, dy = ctx.aim_y } ) ) }
end
M.spikes = function( ctx )
	local x, y = reach( ctx, 160 )
	return { spawn( "zone", "spikes", x, y, mine( ctx, { frames = 5 } ) ) }
end
M.wallward = function( ctx ) return { spawn( "zone", "wallward", ctx.x, ctx.y - 4, mine( ctx, { frames = 20, r = size( ctx, 34 ) } ) ) } end
M.ice_road = function( ctx )
	local x, y = reach( ctx, 200 )
	local len = ctx.spell.named == "frozen_path" and 180 or 120
	return { spawn( "build", "road", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 20 ), tx = x, ty = y, len = size( ctx, len ), x0 = ctx.x, y0 = ctx.y } ) ) }
end

---- wind ----

M.sylph = function( ctx ) return { spawn( "aura", "sylph", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 30 ) } ) ) } end
M.pegasus = function( ctx ) return { spawn( "aura", "pegasus", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 20 ) } ) ) } end
M.skysoar = function( ctx ) return { spawn( "aura", "skysoar", ctx.x, ctx.y, mine( ctx, { frames = 20, dx = ctx.aim_x, dy = ctx.aim_y } ) ) } end
M.levitate = function( ctx ) return { spawn( "aura", "levitate", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 15 ) } ) ) } end
M.book = function( ctx ) return { spawn( "aura", "book", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 20 ) } ) ) } end
M.chair = function( ctx ) return { spawn( "aura", "chair", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 30 ) } ) ) } end
M.gale = function( ctx )
	return { spawn( "zone", "gale", ctx.x, ctx.y - 4, mine( ctx, { frames = secs( ctx, 10 ), dx = ctx.aim_x, dy = ctx.aim_y, len = size( ctx, 220 ) } ) ) }
end
M.wind_wall = function( ctx ) return { spawn( "aura", "wind_wall", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 15 ), radius = size( ctx, 28 ) } ) ) } end
M.whirlwind = function( ctx )
	local x, y = reach( ctx, 60 )
	local gx, gy = ground_below( x, y - 10, 80 )
	return { spawn( "mover", "whirlwind", x, ( gy or y ) - 2, mine( ctx, { frames = secs( ctx, 12 ), tx = x } ) ) }
end
M.bubble = function( ctx ) return { spawn( "aura", "bubble", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 25 ) } ) ) } end
M.umbrella = function( ctx ) return { spawn( "aura", "umbrella", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 25 ) } ) ) } end
M.guidance_items = function( ctx )
	local x, y = reach( ctx, 200 )
	return { spawn( "zone", "guidance_items", x, y, mine( ctx, { frames = 600, r = size( ctx, 150 ) } ) ) }
end

---- time, the mind, space ----

M["repeat"] = function( ctx )
	if GlobalsGetValue( LAST_SPELL_VAR or "witch_notebook.last_cast", "" ) == "" then
		GamePrint( "Nothing to repeat - cast another seal first" )
		return {}
	end
	return { spawn( "repeat", "cast", ctx.x, ctx.y, mine( ctx, { times = 3 } ) ) }
end
M.capture = function( ctx )
	local id, x, y = victim( ctx, 60 )
	return { spawn( "mover", "ribbon_flight", ctx.x + ctx.aim_x * 8, ctx.y - 4, mine( ctx, { frames = 120, target = id or 0, tx = x, ty = y,
		hold = secs( ctx, 5 ) } ) ) }
end
M.lockwax = function( ctx )
	local id, x, y = victim( ctx, 45 )
	if not id then
		GamePrint( "Lockwax: no enemy at the cursor" )
		return {}
	end
	hold_creature( id, secs( ctx, 8 ), "wax", "plasma", ctx.shooter )
	fx_burst( x, y, fx_color( "plasma", 0.3 ), 20, 50, 0.5 )
	return { "held:wax" }
end
M.cookpot = function( ctx ) return { spawn( "aura", "cookpot", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 30 ) } ) ) } end
M.washbarrel = function( ctx ) return { spawn( "aura", "washbarrel", ctx.x, ctx.y, mine( ctx, { frames = 150 } ) ) } end
M.makeover = function( ctx ) return { spawn( "aura", "makeover", ctx.x, ctx.y, mine( ctx, { frames = 600 } ) ) } end
M.reduction = function( ctx )
	local x, y = reach( ctx, 180 )
	return { spawn( "zone", "reduction", x, y, mine( ctx, { frames = 30, r = size( ctx, 40 ), hold = secs( ctx, 15 ) } ) ) }
end
M.counterclock = function( ctx ) return { spawn( "aura", "counterclock", ctx.x, ctx.y, mine( ctx, { frames = 90 } ) ) } end
M.counterclock_creatures = function( ctx )
	local x, y = reach( ctx, 180 )
	return { spawn( "zone", "rewind", x, y, mine( ctx, { frames = 150, r = size( ctx, 50 ) } ) ) }
end
M.time_stop = function( ctx )
	local x, y = reach( ctx, 180 )
	return { spawn( "zone", "time_stop", x, y, mine( ctx, { frames = secs( ctx, 4 ), r = size( ctx, 50 ) } ) ) }
end
M.warmth_zone = function( ctx )
	local x, y = reach( ctx, 160 )
	return { spawn( "zone", "warmth_zone", x, y, mine( ctx, { frames = secs( ctx, 60 ), r = size( ctx, 30 ) } ) ) }
end
M.disguise = function( ctx )
	-- One cloak at a time: a new one is put on over the old, which is dropped without giving the true look back
	-- (the new one keeps it and returns it).
	for _, old in ipairs( EntityGetWithTag( "witch_disguise" ) or {} ) do
		if effect_params( old ).owner == ctx.shooter then EntityKill( old ) end
	end
	local e = spawn( "aura", "disguise", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 30 ) } ) )
	EntityAddTag( e, "witch_disguise" )
	return { e }
end
M.scry = function( ctx )
	return { spawn( "scry", "gaze", ctx.x, ctx.y, mine( ctx, { frames = 150, tx = ctx.x + ctx.aim_x * 320, ty = ctx.y + ctx.aim_y * 320 } ) ) }
end
M.shadow = function( ctx ) return { spawn( "aura", "shadow", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 20 ) } ) ) } end
M.smoke_cloak = function( ctx ) return { spawn( "aura", "smoke_cloak", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 25 ) } ) ) } end
M.smoke_copies = function( ctx )
	local x, y = reach( ctx, 200 )
	return { spawn( "zone", "smoke_copies", x, y, mine( ctx, { frames = 10, r = 90, hold = secs( ctx, 15 ) } ) ) }
end
M.smoke_clone = function( ctx )
	return { spawn( "mover", "clone", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 20 ), side = ctx.aim_x >= 0 and -1 or 1 } ) ) }
end
M.smoke_fairy = function( ctx ) return { spawn( "mover", "fairy", ctx.x, ctx.y - 10, mine( ctx, { frames = secs( ctx, 25 ) } ) ) } end
M.puppet = function( ctx )
	local x, y = reach( ctx, 160 )
	local big = ctx.spell.named == "giant_water_puppet" and 2 or size( ctx, 1 )
	return { spawn( "mover", "puppet", x, y, mine( ctx, { frames = secs( ctx, 12 ), tx = x, ty = y, element = el( ctx, "light" ), big = big } ) ) }
end
M.lure = function( ctx )
	local x, y = reach( ctx, 150 )
	local gx, gy = ground_below( x, y - 10, 80 )
	return { spawn( "mover", "lure", x, ( gy or y ) - 3, mine( ctx, { frames = secs( ctx, 12 ) } ) ) }
end
M.remote_cloak = function( ctx ) return { spawn( "mover", "cloak", ctx.x, ctx.y - 10, mine( ctx, { frames = secs( ctx, 30 ) } ) ) } end
M.mirror = function( ctx ) return { spawn( "aura", "mirror", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 15 ) } ) ) } end
M.shade = function( ctx ) return { spawn( "aura", "shade", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 60 ) } ) ) } end
M.xray = function( ctx ) return { spawn( "aura", "xray", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 20 ) } ) ) } end
M.walk_liquid = function( ctx ) return { spawn( "aura", "walk_liquid", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 40 ) } ) ) } end
M.beastward = function( ctx ) return { spawn( "zone", "beastward", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 25 ), r = size( ctx, 50 ) } ) ) } end
M.beastward_strong = function( ctx )
	return { spawn( "zone", "beastward", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 50 ), r = size( ctx, 80 ), strong = 1 } ) ) }
end
M.forbidden_fire = function( ctx )
	local x, y = reach( ctx, 150 )
	return { spawn( "zone", "forbidden_fire", x, y, mine( ctx, { frames = secs( ctx, 30 ) } ) ) }
end

-- The Windowway: the first seal opens a window by the cursor, the next one its pair
M.portal = function( ctx )
	local x, y = reach( ctx, 220 )
	local waiting = tonumber( GlobalsGetValue( WINDOW_VAR, "0" ) ) or 0
	local e = spawn( "portal", "window", x, y, mine( ctx, { frames = secs( ctx, 90 ), element = el( ctx, "light" ) } ) )
	if waiting ~= 0 and EntityGetIsAlive( waiting ) then
		effect_set( e, "partner", waiting )
		effect_set( waiting, "partner", e )
		GlobalsSetValue( WINDOW_VAR, "0" )
		GamePrint( "The windows are linked: step into one to come out of the other" )
	else
		GlobalsSetValue( WINDOW_VAR, tostring( e ) )
		GamePrint( "A window is open - cast the seal again to open its pair" )
	end
	effect_sound( "teleport", x, y )
	return { e }
end
M.portal_small = function( ctx )
	local x, y = reach( ctx, 200 )
	local frames = secs( ctx, 15 )
	local a = spawn( "portal", "hand", ctx.x + ctx.aim_x * 14, ctx.y - 4 + ctx.aim_y * 14, mine( ctx, { frames = frames, element = el( ctx, "light" ) } ) )
	local b = spawn( "portal", "hand", x, y, mine( ctx, { frames = frames, element = el( ctx, "light" ), partner = a } ) )
	effect_set( a, "partner", b )
	return { a, b }
end
M.doorknob = function( ctx )
	local sx, sy = GlobalsGetValue( DOOR_VAR, "" ):match( "(-?[%d.]+),(-?[%d.]+)" )
	if not sx then
		GlobalsSetValue( DOOR_VAR, string.format( "%.1f,%.1f", ctx.x, ctx.y ) )
		GamePrint( "The doorknob remembered this place" )
		return { spawn( "portal", "mark", ctx.x, ctx.y + 4, mine( ctx, { frames = secs( ctx, 30 ) } ) ) }
	end
	return { spawn( "portal", "door", ctx.x + ctx.aim_x * 12, ctx.y, mine( ctx, { tx = tonumber( sx ), ty = tonumber( sy ) } ) ) }
end

---- the forbidden ----

-- a slow aura of stone: it grows for 'grow' frames, then stands a while
M.petrify = function( ctx )
	local x, y = reach( ctx, 180 )
	local grow = secs( ctx, 6 )
	return { spawn( "zone", "petrify", x, y, mine( ctx, { grow = grow, frames = grow + secs( ctx, 3 ), r = size( ctx, 90 ) } ) ) }
end
M.labyrinth = function( ctx )
	local x, y = reach( ctx, 180 )
	return { spawn( "zone", "labyrinth", x, y, mine( ctx, { frames = secs( ctx, 20 ), r = size( ctx, 70 ) } ) ) }
end
M.oblivion = function( ctx )
	return { spawn( "zone", "oblivion", ctx.x, ctx.y, mine( ctx, { frames = secs( ctx, 20 ), r = size( ctx, 80 ), hold = secs( ctx, 20 ) } ) ) }
end
M.heal = function( ctx ) return { spawn( "aura", "heal", ctx.x, ctx.y, mine( ctx, { frames = 180 } ) ) } end
M.golem = function( ctx )
	local dir = ctx.aim_x >= 0 and 1 or -1
	-- it is made of the ground it stands up from: ahead of the caster, or under them
	local gx, gy = ground_below( ctx.x + dir * 22, ctx.y - 10, 120 )
	if not gy then gx, gy = ground_below( ctx.x, ctx.y - 10, 120 ) end
	if not gy then
		GamePrint( "Golem: no ground here for it to rise from" )
		return {}
	end
	return { spawn( "mover", "golem", gx, gy, mine( ctx, { frames = secs( ctx, 30 ), dir = dir } ) ) }
end
M.wolf_curse = function( ctx )
	local x, y = reach( ctx, 200 )
	return { spawn( "zone", "wolf_curse", x, y, mine( ctx, { frames = 25, r = 45 } ) ) }
end
M.unpolymorph = function( ctx ) return { spawn( "zone", "unpolymorph", ctx.x, ctx.y, mine( ctx, { frames = 25, r = size( ctx, 60 ) } ) ) } end
M.slime = function( ctx )
	local x, y = reach( ctx, 200 )
	return { spawn( "zone", "slime", x, y, mine( ctx, { frames = 25, r = 45 } ) ) }
end
