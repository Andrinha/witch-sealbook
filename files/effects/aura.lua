-- Magic on the caster, following them (manifest.lua): warmth, flight, a bubble of air, cloaks of smoke and shadow,
-- a mirror, a dome against the rain, the flying book, the sealchair... p.owner is the caster, p.frames how long.

-- the caster's controls and character, if they have them
local function body( owner )
	return EntityGetFirstComponent( owner, "ControlsComponent" ), EntityGetFirstComponent( owner, "CharacterDataComponent" )
end

-- keeps the caster's flight from running out
local function endless_flight( cd )
	if cd then ComponentSetValue2( cd, "mFlyingTimeLeft", ComponentGetValue2( cd, "fly_time_max" ) ) end
end

local function set_velocity( cd, vx, vy )
	if cd then
		local ox, oy = ComponentGetValue2( cd, "mVelocity" )
		ComponentSetValue2( cd, "mVelocity", vx or ox, vy or oy )
	end
end

local done = effect_done

local function light( e, r, g, b, radius ) return effect_glow( e, r, g, b, radius, 0.8 ) end

local MODES = {}

-- Snugstone: a soft warmth around the caster - ice and snow melt, clothes dry, frost can't touch them
MODES.warmth = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -4 )
	if not owner or done( e, p, age ) then return end
	if age == 0 then
		light( e, 255, 170, 90, 80 )
		convert_around( e, MELTS.from, MELTS.to, 22, 2 )
	end
	if age % 2 == 0 then
		local a = Random( 0, 628 ) / 100
		local r = Random( 6, 16 )
		fx_dot( x + math.cos( a ) * r, y + math.sin( a ) * r * 0.7, fx_color( "fire", 0.45, 0.8 ), Random( -4, 4 ), -12, 0.9 )
	end
	if age % 30 == 0 then
		clear_effects( owner, { "WET", "FROZEN" } )
		give_effect( owner, MISC .. "effect_protection_freeze.xml", 45 )
	end
end

-- Phantasmal Fireball: a cold blue flame over the caster's head - it lights the way and frightens beasts, but doesn't burn
MODES.phantasm = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -20 )
	if not owner or done( e, p, age ) then return end
	effect_fire_loop( e, true )
	if age == 0 and not EntityGetFirstComponent( e, "LightComponent" ) then light( e, 120, 170, 255, 120 ) end
	fx_flame_ball( x, y, 6, age, true, 0.9 )
	if age % 15 == 0 then
		for _, id in ipairs( creatures_in( x, y, 70, owner ) ) do push_from( id, x, y, 70 ) end
	end
end

-- Watershot: water pours out of the book, as from a flask that never runs dry. Held with a book (lib.lua
-- effect_channel) it pours for as long as fire is held, towards the cursor; a scripted cast pours for p.frames the
-- way it was aimed. Like a tipped flask it pours harder the further away the cursor is.
MODES.pour = function( e, p, age )
	local held = ( p.channel_book or 0 ) > 0
	local owner, controls
	if held then owner, controls = effect_channel( p ) else owner = effect_owner( p ) end
	if not owner or ( not held and age >= p.frames ) then
		EntityKill( e )
		return
	end
	local x, y = EntityGetTransform( owner )
	-- Sasaran's Cloak: the water comes out of the cloak
	local remote = tonumber( GlobalsGetValue( "witch_notebook.remote", "0" ) ) or 0
	if remote > 0 and EntityGetIsAlive( remote ) then x, y = EntityGetTransform( remote ); y = y + 4 end
	y = y - 4
	local dx, dy, far = p.dx or 1, p.dy or 0, 1
	if held then
		local tx, ty = ComponentGetValue2( controls, "mMousePosition" )
		local d = math.sqrt( ( tx - x ) ^ 2 + ( ty - y ) ^ 2 )
		if d > 0.001 then dx, dy = ( tx - x ) / d, ( ty - y ) / d end
		far = math.min( 1, d / 120 )
	end
	-- the book's mouth, drawn back from a wall right in front of it
	local ox, oy = x + dx * 8, y + dy * 8
	local hit, hx, hy = RaytraceSurfaces( x, y, ox, oy )
	if hit then ox, oy = hx - dx * 2, hy - dy * 2 end
	EntitySetTransform( e, ox, oy )
	effect_loop( e, true, "data/audio/Desktop/materials.bank", "materials/spray_potion" )
	local speed = ( 90 + 60 * far ) * math.min( 1.5, math.max( 0.7, p.power or 1 ) )
	for i = 1, p.cells or 4 do
		GameCreateParticle( "water", ox + Random( -1, 1 ), oy + Random( -1, 1 ), 1,
			dx * speed + Random( -12, 12 ), dy * speed + Random( -12, 12 ), false, false, false )
	end
	if age % 3 == 0 then fx_dot( ox, oy, fx_color( "water", 0.7, 0.8 ), dx * speed * 0.6, dy * speed * 0.6, 0.2, 200 ) end
end

-- Rising Platform: a column of water beats up under the caster and lifts them
MODES.geyser = function( e, p, age )
	local owner, x, y = effect_follow( e, p )
	if not owner or done( e, p, age ) then return end
	local _, cd = body( owner )
	if age < p.frames - 12 then set_velocity( cd, nil, -230 ) end
	for i = 1, 6 do
		GameCreateParticle( "water", x + Random( -4, 4 ), y + 6, 1, Random( -20, 20 ), -Random( 120, 200 ), false, false, true )
	end
	for i = 1, 4 do fx_dot( x + Random( -6, 6 ), y + Random( 4, 30 ), fx_color( "water", 0.6 ), 0, -140, 0.25 ) end
end

-- Rising Wave: a wave rises under the caster and carries them forward and up
MODES.wave_ride = function( e, p, age )
	local owner, x, y = effect_follow( e, p )
	if not owner or done( e, p, age ) then return end
	local _, cd = body( owner )
	local dir = ( p.dx or 1 ) >= 0 and 1 or -1
	set_velocity( cd, dir * 170, age < p.frames * 0.6 and -110 or nil )
	for i = 1, 5 do
		GameCreateParticle( "water", x - dir * Random( 2, 10 ), y + 5, 1, -dir * Random( 30, 90 ), Random( -40, 10 ), false, false, true )
	end
	-- the crest curls over in front
	for i = 0, 6 do
		local a = math.pi * i / 6
		fx_dot( x + dir * ( 6 + math.sin( a ) * 6 ), y + 6 - math.cos( a ) * 8, fx_color( "water", 0.7 ), -dir * 20, 0, 0.12 )
	end
end

-- Sylph Shoes: the caster floats - their levitation doesn't run out and they fall softly; a whirl of wind at their feet
MODES.sylph = function( e, p, age )
	local owner, x, y = effect_follow( e, p )
	if not owner or done( e, p, age ) then return end
	local _, cd = body( owner )
	endless_flight( cd )
	if cd then
		local vx, vy = ComponentGetValue2( cd, "mVelocity" )
		if vy > 50 then ComponentSetValue2( cd, "mVelocity", vx, 50 ) end
	end
	for side = -1, 1, 2 do
		local a = age * 0.35 * side
		fx_dot( x + side * 2 + math.cos( a ) * 3, y + 5 + math.sin( a ), fx_color( "wind", 0.5, 0.8 ), 0, 6, 0.25 )
	end
end

-- Pegasus Carriage: a long level flight - endless levitation and little weight; feathers fly behind
MODES.pegasus = function( e, p, age )
	local owner, x, y = effect_follow( e, p )
	if not owner then return end
	local platforming = EntityGetFirstComponent( owner, "CharacterPlatformingComponent" )
	if age >= p.frames then
		if platforming and ( p.gravity or 0 ) > 0 then ComponentSetValue2( platforming, "pixel_gravity", p.gravity ) end
		EntityKill( e )
		return
	end
	if age == 0 and platforming then
		p.gravity = ComponentGetValue2( platforming, "pixel_gravity" )
		effect_set( e, "gravity", p.gravity )
		ComponentSetValue2( platforming, "pixel_gravity", p.gravity * 0.3 )
	end
	local _, cd = body( owner )
	endless_flight( cd )
	-- wings of light beat on both sides
	local beat = math.sin( age * 0.25 )
	for side = -1, 1, 2 do
		for k = 1, 5 do
			local t = k / 5
			fx_dot( x + side * ( 3 + 9 * t ), y - 6 - beat * 6 * t + t * t * 4, fx_color( "air", 0.8 ), 0, 0, 0.05 )
		end
	end
	if age % 6 == 0 then fx_dot( x + Random( -5, 5 ), y - 4, fx_color( "air", 0.95 ), Random( -10, 10 ), 5, 1.2, 15 ) end
end

-- Skysoaring: a gust throws the caster where they aim
MODES.skysoar = function( e, p, age )
	local owner, x, y = effect_follow( e, p )
	if not owner or done( e, p, age ) then return end
	local _, cd = body( owner )
	if age < 12 then set_velocity( cd, p.dx * 420, p.dy * 420 - 70 ) end
	for i = 1, 4 do
		local back = Random( 4, 20 )
		fx_dot( x - p.dx * back + Random( -3, 3 ), y - p.dy * back + Random( -3, 3 ), fx_color( "wind", 0.7 ), -p.dx * 90, -p.dy * 90, 0.2 )
	end
end

-- Wind Wall: a ring of wind round the caster turns projectiles back and keeps enemies out
MODES.wind_wall = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -4 )
	if not owner or done( e, p, age ) then return end
	local r = p.radius or 28
	for i = 1, 10 do
		local a = age * 0.2 + i / 10 * 2 * math.pi + Random( -10, 10 ) / 100
		local rr = r + Random( -2, 2 )
		fx_dot( x + math.cos( a ) * rr, y + math.sin( a ) * rr, fx_color( "wind", 0.6, 0.7 ), -math.sin( a ) * 80, math.cos( a ) * 80, 0.15 )
	end
	for _, id in ipairs( EntityGetInRadiusWithTag( x, y, r + 6, "projectile" ) or {} ) do
		local proj = EntityGetFirstComponent( id, "ProjectileComponent" )
		local vel = EntityGetFirstComponent( id, "VelocityComponent" )
		if proj and vel and ComponentGetValue2( proj, "mWhoShot" ) ~= owner then
			local px, py = EntityGetTransform( id )
			local nx, ny = px - x, py - y
			local d = math.max( 1, math.sqrt( nx * nx + ny * ny ) )
			nx, ny = nx / d, ny / d
			local vx, vy = ComponentGetValue2( vel, "mVelocity" )
			local dot = vx * nx + vy * ny
			if dot < 0 then ComponentSetValue2( vel, "mVelocity", vx - 2 * dot * nx, vy - 2 * dot * ny ) end
		end
	end
	if age % 3 == 0 then
		for _, id in ipairs( creatures_in( x, y, r + 4, owner ) ) do push_from( id, x, y, 60 ) end
	end
end

-- Aeriforms (Bubble Carriage): a bubble of air round the caster - they breathe under water, liquid keeps away
MODES.bubble = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -4 )
	if not owner or done( e, p, age ) then return end
	if age == 0 then EntityAddComponent2( e, "LiquidDisplacerComponent", { radius = 12, velocity_x = 30, velocity_y = 30 } ) end
	if age % 60 == 0 then give_effect( owner, MISC .. "effect_breath_underwater.xml", 90 ) end
	if age % 2 == 0 then
		local c = fx_color( "air", 0.5, 0.7 )
		for i = 0, 11 do
			local a = i / 12 * 2 * math.pi + age * 0.01
			local wobble = 1 + 0.06 * math.sin( age * 0.1 + i )
			fx_dot( x + math.cos( a ) * 13 * wobble, y + math.sin( a ) * 13 / wobble, c, 0, 0, 0.05 )
		end
		fx_dot( x - 5, y - 7, fx_color( "air", 1 ), 0, 0, 0.05 ) -- a glint
	end
	if age % 7 == 0 then fx_dot( x + Random( -8, 8 ), y + 8, fx_color( "air", 0.9 ), 0, -25, 0.5 ) end
end

-- Light Reducing Spell: bright light and blinding don't reach the caster's eyes
MODES.shade = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -10 )
	if not owner or done( e, p, age ) then return end
	if age % 4 == 0 then clear_effects( owner, { "BLINDNESS" } ) end
	if age % 25 == 0 then
		for side = -1, 1, 2 do fx_dot( x + side * 2, y, color_abgr_merge( 90, 60, 140, 200 ), 0, 0, 0.4 ) end
	end
end

-- smoke or shadow round the caster; enemies lose sight of them
local function veil( e, p, age, element, rise )
	local owner, x, y = effect_follow( e, p, -6 )
	if not owner or done( e, p, age ) then return end
	if age % 60 == 0 then give_effect( owner, MISC .. "effect_invisibility.xml", 75 ) end
	for i = 1, 3 do
		local a = Random( 0, 628 ) / 100
		local r = Random( 3, 10 )
		fx_dot( x + math.cos( a ) * r * 0.7, y + math.sin( a ) * r, fx_color( element, Random( 0, 20 ) / 100, 0.6 ), Random( -8, 8 ), rise, 0.6 )
	end
	return owner, x, y
end

-- Illusion Cloak: a cloak and a pointed hood of smoke
MODES.smoke_cloak = function( e, p, age )
	local owner, x, y = veil( e, p, age, "smoke", -8 )
	if not owner then return end
	if age % 3 == 0 then
		local c = fx_color( "smoke", 0.3, 0.7 )
		for k = 0, 4 do fx_dot( x + ( k - 2 ) * 1.2, y - 8 - ( 2 - math.abs( k - 2 ) ) * 2, c, 0, 0, 0.1 ) end -- the hood
		if Random( 1, 6 ) == 1 then GameCreateParticle( "smoke", x + Random( -3, 3 ), y + 4, 1, 0, -10, false, false, true ) end
	end
end

-- Concealment, Borrowshade: the caster wraps themselves in shadow
MODES.shadow = function( e, p, age )
	local owner, x, y = veil( e, p, age, "vacuum", -4 )
	if not owner then return end
	if age % 2 == 0 then
		local a = age * 0.15
		fx_dot( x + math.cos( a ) * 8, y + math.sin( a ) * 10, color_abgr_merge( 40, 20, 60, 220 ), 0, 0, 0.3 )
	end
end

-- Makeover Mask: the caster shines - no stains, sparkles all around, and for a moment enemies can't see them
MODES.makeover = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -6 )
	if not owner or done( e, p, age ) then return end
	if age == 0 then
		clear_effects( owner, DIRT )
		give_effect( owner, MISC .. "effect_stainless_armour.xml", p.frames )
		give_effect( owner, MISC .. "effect_invisibility.xml", 180 )
		fx_burst( x, y, fx_color( "flicker", 0.6 ), 40, 70, 0.8 )
	end
	if age < 120 and age % 2 == 0 then
		local a = Random( 0, 628 ) / 100
		local r = Random( 4, 14 )
		local c = Random( 1, 2 ) == 1 and fx_color( "flicker", 0.7 ) or fx_color( "sunfire", 0.7 )
		-- a little four-pointed star
		local sx, sy = x + math.cos( a ) * r, y + math.sin( a ) * r
		fx_dot( sx, sy, c, 0, -6, 0.35 )
		fx_dot( sx + 1, sy, c, 0, -6, 0.2 ); fx_dot( sx - 1, sy, c, 0, -6, 0.2 )
		fx_dot( sx, sy + 1, c, 0, -6, 0.2 ); fx_dot( sx, sy - 1, c, 0, -6, 0.2 )
	end
end

-- Washbarrel: the caster spins in a whirl of water that washes off stains, poison, slime and fire
MODES.washbarrel = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -4 )
	if not owner then return end
	if age >= p.frames then
		clear_effects( owner, DIRT )
		give_effect( owner, MISC .. "effect_stainless_armour.xml", 600 )
		fx_burst( x, y, fx_color( "water", 0.8 ), 30, 60, 0.6 )
		EntityKill( e )
		return
	end
	for i = 1, 6 do
		local t = Random( 0, 1000 ) / 1000
		local a = age * 0.4 + t * 12
		local r = 8 + 3 * math.sin( t * 6 )
		fx_dot( x + math.cos( a ) * r, y + 8 - t * 22, fx_color( "water", 0.3 + 0.4 * t, 0.9 ), -math.sin( a ) * 30, -10, 0.15 )
	end
	if age % 5 == 0 then GameCreateParticle( "water", x + Random( -6, 6 ), y - Random( 0, 12 ), 1, Random( -40, 40 ), 0, false, false, true ) end
	if age % 10 == 0 then clear_effects( owner, { "OILED", "BLOODY", "SLIMY", "RADIOACTIVE", "POISONED", "ON_FIRE" } ) end
end

-- Magic Cookpot: the flask in hand is stilled in time - its contents don't run out while the spell lasts
local function held_item( owner )
	local inv = EntityGetFirstComponent( owner, "Inventory2Component" )
	local item = inv and ComponentGetValue2( inv, "mActiveItem" ) or 0
	if item ~= 0 and EntityGetFirstComponentIncludingDisabled( item, "MaterialInventoryComponent" ) then return item end
end

local function contents( item )
	local comp = EntityGetFirstComponentIncludingDisabled( item, "MaterialInventoryComponent" )
	local counts = comp and ComponentGetValue2( comp, "count_per_material_type" ) or {}
	local out, total = {}, 0
	for i, n in pairs( counts ) do
		if n > 0 then
			out[i - 1] = n
			total = total + n
		end
	end
	return out, total
end

local function set_amount( item, id, n )
	local name = CellFactory_GetName( id )
	RemoveMaterialInventoryMaterial( item, name )
	if n > 0 then AddMaterialInventoryMaterial( item, name, math.floor( n ) ) end
end

MODES.cookpot = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -6 )
	if not owner or done( e, p, age ) then return end
	if age == 0 then
		local item = held_item( owner )
		if not item then
			GamePrint( "Hold a flask - its contents will freeze in time" )
			EntityKill( e )
			return
		end
		local parts = {}
		for id, n in pairs( ( contents( item ) ) ) do parts[#parts + 1] = id .. ":" .. n end
		effect_set( e, "item", item )
		effect_set( e, "snapshot", table.concat( parts, "," ) )
		return
	end
	local item = math.floor( ( p.item or 0 ) + 0.5 )
	if item == 0 or not EntityGetIsAlive( item ) then
		EntityKill( e )
		return
	end
	if age % 3 == 0 then
		local now = contents( item )
		for id, n in effect_text( p.snapshot ):gmatch( "(%d+):(%d+)" ) do
			id, n = tonumber( id ), tonumber( n )
			if ( now[id] or 0 ) < n then set_amount( item, id, n ) end
		end
	end
	-- a small clock ticking round the flask
	local ix, iy = EntityGetTransform( item )
	if age % 2 == 0 then
		local a = -age * 0.05
		fx_dot( ix + math.cos( a ) * 5, iy + math.sin( a ) * 5, fx_color( "air", 0.7, 0.8 ), 0, 0, 0.1 )
	end
end

-- Counterclock: time runs backwards for the caster's things - the spells in their wands come back, mana too
MODES.counterclock = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -6 )
	if not owner or done( e, p, age ) then return end
	if age == 0 then
		GameRegenItemActionsInPlayer( owner )
		for _, item in ipairs( GameGetAllInventoryItems( owner ) or {} ) do
			local ability = EntityGetFirstComponentIncludingDisabled( item, "AbilityComponent" )
			if ability and EntityHasTag( item, "wand" ) then
				ComponentSetValue2( ability, "mana", ComponentGetValue2( ability, "mana_max" ) )
			end
		end
		effect_sound( "magic", x, y )
	end
	-- a clock whose hands spin backwards
	local c = fx_color( "crystal", 0.6, 0.9 )
	if age % 2 == 0 then
		for i = 0, 11 do
			local a = i / 12 * 2 * math.pi
			fx_dot( x + math.cos( a ) * 14, y + math.sin( a ) * 14, c, 0, 0, 0.05 )
		end
	end
	for k = 1, 6 do
		fx_dot( x + math.cos( -age * 0.3 ) * k * 1.8, y + math.sin( -age * 0.3 ) * k * 1.8, c, 0, 0, 0.04 )
		fx_dot( x + math.cos( -age * 0.05 ) * k * 1.2, y + math.sin( -age * 0.05 ) * k * 1.2, c, 0, 0, 0.04 )
	end
end

-- Mirror Cloak: the caster takes on the look of the nearest beast - its kind takes them for one of its own.
-- The look is the beast's own sprite on the caster's body: only what is seen changes. The caster moves, flies,
-- casts and is hit exactly as before - not as polymorphine does it, which makes one the beast.
-- The caster's true look and kind are kept on the caster, not on the effect, so that a second cloak over the first,
-- or a reload, cannot take the borrowed ones for the true ones.

-- the sprite a creature is seen by: the one tagged "character" (the player's), else its first animated one
local function body_sprite( id )
	local tagged = EntityGetFirstComponent( id, "SpriteComponent", "character" )
	if tagged then return tagged end
	for _, sprite in ipairs( EntityGetComponent( id, "SpriteComponent" ) or {} ) do
		local file = ComponentGetValue2( sprite, "image_file" )
		if type( file ) == "string" and file:find( "%.xml$" ) then return sprite end
	end
end

-- the caster's arm is drawn apart from their body: it is hidden while they look like a beast
local function show_arm( owner, shown )
	for _, child in ipairs( EntityGetAllChildren( owner ) or {} ) do
		if EntityHasTag( child, "player_arm_r" ) then
			for _, sprite in ipairs( EntityGetComponent( child, "SpriteComponent" ) or {} ) do
				ComponentSetValue2( sprite, "alpha", shown and 1 or 0 )
			end
		end
	end
end

-- Puts the beast's look on the caster; false when either has no sprite to speak of.
local function wear_look( owner, beast )
	local mine, theirs = body_sprite( owner ), body_sprite( beast )
	local file = theirs and ComponentGetValue2( theirs, "image_file" )
	if not mine or type( file ) ~= "string" or not file:find( "%.xml$" ) then return false end
	if effect_text( effect_params( owner ).witch_true_sprite ) == "" then
		effect_set( owner, "witch_true_sprite", ComponentGetValue2( mine, "image_file" ) )
		effect_set( owner, "witch_true_offset", string.format( "%g,%g",
			ComponentGetValue2( mine, "offset_x" ), ComponentGetValue2( mine, "offset_y" ) ) )
	end
	ComponentSetValue2( mine, "image_file", file )
	ComponentSetValue2( mine, "offset_x", ComponentGetValue2( theirs, "offset_x" ) )
	ComponentSetValue2( mine, "offset_y", ComponentGetValue2( theirs, "offset_y" ) )
	EntityRefreshSprite( owner, mine )
	show_arm( owner, false )
	return true
end

-- Gives the caster their own look and kind back, if a cloak had taken them.
local function shed_guise( owner )
	local saved = effect_params( owner )
	local file, mine = effect_text( saved.witch_true_sprite ), body_sprite( owner )
	if file ~= "" and mine then
		local ox, oy = effect_text( saved.witch_true_offset ):match( "([-%d.]+),([-%d.]+)" )
		ComponentSetValue2( mine, "image_file", file )
		ComponentSetValue2( mine, "offset_x", tonumber( ox ) or 0 )
		ComponentSetValue2( mine, "offset_y", tonumber( oy ) or 0 )
		EntityRefreshSprite( owner, mine )
		show_arm( owner, true )
	end
	effect_set( owner, "witch_true_sprite", "" )
	local herd, genome = effect_text( saved.witch_true_herd ), EntityGetFirstComponent( owner, "GenomeDataComponent" )
	if herd ~= "" and genome then ComponentSetValue2( genome, "herd_id", tonumber( herd ) or 0 ) end
	effect_set( owner, "witch_true_herd", "" )
end

MODES.disguise = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -6 )
	if not owner then return end
	local genome = EntityGetFirstComponent( owner, "GenomeDataComponent" )
	if age == 0 then
		local beast = nearest_creature( x, y, 250, owner )
		local other = beast and EntityGetFirstComponent( beast, "GenomeDataComponent" )
		if not genome or not other then
			-- no one to mirror: a cloak already worn comes off
			GamePrint( "No beast nearby whose guise you could take" )
			shed_guise( owner )
			EntityKill( e )
			return
		end
		if effect_text( effect_params( owner ).witch_true_herd ) == "" then
			effect_set( owner, "witch_true_herd", tostring( ComponentGetValue2( genome, "herd_id" ) ) )
		end
		ComponentSetValue2( genome, "herd_id", ComponentGetValue2( other, "herd_id" ) )
		local seen = wear_look( owner, beast )
		local name = EntityGetName( beast )
		if GameTextGetTranslatedOrNot then name = GameTextGetTranslatedOrNot( name ) end
		GamePrint( ( seen and "You look like " or "To them you are " ) .. ( name ~= "" and name or "one of their own" ) )
		fx_burst( x, y, fx_color( "air", 0.9 ), 30, 60, 0.5 )
		return
	end
	if age >= p.frames then
		shed_guise( owner )
		fx_burst( x, y, fx_color( "air", 0.9 ), 20, 50, 0.4 )
		EntityKill( e )
		return
	end
	if age % 5 == 0 then fx_dot( x + Random( -5, 5 ), y + Random( -8, 6 ), fx_color( "air", 1, 0.8 ), 0, 0, 0.3 ) end
end

-- Mirror: a mirrored sphere round the caster - enemies' projectiles bounce back at them
MODES.mirror = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -4 )
	if not owner or done( e, p, age ) then return end
	local r = 18
	local genome = EntityGetFirstComponent( owner, "GenomeDataComponent" )
	for _, id in ipairs( EntityGetInRadiusWithTag( x, y, r + 4, "projectile" ) or {} ) do
		local proj = EntityGetFirstComponent( id, "ProjectileComponent" )
		local vel = EntityGetFirstComponent( id, "VelocityComponent" )
		if proj and vel and ComponentGetValue2( proj, "mWhoShot" ) ~= owner then
			local px, py = EntityGetTransform( id )
			local vx, vy = ComponentGetValue2( vel, "mVelocity" )
			if ( px - x ) * vx + ( py - y ) * vy < 0 then
				ComponentSetValue2( vel, "mVelocity", -vx, -vy )
				ComponentSetValue2( proj, "mWhoShot", owner )
				if genome then ComponentSetValue2( proj, "mShooterHerdId", ComponentGetValue2( genome, "herd_id" ) ) end
				fx_burst( px, py, fx_color( "air", 1 ), 8, 40, 0.3 )
			end
		end
	end
	if age % 2 == 0 then
		for i = 0, 13 do
			local a = i / 14 * 2 * math.pi + age * 0.02
			local shine = 0.5 + 0.5 * math.max( 0, math.cos( a + 2.2 ) )
			fx_dot( x + math.cos( a ) * r, y + math.sin( a ) * r, fx_color( "air", shine, 0.4 + 0.5 * shine ), 0, 0, 0.05 )
		end
	end
end

-- Rainwarding: a clear dome over the caster - rain and projectiles from above don't get through
MODES.umbrella = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -22 )
	if not owner or done( e, p, age ) then return end
	if age == 0 then
		convert_around( e, "water,water_salt,water_swamp,swamp,acid,blood,oil,slime,poison,radioactive_liquid,mud,urine",
			"air,air,air,air,air,air,air,air,air,air,air,air", 13, 6 )
	end
	for _, id in ipairs( EntityGetInRadiusWithTag( x, y + 12, 26, "projectile" ) or {} ) do
		local proj = EntityGetFirstComponent( id, "ProjectileComponent" )
		local vel = EntityGetFirstComponent( id, "VelocityComponent" )
		local px, py = EntityGetTransform( id )
		if proj and vel and ComponentGetValue2( proj, "mWhoShot" ) ~= owner and py < y + 12 then
			local vx, vy = ComponentGetValue2( vel, "mVelocity" )
			if vy > 0 then
				ComponentSetValue2( vel, "mVelocity", vx * 0.6, -vy * 0.5 )
				fx_burst( px, py, fx_color( "air", 1 ), 5, 30, 0.2 )
			end
		end
	end
	if age % 2 == 0 then
		local c = fx_color( "air", 0.7, 0.55 )
		for i = 0, 12 do
			local a = math.pi + math.pi * i / 12
			fx_dot( x + math.cos( a ) * 20, y + 12 + math.sin( a ) * 14, c, 0, 0, 0.05 )
		end
	end
end

-- Garmentglimpse: the caster sees through walls - the fog of war around them clears
MODES.xray = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -10 )
	if not owner then return end
	if age == 0 then give_effect( owner, MISC .. "effect_remove_fog_of_war.xml", p.frames ) end
	if done( e, p, age ) then return end
	if age < 60 then
		local r = age * 4
		for i = 0, 15 do
			local a = i / 16 * 2 * math.pi
			fx_dot( x + math.cos( a ) * r, y + math.sin( a ) * r, fx_color( "crystal", 0.7, 1 - age / 60 ), 0, 0, 0.05 )
		end
	end
end

-- Snow-walking: the caster walks on snow and water without sinking
MODES.walk_liquid = function( e, p, age )
	local owner, x, y = effect_follow( e, p )
	if not owner or done( e, p, age ) then return end
	local _, cd = body( owner )
	local wet, wx, wy = RaytraceSurfacesAndLiquiform( x, y - 2, x, y + 7 )
	local solid = RaytraceSurfaces( x, y - 2, x, y + 7 )
	if wet and not solid and cd then
		local vx, vy = ComponentGetValue2( cd, "mVelocity" )
		if vy > 0 then ComponentSetValue2( cd, "mVelocity", vx, 0 ) end
		if wy < y + 4 then EntitySetTransform( owner, x, wy - 4 ) end
		if age % 3 == 0 then
			fx_dot( x - 4, wy, fx_color( "water", 0.8 ), -15, 0, 0.3 )
			fx_dot( x + 4, wy, fx_color( "water", 0.8 ), 15, 0, 0.3 )
		end
	end
end

-- Levitation: the caster rises smoothly and floats; up and down move them
local function hover( e, p, age, lift, draw )
	local owner, x, y = effect_follow( e, p )
	if not owner or done( e, p, age ) then return end
	local controls, cd = body( owner )
	if age == 0 then
		local hit, _, hy = Raytrace( x, y - 8, x, y - 8 - lift )
		p.alt = hit and hy + 14 or y - lift
		effect_set( e, "alt", p.alt )
	end
	local alt = p.alt or y
	if controls then
		if ComponentGetValue2( controls, "mButtonDownFly" ) or ComponentGetValue2( controls, "mButtonDownUp" ) then alt = alt - 1.5 end
		if ComponentGetValue2( controls, "mButtonDownDown" ) then alt = alt + 1.5 end
	end
	if p.follow_ground then
		local gx, gy = ground_below( x, y - 4, 80 )
		if gy then alt = gy - p.follow_ground end
	end
	effect_set( e, "alt", alt )
	set_velocity( cd, nil, math.max( -90, math.min( 90, ( alt - y ) * 5 ) ) + math.sin( age * 0.08 ) * 4 )
	endless_flight( cd )
	if draw then draw( x, y, age ) end
end

MODES.levitate = function( e, p, age )
	hover( e, p, age, 36, function( x, y, age )
		if age % 2 == 0 then fx_dot( x + Random( -4, 4 ), y + 6, fx_color( "wind", 0.7, 0.8 ), 0, 20, 0.3 ) end
	end )
end

-- Expansion Levitation: the book grows and floats under the caster's feet - they ride it
-- The book is drawn from its fore-edge, wide open, its halves beating like wings (gfx/flying_book_1..3.png: tips
-- up, level, down). It grows from the size it has in hand when the seal wakes and shrinks back as it ends; a page
-- comes loose behind it now and then.
local BOOK_BEAT = { 1, 2, 3, 2 }
MODES.book = function( e, p, age )
	hover( e, p, age, 20, function( x, y, age )
		local grown = math.min( age, p.frames - age )
		local frame = grown < 6 and "small" or grown < 12 and "mid" or BOOK_BEAT[math.floor( age / 7 ) % 4 + 1]
		-- the frames are 34 x 20 with the spine on row 13: the spine lies under the caster's feet
		local cx, cy = math.floor( x + 0.5 ), math.floor( y + 0.5 ) + ( type( frame ) == "number" and 7 or 10 )
		GameCreateSpriteForXFrames( "mods/witch_notebook/files/gfx/flying_book_" .. frame .. ".png", cx, cy, true, 0, 0, 1, false )
		if grown < 12 then
			-- the Sign of Enlarge at work: light bursts out round the growing book
			if age % 2 == 0 then
				local a = Random( 0, 628 ) / 100
				fx_dot( x + math.cos( a ) * 4, y + 10 + math.sin( a ) * 2, fx_color( "light", 0.8 ), math.cos( a ) * 50, math.sin( a ) * 25, 0.3 )
			end
			return
		end
		-- the air it rides on, pushed down by each beat, and a loose page left behind
		if age % 7 == 0 then
			for side = -1, 1, 2 do fx_dot( x + side * Random( 6, 15 ), y + 12, fx_color( "wind", 0.8, 0.6 ), side * 12, 22, 0.35 ) end
		end
		if age % 45 == 0 then
			for k = 0, 2 do fx_dot( x - 12 + k, y + 6, color_abgr_merge( 240, 230, 202, 255 ), Random( -25, -10 ), Random( -12, 4 ), 0.9, 30 ) end
		end
	end )
end

-- Sealchair: a stone armchair carries the caster, walking over the ground
MODES.chair = function( e, p, age )
	p.follow_ground = 12
	hover( e, p, age, 12, function( x, y, age )
		local step = math.floor( age / 8 ) % 2
		GameCreateSpriteForXFrames( "mods/witch_notebook/files/gfx/sealchair.png", x - 2, y + 2 + step, true, 0, 0, 1, false )
		if age % 8 == 0 then fx_dot( x + ( step == 0 and -5 or 5 ), y + 11, fx_color( "earth", 0.3 ), 0, -10, 0.4 ) end
	end )
end

-- Healingcraft (forbidden): the caster's wounds close
MODES.heal = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -6 )
	if not owner or done( e, p, age ) then return end
	local dm = EntityGetFirstComponent( owner, "DamageModelComponent" )
	if dm and age % 10 == 0 then
		local hp, max_hp = ComponentGetValue2( dm, "hp" ), ComponentGetValue2( dm, "max_hp" )
		ComponentSetValue2( dm, "hp", math.min( max_hp, hp + max_hp * 0.03 ) )
	end
	if age % 2 == 0 then fx_dot( x + Random( -6, 6 ), y + Random( -4, 8 ), color_abgr_merge( 150, 255, 170, 230 ), 0, -20, 0.6 ) end
end

-- Amplification Scroll: the next spells are stronger - golden rings round the caster
MODES.amplify = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -6 )
	if not owner or done( e, p, age ) then return end
	local r = 6 + age * 0.4
	for i = 0, 9 do
		local a = i / 10 * 2 * math.pi + age * 0.1
		fx_dot( x + math.cos( a ) * r, y + math.sin( a ) * r * 0.4, fx_color( "sunfire", 0.5, 1 - age / p.frames ), 0, -10, 0.1 )
	end
end

-- Wand of Water: a quill of water follows the cursor; with the button held it draws lines of water in the air
MODES.quill = function( e, p, age )
	local owner = effect_owner( p )
	if not owner or done( e, p, age ) then
		if not owner then EntityKill( e ) end
		return
	end
	local controls = EntityGetFirstComponent( owner, "ControlsComponent" )
	if not controls then return end
	local mx, my = ComponentGetValue2( controls, "mMousePosition" )
	local px, py = p.px or mx, p.py or my
	-- the quill glides after the cursor
	local x, y = px + ( mx - px ) * 0.35, py + ( my - py ) * 0.35
	effect_set( e, "px", x )
	effect_set( e, "py", y )
	EntitySetTransform( e, x, y )
	local material = p.material ~= "" and p.material or "water"
	local c = effect_color( p.element, 0.4 )
	for k = 0, 4 do fx_dot( x + k * 0.8, y - k * 1.6, c, 0, 0, 0.05 ) end -- the quill's nib
	if ComponentGetValue2( controls, "mButtonDownFire" ) then
		local d = math.sqrt( ( x - px ) ^ 2 + ( y - py ) ^ 2 )
		local n = math.max( 1, math.floor( d / 1.5 ) )
		for i = 0, n do
			local t = i / n
			GameCreateCosmeticParticle( material, px + ( x - px ) * t, py + ( y - py ) * t, 1, 0, 0, 0, 2.5, 3.5, true, false, false, false, 0, 0 )
		end
		if age % 2 == 0 then GameCreateParticle( material, x, y, 1, 0, 0, false, false, true ) end
	end
end

EFFECT_MODES.aura = MODES
