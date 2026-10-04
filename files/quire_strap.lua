-- The Palm Quire's strap in the open book (notebook.lua draws it under the case): its two ends hang out from under the
-- pad, leather that keeps its curl (book_gfx.lua quire_strap_rest) but sways. Each end is a short chain of points
-- moved by Verlet steps under gravity, every link turning back towards its angle at rest; the ends swing when the witch
-- is thrown about with the book in hand, when a leaf flips over and when the mouse brushes them. Drawn by stamping
-- discs along each chain - its dark edge, the leather over it - with stitches down the middle, the buckle on the left
-- end and holes in the right one. The tab over the lid wobbles on its neck the same way: stiff leather springing
-- back upright, drawn turned (book_gfx.lua quire_tab_image) behind the case's rim.

QuireStrap = {}
local S = QuireStrap

local GRAVITY = 0.05  -- gui pixels per frame, per frame
local DAMPING = 0.9   -- of the speed, every frame
local BEND = 0.35     -- how far a link turns back to its angle at rest, every pass
local ROOT = 0.7      -- ... the first one, held under the pad
local PASSES = 8
local INERTIA = 0.5   -- the strap lags the witch's change of speed (world pixels per second -> gui pixels per frame)
local BRUSH = 4       -- how near the mouse moves the strap along
local Z_EDGE, Z_LEATHER, Z_TOP = 46.4, 46.3, 46.2 -- under the case (45)
local TAB_SPRING = 0.06 -- how hard the tab springs back upright (of its turn, every frame)
local TAB_DAMPING = 0.14 -- ... and its swing dies away
local TAB_PUSH = 8       -- degrees a frame the tab is turned by the witch's change of speed (gui pixels per frame per frame)
local TAB_JOLT = 4       -- ... by a leaf flipping over (times the jolt across)
local TAB_BRUSH = 0.9    -- ... by the mouse moving over it (per gui pixel)
local Z_TAB = 45.05      -- just under the case: the rim covers its root
local STITCH = { 176 / 255, 146 / 255, 108 / 255 }
local HOLE = { 34 / 255, 20 / 255, 14 / 255 }

local ends            -- the two ends: { side, rest = points at rest, bend = each link's turn at rest, root = the first link's angle, pts }
local at_x, at_y      -- the case's top left they hang from
local last_vx, last_vy, last_mx, last_my
local tab = { turn = 0, speed = 0 } -- the tab's turn and its speed, in degrees (positive: its tip to the right)
local tab_x, tab_y  -- its root on the screen

local function wrap( a ) return ( a + math.pi ) % ( 2 * math.pi ) - math.pi end

-- the ends at rest under the case at x, y
function S.reset( def, x, y )
	ends = {}
	for side = -1, 1, 2 do
		local rest = quire_strap_rest( def, side )
		local e = { side = side, rest = rest, bend = {}, pts = {} }
		for i, p in ipairs( rest ) do e.pts[i] = { x = x + p.x, y = y + p.y, px = x + p.x, py = y + p.y } end
		for i = 3, #rest do
			local a0 = math.atan2( rest[i - 1].y - rest[i - 2].y, rest[i - 1].x - rest[i - 2].x )
			local a1 = math.atan2( rest[i].y - rest[i - 1].y, rest[i].x - rest[i - 1].x )
			e.bend[i] = wrap( a1 - a0 )
		end
		e.root = math.atan2( rest[2].y - rest[1].y, rest[2].x - rest[1].x )
		ends[#ends + 1] = e
	end
	at_x, at_y = x, y
	last_vx, last_vy, last_mx, last_my = nil, nil, nil, nil
	local q = quire_case_geometry( def )
	tab_x, tab_y = x + q.cx, y + q.lid - q.r
	tab.turn, tab.speed = 0, 0
end

-- A jolt (a leaf flipping over): the ends kicked by dx, dy - more towards their tips
function S.jolt( dx, dy )
	for _, e in ipairs( ends or {} ) do
		local n = #e.pts
		for i = 2, n do
			local k = ( i - 1 ) / ( n - 1 )
			e.pts[i].px, e.pts[i].py = e.pts[i].px - dx * k * e.side, e.pts[i].py - dy * k
		end
	end
	tab.speed = tab.speed + dx * TAB_JOLT
end

-- One frame: the case's top left at x, y; the witch's speed vx, vy (world pixels per second, nil: unknown); the mouse
function S.update( def, x, y, vx, vy, mx, my )
	if not ends or x ~= at_x or y ~= at_y then S.reset( def, x, y ) end
	local ax, ay = 0, GRAVITY
	if vx and last_vx then
		-- the book in hand changes speed with the witch, the strap lags behind
		ax, ay = ax - ( vx - last_vx ) / 60 * INERTIA, ay - ( vy - last_vy ) / 60 * INERTIA
	end
	last_vx, last_vy = vx, vy
	local mdx, mdy = 0, 0
	if mx and last_mx then mdx, mdy = mx - last_mx, my - last_my end
	last_mx, last_my = mx, my
	-- the tab: a damped spring, pushed by the witch's change of speed and the mouse brushing over it
	tab.speed = tab.speed - tab.turn * TAB_SPRING - tab.speed * TAB_DAMPING + ax * TAB_PUSH
	local tip = math.rad( tab.turn )
	if mx and mdx ~= 0 and math.abs( mx - tab_x - ( tab_y - my ) * math.sin( tip ) ) < 11 and my < tab_y and my > tab_y - 32 then
		tab.speed = tab.speed + mdx * TAB_BRUSH
	end
	tab.turn = tab.turn + tab.speed
	local limit = QUIRE_TAB_STEP * QUIRE_TAB_TURNS
	if math.abs( tab.turn ) > limit then
		tab.turn = math.max( -limit, math.min( limit, tab.turn ) )
		tab.speed = -tab.speed * 0.4
	end
	local L = QUIRE_STRAP_LINK
	for _, e in ipairs( ends ) do
		local p = e.pts
		p[1].x, p[1].y = x + e.rest[1].x, y + e.rest[1].y
		for i = 2, #p do
			local q = p[i]
			local sx, sy = ( q.x - q.px ) * DAMPING, ( q.y - q.py ) * DAMPING
			q.px, q.py = q.x, q.y
			q.x, q.y = q.x + sx + ax, q.y + sy + ay
			if mx and ( mdx ~= 0 or mdy ~= 0 ) and ( q.x - mx ) ^ 2 + ( q.y - my ) ^ 2 < BRUSH * BRUSH then
				q.x, q.y = q.x + mdx * 0.6, q.y + mdy * 0.6
			end
		end
		for _ = 1, PASSES do
			-- the first link leaves the pad as at rest, the others turn back towards their rest angles
			p[2].x = p[2].x + ( p[1].x + math.cos( e.root ) * L - p[2].x ) * ROOT
			p[2].y = p[2].y + ( p[1].y + math.sin( e.root ) * L - p[2].y ) * ROOT
			for i = 3, #p do
				local a = math.atan2( p[i - 1].y - p[i - 2].y, p[i - 1].x - p[i - 2].x ) + e.bend[i]
				p[i].x = p[i].x + ( p[i - 1].x + math.cos( a ) * L - p[i].x ) * BEND
				p[i].y = p[i].y + ( p[i - 1].y + math.sin( a ) * L - p[i].y ) * BEND
			end
			-- the links keep their length; the first point stays under the pad
			for i = 2, #p do
				local a, b = p[i - 1], p[i]
				local dx, dy = b.x - a.x, b.y - a.y
				local d = math.sqrt( dx * dx + dy * dy )
				if d > 0 then
					local k = ( d - L ) / d
					if i == 2 then
						b.x, b.y = b.x - dx * k, b.y - dy * k
					else
						a.x, a.y = a.x + dx * k / 2, a.y + dy * k / 2
						b.x, b.y = b.x - dx * k / 2, b.y - dy * k / 2
					end
				end
			end
		end
	end
end

-- The points along an end a pixel apart: { x, y, along }, and its length
local function walk( p )
	local out, run = { { x = p[1].x, y = p[1].y, along = 0 } }, 0
	for i = 2, #p do
		local dx, dy = p[i].x - p[i - 1].x, p[i].y - p[i - 1].y
		local d = math.sqrt( dx * dx + dy * dy )
		local steps = math.max( 1, math.ceil( d ) )
		for k = 1, steps do
			out[#out + 1] = { x = p[i - 1].x + dx * k / steps, y = p[i - 1].y + dy * k / steps, along = run + d * k / steps }
		end
		run = run + d
	end
	return out, run
end

local function at( path, along )
	for _, s in ipairs( path ) do
		if s.along >= along then return s end
	end
	return path[#path]
end

function S.draw()
	if not ends then return end
	local turn = math.max( -QUIRE_TAB_TURNS, math.min( QUIRE_TAB_TURNS, math.floor( tab.turn / QUIRE_TAB_STEP + 0.5 ) ) )
	BookDraw.image( tab_x - QUIRE_TAB_ROOT_X, tab_y - QUIRE_TAB_ROOT_Y, quire_tab_image( turn ), Z_TAB )
	for _, e in ipairs( ends ) do
		local path, len = walk( e.pts )
		local lx, ly
		for k, s in ipairs( path ) do
			local x, y = math.floor( s.x + 0.5 ), math.floor( s.y + 0.5 )
			if x ~= lx or y ~= ly then
				BookDraw.image( x - 3, y - 3, QUIRE_STRAP_EDGE_IMAGE, Z_EDGE )
				BookDraw.image( x - 2, y - 2, quire_strap_leather_image( k % 3 + 1 ), Z_LEATHER )
				lx, ly = x, y
			end
		end
		-- stitches down the middle, every third pixel, short of the buckle and the holes
		for along = 2, len - 12, 3 do
			local s = at( path, along )
			BookDraw.rect( math.floor( s.x + 0.5 ), math.floor( s.y + 0.5 ), 1, 1, STITCH, Z_TOP )
		end
		local tip = e.pts[#e.pts]
		local before = e.pts[#e.pts - 1]
		if e.side < 0 then
			local a = math.atan2( tip.y - before.y, tip.x - before.x )
			local k = math.floor( a / ( 2 * math.pi ) * QUIRE_STRAP_BUCKLES + 0.5 ) % QUIRE_STRAP_BUCKLES
			local s = at( path, len - 3.5 )
			BookDraw.image( math.floor( s.x + 0.5 ) - 6, math.floor( s.y + 0.5 ) - 6, quire_strap_buckle_image( k ), Z_TOP )
		else
			for _, back in ipairs( { 5, 10 } ) do
				local s = at( path, len - back )
				BookDraw.rect( math.floor( s.x + 0.5 ), math.floor( s.y + 0.5 ), 1, 1, HOLE, Z_TOP )
			end
		end
	end
end
