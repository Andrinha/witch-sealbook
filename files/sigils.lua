-- Spellbook images: the pages and the legend. What sigils and signs mean is in dictionary.lua, their
-- shapes in templates.lua.

SIGIL_NEUTRAL_COLOR = { 230, 200, 120 } -- icon color of a seal without an element

-- the grimoire's seals (grimoire.lua) are drawn on a page this big, their ring around its middle 70 big: the
-- Spellbook's page; the other books scale them to their own (books.lua), and the seals drawn in them to it (notebook.lua)
SEAL_PAGE_SIZE = 180
NOTEBOOK_INK_IMAGE = "mods/witch_notebook/files/gfx/ink.png"
-- the pen's dot: a round, smooth-edged dot 2 gui units wide, BRUSH_RES texels per unit (the screen shows 3-4 pixels
-- per gui unit, so the dot is drawn finer than the gui's own pixels)
NOTEBOOK_BRUSH_IMAGE = "mods/witch_notebook/files/gfx/brush.png"
NOTEBOOK_BRUSH_RES = 4
NOTEBOOK_ERASER_IMAGE = "mods/witch_notebook/files/gfx/eraser_ring.png"
NOTEBOOK_TARGET_IMAGE = "mods/witch_notebook/files/gfx/target.png"
AWAKEN_GLOW_IMAGE = "mods/witch_notebook/files/gfx/awaken_glow.png" -- a soft round light (awaken.lua)
AWAKEN_GLOW_SIZE = 16

function legend_path( key )
	return "mods/witch_notebook/files/gfx/legend_" .. key .. ".png"
end

-- Strokes <-> icon encoding: about 48 points fitted into the 16x16 icon, one hex digit per
-- coordinate, strokes separated by "|"
function sigil_encode( strokes )
	local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
	local total = 0
	for _, stroke in ipairs( strokes ) do
		total = total + #stroke
		for _, p in ipairs( stroke ) do
			minx = math.min( minx, p.x ); maxx = math.max( maxx, p.x )
			miny = math.min( miny, p.y ); maxy = math.max( maxy, p.y )
		end
	end
	local w, h = maxx - minx, maxy - miny
	local s = 11 / math.max( w, h, 0.0001 )
	local ox = 2 + ( 11 - w * s ) / 2
	local oy = 2 + ( 11 - h * s ) / 2
	local function encode_point( p )
		return string.format( "%x%x", math.floor( ox + ( p.x - minx ) * s + 0.5 ), math.floor( oy + ( p.y - miny ) * s + 0.5 ) )
	end

	local step = math.max( 1, math.ceil( total / 48 ) )
	local encoded = {}
	for _, stroke in ipairs( strokes ) do
		local out = {}
		for i = 1, #stroke, step do out[#out + 1] = encode_point( stroke[i] ) end
		out[#out + 1] = encode_point( stroke[#stroke] )
		encoded[#encoded + 1] = table.concat( out )
	end
	return table.concat( encoded, "|" )
end

local function rgba( r, g, b, a )
	return color_abgr_merge( math.floor( r ), math.floor( g ), math.floor( b ), a or 255 )
end

local function draw_line( id, x0, y0, x1, y1, color )
	local dx, dy = math.abs( x1 - x0 ), -math.abs( y1 - y0 )
	local sx = x0 < x1 and 1 or -1
	local sy = y0 < y1 and 1 or -1
	local err = dx + dy
	while true do
		ModImageSetPixel( id, x0, y0, color )
		if x0 == x1 and y0 == y1 then break end
		local e2 = 2 * err
		if e2 >= dy then err = err + dy; x0 = x0 + sx end
		if e2 <= dx then err = err + dx; y0 = y0 + sy end
	end
end

function sigil_draw_icon( id, color, encoded )
	local r, g, b = color[1], color[2], color[3]
	local bg = rgba( r * 0.2, g * 0.2, b * 0.2 )
	local rim = rgba( r * 0.55, g * 0.55, b * 0.55 )
	local ink = rgba( r + ( 255 - r ) * 0.35, g + ( 255 - g ) * 0.35, b + ( 255 - b ) * 0.35 )

	for y = 0, 15 do
		for x = 0, 15 do
			local d = math.sqrt( ( x - 7.5 ) ^ 2 + ( y - 7.5 ) ^ 2 )
			local c = 0
			if d <= 7.6 then c = ( d > 6.7 ) and rim or bg end
			ModImageSetPixel( id, x, y, c )
		end
	end

	for stroke in encoded:gmatch( "[^|]+" ) do
		local px, py
		for i = 1, #stroke - 1, 2 do
			local x = tonumber( stroke:sub( i, i ), 16 )
			local y = tonumber( stroke:sub( i + 1, i + 1 ), 16 )
			if px then draw_line( id, px, py, x, y, ink ) else ModImageSetPixel( id, x, y, ink ) end
			px, py = x, y
		end
	end
end

-- the color of a seal's ink: its element's, "neutral" and unknown keys - SIGIL_NEUTRAL_COLOR
function sigil_icon_color( color_key )
	local element = DICTIONARY_ELEMENTS[color_key]
	return element and element.color or SIGIL_NEUTRAL_COLOR
end

-- a center symbol's legend color: its element's; the ways of manifesting of their own violet, the sculptures teal
SIGIL_SPECIAL_COLOR = { 200, 150, 255 }
SIGIL_SCULPTURE_COLOR = { 110, 220, 200 }
function sigil_symbol_color( key )
	local def = DICTIONARY_SIGILS[key] or {}
	if def.shape then return SIGIL_SCULPTURE_COLOR end
	if def.manifest or def.behavior then return SIGIL_SPECIAL_COLOR end
	return sigil_icon_color( def.element )
end

-- template shape ({ x, y } pairs) -> strokes of { x = , y = }
local function shape_strokes( shape )
	local strokes = {}
	for i, stroke in ipairs( shape ) do
		strokes[i] = {}
		for j, p in ipairs( stroke ) do strokes[i][j] = { x = p[1], y = p[2] } end
	end
	return strokes
end

-- A picture drawn squeezed or stretched (on a turning page) is blended with its transparent pixels, and black ones would
-- edge it with a dark rim: a transparent pixel takes the color of the opaque ones beside it (still transparent)
function image_bleed( id, w, h )
	local px = {}
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local c = ModImageGetPixel( id, x, y )
			px[y * w + x] = c < 0 and c + 4294967296 or c
		end
	end
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			if math.floor( px[y * w + x] / 16777216 ) == 0 then
				local r, g, b, n = 0, 0, 0, 0
				for dy = -1, 1 do
					for dx = -1, 1 do
						local c = ( x + dx >= 0 and x + dx < w and y + dy >= 0 and y + dy < h ) and px[( y + dy ) * w + x + dx] or 0
						if math.floor( c / 16777216 ) > 0 then
							r, g, b, n = r + c % 256, g + math.floor( c / 256 ) % 256, b + math.floor( c / 65536 ) % 256, n + 1
						end
					end
				end
				if n > 0 then ModImageSetPixel( id, x, y, color_abgr_merge( math.floor( r / n ), math.floor( g / n ), math.floor( b / n ), 0 ) ) end
			end
		end
	end
end

-- Pictures cut into columns one texel wide, so that on a page turning sideways they bend with the paper
-- (page_turn.lua Curl:image): file -> { w = width, h = height, [x] = the column's file }
NOTEBOOK_COLUMNS = {}
function image_cut_columns( file, id, w, h )
	local columns = { w = w, h = h }
	for x = 0, w - 1 do
		columns[x] = ( file:gsub( "%.png$", "_col" .. x .. ".png" ) )
		local column = ModImageMakeEditable( columns[x], 1, h )
		for y = 0, h - 1 do ModImageSetPixel( column, 0, y, ModImageGetPixel( id, x, y ) ) end
	end
	NOTEBOOK_COLUMNS[file] = columns
end

function sigils_create_images()
	local ink = ModImageMakeEditable( NOTEBOOK_INK_IMAGE, 2, 2 )
	for y = 0, 1 do for x = 0, 1 do ModImageSetPixel( ink, x, y, rgba( 255, 255, 255 ) ) end end

	-- the pen's dot: each texel as opaque as the share of it inside the circle (4x4 samples)
	local n = 2 * NOTEBOOK_BRUSH_RES
	local brush = ModImageMakeEditable( NOTEBOOK_BRUSH_IMAGE, n, n )
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			local inside = 0
			for sy = 0, 3 do
				for sx = 0, 3 do
					local dx, dy = x + ( sx + 0.5 ) / 4 - n / 2, y + ( sy + 0.5 ) / 4 - n / 2
					if dx * dx + dy * dy <= ( n / 2 ) ^ 2 then inside = inside + 1 end
				end
			end
			ModImageSetPixel( brush, x, y, rgba( 255, 255, 255, math.floor( inside * 255 / 16 + 0.5 ) ) )
		end
	end

	-- The eraser cursor outlines its circular hit area (radius 6 gui units) with a one-unit ring.
	local eraser_size = 14 * NOTEBOOK_BRUSH_RES
	local eraser = ModImageMakeEditable( NOTEBOOK_ERASER_IMAGE, eraser_size, eraser_size )
	local center = eraser_size / 2
	local radius = 6 * NOTEBOOK_BRUSH_RES
	local half_width = NOTEBOOK_BRUSH_RES / 2
	for y = 0, eraser_size - 1 do
		for x = 0, eraser_size - 1 do
			local dx, dy = x + 0.5 - center, y + 0.5 - center
			local distance = math.sqrt( dx * dx + dy * dy )
			local outer = math.min( 1, math.max( 0, radius + half_width + 0.5 - distance ) )
			local inner = math.min( 1, math.max( 0, distance - radius + half_width + 0.5 ) )
			ModImageSetPixel( eraser, x, y, rgba( 255, 255, 255, math.floor( 255 * outer * inner + 0.5 ) ) )
		end
	end

	-- a soft round light, white to its transparent rim: drawn scaled, it gets no dark edge
	local n = AWAKEN_GLOW_SIZE
	local glow = ModImageMakeEditable( AWAKEN_GLOW_IMAGE, n, n )
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			local d = math.sqrt( ( x + 0.5 - n / 2 ) ^ 2 + ( y + 0.5 - n / 2 ) ^ 2 ) / ( n / 2 )
			ModImageSetPixel( glow, x, y, rgba( 255, 255, 255, math.floor( 255 * math.max( 0, 1 - d ) ^ 1.6 + 0.5 ) ) )
		end
	end

	-- 11x11 red cross with a white outline for mouse calibration
	local target = ModImageMakeEditable( NOTEBOOK_TARGET_IMAGE, 11, 11 )
	for y = 0, 10 do
		for x = 0, 10 do
			local dx, dy = math.abs( x - 5 ), math.abs( y - 5 )
			local c = 0
			if math.min( dx, dy ) <= 1 then c = rgba( 255, 255, 255 ) end
			if math.min( dx, dy ) == 0 then c = rgba( 230, 30, 30 ) end
			ModImageSetPixel( target, x, y, c )
		end
	end

	-- legend: every symbol of the center in its element's color (the special and decorative sigils in their own),
	-- signs and frames in ink color
	for _, key in ipairs( DICTIONARY_CENTER_ORDER ) do
		local shape = TEMPLATES_SIGILS[key] and TEMPLATES_SIGILS[key][1]
		local legend = shape and ModImageMakeEditable( legend_path( key ), 16, 16 ) or 0
		if legend ~= 0 then
			sigil_draw_icon( legend, sigil_symbol_color( key ), sigil_encode( shape_strokes( shape ) ) )
			image_bleed( legend, 16, 16 )
			image_cut_columns( legend_path( key ), legend, 16, 16 )
		end
	end
	for _, list in ipairs( { { DICTIONARY_SIGN_ORDER, TEMPLATES_SIGNS }, { DICTIONARY_FRAME_ORDER, TEMPLATES_FRAMES } } ) do
		for _, key in ipairs( list[1] ) do
			local shape = list[2][key] and list[2][key][1]
			local legend = shape and ModImageMakeEditable( legend_path( key ), 16, 16 ) or 0
			if legend ~= 0 then
				sigil_draw_icon( legend, SIGIL_NEUTRAL_COLOR, sigil_encode( shape_strokes( shape ) ) )
				image_bleed( legend, 16, 16 )
				image_cut_columns( legend_path( key ), legend, 16, 16 )
			end
		end
	end
end
