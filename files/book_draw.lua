-- Drawing the books (notebook.lua): GUI calls with a depth and a color, text that fits, soft shadows, and a page's
-- surface - where on the screen a point of a page is. A page lying open is flat (here); a turning page bends
-- (page_turn.lua), and whatever is on it bends with it: both surfaces draw the pen's dots, images and text; a flat one
-- draws dots in a row as one image, a stamp (D.strokes).
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

-- The pen's dots in a row are drawn as few images as can be: as stamps - the dots of a short straight piece of line,
-- made at init (D.create_stamps) in a few lengths and many directions - where the dots lie as a stamp has them, else
-- one by one: a frame of a page of many lines would be thousands of images. Only on a flat page (lying still, or under a
-- sheet turning over it), with the book's pen, in an ink that hides the paper (a fainter ink's dots darken where they
-- overlap, a stamp's wouldn't).
local STAMP_DOTS = { 16, 8, 6, 4, 3, 2 } -- stamps of this many dots in a row, the longest tried first ...
local STAMP_ANGLES = 32        -- ... turned to this many directions over half a turn
local STAMP_OFF = 0.15         -- a dot no farther than this from where the stamp has it (gui units)
local stamps                   -- [dots][direction] = { file, w, h (gui units) }, once made
local STAMP_COS, STAMP_SIN = {}, {}
for k = 0, STAMP_ANGLES - 1 do STAMP_COS[k], STAMP_SIN[k] = math.cos( k * math.pi / STAMP_ANGLES ), math.sin( k * math.pi / STAMP_ANGLES ) end

-- At init: each stamp as its dots drawn one over another would be - each lets through what is under it but for its
-- share of the texel, the pen's dot's (sigils.lua: 4x4 samples)
function D.create_stamps()
	local res = NOTEBOOK_BRUSH_RES
	stamps = {}
	for _, m in ipairs( STAMP_DOTS ) do
		stamps[m] = {}
		local half = ( m - 1 ) * DOT_STEP / 2
		for k = 0, STAMP_ANGLES - 1 do
			local ca, sa = STAMP_COS[k], STAMP_SIN[k]
			-- an even number of texels round the line's middle, the dot's radius beyond its ends
			local w, h = 2 * math.ceil( ( half * math.abs( ca ) + 1 ) * res ), 2 * math.ceil( ( half * math.abs( sa ) + 1 ) * res )
			local file = "mods/witch_notebook/files/gfx/stamp_" .. m .. "_" .. k .. ".png"
			local id = ModImageMakeEditable( file, w, h )
			for py = 0, h - 1 do
				for px = 0, w - 1 do
					local through = 1
					for j = 0, m - 1 do
						local t = ( j - ( m - 1 ) / 2 ) * DOT_STEP * res
						local cx, cy = w / 2 + t * ca, h / 2 + t * sa
						if ( px + 0.5 - cx ) ^ 2 + ( py + 0.5 - cy ) ^ 2 <= ( res + 1 ) ^ 2 then
							local inside = 0
							for sy = 0, 3 do
								for sx = 0, 3 do
									if ( px + ( sx + 0.5 ) / 4 - cx ) ^ 2 + ( py + ( sy + 0.5 ) / 4 - cy ) ^ 2 <= res * res then inside = inside + 1 end
								end
							end
							through = through * ( 1 - math.floor( inside * 255 / 16 + 0.5 ) / 255 )
						end
					end
					ModImageSetPixel( id, px, py, color_abgr_merge( 255, 255, 255, math.floor( ( 1 - through ) * 255 + 0.5 ) ) )
				end
			end
			stamps[m][k] = { file = file, w = w / res, h = h / res }
		end
	end
end

-- 'n' of the pen's dots in a row ('row': x1, y1, x2, y2, ... on the page) in 'color', opaque
function Flat:stamps( row, n, color, z )
	local i = 1
	while i <= n do
		local drawn = false
		for _, m in ipairs( STAMP_DOTS ) do
			local j = i + m - 1
			if j <= n then
				local x0, y0, x1, y1 = row[2 * i - 1], row[2 * i], row[2 * j - 1], row[2 * j]
				local k = math.floor( math.atan2( y1 - y0, x1 - x0 ) % math.pi / ( math.pi / STAMP_ANGLES ) + 0.5 ) % STAMP_ANGLES
				local ca, sa = STAMP_COS[k], STAMP_SIN[k]
				if ( x1 - x0 ) * ca + ( y1 - y0 ) * sa < 0 then ca, sa = -ca, -sa end -- the row runs the other way
				local mx, my = ( x0 + x1 ) / 2, ( y0 + y1 ) / 2
				local fits = true
				for q = 0, m - 1 do
					local t = ( q - ( m - 1 ) / 2 ) * DOT_STEP
					if ( row[2 * ( i + q ) - 1] - mx - t * ca ) ^ 2 + ( row[2 * ( i + q )] - my - t * sa ) ^ 2 > STAMP_OFF ^ 2 then
						fits = false
						break
					end
				end
				if fits then
					local stamp = stamps[m][k]
					local x, y = self.x + mx - stamp.w / 2, self.y + my - stamp.h / 2
					-- under a sheet in the air it isn't drawn (one partly under it is: the sheet's paper lies over it)
					if not ( D.covered and self:hidden( x, y, x + stamp.w, y + stamp.h ) ) then
						GuiZSetForNextWidget( gui, z or 25 )
						GuiColorSetForNextWidget( gui, color[1], color[2], color[3], 1 )
						GuiImage( gui, D.next_id(), x, y, stamp.file, 1, 1 / NOTEBOOK_BRUSH_RES )
					end
					i, drawn = j + 1, true
					break
				end
			end
		end
		if not drawn then
			self:dot( row[2 * i - 1], row[2 * i], color, 1, z )
			i = i + 1
		end
	end
end

local ROW = {} -- the dots of the stretch of line being drawn: x1, y1, x2, y2, ...

-- the 'n' dots in ROW: as stamps ('stamped'), or one by one
local function draw_row( s, n, stamped, color, alpha, z )
	if stamped then return s:stamps( ROW, n, color, z ) end
	for i = 1, n do s:dot( ROW[2 * i - 1], ROW[2 * i], color, alpha, z ) end
end

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
	local stamping = stamps ~= nil and s.stamps ~= nil and step == DOT_STEP and ( s.pen or 1 ) == 1
	for _, stroke in ipairs( list ) do
		local color, alpha = look( stroke, element_color, ink_key )
		local stamped = stamping and ( alpha or 1 ) >= 1
		local n = 0
		local lx, ly
		local left = 0 -- how far along the line the next dot is
		for _, p in ipairs( stroke ) do
			if p.erased then
				draw_row( s, n, stamped, color, alpha, z )
				n, lx, ly, left = 0, nil, nil, 0
			else
				local x, y = to + ( p.x - c ) * k, to + ( p.y - c ) * ky
				if lx then
					local d = math.sqrt( ( x - lx ) ^ 2 + ( y - ly ) ^ 2 )
					local at = left
					while at <= d do
						local t = at / d
						n = n + 1
						ROW[2 * n - 1], ROW[2 * n] = lx + ( x - lx ) * t, ly + ( y - ly ) * t
						at = at + step
					end
					left = at - d
				else
					n = n + 1
					ROW[2 * n - 1], ROW[2 * n] = x, y
					left = step
				end
				lx, ly = x, y
			end
		end
		if lx and left < step - 0.05 then -- the stroke's very end
			n = n + 1
			ROW[2 * n - 1], ROW[2 * n] = lx, ly
		end
		draw_row( s, n, stamped, color, alpha, z )
	end
end
