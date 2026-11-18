-- Straight lines (notebook.lua): the pen drawn along a ruler. With its key held (book_key.lua book_line_held) the pen
-- presses where the line begins and drags to where it ends - a straight line from the one to the other, shown where it
-- will lie while the mouse moves, drawn when the button is let go. A line past the paper's edge is drawn only on the
-- paper. Here: what the gesture keeps, and how the line to the mouse shows on the page; the line itself is drawn by the
-- pen (notebook.lua witch_notebook_pen), fed the two ends of its stretch on the paper.
--   BookLine.press( page, x, y )        the button pressed on 'page' at x, y with the key held
--   BookLine.stretch( x, y, drawable )  the ends of the line's stretch that lies on the paper, to draw
--   BookLine.draw( s, x, y, drawable )  the line from the press to the mouse on the page 's' while the button is held
--   BookLine.mark( s, x, y, drawable )  a small cross where a line pressed here would begin

BookLine = {}
local L = BookLine
local D = BookDraw
local P = BookPages

local GUIDE = P.NOTE_COLOR -- the line on the paper while the mouse moves ...
local CROSS = P.TEXT_COLOR  -- ... the cross where a line pressed here would begin (book_compass.lua: its needle)
local GUIDE_Z = 26          -- over the paper, under the ink (book_draw.lua: the pen's dots lie at 25)
local STEP = 0.5            -- the line sampled this far apart: its ends on the paper to within half a pen's dot
local MIN_LINE = 2          -- the mouse come less than this from the press: a click, no line

-- { page, x, y }: the button pressed on 'page' at x, y, the mouse now elsewhere
L.gesture = nil

function L.press( page, x, y )
	L.gesture = { page = page, x = x, y = y }
end

-- the line from its press to the mouse at x, y, sampled this far apart along it, and how far the mouse has come
local function samples( x, y, step )
	local g = L.gesture
	local d = math.sqrt( ( x - g.x ) ^ 2 + ( y - g.y ) ^ 2 )
	local n = math.max( 1, math.ceil( d / step ) )
	local out = {}
	for k = 0, n do
		local t = k / n
		out[#out + 1] = { x = g.x + ( x - g.x ) * t, y = g.y + ( y - g.y ) * t }
	end
	return out, d
end

-- The stretch of the line from its press to the mouse at x, y that lies on the paper ('drawable': where the pen draws,
-- page units), as its two ends, or nil - a line past the paper's edge is drawn only on the paper. The mouse hardly moved:
-- nil, a click draws nothing.
function L.stretch( x, y, drawable )
	local points, d = samples( x, y, STEP )
	if d < MIN_LINE then return nil end
	local first, last
	for _, p in ipairs( points ) do
		if drawable( p.x, p.y ) then
			if not first then first = p end
			last = p
		end
	end
	if not first or first == last then return nil end
	return first, last
end

---- drawn ----

-- a line of the guide, cut where it leaves the paper the pen draws on
local function guide( s, points, color, alpha, drawable )
	local lines, line = {}, nil
	for _, p in ipairs( points ) do
		if drawable( p.x, p.y ) then
			if not line then line = {}; lines[#lines + 1] = line end
			line[#line + 1] = p
		else
			line = nil
		end
	end
	D.strokes( s, lines, function() return color, alpha end, nil, GUIDE_Z )
end

-- the line from its press to the mouse at x, y on the page 's' while the button is held: dotted, faint, where it lies
-- on the paper ('drawable': where the pen draws on it)
function L.draw( s, x, y, drawable )
	local pen, step = s.pen, s.step
	s.pen, s.step = 0.6, 2.4
	guide( s, samples( x, y, 2 ), GUIDE, 0.75, drawable )
	s.pen, s.step = pen, step
end

-- a small cross at x, y on the page 's': where a line pressed here would begin
function L.mark( s, x, y, drawable )
	local pen, step = s.pen, s.step
	s.pen, s.step = 0.6, 2.4
	guide( s, { { x = x - 3, y = y }, { x = x + 3, y = y } }, CROSS, 0.9, drawable )
	guide( s, { { x = x, y = y - 3 }, { x = x, y = y + 3 } }, CROSS, 0.9, drawable )
	s.pen, s.step = pen, step
end
