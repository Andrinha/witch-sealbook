-- Drawing the books (notebook.lua): GUI calls with a depth and a color, text that fits, soft shadows, and a page's
-- surface - where on the screen a point of a page is. A page lying open is flat (here); a turning page bends
-- (page_turn.lua), and whatever is on it bends with it: both surfaces draw the pen's dots, images and text.
-- Depth (z): the smaller, the nearer - the turning sheets lie over the pages, the pages over the cover.

BookDraw = {}
local D = BookDraw

local gui
local widget_id = 0

-- every frame, before drawing: widgets need ids that stay the same from frame to frame, the images count from 1
function D.begin( g )
	gui = g
	widget_id = 1
end
function D.gui() return gui end
function D.next_id()
	widget_id = widget_id + 1
	return widget_id
end

function D.text( x, y, str, color, z, alpha, scale )
	GuiZSetForNextWidget( gui, z or 20 )
	if color then GuiColorSetForNextWidget( gui, color[1], color[2], color[3], alpha or 1 ) end
	GuiText( gui, x, y, str, scale or 1 )
	return GuiGetTextDimensions( gui, str, scale or 1 )
end

function D.image( x, y, file, z, color, alpha, sx, sy )
	GuiZSetForNextWidget( gui, z )
	if color then GuiColorSetForNextWidget( gui, color[1], color[2], color[3], alpha or 1 ) end
	GuiImage( gui, D.next_id(), x, y, file, alpha or 1, sx or 1, sy or sx or 1 )
end

function D.rect( x, y, w, h, color, z, alpha )
	-- NOTEBOOK_INK_IMAGE is 2x2
	D.image( x, y, NOTEBOOK_INK_IMAGE, z, color, alpha, w / 2, h / 2 )
end

-- A soft shadow 'w' long falling away from x to the right (w > 0) or to the left (w < 0), 'h' high; 'vertical': falling
-- away from y downwards (w > 0) or upwards, 'h' wide. 'soft': its ends fade out too.
local SHADE_COLOR = { 0.12, 0.07, 0.03 }
D.SHADE_COLOR = SHADE_COLOR
function D.shadow( x, y, w, h, alpha, z, soft, vertical )
	if math.abs( w ) < 0.5 or alpha <= 0.01 then return end
	local k = math.abs( w ) / 16
	if vertical then
		D.image( x, w > 0 and y or y + w, w > 0 and BOOK_SHADE_DOWN_IMAGE or BOOK_SHADE_UP_IMAGE, z, SHADE_COLOR, alpha, h, k )
		return
	end
	local x0, right = w > 0 and x or x + w, w < 0
	local fade = soft and math.min( 10, h / 2 ) or 0
	if fade > 0 then
		D.image( x0, y, book_shade_end_image( right, false ), z, SHADE_COLOR, alpha, k, fade / BOOK_SHADE_END_H )
		D.image( x0, y + h - fade, book_shade_end_image( right, true ), z, SHADE_COLOR, alpha, k, fade / BOOK_SHADE_END_H )
	end
	if h - 2 * fade > 0 then
		D.image( x0, y + fade, right and BOOK_SHADE_R_IMAGE or BOOK_SHADE_IMAGE, z, SHADE_COLOR, alpha, k, h - 2 * fade )
	end
end

---- text ----

local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"
D.UTF8_CHAR = UTF8_CHAR

-- 'str' cut to fit 'width', with dots where it was cut (a long name of a composed seal)
local fit_cache = {}
function D.fitted( str, width )
	if GuiGetTextDimensions( gui, str ) <= width then return str end
	local key = width .. "|" .. str
	if fit_cache[key] then return fit_cache[key] end
	local chars = {}
	for ch in str:gmatch( UTF8_CHAR ) do chars[#chars + 1] = ch end
	while #chars > 0 and GuiGetTextDimensions( gui, table.concat( chars ) .. "..." ) > width do table.remove( chars ) end
	fit_cache[key] = table.concat( chars ):gsub( "[%s,]+$", "" ) .. "..."
	return fit_cache[key]
end

function D.centered( x, width, y, str, color, margin )
	str = D.fitted( str, width - ( margin or 8 ) )
	D.text( x + ( width - GuiGetTextDimensions( gui, str ) ) / 2, y, str, color )
end

-- Text wrapped into lines no wider than 'width' onto a surface; returns the y below it
function D.wrapped( s, x, y, width, str, color, step )
	local line = ""
	for word in str:gmatch( "%S+" ) do
		local try = line == "" and word or ( line .. " " .. word )
		if line ~= "" and GuiGetTextDimensions( gui, try ) > width then
			s:text( x, y, line, color )
			y = y + ( step or 10 )
			line = word
		else
			line = try
		end
	end
	if line ~= "" then s:text( x, y, line, color ); y = y + ( step or 10 ) end
	return y
end

-- a letter's code point (BOOK_GLYPHS: the text on a turning page is drawn letter by letter)
function D.code_point( ch )
	local b = ch:byte( 1 )
	if b < 0x80 then return b end
	local n = b >= 0xF0 and 3 or b >= 0xE0 and 2 or 1
	local code = b % ( 2 ^ ( 6 - n ) )
	for k = 2, n + 1 do code = code * 64 + ( ch:byte( k ) or 0x80 ) % 64 end
	return code
end

---- a page lying flat ----

-- While pages turn: the stretches along the way they turn (x, or y for the quire's leaves) that the sheets lying in the
-- air cover - what lies there on the pages beneath is not drawn. { vertical, spans = { { a0, a1 } } } or nil.
D.covered = nil
local function is_covered( a0, a1 )
	local c = D.covered
	if not c then return false end
	for _, span in ipairs( c.spans ) do
		if a0 >= span[1] and a1 <= span[2] then return true end
	end
	return false
end

local Flat = {}
Flat.__index = Flat
D.SCREEN = setmetatable( { x = 0, y = 0 }, Flat )

-- the page of the book 'def' with its top left at x, y
function D.flat( x, y, def, front )
	return setmetatable( { x = x, y = y, def = def, front = front, size = def.page }, Flat )
end
-- the stretch of the screen x0..x1, y0..y1 lies under a sheet in the air
function Flat:hidden( x0, y0, x1, y1 )
	if not D.covered then return false end
	if D.covered.vertical then return is_covered( y0, y1 ) end
	return is_covered( x0, x1 )
end
function Flat:image( px, py, file, z, color, alpha, sx, sy ) D.image( self.x + px, self.y + py, file, z, color, alpha, sx, sy ) end
function Flat:dot( px, py, color, alpha, z )
	local x, y = self.x + px, self.y + py
	if D.covered and self:hidden( x - 1, y - 1, x + 1, y + 1 ) then return end
	local w = self.pen or 1 -- the dot's radius: 1, a finer pen for the guide's sketches (book_pages.lua)
	GuiZSetForNextWidget( gui, z or 25 )
	GuiColorSetForNextWidget( gui, color[1], color[2], color[3], alpha or 1 )
	GuiImage( gui, D.next_id(), x - w, y - w, NOTEBOOK_BRUSH_IMAGE, alpha or 1, w / NOTEBOOK_BRUSH_RES )
end
function Flat:text( px, py, str, color, z, scale )
	local w = GuiGetTextDimensions( gui, str, scale or 1 )
	if D.covered and self:hidden( self.x + px, self.y + py, self.x + px + w, self.y + py + 9 ) then return w end
	return D.text( self.x + px, self.y + py, str, color, z, nil, scale )
end
function Flat:page( kind )
	if D.covered and self:hidden( self.x, self.y, self.x + self.size, self.y + self.size ) then return end
	D.image( self.x, self.y, book_page_image( self.def, kind, self.front ), 30 )
end

---- what is drawn on a page, onto any surface ----

local DOT_STEP = 0.7 -- the pen's dots this far apart along a line on the page: a smooth, unbroken line

-- A drawing on the page 's', exactly as it was drawn: each stroke in its ink's color ('color' replaces the conjuring
-- ink's, 'ink_key' is the ink of every stroke: a sheet's). Its points are the page's, or with 'frame' { c, k, ky, to }
-- points around c scaled by k (up and down by ky, if given) around 'to' (the grimoire's pages, drawn on the Spellbook's
-- page, shown on a book of another size; a drawing showing through a leaf's back, mirrored). 'look': stroke, color,
-- element color, ink key -> color, alpha. Dots go evenly along each stroke, however far apart its points lie (a seal's
-- lighter copy, the grimoire's).
function D.strokes( s, list, look, element_color, z, ink_key, frame )
	local step = s.step or DOT_STEP
	local c, k, ky, to = 0, 1, 1, 0
	if frame then c, k, ky, to = frame.c, frame.k, frame.ky or frame.k, frame.to end
	for _, stroke in ipairs( list ) do
		local color, alpha = look( stroke, element_color, ink_key )
		local lx, ly
		local left = 0 -- how far along the line the next dot is
		for _, p in ipairs( stroke ) do
			if p.erased then
				lx, ly, left = nil, nil, 0
			else
				local x, y = to + ( p.x - c ) * k, to + ( p.y - c ) * ky
				if lx then
					local d = math.sqrt( ( x - lx ) ^ 2 + ( y - ly ) ^ 2 )
					local at = left
					while at <= d do
						local t = at / d
						s:dot( lx + ( x - lx ) * t, ly + ( y - ly ) * t, color, alpha, z )
						at = at + step
					end
					left = at - d
				else
					s:dot( x, y, color, alpha, z )
					left = step
				end
				lx, ly = x, y
			end
		end
		if lx and left < step - 0.05 then s:dot( lx, ly, color, alpha, z ) end -- the stroke's very end
	end
end
