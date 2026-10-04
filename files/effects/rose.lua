-- Water Rose: a flower of water grows where it was cast, the way the game's roots grow (root_grower.xml): a pen
-- wanders up from the nearest surface and leaves real cells behind it. Here the cells are water that stands still
-- (materials.xml witch_still_water), and the pen goes on to draw two leaves and, at the top, a rose: its heart and
-- three rings of petals. While it stands, drops of water fall from its petals and leaves. When the spell's time is
-- up the rose turns into ordinary water and falls.
-- The pen is a child entity with the roots' emitter (entities/rose_pen.xml). It emits once a frame where it is, so
-- it must not move more than about a pixel and a half a frame, and is switched off while it jumps.

local PEN = "mods/witch_notebook/files/entities/rose_pen.xml"
local WATER = "witch_still_water"
local STEP = 1.2   -- pixels the stem grows a frame
local STEM, LEAF, HEAD, STAND, MELT = 0, 1, 2, 3, 4

-- A leaf: out along one edge to the tip and back along the other; x along its axis, y across it.
local LEAF_PATH = {}
for i = 0, 21 do
	local t = i / 21
	local u = 1 - math.abs( 2 * t - 1 )
	-- widest nearer the tip, and closed there: the two edges meet, so the pen's line does not break
	LEAF_PATH[#LEAF_PATH + 1] = { u * 11, math.sin( u ^ 0.8 * math.pi ) * 2.4 * ( t < 0.5 and 1 or -1 ) }
end

-- The rose, around its middle: the heart's small spiral first, then three rings of cupped petals, each ring
-- wider and turned against the last, so it opens outwards as it is drawn. { x, y, lift the pen before it }
local HEAD_PATH, HEAD_DRIPS = {}, {}
for i = 0, 17 do
	local a = i / 17 * 7
	local r = 0.3 + 0.26 * a
	HEAD_PATH[#HEAD_PATH + 1] = { r * math.cos( a ), r * math.sin( a ), i == 0 }
end
for _, ring in ipairs( { { 4.2, 3, 0.2 }, { 7.4, 4, 0.9 }, { 11, 5, 0.3 } } ) do
	local radius, petals, turn = ring[1], ring[2], ring[3]
	local span = 2 * math.pi / petals * 1.3 -- a petal overlaps its neighbors
	local n = math.max( 4, math.floor( radius * span / 1.3 ) )
	for petal = 0, petals - 1 do
		for i = 0, n do
			local u = i / n
			local a = turn + petal * 2 * math.pi / petals + ( u - 0.5 ) * span
			local r = radius * ( 0.86 + 0.2 * math.sin( u * math.pi ) )
			HEAD_PATH[#HEAD_PATH + 1] = { r * math.cos( a ), r * math.sin( a ) * 0.95, i == 0 }
			-- Drops gather under the outermost petals: two pixels below their lower edge, in the open air.
			if radius == 11 and r * math.sin( a ) > 4 then
				HEAD_DRIPS[#HEAD_DRIPS + 1] = { r * math.cos( a ), r * math.sin( a ) * 0.95 + 2 }
			end
		end
	end
end
local DRIP_EVERY = 20 -- frames between drops: three a second
local HEAD_RADIUS, HEAD_LIFT = 13, 10

local function pen_of( e, x, y )
	for _, child in ipairs( EntityGetAllChildren( e ) or {} ) do
		if EntityHasTag( child, "witch_rose_pen" ) then
			return child, EntityGetFirstComponentIncludingDisabled( child, "ParticleEmitterComponent" )
		end
	end
	local child = EntityLoad( PEN, x, y )
	EntityAddChild( e, child )
	return child, EntityGetFirstComponentIncludingDisabled( child, "ParticleEmitterComponent" )
end

-- Put the pen at x, y with a brush of 'brush' pixels each way; 'down': whether it draws there.
local function draw( e, x, y, brush, down )
	local pen, emitter = pen_of( e, x, y )
	EntitySetTransform( pen, x, y )
	EntitySetTransform( e, x, y )
	ComponentSetValue2( emitter, "x_pos_offset_min", -brush )
	ComponentSetValue2( emitter, "x_pos_offset_max", brush )
	ComponentSetValue2( emitter, "y_pos_offset_min", -brush )
	ComponentSetValue2( emitter, "y_pos_offset_max", brush )
	ComponentSetValue2( emitter, "is_emitting", down )
end

local function set( e, p, name, value )
	p[name] = value
	effect_set( e, name, value )
end

local function turned( x, y, angle )
	local c, s = math.cos( angle ), math.sin( angle )
	return x * c - y * s, x * s + y * c
end

-- Where the rose takes root: the nearest surface, as the game's roots do, growing away from it; without one near,
-- the ground below; without that, where it was cast, in the air.
local function root( x, y )
	if GetSurfaceNormal then
		local found, nx, ny, distance = GetSurfaceNormal( x, y, 24, 8 )
		if found then return x + nx * distance, y + ny * distance, -nx, -ny end
	end
	local gx, gy = ground_below( x, y, 60 )
	if gx then return gx, gy - 1, 0, -1 end
	return x, y, 0, -1
end

-- One step of the stem: it sways like the game's roots, leans back upright as a flower does, and turns away from
-- terrain ahead. Returns nil when it is walled in.
local function stem_step( p, x, y, age )
	local seed = p.seed or 0
	local hx, hy = turned( p.hx, p.hy, math.sin( age * 0.21 + seed ) * 0.1 + math.sin( age * 0.043 + seed * 2 ) * 0.06 )
	hx, hy = hx * 0.96, hy * 0.96 - 0.04
	local n = math.sqrt( hx * hx + hy * hy )
	hx, hy = hx / n, hy / n
	if RaytraceSurfaces( x + hx * 2, y + hy * 2, x + hx * 10, y + hy * 10 ) then
		local free
		for _, angle in ipairs( { 0.7, -0.7, 1.4, -1.4 } ) do
			local tx, ty = turned( hx, hy, angle )
			if not RaytraceSurfaces( x + tx * 2, y + ty * 2, x + tx * 10, y + ty * 10 ) then
				hx, hy, free = tx, ty, true
				break
			end
		end
		if not free then return end
	end
	return x + hx * STEP, y + hy * STEP, hx, hy
end

local MODES = {}

MODES.grow = function( e, p, age, x, y )
	local phase = p.phase or STEM
	if age == 0 then
		local hx, hy
		x, y, hx, hy = root( x, y )
		set( e, p, "bx", x ); set( e, p, "by", y )
		set( e, p, "hx", hx ); set( e, p, "hy", hy )
		set( e, p, "seed", ( e * 0.61803398875 % 1 ) * 6.28 )
		draw( e, x, y, 1, true )
		effect_sound( "grow", x, y )
		return
	end
	if phase == STEM then
		local grown, leaves = p.grown or 0, p.leaves or 0
		local nx, ny, hx, hy = stem_step( p, x, y, age )
		-- Under a low ceiling the stem stops short, to leave the rose room to open.
		local room = HEAD_LIFT + HEAD_RADIUS
		local low = nx and grown >= p.length * 0.4 and RaytraceSurfaces( nx, ny, nx + hx * room, ny + hy * room )
		if nx and grown < p.length and not low then
			draw( e, nx, ny, 1, true )
			set( e, p, "hx", hx ); set( e, p, "hy", hy ); set( e, p, "grown", grown + STEP )
			-- a leaf a third and two thirds of the way up, on either side
			if leaves < 2 and grown + STEP >= p.length * ( leaves == 0 and 0.34 or 0.62 ) then
				local side = leaves == 0 and -1 or 1
				local lx, ly = hx * 0.55 - hy * side * 0.85, hy * 0.55 + hx * side * 0.85
				local n = math.sqrt( lx * lx + ly * ly )
				set( e, p, "ax", nx ); set( e, p, "ay", ny )
				set( e, p, "lx", lx / n ); set( e, p, "ly", ly / n )
				-- its tip, where drops will fall from: just under the end of the leaf
				set( e, p, "tip" .. leaves .. "x", nx + lx / n * 11 ); set( e, p, "tip" .. leaves .. "y", ny + ly / n * 11 + 2 )
				set( e, p, "leaves", leaves + 1 ); set( e, p, "i", 1 ); set( e, p, "phase", LEAF )
			end
		else
			-- the top, or no way on: the rose opens here, drawn back from terrain right ahead
			local lift = HEAD_LIFT
			local hit, wx, wy = RaytraceSurfaces( x, y, x + p.hx * room, y + p.hy * room )
			if hit then lift = math.max( 0, math.sqrt( ( wx - x ) ^ 2 + ( wy - y ) ^ 2 ) - HEAD_RADIUS ) end
			set( e, p, "ax", x + p.hx * lift ); set( e, p, "ay", y + p.hy * lift )
			set( e, p, "i", 1 ); set( e, p, "phase", HEAD )
		end
	elseif phase == LEAF then
		local q = LEAF_PATH[p.i]
		if q then
			local px, py = p.ax + p.lx * q[1] - p.ly * q[2], p.ay + p.ly * q[1] + p.lx * q[2]
			-- a leaf never grows into terrain: it is cut short there
			draw( e, px, py, 0.7, not RaytraceSurfaces( p.ax, p.ay, px, py ) )
			set( e, p, "i", p.i + 1 )
		else
			-- back on the stem, without drawing on the way
			draw( e, p.ax, p.ay, 1, false )
			set( e, p, "phase", STEM )
		end
	elseif phase == HEAD then
		local q = HEAD_PATH[p.i]
		if q then
			local px, py = p.ax + q[1], p.ay + q[2]
			-- The pen is lifted for the frame it jumps to the next petal, and where terrain cuts a petal off.
			draw( e, px, py, 0.5, not q[3] and not RaytraceSurfaces( p.ax, p.ay, px, py ) )
			set( e, p, "i", p.i + 1 )
		else
			draw( e, p.ax, p.ay, 0.5, false )
			set( e, p, "phase", STAND )
			-- The spell's time runs from the moment the rose stands.
			set( e, p, "ends", age + p.frames )
		end
	elseif phase == STAND then
		if age >= p.ends then
			-- Turn the standing water back into water, from the middle of the rose out to its ends, and go.
			local mx, my = ( p.bx + p.ax ) / 2, ( p.by + p.ay ) / 2
			local radius = math.sqrt( ( p.bx - p.ax ) ^ 2 + ( p.by - p.ay ) ^ 2 ) / 2 + HEAD_RADIUS + 14
			EntitySetTransform( e, mx, my )
			EntityAddComponent2( e, "MagicConvertMaterialComponent", { from_material_array = WATER, to_material_array = "water",
				radius = math.ceil( radius ), is_circle = true, steps_per_frame = math.ceil( radius / 6 ),
				loop = false, kill_when_finished = false } )
			fx_burst( p.ax, p.ay, fx_color( "water", 0.8 ), 24, 50, 0.5 )
			set( e, p, "phase", MELT )
			set( e, p, "ends", age + 12 )
		elseif age % DRIP_EVERY == 0 then
			-- It drips while it stands: a drop of real water falls from under a petal or from a leaf's tip. The
			-- rose itself loses nothing. No drop where terrain cut the rose off.
			local pick = Random( 1, #HEAD_DRIPS + 2 )
			local q = HEAD_DRIPS[pick]
			local dx, dy = q and p.ax + q[1], q and p.ay + q[2]
			if not q then dx, dy = p["tip" .. ( pick - #HEAD_DRIPS - 1 ) .. "x"], p["tip" .. ( pick - #HEAD_DRIPS - 1 ) .. "y"] end
			if dx and not RaytraceSurfaces( q and p.ax or dx, q and p.ay or dy - 3, dx, dy ) then
				GameCreateParticle( "water", dx, dy, 1, 0, 0, false, false, false )
			end
		end
	elseif age >= p.ends then
		EntityKill( e )
	end
end

EFFECT_MODES.rose = MODES
