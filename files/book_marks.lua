-- Marking what lines are (notebook.lua): the book misreads a sign? With "Mark" the witch circles its lines on an
-- unfinished page - a lasso: the lines lying mostly inside it - and picks what they are from what they could be read as
-- (seal.lua seal_mark_readings). The book then reads them as that symbol (stroke.mark, kept with the page by
-- book_store.lua), and how well they are drawn as it still counts. A click on marked lines shows their readings again.
-- A seal that fails on one symbol tells under it what it looks most like, and [Mark] there opens the menu for its lines
-- (BookMarks.draw_doubt, BookMarks.doubt_click).
-- Here: the lasso and the menu (BookMarks.lasso, BookMarks.menu) and how they and the marked lines are drawn;
-- notebook.lua marks the lines picked and reads the seal again (BookMarks.on_pick), and tells what went wrong
-- (BookMarks.tell).

BookMarks = {}
local K = BookMarks
local D = BookDraw
local P = BookPages

local CHOICES = 8     -- readings offered at most
local INSIDE = 0.6    -- a line is circled when this share of its points lies inside the lasso
local CLICK = 8       -- a lasso shorter than this (page units) is a click ...
local REACH = 7       -- ... on marked lines this close to it
local ROW = 13        -- the menu's rows
local GLOW = { 0.78, 0.5, 0.08 }        -- the lines circled or under the mouse, drawn over in this (notebook.lua PART_GLOW)
local PAPER = { 0.95, 0.91, 0.82 }      -- behind words over a drawing (notebook.lua PART_BACK)
local SIGN_HIGHLIGHT = { 0.6, 0.6, 0.64 }   -- the highlighter under lines marked as a sign,
local FRAME_HIGHLIGHT = { 0.52, 0.47, 0.42 } -- as a frame; a sigil's is its element's (highlight_of)
local HIGHLIGHT_TONE = 175                    -- a sigil's color no lighter than this (luminance, 0-255) ...
local HIGHLIGHT_VIVID = 1.8                   -- ... and this much more vivid: pale yellows seen on paper
local EDGE = { 0.45, 0.36, 0.26 }
local OVER = { 0.95, 0.78, 0.4 }

K.lasso = nil -- { page, face, points }: the lasso being drawn, in page units
K.menu = nil  -- { page, face, strokes, items, marked, x, y, rows }: what circled lines may be read as, to pick from
K.on_pick = function( item, menu ) end -- the lines of 'menu' are 'item' (nil: what the book reads them as)
K.tell = function( text ) end          -- what is wrong under the page (nil: nothing)

local function inside_polygon( pts, x, y )
	local inside, j = false, #pts
	for i = 1, #pts do
		local a, b = pts[i], pts[j]
		if ( a.y > y ) ~= ( b.y > y ) and x < ( b.x - a.x ) * ( y - a.y ) / ( b.y - a.y ) + a.x then inside = not inside end
		j = i
	end
	return inside
end

-- the lines of 'page' marked as one symbol with the line nearest x, y, or nil
local function marked_at( page, x, y )
	local best, nearest = nil, REACH ^ 2
	for _, stroke in ipairs( page.strokes ) do
		if stroke.mark then
			for _, p in ipairs( stroke ) do
				local d = ( p.x - x ) ^ 2 + ( p.y - y ) ^ 2
				if d < nearest then best, nearest = stroke, d end
			end
		end
	end
	if not best then return nil end
	local list = {}
	for _, stroke in ipairs( page.strokes ) do
		if stroke.mark == best.mark then list[#list + 1] = stroke end
	end
	return list
end

-- a reading's name ({ kind, key }: a mark or one of seal_mark_readings'): "Light", "Pulling"
function K.name( item )
	if item.kind == "sign" then return DICTIONARY_SIGNS[item.key].name end
	if item.kind == "frame" then return DICTIONARY_FRAMES[item.key].name end
	local def = DICTIONARY_SIGILS[item.key] or {}
	local element = def.element and DICTIONARY_ELEMENTS[def.element]
	return def.name or element and element.name or item.key
end

-- the precision the lines give the seal read as one of seal_mark_readings' (seal_spell.lua compile_spell), 0..1
function K.precision( item )
	local q = item.kind == "frame" and ( item.score - SealRead.FRAME_SCORE ) / 0.25
		or ( item.score - SEAL_MIN_SCORE ) / ( SEAL_GOOD_SCORE - SEAL_MIN_SCORE )
	return math.max( 0, math.min( 1, q ) )
end
local function percent( item ) return math.floor( K.precision( item ) * 100 + 0.5 ) .. "%" end

-- 'lines' (some of the page's 'strokes') still look like 'mark' as well as the menu wants to offer it: partly erased
-- they may not
function K.holds( strokes, lines, mark )
	for _, item in ipairs( seal_mark_readings( strokes, lines, math.huge ) ) do
		if item.kind == mark.kind and item.key == mark.key then return true end
	end
	return false
end

-- The lasso let go: the lines it circled (or the marked ones clicked) get the menu of their readings, opening where it
-- was let go. Returns what is wrong if there is nothing to show.
local function finish( l )
	local pts, length = l.points, 0
	local last = pts[#pts]
	if not last then return nil end
	for k = 2, #pts do length = length + math.sqrt( ( pts[k].x - pts[k - 1].x ) ^ 2 + ( pts[k].y - pts[k - 1].y ) ^ 2 ) end
	local chosen
	if length < CLICK then
		chosen = marked_at( l.page, last.x, last.y )
		if not chosen then return "Circle the lines of one sign or sigil" end
	else
		chosen = {}
		for _, stroke in ipairs( l.page.strokes ) do
			local n = 0
			for _, p in ipairs( stroke ) do
				if inside_polygon( pts, p.x, p.y ) then n = n + 1 end
			end
			if #stroke > 0 and n >= INSIDE * #stroke then chosen[#chosen + 1] = stroke end
		end
		if #chosen == 0 then return "No lines circled - circle all of one sign or sigil" end
	end
	local items = seal_mark_readings( l.page.strokes, chosen, CHOICES )
	local marked = false
	for _, stroke in ipairs( chosen ) do
		if stroke.mark then marked = true end
	end
	if #items == 0 and not marked then return "These lines look like no sign or sigil" end
	K.menu = { page = l.page, face = l.face, strokes = chosen, items = items, marked = marked, x = last.x, y = last.y }
end

-- The lasso on 'page' (on the face 'face') follows the mouse at x, y while the button is held ('down'); let go, it
-- opens the menu, or tells why it opens none
function K.lasso_at( page, face, x, y, down )
	if not K.lasso then K.lasso = { page = page, face = face, points = {} } end
	if down then
		local last = K.lasso.points[#K.lasso.points]
		if not last or ( x - last.x ) ^ 2 + ( y - last.y ) ^ 2 >= 4 then K.lasso.points[#K.lasso.points + 1] = { x = x, y = y } end
		return
	end
	local done = K.lasso
	K.lasso = nil
	K.tell( finish( done ) )
end

-- A click with the menu open closes it; on a reading's row (or the book's own reading back) the lines are that
function K.click( mx, my )
	local menu = K.menu
	K.menu = nil
	for _, row in ipairs( menu and menu.rows or {} ) do
		if mx >= row.x0 and mx <= row.x1 and my >= row.y0 and my < row.y1 then
			if row.kind ~= "cancel" then K.on_pick( row.item, menu ) end
			return
		end
	end
end

---- drawn ----

-- the highlighter's color under lines marked 'mark': a sigil's that of its element (sigils.lua sigil_symbol_color, as
-- the menu shows it), toned down to show on paper
local highlights = {}
local function highlight_of( mark )
	if mark.kind == "sign" then return SIGN_HIGHLIGHT end
	if mark.kind == "frame" then return FRAME_HIGHLIGHT end
	if not highlights[mark.key] then
		local c = sigil_symbol_color( mark.key )
		local grey = 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]
		local v = {}
		for i = 1, 3 do v[i] = math.max( 0, math.min( 255, grey + ( c[i] - grey ) * HIGHLIGHT_VIVID ) ) end
		local k = math.min( 1, HIGHLIGHT_TONE / math.max( 1, 0.299 * v[1] + 0.587 * v[2] + 0.114 * v[3] ) ) / 255
		highlights[mark.key] = { v[1] * k, v[2] * k, v[3] * k }
	end
	return highlights[mark.key]
end

-- an unfinished page's marked lines lie over a highlighter's line
function K.draw_marks( s, strokes )
	local list = {}
	for _, stroke in ipairs( strokes ) do
		if stroke.mark then list[#list + 1] = stroke end
	end
	if #list == 0 then return end
	local pen, step = s.pen, s.step
	s.pen, s.step = 2.5, 1.5
	D.strokes( s, list, function( stroke ) return highlight_of( stroke.mark ), 0.6 end, nil, 27 )
	s.pen, s.step = pen, step
end

local function bounds( strokes )
	local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
	for _, stroke in ipairs( strokes ) do
		for _, p in ipairs( stroke ) do
			minx, maxx = math.min( minx, p.x ), math.max( maxx, p.x )
			miny, maxy = math.min( miny, p.y ), math.max( maxy, p.y )
		end
	end
	return minx, maxx, miny, maxy
end

-- the marked lines of 'page' under the mouse at px, py on the page 's' ('size' big) lit, what they are marked as under them
function K.draw_hover( s, page, px, py, size )
	local list = marked_at( page, px, py )
	if not list then return end
	D.strokes( s, list, function() return GLOW, 1 end, nil, 24 )
	local minx, maxx, miny, maxy = bounds( list )
	local line = "Marked: " .. K.name( list[1].mark ) .. " - click to change"
	local w = GuiGetTextDimensions( D.gui(), line )
	local x = math.max( 2, math.min( size - w - 2, ( minx + maxx - w ) / 2 ) )
	local y = maxy + 3
	if y + 11 > size - 3 then y = miny - 12 end
	s:image( x - 2, y - 1, NOTEBOOK_INK_IMAGE, 19, PAPER, 0.95, ( w + 4 ) / 2, 5.5 )
	s:text( x, y, line, P.TEXT_COLOR, 18 )
end

---- a seal that failed on one symbol ----

K.doubt_at = nil -- where [Mark] lay by a failed seal's lines the frame before: { x0, y0, x1, y1 (screen), page, face, x, y
                 -- (on the page, under it: where the menu opens) }, or nil

-- Under the lines a seal failed on (page.doubt, book_reading.lua): what they look most like - "Column or Dispersion?" -
-- and [Mark]: a click on it opens the menu of their readings (K.doubt_click).
-- 's': the page's surface, lying at 'pos' on the screen; the mouse at px, py on it; 'size': the page's.
function K.draw_doubt( s, page, face, pos, px, py, size )
	local doubt, gui = page.doubt, D.gui()
	local names = {}
	for i, item in ipairs( doubt.items ) do names[i] = K.name( item ) end
	local button = "[Mark]"
	local bw = GuiGetTextDimensions( gui, button )
	-- on one line, or a reading a line where the page is too narrow for it
	local lines = { table.concat( names, " or " ) .. "?" }
	if #names > 1 and GuiGetTextDimensions( gui, lines[1] ) + 4 + bw > size - 6 then lines = { names[1] .. " or", names[2] .. "?" } end
	local w = 0
	for i, line in ipairs( lines ) do w = math.max( w, GuiGetTextDimensions( gui, line ) + ( i == #lines and 4 + bw or 0 ) ) end
	local minx, maxx, miny, maxy = bounds( doubt.strokes )
	local h = 11 * #lines
	local x = math.max( 2, math.min( size - w - 2, ( minx + maxx - w ) / 2 ) )
	-- under the lines, or over them where it hides less of the drawing (or there is no room under them)
	local mine = {}
	for _, stroke in ipairs( doubt.strokes ) do mine[stroke] = true end
	local function hides( top )
		local n = 0
		for _, stroke in ipairs( page.strokes ) do
			for _, p in ipairs( mine[stroke] and {} or stroke ) do
				if p.x >= x - 2 and p.x <= x + w + 2 and p.y >= top - 1 and p.y <= top + h then n = n + 1 end
			end
		end
		return n
	end
	local y, over_them = maxy + 3, miny - h - 1
	if over_them >= 3 and ( y + h > size - 3 or hides( over_them ) < hides( y ) ) then y = over_them end
	s:image( x - 2, y - 1, NOTEBOOK_INK_IMAGE, 19, PAPER, 0.95, ( w + 4 ) / 2, h / 2 )
	for i, line in ipairs( lines ) do s:text( x, y + 11 * ( i - 1 ), line, P.TEXT_COLOR, 18 ) end
	local bx, by = x + GuiGetTextDimensions( gui, lines[#lines] ) + 4, y + 11 * ( #lines - 1 )
	local over = px >= bx - 2 and px <= bx + bw + 2 and py >= by - 2 and py <= by + 10
	if over then D.strokes( s, doubt.strokes, function() return GLOW, 1 end, nil, 24 ) end
	s:text( bx, by, button, over and GLOW or P.TITLE_COLOR, 18 )
	K.doubt_at = { x0 = pos.x + bx - 2, y0 = pos.y + by - 2, x1 = pos.x + bx + bw + 2, y1 = pos.y + by + 10, page = page,
		face = face, x = bx, y = by + 10 }
end

-- A click at mx, my on the screen: on [Mark] by a failed seal's lines, the menu of what they may be read as opens there.
-- Returns whether it took the click.
function K.doubt_click( mx, my )
	local at = K.doubt_at
	if not at or not at.page.doubt or mx < at.x0 or mx > at.x1 or my < at.y0 or my > at.y1 then return false end
	local page, lines = at.page, at.page.doubt.strokes
	local marked = false
	for _, stroke in ipairs( lines ) do
		if stroke.mark then marked = true end
	end
	K.menu = { page = page, face = at.face, strokes = lines, items = seal_mark_readings( page.strokes, lines, CHOICES ),
		marked = marked, x = at.x, y = at.y }
	return true
end

-- the lasso being drawn on the page 's': a dotted line round what it circles, closed back to its start
function K.draw_lasso( s )
	local points = K.lasso and K.lasso.points
	if not points or #points < 2 then return end
	local line = {}
	for k, p in ipairs( points ) do line[k] = p end
	line[#line + 1] = points[1]
	local step = s.step
	s.step = 2.5
	D.strokes( s, { line }, function() return GLOW, 0.9 end, nil, 17 )
	s.step = step
end

-- The menu, its page lying at 'pos' ('s' its surface) and the book's pages within the screen's 'bounds' { x0, y0, x1, y1 }:
-- each reading's picture as the lines lie, its name, how well they are drawn as it (the precision it gives); the book's
-- own reading back (lines marked before), and Cancel. The rows are kept for the next frame's click (K.click).
function K.draw_menu( s, pos, bounds, mx, my )
	local menu = K.menu
	local gui = D.gui()
	D.strokes( s, menu.strokes, function() return GLOW, 1 end, nil, 24 )
	local mark = menu.strokes[1].mark
	local rows = {}
	for _, item in ipairs( menu.items ) do
		local current = mark and mark.kind == item.kind and mark.key == item.key
		rows[#rows + 1] = { kind = "item", item = item, text = ( current and "* " or "" ) .. K.name( item ),
			note = item.kind .. " " .. percent( item ) }
	end
	if menu.marked then rows[#rows + 1] = { kind = "unmark", text = "As the book reads it" } end
	rows[#rows + 1] = { kind = "cancel", text = "Cancel" }
	local title = "These lines are:"
	local w = GuiGetTextDimensions( gui, title ) + 8
	for _, row in ipairs( rows ) do
		w = math.max( w, 22 + GuiGetTextDimensions( gui, row.text ) + ( row.note and 8 + GuiGetTextDimensions( gui, row.note ) or 0 ) )
	end
	local h = 14 + ROW * #rows + 3
	-- by where the lasso was let go, on the book's pages
	local x = math.floor( math.max( bounds.x0, math.min( bounds.x1 - w, pos.x + menu.x + 6 ) ) )
	local y = math.floor( math.max( bounds.y0, math.min( bounds.y1 - h, pos.y + menu.y - 6 ) ) )
	D.rect( x - 1, y - 1, w + 2, h + 2, EDGE, 8, 0.9 )
	D.rect( x, y, w, h, PAPER, 7, 0.98 )
	D.text( x + 4, y + 2, title, P.NOTE_COLOR, 4 )
	for i, row in ipairs( rows ) do
		local ry = y + 14 + ( i - 1 ) * ROW
		row.x0, row.y0, row.x1, row.y1 = x, ry, x + w, ry + ROW
		if mx >= x and mx <= x + w and my >= ry and my < ry + ROW then D.rect( x + 1, ry, w - 2, ROW, OVER, 6, 0.45 ) end
		local item = row.item
		if item then
			-- a sign stands at the bottom of the ring in its template: here it lies where the lines are
			local turn = item.tilt + ( item.kind == "sign" and item.angle - math.pi / 2 or 0 )
			local color = item.kind == "sigil" and paper_of( sigil_symbol_color( item.key ) ) or P.INK_COLOR
			P.glyph( D.SCREEN, item.kind, item.key, x + 9, ry + ROW / 2, 10, turn, item.mirror, color, 4 )
		end
		D.text( x + 18, ry + 2, row.text, row.kind == "item" and P.TEXT_COLOR or P.NOTE_COLOR, 4 )
		if row.note then D.text( x + w - 4 - GuiGetTextDimensions( gui, row.note ), ry + 2, row.note, P.NOTE_COLOR, 4 ) end
	end
	menu.rows = rows
end
