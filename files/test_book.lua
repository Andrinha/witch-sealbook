-- The Test Book (books.lua BOOKS.test): every sigil with every sign, drawn in advance, to try out in the game how they
-- work together. While the mod is made it lies beside the witch (setting test_book_at_spawn).
-- Its pages are made here, not drawn by hand: a seal tree - what parse_seal reads a drawing as: sigils in the middle,
-- signs round them, a frame - is compiled into the page's spell (compile_spell), and drawn from the templates
-- (templates.lua). A click on a page makes it the book's active seal (notebook.lua). The pages, in groups:
--   Sigils, Condensed, Mixes - every element (its sigil; a sigil with Convergence; two sigils mixed) in every form:
--       Splash (no sign of form), Field (Dispersion and Stability), Column, Wave (Dispersion), Orb (Levitation with smaller columns: it flies), Hanging
--       (Levitation alone), Rain (the Sign of Rain round the sigil), Ring (Regions pointing in and out); first plain,
--       then with a pair of each other sign - the pairs tests/test_sign_effects.py checks
--   Special, Frames, Creatures - every special sigil, frame and decorative sigil: alone, with each element sigil, and
--       with a pair of each sign
-- A sign that does nothing to a seal is left out of its spell (seal_spell.lua): that seal has no page with it.
--   TestBook.pages()      -> the pages: { key, name, title, sign, effect, spell (what cast.lua reads), color, tree, plain (the
--                            page of the same seal without the sign tried) }
--   TestBook.notes( p )   -> what its seal does, beside the plain one's, and what it is drawn of (spell_notes.lua)
--   TestBook.page( key )  -> one of them
--   TestBook.sections()   -> the groups: { name, page, items = { { name, page, parts = { { name, page } } } } }
--   TestBook.strokes( p ) -> a page's drawing, on the grimoire's page (SEAL_PAGE_SIZE, the ring round its middle)

TestBook = {}
local T = TestBook

local R = 70           -- the ring's radius on the grimoire's page
local SCORE = 0.9      -- how well the symbols are drawn: cleanly, the seals don't misfire
local SIGN_DIST, SIGN_SIZE = 0.7, 0.25 -- shares of the radius
local SIGIL_SIZE = 0.45
local FRAME_SIZE = 0.95
local PAIR_SHRINK, PAIR_X = 1.6, 0.27  -- two sigils side by side: smaller, this far from the middle
local SPIN_TURN = math.rad( 45 )       -- the form's signs turned sideways this much: the seal spins

-- where signs go: pairs facing each other across the ring (degrees from the right, 90 at the bottom)
local PAIRS = { { 90, 270 }, { 0, 180 }, { 45, 225 }, { 135, 315 } }

-- The forms, by the signs that make them: { sign, the pair it stands on (PAIRS), size, inverted, with = { a sign drawn
-- with it = this sign's size then } }; 'pairs': the pairs the other signs take, in order; 'sigil', 'dist': the sigil's
-- size and the signs' distance, if not the usual
local FORMS = {
	{ name = "Splash" },
	-- Dispersion held by Stability: the field round the caster
	{ name = "Field", signs = { { "dispersion", 1 }, { "stability", 2 } } },
	{ name = "Column", signs = { { "column", 1 } } },
	{ name = "Wave", signs = { { "dispersion", 1 } } },
	-- Levitation with columns smaller than it: the orb takes Levitation's form but flies (with the Orb sign, which is
	-- Levitation too, the columns are full size)
	{ name = "Orb", signs = { { "levitation", 1 }, { "column", 2, size = 0.15, with = { orb = SIGN_SIZE } } } },
	{ name = "Hanging", signs = { { "levitation", 1 } } },
	-- the Sign of Rain round the sigil, the signs between it and the ring, clear of its corners
	{ name = "Rain", frame = "rain", sigil = 0.3, dist = 0.8, pairs = { 2, 1 } },
	-- Regions pointing at each other: in at the top and the bottom, out at the sides
	{ name = "Ring", signs = { { "regions", 1 }, { "regions", 2, inverted = true } } },
}

local function sign_name( key ) return DICTIONARY_SIGNS[key].name end

-- The signs tried on every seal: a pair facing the middle, a pair facing outwards where that means something else,
-- Regions alone facing out (it launches), the form's own signs turned sideways (it spins). Signs of form are the forms.
local VARIANTS
local function variants()
	if VARIANTS then return VARIANTS end
	VARIANTS = {}
	for _, key in ipairs( DICTIONARY_SIGN_ORDER ) do
		local def = DICTIONARY_SIGNS[key]
		local b = def.behavior
		if b and b ~= "thrust" and b ~= "float" then
			VARIANTS[#VARIANTS + 1] = { key = key, name = sign_name( key ) }
			local inv = def.inverted
			if inv and def.invertible ~= false and ( def.symmetry or 1 ) % 2 == 1 and inv.behavior and inv.behavior ~= b then
				VARIANTS[#VARIANTS + 1] = { key = key, inverted = true, name = sign_name( key ) .. " facing out" }
			end
		end
	end
	VARIANTS[#VARIANTS + 1] = { key = "regions", inverted = true, one = true, name = "one Regions facing out" }
	VARIANTS[#VARIANTS + 1] = { turn = SPIN_TURN, name = "signs turned sideways" }
	return VARIANTS
end

---- seal trees ----

local function sigil_symbol( key, x, y, size )
	return { kind = "sigil", key = key, size = size, score = SCORE, inverted = false, x = x, y = y,
		angle = math.atan2( y, x ), dist = math.sqrt( x * x + y * y ) }
end

-- a sign at 'deg' on the ring facing the middle (inverted: outwards), turned sideways by 'turn'
local function sign_symbol( key, deg, size, dist, inverted, turn )
	local a = math.rad( deg )
	local tilt = ( inverted and math.pi or 0 ) + ( turn or 0 )
	return { kind = "sign", key = key, angle = a, dist = dist, size = size, score = SCORE, inverted = inverted or false,
		turn = turn or 0, dir = a - math.pi + tilt }
end

-- the sigils in the middle: one, or side by side
local function sigil_symbols( keys, size, out )
	if #keys == 1 then
		out[#out + 1] = sigil_symbol( keys[1], 0, 0, size )
	elseif #keys == 2 then
		local x = PAIR_X * size / SIGIL_SIZE
		out[#out + 1] = sigil_symbol( keys[1], -x, 0, size / PAIR_SHRINK )
		out[#out + 1] = sigil_symbol( keys[2], x, 0, size / PAIR_SHRINK )
	end
	return out
end

-- A seal: 'sigils' (keys) in the form 'form' (FORMS), 'condense': with a pair of Convergence, 'variant' (variants())
local function seal_tree( sigils, form, condense, variant )
	local symbols = sigil_symbols( sigils, form.sigil or SIGIL_SIZE, {} )
	local dist = form.dist or SIGN_DIST
	local free, taken = {}, {}
	for _, s in ipairs( form.signs or {} ) do taken[s[2]] = true end
	for _, i in ipairs( form.pairs or { 1, 2, 3, 4 } ) do if not taken[i] then free[#free + 1] = i end end
	local turn = variant and variant.turn
	for _, s in ipairs( form.signs or {} ) do
		for _, deg in ipairs( PAIRS[s[2]] ) do
			local size = s.with and variant and s.with[variant.key] or s.size or SIGN_SIZE
			symbols[#symbols + 1] = sign_symbol( s[1], deg, size, dist, s.inverted, turn )
		end
	end
	local function pair( key, inverted, one )
		local at = PAIRS[table.remove( free, 1 )]
		for k = 1, one and 1 or 2 do symbols[#symbols + 1] = sign_symbol( key, at[k], SIGN_SIZE, dist, inverted ) end
	end
	if condense then pair( "convergence" ) end
	if variant and variant.key then pair( variant.key, variant.inverted, variant.one ) end
	local frames = {}
	if form.frame then frames[1] = { key = form.frame, score = SCORE, size = FRAME_SIZE } end
	return { ring = { x = 0, y = 0, r = R, roundness = 0 }, symbols = symbols, layers = {}, frames = frames, subs = {},
		links = {}, glaives = 0 }
end

-- what a seal is drawn of, in words: "Fire, 2 Column, 2 Pulling facing out, the Sign of Rain"
local function recipe_text( tree )
	local parts, count, order = {}, {}, {}
	for _, sym in ipairs( tree.symbols ) do
		local name
		if sym.kind == "sigil" then
			local def = DICTIONARY_SIGILS[sym.key]
			name = def.name or DICTIONARY_ELEMENTS[def.element].name
		else
			name = sign_name( sym.key ) .. ( sym.inverted and " facing out" or "" ) .. ( sym.turn ~= 0 and " turned" or "" )
		end
		if not count[name] then order[#order + 1] = name end
		count[name] = ( count[name] or 0 ) + 1
	end
	for _, name in ipairs( order ) do parts[#parts + 1] = ( count[name] > 1 and ( count[name] .. " " ) or "" ) .. name end
	for _, frame in ipairs( tree.frames ) do parts[#parts + 1] = "the Sign of " .. DICTIONARY_FRAMES[frame.key].name end
	return #parts > 0 and table.concat( parts, ", " ) or "the ring alone"
end

---- the pages ----

local PAGES, BY_KEY, SECTIONS

-- the spell of a seal tree; a seal the book can't compile has no page (TestBook.errors: what went wrong)
T.errors = {}
local function compile( tree )
	local ok, spell = pcall( compile_spell, tree )
	if ok then return spell end
	T.errors[#T.errors + 1] = tostring( spell )
end

local function same_kind( a, b )
	return a.element == b.element and a.form == b.form and a.floats == b.floats and a.manifest == b.manifest
		and a.shape == b.shape
end
-- the sign added something the seal didn't do without it
local function gained( spell, base )
	for key in pairs( spell.behaviors ) do if not base.behaviors[key] then return true end end
	return false
end

-- a page: its title (the item and the part of it) over the seal, the sign tried under it; 'plain': the page without the
-- sign. Returns its number.
local function add_page( item, part, key, tree, spell, sign, plain )
	local title = item.name .. " - " .. part.name
	PAGES[#PAGES + 1] = { key = "test:" .. key, test = true, name = title .. ", " .. sign, title = title, sign = sign,
		spell = seal_page_data( spell ), color = spell.element, tree = tree, plain = plain,
		effect = "Casts: " .. spell.summary .. ". Drawn: " .. recipe_text( tree ) .. "."
			.. ( spell.quality ~= "Flawless seal!" and ( " " .. spell.quality .. "." ) or "" ) }
	BY_KEY[PAGES[#PAGES].key] = PAGES[#PAGES]
	if not part.page then part.page = #PAGES end
	if not item.page then item.page = #PAGES end
	return #PAGES
end

local function new_part( item, name )
	local part = { name = name }
	item.parts[#item.parts + 1] = part
	return part
end

-- an element in every form, plain and with each sign that does something there
local function element_pages( item, sigils, condense )
	for i, form in ipairs( FORMS ) do
		local part = new_part( item, form.name )
		local tree = seal_tree( sigils, form, condense )
		local base = compile( tree )
		if base then
			local key = item.key .. "/" .. form.name:lower()
			local plain = add_page( item, part, key, tree, base, "plain" )
			for _, v in ipairs( variants() ) do
				local t = seal_tree( sigils, form, condense, v )
				local spell = compile( t )
				if spell and same_kind( spell, base ) and gained( spell, base ) then
					add_page( item, part, key .. "/" .. ( v.key or "turned" ) .. ( v.inverted and "_out" or "" ) .. ( v.one and "_one" or "" ),
						t, spell, v.name, plain )
				end
			end
		end
	end
end

-- a special or decorative sigil (or a frame: 'frame'), alone, with each element sigil, with each sign it takes
local function special_pages( item, sigils, frame, elements )
	local form = frame and { name = "", frame = frame, sigil = 0.3, dist = 0.8, pairs = { 2, 1 } } or FORMS[1]
	local tree = seal_tree( sigils, form )
	local base = compile( tree )
	if not base then return end
	local alone = add_page( item, new_part( item, "Alone" ), item.key, tree, base, "alone" )
	local part = new_part( item, "Elements" )
	for _, e in ipairs( elements ) do
		local both = { sigils[1], e.sigil }
		if frame then both = { e.sigil } end
		local t = seal_tree( both, form )
		local spell = compile( t )
		if spell then add_page( item, part, item.key .. "/" .. e.sigil, t, spell, "with " .. e.name, alone ) end
	end
	part = new_part( item, "Signs" )
	for _, v in ipairs( variants() ) do
		local t = seal_tree( sigils, form, false, v )
		local spell = compile( t )
		if spell and same_kind( spell, base ) and gained( spell, base ) then
			add_page( item, part, item.key .. "/" .. ( v.key or "turned" ) .. ( v.inverted and "_out" or "" ) .. ( v.one and "_one" or "" ),
				t, spell, v.name, alone )
		end
	end
end

local function build()
	PAGES, BY_KEY, SECTIONS = {}, {}, {}
	local function group( name )
		local g = { name = name, items = {} }
		SECTIONS[#SECTIONS + 1] = g
		return g
	end
	local function item( g, key, name )
		local it = { key = key, name = name, parts = {} }
		g.items[#g.items + 1] = it
		return it
	end
	local sigils, condensed, mixes = group( "Sigils" ), group( "Condensed" ), group( "Mixes" )
	-- the element sigils: each element's own (the first of them), every one a tab of its own
	local elements, own, seen = {}, {}, {}
	for _, key in ipairs( DICTIONARY_CENTER_ORDER ) do
		local def = DICTIONARY_SIGILS[key]
		if def.element and not def.manifest and not def.shape then
			local name = def.name or DICTIONARY_ELEMENTS[def.element].name
			element_pages( item( sigils, key, name ), { key } )
			if not def.behavior and not own[def.element] then
				own[def.element], seen[def.element] = key, true
				elements[#elements + 1] = { sigil = key, name = name }
			end
		end
	end
	-- two sigils mixed, in the order the mixes name them
	local mixed, order = {}, DICTIONARY_SIGIL_ORDER
	for i = 1, #order do
		for j = i + 1, #order do
			local mix = DICTIONARY_MIXES[order[i] .. "+" .. order[j]]
			local a, b = own[order[i]], own[order[j]]
			if mix and a and b and not seen[mix] then
				seen[mix] = true
				mixed[#mixed + 1] = { element = mix, sigils = { a, b } }
			end
		end
	end
	-- the element sigils and the mixes condensed by Convergence, then the mixes
	local list = {}
	for _, e in ipairs( elements ) do list[#list + 1] = { element = DICTIONARY_SIGILS[e.sigil].element, sigils = { e.sigil } } end
	for _, m in ipairs( mixed ) do list[#list + 1] = m end
	for _, e in ipairs( list ) do
		local into = DICTIONARY_ELEMENTS[e.element].condensed
		if into and not seen[into] then
			seen[into] = true
			element_pages( item( condensed, into, DICTIONARY_ELEMENTS[into].name ), e.sigils, true )
		end
	end
	for _, m in ipairs( mixed ) do element_pages( item( mixes, m.element, DICTIONARY_ELEMENTS[m.element].name ), m.sigils ) end
	-- the sigils, frames and creatures that manifest in a way of their own (the pages follow the groups' order)
	local special = group( "Special" )
	local empty = item( special, "empty", "Empty Ring" )
	local tree = seal_tree( {}, FORMS[1] )
	local spell = compile( tree )
	if spell then add_page( empty, new_part( empty, "Alone" ), "empty", tree, spell, "nothing inside" ) end
	for _, key in ipairs( DICTIONARY_CENTER_ORDER ) do
		local def = DICTIONARY_SIGILS[key]
		if def.manifest and not def.shape then special_pages( item( special, key, def.name ), { key }, nil, elements ) end
	end
	local frames = group( "Frames" )
	for _, key in ipairs( DICTIONARY_FRAME_ORDER ) do
		if DICTIONARY_FRAMES[key].manifest then
			special_pages( item( frames, key, DICTIONARY_FRAMES[key].name ), {}, key, elements )
		end
	end
	local creatures = group( "Creatures" )
	for _, key in ipairs( DICTIONARY_CENTER_ORDER ) do
		local def = DICTIONARY_SIGILS[key]
		if def.shape then special_pages( item( creatures, key, def.name ), { key }, nil, elements ) end
	end
	-- the first page of each group, item and part; the parts with no page left out
	for _, g in ipairs( SECTIONS ) do
		for _, it in ipairs( g.items ) do
			local parts = {}
			for _, part in ipairs( it.parts ) do if part.page then parts[#parts + 1] = part end end
			it.parts = parts
			g.page = g.page or it.page
		end
	end
end

function T.pages()
	if not PAGES then build() end
	return PAGES
end

function T.page( key )
	if not PAGES then build() end
	return BY_KEY[key]
end

function T.sections()
	if not PAGES then build() end
	return SECTIONS
end

function T.notes( page )
	if not page.notes then
		page.notes = spell_notes( page.spell, page.plain and PAGES[page.plain].spell )
		page.notes[#page.notes + 1] = { text = "Drawn: " .. recipe_text( page.tree ), kind = "drawn" }
	end
	return page.notes
end

---- drawing a page ----

-- a template's strokes, the bigger side 'size' long, centered on x, y and turned by 'turn'
local function place( template, x, y, size, turn, out )
	local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
	for _, stroke in ipairs( template ) do
		for _, p in ipairs( stroke ) do
			minx, maxx = math.min( minx, p[1] ), math.max( maxx, p[1] )
			miny, maxy = math.min( miny, p[2] ), math.max( maxy, p[2] )
		end
	end
	local k = size / math.max( maxx - minx, maxy - miny, 1e-6 )
	local mx, my = ( minx + maxx ) / 2, ( miny + maxy ) / 2
	local c, s = math.cos( turn ), math.sin( turn )
	for _, stroke in ipairs( template ) do
		local line = {}
		for _, p in ipairs( stroke ) do
			local px, py = ( p[1] - mx ) * k, ( p[2] - my ) * k
			line[#line + 1] = { x = x + px * c - py * s, y = y + px * s + py * c }
		end
		out[#out + 1] = line
	end
end

function T.strokes( page )
	if page.strokes then return page.strokes end
	local c = SEAL_PAGE_SIZE / 2
	local out, ring = {}, {}
	for k = 0, 220 do
		local a = -math.pi / 2 + 2 * math.pi * k / 220
		ring[#ring + 1] = { x = c + R * math.cos( a ), y = c + R * math.sin( a ) }
	end
	out[1] = ring
	for _, sym in ipairs( page.tree.symbols ) do
		if sym.kind == "sigil" then
			place( TEMPLATES_SIGILS[sym.key][1], c + sym.x * R, c + sym.y * R, sym.size * R, 0, out )
		else
			local x, y = c + math.cos( sym.angle ) * sym.dist * R, c + math.sin( sym.angle ) * sym.dist * R
			local turn = sym.angle - math.pi / 2 + ( sym.inverted and math.pi or 0 ) + sym.turn
			place( TEMPLATES_SIGNS[sym.key][1], x, y, sym.size * R, turn, out )
		end
	end
	for _, frame in ipairs( page.tree.frames ) do place( TEMPLATES_FRAMES[frame.key][1], c, c, frame.size * R, 0, out ) end
	page.strokes = out
	return out
end
