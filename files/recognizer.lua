-- $P+ Point-Cloud Recognizer (Vatavu 2017), adapted to Lua.
-- https://depts.washington.edu/acelab/proj/dollar/pdollarplus.pdf
-- A symbol may consist of several strokes, matched as one cloud. Stroke order and direction are not
-- compared; optional stroke-count constraints still apply. Position and size are ignored, orientation is not,
-- so templates get slightly tilted copies (signs are turned upright by the caller, see seal.lua).
-- Uses 48 samples and uniform scaling for the game's complex sigils, and ignores pen-lift corners.

local NUM_POINTS = 48 -- enough for the details of complex sigils (wind's curls)
local TILTS = { -math.rad( 15 ), 0, math.rad( 15 ) } -- tolerance for slightly tilted drawings
local SCORE_SCALE = 4 -- convert mean $P+ distance to the game's 0..1 resemblance scale

local function distance( a, b )
	return math.sqrt( ( b.x - a.x ) ^ 2 + ( b.y - a.y ) ^ 2 )
end

-- strokes: list of point lists -> flat list of points tagged with their stroke index, smoothed a
-- little (a moving average) so that hand tremor doesn't add length to the strokes. A dot (a stroke much
-- smaller than the symbol) has no length to sample points from: it becomes a small ring that weighs
-- like a short line, in templates and drawings alike.
local SMOOTH = 2  -- points on each side
local DOT = 0.08  -- a stroke smaller than this share of the symbol is a dot ...
local DOT_RING = 0.07 -- ... drawn as a ring this long (share of the symbol)
local function flatten( strokes )
	local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
	for _, stroke in ipairs( strokes ) do
		for _, p in ipairs( stroke ) do
			minx, maxx = math.min( minx, p.x ), math.max( maxx, p.x )
			miny, maxy = math.min( miny, p.y ), math.max( maxy, p.y )
		end
	end
	local size = math.max( maxx - minx, maxy - miny, 1e-6 )
	-- a small drawing (gui units) is smoothed less: its corners are only a few points apart
	local smooth = size >= 30 and SMOOTH or 1
	local pts = {}
	for id, stroke in ipairs( strokes ) do
		local n = #stroke
		local sx0, sy0, sx1, sy1 = math.huge, math.huge, -math.huge, -math.huge
		for _, p in ipairs( stroke ) do
			sx0, sx1 = math.min( sx0, p.x ), math.max( sx1, p.x )
			sy0, sy1 = math.min( sy0, p.y ), math.max( sy1, p.y )
		end
		if n > 0 and #strokes > 1 and math.max( sx1 - sx0, sy1 - sy0 ) < DOT * size then
			local cx, cy, r = ( sx0 + sx1 ) / 2, ( sy0 + sy1 ) / 2, DOT_RING * size / ( 2 * math.pi )
			for k = 0, 8 do
				pts[#pts + 1] = { x = cx + r * math.cos( k * math.pi / 4 ), y = cy + r * math.sin( k * math.pi / 4 ), id = id }
			end
		else
			for i = 1, n do
				local sx, sy, k = 0, 0, 0
				for j = math.max( 1, i - smooth ), math.min( n, i + smooth ) do
					sx, sy, k = sx + stroke[j].x, sy + stroke[j].y, k + 1
				end
				pts[#pts + 1] = { x = sx / k, y = sy / k, id = id }
			end
		end
	end
	return pts
end

local function path_length( pts )
	local d = 0
	for i = 2, #pts do
		if pts[i].id == pts[i - 1].id then d = d + distance( pts[i - 1], pts[i] ) end
	end
	return d
end

local function resample( pts, n )
	local interval = path_length( pts ) / ( n - 1 )
	local src = {}
	for i, p in ipairs( pts ) do src[i] = { x = p.x, y = p.y, id = p.id } end
	local out = { src[1] }
	local D = 0
	local i = 2
	while i <= #src do
		local a, b = src[i - 1], src[i]
		if a.id == b.id then
			local d = distance( a, b )
			if d > 0 and D + d >= interval then
				local t = ( interval - D ) / d
				local q = { x = a.x + t * ( b.x - a.x ), y = a.y + t * ( b.y - a.y ), id = b.id }
				out[#out + 1] = q
				table.insert( src, i, q ) -- q becomes the start of the next segment
				D = 0
			else
				D = D + d
			end
		end
		i = i + 1
	end
	local last = src[#src]
	while #out < n do out[#out + 1] = { x = last.x, y = last.y, id = last.id } end
	while #out > n do table.remove( out ) end
	return out
end

local function normalize( pts )
	pts = resample( pts, NUM_POINTS )
	local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs( pts ) do
		minx = math.min( minx, p.x ); maxx = math.max( maxx, p.x )
		miny = math.min( miny, p.y ); maxy = math.max( maxy, p.y )
	end
	local size = math.max( maxx - minx, maxy - miny, 0.0001 ) -- uniform scale keeps proportions
	local cx, cy = 0, 0
	for _, p in ipairs( pts ) do
		p.x = ( p.x - minx ) / size
		p.y = ( p.y - miny ) / size
		cx = cx + p.x; cy = cy + p.y
	end
	cx, cy = cx / #pts, cy / #pts
	for _, p in ipairs( pts ) do p.x = p.x - cx; p.y = p.y - cy end
	return pts
end

-- The same smoothed, uniformly scaled samples used for matching; structural checks can inspect
-- their signed turns without making a second, inconsistent preprocessing pipeline.
function recognizer_normalized_points( strokes )
	local pts = flatten( strokes )
	if #pts < 2 or path_length( pts ) <= 0 then return nil end
	return normalize( pts )
end

-- $P+ adds the normalized turning angle to each point. Pen lifts are not corners: endpoints of each
-- resampled stroke have angle zero, so changing stroke order cannot invent bends between strokes.
-- Flat coordinate arrays are much faster in LuaJIT than a table per point.
local function to_cloud( pts )
	local xs, ys, angles = {}, {}, {}
	for i, p in ipairs( pts ) do
		xs[i], ys[i], angles[i] = p.x, p.y, 0
		local a, b = pts[i - 1], pts[i + 1]
		if a and b and a.id == p.id and b.id == p.id then
			local ax, ay, bx, by = p.x - a.x, p.y - a.y, b.x - p.x, b.y - p.y
			local lengths = math.sqrt( ( ax * ax + ay * ay ) * ( bx * bx + by * by ) )
			if lengths > 1e-12 then
				local cosine = math.max( -1, math.min( 1, ( ax * bx + ay * by ) / lengths ) )
				angles[i] = math.acos( cosine ) / math.pi
			end
		end
	end
	return { xs = xs, ys = ys, angles = angles, n = #pts }
end

-- The $P+ many-to-one distance in both directions. First every source point chooses its closest
-- target; target points not chosen by any source are then matched back. One pairwise pass supplies
-- both directions exactly, without storing a distance matrix or changing the published metric.
local function cloud_match( a, b )
	local n, ax, ay, aa, bx, by, ba = a.n, a.xs, a.ys, a.angles, b.xs, b.ys, b.angles
	local near_a, near_b, chosen_a, chosen_b = {}, {}, {}, {}
	for j = 1, n do near_b[j] = math.huge end
	for i = 1, n do
		local best, best_j = math.huge, 1
		local px, py, angle = ax[i], ay[i], aa[i]
		for j = 1, n do
			local dx, dy, dt = px - bx[j], py - by[j], angle - ba[j]
			local d = dx * dx + dy * dy + dt * dt
			if d < best then best, best_j = d, j end
			if d < near_b[j] then near_b[j], chosen_b[j] = d, i end
		end
		near_a[i], chosen_a[i] = best, best_j
	end
	local used_a, used_b = {}, {}
	for i = 1, n do used_b[chosen_a[i]], used_a[chosen_b[i]] = true, true end
	local forward, backward = 0, 0
	for i = 1, n do
		local da, db = math.sqrt( near_a[i] ), math.sqrt( near_b[i] )
		forward, backward = forward + da, backward + db
		if not used_b[i] then forward = forward + db end
		if not used_a[i] then backward = backward + da end
	end
	return math.min( forward, backward )
end

-- shape: list of strokes -> flat point list, rotated
local function transform( shape, angle )
	local cos, sin = math.cos( angle ), math.sin( angle )
	local out = {}
	for _, p in ipairs( flatten( shape ) ) do
		out[#out + 1] = { x = p.x * cos - p.y * sin, y = p.x * sin + p.y * cos, id = p.id }
	end
	return out
end

-- Builds a set of templates: entries { key = ..., shape = list of strokes of { x, y } or { x, y } pairs,
-- strokes = { min, max } (optional) }. Each shape also gets tilted copies: 'tilts' (radians), by default
-- slightly both ways.
function recognizer_new_set( entries, tilts )
	local set = {}
	for _, entry in ipairs( entries ) do
		local shape = {}
		for i, stroke in ipairs( entry.shape ) do
			shape[i] = {}
			for j, p in ipairs( stroke ) do shape[i][j] = { x = p.x or p[1], y = p.y or p[2] } end
		end
		for _, tilt in ipairs( tilts or TILTS ) do
			set[#set + 1] = { key = entry.key, cloud = to_cloud( normalize( transform( shape, tilt ) ) ), strokes = entry.strokes, tilt = tilt,
				penalty = entry.penalty }
		end
	end
	-- the least turned first: keep the upright reading when equally good poses tie
	local function turned( tpl ) return math.abs( ( tpl.tilt + math.pi ) % ( 2 * math.pi ) - math.pi ) end
	for i, tpl in ipairs( set ) do tpl.order = i end
	table.sort( set, function( a, b )
		if turned( a ) ~= turned( b ) then return turned( a ) < turned( b ) end
		return a.order < b.order
	end )
	return set
end

local function score( distance )
	return math.max( 1 - distance * SCORE_SCALE / NUM_POINTS, 0 )
end

-- strokes: list of point lists. Returns every template's match: { { key, tilt, score } }, where the
-- score goes from 0 (no match) to 1 and tilt is how the drawing is turned against the template
-- (radians, clockwise on screen)
function recognizer_scores( set, strokes )
	local pts = recognizer_normalized_points( strokes )
	if not pts then return {} end
	pts = to_cloud( pts )
	local out = {}
	for _, tpl in ipairs( set ) do
		local limits = tpl.strokes
		if not limits or ( #strokes >= ( limits.min or 0 ) and #strokes <= ( limits.max or math.huge ) ) then
			out[#out + 1] = { key = tpl.key, tilt = tpl.tilt, score = score( cloud_match( pts, tpl.cloud ) ) }
		end
	end
	return out
end

-- The template with the best value - its score minus its 'penalty' (a field of the template, if set) -
-- above 'floor': { key, tilt, score, template } or nil. With alternatives enabled, margin measures
-- the penalized score gap to the best different key; other poses of the same symbol do not compete.
function recognizer_best( set, strokes, floor, alternatives )
	local pts = recognizer_normalized_points( strokes )
	if not pts then return nil end
	pts = to_cloud( pts )
	local best, best_value = nil, floor or -math.huge
	local by_key = alternatives and {} or nil
	for _, tpl in ipairs( set ) do
		local limits = tpl.strokes
		if not limits or ( #strokes >= ( limits.min or 0 ) and #strokes <= ( limits.max or math.huge ) ) then
			local penalty = tpl.penalty or 0
			if alternatives or 1 - penalty > best_value then
				local resemblance = score( cloud_match( pts, tpl.cloud ) )
				local value = resemblance - penalty
				if by_key then by_key[tpl.key] = math.max( by_key[tpl.key] or -math.huge, value ) end
				if value > best_value then
					best = { key = tpl.key, tilt = tpl.tilt, score = resemblance, template = tpl }
					best_value = resemblance - penalty
				end
			end
		end
	end
	if best and by_key then
		local second = -math.huge
		for key, value in pairs( by_key ) do
			if key ~= best.key and value > second then second = value end
		end
		best.margin = best_value - second
	end
	return best
end

-- The best match: key, score, tilt
function recognizer_match( set, strokes )
	local best = recognizer_best( set, strokes )
	if not best then return nil, 0, 0 end
	return best.key, best.score, best.tilt
end
