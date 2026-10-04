-- The books' look (notebook.lua draws with it, books.lua has the books): paper for their pages, the covers, ribbon
-- bookmarks, ink bottles, soft shadows. Drawn at mod init into in-memory images (ModImageMakeEditable works only then).
-- A page is also cut into narrow strips across the way it turns: a turning page is drawn strip by strip along a curve,
-- so it bends like paper instead of swinging round like a board - a book's pages in upright strips, the Palm Quire's
-- round leaves, which flip up over their top, in flat ones.
--   Spellbook  - warm paper in a ruled frame; a red-brown leather cover with a gold frame and a stitched spine.
--   Great Tome - old vellum in a rubricated double frame with Noita's eyes; black leather with iron corners, a gilt
--                border of eyes, raised bands on the spine and a clasp; marbled endpapers.
--   Palm Quire - round leaves on a brass-rimmed pad; above it the lid with the sigil the manga draws on it and a tab
--                with a hole, two hinges between, straps under the pad.

BOOK_GFX = "mods/witch_notebook/files/gfx/book/"
BOOK_BOTTLE_W, BOOK_BOTTLE_H = 13, 19
BOOK_BOTTLE_LEVELS = 11                 -- rows of liquid in a bottle
BOOK_DIGIT_W, BOOK_DIGIT_H = 3, 5       -- the page numbers' small digits
BOOK_SHADE_END_H = 8 -- the shades' soft ends, 16 x 8: fading in from the top, and out towards the bottom
BOOK_SPINE_SHADE_W, BOOK_SPINE_SHADE_ALPHA = 22, 0.32

-- How each book looks, beyond its size (books.lua): its papers; its ribbon's size and where it lies on its page (from the
-- page's right edge, over its top edge); the turned-up corner; the page number's gap in the frame's bottom line and how
-- far over the page's bottom the number is; where a seal's name goes (a sheet's a little lower), a word in the corner,
-- the bottle of a seal's ink (from the right and bottom), how far under the page the words about it go; the front
-- pages' bookplate and title emblem; the page edges' color
BOOK_LOOKS = {
	book = {
		kinds = { "page", "plain", "sheet", "dark", "endpaper", "title" },
		ribbon = { w = 7, h = 40, x = 25, y = 6, color = { 190, 28, 44 } },
		dogear = 16, number_gap = 12.5, number_y = 6,
		name_y = 5, sheet_name_y = 12, label = { x = 9, y = 7 }, bottle = { x = 19, y = 26 }, label_gap = 3,
		plate = { x = 38, y = 48, w = 104, h = 84 }, emblem = { x = 89.5, y = 64, r = 34 },
		edge = { 0.86, 0.8, 0.66 },
	},
	tome = {
		kinds = { "page", "plain", "sheet", "dark", "endpaper", "title" },
		ribbon = { w = 9, h = 54, x = 36, y = 8, color = { 34, 84, 58 }, gilt = true },
		dogear = 20, number_gap = 14.5, number_y = 8,
		name_y = 15, sheet_name_y = 21, label = { x = 16, y = 15 }, bottle = { x = 27, y = 36 }, label_gap = 12,
		plate = { x = 56, y = 60, w = 128, h = 116 }, emblem = { x = 119.5, y = 86, r = 46 },
		edge = { 0.78, 0.7, 0.55 },
	},
	quire = {
		kinds = { "page", "sheet", "dark", "back" },
		ribbon = { w = 5, h = 26, x = 38, y = 2, color = { 176, 30, 40 } },
		curl = 52, -- the bottom of a leaf curling up under the mouse: its width
		edge = { 0.86, 0.8, 0.66 },
		side = 15, top = 38, strap = 28, -- the case around the pages: room for the straps at the sides, the tab over the lid, the straps under the pad
		tab = { neck = 7, r = 10, tip = 31, eyelet = 4.6, hole = 1.8 }, -- over the rim's top: its neck, the drop's radius, its tip; the eyelet's radii
	},
}
BOOK_LOOKS.test = BOOK_LOOKS.book -- the Test Book lies open as the Spellbook does, on its paper

function book_page_image( def, kind, front )
	if front == nil or def.round then return BOOK_GFX .. def.gfx .. "page_" .. kind .. ".png" end
	return BOOK_GFX .. def.gfx .. "page_spine_" .. ( front and "front_" or "back_" ) .. kind .. ".png"
end
function book_strip_image( def, kind, i ) return BOOK_GFX .. def.gfx .. "strip_" .. kind .. "_" .. i .. ".png" end
function book_turn_strip_image( def, kind, i, front )
	if def.round or ( front and i or def.strips - 1 - i ) * def.page / def.strips >= BOOK_SPINE_SHADE_W then
		return book_strip_image( def, kind, i )
	end
	return BOOK_GFX .. def.gfx .. "strip_spine_" .. ( front and "front_" or "back_" ) .. kind .. "_" .. i .. ".png"
end
function book_cover_image( def ) return BOOK_GFX .. def.gfx .. "cover.png" end
function book_ribbon_image( def ) return BOOK_GFX .. def.gfx .. "ribbon.png" end
function book_ribbon_row_image( def, row ) return BOOK_GFX .. def.gfx .. "ribbon_row_" .. row .. ".png" end
function book_ribbon_flipped_image( def ) return BOOK_GFX .. def.gfx .. "ribbon_flip_y.png" end
function book_dogear_image( def, right ) return BOOK_GFX .. def.gfx .. ( right and "dogear_right.png" or "dogear_left.png" ) end
function book_fill_image( level ) return BOOK_GFX .. "bottle_fill_" .. level .. ".png" end
function book_digit_image( d ) return BOOK_GFX .. "digit_" .. d .. ".png" end
BOOK_BOTTLE_IMAGE = BOOK_GFX .. "bottle.png"
BOOK_GLOW_IMAGE = BOOK_GFX .. "glow.png"
BOOK_SHADE_IMAGE = BOOK_GFX .. "shade.png"     -- 16 x 1, opaque on the left fading to the right
BOOK_SHADE_R_IMAGE = BOOK_GFX .. "shade_r.png" -- ... fading to the left
BOOK_SHADE_DOWN_IMAGE = BOOK_GFX .. "shade_down.png" -- 1 x 16, opaque at the top fading downwards
BOOK_SHADE_UP_IMAGE = BOOK_GFX .. "shade_up.png"     -- ... fading upwards
function book_shade_end_image( right, bottom )
	return BOOK_GFX .. "shade" .. ( right and "_r" or "" ) .. ( bottom and "_bottom" or "_top" ) .. ".png"
end
BOOK_FLOURISH_IMAGE = BOOK_GFX .. "flourish.png"
BOOK_MOTE_IMAGE = "mods/witch_notebook/files/gfx/mote.png"
QUIRE_EDGE_IMAGE = BOOK_GFX .. "quire_edge.png"    -- a leaf's edge under the pad's top leaf: a disc
QUIRE_CURL_IMAGE = BOOK_GFX .. "quire_curl.png"    -- the pad's leaf curling up at its bottom
QUIRE_CURL_UP_IMAGE = BOOK_GFX .. "quire_curl_up.png" -- the leaves flipped onto the lid, curling down at their top
QUIRE_STRAP_EDGE_IMAGE = BOOK_GFX .. "quire_strap_edge.png" -- the strap stamped along its chain: its dark edge, 7 x 7
function quire_strap_leather_image( k ) return BOOK_GFX .. "quire_strap_leather_" .. k .. ".png" end -- the leather, 5 x 5
QUIRE_STRAP_BUCKLES = 16 -- the buckle turned every 360 / 16 degrees, 13 x 13
function quire_strap_buckle_image( k ) return BOOK_GFX .. "quire_strap_buckle_" .. k .. ".png" end
-- the quire's tab swinging on its neck (quire_strap.lua): drawn turned every QUIRE_TAB_STEP degrees either way, up to
-- QUIRE_TAB_TURNS steps; each image has the tab's root - the rim's top - at QUIRE_TAB_ROOT_X, QUIRE_TAB_ROOT_Y
QUIRE_TAB_STEP, QUIRE_TAB_TURNS = 2, 8
QUIRE_TAB_W, QUIRE_TAB_H, QUIRE_TAB_ROOT_X, QUIRE_TAB_ROOT_Y = 50, 38, 24.5, 35.5
function quire_tab_image( turn ) return BOOK_GFX .. "quire_tab_" .. ( turn + QUIRE_TAB_TURNS ) .. ".png" end

local function rgba( r, g, b, a )
	local c = function( v ) return math.max( 0, math.min( 255, math.floor( v + 0.5 ) ) ) end
	return color_abgr_merge( c( r ), c( g ), c( b ), c( a or 255 ) )
end

-- cheap deterministic noise: a hash of the cell, and smooth value noise over cells of 'size'
local function hash( x, y, seed )
	local n = math.sin( x * 12.9898 + y * 78.233 + ( seed or 0 ) * 37.719 ) * 43758.5453
	return n - math.floor( n )
end
local function smooth( x, y, size, seed )
	local gx, gy = x / size, y / size
	local x0, y0 = math.floor( gx ), math.floor( gy )
	local fx, fy = gx - x0, gy - y0
	fx, fy = fx * fx * ( 3 - 2 * fx ), fy * fy * ( 3 - 2 * fy )
	local a, b = hash( x0, y0, seed ), hash( x0 + 1, y0, seed )
	local c, d = hash( x0, y0 + 1, seed ), hash( x0 + 1, y0 + 1, seed )
	return ( a + ( b - a ) * fx ) + ( ( c + ( d - c ) * fx ) - ( a + ( b - a ) * fx ) ) * fy
end

local function mix( a, b, t ) return a + ( b - a ) * t end

-- An image made pixel by pixel: 'pixel( x, y )' -> r, g, b[, a] or nil (transparent); 'bleed': transparent pixels take
-- their neighbours' color, for an image drawn scaled
local function make_image( file, w, h, pixel, bleed )
	local id = ModImageMakeEditable( file, w, h )
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local r, g, b, a = pixel( x, y )
			ModImageSetPixel( id, x, y, r and rgba( r, g, b, a ) or 0 )
		end
	end
	if bleed then image_bleed( id, w, h ) end
	return id
end

---- paper ----

-- A page's paper, pixel by pixel: grainy and fibrous, darker towards its edges and corners ('round': a round leaf,
-- darker towards its rim). 'tone': the paper's color, 'age': how much it is stained.
local PAPER = { 240, 229, 200 }
local VELLUM = { 232, 212, 168 }
local function paper( x, y, seed, size, round, tone, age )
	tone, age = tone or PAPER, age or 1
	local blot = ( smooth( x, y, 23, seed ) - 0.5 ) * 12 * age + ( smooth( x, y, 7, seed + 1 ) - 0.5 ) * 6
	local grain = ( hash( x, y, seed + 2 ) - 0.5 ) * 7
	local fiber = hash( math.floor( x / 5 ), y, seed + 3 ) > 0.965 and -5 or 0 -- short strands running along the page
	local edge, corner
	if round then
		local c = ( size - 1 ) / 2
		edge = c - math.sqrt( ( x - c ) ^ 2 + ( y - c ) ^ 2 )
		corner = 0
	else
		edge = math.min( x, y, size - 1 - x, size - 1 - y )
		corner = math.max( 0, 22 - math.min( x + y, ( size - 1 - x ) + y, x + ( size - 1 - y ), ( size - 1 - x ) + ( size - 1 - y ) ) ) * 0.5
	end
	local shade = edge < 12 and ( 12 - edge ) * 0.9 * age or 0
	local d = blot + grain + fiber - shade - corner
	local r, g, b = tone[1] + d, tone[2] + d * 1.05, tone[3] + d * 1.2
	if edge < 1 then r, g, b = r * 0.72, g * 0.68, b * 0.62 end
	return r, g, b
end

-- A few specks of age on the paper (foxing)
local function specks( x, y, seed )
	local cx, cy = math.floor( x / 30 ), math.floor( y / 30 )
	if hash( cx, cy, seed + 9 ) < 0.78 then return 0 end
	local px = cx * 30 + 4 + hash( cx, cy, seed + 10 ) * 22
	local py = cy * 30 + 4 + hash( cx, cy, seed + 11 ) * 22
	local r = 1 + hash( cx, cy, seed + 12 ) * 2.2
	local d = math.sqrt( ( x - px ) ^ 2 + ( y - py ) ^ 2 )
	return d < r and ( 1 - d / r ) * 14 or 0
end

-- The bookplate's shape: a rectangle with its corners cut in quarter circles; returns how far in from its edge the
-- point is (< 0 - outside)
local function plate_depth( plate, x, y )
	local d = math.min( x - plate.x, plate.x + plate.w - 1 - x, y - plate.y, plate.y + plate.h - 1 - y )
	if d < 0 then return d end
	for _, cx in ipairs( { plate.x, plate.x + plate.w - 1 } ) do
		for _, cy in ipairs( { plate.y, plate.y + plate.h - 1 } ) do
			local dc = math.sqrt( ( x - cx ) ^ 2 + ( y - cy ) ^ 2 ) - 7
			if dc < 7 then d = math.min( d, dc ) end
		end
	end
	return d
end

-- a bookplate pasted onto an endpaper: old paper with a double rule, and its shadow; nil where it isn't
local function bookplate( plate, x, y, r, g, b, seed )
	local d = plate_depth( plate, x, y )
	if d >= 0 then
		r, g, b = paper( x, y, seed, 1000 )
		local ink = { 120, 88, 60 }
		local t = ( d >= 2 and d < 3 ) and 0.55 or ( d >= 4.5 and d < 5.5 ) and 0.3 or 0
		return mix( r, ink[1], t ), mix( g, ink[2], t ), mix( b, ink[3], t )
	elseif plate_depth( plate, x - 2, y - 2 ) >= 0 then
		return r * 0.55, g * 0.55, b * 0.6
	end
	return r, g, b
end

-- The leather's grain
local function leather( x, y, seed )
	return ( smooth( x, y, 9, seed ) - 0.5 ) * 16 + ( smooth( x, y, 3, seed + 1 ) - 0.5 ) * 8 + ( hash( x, y, seed + 2 ) - 0.5 ) * 6
end

---- the Spellbook's pages ----

-- The inside of the cover (it lies on the left, the spine on its right): the leather turned in round the edges, deep
-- blue paper with gold stars and moons, as in a witch's book, and a bookplate pasted in the middle
local GOLD = { 212, 170, 84 }
local function endpaper_pixel( look, size, x, y )
	local turn = 8
	local e = math.min( x, y, size - 1 - y )
	local r, g, b
	if e < turn then
		local n = leather( x, y, 21 )
		r, g, b = 86 + n, 44 + n * 0.6, 34 + n * 0.5
		if e == turn - 1 then r, g, b = r * 0.72, g * 0.7, b * 0.7 end -- the leather's cut edge
		return r, g, b
	end
	-- the paper, faintly marbled
	local warp = smooth( x, y, 11, 33 ) * 14
	local n = ( smooth( x, y, 16, 31 ) - 0.5 ) * 12 + ( smooth( x + warp, y - warp * 0.5, 6, 32 ) - 0.5 ) * 9 + ( hash( x, y, 34 ) - 0.5 ) * 4
	r, g, b = 36 + n * 0.45, 40 + n * 0.55, 82 + n
	-- gold stars, crescents and specks on a staggered grid
	local cell = 22
	local row = math.floor( ( y - turn ) / cell )
	local ox = turn + ( row % 2 ) * cell / 2
	local col = math.floor( ( x - ox ) / cell )
	local dx, dy = x - ( ox + col * cell + cell / 2 ), y - ( turn + row * cell + cell / 2 )
	local ax, ay = math.abs( dx ), math.abs( dy )
	local pick = hash( col, row, 35 )
	local star = false
	if pick < 0.45 then
		star = ( ax == 0 and ay <= 3 ) or ( ay == 0 and ax <= 3 )
	elseif pick < 0.7 then
		star = dx * dx + dy * dy <= 7 and ( dx - 1.6 ) ^ 2 + ( dy + 0.8 ) ^ 2 > 5.5
	elseif pick < 0.9 then
		star = ax + ay == 0
	end
	if star then
		local k = ( ax == 0 and ay == 0 ) and 1 or 0.85
		r, g, b = GOLD[1] * k, GOLD[2] * k, GOLD[3] * k
	end
	-- a gilt fillet along the leather, the leather's shadow, the fold into the spine
	if e == turn + 3 then r, g, b = mix( r, GOLD[1], 0.7 ), mix( g, GOLD[2], 0.7 ), mix( b, GOLD[3], 0.7 ) end
	if e == turn then r, g, b = r * 0.6, g * 0.6, b * 0.6 elseif e == turn + 1 then r, g, b = r * 0.8, g * 0.8, b * 0.8 end
	local fold = size - 1 - x
	if fold < 10 then r, g, b = r * ( 0.6 + fold * 0.04 ), g * ( 0.6 + fold * 0.04 ), b * ( 0.6 + fold * 0.04 ) end
	return bookplate( look.plate, x, y, r, g, b, 5 )
end

-- Round the title emblem (drawn on the page, notebook.lua): a tone of dots inside its ring and focus lines bursting out
-- of it, as in manga
local function emblem_backdrop( emblem, x, y, line )
	local dx, dy = x - emblem.x, y - emblem.y
	local d = math.sqrt( dx * dx + dy * dy )
	if d < emblem.r - 7 and x % 3 == 0 and y % 3 == 0 then line( 0.22 * ( 1 - d / emblem.r ) + 0.08 ) end
	local r0, r1 = emblem.r + 4, emblem.r + 17
	if d >= r0 and d <= r1 then
		local rays = 120
		local k = ( math.atan2( dy, dx ) / ( 2 * math.pi ) + 0.5 ) * rays
		local ray = math.floor( k )
		local len = r0 + ( r1 - r0 ) * ( 0.45 + 0.55 * hash( ray, 1, 41 ) )
		local width = 0.22 * ( 1 - ( d - r0 ) / ( len - r0 ) )
		if hash( ray, 2, 42 ) > 0.3 and d <= len and math.abs( k - ray - 0.5 ) < width then line( 0.35 ) end
	end
end

-- The title page: a double ruled frame with ornaments in its corners and in the middle of its sides, the emblem's
-- backdrop
local function title_pixel( look, size, x, y, r, g, b )
	local ink = { 96, 66, 44 }
	local function line( t ) r, g, b = mix( r, ink[1], t ), mix( g, ink[2], t ), mix( b, ink[3], t ) end
	local ex, ey = math.min( x, size - 1 - x ), math.min( y, size - 1 - y )
	if ( ex == 6 and ey >= 6 ) or ( ey == 6 and ex >= 6 ) then line( 0.5 ) end
	if ( ex == 9 and ey >= 9 ) or ( ey == 9 and ex >= 9 ) then line( 0.28 ) end
	-- the corners: a quarter ring over the frame's corner and a small diamond inside it
	if ex >= 6 and ey >= 6 and ex <= 20 and ey <= 20 then
		local d = math.sqrt( ( ex - 6 ) ^ 2 + ( ey - 6 ) ^ 2 )
		if math.abs( d - 11 ) < 0.6 then line( 0.4 ) end
		if math.abs( ex - 14 ) + math.abs( ey - 14 ) == 2 then line( 0.45 ) end
	end
	-- the middles of the sides: a diamond on the inner rule
	local mx, my = math.abs( x - ( size - 1 ) / 2 ), math.abs( y - ( size - 1 ) / 2 )
	if ( mx + math.abs( ey - 9 ) == 2.5 ) or ( my + math.abs( ex - 9 ) == 2.5 ) then line( 0.5 ) end
	emblem_backdrop( look.emblem, x, y, line )
	return r, g, b
end

-- A sheet pasted onto a page: older, rougher paper with a torn edge and a shadow; 'inset' - how far in from the page's
-- edge it lies, 'e' - how far in the pixel is ('dark': a forbidden sheet, burnt). Returns nil off the sheet.
local function pasted_sheet( x, y, e, inset, dark, r, g, b )
	if e >= inset then
		local k = dark and { 0.66, 0.5, 0.42 } or { 0.97, 0.93, 0.8 }
		local burn = dark and math.max( 0, 6 - ( e - inset ) ) * 14 or math.max( 0, 3 - ( e - inset ) ) * 8
		local blot = ( smooth( x, y, 17, 5 ) - 0.5 ) * ( dark and 30 or 14 )
		return r * k[1] - burn + blot, g * k[2] - burn * 1.1 + blot, b * k[3] - burn * 1.3 + blot * 0.8
	elseif e >= inset - 2.5 then
		return r * 0.82, g * 0.8, b * 0.76, true -- its shadow on the page
	end
end

-- a strip of tape across the point cx, cy, turned by 45 degrees ('dir': which way)
local function tape( x, y, cx, cy, dir, r, g, b, long )
	local u = ( x - cx ) * 0.7071 * dir + ( y - cy ) * 0.7071
	local v = -( x - cx ) * 0.7071 * dir + ( y - cy ) * 0.7071
	if math.abs( u ) < 4 and math.abs( v ) < ( long or 11 ) then
		r, g, b = mix( r, 250, 0.35 ), mix( g, 244, 0.35 ), mix( b, 220, 0.35 )
		if math.abs( math.abs( u ) - 3.5 ) < 0.5 then r, g, b = r * 0.93, g * 0.93, b * 0.9 end
	end
	return r, g, b
end

local function book_page_pixel( look, size, kind, x, y )
	if kind == "endpaper" then return endpaper_pixel( look, size, x, y ) end
	local r, g, b = paper( x, y, 3, size )
	local sp = specks( x, y, 3 )
	r, g, b = r - sp * 0.6, g - sp * 0.8, b - sp
	local ink = { 120, 88, 60 }
	local function line( t ) r, g, b = mix( r, ink[1], t ), mix( g, ink[2], t ), mix( b, ink[3], t ) end
	if kind == "page" or kind == "plain" then
		-- a thin ruled frame with little diamonds in the corners; the bottom line parts in the middle for the page's
		-- number, between two more diamonds
		local ex, ey = math.min( x, size - 1 - x ), math.min( y, size - 1 - y )
		local gap = math.abs( x - ( size - 1 ) / 2 ) -- from the middle
		local bottom = y > size / 2
		if ( ex == 5 and ey >= 5 ) or ( ey == 5 and ex >= 5 and not ( bottom and gap < look.number_gap + 2 ) ) then line( 0.22 ) end
		if ex <= 8 and ey <= 8 and math.abs( ex - 5 ) + math.abs( ey - 5 ) == 3 then line( 0.3 ) end
		if bottom and math.abs( gap - look.number_gap ) + math.abs( ey - 5 ) == 2 then line( 0.3 ) end
		if kind == "page" then
			local c = ( size - 1 ) / 2
			local d = math.sqrt( ( x - c ) ^ 2 + ( y - c ) ^ 2 )
			if math.abs( d - 0.4 * size ) < 0.6 then line( 0.14 ) end -- faint guide for the outer circle
		end
	elseif kind == "title" then
		r, g, b = title_pixel( look, size, x, y, r, g, b )
	elseif kind == "sheet" or kind == "dark" then
		-- a sheet held by two strips of tape over its top corners
		local inset = 8 + smooth( x + y * 0.3, y - x * 0.3, 5, 17 ) * 2.5
		local e = math.min( x, y, size - 1 - x, size - 1 - y )
		local sr, sg, sb, shadow = pasted_sheet( x, y, e, inset, kind == "dark", r, g, b )
		if sr and ( not shadow or x > y - 3 ) then r, g, b = sr, sg, sb end
		r, g, b = tape( x, y, 14, 14, 1, r, g, b )
		r, g, b = tape( x, y, size - 15, 14, -1, r, g, b )
	end
	return r, g, b
end

---- the Great Tome's pages ----

-- one of Noita's eyes, 7 x 5, in the middle at cx, cy
local EYE = { "..###..", ".#...#.", "#..#..#", ".#...#.", "..###.." }
local function eye_at( x, y, cx, cy )
	local dx, dy = x - math.floor( cx ) + 3, y - math.floor( cy ) + 2
	if dx < 0 or dy < 0 or dx > 6 or dy > 4 then return false end
	return EYE[dy + 1]:sub( dx + 1, dx + 1 ) == "#"
end

-- The marbled endpaper of an old tome: oxblood and black combed into veins, thin gold among them; the black leather
-- turned in round its edges, a gilt fillet, a bookplate in the middle
local TOME_LEATHER = { 46, 32, 29 }
local function tome_endpaper_pixel( look, size, x, y )
	local turn = 11
	local e = math.min( x, y, size - 1 - y )
	if e < turn then
		local n = leather( x, y, 71 )
		local r, g, b = TOME_LEATHER[1] + n, TOME_LEATHER[2] + n * 0.7, TOME_LEATHER[3] + n * 0.6
		if e == turn - 1 then r, g, b = r * 0.7, g * 0.7, b * 0.7 end
		return r, g, b
	end
	-- marbling: the colours float in bands - the lines of a slowly bent field, stretched along the page - each band its
	-- own shade of oxblood, thin veins of gold and black between them
	local wx = x + ( smooth( x, y, 37, 61 ) - 0.5 ) * 40
	local wy = y + ( smooth( x + 11, y - 7, 29, 62 ) - 0.5 ) * 40
	local f = ( smooth( wx * 0.6, wy, 21, 63 ) * 0.75 + smooth( wx, wy, 9, 64 ) * 0.25 ) * 7
	local band = math.floor( f )
	local r, g, b = unpack( ( { { 96, 24, 28 }, { 44, 14, 18 }, { 124, 36, 34 }, { 66, 18, 24 }, { 30, 10, 14 } } )[band % 5 + 1] )
	local vein = f - band
	if vein < 0.06 then r, g, b = 204, 158, 74 elseif vein > 0.94 then r, g, b = 18, 8, 10 end
	local grain = ( hash( x, y, 65 ) - 0.5 ) * 8
	r, g, b = r + grain, g + grain * 0.6, b + grain * 0.6
	if e == turn + 3 then r, g, b = mix( r, GOLD[1], 0.75 ), mix( g, GOLD[2], 0.75 ), mix( b, GOLD[3], 0.75 ) end
	if e == turn then r, g, b = r * 0.55, g * 0.55, b * 0.55 elseif e == turn + 1 then r, g, b = r * 0.78, g * 0.78, b * 0.78 end
	local fold = size - 1 - x
	if fold < 12 then r, g, b = r * ( 0.55 + fold * 0.037 ), g * ( 0.55 + fold * 0.037 ), b * ( 0.55 + fold * 0.037 ) end
	return bookplate( look.plate, x, y, r, g, b, 7 )
end

-- The tome's frame: a red rule outside, a brown one inside, red squares at the corners and one of Noita's eyes in the
-- middle of the top and of the sides; the rules part at the bottom for the page's number
local function tome_frame( look, size, x, y, line, red )
	local ex, ey = math.min( x, size - 1 - x ), math.min( y, size - 1 - y )
	local mid_x, mid_y = math.abs( x - ( size - 1 ) / 2 ), math.abs( y - ( size - 1 ) / 2 )
	local bottom = y > size / 2
	local parted = bottom and mid_x < look.number_gap + 2
	local top_eye = not bottom and mid_x < 6
	local side_eye = mid_y < 5
	if ( ex == 8 and ey >= 8 and not side_eye ) or ( ey == 8 and ex >= 8 and not parted and not top_eye ) then red( 0.5 ) end
	if ( ex == 11 and ey >= 11 ) or ( ey == 11 and ex >= 11 and not parted ) then line( 0.3 ) end
	if ex >= 7 and ex <= 9 and ey >= 7 and ey <= 9 then red( 0.62 ) end
	if bottom and math.abs( mid_x - look.number_gap ) < 0.6 and ey >= 7 and ey <= 12 then red( 0.4 ) end
	if eye_at( x, y, ( size - 1 ) / 2, 8 ) then line( 0.5 ) end
	if eye_at( x, y, 5, ( size - 1 ) / 2 ) or eye_at( x, y, size - 6, ( size - 1 ) / 2 ) then line( 0.5 ) end
end

local function tome_page_pixel( look, size, kind, x, y )
	if kind == "endpaper" then return tome_endpaper_pixel( look, size, x, y ) end
	local r, g, b = paper( x, y, 13, size, false, VELLUM, 1.5 )
	local sp = specks( x, y, 13 )
	r, g, b = r - sp * 0.8, g - sp, b - sp * 1.2
	local ink, rubric = { 84, 56, 38 }, { 150, 38, 30 }
	local function line( t ) r, g, b = mix( r, ink[1], t ), mix( g, ink[2], t ), mix( b, ink[3], t ) end
	local function red( t ) r, g, b = mix( r, rubric[1], t ), mix( g, rubric[2], t ), mix( b, rubric[3], t ) end
	if kind == "page" or kind == "plain" or kind == "title" then
		tome_frame( look, size, x, y, line, red )
		local c = ( size - 1 ) / 2
		local d = math.sqrt( ( x - c ) ^ 2 + ( y - c ) ^ 2 )
		if kind == "page" and math.abs( d - 0.4 * size ) < 0.6 then line( 0.13 ) end -- faint guide for the outer circle
		if kind == "title" then emblem_backdrop( look.emblem, x, y, line ) end
	elseif kind == "sheet" or kind == "dark" then
		-- a sheet held by two blobs of red wax at its top corners
		local inset = 12 + smooth( x + y * 0.3, y - x * 0.3, 6, 18 ) * 3
		local e = math.min( x, y, size - 1 - x, size - 1 - y )
		local sr, sg, sb, shadow = pasted_sheet( x, y, e, inset, kind == "dark", r, g, b )
		if sr and ( not shadow or x > y - 3 ) then r, g, b = sr, sg, sb end
		for _, c in ipairs( { { 17, 17 }, { size - 18, 17 } } ) do
			local d = math.sqrt( ( x - c[1] ) ^ 2 + ( y - c[2] ) ^ 2 ) + ( smooth( x, y, 2, 19 ) - 0.5 ) * 1.6
			if d < 5 then
				local k = d < 2.6 and 0.8 or ( d > 4 and 0.85 or 1 )
				r, g, b = 150 * k, 26 * k, 30 * k
				if d < 2.2 and eye_at( x, y, c[1], c[2] ) then r, g, b = 96, 14, 20 end -- an eye pressed into the wax
			end
		end
	end
	return r, g, b
end

---- the Palm Quire's leaves ----

-- A round leaf: paper to its rim, a thin circle ruled near it with a tick at the four sides and a faint guide for the
-- seal's ring ('page'); a smaller round sheet pasted on it ('sheet', 'dark'); its back ('back'). Transparent off the leaf.
local function quire_page_pixel( look, size, kind, x, y )
	local c = ( size - 1 ) / 2
	local d = math.sqrt( ( x - c ) ^ 2 + ( y - c ) ^ 2 )
	local rim = c + 0.5 - d
	if rim < 0 then return nil end
	local r, g, b = paper( x, y, kind == "back" and 23 or 3, size, true )
	if kind == "back" then r, g, b = r * 0.95, g * 0.94, b * 0.92 end
	local ink = { 120, 88, 60 }
	local function line( t ) r, g, b = mix( r, ink[1], t ), mix( g, ink[2], t ), mix( b, ink[3], t ) end
	if kind == "page" then
		if math.abs( rim - 5 ) < 0.55 then line( 0.24 ) end
		local ax, ay = math.abs( x - c ), math.abs( y - c )
		if rim >= 5 and rim <= 9 and ( ax < 0.6 or ay < 0.6 ) then line( 0.3 ) end
		if math.abs( d - 0.4 * size ) < 0.6 then line( 0.14 ) end
	elseif kind == "sheet" or kind == "dark" then
		local inset = 6 + smooth( x + y * 0.3, y - x * 0.3, 4, 17 ) * 2
		local sr, sg, sb, shadow = pasted_sheet( x, y, rim, inset, kind == "dark", r, g, b )
		if sr and ( not shadow or x > y - 3 ) then r, g, b = sr, sg, sb end
		r, g, b = tape( x, y, c - 34, c - 34, 1, r, g, b, 8 )
		r, g, b = tape( x, y, c + 34, c - 34, -1, r, g, b, 8 )
	end
	return r, g, b
end

local PAGE_PIXEL = { book = book_page_pixel, tome = tome_page_pixel, quire = quire_page_pixel }

-- A book's pages, and the strips a turning page is cut into: upright ones, or for the quire's leaves, which flip up,
-- flat ones
local function create_pages( def )
	local look, size = BOOK_LOOKS[def.key], def.page
	local n, w = def.strips, size / def.strips
	for _, kind in ipairs( look.kinds ) do
		local pixel = function( x, y ) return PAGE_PIXEL[def.key]( look, size, kind, x, y ) end
		local page = make_image( book_page_image( def, kind ), size, size, pixel, def.round )
		local shaded = {}
		if not def.round then
			for _, front in ipairs( { true, false } ) do
				shaded[front] = make_image( book_page_image( def, kind, front ), size, size, function( x, y )
					local c = ModImageGetPixel( page, x, y )
					if c < 0 then c = c + 4294967296 end
					local a = math.floor( c / 16777216 )
					local distance = front and x + 0.5 or size - x - 0.5
					local fade = math.max( 0, 1 - distance / BOOK_SPINE_SHADE_W )
					local shade = BOOK_SPINE_SHADE_ALPHA * fade * fade
					local tint = BookDraw.SHADE_COLOR
					local r, g, b = c % 256, math.floor( c / 256 ) % 256, math.floor( c / 65536 ) % 256
					return r + ( tint[1] * 255 - r ) * shade, g + ( tint[2] * 255 - g ) * shade,
						b + ( tint[3] * 255 - b ) * shade, a
				end )
			end
		end
		for i = 0, n - 1 do
			local file = book_strip_image( def, kind, i )
			if def.round then
				local strip = ModImageMakeEditable( file, size, w )
				for y = 0, w - 1 do
					for x = 0, size - 1 do ModImageSetPixel( strip, x, y, ModImageGetPixel( page, x, i * w + y ) ) end
				end
			else
				local strip = ModImageMakeEditable( file, w, size )
				for y = 0, size - 1 do
					for x = 0, w - 1 do ModImageSetPixel( strip, x, y, ModImageGetPixel( page, i * w + x, y ) ) end
				end
				-- Turning sheets use the same shaded pixels as the flat pages at the spine.
				for _, front in ipairs( { true, false } ) do
					if ( front and i or n - 1 - i ) * w < BOOK_SPINE_SHADE_W then
						local shaded_strip = ModImageMakeEditable( book_turn_strip_image( def, kind, i, front ), w, size )
						for y = 0, size - 1 do
							for x = 0, w - 1 do ModImageSetPixel( shaded_strip, x, y, ModImageGetPixel( shaded[front], i * w + x, y ) ) end
						end
					end
				end
			end
		end
	end
end

---- covers ----

-- The Spellbook's cover: dark red-brown leather, a gilt rule round it with ornaments in the corners, the spine between
-- the pages stitched with pale thread
local function create_book_cover( def )
	local m, size, spine = def.margin, def.page, 2 * def.gap
	local w, h = 2 * size + spine + 2 * m, size + 2 * m
	local spine0 = m + size
	local id = make_image( book_cover_image( def ), w, h, function( x, y )
		local n = leather( x, y, 21 )
		local r, g, b = 86 + n, 44 + n * 0.6, 34 + n * 0.5
		local edge = math.min( x, y, w - 1 - x, h - 1 - y )
		-- rounded corners, a bevelled rim
		local cx, cy = math.min( x, w - 1 - x ), math.min( y, h - 1 - y )
		if cx < 3 and cy < 3 and ( 3 - cx ) ^ 2 + ( 3 - cy ) ^ 2 > 10 then return nil end
		if edge == 0 then r, g, b = r * 0.55, g * 0.55, b * 0.55
		elseif edge == 1 then
			if x == 1 or y == 1 then r, g, b = r * 1.25, g * 1.2, b * 1.15 else r, g, b = r * 0.75, g * 0.75, b * 0.75 end
		end
		-- the gilt rule, 3 in from the edge
		if edge == 3 then r, g, b = 204, 160, 72 end
		if edge == 4 then r, g, b = r * 0.7, g * 0.7, b * 0.7 end
		-- the spine: darker, with a groove on each side and the stitches
		if x >= spine0 and x < spine0 + spine then
			local sx = x - spine0
			r, g, b = r * 0.72, g * 0.7, b * 0.7
			if sx == 0 or sx == spine - 1 then r, g, b = r * 0.6, g * 0.6, b * 0.6 end
			if ( sx == 3 or sx == 4 ) and ( y - m ) % 12 >= 2 and ( y - m ) % 12 <= 6 and y > m + 4 and y < h - m - 4 then
				r, g, b = 214, 196, 160
			end
		end
		return r, g, b
	end )
	-- gilt ornaments in the corners: a quarter rosette and two curls along the rule
	local gold, dark = rgba( 224, 182, 88 ), rgba( 120, 80, 30 )
	for _, corner in ipairs( { { 0, 0, 1, 1 }, { w - 1, 0, -1, 1 }, { 0, h - 1, 1, -1 }, { w - 1, h - 1, -1, -1 } } ) do
		for dy = 0, 12 do
			for dx = 0, 12 do
				local d = math.sqrt( ( dx - 3 ) ^ 2 + ( dy - 3 ) ^ 2 )
				local on = ( d >= 3.2 and d <= 4.2 ) or ( dx == 3 and dy == 3 )
					or ( dy == 3 and dx >= 8 and dx <= 11 ) or ( dx == 3 and dy >= 8 and dy <= 11 )
					or ( math.abs( ( dx - 9 ) ^ 2 + ( dy - 6 ) ^ 2 - 3 ) < 1.6 and dy >= 6 ) or ( math.abs( ( dy - 9 ) ^ 2 + ( dx - 6 ) ^ 2 - 3 ) < 1.6 and dx >= 6 )
				if on then
					ModImageSetPixel( id, corner[1] + corner[3] * ( dx + 1 ), corner[2] + corner[4] * ( dy + 1 ), ( dx + dy ) % 5 == 0 and dark or gold )
				end
			end
		end
	end
end

-- The Great Tome's cover: black leather worn lighter at its edges, a gilt border - two rules and a row of dots with
-- Noita's eyes in the middle of the sides - iron corners with rivets, the spine's raised bands, the clasp's catch on the
-- right board and its strap on the left
local IRON = { 104, 96, 88 }
local function create_tome_cover( def )
	local m, size, spine = def.margin, def.page, 2 * def.gap
	local w, h = 2 * size + spine + 2 * m, size + 2 * m
	local spine0 = m + size
	local boards = { { x0 = 0, x1 = spine0 - 1 }, { x0 = spine0 + spine, x1 = w - 1 } }
	make_image( book_cover_image( def ), w, h, function( x, y )
		local edge = math.min( x, y, w - 1 - x, h - 1 - y )
		local cx, cy = math.min( x, w - 1 - x ), math.min( y, h - 1 - y )
		if cx < 3 and cy < 3 and ( 3 - cx ) ^ 2 + ( 3 - cy ) ^ 2 > 10 then return nil end
		local n = leather( x, y, 71 )
		local wear = edge < 7 and ( 7 - edge ) * 2.5 or 0
		local r, g, b = TOME_LEATHER[1] + n + wear, TOME_LEATHER[2] + n * 0.7 + wear * 0.8, TOME_LEATHER[3] + n * 0.6 + wear * 0.6
		if edge == 0 then r, g, b = r * 0.5, g * 0.5, b * 0.5
		elseif edge == 1 then
			if x == 1 or y == 1 then r, g, b = r * 1.35, g * 1.3, b * 1.25 else r, g, b = r * 0.7, g * 0.7, b * 0.7 end
		end
		-- the spine: darker, grooved, with raised bands and gilt lines across them
		if x >= spine0 and x < spine0 + spine then
			local sx = x - spine0
			r, g, b = r * 0.7, g * 0.68, b * 0.68
			if sx == 0 or sx == spine - 1 then r, g, b = r * 0.55, g * 0.55, b * 0.55 end
			local band = ( y - m ) % 44
			if y > m + 8 and y < h - m - 8 and sx > 0 and sx < spine - 1 then
				if band == 20 then r, g, b = r * 1.6, g * 1.55, b * 1.5
				elseif band == 21 then r, g, b = 196, 152, 70
				elseif band == 22 then r, g, b = r * 1.3, g * 1.25, b * 1.2
				elseif band == 23 then r, g, b = r * 0.55, g * 0.55, b * 0.55 end
			end
			return r, g, b
		end
		-- the gilt border on each board: two rules and a row of dots, an eye in the middle of every side
		for _, board in ipairs( boards ) do
			if x >= board.x0 and x <= board.x1 then
				local bx, by = math.min( x - board.x0, board.x1 - x ), math.min( y, h - 1 - y )
				local be = math.min( bx, by )
				local mid_x = math.abs( x - ( board.x0 + board.x1 ) / 2 )
				local mid_y = math.abs( y - ( h - 1 ) / 2 )
				local on_eye = ( by < 9 and mid_x < 6 ) or ( bx < 9 and mid_y < 5 )
				if ( be == 3 or be == 8 ) and not on_eye then r, g, b = 206, 162, 74 end
				if ( be == 4 or be == 9 ) and not on_eye then r, g, b = r * 0.65, g * 0.65, b * 0.65 end
				if be == 6 and ( ( bx == 6 and y % 4 == 0 ) or ( by == 6 and x % 4 == 0 ) ) and not on_eye then r, g, b = 196, 150, 66 end
				local ecx = ( board.x0 + board.x1 ) / 2
				if eye_at( x, y, math.floor( ecx ), 5 ) or eye_at( x, y, math.floor( ecx ), h - 6 )
					or eye_at( x, y, board.x0 + 5, math.floor( ( h - 1 ) / 2 ) ) or eye_at( x, y, board.x1 - 5, math.floor( ( h - 1 ) / 2 ) ) then
					r, g, b = 226, 180, 84
				end
			end
		end
		-- iron corners with three rivets each, a highlight along their inner edge
		local ox, oy = math.min( x, w - 1 - x ), math.min( y, h - 1 - y )
		if ox + oy < 20 then
			local k = 0.85 + 0.3 * smooth( x, y, 3, 75 )
			r, g, b = IRON[1] * k, IRON[2] * k, IRON[3] * k
			if ox + oy >= 18 then r, g, b = 150, 140, 126 end
			if ox + oy <= 1 then r, g, b = r * 0.6, g * 0.6, b * 0.6 end
			for _, rivet in ipairs( { { 4, 4 }, { 11, 4 }, { 4, 11 } } ) do
				local d = ( ox - rivet[1] ) ^ 2 + ( oy - rivet[2] ) ^ 2
				if d <= 1 then r, g, b = 196, 188, 170 elseif d <= 2.5 then r, g, b = 60, 54, 50 end
			end
		end
		-- the clasp: a brass catch with a keyhole on the right board's edge, the strap's end on the left
		local mid = ( h - 1 ) / 2
		if x >= w - 10 and x <= w - 3 and math.abs( y - mid ) <= 9 then
			local k = 0.9 + 0.2 * ( ( w - 3 - x ) / 7 )
			r, g, b = 186 * k, 146 * k, 70 * k
			if x == w - 10 or math.abs( y - mid ) == 9 then r, g, b = 110, 80, 36 end
			if x >= w - 7 and x <= w - 6 and y >= mid - 3 and y <= mid + 1 then r, g, b = 30, 20, 14 end -- the keyhole
		end
		if x >= 1 and x <= 8 and math.abs( y - mid ) <= 4 then
			r, g, b = 70, 42, 30
			if math.abs( y - mid ) == 4 then r, g, b = 40, 24, 18 end
			if y == mid and x % 2 == 0 then r, g, b = 150, 120, 90 end -- stitches
			if x <= 3 then r, g, b = 172, 134, 62 end -- its brass tip
		end
		return r, g, b
	end )
end

-- The Palm Quire's case, drawn under its leaves: the lid above, open - leather hatched in ink as in the manga, a brass
-- rim, the gilt sigil the manga draws on it (a triangle and three lines to the rim), a pointed tab with a hole over it;
-- two hinges; the pad below, its leaves on a brass-rimmed leather back; two straps under it, to fasten it on the hand.
-- The image's top left is the lid's page's top left less look.side, look.top.
function quire_case_geometry( def )
	local look, size, g = BOOK_LOOKS.quire, def.page, def.gap
	local cx = look.side + ( size - 1 ) / 2
	local lid = look.top + ( size - 1 ) / 2
	return { cx = cx, lid = lid, pad = lid + size + 2 * g, r = size / 2 + def.margin, w = size + 2 * look.side,
		h = look.top + 2 * size + 2 * g + def.margin + look.strap, hinge = look.top + size + g }
end

-- Whether x, y is on the quire's tab: a neck flaring out of the lid's rim, the drop's round bottom, its pointed top
function quire_tab( q, x, y )
	local tab = BOOK_LOOKS.quire.tab
	local ty, dx = q.lid - q.r - y, math.abs( x - q.cx ) -- how high over the rim's top
	local mid = tab.neck + tab.r -- the drop's middle
	local half = -1
	if ty >= -3 and ty <= tab.neck + 1 then half = 3.5 + math.max( 0, 2 - ty ) * 1.2 end
	if ty >= tab.neck and ty <= mid then half = math.max( half, math.sqrt( math.max( 0, tab.r ^ 2 - ( ty - mid ) ^ 2 ) ) ) end
	if ty > mid and ty <= tab.tip then half = math.max( half, tab.r * ( 1 - ( ty - mid ) / ( tab.tip - mid ) ) ^ 0.75 ) end
	return dx <= half + 0.5
end

-- The quire's strap at rest (quire_strap.lua moves it): its end on 'side' (-1 the left one, with the buckle; 1 the
-- right one, punched with holes) curls out from under the pad's bottom along a curve - points on it a link apart,
-- in the case image's pixels
QUIRE_STRAP_LINK = 3
function quire_strap_rest( def, side )
	local q = quire_case_geometry( def )
	local bottom = q.pad + q.r
	local p0x, p0y = q.cx + side * 10, bottom - 7
	local p1x, p1y = q.cx + side * 16, bottom + 15
	local p2x, p2y = q.cx + side * 38, bottom + 18
	local pts, run, px, py = { { x = p0x, y = p0y } }, 0, p0x, p0y
	for i = 1, 400 do
		local t = i / 400
		local x = ( 1 - t ) ^ 2 * p0x + 2 * ( 1 - t ) * t * p1x + t * t * p2x
		local y = ( 1 - t ) ^ 2 * p0y + 2 * ( 1 - t ) * t * p1y + t * t * p2y
		run = run + math.sqrt( ( x - px ) ^ 2 + ( y - py ) ^ 2 )
		if run >= QUIRE_STRAP_LINK then
			pts[#pts + 1] = { x = x, y = y }
			run = 0
		end
		px, py = x, y
	end
	return pts
end

-- Whether u, v (from the lid's middle) is on the sigil the manga draws on the quire's lid: a triangle pointing up, and
-- from its corners three lines out to the rim
function quire_lid_sigil( u, v, leaf )
	local tr = 0.42 * leaf
	for i = 0, 2 do
		local a0, a1 = -math.pi / 2 + i * 2 * math.pi / 3, -math.pi / 2 + ( i + 1 ) * 2 * math.pi / 3
		local x0, y0 = math.cos( a0 ) * tr, math.sin( a0 ) * tr
		local x1, y1 = math.cos( a1 ) * tr, math.sin( a1 ) * tr
		-- the side from corner i to corner i + 1
		local ex, ey = x1 - x0, y1 - y0
		local t = math.max( 0, math.min( 1, ( ( u - x0 ) * ex + ( v - y0 ) * ey ) / ( ex * ex + ey * ey ) ) )
		if math.sqrt( ( u - x0 - ex * t ) ^ 2 + ( v - y0 - ey * t ) ^ 2 ) < 0.75 then return true end
		-- the line from corner i out to the rim
		local along = u * math.cos( a0 ) + v * math.sin( a0 )
		local off = -u * math.sin( a0 ) + v * math.cos( a0 )
		if along >= tr and along <= leaf - 3 and math.abs( off ) < 0.6 then return true end
	end
	return false
end

local BRASS = { 196, 156, 76 }
-- A pixel of the quire's tab, as the manga draws it: a drop of leather on a short neck, stitched round, a brass eyelet
-- in it (nil: off it, or the eyelet's hole). 'at' gives the point of the case image (unturned) that the pixel px, py
-- of the image being drawn shows - the tab is drawn turned too; its edge and stitches follow that image's pixels.
local function quire_tab_pixel( q, at, px, py )
	local x, y = at( px, py )
	if not quire_tab( q, x, y ) then return nil end
	local tab = BOOK_LOOKS.quire.tab
	local ex, ey = x - q.cx, y - ( q.lid - q.r - tab.neck - tab.r )
	local de = math.sqrt( ex * ex + ey * ey )
	if de < tab.hole then return nil end
	if de < tab.eyelet then
		-- the eyelet's ring: its outer slope lit from the upper left, its inner one from the lower right
		local lit = math.cos( math.atan2( ey, ex ) + 2.36 )
		local k = de > tab.eyelet - 0.9 and 0.5 or de < tab.hole + 0.8 and 0.6
			or 1 + 0.32 * lit * ( de > ( tab.hole + tab.eyelet ) / 2 and 1 or -1 )
		return BRASS[1] * k, BRASS[2] * k, BRASS[3] * k
	end
	local depth = 3 -- how far in from the tab's edge (not the rim it grows out of): 1 - its edge, 2 - the stitches' row
	for k = 2, 1, -1 do
		for _, d in ipairs( { { k, 0 }, { -k, 0 }, { 0, k }, { 0, -k } } ) do
			local nx, ny = at( px + d[1], py + d[2] )
			if not quire_tab( q, nx, ny ) and ( nx - q.cx ) ^ 2 + ( ny - q.lid ) ^ 2 > q.r ^ 2 then depth = k end
		end
	end
	local n = leather( px, py, 45 )
	local k = 1 + 0.12 * math.cos( math.atan2( ey, ex ) + 2.36 ) -- the drop's swell, lit from the upper left
	local r, g, b = ( 80 + n ) * k, ( 48 + n * 0.6 ) * k, ( 34 + n * 0.5 ) * k
	if depth == 1 then r, g, b = r * 0.6, g * 0.6, b * 0.6
	elseif depth == 2 and ( px + py ) % 2 == 0 and q.lid - q.r - y > tab.neck then r, g, b = 168, 138, 100 end
	return r, g, b
end
local function unturned( x, y ) return x, y end

local function create_quire_case( def )
	local q = quire_case_geometry( def )
	local size = def.page
	local leaf = size / 2 -- the leaves' radius
	make_image( book_cover_image( def ), q.w, q.h, function( x, y )
		local dl = math.sqrt( ( x - q.cx ) ^ 2 + ( y - q.lid ) ^ 2 )
		local dp = math.sqrt( ( x - q.cx ) ^ 2 + ( y - q.pad ) ^ 2 )
		-- the hinges: two brass knuckles across the gap
		for _, hx in ipairs( { q.cx - 24, q.cx + 24 } ) do
			if math.abs( x - hx ) <= 4 and math.abs( y - q.hinge ) <= 5 then
				local k = 1.15 - 0.12 * math.abs( x - hx )
				if math.abs( y - q.hinge ) == 5 or math.abs( x - hx ) == 4 then k = 0.55 end
				if y == math.floor( q.hinge ) then k = 0.7 end
				return BRASS[1] * k, BRASS[2] * k, BRASS[3] * k
			end
		end
		-- the rims: brass, lit from the upper left
		for _, c in ipairs( { { d = dl, cy = q.lid }, { d = dp, cy = q.pad } } ) do
			if c.d <= q.r and c.d > leaf - 1 then
				local a = math.atan2( y - c.cy, x - q.cx )
				local lit = 1 + 0.25 * math.cos( a + 2.36 )
				local k = ( c.d > q.r - 1 or c.d < leaf ) and 0.55 or lit * ( 0.9 + 0.15 * math.sin( ( c.d - leaf ) * 1.2 ) )
				return BRASS[1] * k, BRASS[2] * k, BRASS[3] * k
			end
		end
		-- the lid's inside: dark leather hatched in ink, darker to its rim, the gilt sigil
		if dl <= leaf - 1 then
			local n = leather( x, y, 41 )
			local k = 1 - 0.35 * ( dl / leaf ) ^ 2
			local r, g, b = ( 74 + n ) * k, ( 44 + n * 0.6 ) * k, ( 32 + n * 0.5 ) * k
			if ( x + y ) % 3 == 0 then r, g, b = r * 0.72, g * 0.7, b * 0.7 end
			-- the sigil, tooled in gilt with a shadow along its lower right; stitches round the leather inside the rim
			local u, v = x - q.cx, y - q.lid
			if quire_lid_sigil( u, v, leaf ) then return 222, 178, 86 end
			if quire_lid_sigil( u - 1, v - 1, leaf ) then return r * 0.55, g * 0.55, b * 0.55 end
			if dl >= leaf - 4.5 and dl < leaf - 3.5 and math.floor( ( math.atan2( v, u ) + math.pi ) * leaf / 2.2 ) % 2 == 0 then
				return 150, 120, 86
			end
			return r, g, b
		end
		-- the pad's leather back, under its leaves
		if dp <= leaf - 1 then
			local n = leather( x, y, 43 )
			return 70 + n, 42 + n * 0.6, 30 + n * 0.5
		end
		-- the tab over the lid: only where it grows out of the rim, the rest swings (quire_strap.lua, the images below)
		if quire_tab( q, x, y ) then
			if q.lid - q.r - y <= 1 then return quire_tab_pixel( q, unturned, x, y ) end
			return nil
		end
		-- (the strap under the pad: quire_strap.lua draws it)
		return nil
	end )
end

---- ribbons, bottles, shades, corners ----

-- A ribbon bookmark: silk, lighter down its middle, its end cut into a fork; 'gilt': gold threads along its edges
local function create_ribbon( def )
	local look = BOOK_LOOKS[def.key].ribbon
	local file, w, h, c = book_ribbon_image( def ), look.w, look.h, look.color
	local id = make_image( file, w, h, function( x, y )
		local t = math.abs( x - ( w - 1 ) / 2 ) / ( ( w - 1 ) / 2 )
		local k = 1.12 - 0.45 * t * t
		local weave = ( ( x + y ) % 3 == 0 ) and 0.94 or 1
		local fork = y > h - 1 - ( ( w - 1 ) / 2 - math.abs( x - ( w - 1 ) / 2 ) ) * 1.3
		if fork then return nil end
		if look.gilt and ( x == 0 or x == w - 1 ) then return 204, 164, 76 end
		return c[1] * k * weave, c[2] * k, c[3] * k
	end, true )
	image_cut_columns( file, id, w, h ) -- it lies on a page, also on a turning one
	if def.round then
		for y = 0, h - 1 do
			local row = ModImageMakeEditable( book_ribbon_row_image( def, y ), w, 1 )
			for x = 0, w - 1 do ModImageSetPixel( row, x, 0, ModImageGetPixel( id, x, y ) ) end
		end
		local flipped = ModImageMakeEditable( book_ribbon_flipped_image( def ), w, h )
		for y = 0, h - 1 do
			for x = 0, w - 1 do ModImageSetPixel( flipped, x, y, ModImageGetPixel( id, x, h - 1 - y ) ) end
		end
	end
end

-- An ink bottle: a round flask of glass with a cork, see-through where the ink is drawn behind it; and the ink at every
-- level, shaped like the inside of the flask
local BOTTLE_TOP = 7 -- where the belly starts
local function bottle_inside( x, y )
	local w, h = BOOK_BOTTLE_W, BOOK_BOTTLE_H
	if y < BOTTLE_TOP - 3 or y > h - 2 then return false end
	if y < BOTTLE_TOP then return x >= 5 and x <= 7 end -- the neck
	local cx, cy, rx, ry = ( w - 1 ) / 2, ( BOTTLE_TOP + h - 2 ) / 2, ( w - 3 ) / 2, ( h - 1 - BOTTLE_TOP ) / 2
	return ( ( x - cx ) / rx ) ^ 2 + ( ( y - cy ) / ry ) ^ 2 <= 1
end
local function create_bottles()
	local w, h = BOOK_BOTTLE_W, BOOK_BOTTLE_H
	local glass = make_image( BOOK_BOTTLE_IMAGE, w, h, function( x, y )
		local inside = bottle_inside( x, y )
		local near = false
		for _, d in ipairs( { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } ) do
			if bottle_inside( x + d[1], y + d[2] ) then near = true end
		end
		if y <= 2 and x >= 4 and x <= 8 then
			return 150 - y * 12, 102 - y * 8, 62 - y * 6 -- the cork
		elseif not inside and near then
			return 60, 54, 70, 230 -- the glass's outline
		elseif inside then
			-- a highlight on the glass, upper left
			local hl = ( x == 3 and y >= BOTTLE_TOP + 2 and y <= BOTTLE_TOP + 5 ) or ( x == 4 and y == BOTTLE_TOP + 1 )
			if hl then return 255, 255, 255, 190 end
			return 220, 230, 255, 26
		end
	end, true ) -- the bottles are drawn on the pages, also on a turning one
	image_cut_columns( BOOK_BOTTLE_IMAGE, glass, w, h )
	local rows = {}
	for y = h - 2, BOTTLE_TOP, -1 do rows[#rows + 1] = y end
	for level = 1, BOOK_BOTTLE_LEVELS do
		local id = make_image( book_fill_image( level ), w, h, function( x, y )
			if not ( bottle_inside( x, y ) and y >= ( rows[level] or BOTTLE_TOP ) ) then return nil end
			local shine = y == ( rows[level] or BOTTLE_TOP ) and 1.25 or 1
			return 255 * math.min( 1, shine ), 255, 255
		end, true )
		image_cut_columns( book_fill_image( level ), id, w, h )
	end
end

-- a soft round glow, soft shadow ramps (along x and along y), the motes, the flourish under titles
local function create_soft()
	make_image( BOOK_GLOW_IMAGE, 25, 25, function( x, y )
		local d = math.sqrt( ( x - 12 ) ^ 2 + ( y - 12 ) ^ 2 ) / 12.5
		if d < 1 then return 255, 255, 255, 255 * ( 1 - d ) ^ 2 end
	end )
	local ramp = function( t ) return 255, 255, 255, 255 * t * t end
	make_image( BOOK_SHADE_IMAGE, 16, 1, function( x ) return ramp( 1 - x / 15 ) end )
	make_image( BOOK_SHADE_R_IMAGE, 16, 1, function( x ) return ramp( x / 15 ) end )
	make_image( BOOK_SHADE_DOWN_IMAGE, 1, 16, function( x, y ) return ramp( 1 - y / 15 ) end )
	make_image( BOOK_SHADE_UP_IMAGE, 1, 16, function( x, y ) return ramp( y / 15 ) end )
	for _, right in ipairs( { false, true } ) do
		for _, bottom in ipairs( { false, true } ) do
			make_image( book_shade_end_image( right, bottom ), 16, BOOK_SHADE_END_H, function( x, y )
				local v = ( ( bottom and BOOK_SHADE_END_H - 1 - y or y ) + 0.5 ) / BOOK_SHADE_END_H
				v = v * v * ( 3 - 2 * v )
				local t = 1 - ( right and 15 - x or x ) / 15
				return 255, 255, 255, 255 * t * t * v
			end )
		end
	end
	make_image( BOOK_MOTE_IMAGE, 3, 3, function( x, y )
		local center = x == 1 and y == 1
		return 255, 255, 255, center and 255 or ( ( x == 1 or y == 1 ) and 110 or 0 )
	end )
	-- a flourish under titles: a diamond in the middle, lines tapering away, curls at the ends
	local fw, fh = 61, 7
	local fl = make_image( BOOK_FLOURISH_IMAGE, fw, fh, function( x, y )
		local cx, cy = ( fw - 1 ) / 2, ( fh - 1 ) / 2
		local dx, dy = math.abs( x - cx ), math.abs( y - cy )
		local a = 0
		if dx + dy * 1.4 <= 3 then a = dx + dy * 1.4 <= 1.5 and 255 or 200 end
		if dy == 0 and dx > 4 and dx < cx - 3 then a = 230 * ( 1 - ( dx - 4 ) / ( cx - 3 ) ) + 25 end
		local ex = cx - dx
		if dx >= cx - 5 then
			local d = math.sqrt( ( ex - 2.5 ) ^ 2 + ( y - cy + 1 ) ^ 2 )
			if math.abs( d - 1.8 ) < 0.55 then a = 160 end
		end
		if a > 0 then return 255, 255, 255, a end
	end, true )
	image_cut_columns( BOOK_FLOURISH_IMAGE, fl, fw, fh )
end

-- A page's corner turned up under the mouse (a dog-ear): the page beneath shows in the corner, the flap - the page's back,
-- lighter towards its tip - lies over it with a soft shadow along the fold. 'right': the bottom right corner.
local function create_dogear( def, right )
	local n = BOOK_LOOKS[def.key].dogear
	local f = n - 3 -- how far from the corner the fold is
	local fold = 2 * ( n - 1 ) - f
	make_image( book_dogear_image( def, right ), n, n, function( x, y )
		local cx = right and x or n - 1 - x -- as if it were the bottom right corner
		local s = cx + y
		if s > fold then
			-- the corner folded away: the page beneath shows, darker in the fold's shadow
			if s <= fold + 2 then return 118, 98, 74, 235 end
			return 196, 182, 150
		elseif cx >= n - 1 - f and y >= n - 1 - f then
			-- the flap: the page's back, lighter towards its tip, creased along the fold, outlined
			if cx == n - 1 - f or y == n - 1 - f then return 150, 132, 104 end
			if s >= fold - 1 then return 170, 152, 122 end
			local k = 0.88 + 0.14 * ( fold - s ) / f
			return 240 * k, 230 * k, 204 * k
		end
	end )
end

-- The Palm Quire's leaf curling at its edge under the mouse: the bottom of the pad's leaf lifts - its back, lighter, over
-- the leaf beneath in its shadow ('up': the top of the leaves flipped onto the lid, curling down); and a leaf's rim
-- under the top one, to stack them
local function create_quire_curls( def )
	local look, size = BOOK_LOOKS.quire, def.page
	local w, hh = look.curl, 7 -- the curl's width, the height of each half
	local r = size / 2
	local c = ( w - 1 ) / 2
	for _, up in ipairs( { false, true } ) do
		make_image( up and QUIRE_CURL_UP_IMAGE or QUIRE_CURL_IMAGE, w, 2 * hh, function( x, yy )
			local y = up and 2 * hh - 1 - yy or yy
			-- the leaf's rim at this x: how far above the image's bottom it is
			local dx = x - c
			if math.abs( dx ) >= r then return nil end
			local rim = r - math.sqrt( r * r - dx * dx ) -- 0 at the middle, more to the sides
			local from_bottom = 2 * hh - 1 - y
			local lift = hh - rim * 1.6 -- how high the flap reaches here
			if from_bottom < rim then return nil end
			if from_bottom < hh then
				-- under the flap: the leaf beneath, in the fold's shadow
				if from_bottom >= hh - 1.5 then return 118, 98, 74, 235 end
				return 196, 182, 150
			elseif from_bottom - hh <= lift then
				local k = 0.9 + 0.12 * ( from_bottom - hh ) / hh
				if from_bottom - hh >= lift - 1 then return 150, 132, 104 end
				return 240 * k, 230 * k, 204 * k
			end
		end )
	end
	make_image( QUIRE_EDGE_IMAGE, size, size, function( x, y )
		local d = math.sqrt( ( x - ( size - 1 ) / 2 ) ^ 2 + ( y - ( size - 1 ) / 2 ) ^ 2 )
		if d <= r - 0.5 then return 255, 255, 255 end
	end )
end

-- What the quire's strap is stamped with (quire_strap.lua): a disc of its dark edge, discs of leather in three shades,
-- and the buckle - a brass frame round the strap's end with its prong across, turned every way
local function create_quire_strap_images( def )
	-- the tab, turned about its root
	local q = quire_case_geometry( def )
	local root_y = q.lid - q.r
	for turn = -QUIRE_TAB_TURNS, QUIRE_TAB_TURNS do
		local a = math.rad( turn * QUIRE_TAB_STEP )
		local c, sn = math.cos( a ), math.sin( a )
		local function at( x, y )
			local ox, oy = x - QUIRE_TAB_ROOT_X, y - QUIRE_TAB_ROOT_Y
			return q.cx + ox * c + oy * sn, root_y - ox * sn + oy * c
		end
		make_image( quire_tab_image( turn ), QUIRE_TAB_W, QUIRE_TAB_H, function( x, y )
			local tx, ty = at( x, y )
			if ( tx - q.cx ) ^ 2 + ( ty - q.lid ) ^ 2 <= q.r ^ 2 then return nil end -- under the rim
			return quire_tab_pixel( q, at, x, y )
		end )
	end
	make_image( QUIRE_STRAP_EDGE_IMAGE, 7, 7, function( x, y )
		if ( x - 3 ) ^ 2 + ( y - 3 ) ^ 2 <= 3.3 ^ 2 then return 52, 32, 22 end
	end )
	for k, shade in ipairs( { 1, 0.93, 1.07 } ) do
		make_image( quire_strap_leather_image( k ), 5, 5, function( x, y )
			if ( x - 2 ) ^ 2 + ( y - 2 ) ^ 2 <= 2.4 ^ 2 then return 84 * shade, 52 * shade, 36 * shade end
		end )
	end
	for k = 0, QUIRE_STRAP_BUCKLES - 1 do
		local a = k * 2 * math.pi / QUIRE_STRAP_BUCKLES
		local ux, uy = math.cos( a ), math.sin( a )
		make_image( quire_strap_buckle_image( k ), 13, 13, function( x, y )
			local u = ( x - 6 ) * ux + ( y - 6 ) * uy -- along the strap
			local w = math.abs( -( x - 6 ) * uy + ( y - 6 ) * ux ) -- across it
			if math.abs( u ) > 3.5 or w > 4.9 then return nil end
			if w > 3.6 or math.abs( u ) > 2.9 or math.abs( u ) < 0.5 then
				local k = ( w > 4.3 or u < -2.9 ) and 0.6 or 1.05
				return BRASS[1] * k, BRASS[2] * k, BRASS[3] * k
			end
		end )
	end
end

---- letters and digits ----

-- The game's pixel font without its shadow (data/fonts/font_pixel_noshadow.xml: GuiText's letters), a letter an image:
-- GuiText can't be squeezed, so the text on a turning page is drawn letter by letter, each one squeezed and stretched
-- with the paper under it
BOOK_GLYPHS = {}      -- code point -> { width = advance, file, w, h, ox, oy } (no file: a space)
BOOK_WORD_SPACE = 6   -- the advance of a letter the font doesn't have
function book_glyph_image( code ) return BOOK_GFX .. "glyph_" .. code .. ".png" end
local function create_glyphs()
	local xml = ModTextFileGetContent( "data/fonts/font_pixel_noshadow.xml" )
	local texture = xml and xml:match( "<Texture>%s*(.-)%s*</Texture>" )
	if not texture then return end
	local font = ModImageMakeEditable( texture, 0, 0 )
	if not font or font == 0 then return end
	BOOK_WORD_SPACE = tonumber( xml:match( "<WordSpace>%s*([%d.]+)" ) ) or BOOK_WORD_SPACE
	for attrs in xml:gmatch( "<QuadChar(.-)>" ) do
		local a = {}
		for key, value in attrs:gmatch( '([%w_]+)="([^"]*)"' ) do a[key] = tonumber( value ) end
		if a.id and a.width then
			local glyph = { width = a.width, ox = a.offset_x or 0, oy = a.offset_y or 0, w = a.rect_w or 0, h = a.rect_h or 0 }
			if glyph.w > 0 and glyph.h > 0 and a.id ~= 32 then
				glyph.file = book_glyph_image( a.id )
				local id = ModImageMakeEditable( glyph.file, glyph.w, glyph.h )
				for y = 0, glyph.h - 1 do
					for x = 0, glyph.w - 1 do ModImageSetPixel( id, x, y, ModImageGetPixel( font, a.rect_x + x, a.rect_y + y ) ) end
				end
				image_bleed( id, glyph.w, glyph.h )
			end
			BOOK_GLYPHS[a.id] = glyph
		end
	end
end

-- small rounded digits for the page numbers
local DIGITS = {
	[0] = { ".#.", "#.#", "#.#", "#.#", ".#." }, { ".#.", "##.", ".#.", ".#.", "###" }, { "##.", "..#", ".#.", "#..", "###" },
	{ "##.", "..#", ".#.", "..#", "##." }, { "#.#", "#.#", "###", "..#", "..#" }, { "###", "#..", "##.", "..#", "##." },
	{ ".##", "#..", "##.", "#.#", ".#." }, { "###", "..#", ".#.", ".#.", ".#." }, { ".#.", "#.#", ".#.", "#.#", ".#." },
	{ ".#.", "#.#", ".##", "..#", "##." },
}
local function create_digits()
	for d = 0, 9 do
		make_image( book_digit_image( d ), BOOK_DIGIT_W, BOOK_DIGIT_H, function( x, y )
			return 255, 255, 255, DIGITS[d][y + 1]:sub( x + 1, x + 1 ) == "#" and 255 or 0
		end )
	end
end

function book_gfx_create()
	for _, key in ipairs( BOOK_ORDER ) do
		local def = BOOKS[key]
		create_pages( def )
		create_ribbon( def )
		if def.round then
			create_quire_case( def )
			create_quire_curls( def )
			create_quire_strap_images( def )
		else
			if key == "tome" then create_tome_cover( def ) else create_book_cover( def ) end
			create_dogear( def, true )
			create_dogear( def, false )
		end
	end
	create_bottles()
	create_soft()
	create_glyphs()
	create_digits()
end
