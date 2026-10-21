-- The compass (notebook.lua): a ring drawn true, as the witches draw theirs with instruments. With its key held
-- (book_key.lua book_compass_held) the pen sets the compass - pressed where the ring's middle goes and dragged out to its
-- size, the legs opening - then draws along its circle: pressed on the circle and moved along it, the line goes round
-- with the mouse, however far from the line the mouse goes. The compass stays set on its page, to close the ring's gap
-- later or draw a layer round the same middle (pressed by it, the needle goes back in its hole). Here: what the compass
-- does with the mouse, where the pen goes along the circle, and how the compass shows on the page.
--   BookCompass.press( page, x, y )  the button pressed on 'page' at x, y with the key held
--   BookCompass.drag( x, y )         the mouse held at x, y: the points of the line drawn since, along the circle
--   BookCompass.release()            let go
--   BookCompass.draw( s, page, x, y, drawable )  the compass on the page 's' while its key is held, the mouse at x, y

BookCompass = {}
local C = BookCompass
local D = BookDraw
local P = BookPages

local REACH = 8           -- pressed this close to the circle's line (page units), the pen may draw along it ...
local ALONG = 2           -- ... and does once it is moved this far along it; first moved this far off the line ...
local AWAY = REACH        -- ... the press sets the compass anew from there
local HOLE = 5            -- pressed this close to the middle, the needle goes back in its hole
local MIN_RADIUS = 8      -- legs opened less than this set nothing: a click
local STILL = 3           -- the mouse this close to the middle points nowhere: the pen stays where it is
local MAX_TURN = 2 * math.pi + 0.12 -- once round and a little more, the ring closed, the line goes no further
local GUIDE = P.NOTE_COLOR         -- the compass on the paper ...
local NEEDLE = P.TEXT_COLOR         -- ... its needle, and its pen where it touches the line
local GUIDE_Z = 26                  -- over the paper, under the ink (book_draw.lua: the pen's dots lie at 25)

-- { kind = "set", page, x, y, r }: the needle in, the legs opening; { kind = "press", page, x, y }: pressed by the
-- circle, not yet moved; { kind = "line", page, a, start, mouse, mouse_at }: the pen going round - its angle, where it
-- began, the mouse's angle unwound and as it was last frame
C.gesture = nil

local function wrap( a ) return ( a + math.pi ) % ( 2 * math.pi ) - math.pi end

-- the needle goes in at x, y on 'page' - in its hole, if pressed by it
local function set_at( page, x, y )
	local c = page.compass
	if c and ( x - c.x ) ^ 2 + ( y - c.y ) ^ 2 <= HOLE ^ 2 then x, y = c.x, c.y end
	C.gesture = { kind = "set", page = page, x = x, y = y, r = 0 }
end

function C.press( page, x, y )
	local c = page.compass
	if c and math.abs( math.sqrt( ( x - c.x ) ^ 2 + ( y - c.y ) ^ 2 ) - c.r ) <= REACH then
		C.gesture = { kind = "press", page = page, x = x, y = y }
	else
		set_at( page, x, y )
	end
end

-- The pen at the angle 'a' on the circle 'c'
local function on_circle( c, a ) return { x = c.x + c.r * math.cos( a ), y = c.y + c.r * math.sin( a ) } end

-- Returns the points the pen passes, along the circle (the first one where the line begins), or nil
function C.drag( x, y )
	local g = C.gesture
	if not g or g.kind == "set" then
		if g then g.r = math.sqrt( ( x - g.x ) ^ 2 + ( y - g.y ) ^ 2 ) end
		return nil
	end
	local c = g.page.compass
	local d = math.sqrt( ( x - c.x ) ^ 2 + ( y - c.y ) ^ 2 )
	if g.kind == "press" then
		-- pressed by the circle: moved along it, the pen draws; pulled off it, the compass is set anew from the press
		local a0, a = math.atan2( g.y - c.y, g.x - c.x ), math.atan2( y - c.y, x - c.x )
		if math.abs( d - c.r ) > AWAY then
			set_at( g.page, g.x, g.y )
			return C.drag( x, y )
		end
		if math.abs( wrap( a - a0 ) ) * c.r < ALONG then return nil end
		g.kind, g.a, g.start, g.mouse, g.mouse_at = "line", a0, a0, a0, a0
		local out = { on_circle( c, a0 ) }
		for _, p in ipairs( C.drag( x, y ) or {} ) do out[#out + 1] = p end
		return out
	end
	if d < STILL then return nil end
	local m = math.atan2( y - c.y, x - c.x )
	g.mouse = g.mouse + wrap( m - g.mouse_at )
	g.mouse_at = m
	local to = g.start + math.max( -MAX_TURN, math.min( MAX_TURN, g.mouse - g.start ) )
	local n = math.ceil( math.abs( to - g.a ) * c.r )
	local out = {}
	for k = 1, n do out[k] = on_circle( c, g.a + ( to - g.a ) * k / n ) end
	g.a = to
	return out
end

-- Let go: legs opened enough stay set on the page
function C.release()
	local g = C.gesture
	C.gesture = nil
	if g and g.kind == "set" and g.r >= MIN_RADIUS then g.page.compass = { x = g.x, y = g.y, r = g.r } end
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

local function circle_points( x, y, r )
	local out, n = {}, math.max( 24, math.ceil( 2 * math.pi * r / 2 ) )
	for k = 0, n do out[#out + 1] = on_circle( { x = x, y = y, r = r }, k / n * 2 * math.pi ) end
	return out
end

-- the needle's hole: a small cross
local function needle( s, x, y, drawable )
	guide( s, { { x = x - 3, y = y }, { x = x + 3, y = y } }, NEEDLE, 0.9, drawable )
	guide( s, { { x = x, y = y - 3 }, { x = x, y = y + 3 } }, NEEDLE, 0.9, drawable )
end

-- The compass on the page 's' of 'page', the mouse at x, y ('drawable': where the pen draws on it): the needle where it
-- would go in, or set in its hole with the circle dotted round it - the pen's spot on the line when pressing there draws
-- along it; while the legs open, the leg to the mouse and the circle they make
function C.draw( s, page, x, y, drawable )
	local pen, step = s.pen, s.step
	s.pen, s.step = 0.6, 2.4
	local g = C.gesture
	if g and g.kind == "set" then
		needle( s, g.x, g.y, drawable )
		local a = math.atan2( y - g.y, x - g.x )
		guide( s, { { x = g.x, y = g.y }, on_circle( g, a ) }, GUIDE, 0.6, drawable )
		if g.r >= MIN_RADIUS then guide( s, circle_points( g.x, g.y, g.r ), GUIDE, 0.75, drawable ) end
	elseif page.compass then
		local c = page.compass
		needle( s, c.x, c.y, drawable )
		guide( s, circle_points( c.x, c.y, c.r ), GUIDE, 0.75, drawable )
		local d = math.sqrt( ( x - c.x ) ^ 2 + ( y - c.y ) ^ 2 )
		if not g and math.abs( d - c.r ) <= REACH and d > 0 then
			local spot = on_circle( c, math.atan2( y - c.y, x - c.x ) )
			s.pen = 1.4
			guide( s, { spot, spot }, NEEDLE, 0.9, drawable )
		end
	elseif not g then
		needle( s, x, y, drawable )
	end
	s.pen, s.step = pen, step
end
