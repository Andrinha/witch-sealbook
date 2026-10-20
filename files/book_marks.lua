-- Marking what lines are (notebook.lua): the book misreads a sign? With "Mark" the witch circles its lines on an
-- unfinished page - a lasso: the lines lying mostly inside it - and picks what they are from what they could be read as
-- (seal.lua seal_mark_readings). The book then reads them as that symbol (stroke.mark, kept with the page by
-- book_store.lua), and how well they are drawn as it still counts. A click on marked lines shows their readings again.
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
local HIGHLIGHT = { 0.5, 0.72, 0.95 }   -- the highlighter under marked lines
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

-- an unfinished page's marked lines lie over a highlighter's line
function K.draw_marks( s, strokes )
	local list = {}
	for _, stroke in ipairs( strokes ) do
		if stroke.mark then list[#list + 1] = stroke end
	end
	if #list == 0 then return end
	local pen, step = s.pen, s.step
	s.pen, s.step = 2.5, 1.5
	D.strokes( s, list, function() return HIGHLIGHT, 0.6 end, nil, 27 )
	s.pen, s.step = pen, step
end

-- the marked lines of 'page' under the mouse at px, py on the page 's' ('size' big) lit, what they are marked as under them
function K.draw_hover( s, page, px, py, size )
	local list = marked_at( page, px, py )
	if not list then return end
	D.strokes( s, list, function() return GLOW, 1 end, nil, 24 )
	local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
	for _, stroke in ipairs( list ) do
		for _, p in ipairs( stroke ) do
			minx, maxx = math.min( minx, p.x ), math.max( maxx, p.x )
			miny, maxy = math.min( miny, p.y ), math.max( maxy, p.y )
		end
	end
	local line = "Marked: " .. K.name( list[1].mark ) .. " - click to change"
	local w = GuiGetTextDimensions( D.gui(), line )
	local x = math.max( 2, math.min( size - w - 2, ( minx + maxx - w ) / 2 ) )
	local y = maxy + 3
	if y + 11 > size - 3 then y = miny - 12 end
	s:image( x - 2, y - 1, NOTEBOOK_INK_IMAGE, 19, PAPER, 0.95, ( w + 4 ) / 2, 5.5 )
	s:text( x, y, line, P.TEXT_COLOR, 18 )
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
		-- the precision the lines give the seal as it (seal_spell.lua compile_spell)
		local q = item.kind == "frame" and ( item.score - SealRead.FRAME_SCORE ) / 0.25
			or ( item.score - SEAL_MIN_SCORE ) / ( SEAL_GOOD_SCORE - SEAL_MIN_SCORE )
		q = math.max( 0, math.min( 1, q ) )
		local current = mark and mark.kind == item.kind and mark.key == item.key
		rows[#rows + 1] = { kind = "item", item = item, text = ( current and "* " or "" ) .. K.name( item ),
			note = item.kind .. " " .. math.floor( q * 100 + 0.5 ) .. "%" }
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
