-- Solid magic built piece by piece (manifest.lua): a stone wall rising from the ground, a pillar that lifts the
-- caster, an arched bridge, a ribbon stretched to the cursor, an icy road, a cage of sand, a cloud to stand on, a
-- disc of water, a sand castle, a stone arm. Pieces are static bodies (entities/solid/*.xml, tools/make_gfx.py);
-- each crumbles when its time is up, in the order it was built. The plan is "kind,x,y;..." in p.plan.

local MODES = {}

local SPARK = { stone = "stone", sand = "sand", ice = "ice", crystal = "crystal", water = "water", cloud = "air", light = "light" }

local function plan_add( plan, kind, x, y )
	plan[#plan + 1] = string.format( "%s,%d,%d", kind, math.floor( x + 0.5 ), math.floor( y + 0.5 ) )
end

-- builds the plan: 'per_step' pieces every 'interval' frames; returns true once everything is built
local function build( e, p, age, per_step, interval )
	local built = math.floor( p.built or 0 )
	local pieces = {}
	for kind, x, y in effect_text( p.plan ):gmatch( "([%w_]+),(-?%d+),(-?%d+)" ) do pieces[#pieces + 1] = { kind, tonumber( x ), tonumber( y ) } end
	if built >= #pieces then return true end
	if age % ( interval or 1 ) ~= 0 then return false end
	for i = built + 1, math.min( #pieces, built + ( per_step or 1 ) ) do
		local q = pieces[i]
		solid_piece( q[1], q[2], q[3], math.max( 30, p.frames - age + i * 2 ) )
		local look = q[1]:match( "^(%a+)_" ) or q[1]
		local c = effect_color( SPARK[look] or "earth", 0.5 )
		for k = 1, 5 do fx_dot( q[2] + Random( -4, 4 ), q[3] + Random( -3, 3 ), c, Random( -20, 20 ), Random( -30, 0 ), 0.4 ) end
		built = i
	end
	effect_set( e, "built", built )
	return built >= #pieces
end

local done = effect_done

local function planned( e, p, plan )
	p.plan = table.concat( plan, ";" )
	effect_set( e, "plan", p.plan )
	effect_sound( "grow", EntityGetTransform( e ) )
end

-- the planks a ribbon, bridge or road of the element is made of
local function plank_for( element )
	if element == "crystal" or element == "frost" or element == "shimmer" then return "crystal_plank" end
	if element == "water" or element == "ice" or element == "storm" then return "ice_plank" end
	if element == "light" or element == "beam" or element == "sunfire" or element == "flicker" or element == "fireworks" then return "light_plank" end
	if element == "sand" or element == "sandstorm" then return "sand_plank" end
	return "stone_plank"
end

-- Wall Bend: the ground in front of the caster is drawn up into a wall of brickwork that bends back over them, as
-- in the manga - cover from what comes at them and from above. Courses of a brick and a half brick, their joints
-- staggered; each course leans a little further back than the one under it.
MODES.wall = function( e, p, age, x, y )
	if age == 0 then
		local dir = ( p.dx or 1 ) >= 0 and 1 or -1
		-- It is the ground drawn up, so it needs ground under its foot: 18 pixels ahead of the caster, or a
		-- little nearer at an edge. Over a drop, in the air or with rock where it would stand, nothing rises.
		local wx, gy
		for _, ahead in ipairs( { 18, 14 } ) do
			local tx = math.floor( x + dir * ahead + 0.5 )
			local _, ty = ground_below( tx, y - 10, 60 )
			if ty and ty > y - 9 then
				wx, gy = tx, math.floor( ty + 0.5 )
				break
			end
		end
		if not wx then
			GamePrint( "Wall Bend: there is no ground here to draw up" )
			fx_burst( x + dir * 18, y + 4, fx_color( "stone", 0.3 ), 8, 25, 0.4, 60 )
			EntityKill( e )
			return
		end
		local plan = {}
		local courses = math.floor( ( 7 + 2 * ( p.power or 1 ) ) * 1.5 )
		for k = 0, courses - 1 do
			local t = k / ( courses - 1 )
			local left = wx - 6 - dir * math.floor( courses * t * t + 0.5 )
			local cy = gy - 2 - k * 4
			if k % 2 == 0 then
				plan_add( plan, "stone_brick", left + 4, cy ); plan_add( plan, "stone_brick_half", left + 10, cy )
			else
				plan_add( plan, "stone_brick_half", left + 2, cy ); plan_add( plan, "stone_brick", left + 8, cy )
			end
		end
		planned( e, p, plan )
		-- the ground gives it up: a puff of dust at its foot
		fx_burst( wx, gy - 2, fx_color( "stone", 0.3 ), 14, 40, 0.5, 60 )
	end
	if done( e, p, age ) then return end
	build( e, p, age, 2, 3 )
end

-- Earth Lift: the ground under the caster rises in a pillar that carries them up
MODES.lift = function( e, p, age, x, y )
	local owner = effect_owner( p )
	if not owner or done( e, p, age ) then
		if not owner then EntityKill( e ) end
		return
	end
	local ox, oy = EntityGetTransform( owner )
	local top = p.top
	if age == 0 or not top then
		local gx, gy = ground_below( x, y - 6, 40 )
		top = gy or ( oy + 5 )
		effect_set( e, "top", top )
		effect_set( e, "hops", 0 )
	end
	local hops = math.floor( p.hops or 0 )
	-- the pillar stays where it began; the caster rides it only while above it
	if math.abs( ox - x ) > 8 or hops > ( p.steps or 6 ) then
		if age > 30 and hops > ( p.steps or 6 ) then
			effect_set( e, "frames", 0 )
			EntityKill( e )
		end
		return
	end
	if age % 14 == 0 then
		push_creature( owner, 0, -100, true )
		effect_set( e, "hops", hops + 1 )
		fx_material( "sand", x, top - 2, 6, 5, 0, -30 )
	end
	-- fill from the pillar's top up to just under the caster's feet
	local feet = oy + 5
	local count = 0
	while top - 4 >= feet and count < 2 do
		top = top - 4
		solid_piece( "stone_slab", x, top + 2, p.life )
		count = count + 1
	end
	effect_set( e, "top", top )
	if age % 2 == 0 then fx_dot( x + Random( -6, 6 ), top, fx_color( "earth", 0.4 ), Random( -20, 20 ), -20, 0.4 ) end
end

-- Sand Bridge, the Sigil of Bridging: an arched bridge rises towards where the caster aimed and sets hard
MODES.bridge = function( e, p, age, x, y )
	if age == 0 then
		local dir = ( p.dx or 1 ) >= 0 and 1 or -1
		local len = p.len or 100
		local ax, ay = x, y + 5
		local bx = ax + dir * len
		local gx, gy = ground_below( bx, ay - 30, 80 )
		local by = gy and math.min( gy, ay + 30 ) or ay
		local h = len * 0.22
		local plan = {}
		local n = math.floor( len / 7 )
		for i = 1, n do
			local t = i / n
			local px = ax + ( bx - ax ) * t
			local py = ay + ( by - ay ) * t - h * math.sin( t * math.pi )
			plan_add( plan, p.piece or "sand_plank", px, py )
		end
		planned( e, p, plan )
	end
	if done( e, p, age ) then return end
	build( e, p, age, 1, 2 )
end

-- The Weave frame (Boulder Stretch, Crystal Ribbon): a flexible ribbon stretches from the caster to the cursor
MODES.ribbon = function( e, p, age, x, y )
	if age == 0 then
		local ax, ay = x, y + 5
		local bx, by = p.tx, p.ty
		local dx = bx - ax
		local len = math.sqrt( dx * dx + ( by - ay ) ^ 2 )
		local n = math.max( 2, math.floor( len / 7 ) )
		local sag = math.abs( dx ) * 0.12
		local plan = {}
		local piece = plank_for( p.element )
		for i = 1, n do
			local t = i / n
			plan_add( plan, piece, ax + dx * t, ay + ( by - ay ) * t + sag * math.sin( t * math.pi ) )
		end
		planned( e, p, plan )
	end
	if done( e, p, age ) then return end
	if build( e, p, age, 2, 2 ) and p.element == "crystal" and age % 3 == 0 then
		-- the crystal shimmers in all colors
		local t = Random( 0, 1000 ) / 1000
		local c = color_abgr_merge( Random( 150, 255 ), Random( 150, 255 ), Random( 150, 255 ), 255 )
		local dx = p.tx - x
		fx_dot( x + dx * t, y + 4 + ( p.ty - y - 5 ) * t + math.abs( dx ) * 0.12 * math.sin( t * math.pi ), c, 0, -5, 0.4 )
	end
end

-- Icy Road, Frozen Path: the air ahead freezes into a road of ice from the caster's feet towards the cursor; water on
-- the way freezes
MODES.road = function( e, p, age, x, y )
	if age == 0 then
		local dx, dy = p.tx - x, p.ty - ( y + 5 )
		local len = math.min( p.len or 120, math.sqrt( dx * dx + dy * dy ) )
		local d = math.max( 1, math.sqrt( dx * dx + dy * dy ) )
		dx, dy = dx / d, dy / d
		-- a road can't be steep: at most one step up in two
		if math.abs( dy ) > 0.45 then
			local s = dy > 0 and 1 or -1
			dy = 0.45 * s
			dx = ( dx >= 0 and 1 or -1 ) * math.sqrt( 1 - dy * dy )
		end
		local plan = {}
		for i = 1, math.floor( len / 7 ) do
			plan_add( plan, "ice_plank", x + dx * i * 7, y + 6 + dy * i * 7 )
		end
		planned( e, p, plan )
		effect_set( e, "dx", dx )
		effect_set( e, "dy", dy )
		convert_around( e, FREEZES.from, FREEZES.to, 8, 3 )
	end
	if done( e, p, age ) then return end
	local finished = build( e, p, age, 1, 2 )
	-- the freezing front runs along the road
	local built = math.floor( p.built or 0 )
	local fx, fy = p.x0 + ( p.dx or 1 ) * built * 7, p.y0 + 6 + ( p.dy or 0 ) * built * 7
	if not finished then
		EntitySetTransform( e, fx, fy )
		for k = 1, 3 do fx_dot( fx + Random( -3, 3 ), fy + Random( -3, 2 ), fx_color( "ice", 0.7 ), Random( -15, 15 ), Random( -20, 5 ), 0.5 ) end
	elseif age % 6 == 0 then
		local t = Random( 0, built * 7 )
		fx_dot( p.x0 + ( p.dx or 1 ) * t, p.y0 + 4 + ( p.dy or 0 ) * t, fx_color( "ice", 0.9 ), 0, -4, 0.6 )
	end
end

-- Sand Cage: thick panels of sand rise in a spiral round the enemy and set hard, as in the manga. The cage's sides
-- are slanted panels that overlap up a teardrop's outline to a point over the enemy's head: these are solid. The
-- panels that cross in front are a picture only (gfx/sand_cage_bands_*.png), shown as far up as the sides stand,
-- so the caged one is not walled into stone. The outline's numbers are tools/make_gfx.py's.
-- The picture is a sprite of the effect's own with a z in front of creatures: the caged one is seen through the
-- gaps between the bands, behind them. (GameCreateSpriteForXFrames has no z and draws behind creatures.)
local CAGE = { r = 16, h = 52, bottom = 17, panels = 14 }
local function cage_half_width( s )
	if s < 0.3 then return CAGE.r * math.sqrt( math.max( 0, 1 - ( ( s - 0.3 ) / 0.3 ) ^ 2 ) ) end
	return CAGE.r * ( 1 - ( ( s - 0.3 ) / 0.7 ) ^ 1.7 )
end

-- Shows the bands as far up as 'shown' thirds of the cage (0: none yet). The image is 34 x 54; the pixel at its
-- offset lies on the cage's middle, which puts its last row just under the lowest panel.
local function cage_bands( e, cx, cy, shown )
	local path = "mods/witch_notebook/files/gfx/sand_cage_bands_" .. math.max( 1, shown ) .. ".png"
	local sprite = ( EntityGetComponentIncludingDisabled( e, "SpriteComponent", "witch_cage_bands" ) or {} )[1]
	if not sprite then
		EntitySetTransform( e, cx, cy )
		EntityAddComponent2( e, "SpriteComponent", { _tags = "witch_cage_bands", image_file = path,
			offset_x = CAGE.r + 1, offset_y = CAGE.h - CAGE.bottom, z_index = -1, visible = shown > 0,
			update_transform = true, update_transform_rotation = false } )
		return
	end
	if ComponentGetValue2( sprite, "image_file" ) ~= path or ComponentGetValue2( sprite, "visible" ) ~= ( shown > 0 ) then
		ComponentSetValue2( sprite, "image_file", path )
		ComponentSetValue2( sprite, "visible", shown > 0 )
		EntityRefreshSprite( e, sprite )
	end
end

MODES.cage = function( e, p, age, x, y )
	if age == 0 then
		local target = nearest_creature( x, y, 40, p.owner )
		local cx, cy = x, y
		if target then
			cx, cy = EntityGetTransform( target )
			cy = cy - 4
			hold_creature( target, 90, "sand", "sand", p.owner )
		end
		cx, cy = math.floor( cx + 0.5 ), math.floor( cy + 0.5 )
		local plan = {}
		-- from the bottom up, a panel on either side by turns: the cage winds up round the enemy
		for i = 0, CAGE.panels - 1 do
			local s = i / ( CAGE.panels - 1 )
			local half = cage_half_width( s )
			plan_add( plan, "sand_panel", cx + ( i % 2 == 0 and -half or half ), cy + CAGE.bottom - s * CAGE.h )
			if half >= 1.5 then plan_add( plan, "sand_panel", cx + ( i % 2 == 0 and half or -half ), cy + CAGE.bottom - s * CAGE.h ) end
		end
		planned( e, p, plan )
		effect_set( e, "cx", cx )
		effect_set( e, "cy", cy )
		effect_set( e, "total", #plan )
		p.cx, p.cy, p.total = cx, cy, #plan
	end
	if done( e, p, age ) then return end
	local cx, cy = p.cx or x, p.cy or y
	local finished = build( e, p, age, 1, 2 )
	local built, total = math.floor( p.built or 0 ), p.total or 2 * CAGE.panels - 2
	-- the bands in front, a third of the cage at a time
	cage_bands( e, cx, cy, math.min( 3, math.floor( built / total * 3 + 0.001 ) ) )
	if not finished then
		-- sand whirls up round the cage as it rises
		local a = age * 0.3
		local s = built / total
		for k = 1, 3 do
			local half = cage_half_width( s ) + 3
			fx_dot( cx + math.cos( a + k * 2.1 ) * half, cy + CAGE.bottom - s * CAGE.h, fx_color( "sand", 0.2 ), -math.sin( a + k * 2.1 ) * 40, -25, 0.3 )
		end
	end
end

-- Billow, Billow Cluster, Serpent's Bed: a fluffy cloud to stand on; pressed in, it grows back
MODES.cloud = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	local kind = p.piece or "cloud"
	local piece = math.floor( ( p.piece_id or 0 ) + 0.5 )
	if age < 30 then
		-- the loose stuff around gathers into it
		for k = 1, 4 do
			local a = Random( 0, 628 ) / 100
			local r = Random( 25, 45 )
			fx_dot( x + math.cos( a ) * r, y + math.sin( a ) * r, effect_color( kind == "cloud" and "air" or "sand", 0.3 ), -math.cos( a ) * r * 2, -math.sin( a ) * r * 2, 0.5 )
		end
	elseif piece == 0 or ( not EntityGetIsAlive( piece ) and age % 60 == 0 ) then
		effect_set( e, "piece_id", solid_piece( kind, x, y, p.frames - age ) )
		fx_burst( x, y, effect_color( kind == "cloud" and "air" or "sand", 0.5 ), 20, 30, 0.6 )
	end
	if age % 5 == 0 then
		fx_dot( x + Random( -18, 18 ), y + Random( -6, 6 ), effect_color( kind == "cloud" and "air" or "sand", 0.8, 0.7 ), Random( -4, 4 ), -3, 1 )
	end
end

-- Serpent's Bed of Sand: a great soft cloud of sand, after the manga. Sand streams up out of the ground and heaps
-- into billows, from the middle outwards; one can stand and lie on them. Whatever happens to the cloud it comes back
-- to its shape - a billow that is dug or blown away grows again - and a beast that settles on it is so comfortable
-- that it falls asleep, as the dragon did. It rests on the ground under the cursor, or hangs where it was cast.
local BED = {
	{ "sand_puff_l", 0, 3 }, { "sand_puff_l", -13, 4 }, { "sand_puff_l", 13, 4 }, { "sand_puff_m", -7, -5 }, { "sand_puff_m", 7, -5 },
	{ "sand_puff_l", -25, 5 }, { "sand_puff_l", 25, 5 }, { "sand_puff_m", -19, -3 }, { "sand_puff_m", 19, -3 },
	{ "sand_puff_s", -33, 7 }, { "sand_puff_s", 33, 7 }, { "sand_puff_s", 0, -10 },
}
local BED_GATHER, BED_HALF, BED_SLEEP = 24, 36, 360 -- frames the sand gathers; half the bed's width; frames of sleep

MODES.bed = function( e, p, age, x, y )
	if age == 0 then
		local gx, gy = ground_below( x, y - 10, 70 )
		x, y = math.floor( x + 0.5 ), math.floor( ( gy and gy - 11 or y ) + 0.5 )
		EntitySetTransform( e, x, y )
		local plan = {}
		for _, q in ipairs( BED ) do plan_add( plan, q[1], x + q[2], y + q[3] ) end
		planned( e, p, plan )
		effect_set( e, "grounded", gy and 1 or 0 )
		p.grounded = gy and 1 or 0
	end
	if done( e, p, age ) then return end
	if age < BED_GATHER + #BED * 2 then
		-- fine sand is drawn up out of the ground (or in from the air around) into the cloud
		for k = 1, 4 do
			local sx = x + Random( -BED_HALF, BED_HALF )
			local sy = p.grounded == 1 and y + 11 or y + Random( -30, 30 )
			fx_dot( sx, sy, fx_color( "sand", 0.3, 0.9 ), ( x - sx ) * 1.5, ( y - sy ) * 1.5 - 20, 0.45 )
		end
	end
	if age < BED_GATHER then return end
	local finished = build( e, p, age, 1, 2 )
	if not finished then return end
	-- it always comes back to its shape: a billow that is gone grows again
	if age % 60 == 0 then
		for _, q in ipairs( BED ) do
			if #( EntityGetInRadiusWithTag( x + q[2], y + q[3], 3, "witch_solid" ) or {} ) == 0 then
				solid_piece( q[1], x + q[2], y + q[3], math.max( 30, p.frames - age ) )
				fx_burst( x + q[2], y + q[3], fx_color( "sand", 0.4 ), 10, 25, 0.4 )
			end
		end
	end
	if age % 10 ~= 0 then return end
	-- whoever lies on it sinks in a little: sand puffs up round them; a beast soon sleeps (once on each bed)
	for _, id in ipairs( creatures_in( x, y - 10, BED_HALF + 14, 0, true ) ) do
		local cx, cy = EntityGetTransform( id )
		if math.abs( cx - x ) <= BED_HALF and cy < y + 2 and cy > y - 28 then
			fx_dot( cx + Random( -5, 5 ), cy + 6, fx_color( "sand", 0.5, 0.7 ), Random( -8, 8 ), -10, 0.5, 30 )
			if id ~= effect_owner( p ) and not EntityHasTag( id, "player_unit" ) and p["slept_" .. id] ~= 1 then
				local rested = ( p["rest_" .. id] or 0 ) + 1
				effect_set( e, "rest_" .. id, rested )
				if rested >= 6 then
					hold_creature( id, BED_SLEEP, "sleep", "sand", p.owner )
					effect_set( e, "slept_" .. id, 1 )
				end
			end
		end
	end
end

-- Everflow: a thin disc of water stands in the air to stand on, slowly turning
MODES.disc = function( e, p, age, x, y )
	if age == 0 then solid_piece( "water_disc", x, y, p.frames ) end
	if done( e, p, age ) then return end
	local c = fx_color( "water", 0.4, 0.8 )
	for k = 0, 3 do
		local a = age * 0.05 + k / 4 * 2 * math.pi
		fx_dot( x + math.cos( a ) * 14, y + math.sin( a ) * 3, c, 0, 0, 0.1 )
	end
	if age % 12 == 0 then GameCreateParticle( "water", x + Random( -12, 12 ), y + 3, 1, 0, 0, false, false, true ) end
end

-- Playland of Sand: a sand castle with towers and arches grows out of the ground
MODES.castle = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	if age < 40 then
		for k = 1, 4 do
			local a = age * 0.3 + k * 1.6
			local h = Random( 0, 36 )
			fx_dot( x + math.cos( a ) * ( 26 - h * 0.3 ), y - h, fx_color( "sand", 0.3 ), -math.sin( a ) * 30, -10, 0.3 )
		end
	elseif age == 40 then
		local gx, gy = ground_below( x, y - 20, 80 )
		solid_piece( "sand_castle", x, ( gy or y ) - 18, p.frames - age )
		fx_material( "sand", x, ( gy or y ) - 18, 30, 20 )
		effect_sound( "earth", x, y )
	end
end

-- Replication: a hand of stone grows out of the rock by the cursor, reaching the way the caster aims
MODES.arm = function( e, p, age, x, y )
	if age == 0 then
		local dx, dy = p.dx or 1, p.dy or 0
		-- rooted in the nearest rock: look back towards the caster, then down
		local ax, ay, hit = ground_along( x, y, -dx, -dy, 40 )
		if not hit then
			local gx, gy = ground_below( x, y, 60 )
			ax, ay = x, gy or y
		end
		local plan = {}
		for k = 1, 6 do plan_add( plan, "stone_block", ax + dx * k * 5, ay + dy * k * 5 ) end
		plan_add( plan, "stone_hand", ax + dx * 38, ay + dy * 38 )
		planned( e, p, plan )
	end
	if done( e, p, age ) then return end
	build( e, p, age, 1, 4 )
end

EFFECT_MODES.build = MODES
