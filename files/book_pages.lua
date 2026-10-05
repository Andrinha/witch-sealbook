-- What is written on the books' pages, on any surface 's' (book_draw.lua: a page lying flat; page_turn.lua: a page
-- turning): the pen's kit - a drawing, a line of text in the middle, a title, an ink bottle - and the pages that are
-- the same in every run: the Spellbook's hints and the books' front pages. notebook.lua draws the rest with the kit.

BookPages = {}
local P = BookPages
local D = BookDraw

-- on paper
P.INK_COLOR = { 0.12, 0.1, 0.2 }
P.TEXT_COLOR = { 0.25, 0.18, 0.12 }
P.NOTE_COLOR = { 0.52, 0.44, 0.34 }
P.ERROR_COLOR = { 0.7, 0.15, 0.1 }
P.RIBBON_COLOR = { 0.72, 0.12, 0.18 }
P.TITLE_COLOR = { 0.46, 0.1, 0.12 }
P.GOLD_INK = { 0.7, 0.5, 0.14 }
P.NUMBER_COLOR = { 0.42, 0.31, 0.21 }

local size -- the side of the open book's page

-- every frame, before the pages are drawn
function P.begin( page_size )
	size = page_size
end

---- the pen's kit ----

-- A color dark enough to read on paper: light yellow gets as dark as deep blue
function paper_of( c )
	local k = math.min( 1, 95 / ( 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3] ) ) / 255
	return { c[1] * k, c[2] * k, c[3] * k }
end
-- an element's
function P.paper_color( key ) return paper_of( sigil_icon_color( key ) ) end

-- A stroke's color on paper: its ink's; 'element_color' replaces the conjuring ink's (the grimoire's pages, a wrong seal)
local function stroke_look( stroke, element_color, ink_key )
	if stroke.trouble then return P.ERROR_COLOR, 1 end -- what the book couldn't read (notebook.lua finish_sigil)
	local ink = INK_BY_KEY[ink_key or stroke.ink or "ink"]
	if not ink or ink.key == "ink" then return element_color or P.INK_COLOR, 1 end
	return ink.color, ink.alpha or 1
end

-- the pen's drawing on a page of the open book: 'grimoire' - in the grimoire's units, scaled to the page ('scale': a
-- little smaller, a sheet pasted in)
function P.strokes( s, list, element_color, z, ink_key, grimoire, scale )
	local frame
	if grimoire then
		frame = { c = SEAL_PAGE_SIZE / 2, k = size / SEAL_PAGE_SIZE * ( scale or 1 ), to = size / 2 }
	end
	D.strokes( s, list, stroke_look, element_color, z, ink_key, frame )
end

-- text centered on the page; 'margin': room kept free at the sides (a ribbon over the page's top edge)
function P.centered( s, y, str, color, margin )
	str = D.fitted( str, size - ( margin or 8 ) )
	s:text( ( size - GuiGetTextDimensions( D.gui(), str ) ) / 2, y, str, color )
end

-- a title with a flourish under it
function P.title( s, y, str, color )
	P.centered( s, y, str, color )
	s:image( ( size - 61 ) / 2, y + 10, BOOK_FLOURISH_IMAGE, 21, color, 0.55 )
end

-- An ink bottle 'level' full (0..1) of 'ink'; 'faded' when there is none
function P.bottle( s, px, py, ink, level, z, scale, faded )
	scale = scale or 1
	local levels = math.floor( ( level or 0 ) * BOOK_BOTTLE_LEVELS + 0.99 )
	if levels > 0 then
		local c = ink.liquid
		s:image( px, py, book_fill_image( math.min( BOOK_BOTTLE_LEVELS, levels ) ), z + 0.5, { c[1] / 255, c[2] / 255, c[3] / 255 },
			ink.alpha and 0.7 or 1, scale )
	end
	s:image( px, py, BOOK_BOTTLE_IMAGE, z, nil, faded and 0.45 or 1, scale )
end

---- the Spellbook's hints ----

-- The Spellbook's first pages: how to draw, then the book's vocabulary - the element sigils, the signs, the special and
-- decorative sigils and the frames - each with its icon, name and what it does, then the inks
-- shorter words where the dictionary's don't fit a column of the page: { name, note }
local SHORT = { flicker = { "Flickering" }, unburning = { "Unburning", "cold fire" }, aeriforms = { nil, "air bubble" },
	underfoot = { "Underfoot" }, whorl = { "Whorling" }, purification = { "Purify" }, obliviation = { "Obliviate" },
	concealment = { "Conceal" }, leech = { "Leech" }, dispersion = { nil, "outwards" }, convergence = { "Converge" },
	stability = { nil, "hangs" }, regions = { nil, "where" }, sights = { "Sights", "aims" }, strengthen = { "Strength" },
	detection = { "Detect", "seeks" }, partition = { nil, "bounds" }, refuse = { nil, "filth" }, solidify = { "Solidify" },
	envelop = { "Envelop", "wraps" }, immobility = { "Immobile" }, mimicry = { nil, "mimics" }, collection = { "Collect", "gathers" },
	gathering = { "Gather", "draws in" }, diamond = { nil, "matter" }, orb = { nil, "holds" }, purify = { "Purity" },
	link = { nil, "chains" }, stillness = { nil, "keeps" }, projection = { "Project", "at target" }, windsign = { "Spiraling" },
	aeriform = { "Aeriform", "gust" }, rain = { nil, "at target" }, rainward = { "Inv. Rain", "rain dome" }, holding = { nil, "keeps shape" },
	dancing = { "Puppets", "decoy" } }
local hints
local function hint_pages()
	if hints then return hints end
	local function row( key, name, note_text )
		local short = SHORT[key] or {}
		return { key = key, name = short[1] or name or key, note = short[2] or note_text }
	end
	local function sigil_row( key )
		local def = DICTIONARY_SIGILS[key]
		local element = def.element and DICTIONARY_ELEMENTS[def.element]
		return row( key, def.name or ( element and element.name ), def.hint )
	end
	local elements, specials, sculptures = {}, {}, {}
	for _, key in ipairs( DICTIONARY_CENTER_ORDER ) do
		local def = DICTIONARY_SIGILS[key]
		if def.shape then sculptures[#sculptures + 1] = sigil_row( key )
		elseif def.manifest or def.behavior then specials[#specials + 1] = sigil_row( key )
		else elements[#elements + 1] = sigil_row( key ) end
	end
	local basic, more = {}, {}
	local is_basic = {}
	for _, key in ipairs( DICTIONARY_BASIC_SIGNS ) do is_basic[key] = true end
	for _, key in ipairs( DICTIONARY_SIGN_ORDER ) do
		local def = DICTIONARY_SIGNS[key]
		local sign = row( key, def.name, def.hint )
		if is_basic[key] then basic[#basic + 1] = sign else more[#more + 1] = sign end
	end
	local half = math.ceil( #more / 2 )
	local more1, more2 = {}, {}
	for i, r in ipairs( more ) do if i <= half then more1[#more1 + 1] = r else more2[#more2 + 1] = r end end
	local specials1, specials2 = {}, {}
	for i, r in ipairs( specials ) do
		if i <= math.ceil( #specials / 2 ) then specials1[#specials1 + 1] = r else specials2[#specials2 + 1] = r end
	end
	local frames = {}
	for _, key in ipairs( DICTIONARY_FRAME_ORDER ) do
		local def = DICTIONARY_FRAMES[key]
		frames[#frames + 1] = row( key, def.name, def.hint )
	end
	for _, r in ipairs( sculptures ) do r.note = nil end -- ("sculpture": the page's title says it)
	local dyed = {}
	for _, ink in ipairs( INKS ) do
		if ink.key ~= "ink" then dyed[#dyed + 1] = ink end
	end
	hints = {
		{ sketch = "howto" },
		{ sketch = "elements", rows = elements },
		{ sketch = "list", kind = "sign", title = "Signs around the sigil", subtitle = "inside the ring, pointing to its middle", rows = basic,
			footer = "Dispersion + Stability: a field around you" },
		{ sketch = "list", kind = "sign", title = "More signs", rows = more1 },
		{ sketch = "list", kind = "sign", title = "More signs", rows = more2 },
		{ sketch = "margin" },
		{ sketch = "list", kind = "sigil", title = "Special sigils", subtitle = "in the middle instead of an element", rows = specials1 },
		{ sketch = "list", kind = "sigil", title = "Special sigils", subtitle = "... or drawn next to one", rows = specials2 },
		{ sketch = "list", kind = "sigil", title = "Sculptures", subtitle = "the element takes a beast's shape", rows = sculptures },
		{ sketch = "list", kind = "frame", title = "Frames", subtitle = "a big sign round the sigil, in the ring", rows = frames },
		{ title = "Inks and magical dyes", inks = { dyed[1], dyed[2], dyed[3] },
			intro_text = "A dye in a flask of ink makes a new ink - shake the flask. The bottles on the left: click one to draw with it." },
		{ title = "Inks and magical dyes", inks = { dyed[4], dyed[5], dyed[6] },
			text = "An ink's share of the lines is its share of the power. Water makes every ink run but Oil Ink." },
	}
	return hints
end

local function draw_ink_rows( s, top, width, inks )
	local x = 8
	for _, ink in ipairs( inks ) do
		P.bottle( s, x, top + 1, ink, 1, 21, 0.8 )
		local name_color = ink.alpha and { 0.36, 0.44, 0.58 } or ink.color
		s:text( x + 15, top, ink.name, name_color )
		top = D.wrapped( s, x + 15, top + 9, width - 15, "+ " .. ( ink.dye or "" ) .. ": " .. ( ink.hint or ink.text ), P.TEXT_COLOR, 9 ) + 5
	end
	return top
end

---- the guide as a witch's study notes: sketches drawn big in a fine pen, handwritten notes ----

local SKETCH_PEN = 0.7 -- the fine pen's dot radius (the book's pen: 1)

-- a template's strokes (templates.lua: unit coordinates, y down) 'k' big around cx, cy, turned by 'turn' radians
local function template_strokes( template, cx, cy, k, turn, out )
	local c, sn = math.cos( turn or 0 ), math.sin( turn or 0 )
	out = out or {}
	for _, stroke in ipairs( template ) do
		local st = {}
		for _, pt in ipairs( stroke ) do
			local x, y = ( pt[1] - 0.5 ) * k, ( pt[2] - 0.5 ) * k
			st[#st + 1] = { x = cx + x * c - y * sn, y = cy + x * sn + y * c }
		end
		out[#out + 1] = st
	end
	return out
end
local function arc( cx, cy, r, a0, a1, out )
	local st, n = {}, math.max( 6, math.floor( math.abs( a1 - a0 ) * r / 2 ) )
	for k = 0, n do
		local a = a0 + ( a1 - a0 ) * k / n
		st[#st + 1] = { x = cx + math.cos( a ) * r, y = cy + math.sin( a ) * r }
	end
	out[#out + 1] = st
	return out
end
-- the fine pen's strokes in a color
local function sketch( s, strokes, color )
	local pen = s.pen
	s.pen = SKETCH_PEN
	P.strokes( s, strokes, color )
	s.pen = pen
end
-- a handwritten heading: the words, a wavy line under them
local function heading( s, y, str, color )
	local w = GuiGetTextDimensions( D.gui(), str )
	local x0 = math.floor( ( size - w ) / 2 )
	s:text( x0, y, str, color )
	local line = {}
	for k = 0, 24 do
		local x = x0 - 3 + ( w + 6 ) * k / 24
		line[#line + 1] = { x = x, y = y + 11 + math.sin( k * 0.9 ) * 0.6 }
	end
	sketch( s, { line }, color )
end
local function note( s, cx, y, str, color )
	local w = GuiGetTextDimensions( D.gui(), str )
	s:text( math.floor( cx - w / 2 ), y, str, color or P.NOTE_COLOR )
end
-- a little arrow: from x0, y0 to x1, y1, its head at the end
local function arrow( x0, y0, x1, y1, out )
	local a = math.atan2( y1 - y0, x1 - x0 )
	out[#out + 1] = { { x = x0, y = y0 }, { x = ( x0 + x1 ) / 2 + math.sin( a ) * 2, y = ( y0 + y1 ) / 2 - math.cos( a ) * 2 }, { x = x1, y = y1 } }
	for _, side in ipairs( { 2.6, -2.6 } ) do
		out[#out + 1] = { { x = x1, y = y1 }, { x = x1 - math.cos( a + side * 0.2 ) * 4, y = y1 - math.sin( a + side * 0.2 ) * 4 } }
	end
	return out
end
local function sparkle( cx, cy, r, out )
	out[#out + 1] = { { x = cx - r, y = cy }, { x = cx + r, y = cy } }
	out[#out + 1] = { { x = cx, y = cy - r }, { x = cx, y = cy + r } }
	return out
end

-- How to draw a seal, in four sketches: a sigil in the middle, signs around facing in, the ring drawn last round them, the
-- ring closed. The ring wakes the seal the moment it closes, so it comes last (a ring drawn first and closed wakes empty:
-- the shockwave). Where the ring will go is dotted in the first two.
local function howto_page( s )
	heading( s, 6, "How to draw a seal", P.TITLE_COLOR )
	local fire = TEMPLATES_SIGILS.fire[1]
	local sign = TEMPLATES_SIGNS.levitation[1]
	local fire_color = P.paper_color( "fire" )
	local cells = { { 46, 48 }, { 134, 48 }, { 46, 116 }, { 134, 116 } }
	local notes = { { "a sigil in", "the middle" }, { "signs around,", "facing in" }, { "the ring last,", "round them" },
		{ "close the ring:", "it wakes!" } }
	local R, OPEN = 19, 1.1 -- the third sketch's ring stops this short of closing (radians)
	local START = -math.pi / 2 + 0.35
	for i, c in ipairs( cells ) do
		local x, y = c[1], c[2]
		local ink, dots, marks = {}, {}, {}
		if i <= 2 then
			for k = 0, 17 do arc( x, y, R, k * math.pi / 9, k * math.pi / 9 + 0.12, dots ) end
		elseif i == 3 then
			arc( x, y, R, START, START + 2 * math.pi - OPEN, ink )
			-- the pen goes on round to where it began
			local a = START + 2 * math.pi - OPEN + 0.25
			arrow( x + math.cos( a ) * ( R + 5 ), y + math.sin( a ) * ( R + 5 ), x + math.cos( START - 0.2 ) * ( R + 5 ),
				y + math.sin( START - 0.2 ) * ( R + 5 ), marks )
		else
			arc( x, y, R, 0, 2 * math.pi, ink )
			for k = 0, 7 do
				local a = k * math.pi / 4 + math.pi / 8
				marks[#marks + 1] = { { x = x + math.cos( a ) * ( R + 3 ), y = y + math.sin( a ) * ( R + 3 ) },
					{ x = x + math.cos( a ) * ( R + 7 ), y = y + math.sin( a ) * ( R + 7 ) } }
			end
		end
		if i >= 2 then
			for k = 0, 3 do
				local a = math.pi / 4 + k * math.pi / 2
				template_strokes( sign, x + math.cos( a ) * 12.5, y + math.sin( a ) * 12.5, 7, a - math.pi / 2, ink )
			end
		end
		if #dots > 0 then sketch( s, dots, P.NOTE_COLOR ) end
		sketch( s, ink, P.INK_COLOR )
		sketch( s, template_strokes( fire, x, y, 11 ), fire_color )
		if #marks > 0 then sketch( s, marks, i == 4 and P.GOLD_INK or P.NOTE_COLOR ) end
		s:text( x - 38, y - 26, tostring( i ) .. ".", P.TITLE_COLOR )
		note( s, x, y + R + 3, notes[i][1], P.TEXT_COLOR )
		note( s, x, y + R + 12, notes[i][2], P.TEXT_COLOR )
	end
	note( s, size / 2, 157, "LMB on its page: the book in hand casts it", P.NOTE_COLOR )
end

-- A list of symbols in two columns, each drawn big in the fine pen - a sign as it lies just inside the ring at its
-- bottom (a piece of the ring under it), pointing to the seal's middle; a sigil in its color - its name and what it
-- does beside it
local TEMPLATES_OF = { sign = "TEMPLATES_SIGNS", sigil = "TEMPLATES_SIGILS", frame = "TEMPLATES_FRAMES" }
local function list_page( s, page )
	heading( s, 6, page.title, P.TITLE_COLOR )
	if page.subtitle then note( s, size / 2, 22, page.subtitle, P.NOTE_COLOR ) end
	local rows = page.rows
	local per_column = math.ceil( #rows / 2 )
	local top = page.subtitle and 44 or 36
	local step = math.min( 30, math.floor( ( 166 - top ) / per_column ) )
	local ring = page.kind == "sign" and step >= 24 -- room for a piece of the ring under each sign
	local k = math.min( 22, step - ( ring and 6 or 4 ) )
	local templates = _G[TEMPLATES_OF[page.kind]]
	for i, row in ipairs( rows ) do
		local column, r = i <= per_column and 0 or 1, ( i - 1 ) % per_column
		local x, y = 10 + k / 2 + column * 86, top + r * step
		local template = templates[row.key] and templates[row.key][1]
		local color = page.kind == "sigil" and paper_of( sigil_symbol_color( row.key ) ) or P.INK_COLOR
		if template then sketch( s, template_strokes( template, x, y, k ), color ) end
		if ring then
			sketch( s, arc( x, y - 2.2 * k, 2.9 * k, math.pi / 2 - 0.22, math.pi / 2 + 0.22, {} ), P.NOTE_COLOR )
		end
		local tx = x + k / 2 + 5
		local room = column * 86 + 92 - tx
		s:text( tx, y - ( row.note and 9 or 4 ), D.fitted( row.name, room ), P.TEXT_COLOR )
		if row.note then s:text( tx, y, D.fitted( row.note, room ), P.NOTE_COLOR ) end
	end
	if page.footer then note( s, size / 2, 157, page.footer, P.NOTE_COLOR ) end
end

-- The element sigils, each drawn big in its color, its name under it
local function elements_page( s, rows )
	heading( s, 6, "The element sigils", P.TITLE_COLOR )
	note( s, size / 2, 22, "one in the middle of every seal", P.NOTE_COLOR )
	local per_row, cw = 4, ( size - 16 ) / 4
	for i, row in ipairs( rows ) do
		local r, col = math.floor( ( i - 1 ) / per_row ), ( i - 1 ) % per_row
		local in_row = math.min( per_row, #rows - r * per_row )
		local x = 8 + ( col + 0.5 ) * cw + ( per_row - in_row ) * cw / 2
		local y = 50 + r * 42
		local template = TEMPLATES_SIGILS[row.key] and TEMPLATES_SIGILS[row.key][1]
		if template then sketch( s, template_strokes( template, x, y, 24 ), P.paper_color( row.key ) ) end
		note( s, x, y + 15, row.name, P.TEXT_COLOR )
	end
end

-- Notes in the margin: how the same sign acts drawn another way - facing out, turned sideways, bigger - and a frame
local function margin_page( s )
	heading( s, 6, "Notes in the margin", P.TITLE_COLOR )
	local fire, sign = TEMPLATES_SIGILS.fire[1], TEMPLATES_SIGNS.levitation[1]
	local fire_color = P.paper_color( "fire" )
	local R = 17
	local function seal( x, y, framed )
		sketch( s, arc( x, y, R, 0, 2 * math.pi, {} ), P.INK_COLOR )
		sketch( s, template_strokes( fire, x, y, framed and 8 or 10 ), fire_color )
	end
	-- facing out: the other way round
	local x, y = 46, 50
	seal( x, y )
	sketch( s, template_strokes( sign, x, y + 11, 8, math.pi ), P.INK_COLOR )
	sketch( s, arrow( x + 9, y + 12, x + 9, y + 26, {} ), P.GOLD_INK )
	note( s, x, y + R + 6, "facing out:", P.TEXT_COLOR )
	note( s, x, y + R + 15, "the other way", P.NOTE_COLOR )
	-- sideways: it spins
	x = 134
	seal( x, y )
	sketch( s, template_strokes( sign, x, y + 11, 8, math.pi / 2 ), P.INK_COLOR )
	local spin = arc( x, y, R + 5, -0.4, 1.0, {} )
	local tip = spin[1][#spin[1]]
	spin[#spin + 1] = { { x = tip.x, y = tip.y }, { x = tip.x + 3.5, y = tip.y - 1 } }
	spin[#spin + 1] = { { x = tip.x, y = tip.y }, { x = tip.x + 0.5, y = tip.y - 4 } }
	sketch( s, spin, P.GOLD_INK )
	note( s, x, y + R + 6, "sideways:", P.TEXT_COLOR )
	note( s, x, y + R + 15, "it spins", P.NOTE_COLOR )
	-- bigger: stronger
	x, y = 46, 110
	sketch( s, template_strokes( sign, x - 15, y + 6, 8 ), P.INK_COLOR )
	sketch( s, template_strokes( sign, x + 9, y, 22 ), P.INK_COLOR )
	sketch( s, sparkle( x + 22, y - 12, 2, sparkle( x + 19, y - 4, 1.2, {} ) ), P.GOLD_INK )
	note( s, x, y + R + 6, "a bigger sign:", P.TEXT_COLOR )
	note( s, x, y + R + 15, "stronger", P.NOTE_COLOR )
	-- a frame round the sigil
	x = 134
	seal( x, y, true )
	sketch( s, template_strokes( TEMPLATES_FRAMES.holding[1], x, y, 24 ), P.INK_COLOR )
	note( s, x, y + R + 6, "a frame: round", P.TEXT_COLOR )
	note( s, x, y + R + 15, "the sigil", P.NOTE_COLOR )
	note( s, size / 2, 157, "Seals learned: [Grimoire] above", P.NOTE_COLOR )
end

function P.hint_page( s, p )
	local margin = 8
	local width = size - 2 * margin
	local page = hint_pages()[p]
	if not page then return end
	if page.sketch == "howto" then return howto_page( s ) end
	if page.sketch == "elements" then return elements_page( s, page.rows ) end
	if page.sketch == "list" then return list_page( s, page ) end
	if page.sketch == "margin" then return margin_page( s ) end
	heading( s, 6, page.title, P.TITLE_COLOR )
	local top = 22
	if page.intro_text then top = D.wrapped( s, margin, top, width, page.intro_text, P.NOTE_COLOR, 9 ) + 3 end
	top = draw_ink_rows( s, top, width, page.inks )
	if page.text then D.wrapped( s, margin, top + 1, width, page.text, P.NOTE_COLOR, 9 ) end
end

---- the front pages ----

-- The front of a book, drawn with the pen as the seals are: on the Spellbook's title page a witch's hat in a seal's ring,
-- on the Great Tome's an eye in a seal's ring, three more round it - the Brimmed Caps' eye, Noita's Kolmisilmä; their
-- bookplates (ex libris) show something else: an inkwell with a quill, the Tower of Tomes
do
	local arts = {}
	local function arc_stroke( cx, cy, r, a0, a1, n )
		local st = {}
		for k = 0, n do
			local a = a0 + ( a1 - a0 ) * k / n
			st[#st + 1] = { x = cx + math.cos( a ) * r, y = cy + math.sin( a ) * r }
		end
		return st
	end
	local function curve_stroke( pts, n, st )
		st = st or {}
		local p0, p1, p2, p3 = pts[1], pts[2], pts[3], pts[4]
		for k = ( #st > 0 and 1 or 0 ), n do
			local t = k / n
			local u = 1 - t
			st[#st + 1] = { x = u ^ 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ^ 3 * p3[1],
				y = u ^ 3 * p0[2] + 3 * u * u * t * p1[2] + 3 * u * t * t * p2[2] + t ^ 3 * p3[2] }
		end
		return st
	end
	-- a witch's hat, its brim's middle at cx, cy, 'k' its size (1: the brim 64 wide), after the one on the mod's cover:
	-- the brim dips towards us and its tips curl up, the crown leans and its tip falls over to the right and curls; a band,
	-- with a buckle on a big hat
	local function hat_strokes( cx, cy, k, out )
		local function at( x, y ) return { cx + x * k, cy + y * k } end
		local function curve( pts, n, st ) return curve_stroke( { at( pts[1], pts[2] ), at( pts[3], pts[4] ), at( pts[5], pts[6] ), at( pts[7], pts[8] ) }, n, st ) end
		-- the brim: its front, and its back where the crown doesn't hide it
		out[#out + 1] = curve( { 0, 5, 17, 5, 29, -2, 32, -10 }, 14, curve( { -32, -10, -29, -2, -17, 5, 0, 5 }, 14 ) )
		out[#out + 1] = curve( { -32, -10, -27, -6, -18, -7, -11, -8 }, 8 )
		out[#out + 1] = curve( { 11, -8, 18, -7, 27, -6, 32, -10 }, 8 )
		-- the crown: its left side up to the tip falling over and curling, its right side up to the fold
		local crown = curve( { -11, -8, -10, -22, -8, -33, -1, -41 }, 14 )
		curve( { -1, -41, 6, -49, 18, -50, 22, -42 }, 12, crown )
		out[#out + 1] = curve( { 22, -42, 24, -37, 19, -34, 17, -38 }, 8, crown )
		out[#out + 1] = curve( { 7, -35, 8, -41, 15, -43, 18, -40 }, 8, curve( { 11, -8, 10, -19, 6, -28, 7, -35 }, 12 ) )
		-- the band
		out[#out + 1] = curve( { -10.6, -10, -4, -8, 4, -8, 10.6, -10 }, 10 )
		out[#out + 1] = curve( { -10, -15, -3, -13, 3, -13, 10, -15 }, 10 )
		if k >= 0.6 then
			local buckle = {}
			for _, c in ipairs( { { -2.5, -8.5 }, { -2.5, -13.5 }, { 2.5, -13.5 }, { 2.5, -8.5 }, { -2.5, -8.5 } } ) do
				buckle[#buckle + 1] = { x = cx + c[1] * k, y = cy + c[2] * k }
			end
			out[#out + 1] = buckle
		end
	end
	-- an eye 2w wide: its lids, the iris and the pupil
	local function eye_strokes( cx, cy, w, out )
		local h = w * 0.5
		out[#out + 1] = curve_stroke( { { cx - w, cy }, { cx - w * 0.45, cy - h * 1.3 }, { cx + w * 0.45, cy - h * 1.3 }, { cx + w, cy } }, 14 )
		out[#out + 1] = curve_stroke( { { cx - w, cy }, { cx - w * 0.45, cy + h * 1.1 }, { cx + w * 0.45, cy + h * 1.1 }, { cx + w, cy } }, 14 )
		out[#out + 1] = arc_stroke( cx, cy, h * 0.78, 0, 2 * math.pi, 20 )
		out[#out + 1] = arc_stroke( cx, cy, math.max( 0.6, h * 0.22 ), 0, 2 * math.pi, 8 )
	end
	local function sparkle( cx, cy, r, out )
		out[#out + 1] = { { x = cx - r, y = cy }, { x = cx + r, y = cy } }
		out[#out + 1] = { { x = cx, y = cy - r }, { x = cx, y = cy + r } }
	end
	-- a seal's double ring with ticks between
	local function seal_ring( em, out, ticks )
		out[#out + 1] = arc_stroke( em.x, em.y, em.r, 0, 2 * math.pi, 96 )
		out[#out + 1] = arc_stroke( em.x, em.y, em.r - 6, 0, 2 * math.pi, 84 )
		for k = 0, ticks - 1 do
			local a = k * 2 * math.pi / ticks
			out[#out + 1] = { { x = em.x + math.cos( a ) * ( em.r - 6 ), y = em.y + math.sin( a ) * ( em.r - 6 ) },
				{ x = em.x + math.cos( a ) * em.r, y = em.y + math.sin( a ) * em.r } }
		end
	end
	local function poly( ox, oy, pts )
		local st = {}
		for _, c in ipairs( pts ) do st[#st + 1] = { x = ox + c[1], y = oy + c[2] } end
		return st
	end
	-- the Spellbook's bookplate: an inkwell, its bottom's middle at cx, cy, with a quill dipped in it
	local function quill_strokes( cx, cy, out, gold )
		out[#out + 1] = poly( cx, cy, { { -4, -11 }, { -4, -9 }, { -9, -7 }, { -10, -3 }, { -9, 0 }, { 9, 0 }, { 10, -3 }, { 9, -7 }, { 4, -9 }, { 4, -11 } } )
		out[#out + 1] = poly( cx, cy, { { -5.5, -11.5 }, { 5.5, -11.5 } } )
		out[#out + 1] = poly( cx, cy, { { -7, -4 }, { 7, -4 } } )
		-- the quill: its shaft from the well up to the right, the vane round its upper part, wider on the top side
		local x0, y0, x1, y1 = cx + 1, cy - 10, cx + 29, cy - 26
		local len = math.sqrt( ( x1 - x0 ) ^ 2 + ( y1 - y0 ) ^ 2 )
		local dx, dy = ( x1 - x0 ) / len, ( y1 - y0 ) / len
		local function at( t, side ) return { x = x0 + dx * len * t + dy * side, y = y0 + dy * len * t - dx * side } end
		out[#out + 1] = { at( 0, 0 ), at( 1, 0 ) }
		for _, w in ipairs( { 5, -3.5 } ) do
			local st = {}
			for k = 0, 12 do
				local t = 0.3 + 0.7 * k / 12
				st[#st + 1] = at( t, w * math.sin( math.pi * ( t - 0.3 ) / 0.7 ) ^ 0.7 * ( 1 - 0.35 * ( t - 0.3 ) / 0.7 ) )
			end
			out[#out + 1] = st
		end
		-- a notch in the vane, and a drop of ink at the nib
		out[#out + 1] = { at( 0.62, 4.6 ), at( 0.56, 2.2 ) }
		gold[#gold + 1] = poly( cx, cy, { { 1, -13.5 }, { 2, -15.5 }, { 3, -13.5 }, { 2, -12.5 }, { 1, -13.5 } } )
	end
	-- the Great Tome's bookplate: the Tower of Tomes, a stack of books with a pointed roof and a pennant, its bottom's
	-- middle at cx, cy
	local function tower_strokes( cx, cy, out, gold )
		out[#out + 1] = poly( cx, cy, { { -30, 0.5 }, { 30, 0.5 } } )
		local y = 0
		for _, b in ipairs( { { 30, 0, 6 }, { 26, 2, 5 }, { 28, -2, 5 }, { 22, 1, 5 }, { 24, -1, 5 }, { 19, 1, 4 } } ) do
			local w, off, h = b[1], b[2], b[3]
			local l, r = off - w / 2, off + w / 2
			out[#out + 1] = poly( cx, cy, { { l, y }, { l, y - h }, { r, y - h }, { r, y }, { l, y } } )
			-- the spine's bands
			out[#out + 1] = poly( cx, cy, { { l + 3, y - 1 }, { l + 3, y - h + 1 } } )
			out[#out + 1] = poly( cx, cy, { { r - 3, y - 1 }, { r - 3, y - h + 1 } } )
			y = y - h
		end
		-- the roof leaning a little, the window under it, the pennant on its tip
		out[#out + 1] = curve_stroke( { { cx - 11, cy + y }, { cx - 7, cy + y - 6 }, { cx - 2, cy + y - 13 }, { cx + 2, cy + y - 19 } }, 10,
			curve_stroke( { { cx + 2, cy + y - 19 }, { cx + 4, cy + y - 12 }, { cx + 8, cy + y - 5 }, { cx + 13, cy + y } }, 10 ) )
		out[#out + 1] = poly( cx, cy, { { -1, y - 1 }, { -1, y - 5 }, { 1, y - 7 }, { 3, y - 5 }, { 3, y - 1 } } )
		gold[#gold + 1] = poly( cx, cy, { { 2, y - 19 }, { 2, y - 25 }, { 10, y - 23 }, { 2, y - 21 } } )
		-- a crescent moon over the tower
		gold[#gold + 1] = arc_stroke( cx - 22, cy + y - 10, 5, math.pi * 0.35, math.pi * 1.65, 12 )
		gold[#gold + 1] = arc_stroke( cx - 20.5, cy + y - 10, 3.6, math.pi * 0.42, math.pi * 1.58, 10 )
	end
	local function get_art( key )
		if arts[key] then return arts[key] end
		local look = BOOK_LOOKS[key]
		local em, plate = look.emblem, look.plate
		local ink, gold, small, small_gold = {}, {}, {}, {}
		local cx = plate.x + plate.w / 2
		if key == "tome" then
			seal_ring( em, ink, 16 )
			eye_strokes( em.x, em.y, 17, ink )
			for i = 0, 2 do
				local a = -math.pi / 2 + i * 2 * math.pi / 3
				eye_strokes( em.x + math.cos( a ) * ( em.r + 11 ), em.y + math.sin( a ) * ( em.r + 11 ) + 1, 5, gold )
			end
			for _, st in ipairs( { { -52, -34, 3 }, { 54, -30, 2.5 }, { -50, 36, 2 }, { 52, 40, 3 } } ) do
				sparkle( em.x + st[1], em.y + st[2], st[3], gold )
			end
			tower_strokes( cx, plate.y + 77, small, small_gold )
			sparkle( cx - 30, plate.y + 46, 2, small_gold )
			sparkle( cx + 27, plate.y + 58, 1.5, small_gold )
			sparkle( cx + 33, plate.y + 32, 2, small_gold )
		else
			seal_ring( em, ink, 12 )
			hat_strokes( em.x - 1, em.y + 14, 0.66, ink )
			sparkle( em.x + 13, em.y - 25, 2.5, gold )
			for _, st in ipairs( { { -46, -24, 3 }, { 47, -18, 2.5 }, { -44, 26, 2 }, { 45, 28, 3 }, { 0, -44, 2 } } ) do
				sparkle( em.x + st[1], em.y + st[2], st[3], gold )
			end
			quill_strokes( cx - 9, plate.y + 46, small, small_gold )
			sparkle( cx - 26, plate.y + 28, 2, small_gold )
			sparkle( cx + 28, plate.y + 42, 1.5, small_gold )
		end
		arts[key] = { ink = ink, gold = gold, small = small, small_gold = small_gold }
		return arts[key]
	end

	local function centered_text( s, y, str, color, scale )
		local w = GuiGetTextDimensions( D.gui(), str, scale or 1 )
		s:text( math.floor( ( size - w ) / 2 ), y, str, color, nil, scale )
	end

	local TEXTS = {
		-- the owner on the bookplate: Noita, the witch ("noita" is Finnish for witch); the Tome is the Tower's own
		book = { name = "SPELLBOOK", under = "seals, inks and notes", owner = "NOITA" },
		tome = { name = "GREAT TOME", under = "seals too great for a notebook", owner = "TOWER OF TOMES" },
	}
	-- page 'p' (1: the bookplate, 2: the title) of the book 'key', whose look is 'look' (book_gfx.lua BOOK_LOOKS)
	function P.front_page( s, p, key, look )
		local art, texts = get_art( key ), TEXTS[key] or TEXTS.book
		if p == 1 then
			local plate = look.plate
			centered_text( s, plate.y + 8, "EX LIBRIS", P.TITLE_COLOR )
			P.strokes( s, art.small, P.INK_COLOR )
			P.strokes( s, art.small_gold, P.GOLD_INK )
			centered_text( s, plate.y + plate.h - 30, texts.owner, P.TITLE_COLOR )
			s:image( math.floor( ( size - 61 ) / 2 ), plate.y + plate.h - 19, BOOK_FLOURISH_IMAGE, 24, P.TEXT_COLOR, 0.8 )
		else
			P.strokes( s, art.ink, P.INK_COLOR )
			P.strokes( s, art.gold, P.GOLD_INK )
			local y = look.emblem.y + look.emblem.r + 13 + ( key == "tome" and 10 or 0 )
			centered_text( s, y, "T H E", P.NOTE_COLOR )
			centered_text( s, y + 9, texts.name, P.TITLE_COLOR, 2 )
			s:image( math.floor( ( size - 61 ) / 2 ), y + 33, BOOK_FLOURISH_IMAGE, 24, P.TEXT_COLOR, 0.8 )
			centered_text( s, y + 42, texts.under, P.NOTE_COLOR )
		end
	end
end
