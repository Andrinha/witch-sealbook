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

-- Billow, Billow Cluster: a fluffy cloud to stand on; pressed in, it grows back. What is drawn round the sigil
-- shapes it (manifest.lua M.cloud): the element gives the cloud a temper - sand heaps up a cloud of sand, fire
-- embers that scorch what is beneath, water a rain that puts out fire, crystal and frost snow that freezes the
-- water around, lightning a storm that strikes down at what comes under it, light a lamp of a cloud, smoke wisps,
-- wind blowing through, flicker fireworks; Collection keeps the matter streaming in and the cloud heaps up one
-- billow at a time, its inverse scatters it into nothing, Expansion heaps up more billows from the start, Binding
-- holds whoever climbs onto it, the Spiraling Wind spins its streams round, Aeriforms blow it away, and Mimicry
-- makes it dissolve and flow together again where the cursor has gone.
local CLOUD_HEAP = {
	{ "main", 0, 0 }, { "l", -22, 2 }, { "l", 22, 2 }, { "m", -12, -4 }, { "m", 12, -4 }, { "s", 0, -8 },
}
local CLOUD_HALF_EXTRA, CLOUD_GATHER, CLOUD_REGROW, CLOUD_FLOW = 13, 480, 60, 40

-- the heap's piece kinds: the middle in the temper's own look, the puffs beside it in the same
local CLOUD_PUFFS = { cloud = "cloud_puff_", sand_cloud = "sand_puff_", ember_cloud = "ember_puff_",
	rain_cloud = "rain_puff_", frost_cloud = "frost_puff_", storm_cloud = "storm_puff_", glow_cloud = "glow_puff_" }
local function cloud_kinds( p )
	local main = p.piece or "cloud"
	local puff = CLOUD_PUFFS[main] or "cloud_puff_"
	local kinds = {}
	for i, q in ipairs( CLOUD_HEAP ) do kinds[i] = q[1] == "main" and main or puff .. q[1] end
	return kinds
end

local function cloud_plan( p, x, y, count )
	-- the plan holds absolute places (build.lua's build()), so what grows or grows back reads them as they are
	local kinds = cloud_kinds( p )
	local plan = {}
	for i = 1, math.min( count, #CLOUD_HEAP ) do
		plan_add( plan, kinds[i], x + CLOUD_HEAP[i][2], y + CLOUD_HEAP[i][3] )
	end
	return plan
end

-- how many billows Expansion heaps up round the middle (its inverse: one lone wide cloud)
local function cloud_count( p )
	local grow = p.grow or 1
	if grow < 1.1 then return 1 end
	if grow < 1.5 then return 3 end
	return 5
end

-- how wide the heap stands now: half the span of the billows its plan holds
local function cloud_half( p )
	local n = 0
	for _ in effect_text( p.plan ):gmatch( "([%w_]+)," ) do n = n + 1 end
	return 18 + CLOUD_HALF_EXTRA * ( math.max( 1, n ) - 1 ) / ( #CLOUD_HEAP - 1 )
end

-- the loose matter around, streaming into the cloud's middle
local function cloud_stream( p, x, y, wide )
	local element = ( p.temper or "plain" ) == "sand" and "sand" or ( p.element or "air" )
	for k = 1, 3 do
		local a = Random( 0, 628 ) / 100
		local r = Random( 25, 45 ) * wide
		local sx, sy = x + math.cos( a ) * r, y + math.sin( a ) * r * 0.7
		fx_dot( sx, sy, effect_color( element, 0.3 ), ( x - sx ) * 1.5, ( y - sy ) * 1.5 - 10, 0.45 )
	end
end

-- whoever is on the cloud now: standing, lying or riding it
local function cloud_riders( p, x, y, half )
	local out = {}
	for _, id in ipairs( creatures_in( x, y - 10, half + 12, p.owner, true ) ) do
		local cx, cy = EntityGetTransform( id )
		if math.abs( cx - x ) <= half and cy < y + 4 and cy > y - 24 then out[#out + 1] = id end
	end
	return out
end

-- the temper's own show: what the cloud of that element sheds, and what it does to what is beneath it
local function cloud_temper( p, age, x, y )
	local temper = p.temper or "plain"
	local half = cloud_half( p )
	if temper == "plain" or temper == "sand" then
		-- a soft sparkle over its top
		fx_dot( x + Random( -18, 18 ), y + Random( -8, 4 ), effect_color( temper == "sand" and "sand" or "air", 0.8, 0.7 ), Random( -4, 4 ), -3, 1 )
	elseif temper == "ember" then
		-- embers drop from its underside; whoever lies on it or beneath it smolders
		fx_dot( x + Random( -half, half ), y + 6, fx_color( "fire", 0.7 ), Random( -5, 5 ), Random( 10, 30 ), 0.7, 50 )
		if age % 20 == 0 then
			for _, id in ipairs( cloud_riders( p, x, y, half ) ) do
				seal_damage( id, 0.04 * ( p.power or 1 ), "DAMAGE_FIRE", p.owner, EntityGetTransform( id ) )
				give_effect( id, MISC .. "effect_apply_on_fire.xml", 90 )
			end
		end
		if age % 30 == 0 then
			for _, id in ipairs( creatures_in( x, y + 12, half + 10, 0, true ) ) do
				local cx, cy = EntityGetTransform( id )
				if cy > y - 4 then seal_damage( id, 0.04 * ( p.power or 1 ), "DAMAGE_FIRE", p.owner, cx, cy ) end
			end
		end
	elseif temper == "rain" then
		-- droplets fall - real water, that puts out fire on whoever is under it and on it
		fx_dot( x + Random( -half, half ), y + 7, fx_color( "water", 0.5 ), Random( -3, 3 ), Random( 20, 40 ), 0.7, 90 )
		if age % 8 == 0 then GameCreateParticle( "water", x + Random( -half, half ), y + 7, 1, 0, 30, false, false, true ) end
		if age % 30 == 0 then
			for _, id in ipairs( cloud_riders( p, x, y, half ) ) do clear_effects( id, { "ON_FIRE" } ) end
			for _, id in ipairs( creatures_in( x, y + 12, half + 10, 0, true ) ) do
				local cx, cy = EntityGetTransform( id )
				if cy > y - 4 then clear_effects( id, { "ON_FIRE" } ) end
			end
		end
	elseif temper == "snow" then
		-- snow drifts down, and the water round the cloud freezes (the converter set up when it gathered)
		fx_dot( x + Random( -half, half ), y + 6, fx_color( "frost", 0.7 ), Random( -3, 3 ), Random( 6, 14 ), 0.9, 15 )
		if age % 12 == 0 then GameCreateParticle( "snow", x + Random( -half, half ), y + 7, 1, 0, 10, false, false, true ) end
	elseif temper == "storm" then
		-- sparks crackle under it; now and then it strikes down at what has come under it
		fx_dot( x + Random( -half, half ), y + Random( 2, 8 ), fx_color( "thunder", 0.8 ), Random( -20, 20 ), Random( 10, 40 ), 0.3 )
		if age % 90 == 30 then
			local victim = nearest_creature( x, y + 16, 80, p.owner )
			if victim then
				local cx, cy = EntityGetTransform( victim )
				fx_line( x + Random( -8, 8 ), y + 6, cx, cy - 6, fx_color( "thunder", 1 ), 3, 0.35, 3 )
				seal_damage( victim, 0.25 * ( p.power or 1 ), "DAMAGE_ELECTRICITY", p.owner, cx, cy )
			end
		end
	elseif temper == "glow" then
		-- a lamp of a cloud: bright motes rise from it
		fx_dot( x + Random( -half, half ), y + Random( -6, 2 ), fx_color( "light", 0.9 ), Random( -3, 3 ), Random( -10, -4 ), 0.8 )
	elseif temper == "wisp" then
		-- wisps shed off its top and drift away
		fx_dot( x + Random( -half, half ), y - Random( 0, 6 ), effect_color( p.element or "smoke", 0.4, 0.6 ), Random( -6, 6 ), -Random( 6, 16 ), 0.9 )
	elseif temper == "wind" then
		-- a gust blows through it, off the top of the cloud
		fx_dot( x - half - 8, y + Random( -10, 6 ), fx_color( "wind", 0.7, 0.6 ), Random( 60, 90 ), Random( -5, 5 ), 0.8 )
	elseif temper == "sparkle" then
		-- fireworks pop round it in its element's colors
		local a = Random( 0, 628 ) / 100
		fx_dot( x + math.cos( a ) * Random( 4, half ), y + math.sin( a ) * Random( 2, 8 ),
			effect_color( p.element or "flicker", Random( 300, 900 ) / 1000, 0.9 ), 0, -Random( 10, 30 ), 0.7 )
	end
end

MODES.cloud = function( e, p, age, x, y )
	-- the signs that undo it: the cloud's matter streams away and nothing gathers (the inverted Collection, and
	-- Aeriforms' gust that carries it off the way the caster threw it)
	if ( p.scatter or 0 ) > 0 or ( p.gust or 0 ) > 0 then
		local dx, dy = 0, 0
		if ( p.gust or 0 ) > 0 then
			local owner = effect_owner( p )
			local ox, oy = 0, -40
			if owner then ox, oy = EntityGetTransform( owner ) end
			local d = math.max( 1, math.sqrt( ( x - ox ) ^ 2 + ( y - oy ) ^ 2 ) )
			dx, dy = ( x - ox ) / d, ( y - oy ) / d
		end
		for k = 1, 3 do
			local a = ( p.gust or 0 ) > 0 and math.atan2( dy, dx ) or Random( 0, 628 ) / 100
			local r = 14 + age
			fx_dot( x + math.cos( a ) * r, y + math.sin( a ) * r * 0.5, effect_color( p.element or "air", 0.3 ),
				math.cos( a ) * 30 + dx * 70, math.sin( a ) * 15 + dy * 70, 0.5 )
		end
		if age == 40 then fx_ring( x, y, 20, effect_color( p.element or "air", 0.5, 0.7 ), 16, 60, 0.4 ) end
		if age > 40 then EntityKill( e ) end
		return
	end
	if age == 0 then
		planned( e, p, cloud_plan( p, x, y, cloud_count( p ) ) )
		p.flow = CLOUD_FLOW
		effect_set( e, "flow", p.flow )
		if p.temper == "glow" then effect_glow( e, 255, 235, 150, 70, 0.5 )
		elseif p.temper == "ember" then effect_glow( e, 255, 130, 40, 55, 0.4 ) end
		-- the air round a snow cloud freezes the water in it
		if p.temper == "snow" then convert_around( e, FREEZES.from, FREEZES.to, 40, 3 ) end
	end
	if done( e, p, age ) then return end
	-- Mimicry: the cloud dissolves, and flows together again where the cursor has gone
	local flow = math.floor( p.flow or 0 )
	if p.mimic == 1 and flow == 0 and age % 6 == 0 then
		local owner = effect_owner( p )
		local controls = owner and EntityGetFirstComponent( owner, "ControlsComponent" )
		if controls then
			local mx, my = ComponentGetValue2( controls, "mMousePosition" )
			if ( mx - x ) ^ 2 + ( my - y ) ^ 2 > 60 * 60 then
				local n = 0
				for _ in effect_text( p.plan ):gmatch( "([%w_]+),(-?%d+),(-?%d+)" ) do n = n + 1 end
				for kind, px, py in effect_text( p.plan ):gmatch( "([%w_]+),(-?%d+),(-?%d+)" ) do
					for _, id in ipairs( EntityGetInRadiusWithTag( tonumber( px ), tonumber( py ), 3, "witch_solid" ) or {} ) do EntityKill( id ) end
					fx_burst( tonumber( px ), tonumber( py ), effect_color( p.element or "air", 0.5, 0.6 ), 6, 25, 0.4 )
				end
				EntitySetTransform( e, mx, my )
				x, y = mx, my
				-- the heap it had gathered flows together again, whole, at the cursor's new place
				planned( e, p, cloud_plan( p, x, y, n ) )
				flow, p.built = CLOUD_FLOW, 0
				p.flow = flow
				effect_set( e, "flow", flow )
				effect_set( e, "built", 0 )
			end
		end
	end
	-- the matter gathers: streams first, then the billows heap up, the middle one first
	local finished = false
	if flow > 0 then
		cloud_stream( p, x, y, 1 )
		p.flow = flow - 1
		effect_set( e, "flow", p.flow )
	else
		finished = build( e, p, age, 1, 2 )
		-- Collection: the streams keep coming, and now and then the cloud heaps up another billow
		if ( p.gather or 0 ) > 0 then
			if age % 5 == 0 then cloud_stream( p, x, y, 1.6 ) end
			if finished and age % math.floor( CLOUD_GATHER / math.max( 0.7, p.gather ) ) == 0 then
				local plan, n = effect_text( p.plan ), 0
				for _ in plan:gmatch( "([%w_]+),(-?%d+),(-?%d+)" ) do n = n + 1 end
				if n < #CLOUD_HEAP then
					local kind = cloud_kinds( p )[n + 1]
					local q = CLOUD_HEAP[n + 1]
					plan = plan .. ";" .. string.format( "%s,%d,%d", kind, x + q[2], y + q[3] )
					effect_set( e, "plan", plan )
					p.plan = plan
					-- the new billow pops in at once, a puff out of the gathered matter
					solid_piece( kind, x + q[2], y + q[3], math.max( 30, p.frames - age ) )
					p.built = n + 1
					effect_set( e, "built", p.built )
					fx_burst( x + q[2], y + q[3], effect_color( p.element or "air", 0.4, 0.8 ), 10, 25, 0.5 )
				end
			end
		end
	end
	-- a billow that is dug or blown away grows again; Strengthening brings it back sooner
	if finished and age % ( ( p.strong or 0 ) > 0 and 20 or CLOUD_REGROW ) == 0 then
		for kind, px, py in effect_text( p.plan ):gmatch( "([%w_]+),(-?%d+),(-?%d+)" ) do
			if #( EntityGetInRadiusWithTag( tonumber( px ), tonumber( py ), 3, "witch_solid" ) or {} ) == 0 then
				solid_piece( kind, tonumber( px ), tonumber( py ), math.max( 30, p.frames - age ) )
				fx_burst( tonumber( px ), tonumber( py ), effect_color( p.element or "air", 0.5, 0.7 ), 8, 25, 0.4 )
			end
		end
	end
	-- the temper's show: rain, embers, snow, bolts, wisps, glow
	if flow == 0 and age % 4 == 0 then cloud_temper( p, age, x, y ) end
	-- the Spiraling Wind: sparks circle the cloud as it stands, as its streams did while it gathered
	if ( p.whirl or 0 ) > 0 and age % 2 == 0 then
		local a = age * 0.12
		for k = 0, 2 do
			local t = a + k * 2.1
			fx_dot( x + math.cos( t ) * ( cloud_half( p ) + 5 ), y + math.sin( t ) * 6, effect_color( p.element or "air", 0.5, 0.7 ), -math.sin( t ) * 30, math.cos( t ) * 8, 0.4 )
		end
	end
	-- Binding: whoever climbs onto the cloud is held on it, as if time had stopped for them there
	if ( p.hold or 0 ) > 0 and age % 12 == 0 then
		for _, id in ipairs( creatures_in( x, y - 10, cloud_half( p ) + 12, p.owner, true ) ) do
			local cx, cy = EntityGetTransform( id )
			if math.abs( cx - x ) <= cloud_half( p ) and cy < y + 4 and cy > y - 24 then
				hold_creature( id, 24, "time", p.element or "light", p.owner )
			end
		end
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
	if age == 0 then effect_sound( "grow", x, y ) end
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
