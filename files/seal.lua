-- Seals, following Witch Hat Atelier (see docs/architecture.md): a closed ring, a sigil that sets the
-- element and signs around it that shape it. Reading a drawing, the first of two independent steps:
--   parse_seal( strokes )  -> seal tree: the rings, frames and every symbol with its place, size and turn;
--                             seals drawn inside the seal and seals linked to it by a line are trees of
--                             their own
-- The second, compile_spell( seal ) -> spell, is in seal_spell.lua; a seal that looks like one of the wiki's
-- seals (grimoire.lua) is also named after it: seal_canon.lua. Both are loaded after this file.

local MIN_RING_SIZE = 50     -- smallest ring, in gui units
local MAX_ROUNDNESS = 0.22   -- std deviation of the radius / mean radius
local MIN_OPEN_TURN = 0.5    -- a round line covering less than this share of the turn is not a ring attempt
local MAX_GAP_ANGLE = 0.25   -- widest gap (radians) a closed ring may leave; a wider one is a prepared ring
local EMPTY_RING_GAP = 0.09  -- ... an empty one only this (one direction of RING_BINS): a ring left open on purpose to draw
                             -- in later must not wake as the shockwave
local RING_BINS = 72         -- directions checked around the ring
local CLOSING_OFF = 0.08     -- a short stroke closing the ring's gap lies this close to its line (share of the radius)
local OUTER_RING = 1.03      -- an open ring this much bigger than the closed one is the real ring, still open
local MIN_ARC_SIZE = 25      -- strokes smaller than this aren't part of the ring
local ARC_OFF_RING = 0.15    -- an arc's mean radius may differ from the ring's by this share
local MORE_ARCS_RING = 1.06 -- a ring of more strokes is the ring only when it is this much bigger than one of fewer
local NOISE_SIZE = 3         -- a scribble smaller than this is a slip of the pen (a tap of it, a few points, is a dot) ...
local SMALL_MARK = 2         -- ... unless a sign can't be read without it: then the marks over this are read too
local INSIDE = 0.95          -- symbols must lie within this share of the radius
local LARGE_SIGIL = 1.0      -- a sigil this wide must lie almost entirely inside the ring
local SIGIL_OUTSIDE_LIMIT = 0.1 -- share of its points allowed past the inner edge of the ring
local CENTER_ZONE = 0.3      -- closer to the center a symbol has no reliable turn: sigils only ...
local STRONG_SIGIL = 0.6      -- a sigil read this well in the middle ...
local WEAK_MARK = 0.5         -- ... makes the small marks beside it read worse than this its own strokes
local CENTRAL_OUTER = 0.5     -- a small part of the sigil (a ray, a drop) this close joins it ...
local CENTRAL_PART = 0.2      -- ... if it is this small ...
local CENTRAL_REACH = 0.06    -- ... and this close to what stands in the middle (shares of the radius)
local OFF_CENTER_REACH = 0.12 -- a sigil off the middle: how close its small parts lie (players draw its rays apart)
local CENTRAL = 0.35         -- strokes whose middle is this close to the center are read together, as the sigil
local SPAN = 0.55            -- ... unless it is a big sign spanning the seal (Skysoaring, Flame Shot)
local SPAN_MARGIN = 0.06     -- a sign in the center must be read this much better than as a sigil
local CENTER_SIGN_MARGIN = 0.15 -- no wiki seal has a sign in its middle: two sigils side by side are likelier
-- Twins: a seal's signs are drawn round its ring the same, often mirrored. A glyph drawn like a sign read clearly in the
-- same seal (TWIN_SURE) - both turned to face the middle, as drawn or mirrored - is its twin (seal_twins) ...
local TWIN_SURE = 0.65   -- (SEAL_GOOD_SCORE) a sign read this well can have twins
local TWIN_SHAPE = 0.8   -- ... a glyph this much like it ...
local TWIN_SIZE = 1.35   -- ... no more than this much bigger or smaller ...
local TWIN_RING = 0.3    -- ... both this far from the middle (shares of the radius)
local TWIN_GAP = 0.1     -- pieces this close (a share of the radius) may be one glyph torn in its strokes
local TWIN_OVER = 0.1    -- a sign read on its own is read as its twin when it is this much more like the twin ...
local TWIN_READ = 0.45   -- ... or when it reads as the twin's sign this well ...
local TWIN_TIE = 0.08    -- ... no more than this worse than as anything, and looks somewhat like the twin
local TWIN_LOOK = 0.5    -- (a glyph of a wiki's seal of its own may read as a sign, but doesn't look like its twin)
local TWIN_AGREE = 0.55  -- two glyphs or more reading as one sign this well make it sure too
local RING_ZONE = 0.55       -- by the ring a sign ...
local RING_MARGIN = 0.04     -- ... may be read this much worse than a sigil and still count
local CIRCLE_ROUNDNESS = 0.1 -- rings inside the seal are drawn with care: a rounded square (Rain) isn't one
local SIGIL_TURNED = 0.03    -- a sigil read turned on its side or upside down scores this much less
-- symbols drawn around a circle: a circle with one of these inside is the symbol, not a seal in the seal
local CIRCLE_SYMBOLS = { repetition = true, owlcat = true, obliviation = true, orb = true, immobility = true, guidance = true, underfoot = true,
	solidify = true, unburning = true }
local GROUP_MARGIN = 0.55    -- strokes closer than this share of their size may belong to the same symbol
local MIN_GROUP_MARGIN = 4   -- ... but at least this many gui units
local TOUCH = 3              -- strokes closer than this (gui units) touch
local SIGIL_MIN_SIZE = 0.2   -- a few short marks cannot stand for a full sigil after normalization
local INVERTED_MARGIN = 0.08 -- how much better an inverted reading of a sign must score
local POSE_STEP = math.rad( 15 ) -- signs are matched in every pose around the circle, this far apart
-- rings in rings (the wiki's Vapor Bubble, Water Bolt, Serpent's Bed of Sand) and seals linked by a line
local LAYER_CENTER = 0.18    -- a ring whose center is this close (share of the radius) is concentric: a layer
local LAYER_MIN = 0.45       -- ... if it is at least this big
local SUB_MIN = 0.14         -- a smaller circle with symbols inside is a seal of its own in the seal
local ON_RING = 0.22         -- a circle whose center is this close to the ring line sits on the ring
local LINK_TOUCH = 6         -- a line joins two rings when its ends come this close to them (gui units)
local FRAME_MIN = 0.45       -- strokes bigger than this share of the radius around the center may be a frame
local FRAME_SCORE = 0.55     -- a frame must match at least this well
local BAND_MARKS = 8         -- this many small marks between the ring and a layer ring make a band
local GLAIVE_SCORE = 0.5
local OUTSIDE_SLIP = 0.15    -- stray marks outside the ring may be small, not a substantial part of the drawing
local INSIDE_SLIP = 0.3      -- individually small slips cannot add up to a second drawing inside the ring
SEAL_MIN_SCORE = 0.33        -- candidate floor for segmentation; weak matches need a separate spell-level check
SEAL_GOOD_SCORE = 0.65       -- $P+ resemblance of a cleanly drawn symbol
local SIGIL_MIN_SCORE = { selection = 0.6, lightning = 0.5 } -- a bare cross or line resembles these incomplete sigils

local function clamp( v, lo, hi ) return math.max( lo, math.min( hi, v ) ) end
local function round2( v ) return math.floor( v * 100 + 0.5 ) / 100 end

local function bbox( strokes )
	local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
	for _, stroke in ipairs( strokes ) do
		for _, p in ipairs( stroke ) do
			minx = math.min( minx, p.x ); maxx = math.max( maxx, p.x )
			miny = math.min( miny, p.y ); maxy = math.max( maxy, p.y )
		end
	end
	return { minx = minx, miny = miny, maxx = maxx, maxy = maxy, cx = ( minx + maxx ) / 2, cy = ( miny + maxy ) / 2,
		size = math.max( maxx - minx, maxy - miny ), w = maxx - minx, h = maxy - miny }
end

local function stroke_length( stroke )
	local d = 0
	for i = 2, #stroke do d = d + math.sqrt( ( stroke[i].x - stroke[i - 1].x ) ^ 2 + ( stroke[i].y - stroke[i - 1].y ) ^ 2 ) end
	return d
end

-- How much a set of strokes looks like a ring: nil if it is too small or not round. A ring may be drawn
-- in several arcs (lifting the pen); it is closed when its points go all the way around, leaving no
-- gap wider than MAX_GAP_ANGLE.
local function ring_info( strokes, min_size )
	local b = bbox( strokes )
	if b.size < ( min_size or MIN_RING_SIZE ) then return nil end
	local sum, sum_sq, n = 0, 0, 0
	for _, stroke in ipairs( strokes ) do
		for _, p in ipairs( stroke ) do
			local r = math.sqrt( ( p.x - b.cx ) ^ 2 + ( p.y - b.cy ) ^ 2 )
			sum = sum + r; sum_sq = sum_sq + r * r; n = n + 1
		end
	end
	if n < 10 then return nil end
	local mean = sum / n
	local std = math.sqrt( math.max( sum_sq / n - mean * mean, 0 ) )
	if mean <= 0 or std / mean > MAX_ROUNDNESS then return nil end
	-- every arc must lie on the ring itself, not a symbol inside filling its gap
	for _, stroke in ipairs( strokes ) do
		local arc_sum = 0
		for _, p in ipairs( stroke ) do arc_sum = arc_sum + math.sqrt( ( p.x - b.cx ) ^ 2 + ( p.y - b.cy ) ^ 2 ) end
		if math.abs( arc_sum / #stroke - mean ) > ARC_OFF_RING * mean then return nil end
	end

	-- which directions around the center the points cover
	local bins, covered = {}, 0
	for _, stroke in ipairs( strokes ) do
		for _, p in ipairs( stroke ) do
			local bin = math.floor( ( math.atan2( p.y - b.cy, p.x - b.cx ) + math.pi ) / ( 2 * math.pi ) * RING_BINS ) % RING_BINS
			if not bins[bin] then bins[bin] = true; covered = covered + 1 end
		end
	end
	if covered / RING_BINS < MIN_OPEN_TURN then return nil end
	local widest, run = 0, 0
	for i = 0, 2 * RING_BINS - 1 do -- twice around, so a gap across bin 0 counts whole
		if bins[i % RING_BINS] then run = 0 else run = run + 1; widest = math.max( widest, run ) end
	end
	local gap = math.min( widest, RING_BINS ) / RING_BINS * 2 * math.pi
	return { x = b.cx, y = b.cy, r = mean, roundness = std / mean, closed = gap <= MAX_GAP_ANGLE, gap = gap }
end

-- The ring: the biggest round stroke, or up to four big arcs that together make a round ring
local function find_ring( strokes )
	local arcs = {}
	for i, stroke in ipairs( strokes ) do
		if bbox( { stroke } ).size >= MIN_ARC_SIZE then arcs[#arcs + 1] = i end
	end
	local best, best_parts, open_ring, open_r, open_best, open_parts
	local function try( parts )
		local set = {}
		for k, i in ipairs( parts ) do set[k] = strokes[i] end
		local info = ring_info( set )
		if not info then return end
		if info.closed then
			-- a ring whole in fewer strokes stays the ring: a line near it taken along would only shift it (a spoke out to a
			-- small seal lies about as far from the middle as the ring)
			local wins = not best
			if best and #parts == #best_parts then wins = info.r > best.r end
			if best and #parts > #best_parts then wins = info.r > best.r * MORE_ARCS_RING end
			if best and #parts < #best_parts then wins = info.r * MORE_ARCS_RING >= best.r end
			if wins then best, best_parts = info, parts end
		else
			open_ring = true
			open_r = math.max( open_r or 0, info.r )
			if not open_best or info.r > open_best.r then open_best, open_parts = info, parts end
		end
	end
	for a = 1, #arcs do
		try( { arcs[a] } )
		for b = a + 1, #arcs do
			try( { arcs[a], arcs[b] } )
			for c = b + 1, #arcs do
				try( { arcs[a], arcs[b], arcs[c] } )
				for d = c + 1, #arcs do try( { arcs[a], arcs[b], arcs[c], arcs[d] } ) end
			end
		end
	end
	-- a small gap closed with a short line: strokes too small to be arcs of their own close the biggest open ring when
	-- they lie on its line
	if open_best and ( not best or open_best.r > best.r * OUTER_RING ) then
		local parts, used = {}, {}
		for _, i in ipairs( open_parts ) do
			parts[#parts + 1] = i
			used[i] = true
		end
		for i, stroke in ipairs( strokes ) do
			local size = bbox( { stroke } ).size
			-- it bridges at least half of the gap: a bit of a symbol near the ring is no closing line
			if not used[i] and #stroke >= 2 and size < MIN_ARC_SIZE and size >= 0.5 * open_best.gap * open_best.r then
				local on = true
				for _, p in ipairs( stroke ) do
					local d = math.sqrt( ( p.x - open_best.x ) ^ 2 + ( p.y - open_best.y ) ^ 2 )
					if math.abs( d - open_best.r ) > CLOSING_OFF * open_best.r then
						on = false
						break
					end
				end
				if on then parts[#parts + 1] = i end
			end
		end
		if #parts > #open_parts then
			local set = {}
			for k, i in ipairs( parts ) do set[k] = strokes[i] end
			local info = ring_info( set )
			if info and info.closed then best, best_parts = info, parts end
		end
	end
	if not best then return nil, open_ring end
	local parts = {}
	for _, i in ipairs( best_parts ) do parts[i] = true end
	return best, parts, open_r
end

-- How many corners a line has: where it turns sharply (a pentagon has five, a circle none)
local function corner_count( stroke )
	local pts = { stroke[1] }
	for i = 2, #stroke do
		local p, l = stroke[i], pts[#pts]
		if ( p.x - l.x ) ^ 2 + ( p.y - l.y ) ^ 2 >= 9 then pts[#pts + 1] = p end
	end
	local n = #pts
	if n < 8 then return 0 end
	local count, sharp_before = 0, false
	for i = 1, n do
		local a, b, c = pts[( i - 3 ) % n + 1], pts[i], pts[( i + 1 ) % n + 1]
		local ux, uy, vx, vy = b.x - a.x, b.y - a.y, c.x - b.x, c.y - b.y
		local lu, lv = math.sqrt( ux * ux + uy * uy ), math.sqrt( vx * vx + vy * vy )
		local sharp = false
		if lu > 0 and lv > 0 then
			local cos = ( ux * vx + uy * vy ) / ( lu * lv )
			sharp = cos < math.cos( math.rad( 40 ) )
		end
		if sharp and not sharp_before then count = count + 1 end
		sharp_before = sharp
	end
	return count
end

-- Other closed circles drawn in one stroke: { index, x, y, r, roundness }. A circle's line is about as long
-- as its circumference (a zigzag going around - the Windowway's band - is not a circle) and has no corners
-- (the Flower's pentagon is not a circle).
local function find_circles( strokes, skip, min_size )
	local out = {}
	for i, stroke in ipairs( strokes ) do
		if not skip[i] and #stroke >= 10 then
			local info = ring_info( { stroke }, min_size )
			if info and info.closed and info.roundness <= CIRCLE_ROUNDNESS and stroke_length( stroke ) <= 1.35 * 2 * math.pi * info.r
				and corner_count( stroke ) < 3 then
				info.index = i
				out[#out + 1] = info
			end
		end
	end
	return out
end

-- Small closed loops (the little rings of Dancing Puppets): { index, x, y, r }
local function small_circles( strokes, skip )
	local out = {}
	for i, stroke in ipairs( strokes ) do
		if not skip[i] and #stroke >= 6 then
			local b = bbox( { stroke } )
			local a, z = stroke[1], stroke[#stroke]
			local closed = ( a.x - z.x ) ^ 2 + ( a.y - z.y ) ^ 2 <= ( 0.3 * b.size + 1.5 ) ^ 2
			if closed and b.size >= 3 and b.size <= 40 and math.min( b.w, b.h ) >= 0.6 * b.size
				and stroke_length( stroke ) >= 2.4 * b.size then
				out[#out + 1] = { index = i, x = b.cx, y = b.cy, r = b.size / 2 }
			end
		end
	end
	return out
end

-- Points of a stroke about every two gui units: enough to tell how close two strokes come
local function sparse( stroke )
	local out = { stroke[1] }
	for i = 2, #stroke do
		local p, l = stroke[i], out[#out]
		if i == #stroke or ( p.x - l.x ) ^ 2 + ( p.y - l.y ) ^ 2 >= 4 then out[#out + 1] = p end
	end
	return out
end

-- Groups strokes that come close to each other: one group = one symbol. Two strokes belong together when they
-- come closer than a share of the bigger one's size (the two waves of Stability), but at least MIN_GROUP_MARGIN;
-- signs that got grouped together are told apart by reading the group (read_group). Strokes are compared with
-- each other, not with a growing group's box: a ring of signs around the sigil (the Sylph Shoes, the Bubble
-- Carriage) doesn't swallow the sigil in the middle.
local function group_strokes( strokes, margin, share )
	margin, share = margin or MIN_GROUP_MARGIN, share or GROUP_MARGIN
	local n = #strokes
	local boxes, points, parent = {}, {}, {}
	for i, stroke in ipairs( strokes ) do
		boxes[i] = bbox( { stroke } )
		points[i] = sparse( stroke )
		parent[i] = i
	end
	local function find( i )
		while parent[i] ~= i do parent[i] = parent[parent[i]]; i = parent[i] end
		return i
	end
	for i = 1, n do
		for j = i + 1, n do
			local a, b = boxes[i], boxes[j]
			local m = math.max( margin, share * math.max( a.size, b.size ) )
			if a.minx - m <= b.maxx and b.minx - m <= a.maxx and a.miny - m <= b.maxy and b.miny - m <= a.maxy and find( i ) ~= find( j ) then
				local close = false
				local m2 = m * m
				for _, p in ipairs( points[i] ) do
					for _, q in ipairs( points[j] ) do
						if ( p.x - q.x ) ^ 2 + ( p.y - q.y ) ^ 2 <= m2 then close = true; break end
					end
					if close then break end
				end
				if close then parent[find( i )] = find( j ) end
			end
		end
	end
	local by_root, groups = {}, {}
	for i, stroke in ipairs( strokes ) do
		local root = find( i )
		if not by_root[root] then
			by_root[root] = { strokes = {} }
			groups[#groups + 1] = by_root[root]
		end
		table.insert( by_root[root].strokes, stroke )
	end
	for _, g in ipairs( groups ) do g.box = bbox( g.strokes ) end
	return groups
end

local function strokes_touch( a, b, d )
	d = d or TOUCH
	for _, p in ipairs( a ) do
		for _, q in ipairs( b ) do
			if ( p.x - q.x ) ^ 2 + ( p.y - q.y ) ^ 2 <= d * d then return true end
		end
	end
	return false
end

-- Splits strokes into the parts that really touch (points closer than TOUCH): a symbol drawn close to
-- another is grouped with it, touching parts show where one ends
local function touching_parts( strokes )
	local part = {}
	for i = 1, #strokes do part[i] = i end
	local function find( i )
		while part[i] ~= i do i = part[i] end
		return i
	end
	for i = 1, #strokes do
		for j = i + 1, #strokes do
			if find( i ) ~= find( j ) and strokes_touch( strokes[i], strokes[j] ) then part[find( i )] = find( j ) end
		end
	end
	local by_root, parts = {}, {}
	for i, stroke in ipairs( strokes ) do
		local root = find( i )
		if not by_root[root] then
			by_root[root] = { strokes = {} }
			parts[#parts + 1] = by_root[root]
		end
		table.insert( by_root[root].strokes, stroke )
	end
	for _, p in ipairs( parts ) do p.box = bbox( p.strokes ) end
	return parts
end

local function rotate( strokes, cx, cy, angle )
	local cos, sin = math.cos( angle ), math.sin( angle )
	local out = {}
	for i, stroke in ipairs( strokes ) do
		out[i] = {}
		for j, p in ipairs( stroke ) do
			local x, y = p.x - cx, p.y - cy
			out[i][j] = { x = cx + x * cos - y * sin, y = cy + x * sin + y * cos }
		end
	end
	return out
end

-- Template sets, built on first use
local sigil_set, non_flicker_sigil_set, sign_set, frame_set, glaive_set
local SIGN_STROKES = { dispersion = { min = 2 }, levitation = { min = 2 }, pull = { min = 2 },
	pierce = { min = 2 }, crosshair = { min = 3 }, expansion = { min = 2 }, stability = { min = 2 },
	sights = { min = 2 }, strengthen = { min = 2 }, entwine = { min = 2 }, detection = { min = 3 }, partition = { min = 2 },
	refuse = { min = 1 }, solidify = { min = 2 }, binding = { min = 2 }, immobility = { min = 2 }, pointing = { min = 2 },
	mimicry = { min = 2 }, collection = { min = 2 }, gathering = { min = 2 }, orb = { min = 2 }, link = { min = 2 },
	stillness = { min = 3 }, cooling = { min = 3 }, coil = { min = 2 }, aeriform = { min = 3 },
	regions = { max = 2 }, diamond = { max = 2 }, purify = { max = 2 }, windsign = { max = 2 }, projection = { max = 3 },
	reflection = { max = 4 }, envelop = { max = 3 } }
-- the extra ways a sign is drawn (templates.lua) need all their strokes: levitation drawn as an arrow
-- in two strokes would take in slanted columns, a short-based column in one stroke - any bare line
local VARIANT_STROKES = { levitation = { min = 3 }, column = { min = 2 } }
-- center symbols with many parts can't be drawn in one or two strokes
local SIGIL_STROKES = { aeriforms = { min = 5 }, crystal = { min = 4 }, concealment = { min = 4 }, sand = { min = 3 },
	undulation = { min = 3 }, calling = { min = 3 }, unburning = { min = 3 }, whorl = { min = 3 }, owlcat = { min = 3 },
	leech = { min = 4 }, dragon = { min = 4 }, horse = { min = 4 }, bird = { min = 3 }, purification = { min = 3 },
	obliviation = { min = 2 }, selection = { min = 2 }, billow = { min = 2 }, guidance = { min = 3 }, bridging = { min = 2 },
	repetition = { min = 2 }, sword = { min = 2 }, flicker = { max = 3 }, lightning = { max = 2 }, smoke = { max = 3 },
	scalewolf = { min = 6 }, torchstag = { min = 4 }, liongoat = { min = 4 }, frillram = { min = 4 },
	fish = { min = 2 }, -- its body and its tail: a lone S is the wind sigil's bare S, not a fish turned on its side
	fire = { min = 2 } } -- the fire sigil is a triangle and its rays: a one-stroke star is Flickering Light

-- a less usual way of drawing a symbol counts a little less: the wind sigil's bare S must not take the water sigil
-- whose drops came off
local VARIANT_PENALTY = { wind = 0.06 }

-- the special and decorative sigils are rarer than the elements': a drawing that could be either is an element
local SPECIAL_SIGIL = 0.03

local function shape_entries( list, key, limits, first_limits )
	local out = {}
	local def = DICTIONARY_SIGILS[key]
	local prior = def and ( def.manifest or def.shape or def.behavior ) and SPECIAL_SIGIL or 0
	for i, shape in ipairs( list ) do
		local penalty = prior + ( i > 1 and VARIANT_PENALTY[key] or 0 )
		out[#out + 1] = { key = key, shape = shape, strokes = ( i > 1 and limits ) or first_limits, penalty = penalty > 0 and penalty or nil }
	end
	return out
end

local function mirrored( shape )
	local out = {}
	for i, stroke in ipairs( shape ) do
		out[i] = {}
		for j, p in ipairs( stroke ) do out[i][j] = { 1 - ( p.x or p[1] ), p.y or p[2] } end
	end
	return out
end

local function template_sets()
	if not sigil_set then
		local entries = {}
		for _, key in ipairs( DICTIONARY_CENTER_ORDER ) do
			for _, e in ipairs( shape_entries( TEMPLATES_SIGILS[key] or {}, key, SIGIL_STROKES[key], SIGIL_STROKES[key] ) ) do
				entries[#entries + 1] = e
			end
		end
		-- sigils stand upright in the center, but around it they are often turned towards it or lying on their
		-- side (the Bird of Light Beacon's birds, the Floating Drops' water sigils): those poses count a little less
		local r15 = math.rad( 15 )
		sigil_set = recognizer_new_set( entries, { -r15, 0, r15, math.pi / 2, math.pi, 3 * math.pi / 2 } )
		for _, tpl in ipairs( sigil_set ) do
			if math.abs( tpl.tilt ) > r15 + 1e-6 then tpl.penalty = ( tpl.penalty or 0 ) + SIGIL_TURNED end
		end
		non_flicker_sigil_set = {}
		for _, tpl in ipairs( sigil_set ) do
			if tpl.key ~= "flicker" then non_flicker_sigil_set[#non_flicker_sigil_set + 1] = tpl end
		end
		entries = {}
		for _, key in ipairs( DICTIONARY_SIGN_ORDER ) do
			for i, shape in ipairs( TEMPLATES_SIGNS[key] or {} ) do
				local strokes = i > 1 and VARIANT_STROKES[key] or SIGN_STROKES[key]
				entries[#entries + 1] = { key = key, shape = shape, strokes = strokes }
				if DICTIONARY_SIGNS[key].mirror then
					entries[#entries + 1] = { key = key, shape = mirrored( shape ), strokes = strokes, mirror = true }
				end
			end
		end
		local poses = {}
		for i = 0, math.floor( 2 * math.pi / POSE_STEP + 0.5 ) - 1 do poses[#poses + 1] = i * POSE_STEP end
		sign_set = recognizer_new_set( entries, poses )
		-- what each pose means for its sign; an inverted reading must be clearly better where a slightly turned
		-- drawing could be read either way (a triangle turned 60 degrees is inverted), otherwise only a little
		for _, tpl in ipairs( sign_set ) do
			local def = DICTIONARY_SIGNS[tpl.key]
			tpl.inverted, tpl.turn = sign_pose( tpl.key, tpl.tilt )
			if def.invertible == false then tpl.inverted = false end
			tpl.penalty = tpl.inverted and ( ( def.symmetry or 1 ) >= 3 and INVERTED_MARGIN or 0.02 ) or 0
		end
		entries = {}
		for key, shape in pairs( TEMPLATES_FRAMES or {} ) do
			for _, s in ipairs( shape ) do entries[#entries + 1] = { key = key, shape = s } end
		end
		table.sort( entries, function( a, b ) return a.key < b.key end )
		frame_set = recognizer_new_set( entries, { 0, math.pi / 2, math.pi, 3 * math.pi / 2 } )
		glaive_set = recognizer_new_set( { { key = "glaive", shape = TEMPLATES_GLAIVE } }, { -0.3, 0, 0.3 } )
	end
	return sigil_set, sign_set, frame_set, glaive_set
end

-- Flickering Light is a closed star outline. Join up to three strokes by their endpoints, trying
-- their order and direction; a pen lift may leave a small gap, but an open loop is not the outline.
local FLICKER_GAP = 0.18 -- widest endpoint gap, as a share of the symbol's size
local function flicker_contour( strokes, box )
	if #strokes == 0 or #strokes > 3 or box.size <= 0 then return nil end
	for _, stroke in ipairs( strokes ) do if #stroke < 2 then return nil end end
	local gap2 = ( FLICKER_GAP * box.size ) ^ 2
	local function distance2( a, b ) return ( a.x - b.x ) ^ 2 + ( a.y - b.y ) ^ 2 end
	local first = strokes[1][1]
	local order, used = { { stroke = strokes[1] } }, { [1] = true }
	local best, best_gap = nil, math.huge
	local function join( last, gaps )
		if #order == #strokes then
			local closing = distance2( last, first )
			if closing > gap2 or gaps + closing >= best_gap then return end
			best, best_gap = {}, gaps + closing
			for _, part in ipairs( order ) do
				local stroke = part.stroke
				for i = 1, #stroke do best[#best + 1] = stroke[part.reverse and ( #stroke + 1 - i ) or i] end
			end
			best[#best + 1] = first
			return
		end
		for i = 2, #strokes do
			if not used[i] then
				local stroke = strokes[i]
				for direction = 0, 1 do
					local reverse = direction == 1
					local start, finish = stroke[reverse and #stroke or 1], stroke[reverse and 1 or #stroke]
					local gap = distance2( last, start )
					if gap <= gap2 then
						used[i], order[#order + 1] = true, { stroke = stroke, reverse = reverse }
						join( finish, gaps + gap )
						used[i], order[#order] = nil, nil
					end
				end
			end
		end
	end
	join( strokes[1][#strokes[1]], 0 )
	return best
end

local function flicker_shape( strokes, box )
	local contour = flicker_contour( strokes, box )
	local points = contour and recognizer_normalized_points( { contour } )
	if not points then return false end
	-- Signed bends distinguish a star's inward valleys from a convex oval or polygon. Chords two
	-- samples apart suppress tremor; count substantial consecutive inward bends, in either direction.
	local n = #points
	if ( points[1].x - points[n].x ) ^ 2 + ( points[1].y - points[n].y ) ^ 2 < 0.0001 then n = n - 1 end
	local turns, total = {}, 0
	for i = 1, n do
		local a, p, b = points[( i - 3 ) % n + 1], points[i], points[( i + 1 ) % n + 1]
		local ax, ay, bx, by = p.x - a.x, p.y - a.y, b.x - p.x, b.y - p.y
		local turn = math.atan2( ax * by - ay * bx, ax * bx + ay * by )
		turns[i], total = turn, total + turn
	end
	local direction, start = total >= 0 and 1 or -1, 1
	for i, turn in ipairs( turns ) do if turn * direction >= 0 then start = i; break end end
	local valleys, inward, bend = 0, 0, 0
	for offset = 0, n do
		local turn = turns[( start + offset - 1 ) % n + 1] * direction
		if turn < 0 then bend = bend - turn
		elseif bend > 0 then
			inward = inward + bend
			if bend >= 0.35 then valleys = valleys + 1 end
			bend = 0
		end
	end
	-- The reference has six valleys; four allows an uneven hand without admitting smooth loops.
	return valleys >= 4 and inward >= 2
end

-- The water sigil is an S between two drops. As one point cloud the drops' outlines outweigh the S, so drops drawn
-- rounder, bigger or farther out than the template's read poorly as water - and the S alone reads as the wind sigil's
-- bare S. Read by its parts: the tallest stroke an S, and left and right of it a small closed loop each (a drop, an
-- oval, a circle; in one stroke or two). A ray, a chevron or a dot is no drop: the wind, sand and Aeriforms sigils keep
-- their own reading. Returns how well the S reads as an S, or nil.
local DROP_LOOP = 1.8      -- a drop's line is at least this many times as long as the drop is big
local DROP_GAP = 0.4       -- ... its ends this close (shares of its size): a loop, closed or nearly
local DROP_MIN, DROP_MAX = 0.15, 0.8 -- a drop's size against the S's height ...
local DROP_REACH = 1.0     -- ... its middle no farther to the side of the S's middle than this ...
local DROP_LEVEL = 0.5     -- ... nor above or below it
local s_set
local function water_shape( strokes )
	if #strokes < 3 or #strokes > 5 then return nil end
	local s, sb
	for _, stroke in ipairs( strokes ) do
		local b = bbox( { stroke } )
		if #stroke >= 2 and ( not sb or b.h > sb.h ) then s, sb = stroke, b end
	end
	if not sb or sb.h <= 0 then return nil end
	local sides = { {}, {} }
	for _, stroke in ipairs( strokes ) do
		if stroke ~= s then table.insert( sides[bbox( { stroke } ).cx < sb.cx and 1 or 2], stroke ) end
	end
	local function close( a, b, d ) return ( a.x - b.x ) ^ 2 + ( a.y - b.y ) ^ 2 <= d * d end
	for side, list in ipairs( sides ) do
		if #list == 0 or #list > 2 then return nil end
		local b = bbox( list )
		local length = 0
		for _, stroke in ipairs( list ) do
			if #stroke < 2 then return nil end
			length = length + stroke_length( stroke )
		end
		local off = ( b.cx - sb.cx ) * ( side == 1 and -1 or 1 )
		if b.size < DROP_MIN * sb.h or b.size > DROP_MAX * sb.h or off <= 0 or off > DROP_REACH * sb.h
			or math.abs( b.cy - sb.cy ) > DROP_LEVEL * sb.h or length < DROP_LOOP * b.size or math.min( b.w, b.h ) < 0.3 * b.size then
			return nil
		end
		local gap = DROP_GAP * b.size
		local p, q = list[1], list[2]
		if q then
			local a1, a2, b1, b2 = p[1], p[#p], q[1], q[#q]
			if not ( ( close( a1, b1, gap ) and close( a2, b2, gap ) ) or ( close( a1, b2, gap ) and close( a2, b1, gap ) ) ) then return nil end
		elseif not close( p[1], p[#p], gap ) then
			return nil
		end
	end
	if not s_set then
		-- the water sigil's own S, and the bare S hands draw (the wind sigil's)
		s_set = recognizer_new_set( { { key = "s", shape = { TEMPLATES_SIGILS.water[1][1] } },
			{ key = "s", shape = TEMPLATES_SIGILS.wind[#TEMPLATES_SIGILS.wind] } } )
	end
	local _, score = recognizer_match( s_set, { s } )
	return score
end

-- A sign's pose: how it is turned against facing the center (radians) -> inverted, turn. One angle
-- covers both: near 0 the sign faces the center, near half a turn it faces outwards (inverted), and
-- what is left is how far it is turned sideways. A sign that looks the same turned by a part of the
-- circle (its symmetry: 2 for a line through a diamond, 3 for a triangle) only has poses within that
-- part: with an odd symmetry its inverted pose is half of the part away (a triangle turned 60 degrees
-- points the other way), with an even one it can't be inverted at all.
function sign_pose( key, pose )
	local n = DICTIONARY_SIGNS[key].symmetry or 1
	local part = 2 * math.pi / n
	local t = ( pose + part / 2 ) % part - part / 2 -- -part/2 .. part/2
	if n % 2 == 1 and math.abs( t ) > part / 4 then
		return true, t - ( t > 0 and part / 2 or -part / 2 )
	end
	return false, t
end

-- One symbol: a sigil as drawn, or a sign in any pose, turned into its bottom-of-ring pose first (the
-- center is up). The best score wins; signs usually face the center, so an inverted reading must be
-- clearly better. A sign also tells if it is inverted, how far it is turned sideways ('turn', radians)
-- and where it points ('dir', radians, page coordinates). Near the center a large spanning sign or a
-- clearly better sign reading may beat a weak sigil reading.
-- one drawing tries the same strokes in many groupings: each set of strokes is read once
local symbol_cache = setmetatable( {}, { __mode = "k" } )
local function recognize_symbol_uncached( strokes, box, ring )
	local sigils, signs = template_sets()
	local dx, dy = box.cx - ring.x, box.cy - ring.y
	local dist = math.sqrt( dx * dx + dy * dy ) / ring.r
	local angle = math.atan2( dy, dx )
	local size = box.size / ring.r
	local key, score = nil, 0
	if size >= SIGIL_MIN_SIZE then key, score = recognizer_match( sigils, strokes ) end
	if key == "flicker" and not flicker_shape( strokes, box ) then
		key, score = recognizer_match( non_flicker_sigil_set, strokes )
	end
	local water = size >= SIGIL_MIN_SIZE and water_shape( strokes )
	if water and water > score then key, score = "water", water end
	local best = { kind = "sigil", key = key, score = score, inverted = false }
	local spanning = size >= SPAN and math.max( box.w, box.h ) >= 2.2 * math.max( math.min( box.w, box.h ), 1 )
	if dist >= CENTER_ZONE or spanning or score < STRONG_SIGIL then
		-- a sign must beat the sigil reading to count (and one far below the least score never does); by the
		-- ring, where signs stand, a little worse sign reading is enough. In the center a compact sign
		-- must be much clearer, since its direction there is ambiguous.
		local margin = dist < CENTER_ZONE and ( spanning and SPAN_MARGIN or CENTER_SIGN_MARGIN )
			or ( dist >= RING_ZONE and -RING_MARGIN or 0 )
		local m = recognizer_best( signs, rotate( strokes, box.cx, box.cy, math.pi / 2 - angle ),
			math.max( score + margin, SEAL_MIN_SCORE - INVERTED_MARGIN - 1e-9 ), true )
		if m then
			best = { kind = "sign", key = m.key, score = m.score, inverted = m.template.inverted, turn = m.template.turn,
				mirror = m.template.mirror, dir = angle - math.pi + m.template.tilt, margin = m.margin }
		end
	end
	local min_score = best.kind == "sigil" and SIGIL_MIN_SCORE[best.key] or SEAL_MIN_SCORE
	if not best.key or best.score < ( min_score or SEAL_MIN_SCORE ) then return nil end
	-- Point-cloud matching ignores scale and position. A large scribble crossing the ring can otherwise resemble a
	-- sigil after normalization; genuine large sigils stay inside the ring even when they fill most of it.
	if best.kind == "sigil" and size > LARGE_SIGIL then
		local outside, total = 0, 0
		local edge2 = ( INSIDE * ring.r ) ^ 2
		for _, stroke in ipairs( strokes ) do
			for _, p in ipairs( stroke ) do
				total = total + 1
				if ( p.x - ring.x ) ^ 2 + ( p.y - ring.y ) ^ 2 > edge2 then outside = outside + 1 end
			end
		end
		if outside > total * SIGIL_OUTSIDE_LIMIT then return nil end
	end
	best.angle, best.dist, best.size = angle, dist, size
	return best
end

local function recognize_symbol( strokes, box, ring )
	local ids = {}
	for k, st in ipairs( strokes ) do ids[k] = tostring( st ) end
	table.sort( ids )
	local key = table.concat( ids, "," ) .. "@" .. ring.x .. "," .. ring.y .. "," .. ring.r
	local cache = symbol_cache[ring]
	if not cache then
		cache = {}
		symbol_cache[ring] = cache
	end
	local hit = cache[key]
	if hit == nil then
		hit = recognize_symbol_uncached( strokes, box, ring ) or false
		cache[key] = hit
		cache.count = ( cache.count or 0 ) + 1
	end
	if not hit then return nil end
	-- a copy: readings get changed by who reads them; it keeps the strokes it read (the book marks a seal's parts)
	local copy = {}
	for k, v in pairs( hit ) do copy[k] = v end
	copy.strokes = strokes
	return copy
end

-- A glyph turned to face the middle, as a sign at the bottom of the ring is drawn; and its box
local function posed( strokes, ring )
	local b = bbox( strokes )
	return rotate( strokes, b.cx, b.cy, math.pi / 2 - math.atan2( b.cy - ring.y, b.cx - ring.x ) ), b
end
local function mirrored_points( strokes )
	local out = {}
	for i, stroke in ipairs( strokes ) do
		out[i] = {}
		for j, p in ipairs( stroke ) do out[i][j] = { x = -p.x, y = p.y } end
	end
	return out
end

-- 'strokes' read as the sign 'key' only, in their place on the ring (a glyph read as its twin): its pose, turn and
-- score as that sign, or nil when even that reads too badly
local key_sets = {}
local function read_as_sign( strokes, ring, key )
	if not key_sets[key] then
		local _, signs = template_sets()
		local only = {}
		for _, tpl in ipairs( signs ) do
			if tpl.key == key then only[#only + 1] = tpl end
		end
		key_sets[key] = only
	end
	local box = bbox( strokes )
	local dx, dy = box.cx - ring.x, box.cy - ring.y
	local angle = math.atan2( dy, dx )
	local m = recognizer_best( key_sets[key], rotate( strokes, box.cx, box.cy, math.pi / 2 - angle ), SEAL_MIN_SCORE )
	if not m then return nil end
	return { kind = "sign", key = key, score = m.score, inverted = m.template.inverted, turn = m.template.turn,
		mirror = m.template.mirror, dir = angle - math.pi + m.template.tilt, margin = 1, twin = true, strokes = strokes,
		angle = angle, dist = math.sqrt( dx * dx + dy * dy ) / ring.r, size = box.size / ring.r }
end

-- Twins round the ring: a seal's signs are drawn round it alike, often mirrored. 'named': glyphs whose reading is sure,
-- { strokes, key (a sign's, or nil) }; 'pieces': the others, { strokes, box, own (how well it reads on its own, 0: not
-- at all) }. A piece - or two or three lying close together, a glyph torn in its strokes - is a named glyph's twin when
--   it is drawn like it: both turned to face the middle, as drawn or mirrored, very alike and about as big (the same
--   glyph copied - a wiki's seal traced), or
--   it reads as that glyph's sign about as well as it reads as anything, looks somewhat like it, and is about as big
--   (a hand draws one of the seal's signs worse: a sloppy fourth column read as Piercing; a torn one as two signs).
-- Returns { members (piece indices), named (index), score, strokes }, the likest first, no piece in two. Used to read a
-- seal (parse_with) and to name the parts of the wiki's seals (tools/make_grimoire_parts.py), so the book reads and
-- names a drawing alike.
function seal_twins( named, pieces, ring )
	local entries, sizes, by_key = {}, {}, {}
	for n, glyph in ipairs( named ) do
		local shape, b = posed( glyph.strokes, ring )
		if math.sqrt( ( b.cx - ring.x ) ^ 2 + ( b.cy - ring.y ) ^ 2 ) >= TWIN_RING * ring.r then
			entries[#entries + 1] = { key = n, shape = shape }
			entries[#entries + 1] = { key = n, shape = mirrored_points( shape ) }
			sizes[n] = b.size
			if glyph.key and not by_key[glyph.key] then by_key[glyph.key] = n end
		end
	end
	if #entries == 0 or #pieces == 0 then return {} end
	local r15 = math.rad( 15 )
	local set = recognizer_new_set( entries, { -r15, 0, r15 } )
	local function gap( a, b ) return math.max( a.minx - b.maxx, b.minx - a.maxx, a.miny - b.maxy, b.miny - a.maxy, 0 ) end
	local near = {}
	for i = 1, #pieces do
		near[i] = {}
		for j = 1, #pieces do
			if i ~= j and gap( pieces[i].box, pieces[j].box ) <= TWIN_GAP * ring.r then near[i][#near[i] + 1] = j end
		end
	end
	local candidates, seen = {}, {}
	local function add( members )
		table.sort( members )
		local key = table.concat( members, "," )
		if not seen[key] then
			seen[key] = true
			candidates[#candidates + 1] = members
		end
	end
	for i = 1, #pieces do
		add( { i } )
		for _, j in ipairs( near[i] ) do
			add( { i, j } )
			for _, k in ipairs( near[j] ) do
				if k ~= i then add( { i, j, k } ) end
			end
		end
	end
	local function alike_size( size, n )
		local ratio = size / sizes[n]
		return ratio > 1 / TWIN_SIZE and ratio < TWIN_SIZE
	end
	local twins = {}
	for _, members in ipairs( candidates ) do
		local list, own = {}, 0
		for _, m in ipairs( members ) do
			for _, stroke in ipairs( pieces[m].strokes ) do list[#list + 1] = stroke end
			own = math.max( own, pieces[m].own or 0 )
		end
		local shape, b = posed( list, ring )
		if math.sqrt( ( b.cx - ring.x ) ^ 2 + ( b.cy - ring.y ) ^ 2 ) >= TWIN_RING * ring.r then
			local twin
			-- how like each named glyph it looks, as drawn or mirrored
			local look = {}
			for _, m in ipairs( recognizer_scores( set, shape ) ) do look[m.key] = math.max( look[m.key] or 0, m.score ) end
			-- drawn like it
			for n, score in pairs( look ) do
				if score >= TWIN_SHAPE and score >= own + TWIN_OVER and alike_size( b.size, n ) and ( not twin or score > twin.score ) then
					twin = { named = n, score = score }
				end
			end
			-- read as its sign about as well as anything, looking somewhat like a glyph of that sign
			for key, n in pairs( by_key ) do
				local looks = 0
				for m, glyph in ipairs( named ) do
					if glyph.key == key then looks = math.max( looks, look[m] or 0 ) end
				end
				local as = looks >= TWIN_LOOK and read_as_sign( list, ring, key )
				if as and as.score >= TWIN_READ and as.score >= own - TWIN_TIE and alike_size( b.size, n )
					and ( not twin or as.score > twin.score ) then
					twin = { named = n, score = as.score }
				end
			end
			if twin then
				twin.members, twin.strokes = members, list
				twins[#twins + 1] = twin
			end
		end
	end
	-- the likest first, a joined-up glyph before its pieces when as like
	table.sort( twins, function( a, b )
		if math.abs( a.score - b.score ) > 0.01 then return a.score > b.score end
		return #a.members > #b.members
	end )
	local used, out = {}, {}
	for _, twin in ipairs( twins ) do
		local free = true
		for _, m in ipairs( twin.members ) do
			if used[m] then free = false end
		end
		if free then
			for _, m in ipairs( twin.members ) do used[m] = true end
			out[#out + 1] = twin
		end
	end
	return out
end

-- A seal's glyphs read weakly or not at all round the ring, twins of a sign it has read surely, are that sign (the signs
-- of a seal are drawn alike, and a hand draws one of them worse). Sure: read well (TWIN_SURE), or read fairly well
-- (TWIN_AGREE) by two glyphs or more. A sign drawn clearly stays what it is, whatever its neighbours.
-- Groups: { strokes, box, symbols }.
local function read_twins( groups, ring )
	local count = {}
	for _, g in ipairs( groups ) do
		local only = g.symbols and #g.symbols == 1 and g.symbols[1]
		if only and only.kind == "sign" and only.score >= TWIN_AGREE and only.dist >= TWIN_RING then
			count[only.key] = ( count[only.key] or 0 ) + 1
		end
	end
	local named, pieces, of = {}, {}, {}
	for gi, g in ipairs( groups ) do
		local only = g.symbols and #g.symbols == 1 and g.symbols[1]
		local sure = only and only.kind == "sign" and only.dist >= TWIN_RING
			and ( only.score >= TWIN_SURE or ( only.score >= TWIN_AGREE and count[only.key] >= 2 ) )
		if sure then
			named[#named + 1] = { strokes = g.strokes, key = only.key }
			-- glyphs agreeing on one sign aren't ambiguous between it and another (seal_spell.lua SIGN_MIN_MARGIN)
			if count[only.key] >= 2 then only.margin = math.max( only.margin or 0, 1 ) end
		end
		if not sure or only.score < TWIN_SURE then
			-- not sure, or sure only by agreeing: may yet be another sign's twin
			local weak, own = true, 0
			for _, sym in ipairs( g.symbols or {} ) do
				if sym.kind ~= "sign" or sym.score >= TWIN_SURE then weak = false end
				own = math.max( own, sym.score )
			end
			if weak and g.box.size < RING_ZONE * ring.r then
				pieces[#pieces + 1] = { strokes = g.strokes, box = g.box, own = own }
				of[#pieces] = gi
			end
		end
	end
	local gone, added = {}, {}
	for _, twin in ipairs( seal_twins( named, pieces, ring ) ) do
		local key = named[twin.named].key
		local same = #twin.members == 1 and groups[of[twin.members[1]]].symbols
		same = same and #same == 1 and same[1].key == key
		local sym = not same and read_as_sign( twin.strokes, ring, key )
		if sym then
			for _, m in ipairs( twin.members ) do gone[of[m]] = true end
			added[#added + 1] = { strokes = twin.strokes, box = bbox( twin.strokes ), symbols = { sym } }
		end
	end
	if #added == 0 then return groups end
	local out = {}
	for gi, g in ipairs( groups ) do
		if not gone[gi] then out[#out + 1] = g end
	end
	for _, g in ipairs( added ) do out[#out + 1] = g end
	return out
end

-- The parts of a wiki's seal - drawn by hand in the book, or a page of the grimoire (read once by
-- tools/make_grimoire_parts.py: it would take seconds here) - for the book to name the part under the mouse
-- (notebook.lua draw_parts). The seal is cast as a whole; its drawing is read as any seal ('tree': parse_seal's) and a
-- part named when it is sure: a symbol of the seal's recipe ('symbols', 'recipe'); with no recipe (a traced seal) one
-- read clearly, an element sigil only in the middle. A glyph that is a named part's twin round the ring (seal_twins,
-- as the book reads a seal) is named the same; every other glyph - what the reading tore or didn't read, grouped as the
-- book groups strokes, pieces lying close together joined - is a 'mark', a glyph of the seal's own: the wiki draws
-- glyphs of its own, and a rough match would name them wrongly.
--   seal_parts( strokes, tree, entry ) -> { { kind ("sigil", "sign", "mark"), key, inverted, strokes } }
local PART_TRACED = 0.7  -- a traced seal's symbol is named when read this well ...
local PART_SIGIL = 0.5   -- ... a sigil only this close to the middle (shares of the radius): farther out it is a sign's look
local PART_LARGEST = 0.9 -- what no symbol reads, as big as this share of the radius or more, is a ring or a line
local PART_GLYPH = 0.45  -- pieces of the seal's own glyphs lying close together are one, if no bigger than this
local PART_MARGIN = 3.5  -- how close strokes are grouped (as segment's FINE_MARGIN)
function seal_parts( strokes, tree, entry )
	local known = {}
	for _, signature in ipairs( { entry and entry.symbols or "", entry and entry.recipe or "" } ) do
		for key in signature:gmatch( "([%w_]+:[%w_]+)=" ) do known[key] = true end
	end
	local recipe = next( known ) ~= nil
	local ring, ring_parts = find_ring( strokes )
	ring = ring or ( tree and tree.ring )
	if not ring then return {} end
	ring_parts = ring_parts or {}
	local is_ring = {}
	for i in pairs( ring_parts ) do is_ring[strokes[i]] = true end
	local parts, named, taken = {}, {}, {}
	for _, sym in ipairs( tree and tree.symbols or {} ) do
		local sure
		if recipe then sure = known[sym.kind .. ":" .. sym.key]
		else sure = sym.score >= PART_TRACED and not ( sym.kind == "sigil" and sym.dist >= PART_SIGIL ) end
		if sure and sym.strokes then
			parts[#parts + 1] = { kind = sym.kind, key = sym.key, inverted = sym.inverted, strokes = sym.strokes }
			named[#named + 1] = { strokes = sym.strokes, key = sym.kind == "sign" and sym.key or nil, part = #parts }
			for _, stroke in ipairs( sym.strokes ) do taken[stroke] = true end
		end
	end
	-- the rest, the ring left out: grouped as the book first groups strokes (segment); a group too big to be one glyph
	-- (glyphs close together in a band chain up) grouped again, closer
	local rest = {}
	for _, stroke in ipairs( strokes ) do
		if not taken[stroke] and not is_ring[stroke] and #stroke > 0 then rest[#rest + 1] = stroke end
	end
	local pieces = {}
	local function split( list, margin )
		for _, g in ipairs( group_strokes( list, margin, 0 ) ) do
			if g.box.size < PART_LARGEST * ring.r then
				local sym = recognize_symbol( g.strokes, g.box, ring )
				pieces[#pieces + 1] = { strokes = g.strokes, box = g.box, own = sym and sym.score or 0 }
			elseif margin > 0.6 and #g.strokes > 1 then
				split( g.strokes, margin / 2 )
			end
		end
	end
	split( rest, PART_MARGIN )
	local used = {}
	for _, twin in ipairs( seal_twins( named, pieces, ring ) ) do
		local of = parts[named[twin.named].part]
		parts[#parts + 1] = { kind = of.kind, key = of.key, inverted = of.inverted, strokes = twin.strokes }
		for _, m in ipairs( twin.members ) do used[m] = true end
	end
	-- the seal's own glyphs: pieces lying close together are one, unless together they'd be bigger than a glyph
	local left, piece_of = {}, {}
	for i, piece in ipairs( pieces ) do
		if not used[i] then
			for _, stroke in ipairs( piece.strokes ) do
				left[#left + 1] = stroke
				piece_of[stroke] = i
			end
		end
	end
	for _, g in ipairs( group_strokes( left, TWIN_GAP * ring.r, 0 ) ) do
		if g.box.size < PART_GLYPH * ring.r then
			parts[#parts + 1] = { kind = "mark", key = "-", inverted = false, strokes = g.strokes }
		else
			local back = {}
			for _, stroke in ipairs( g.strokes ) do back[piece_of[stroke]] = true end
			for i in pairs( back ) do parts[#parts + 1] = { kind = "mark", key = "-", inverted = false, strokes = pieces[i].strokes } end
		end
	end
	return parts
end

-- How good a reading of a group of strokes is: its symbols' mean score, a little less for every extra symbol
-- and much less for weak ones (a sigil torn into parts reads as a few weak signs)
local function reading_value( symbols )
	local sum, weak = 0, 0
	for _, s in ipairs( symbols ) do
		sum = sum + s.score
		if s.score < 0.5 then weak = weak + 1 end
	end
	return sum / #symbols - 0.03 * ( #symbols - 1 ) - 0.1 * weak
end

-- $P+'s many-to-one matching can read a compound sign's fragments very well (Expansion's two
-- arrowheads as Regions). Prefer a clear, compact peripheral sign over tearing it into fragments.
local COMPOUND_SIGN_MARGIN = 0.1
local function compact_sign( symbol )
	return symbol and symbol.kind == "sign" and symbol.dist >= RING_ZONE and symbol.size <= 0.4
		and symbol.score >= SEAL_GOOD_SCORE
end

-- Reads every group of strokes as one symbol each; nil if one of them isn't a symbol
local function read_each( groups, ring )
	local out = {}
	for _, g in ipairs( groups ) do
		local symbol = recognize_symbol( g.strokes, g.box or bbox( g.strokes ), ring )
		if not symbol then return nil end
		out[#out + 1] = symbol
	end
	return out
end

-- A group may be a sigil of separate strokes (wind's rays, water's drops) that signs next to it joined:
-- peel off the outermost parts one by one, read what was peeled as symbols of its own and the rest as
-- one. Returns every reading where everything is recognized.
local function peel( parts, ring )
	local by_distance = {}
	for i, part in ipairs( parts ) do
		by_distance[i] = { part = part, d = ( part.box.cx - ring.x ) ^ 2 + ( part.box.cy - ring.y ) ^ 2 }
	end
	table.sort( by_distance, function( a, b ) return a.d > b.d end )
	local readings = {}
	for k = 1, math.min( #by_distance - 1, 8 ) do
		local outer, rest = {}, {}
		for i, entry in ipairs( by_distance ) do
			for _, stroke in ipairs( entry.part.strokes ) do table.insert( i <= k and outer or rest, stroke ) end
		end
		local core = recognize_symbol( rest, bbox( rest ), ring )
		if core then
			local others = read_each( group_strokes( outer ), ring )
			if others then
				table.insert( others, 1, core )
				readings[#readings + 1] = others
			end
		end
	end
	return readings
end

-- Symbols touching each other (Flame Shot: the column grows out of the sigil) make one group of strokes:
-- try every way of splitting the group's strokes in two, keep the best reading where both are recognized
local MAX_SPLIT_STROKES = 7
-- symbol readings one drawing may spend on trying other groupings (each costs ~10-20 ms): a drawing of very many
-- strokes stops there instead of freezing the game
local SPLIT_BUDGET = 60
local READ_BUDGET = 160
local function spent( ring )
	local cache = symbol_cache[ring]
	return cache and cache.count or 0
end
local function split_in_two( strokes, ring )
	local n = #strokes
	if n < 2 or n > MAX_SPLIT_STROKES or spent( ring ) > SPLIT_BUDGET then return nil end
	local best, best_value
	for mask = 1, 2 ^ ( n - 1 ) - 1 do
		local a, b = {}, {}
		for i = 1, n do
			if math.floor( mask / 2 ^ ( i - 1 ) ) % 2 == 1 then a[#a + 1] = strokes[i] else b[#b + 1] = strokes[i] end
		end
		local sa = recognize_symbol( a, bbox( a ), ring )
		if sa then
			local sb = recognize_symbol( b, bbox( b ), ring )
			if sb then
				local v = reading_value( { sa, sb } )
				if not best_value or v > best_value then best, best_value = { sa, sb }, v end
			end
		end
	end
	return best
end

-- What a reading loses for signs beside a sigil in the very middle of the seal: they are rather the sigil's own parts
-- drawn apart - the water sigil's drops beside its S, which alone reads as wind, aren't two signs in its middle
local function signs_beside_sigil( list )
	local sigil = false
	for _, sym in ipairs( list ) do
		if sym.kind == "sigil" then sigil = true end
	end
	if not sigil then return 0 end
	local cost = 0
	for _, sym in ipairs( list ) do
		if sym.kind == "sign" and sym.dist < CENTER_ZONE then cost = cost + CENTER_SIGN_MARGIN end
	end
	return cost
end

-- Reads a group of strokes: whole, as its touching parts, peeled, or split in two - the best reading wins.
-- Returns the symbols or nil.
local function read_group( group, ring )
	local readings = {}
	local whole = recognize_symbol( group.strokes, group.box, ring )
	if whole then readings[1] = { whole } end
	-- two symbols drawn close together get grouped: read the parts that really touch separately too
	local parts = #group.strokes > 1 and spent( ring ) <= READ_BUDGET and touching_parts( group.strokes ) or {}
	if #parts > 1 then
		readings[#readings + 1] = read_each( parts, ring )
		if #parts > 2 then
			for _, r in ipairs( peel( parts, ring ) ) do readings[#readings + 1] = r end
		end
	end
	local best, best_value
	for i, r in pairs( readings ) do
		if r and #r > 0 then
			local v = reading_value( r ) - signs_beside_sigil( r )
			if i ~= 1 and compact_sign( whole ) then v = v - COMPOUND_SIGN_MARGIN * ( #r - 1 ) end
			-- in the middle of the seal a sign spanning it has to be clearly better than sigils side by side
			if i == 1 and whole and whole.kind == "sign" and whole.dist < CENTER_ZONE then v = v - CENTER_SIGN_MARGIN end
			if not best_value or v > best_value then best, best_value = r, v end
		end
	end
	local central_sign = best and #best == 1 and best[1].kind == "sign" and best[1].dist < CENTER_ZONE
	if not best or best_value < 0.45 or central_sign then
		local pair = split_in_two( group.strokes, ring )
		if pair and ( not best_value or reading_value( pair ) > best_value ) then best = pair end
	end
	return best
end

-- Splits strokes into symbols: the strokes that touch make small groups first, then neighbouring groups are joined
-- whenever together they read better as one symbol than apart - two or three at once (the water sigil's S and both
-- its drops, the two waves of Stability), the biggest gain first. A group read very well is a symbol of its own and
-- joins nothing. Returns the groups: { strokes, box, symbols (nil: not read), value }.
local FINE_MARGIN = 3.5
local LOCKED_READING = 0.92
local MAX_JOINED = 3 -- a group is tried with up to this many neighbours at once
local MAX_NEIGHBOURS = 6 -- ... among its nearest neighbours
local JOIN_BUDGET = 100 -- readings of joined groups one drawing may try: a drawing of very many strokes stops joining there
local function segment( strokes, ring )
	local groups = group_strokes( strokes, FINE_MARGIN, 0 )
	local function points_of( g )
		local pts = {}
		for _, st in ipairs( g.strokes ) do
			for _, p in ipairs( sparse( st ) ) do pts[#pts + 1] = p end
		end
		return pts
	end
	local next_id = 0
	local function prepare( g )
		next_id = next_id + 1
		g.id = next_id
		g.points = g.points or points_of( g )
		g.ink = 0
		for _, st in ipairs( g.strokes ) do g.ink = g.ink + math.max( stroke_length( st ), 2 ) end
	end
	for _, g in ipairs( groups ) do
		g.symbols = read_group( g, ring )
		g.value = g.symbols and reading_value( g.symbols ) or -1
		prepare( g )
	end
	local function near( a, b )
		local m = math.max( 6, GROUP_MARGIN * math.min( a.box.size, b.box.size ) )
		if a.box.minx - m > b.box.maxx or b.box.minx - m > a.box.maxx or a.box.miny - m > b.box.maxy or b.box.miny - m > a.box.maxy then
			return false
		end
		local m2 = m * m
		for _, p in ipairs( a.points ) do
			for _, q in ipairs( b.points ) do
				if ( p.x - q.x ) ^ 2 + ( p.y - q.y ) ^ 2 <= m2 then return true end
			end
		end
		return false
	end
	local cache = {}
	local tried = 0
	-- reads the groups together as one symbol: the reading and its value, or nil
	local function joined_reading( list )
		local ids = {}
		for k, g in ipairs( list ) do ids[k] = g.id end
		table.sort( ids )
		local key = table.concat( ids, "," )
		if cache[key] == nil then
			tried = tried + 1
			local joined = {}
			for _, g in ipairs( list ) do
				for _, st in ipairs( g.strokes ) do joined[#joined + 1] = st end
			end
			local box = bbox( joined )
			local symbol = box.size <= 1.1 * ring.r and recognize_symbol( joined, box, ring )
			cache[key] = symbol and { strokes = joined, box = box, symbols = { symbol }, value = reading_value( { symbol } ) } or false
		end
		return cache[key] or nil
	end
	while true do
		local best
		for i, a in ipairs( groups ) do
			if a.value < LOCKED_READING then
				local around = {}
				for j, b in ipairs( groups ) do
					if j ~= i and b.value < LOCKED_READING and near( a, b ) then around[#around + 1] = b end
				end
				-- only the nearest few
				if #around > MAX_NEIGHBOURS then
					local function d2( b ) return ( b.box.cx - a.box.cx ) ^ 2 + ( b.box.cy - a.box.cy ) ^ 2 end
					table.sort( around, function( p, q ) return d2( p ) < d2( q ) end )
					for k = #around, MAX_NEIGHBOURS + 1, -1 do around[k] = nil end
				end
				-- a with every combination of up to MAX_JOINED of its neighbours
				local function try( start, chosen )
					if #chosen > 0 then
						-- what the groups are worth apart: their readings weighed by how much of the drawing each explains
						-- (a part of a sigil read as some other symbol explains little of it; unread counts as nothing)
						local list = { a }
						local worth, ink = math.max( a.value, 0 ) * a.ink, a.ink
						for _, b in ipairs( chosen ) do
							list[#list + 1] = b
							worth, ink = worth + math.max( b.value, 0 ) * b.ink, ink + b.ink
						end
						worth = worth / ink
						local r = joined_reading( list )
						-- sigils side by side don't make one sign together (two fire sigils aren't Solidification)
						if r and r.symbols[1].kind == "sign" then
							local sigils = 0
							for _, g in ipairs( list ) do
								if g.symbols and #g.symbols == 1 and g.symbols[1].kind == "sigil" and g.value >= 0.55 then sigils = sigils + 1 end
							end
							if sigils >= 2 then r = nil end
						end
						if r then
							local gain = r.value - worth
							if compact_sign( r.symbols[1] ) then
								local fragments = true
								for _, g in ipairs( list ) do
									if not g.symbols or #g.symbols ~= 1 or g.symbols[1].kind ~= "sign" then fragments = false; break end
								end
								if fragments then gain = gain + COMPOUND_SIGN_MARGIN * ( #list - 1 ) end
							end
							if gain > 0.02 and ( not best or gain > best.gain ) then best = { list = list, group = r, gain = gain } end
						end
					end
					if #chosen >= MAX_JOINED or tried > JOIN_BUDGET then return end
					for k = start, #around do
						chosen[#chosen + 1] = around[k]
						try( k + 1, chosen )
						chosen[#chosen] = nil
					end
				end
				if #around > 0 then try( 1, {} ) end
			end
		end
		if not best then break end
		local gone = {}
		for _, g in ipairs( best.list ) do gone[g] = true end
		local rest = {}
		for _, g in ipairs( groups ) do if not gone[g] then rest[#rest + 1] = g end end
		prepare( best.group )
		rest[#rest + 1] = best.group
		groups = rest
	end
	-- a small mark left unread (a dot, a stray tick) joins the nearest symbol if that symbol stays readable, or is a
	-- slip of the pen
	local kept = {}
	for _, g in ipairs( groups ) do
		if not g.symbols and g.box.size < 0.12 * ring.r then
			local home, home_value
			for _, h in ipairs( groups ) do
				if h ~= g and h.symbols and #h.symbols == 1 and near( g, h ) then
					local r = joined_reading( { h, g } )
					if r and r.value >= h.value - 0.08 and ( not home_value or r.value > home_value ) then home, home_value = h, r.value end
				end
			end
			if home then
				local r = joined_reading( { home, g } )
				home.strokes, home.box, home.symbols, home.value = r.strokes, r.box, r.symbols, r.value
				home.points = nil
				home.points = points_of( home )
			end
		else
			kept[#kept + 1] = g
		end
	end
	return kept
end

-- Is the seal's ring closed? (the stroke that closes it awakens the seal) Only the outermost ring counts: a layer
-- drawn closed inside a ring that still has its gap doesn't awaken the seal
-- A ring with nothing in it yet wakes only when it is closed for sure: it is the shockwave
function seal_ring_closed( strokes )
	local ring, parts, open_r = find_ring( strokes )
	if not ring or ( open_r and open_r > ring.r * OUTER_RING ) then return false end
	if ring.gap <= EMPTY_RING_GAP then return true end
	for i, stroke in ipairs( strokes ) do
		if not parts[i] and bbox( { stroke } ).size >= NOISE_SIZE then return true end
	end
	return false
end

local function inside_circle( stroke, c, share )
	local r2 = ( c.r * ( share or 1 ) ) ^ 2
	for _, p in ipairs( stroke ) do
		if ( p.x - c.x ) ^ 2 + ( p.y - c.y ) ^ 2 > r2 then return false end
	end
	return true
end

local function distance_to_ring( p, c )
	return math.abs( math.sqrt( ( p.x - c.x ) ^ 2 + ( p.y - c.y ) ^ 2 ) - c.r )
end

-- A frame (the Sign of Rain around the water sigil, Holding, Stretch, Dancing Puppets, a Flower): big
-- strokes around the center with whatever touches them from outside. Returns the frame and the strokes it
-- used, or nil.
local function find_frame( strokes, ring )
	local big, used = {}, {}
	for i, stroke in ipairs( strokes ) do
		local b = bbox( { stroke } )
		if b.size >= FRAME_MIN * ring.r and #stroke >= 6 then
			-- a line through the middle belongs to the sigil (the water sigil's long S)
			local near = 0
			for _, p in ipairs( stroke ) do
				if ( p.x - ring.x ) ^ 2 + ( p.y - ring.y ) ^ 2 < ( 0.25 * ring.r ) ^ 2 then near = near + 1 end
			end
			if near <= 0.12 * #stroke then big[#big + 1] = i end
		end
	end
	if #big == 0 then return nil end
	local set, index = {}, {}
	for _, i in ipairs( big ) do used[i] = true end
	-- strokes touching the big ones, away from the center (ticks, rays, small rings), belong to the frame
	local grew = true
	while grew do
		grew = false
		for i, stroke in ipairs( strokes ) do
			if not used[i] then
				local b = bbox( { stroke } )
				local far = math.sqrt( ( b.cx - ring.x ) ^ 2 + ( b.cy - ring.y ) ^ 2 ) > 0.28 * ring.r
				if far then
					for j in pairs( used ) do
						if strokes_touch( stroke, strokes[j], TOUCH + 1 ) then used[i] = true; grew = true; break end
					end
				end
			end
		end
	end
	for i in pairs( used ) do set[#set + 1] = strokes[i]; index[#index + 1] = i end
	local box = bbox( set )
	local tol = 0.2 * ring.r
	if box.minx > ring.x + tol or box.maxx < ring.x - tol or box.miny > ring.y + tol or box.maxy < ring.y - tol then return nil end
	if box.size < 0.7 * ring.r then return nil end
	-- a frame goes around the sigil: its middle stays empty (a big sigil in the middle is no frame)
	local center, total = 0, 0
	for _, stroke in ipairs( set ) do
		for _, p in ipairs( stroke ) do
			total = total + 1
			if ( p.x - ring.x ) ^ 2 + ( p.y - ring.y ) ^ 2 < ( 0.1 * ring.r ) ^ 2 then center = center + 1 end
		end
	end
	if center > 0.05 * total then return nil end
	local _, _, frames = template_sets()
	local key, score = recognizer_match( frames, set )
	if not key or score < FRAME_SCORE then return nil end
	-- a big sign spanning the seal reads better as that sign
	local signs = select( 2, template_sets() )
	local m = recognizer_best( signs, set, score )
	if m then return nil end
	return { key = key, score = score, size = box.size / ring.r }, index
end

-- Glaives: signs drawn outside the ring, their stems touching it (forbidden magic)
local function find_glaives( outside, ring )
	local count, used = 0, {}
	local _, _, _, glaives = template_sets()
	for _, group in ipairs( group_strokes( outside ) ) do
		local near = false
		for _, stroke in ipairs( group.strokes ) do
			for _, p in ipairs( stroke ) do
				if distance_to_ring( p, ring ) <= LINK_TOUCH then near = true; break end
			end
			if near then break end
		end
		if near and group.box.size <= 0.6 * ring.r then
			local angle = math.atan2( group.box.cy - ring.y, group.box.cx - ring.x )
			local key, score = recognizer_match( glaives, rotate( group.strokes, group.box.cx, group.box.cy, math.pi / 2 - angle ) )
			if key and score >= GLAIVE_SCORE then
				count = count + 1
				for _, stroke in ipairs( group.strokes ) do used[stroke] = true end
			end
		end
	end
	return count, used
end

-- The seal inside a circle: its symbols (a smaller seal drawn in or linked to the main one)
local parse_inside

-- The seal tree or nil and an error text; scribbles smaller than 'noise' are left out
-- Preserve a complete ornamental drawing, including its short detached ticks.
-- Small groups keep the normal segmentation rules; only a clear creature
-- match spanning at least .45 of the ring radius gets this protection.
local function decorative_groups( strokes, ring )
	local groups, ink, remaining = {}, {}, strokes
	for _, reach in ipairs( { 0.45, 0.3 } ) do
		for _, group in ipairs( group_strokes( remaining, math.max( FINE_MARGIN, .07 * ring.r ), reach ) ) do
			if #group.strokes >= 4 and group.box.size >= .45 * ring.r then
				local symbol = recognize_symbol( group.strokes, group.box, ring )
				local def = symbol and symbol.kind == "sigil" and DICTIONARY_SIGILS[symbol.key]
				if def and def.shape and symbol.score >= SEAL_GOOD_SCORE then
					group.symbols = { symbol }
					groups[#groups + 1] = group
					for _, stroke in ipairs( group.strokes ) do ink[stroke] = true end
				end
			end
		end
		remaining = {}
		for _, stroke in ipairs( strokes ) do if not ink[stroke] then remaining[#remaining + 1] = stroke end end
	end
	return groups, ink, remaining
end

local function parse_with( strokes, noise )
	local ring, ring_parts = find_ring( strokes )
	if not ring then
		return nil, ring_parts and "The ring is not closed" or "No ring - the seal does nothing"
	end
	local seal = { ring = { x = ring.x, y = ring.y, r = ring.r, roundness = ring.roundness }, symbols = {}, layers = {}, frames = {},
		subs = {}, links = {}, glaives = 0, satellites = 0, strokes = strokes }

	-- other circles: layers (concentric), seals inside, seals on the ring, linked seals outside
	local circles = find_circles( strokes, ring_parts, 12 )
	local claimed = {}
	for i in pairs( ring_parts ) do claimed[i] = true end
	-- Dancing Puppets: a ring around the sigil with small rings on it and arms reaching out (Flying Puppet
	-- of Diversion) - a frame, not a layer
	local tiny = small_circles( strokes, claimed )
	for _, c in ipairs( circles ) do
		local d = math.sqrt( ( c.x - ring.x ) ^ 2 + ( c.y - ring.y ) ^ 2 )
		if not seal.frames[1] and d <= LAYER_CENTER * ring.r and c.r >= 0.25 * ring.r and c.r < 0.7 * ring.r then
			local on = {}
			for _, t in ipairs( tiny ) do
				if t.index ~= c.index and t.r < 0.35 * c.r and math.abs( math.sqrt( ( t.x - c.x ) ^ 2 + ( t.y - c.y ) ^ 2 ) - c.r ) <= 0.12 * c.r then
					on[#on + 1] = t
				end
			end
			if #on >= 3 then
				local used = { [c.index] = true }
				for _, t in ipairs( on ) do used[t.index] = true end
				-- the arms: strokes touching them outside the puppets' ring
				local grew = true
				while grew do
					grew = false
					for i, stroke in ipairs( strokes ) do
						if not used[i] and not claimed[i] then
							local b = bbox( { stroke } )
							if math.sqrt( ( b.cx - c.x ) ^ 2 + ( b.cy - c.y ) ^ 2 ) >= 0.85 * c.r then
								for j in pairs( used ) do
									if strokes_touch( stroke, strokes[j], TOUCH + 1 ) then used[i] = true; grew = true; break end
								end
							end
						end
					end
				end
				for i in pairs( used ) do claimed[i] = true end
				seal.frames[1] = { key = "dancing", score = 0.8, size = 2 * c.r / ring.r }
			end
		end
	end
	local inner_circles, outer_circles = {}, {}
	for _, c in ipairs( circles ) do
		local d = math.sqrt( ( c.x - ring.x ) ^ 2 + ( c.y - ring.y ) ^ 2 )
		if claimed[c.index] then
			-- part of the frame
		elseif d <= LAYER_CENTER * ring.r and c.r >= LAYER_MIN * ring.r and c.r < 0.97 * ring.r then
			seal.layers[#seal.layers + 1] = { r = c.r / ring.r, roundness = c.roundness }
			claimed[c.index] = true
		elseif d + c.r <= ring.r * 1.02 and c.r >= SUB_MIN * ring.r then
			inner_circles[#inner_circles + 1] = c
		elseif math.abs( d - ring.r ) <= ON_RING * ring.r and c.r >= 0.07 * ring.r and c.r < 0.4 * ring.r then
			outer_circles[#outer_circles + 1] = { circle = c, on_ring = true }
		elseif d - c.r >= ring.r * 0.98 and c.r >= 0.12 * ring.r then
			outer_circles[#outer_circles + 1] = { circle = c }
		end
	end
	table.sort( seal.layers, function( a, b ) return a.r > b.r end )

	-- seals inside the seal: a circle holding symbols of its own (the Serpent's Bed of Sand's Wall Breakers).
	-- A circle that reads, with what is inside it, as one symbol (Repetition, Owlcat) is that symbol.
	for _, c in ipairs( inner_circles ) do
		local content, content_index = { strokes[c.index] }, {}
		for i, stroke in ipairs( strokes ) do
			if i ~= c.index and not claimed[i] and inside_circle( stroke, c, 0.98 ) then
				content[#content + 1] = stroke; content_index[#content_index + 1] = i
			end
		end
		if #content > 1 then
			local whole = recognize_symbol( content, bbox( content ), ring )
			-- in the middle of the ring it is the sigil more likely than a small seal (those stand around it)
			local centered = ( c.x - ring.x ) ^ 2 + ( c.y - ring.y ) ^ 2 <= ( CENTER_ZONE * ring.r ) ^ 2
			if not whole or not CIRCLE_SYMBOLS[whole.key] or whole.score < ( centered and 0.5 or 0.7 ) then
				local inner = {}
				for k = 2, #content do inner[#inner + 1] = content[k] end
				local sub = parse_inside( inner, c )
				if sub and #sub.symbols > 0 then
					sub.angle = math.atan2( c.y - ring.y, c.x - ring.x )
					sub.dist = math.sqrt( ( c.x - ring.x ) ^ 2 + ( c.y - ring.y ) ^ 2 ) / ring.r
					sub.size = c.r / ring.r
					seal.subs[#seal.subs + 1] = sub
					claimed[c.index] = true
					for _, i in ipairs( content_index ) do claimed[i] = true end
				end
			end
		end
	end

	-- seals on the ring (the Mirror spell's satellites) and seals outside joined to it by a line (Water Cage)
	for _, entry in ipairs( outer_circles ) do
		local c = entry.circle
		local content, content_index = {}, {}
		for i, stroke in ipairs( strokes ) do
			if i ~= c.index and not claimed[i] and inside_circle( stroke, c, 0.98 ) then
				content[#content + 1] = stroke; content_index[#content_index + 1] = i
			end
		end
		local linked = entry.on_ring
		local link_index
		if not linked then
			-- a line from this circle to the ring
			for i, stroke in ipairs( strokes ) do
				if not claimed[i] and i ~= c.index and #stroke >= 2 then
					local a, b = stroke[1], stroke[#stroke]
					local ends = { { a, b }, { b, a } }
					for _, e in ipairs( ends ) do
						if distance_to_ring( e[1], c ) <= LINK_TOUCH and distance_to_ring( e[2], ring ) <= LINK_TOUCH + 2 then
							linked, link_index = true, i
						end
					end
				end
				if linked then break end
			end
		end
		if linked then
			local sub = parse_inside( content, c )
			sub.angle = math.atan2( c.y - ring.y, c.x - ring.x )
			sub.size = c.r / ring.r
			if entry.on_ring then
				seal.satellites = seal.satellites + 1
				for _, s in ipairs( sub.symbols ) do s.satellite = true; seal.symbols[#seal.symbols + 1] = s end
			else
				seal.links[#seal.links + 1] = sub
			end
			claimed[c.index] = true
			if link_index then claimed[link_index] = true end
			for _, i in ipairs( content_index ) do claimed[i] = true end
		end
	end

	-- what is left inside the ring: frames and symbols; outside it: glaives
	local raw_inner = {}
	for i, stroke in ipairs( strokes ) do
		if not claimed[i] then
			local b = bbox( { stroke } )
			if ( b.cx - ring.x ) ^ 2 + ( b.cy - ring.y ) ^ 2 < ( ring.r * INSIDE ) ^ 2 then raw_inner[#raw_inner + 1] = stroke end
		end
	end
	local _, ornamental_ink = decorative_groups( raw_inner, ring )
	local inner, outside = {}, {}
	local tiny_inner_ink, tiny_outside_ink = 0, 0
	for i, stroke in ipairs( strokes ) do
		if not claimed[i] then
			local b = bbox( { stroke } )
			local d2 = ( b.cx - ring.x ) ^ 2 + ( b.cy - ring.y ) ^ 2
			local keep = b.size >= noise or #stroke <= 3 or ornamental_ink[stroke]
			if not keep and b.size >= SMALL_MARK then seal.small = ( seal.small or 0 ) + 1 end
			if not keep then
				if d2 < ( ring.r * INSIDE ) ^ 2 then
					tiny_inner_ink = tiny_inner_ink + stroke_length( stroke )
				else
					tiny_outside_ink = tiny_outside_ink + stroke_length( stroke )
				end
			end
			if keep and d2 < ( ring.r * INSIDE ) ^ 2 then
				inner[#inner + 1] = stroke
			elseif keep then
				outside[#outside + 1] = stroke
			end
		end
	end
	local glaives, glaive_strokes = find_glaives( outside, ring )
	seal.glaives = glaives
	local inner_ink, outside_ink, stray_ink = 0, tiny_outside_ink, tiny_outside_ink
	for _, stroke in ipairs( inner ) do inner_ink = inner_ink + stroke_length( stroke ) end
	for _, stroke in ipairs( outside ) do
		local ink = stroke_length( stroke )
		outside_ink = outside_ink + ink
		if not glaive_strokes[stroke] then stray_ink = stray_ink + ink end
	end
	if stray_ink > math.max( 0.2 * ring.r, OUTSIDE_SLIP * ( inner_ink + outside_ink ) ) then
		seal.trouble = {}
		for _, stroke in ipairs( outside ) do
			if not glaive_strokes[stroke] then seal.trouble[#seal.trouble + 1] = stroke end
		end
		return nil, "Marks outside the ring are not recognized", seal
	end

	-- a band of marks all around between the ring and an inner ring that aren't signs: windows (Windowway)
	if seal.layers[1] and seal.layers[1].r >= 0.6 then
		local band, rest = {}, {}
		local r_in = seal.layers[1].r * ring.r
		local bins, covered = {}, 0
		for _, stroke in ipairs( inner ) do
			local in_band = true
			for _, p in ipairs( stroke ) do
				local d = math.sqrt( ( p.x - ring.x ) ^ 2 + ( p.y - ring.y ) ^ 2 )
				if d < r_in * 0.96 or d > ring.r * 1.04 then in_band = false; break end
			end
			if in_band then
				band[#band + 1] = stroke
				for _, p in ipairs( stroke ) do
					local bin = math.floor( ( math.atan2( p.y - ring.y, p.x - ring.x ) + math.pi ) / ( 2 * math.pi ) * RING_BINS ) % RING_BINS
					if not bins[bin] then bins[bin] = true; covered = covered + 1 end
				end
			else
				rest[#rest + 1] = stroke
			end
		end
		if covered >= 0.6 * RING_BINS then
			local groups = group_strokes( band )
			local unread = 0
			for _, g in ipairs( groups ) do
				if g.box.size > 0.6 * ring.r or not recognize_symbol( g.strokes, g.box, ring ) then unread = unread + 1 end
			end
			if unread >= 0.6 * #groups and ( #groups >= BAND_MARKS or unread >= 1 and #groups <= 3 ) then
				seal.band = "windows"
				inner = rest
			end
		end
	end

	local frame, frame_index = find_frame( inner, ring )
	if frame then
		seal.frames[1] = frame
		local used = {}
		for _, i in ipairs( frame_index ) do used[i] = true end
		local rest = {}
		for i, stroke in ipairs( inner ) do if not used[i] then rest[#rest + 1] = stroke end end
		inner = rest
	end

	-- Ornamental sigils have detached hooves, scales and horns. Keep a complete, strongly
	-- recognized creature together before the central/outer split can peel those parts off.
	-- The small join distance leaves a separate element sigil beside it independent.
	local decorations, _, remaining = decorative_groups( inner, ring )

	-- the sigil first: what stands in the middle of the ring is read together, as one symbol (or two sigils side
	-- by side, a sign drawn close to them peeled off), so that a sigil of many parts - Aeriforms, the water sigil's
	-- drops - isn't torn apart among the signs around it; the rest is split into signs
	local central, rest = {}, {}
	for _, stroke in ipairs( remaining ) do
		local b = bbox( { stroke } )
		local central_stroke = ( b.cx - ring.x ) ^ 2 + ( b.cy - ring.y ) ^ 2 <= ( CENTRAL * ring.r ) ^ 2 and b.size <= 0.9 * ring.r
		table.insert( central_stroke and central or rest, stroke )
	end
	-- the sigil's small parts a little farther out (the wind sigil's rays, the water sigil's drops) belong to it: a small
	-- stroke touching what stands in the middle joins it
	if #central > 0 then
		local core = bbox( central )
		local m = CENTRAL_REACH * ring.r
		local kept = {}
		for _, stroke in ipairs( rest ) do
			local b = bbox( { stroke } )
			local near_middle = ( b.cx - ring.x ) ^ 2 + ( b.cy - ring.y ) ^ 2 <= ( CENTRAL_OUTER * ring.r ) ^ 2
			local touches = b.minx <= core.maxx + m and b.maxx >= core.minx - m and b.miny <= core.maxy + m and b.maxy >= core.miny - m
			if near_middle and touches and b.size <= CENTRAL_PART * ring.r then central[#central + 1] = stroke else kept[#kept + 1] = stroke end
		end
		rest = kept
	end
	local groups
	if #central > 0 then
		local middle = { strokes = central, box = bbox( central ) }
		-- a reading of the middle, and what it is worth: small marks read weakly beside a well read sigil are its
		-- own strokes drawn apart (the rays a player gives the wind sigil) and are left out
		local function judge( list )
			if not list or #list == 0 then return nil, -1 end
			local strong = false
			for _, sym in ipairs( list ) do
				if sym.kind == "sigil" and sym.score >= STRONG_SIGIL then strong = true end
			end
			if strong and #list > 1 then
				local kept = {}
				for _, sym in ipairs( list ) do
					if not ( sym.score < WEAK_MARK and sym.size < CENTRAL_PART ) then kept[#kept + 1] = sym end
				end
				list = kept
			end
			local v = reading_value( list ) - signs_beside_sigil( list )
			if #list == 1 and list[1].kind == "sign" and list[1].dist < CENTER_ZONE then v = v - CENTER_SIGN_MARGIN end
			return list, v
		end
		local symbols, value = judge( read_group( middle, ring ) )
		-- or the middle split the way the rest is: a sigil of many parts joined up, two sigils side by side apart
		-- (a small mark left unread beside a sigil is one of its strokes)
		local split, all_read = {}, true
		for _, g in ipairs( segment( central, ring ) ) do
			if g.symbols and #g.symbols > 0 then
				for _, symbol in ipairs( g.symbols ) do split[#split + 1] = symbol end
			elseif g.box.size >= CENTRAL_PART * ring.r then
				all_read = false
				break
			end
		end
		if all_read and #split > 0 then
			local list, v = judge( split )
			if v > value then symbols, value = list, v end
		end
		-- a sign in the middle (Skysoaring's big levitation arrow) is no sigil to keep together: its parts farther out
		-- (the arrow's bar) would be torn off it, so the whole inside is read the usual way
		local has_sigil = false
		for _, sym in ipairs( symbols or {} ) do
			if sym.kind == "sigil" then has_sigil = true end
		end
		if symbols and value >= 0.5 and has_sigil then
			middle.symbols = symbols
			groups = segment( rest, ring )
			table.insert( groups, 1, middle )
		end
	end
	groups = groups or segment( remaining, ring )
	-- a sigil standing off the middle (Skysoaring's wind under its big arrow) keeps its small parts too: marks right
	-- beside a sigil read well, every stroke of them small, are its rays and drops, not signs of their own
	for _, g in ipairs( groups ) do
		local sym = g.symbols and #g.symbols == 1 and g.symbols[1]
		if sym and sym.kind == "sigil" and sym.score >= STRONG_SIGIL and not g.taken then
			local m = OFF_CENTER_REACH * ring.r
			local core = g.box
			for _, o in ipairs( groups ) do
				local part = o ~= g and not o.taken and o.symbols ~= nil
				for _, os in ipairs( part and o.symbols or {} ) do
					if os.kind ~= "sign" then part = false end
				end
				for _, stroke in ipairs( part and o.strokes or {} ) do
					local b = bbox( { stroke } )
					if b.size > CENTRAL_PART * ring.r or b.minx > core.maxx + m or b.maxx < core.minx - m
						or b.miny > core.maxy + m or b.maxy < core.miny - m then part = false end
				end
				if part then
					o.taken = true
					for _, stroke in ipairs( o.strokes ) do g.strokes[#g.strokes + 1] = stroke end
				end
			end
		end
	end
	local kept_groups = {}
	for _, g in ipairs( groups ) do
		if not g.taken then kept_groups[#kept_groups + 1] = g end
	end
	groups = read_twins( kept_groups, ring )
	for _, group in ipairs( decorations ) do groups[#groups + 1] = group end
	-- segment() forgives individual short marks, but many such marks must not disappear together and leave
	-- an otherwise convincing sigil behind. Count ink that none of the chosen groups explains.
	local grouped, unread_ink = {}, tiny_inner_ink
	for _, group in ipairs( groups ) do
		for _, stroke in ipairs( group.strokes ) do grouped[stroke] = true end
	end
	for _, stroke in ipairs( inner ) do
		if not grouped[stroke] then unread_ink = unread_ink + stroke_length( stroke ) end
	end
	-- what a seal fails on, the book marks on the page (seal.trouble: the strokes)
	if unread_ink > math.max( 0.25 * ring.r, INSIDE_SLIP * ( inner_ink + tiny_inner_ink ) ) then
		seal.trouble = {}
		for _, stroke in ipairs( inner ) do
			if not grouped[stroke] then seal.trouble[#seal.trouble + 1] = stroke end
		end
		return nil, "Marks inside the ring are not recognized", seal
	end
	local lines = {}
	for _, group in ipairs( groups ) do
		local symbols = group.symbols
		if not symbols then
			-- a long line across the seal that is no sign (the Glowstone Path's crossing arcs) only costs precision
			if group.box.size >= 1.2 * ring.r then
				seal.lines = ( seal.lines or 0 ) + 1
				for _, stroke in ipairs( group.strokes ) do lines[#lines + 1] = stroke end
			else
				seal.trouble = group.strokes
				return nil, "A sign inside the ring is not recognized", seal
			end
		end
		for _, symbol in ipairs( symbols or {} ) do seal.symbols[#seal.symbols + 1] = symbol end
	end
	-- An empty ring is the shockwave only when it really is empty. An unreadable long stroke must not disappear
	-- into the exception for the Glowstone Path's crossing arcs and leave a false shockwave behind.
	if ( seal.lines or 0 ) > 0 and #seal.symbols == 0 and #seal.frames == 0 and #seal.subs == 0 and #seal.links == 0 then
		seal.trouble = lines
		return nil, "A sign inside the ring is not recognized", seal
	end
	return seal
end

-- Returns the seal tree or nil and an error text. Tiny scribbles beside a sigil are slips of the pen and misread it;
-- but a sign may have small marks of its own (the Carousel's), so a sign unread without them is read again with them
function parse_seal( strokes )
	local seal, err, partial = parse_with( strokes, NOISE_SIZE )
	if not seal and partial and partial.small then
		local again = parse_with( strokes, SMALL_MARK )
		if again then return again end
	end
	return seal, err, partial
end

-- The symbols of a smaller seal inside a circle (no rings of its own)
parse_inside = function( strokes, c )
	local sub = { ring = { x = c.x, y = c.y, r = c.r, roundness = c.roundness }, symbols = {}, layers = {}, frames = {}, subs = {},
		links = {}, glaives = 0, satellites = 0 }
	for _, group in ipairs( segment( strokes, sub.ring ) ) do
		for _, symbol in ipairs( group.symbols or {} ) do sub.symbols[#sub.symbols + 1] = symbol end
	end
	return sub
end

-- What the seal's other files share with this one (seal_canon.lua, seal_spell.lua)
SealRead = { find_ring = find_ring, bbox = bbox, recognize_symbol = recognize_symbol, clamp = clamp, round2 = round2,
	MAX_ROUNDNESS = MAX_ROUNDNESS, STRONG_SIGIL = STRONG_SIGIL, SPAN = SPAN, FRAME_SCORE = FRAME_SCORE }
