-- Effects on a creature (lib.lua hold_creature): it stays where it was caught for p.frames, its mind still, and the
-- magic that holds it is seen around it. Modes are the looks: a white ribbon (Capture Pennant), a clock (Time Stop),
-- sealing wax (Lockwax), a ball of water (a water seal's Binding; the Water Cage's own sphere), sand. 'shrunk' makes
-- it small and weak instead (Reduction).
-- The effect is the creature's child: it ends with it.

local AI = { "AnimalAIComponent", "AdvancedFishAIComponent", "WormAIComponent", "ControlsComponent" }

local function set_mind( id, enabled )
	for _, name in ipairs( AI ) do
		for _, comp in ipairs( EntityGetComponentIncludingDisabled( id, name ) or {} ) do
			if not ( name == "ControlsComponent" and EntityHasTag( id, "player_unit" ) ) then
				EntitySetComponentIsEnabled( id, comp, enabled )
			end
		end
	end
end

-- keeps the creature in place; draws the look; lets it go at the end. Returns the creature, or nil when done
local function hold( e, p, age, release )
	local id = effect_owner( p )
	if not id then
		EntityKill( e )
		return
	end
	if age == 0 then set_mind( id, false ) end
	if age >= p.frames then
		set_mind( id, true )
		if release then release( id, p ) end
		EntityKill( e )
		return
	end
	EntitySetTransform( id, p.hx, p.hy )
	push_creature( id, 0, 0, true )
	return id
end

local function ribbon( e, p, age )
	local id = hold( e, p, age, function( id, p )
		-- the ribbon unwinds and flies off
		local c = fx_color( "light", 0.9 )
		for i = 1, 24 do
			local a = i / 24 * 2 * math.pi
			fx_dot( p.hx + math.cos( a ) * 6, p.hy - 5 + math.sin( a ) * 8, c, math.cos( a ) * 40, math.sin( a ) * 40 - 20, 0.6, 40 )
		end
	end )
	if not id then return end
	-- a white ribbon wound round and round, slowly turning; it tightens in the first frames
	local c = fx_color( "light", 0.92 )
	local tight = math.min( 1, age / 20 )
	local r = 12 - 5 * tight
	for i = 0, 17 do
		local t = i / 17
		local a = age * 0.08 + t * 4 * math.pi
		local depth = math.sin( a )
		if depth > -0.3 or i % 3 == 0 then
			fx_dot( p.hx + math.cos( a ) * r, p.hy + 3 - t * 16 + depth * 1.5, c, 0, 0, 0.05 )
		end
	end
	-- the pennant's tail flutters
	if age % 3 == 0 then fx_dot( p.hx + 8 + math.sin( age * 0.3 ) * 2, p.hy - 12, c, 10, -4, 0.4 ) end
end

local function clock( e, p, age )
	local id = hold( e, p, age )
	if not id then return end
	local cx, cy = p.hx, p.hy - 5
	local c = fx_color( "air", 0.6, 0.9 )
	if age % 2 == 0 then
		for i = 0, 11 do
			local a = i / 12 * 2 * math.pi
			fx_dot( cx + math.cos( a ) * 11, cy + math.sin( a ) * 11, c, 0, 0, 0.06 )
		end
	end
	-- the hands stand still, and tremble
	local shake = ( age % 30 < 2 ) and 0.2 or 0
	for k = 1, 5 do
		fx_dot( cx + math.cos( -1.2 + shake ) * k * 1.4, cy + math.sin( -1.2 + shake ) * k * 1.4, c, 0, 0, 0.05 )
		fx_dot( cx + math.cos( 0.4 ) * k * 1.9, cy + math.sin( 0.4 ) * k * 1.9, c, 0, 0, 0.05 )
	end
end

local function wax( e, p, age )
	local id = hold( e, p, age, function( id, p )
		for i = 1, 18 do fx_dot( p.hx + Random( -5, 5 ), p.hy - Random( 0, 12 ), fx_color( "plasma", 0, 1 ), Random( -30, 30 ), Random( -40, 0 ), 0.7, 80 ) end
	end )
	if not id then return end
	-- blobs of red sealing wax over it, the same every frame, and the seal pressed in the middle
	SetRandomSeed( id, 77 )
	local red = color_abgr_merge( 170, 25, 35, 255 )
	local dark = color_abgr_merge( 110, 10, 20, 255 )
	for i = 1, 14 do
		local bx, by = p.hx + Random( -5, 5 ), p.hy + 2 - Random( 0, 14 )
		fx_dot( bx, by, i % 3 == 0 and dark or red, 0, 0, 0.04 )
	end
	SetRandomSeed( age, id )
	local gold = color_abgr_merge( 255, 210, 110, 255 )
	for i = 0, 7 do
		local a = i / 8 * 2 * math.pi + age * 0.02
		fx_dot( p.hx + math.cos( a ) * 3, p.hy - 6 + math.sin( a ) * 3, gold, 0, 0, 0.04 )
	end
end

-- Sealed in a Water Cage (effects/water_cage.lua): the cage's water is real, so nothing is drawn round the creature
-- here. It is drawn through the air into the middle of the sphere (p.cx, p.cy; p.oy: its body's middle from its
-- feet) and floats there, breathing out bubbles, until the cage is gone.
local CAGE_DRAG = 2.5 -- pixels a frame

local function caged( e, p, age )
	if not EntityGetIsAlive( p.cage ) then p.frames = age end
	local dx, dy = p.cx - p.hx, p.cy - p.oy - p.hy
	local d = math.sqrt( dx * dx + dy * dy )
	if d > 0.01 then
		local step = math.min( d, CAGE_DRAG )
		p.hx, p.hy = p.hx + dx / d * step, p.hy + dy / d * step
		effect_set( e, "hx", p.hx )
		effect_set( e, "hy", p.hy )
	end
	local id = hold( e, p, age )
	if not id then return end
	if d <= 0.01 then EntitySetTransform( id, p.hx, p.hy + math.sin( age * 0.07 ) * 1.5 ) end
	if age % 5 == 0 then fx_dot( p.hx + Random( -3, 3 ), p.hy + p.oy - 2, fx_color( "water", 0.85, 0.9 ), Random( -4, 4 ), -28, 0.45 ) end
	return id
end

local function water( e, p, age )
	local id
	local cx, cy = p.hx, p.hy - 5
	if ( p.cage or 0 ) > 0 then
		id = caged( e, p, age )
		if not id then return end
		cx, cy = p.cx, p.cy
	else
		id = hold( e, p, age, function( id, p )
			fx_material( "water", p.hx, p.hy - 5, 70, 9, 0, 20 )
		end )
		if not id then return end
		local c = fx_color( "water", 0.2, 0.8 )
		for i = 0, 15 do
			local a = i / 16 * 2 * math.pi + age * 0.03
			fx_dot( cx + math.cos( a ) * 11, cy + math.sin( a ) * 11, c, 0, 0, 0.05 )
		end
		if age % 4 == 0 then fx_dot( cx + Random( -7, 7 ), cy + 8, fx_color( "water", 0.8 ), 0, -35, 0.4 ) end -- bubbles
	end
	if age % 20 == 0 then
		give_effect( id, MISC .. "effect_apply_wet.xml" )
		seal_damage( id, 0.12, "DAMAGE_DROWNING", p.caster, cx, cy )
	end
end

local function sand( e, p, age )
	local id = hold( e, p, age, function( id, p ) fx_material( "sand", p.hx, p.hy - 4, 40, 7 ) end )
	if not id then return end
	local c = fx_color( "sand", 0.1 )
	for i = 1, 5 do
		local t = Random( 0, 1000 ) / 1000
		local a = age * 0.25 + t * 9
		fx_dot( p.hx + math.cos( a ) * ( 10 - 4 * t ), p.hy + 3 - t * 18, c, 0, -10, 0.2 )
	end
end

-- Reduction: the creature is small and weak for a while; its sprites and hitboxes shrink and come back
local function shrunk( e, p, age )
	local id = effect_owner( p )
	if not id then
		EntityKill( e )
		return
	end
	local k = p.scale or 0.5
	local function scale( by )
		for _, sprite in ipairs( EntityGetComponentIncludingDisabled( id, "SpriteComponent" ) or {} ) do
			ComponentSetValue2( sprite, "has_special_scale", true )
			ComponentSetValue2( sprite, "special_scale_x", ComponentGetValue2( sprite, "special_scale_x" ) * by )
			ComponentSetValue2( sprite, "special_scale_y", ComponentGetValue2( sprite, "special_scale_y" ) * by )
		end
		for _, box in ipairs( EntityGetComponentIncludingDisabled( id, "HitboxComponent" ) or {} ) do
			for _, f in ipairs( { "aabb_min_x", "aabb_max_x", "aabb_min_y", "aabb_max_y" } ) do
				ComponentSetValue2( box, f, ComponentGetValue2( box, f ) * by )
			end
		end
	end
	if age == 0 then
		scale( k )
		give_effect( id, MISC .. "effect_weaken.xml", p.frames )
		give_effect( id, MISC .. "effect_movement_slower_2x.xml", p.frames )
		fx_burst( p.hx, p.hy - 5, fx_color( "flicker", 0.5 ), 20, 40, 0.5 )
	end
	if age >= p.frames then
		scale( 1 / k )
		local x, y = EntityGetTransform( id )
		fx_burst( x, y - 5, fx_color( "flicker", 0.5 ), 16, 50, 0.4 )
		EntityKill( e )
		return
	end
	if age % 10 == 0 then
		local x, y = EntityGetTransform( id )
		fx_dot( x + Random( -4, 4 ), y - Random( 0, 8 ), fx_color( "flicker", 0.6 ), 0, -15, 0.5 )
	end
end

-- Asleep on the Serpent's Bed of Sand: it lies still, and small z's rise from it
local function sleep( e, p, age )
	local id = hold( e, p, age )
	if not id then return end
	if age % 24 == 0 then
		local c = fx_color( "air", 0.9, 0.9 )
		local zx, zy = p.hx + 4 + ( age / 24 % 3 ) * 3, p.hy - 12 - ( age / 24 % 3 ) * 3
		for _, q in ipairs( { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 1, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 } } ) do
			fx_dot( zx + q[1], zy + q[2], c, 3, -9, 0.9 )
		end
	end
end

EFFECT_MODES.held = { ribbon = ribbon, time = clock, wax = wax, water = water, sand = sand, shrunk = shrunk, sleep = sleep }
