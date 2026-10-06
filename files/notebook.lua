-- The witch's books of seals (books.lua): the Palm Quire, the Spellbook every run starts with and the Great Tome. The configured key
-- opens the book in hand, else the one opened last, while it is in the inventory; right click opens the book in hand.
-- The names over the book switch to the others the witch carries. The Spellbook's first spreads explain how to draw
-- and what the inks do, the tome opens with
-- its title; then come the seals, one a page, and a blank page for the next.
-- Draw with the left mouse button - a ring, a sigil in the center and signs around it (see seal.lua). As in Witch Hat
-- Atelier the seal awakens when its ring closes: draw the ring with a gap, the symbols inside, then close the gap - the
-- seal stays on its page and becomes the book's active one. A click on a seal's page makes it active: the book in hand
-- casts it, with no limit (spellbook.lua). A/D, the arrows or the mouse wheel turn the pages; the eraser or right click
-- removes part of a drawing, and the clear button empties the page. The configured key, Esc or a click outside closes it.
-- Drawing spends witch ink (ink.lua): the bottles beside the book are the inks in the flasks, a click picks the one to
-- draw with, and a seal takes on the inks it is drawn with. Sheets with seals found in the world (sheets.lua) are
-- pasted in as pages of their own, into a book that holds them. The button over the book opens its other part, the
-- wiki's grimoire (grimoire.lua): the learned seals that fit the book, a page each, sorted in sections, to study and
-- redraw; with the mod setting "full_grimoire" all of them, and a click makes one the active seal, as if it were drawn.
-- The Test Book (test_book.lua) has no pages to draw on: it shows only its own, every sigil with every sign, in sections
-- to jump to over and under it, and a click makes one the active seal. What a seal does (spell_notes.lua) is written
-- beside the Test Book's pages, and under the book for a drawn seal under the mouse.
-- A book's pages are kept in the run's globals by book_store.lua, as text (strokes.lua); the pages that are the same in
-- every run and the pen's kit are in book_pages.lua, the mouse and its calibration in book_mouse.lua.
-- The books' look is in book_gfx.lua, a page turning over in page_turn.lua: a book's page turns sideways, the quire's
-- round leaves flip up over the hinge at their top, onto its lid.

dofile_once( "mods/witch_notebook/files/book_key.lua" )
local D = BookDraw
local T = PageTurn
local S = BookStore -- a book's pages as the run keeps them (book_store.lua)
local M = BookMouse -- the mouse on the gui (book_mouse.lua)
local P = BookPages -- the pen's kit, the hints and the front pages (book_pages.lua)
local seal_var, save_seal, load_seal_strokes, load_book, wiki_page_strokes = S.seal_var, S.save_seal, S.load_seal_strokes, S.load, S.wiki_page_strokes
local encode_strokes, encode_inks, thin_strokes = strokes_encode, strokes_encode_inks, strokes_thin -- strokes.lua
local is_learned, learn = book_seal_known, book_learn_seal -- books.lua
local draw_strokes, centered_on, draw_bottle, paper_color = P.strokes, P.centered, P.bottle, P.paper_color

local KEYS_BACK = { 4, 80 }     -- Key_a, Key_LEFT
local KEYS_ON = { 7, 79 }       -- Key_d, Key_RIGHT
local MOUSE_LEFT = 1            -- data/scripts/debug/keycodes.lua: Mouse_left
local MOUSE_RIGHT = 2           -- Mouse_right
local WHEEL_UP, WHEEL_DOWN = 4, 5 -- Mouse_wheel_up, Mouse_wheel_down
local MIN_SIZE = 20   -- smallest accepted sigil, in gui units
local RESULT_FRAMES = 50
local NOTE_FRAMES = 150
local TEAR_FRAMES = 150 -- "tear out" asks again, a second click within this time tears the page out
local MAX_POINTS = 5000
local ERASER_RADIUS = 6
local FRONT_PAGES = 2 -- a book's inside of the cover and its title page: no page numbers
local FLIP_GAP = 5     -- turned quickly, the next sheet lifts at least this many frames after the last one
local FLIP_SHEETS = 6  -- at most this many sheets in the air: a longer way turns several pages at once
local FIRST_OPEN_WAIT = 20 -- opened for the first time, the book lies open this long, then turns to the blank page
local FULL_GRIMOIRE_SETTING = "witch_notebook.full_grimoire"
-- buttons need ids that stay the same every frame, ink dots use ids from 1 upwards
local BUTTON = {
	RECALIBRATE = 900002, BACK = 900003, ON = 900004, -- 900001 and 900008: the calibration's (book_mouse.lua)
	TEAR = 900005, -- and the next one for the right page
	EDIT = 900300, -- and the next one for the right page
	WIKI = 900007, ERASER = 900009, RETRY = 900098, CLEAR = 900099,
	TAB = 900010, -- and the next ones, a section each
	BOOK = 900100, -- and the next ones, a book each
	TEST = 900200, -- and the next ones: the Test Book's groups, then (+20) items, then (+40) parts
}

local DEBUG_HISTORY = 10 -- recent drawings kept for offline debugging
local BOOK_GIVEN_FLAG = "witch_notebook_spellbook" -- every run starts with the Spellbook
local LEARNED_VAR = BOOK_LEARNED_VAR -- the wiki's seals learned (books.lua)

-- on paper (book_pages.lua), and around the book
local INK_COLOR, NOTE_COLOR, ERROR_COLOR, NUMBER_COLOR = P.INK_COLOR, P.NOTE_COLOR, P.ERROR_COLOR, P.NUMBER_COLOR
local GOLD_COLOR = { 0.95, 0.8, 0.45 }
local LIGHT_TEXT = { 0.93, 0.9, 0.82 }
local GREY = { 0.7, 0.7, 0.7 }

local FROZEN_BUTTONS = { "Fire", "Fire2", "Action", "Throw", "Interact", "Left", "Right", "Up", "Down", "Jump", "Run", "Fly", "Dig" }

local gui
local is_open = false
local shown_open_key -- last key reflected in book item tooltips
local cur          -- the book open, or opened last: seals holds completed pages and unfinished drafts (draft = "1");
                   -- blank is the next empty page, edit is the draft or blank page being drawn on.
local view         -- where the open book lies this frame (layout)
local is_drawing = false
local ink_debt = 0     -- ink drawn but not yet taken from the flasks (less than one cell)
local result -- { text, frames }: temporary feedback for a drawing that stays editable
local awakening -- { page, state }: a seal just recognized lights up on its page (awaken.lua)
local note   -- { text, frames }: a word under the book
local tear -- { seal, frames }: "tear out" was clicked once
local flips = {}  -- the sheets in the air: { from, to, frame, back }, turning over from spread 'from' to 'to' (with
                  -- 'back' turning back to 'from'); cur.spread is where they all lead
local queued = 0  -- spreads still to turn (+ on, - back), a sheet at a time
local drag -- { f = the sheet held, x0, y0, frames, moved, speed }: a page's corner held with the mouse
local flip_wait = 0 -- frames before the next sheet may lift
local notebook_box -- { x0, y0, x1, y1 }: gui area of the book, a click outside closes it
local wait_release = false -- a click that opened/closed the book or ended the calibration: controls stay frozen and nothing is
                           -- drawn until the button is released, so the wand doesn't fire
local press_at              -- { x, y }: where the left button last went down; a panel button counts only a press begun on it
notebook_button_rects = {}  -- id -> { x, y, w, h } of the panel buttons (the tests press them where they are)
local wiki = false          -- the book shows the wiki's grimoire (grimoire.lua) instead of the drawn seals
local hover_entry           -- the grimoire page under the mouse: its effect is written under the book
local hover_text            -- ... or what the page or the bottle under the mouse is
local hover_seal            -- ... or the drawn seal under the mouse: what it does (spell_notes.lua) is written there
local selected_ink = "ink"  -- the ink the book draws with (ink.lua INKS)
local amounts = {}          -- how much of every ink the flasks hold

local function get_player()
	return EntityGetWithTag( "player_unit" )[1]
end

-- the witch's speed (world pixels a second), for the quire's strap to swing with; nil, nil when there's none
local function witch_speed()
	local player = get_player()
	local c = player and EntityGetFirstComponent( player, "CharacterDataComponent" )
	if not c then return nil, nil end
	local vx, vy = ComponentGetValue2( c, "mVelocity" )
	if type( vx ) ~= "number" or type( vy ) ~= "number" then return nil, nil end
	return vx, vy
end
local strap_flipping = false -- a leaf was flipping last frame (one starting jolts the quire's strap)

local function set_controls_enabled( player, enabled )
	local controls = player and EntityGetFirstComponentIncludingDisabled( player, "ControlsComponent" )
	if not controls then return end
	ComponentSetValue2( controls, "enabled", enabled )
	if not enabled then
		-- the disabled component keeps its last state, so release every button explicitly
		for _, name in ipairs( FROZEN_BUTTONS ) do
			ComponentSetValue2( controls, "mButtonDown" .. name, false )
		end
	end
end

---- the witch's books: which ones they carry, which is in hand ----

-- the books in the witch's inventory (held, in the quick or the full inventory): key -> true
local function carried_books( player )
	local out = {}
	for _, item in ipairs( player and EntityGetWithTag( BOOK_TAG ) or {} ) do
		if EntityGetRootEntity( item ) == player then out[book_key_of( item )] = true end
	end
	return out
end

local function held_book( player )
	local inventory = EntityGetFirstComponentIncludingDisabled( player, "Inventory2Component" )
	local item = inventory and ComponentGetValue2( inventory, "mActiveItem" )
	if item and item ~= 0 and EntityHasTag( item, BOOK_TAG ) then return book_key_of( item ) end
end

-- A book in hand still recharging after a seal stronger than a shot: a short bar over the witch's head empties as it
-- recharges, in the colors of the game's reload bar (book_gfx.lua draws its frame and its fill). It stands in the world,
-- by the witch, so the screen's size and the game's resolution settings can't move it off. Made once: its fill only
-- shrinks from the right (no picture changes, nothing to reload). A wait no longer than the book's own delay (a shot)
-- isn't shown: the bar would blink at every click. cast.lua spellbook_use keeps on the book the frame it can cast
-- again and how long it waits.
local RECHARGE_TAG = "witch_recharge_bar"
local RECHARGE_ABOVE = 24 -- world pixels over the witch's feet
local function show_recharge( player )
	local bar = ( EntityGetWithTag( RECHARGE_TAG ) or {} )[1]
	if bar and not EntityHasTag( bar, RECHARGE_TAG ) then bar = nil end
	local left, total, delay = 0, 0, 0
	local inventory = player and EntityGetFirstComponentIncludingDisabled( player, "Inventory2Component" )
	local item = inventory and ComponentGetValue2( inventory, "mActiveItem" )
	if item and item ~= 0 and EntityHasTag( item, BOOK_TAG ) then
		delay = BOOKS[book_key_of( item )].cast_delay
		for _, comp in ipairs( EntityGetComponentIncludingDisabled( item, "VariableStorageComponent" ) or {} ) do
			if ComponentGetValue2( comp, "name" ) == SPELLBOOK_NEXT_CAST_VAR then
				left = ComponentGetValue2( comp, "value_int" ) - GameGetFrameNum()
				total = ComponentGetValue2( comp, "value_float" ) or 0
			end
		end
	end
	if left <= 0 or total <= delay or left > total then
		if bar then EntityKill( bar ) end
		return
	end
	if not bar then
		bar = EntityCreateNew( RECHARGE_TAG )
		EntityAddTag( bar, RECHARGE_TAG )
		-- the bar's place is the inside's left end: the frame a pixel round it, the fill from there
		EntityAddComponent2( bar, "SpriteComponent", { image_file = BOOK_RECHARGE_FRAME, offset_x = 1, offset_y = 1, z_index = -60,
			update_transform_rotation = false } )
		EntityAddComponent2( bar, "SpriteComponent", { _tags = "witch_fill", image_file = BOOK_RECHARGE_FILL, z_index = -61,
			has_special_scale = true, special_scale_x = 1, special_scale_y = 1, update_transform_rotation = false } )
	end
	local fill = EntityGetFirstComponentIncludingDisabled( bar, "SpriteComponent", "witch_fill" )
	if fill then ComponentSetValue2( fill, "special_scale_x", left / total ) end
	local x, y = EntityGetTransform( player )
	EntitySetTransform( bar, x - BOOK_RECHARGE_W / 2, y - RECHARGE_ABOVE )
end

-- which book the configured key opens: the one in hand, else the one opened last, else the first the witch carries
-- Right click passes held_only: only the book in hand can open this way.
local function book_to_open( player, carried, held_only )
	local key = held_book( player )
	if key and carried[key] then return key end
	if held_only then return nil end
	key = GlobalsGetValue( BOOK_OPEN_VAR, "book" )
	if carried[key] then return key end
	for _, k in ipairs( { "book", "tome", "quire", "test" } ) do
		if carried[k] then return k end
	end
end

---- the open book's pages (book_store.lua keeps them in the run's globals) ----

-- A drawing of the book 'def' in the grimoire's units (SEAL_PAGE_SIZE, the ring around its middle - fx_seal draws it in
-- the air): a sheet's already is, a drawn seal is on its book's page
local function seal_page_units( def, seal )
	local k = SEAL_PAGE_SIZE / def.page
	if seal.sheet ~= "" or k == 1 then return seal.strokes end
	local c, out = SEAL_PAGE_SIZE / 2, {}
	for i, stroke in ipairs( seal.strokes ) do
		local line = { ink = stroke.ink }
		for j, p in ipairs( stroke ) do line[j] = { x = c + ( p.x - def.page / 2 ) * k, y = c + ( p.y - def.page / 2 ) * k } end
		out[i] = line
	end
	return out
end

local function save_page() S.save_page( cur ) end

local function clear_page()
	cur.edit.strokes = {}
	cur.edit.point_count = 0
	cur.edit.failed = false
	cur.edit.erase_index, cur.edit.erase_dirty = nil, nil
	is_drawing = false
	cur.erase_last_x, cur.erase_last_y = nil, nil
	ink_debt = 0
	result = nil
	if cur.edit.draft == "1" then save_seal( cur, cur.edit_face - cur.def.intro ) end
end

---- the wiki's seals learned, and the grimoire's pages ----

local function full_grimoire()
	return ModSettingGet( FULL_GRIMOIRE_SETTING ) == true
end

-- the grimoire's pages in the open book: all of them, or the learned ones - those its pages hold
local wiki_list_cache, wiki_list_key
local function wiki_list()
	if cur.def.test then return TestBook.pages() end
	local learned = full_grimoire() and "*" or GlobalsGetValue( LEARNED_VAR, "" ) .. "|" .. book_learned_before()
	local key = cur.key .. "|" .. learned
	if wiki_list_key ~= key then
		wiki_list_key = key
		wiki_list_cache = {}
		for _, entry in ipairs( GRIMOIRE or {} ) do
			if ( learned == "*" or is_learned( entry.key ) ) and book_holds( cur.key, seal_book( entry ) ) then
				wiki_list_cache[#wiki_list_cache + 1] = entry
			end
		end
	end
	return wiki_list_cache
end

-- how many learned seals the open book's pages can't hold
local function wiki_too_great()
	local n = 0
	for _, entry in ipairs( GRIMOIRE or {} ) do
		if ( full_grimoire() or is_learned( entry.key ) ) and not book_holds( cur.key, seal_book( entry ) ) then n = n + 1 end
	end
	return n
end

local function wiki_color( entry )
	return entry.spell:match( "element=([%w_]+)" ) or "light"
end

-- the page 'key' of the book 'st's other part: the grimoire's, or the Test Book's own
local function wiki_lookup( st, key )
	if st.def.test then return TestBook.page( key ) end
	return GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[key]
end

---- pages and spreads ----

-- A book shows two pages, a spread; the Palm Quire its leaf on the pad and, on the lid, the back of the leaf flipped
-- before it - or the lid itself (face 0). Faces: a page (> 0), the back of a leaf (< 0), the lid (0).
local function blank_page() return cur.def.intro + #cur.seals + 1 end
local function last_blank_page() return blank_page() + 1 end
local function editable_page( face )
	if face == blank_page() then return cur.blank end
	if face == last_blank_page() then return cur.blank_next end
	local seal = cur.seals[face - cur.def.intro]
	return seal and seal.draft == "1" and seal or nil
end
local function select_edit_page( face )
	local page = editable_page( face )
	if not page then return end
	if cur.edit ~= page then
		witch_notebook_finish_erase()
		cur.erase_last_x, cur.erase_last_y = nil, nil
	end
	if cur.edit ~= page then result = nil end
	cur.edit, cur.edit_face = page, face
end
local function spread_of( p ) return cur.def.round and p or math.ceil( p / 2 ) end
local function spread_faces( s )
	if cur.def.round then return s > 1 and -( s - 1 ) or 0, s end
	return 2 * s - 1, 2 * s
end
local function last_spread()
	if wiki then return math.max( 1, spread_of( #wiki_list() ) ) end
	return spread_of( last_blank_page() )
end
-- the two faces of the sheet turning between spreads f.from and f.to (several pages at once turn as one sheet)
local function sheet_faces( f )
	local lo, hi = math.min( f.from, f.to ), math.max( f.from, f.to )
	if cur.def.round then return { { face = lo, front = true }, { face = -( hi - 1 ), front = false } } end
	return { { face = 2 * lo, front = true }, { face = 2 * hi - 1, front = false } }
end

local function wiki_entry( p ) return wiki and p > 0 and wiki_list()[p] end

-- what paper a face is: a seal's, a page of text, a sheet pasted in, the back of a leaf
local function page_kind( face )
	if face < 0 then return "back" end
	local text = cur.def.round and "page" or "plain"
	if wiki then return wiki_entry( face ) and "page" or text end
	if cur.def.intro >= FRONT_PAGES then
		if face == 1 then return "endpaper" end
		if face == 2 then return "title" end
	end
	local seal = cur.seals[face - cur.def.intro]
	if seal and seal.sheet ~= "" then
		local entry = GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[seal.sheet]
		return ( entry and sheet_entry_forbidden and sheet_entry_forbidden( entry ) ) and "dark" or "sheet"
	end
	return ( seal or face == blank_page() or face == last_blank_page() ) and "page" or text
end

---- the book's names, the active seal ----

-- A book item is named after its active seal
local function name_book_items( st )
	local seal = st.seals[st.active]
	local entry = st.active == 0 and wiki_lookup( st, st.active_wiki )
	local base = st.def.name
	local name = seal and ( base .. ": " .. seal.name ) or entry and ( base .. ": " .. entry.name ) or base
	local hint = book_open_hint()
	local description = seal and ( seal.quality .. ". LMB - cast, " .. hint .. " - open the book." )
		or entry and ( ( entry.test and "A test seal" or "A learned seal" ) .. ". LMB - cast, " .. hint .. " - open the book." )
		or ( st.def.about .. " " .. hint .. " - open it and draw a seal." )
	for _, book in ipairs( EntityGetWithTag( BOOK_TAG ) or {} ) do
		if book_key_of( book ) == st.key then
			local item = EntityGetFirstComponentIncludingDisabled( book, "ItemComponent" )
			if item then
				ComponentSetValue2( item, "item_name", name )
				ComponentSetValue2( item, "ui_description", description )
			end
			for _, kind in ipairs( { "UIInfoComponent", "AbilityComponent" } ) do
				local comp = EntityGetFirstComponentIncludingDisabled( book, kind )
				if comp then ComponentSetValue2( comp, kind == "UIInfoComponent" and "name" or "ui_name", name ) end
			end
		end
	end
end

-- The book casts its active seal: its spell goes to the run's globals, where spellbook.lua reads it
local function set_active( st, i )
	st.active = st.seals[i] and st.seals[i].draft ~= "1" and i or 0
	GlobalsSetValue( book_var( st.key, "active" ), tostring( st.active ) )
	local seal = st.seals[st.active]
	GlobalsSetValue( book_var( st.key, "active_spell" ), seal and seal.spell or "" )
	-- the drawing too: the seal flares up in the air as it was drawn
	GlobalsSetValue( book_var( st.key, "active_strokes" ), seal and encode_strokes( thin_strokes( seal_page_units( st.def, seal ), 3 ) ) or "" )
	if seal then
		st.active_wiki = ""
		GlobalsSetValue( book_var( st.key, "active_wiki" ), "" )
	end
	name_book_items( st )
end

-- A page of the wiki's grimoire becomes the active seal, cast as a flawless drawing of it (a Test Book's page: as its
-- seal compiles)
local function set_active_wiki( st, key )
	local entry = wiki_lookup( st, key )
	if not entry then return end
	set_active( st, 0 )
	st.active_wiki = key
	GlobalsSetValue( book_var( st.key, "active_wiki" ), key )
	GlobalsSetValue( book_var( st.key, "active_spell" ), entry.test and entry.spell or seal_page_data( { named = key, precision = 1, stability = 1 } ) )
	GlobalsSetValue( book_var( st.key, "active_strokes" ), encode_strokes( thin_strokes( S.entry_strokes( entry ), 3 ) ) )
	name_book_items( st )
end

-- the inks of a drawing by their shares of its line: "blood:0.6" for the spell (ink.lua ink_mix_data)
local function ink_shares( list )
	local lengths, total = {}, 0
	for _, stroke in ipairs( list ) do
		local len = 0
		for k = 2, #stroke do len = len + math.sqrt( ( stroke[k].x - stroke[k - 1].x ) ^ 2 + ( stroke[k].y - stroke[k - 1].y ) ^ 2 ) end
		local key = stroke.ink or "ink"
		lengths[key] = ( lengths[key] or 0 ) + len
		total = total + len
	end
	local shares = {}
	for key, len in pairs( lengths ) do shares[key] = total > 0 and len / total or 0 end
	return shares
end

-- the spell data with the inks it is drawn with (cast.lua applies them)
local function with_inks( data, mix )
	if not mix or mix == "" then return data end
	return ( data:gsub( "^([^&]*)", "%1;ink=" .. mix, 1 ) )
end

local function add_seal( spell )
	local i = cur.edit.draft == "1" and cur.edit_face - cur.def.intro or #cur.seals + 1
	local kept = thin_strokes( cur.edit.strokes )
	cur.seals[i] = { spell = with_inks( spell.data or seal_page_data( spell ), ink_mix_data( ink_shares( cur.edit.strokes ) ) ),
		name = spell.summary, quality = spell.quality, color = spell.element, strokes = kept, inks = encode_inks( kept ), sheet = "",
		tier = "", fresh = "", draft = "" }
	save_seal( cur, i )
	GlobalsSetValue( book_var( cur.key, "seals" ), tostring( i ) )
	set_active( cur, i )
	if spell.named then learn( spell.named ) end
	return i
end

-- The first mark on either blank page turns the pair into drafts; another pair is already ready after it.
local function promote_blank()
	if ( cur.edit ~= cur.blank and cur.edit ~= cur.blank_next ) or cur.edit.point_count == 0 then return end
	local i = #cur.seals + 1
	for j, page in ipairs( { cur.blank, cur.blank_next } ) do
		page.draft, page.sheet = "1", ""
		cur.seals[i + j - 1] = page
		save_seal( cur, i + j - 1 )
	end
	GlobalsSetValue( book_var( cur.key, "seals" ), tostring( i + 1 ) )
	cur.blank = { strokes = {}, point_count = 0, failed = false }
	cur.blank_next = { strokes = {}, point_count = 0, failed = false }
	save_page()
end

---- sheets found in the world ----

-- the tier of a wiki's seal, from the sheets' ranking (sheets.lua)
local function entry_tier( key )
	for _, row in ipairs( SHEET_LIST or {} ) do
		if row.key == key then return row.tier end
	end
end

-- A sheet picked up in the world (sheets.lua) is pasted into the book 'st' after its last seal; it opens on it next time
local function paste_sheet( st, entry, ink )
	local i = #st.seals + 1
	local forbidden = sheet_entry_forbidden and sheet_entry_forbidden( entry )
	local tier = entry_tier( entry.key )
	ink = INK_BY_KEY[ink] and ink or "ink"
	local data = with_inks( seal_page_data( { named = entry.key, precision = 1, stability = 1 } ), ink ~= "ink" and ( ink .. ":1" ) or "" )
	local quality = ( forbidden and "Forbidden sheet" or "Ready sheet" ) .. ( tier and ( ", tier " .. sheet_tier_name( tier ) ) or "" )
	st.seals[i] = { spell = data, name = entry.name, quality = quality, color = wiki_color( entry ), inks = ink == "ink" and "" or ink,
		sheet = entry.key, tier = tostring( tier or "" ), fresh = "1" }
	load_seal_strokes( st.seals[i] )
	save_seal( st, i )
	GlobalsSetValue( book_var( st.key, "seals" ), tostring( i ) )
	-- the book opens on the new page
	local p = st.def.intro + i
	st.spread = st.def.round and p or math.ceil( p / 2 )
	st.own_spread = st.spread
	GlobalsSetValue( book_var( st.key, "spread" ), tostring( st.spread ) )
end

-- The book a sheet goes into: the book opened last if it holds the seal, else the first of the witch's books that does
local function sheet_book( entry )
	local need = seal_book( entry )
	local last = GlobalsGetValue( BOOK_OPEN_VAR, "book" )
	if BOOKS[last] and not BOOKS[last].test and book_owned( last ) and book_holds( last, need ) then return last end
	for _, key in ipairs( { "book", "tome", "quire" } ) do
		if book_owned( key ) and book_holds( key, need ) then return key end
	end
end

-- Sheets picked up are pasted in the next frame; a seal too great for the witch's books waits for a book that holds it
local function paste_pending_sheets()
	local pending = GlobalsGetValue( SHEET_PENDING_VAR, "" )
	if pending == "" then return end
	GlobalsSetValue( SHEET_PENDING_VAR, "" )
	for key, ink in pending:gmatch( "([%w_]+):([%w_]*);" ) do
		local entry = GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[key]
		if entry then
			learn( key )
			local target = sheet_book( entry )
			if target then
				paste_sheet( load_book( target ), entry, ink )
				GamePrintImportant( "Seal Sheet: " .. entry.name, "Pasted into the " .. BOOKS[target].name .. " - " .. book_open_key_hint() .. " to open it" )
			else
				GlobalsSetValue( SHEETS_WAITING_VAR, GlobalsGetValue( SHEETS_WAITING_VAR, "" ) .. key .. ":" .. ink .. ";" )
				GamePrintImportant( "Seal Sheet: " .. entry.name, "Too great for your books - it waits for " .. book_named( seal_book( entry ) ) )
			end
		end
	end
	wiki_list_key = nil
end

local function tear_out( i )
	table.remove( cur.seals, i )
	for j = i, #cur.seals + 1 do save_seal( cur, j ) end -- the pages after it move up, the last one is cleared
	GlobalsSetValue( book_var( cur.key, "seals" ), tostring( #cur.seals ) )
	if cur.active == i then set_active( cur, 0 ) elseif cur.active > i then set_active( cur, cur.active - 1 ) end
	if cur.edit == cur.blank then cur.edit_face = blank_page()
	elseif cur.edit == cur.blank_next then cur.edit_face = last_blank_page()
	else
		for j, page in ipairs( cur.seals ) do if page == cur.edit then cur.edit_face = cur.def.intro + j break end end
	end
	cur.spread = math.min( cur.spread, last_spread() )
end

-- A drawn seal goes back to a draft: its lines stay on the page to be erased or added to, and it awakens again when the
-- ring is closed (or with "Try seal" if it still is). Until then the book doesn't cast it.
local function edit_seal( i )
	local seal = cur.seals[i]
	if not seal or seal.sheet ~= "" then return end
	select_edit_page( cur.def.intro + i )
	seal.draft, seal.fresh, seal.parts = "1", "", nil
	seal.point_count = 0
	for _, stroke in ipairs( seal.strokes ) do seal.point_count = seal.point_count + #stroke end
	seal.failed = seal_ring_closed( seal.strokes )
	if cur.active == i then set_active( cur, 0 ) end
	save_seal( cur, i )
	cur.eraser_selected = false
end

---- turning the pages ----

local function turning() return #flips > 0 or queued ~= 0 end

-- while pages turn, the pages on view are those from the lowest spread in the air to the highest
local function spreads_in_air()
	local lo, hi = cur.spread, cur.spread
	for _, f in ipairs( flips ) do lo, hi = math.min( lo, f.from, f.to ), math.max( hi, f.from, f.to ) end
	return lo, hi
end

-- Pages turned faster than a sheet turns over: the sheets turn together, each one lifting a little after the last. A
-- turn back while the last sheet is still in the air sends that sheet back.
local function turn_pages( by )
	if drag then return end -- a page held by its corner
	local to = math.max( 1, math.min( last_spread(), cur.spread + queued + by ) )
	if to == cur.spread + queued then return end
	queued = to - cur.spread
	is_drawing = false -- a line being drawn just ends
	tear = nil
end

-- the sheet in the air that lands on the spread on view coming from the side of 'd' (it turns back if the pages turn
-- that way)
local function sheet_landing( d )
	for _, f in ipairs( flips ) do
		local origin, dest = f.back and f.to or f.from, f.back and f.from or f.to
		if dest == cur.spread and ( origin - dest ) * d > 0 then return f end
	end
end

local function update_flips()
	local frames = cur.def.flip_frames
	for k = #flips, 1, -1 do
		local f = flips[k]
		if not f.held then
			if f.lift then f.lift = f.lift * 0.82 end -- let go, the paper straightens
			f.frame = f.frame + ( f.back and -1 or 1 )
			if f.frame >= frames or f.frame <= 0 then table.remove( flips, k ) end
		end
	end
	flip_wait = flip_wait - 1
	while queued ~= 0 do
		local d = queued > 0 and 1 or -1
		local f = sheet_landing( d )
		local origin = f and ( f.back and f.to or f.from )
		local target = cur.spread + queued
		if f and ( target - origin ) * d < 0 then
			-- a sheet carrying several pages, and the pages wanted lie among them: it lands there instead (sending it
			-- back would overshoot, and the rest would send it on again, forever)
			if f.back then f.from = target else f.to = target end
			cur.spread, queued = target, 0
		elseif f then
			f.back = not f.back
			cur.spread = f.back and f.from or f.to
			queued = queued - ( cur.spread - ( f.back and f.to or f.from ) )
		else
			if flip_wait > 0 or #flips >= FLIP_SHEETS then break end
			-- a long way: the sheets left to lift share it, several pages each
			local n = math.max( 1, math.floor( math.abs( queued ) / ( FLIP_SHEETS - #flips ) ) )
			local to = math.max( 1, math.min( last_spread(), cur.spread + d * n ) )
			if to == cur.spread then queued = 0 break end
			flips[#flips + 1] = { from = cur.spread, to = to, frame = 0 }
			queued = queued - ( to - cur.spread )
			cur.spread = to
			flip_wait = FLIP_GAP
		end
	end
	-- a seal just recognized awakens while its page lies still
	if awakening and ( turning() or not awaken_step( awakening.state ) ) then awakening = nil end
end

-- A page's corner held with the mouse: the sheet's free edge follows the mouse. Let go, a click turns the page, a
-- flick sends it the way it was flung, else it falls the way it leans.
local function grab_corner( d, mx, my )
	local f = { from = cur.spread, to = cur.spread + d, frame = 0, held = true }
	flips[#flips + 1] = f
	cur.spread = f.to
	drag = { f = f, x0 = mx, y0 = my, frames = 0, moved = 0, speed = 0 }
	is_drawing = false
	tear = nil
end

local function update_drag( mx, my )
	local f = drag.f
	local frames = cur.def.flip_frames
	local t = f.frame / frames
	local along, across = mx - drag.x0, my - drag.y0
	if view.vertical then along, across = across, along end
	if InputIsMouseButtonDown( MOUSE_LEFT ) then
		local now = T.turn_at( view, ( view.vertical and my or mx ) - view.hinge, f.to > f.from )
		drag.frames = drag.frames + 1
		drag.moved = math.max( drag.moved, math.abs( along ) )
		drag.speed = drag.speed * 0.5 + ( now - t ) * 0.5
		f.frame = now * frames
		f.lift = math.max( -40, math.min( 30, across ) ) -- the corner up or down (the quire's: aside) with the mouse
		return
	end
	local click = drag.moved < 3 and drag.frames < 15
	local on = click or drag.speed > 0.015 or ( drag.speed > -0.015 and t >= 0.5 )
	f.held = nil
	if not on then
		f.back = true
		cur.spread = f.from
	end
	drag = nil
end

---- opening and closing ----

-- The drawn seals or the wiki's grimoire: each part keeps its own open spread
local function toggle_wiki()
	if cur.def.test then return end -- the Test Book has its own pages only
	if wiki then cur.wiki_spread = cur.spread else cur.own_spread = cur.spread end
	wiki = not wiki and GRIMOIRE ~= nil
	cur.spread = wiki and cur.wiki_spread or cur.own_spread
	cur.spread = math.max( 1, math.min( cur.spread, last_spread() ) )
	flips, queued, drag, tear, hover_entry = {}, 0, nil, nil, nil
	is_drawing = false
end

-- The open book is put away (closed, or another one opened): the pages still turning lie where they were turned to,
-- the drawing stays on its page
local function put_away()
	witch_notebook_finish_erase()
	if wiki and not cur.def.test then toggle_wiki() end
	cur.spread = cur.spread + queued
	flips, queued, drag = {}, 0, nil
	is_drawing = false -- a line being drawn just ends; it doesn't awaken the seal
	cur.erase_last_x, cur.erase_last_y = nil, nil
	save_page()
	for i, seal in ipairs( cur.seals ) do if seal.draft == "1" then save_seal( cur, i ) end end
	GlobalsSetValue( book_var( cur.key, "spread" ), tostring( cur.spread ) )
	result, awakening, note, tear = nil, nil, nil, nil
end

-- 'key' is opened: the first time, at its beginning, and it turns through its first pages to the blank one
local function open_book( key )
	cur = load_book( key )
	GlobalsSetValue( BOOK_OPEN_VAR, key )
	wiki = cur.def.test == true
	cur.spread = math.max( 1, math.min( cur.spread, last_spread() ) )
	if GlobalsGetValue( book_var( key, "opened" ), "" ) == "" then
		GlobalsSetValue( book_var( key, "opened" ), "1" )
		cur.spread = 1
		turn_pages( spread_of( blank_page() ) - 1 )
		flip_wait = FIRST_OPEN_WAIT
	end
end

local function open_notebook( key )
	is_open = true
	selected_ink = GlobalsGetValue( INK_VAR, "ink" )
	if not INK_BY_KEY[selected_ink] then selected_ink = "ink" end
	open_book( key )
	cur.eraser_selected = false
	cur.erase_last_x, cur.erase_last_y = nil, nil
	wait_release = InputIsMouseButtonDown( MOUSE_LEFT ) or InputIsMouseButtonDown( MOUSE_RIGHT )
end

local function close_notebook( player )
	is_open = false
	M.stop() -- closed, the calibration is given up
	if cur then put_away() end
	notebook_box = nil
	wait_release = InputIsMouseButtonDown( MOUSE_LEFT ) or InputIsMouseButtonDown( MOUSE_RIGHT )
	if not wait_release then set_controls_enabled( player, true ) end
end

---- drawing seals ----

-- Every recognized drawing is kept in the run's globals, which the game saves in world_state.xml (Save & Quit):
-- python tests/debug_sigil.py reads them back and explains the recognition
local function record_drawing( result_text )
	local n = ( tonumber( GlobalsGetValue( "witch_notebook.debug_next", "0" ) ) or 0 ) + 1
	GlobalsSetValue( "witch_notebook.debug_next", tostring( n ) )
	local data = "n=" .. n .. ";frame=" .. GameGetFrameNum() .. ";book=" .. cur.key .. ";result=" .. result_text .. ";strokes=" .. encode_strokes( cur.edit.strokes )
	GlobalsSetValue( "witch_notebook.debug_" .. ( ( n - 1 ) % DEBUG_HISTORY + 1 ), data )
end

-- a wiki's seal too great for the open book's pages: why it doesn't awaken
local function too_great( spell )
	local entry = spell and spell.named and GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[spell.named]
	local need = entry and seal_book( entry )
	if need and not book_holds( cur.key, need ) then
		return "Too great for the " .. cur.def.name .. ": " .. book_named( need ) .. " holds it"
	end
end

local function finish_sigil()
	local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
	for _, stroke in ipairs( cur.edit.strokes ) do
		for _, p in ipairs( stroke ) do
			minx = math.min( minx, p.x ); maxx = math.max( maxx, p.x )
			miny = math.min( miny, p.y ); maxy = math.max( maxy, p.y )
		end
	end
	if cur.edit.point_count < 10 or math.max( maxx - minx, maxy - miny ) < MIN_SIZE then
		cur.edit.failed = true
		result = { text = "The seal is too small - edit the drawing", frames = RESULT_FRAMES }
		return
	end

	-- one of the wiki's seals is known at a glance, as a whole (and casts as the wiki's spell); any other seal is read
	-- symbol by symbol (seal_spell.lua)
	local spell, err, seal = read_spell( cur.edit.strokes )
	err = too_great( spell ) or err
	if err and spell then spell = nil end
	-- the strokes it couldn't read stay marked until the seal is read again
	for _, stroke in ipairs( cur.edit.strokes ) do stroke.trouble = nil end
	cur.edit.marked = nil
	if not spell and seal and seal.trouble and #seal.trouble > 0 then
		for _, stroke in ipairs( seal.trouble ) do stroke.trouble = true end
		cur.edit.marked = true
	end
	record_drawing( spell and ( spell.summary .. " / " .. ( spell.data or serialize_spell( spell ) ) ) or err )
	if spell then
		-- the seal stays on its page, a blank page follows; on it the seal awakens
		local tree = seal or parse_seal( cur.edit.strokes )
		local state = awaken_new( cur.edit.strokes, tree, spell.element )
		local i = add_seal( spell )
		-- what its parts were read as, to show them under the mouse (draw_parts); a wiki's seal as its pages are told
		if tree then
			local entry = spell.named and GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[spell.named]
			cur.seals[i].parts = entry and seal_parts( cur.edit.strokes, tree, entry ) or tree.symbols
			cur.seals[i].parts_of, cur.seals[i].parts_data = cur.seals[i].strokes, cur.seals[i].spell:match( "^[^&]*" ) or ""
		end
		awakening = { page = cur.def.intro + i, state = state }
		if cur.edit == cur.blank or cur.edit == cur.blank_next then clear_page() end
		select_edit_page( blank_page() )
		save_page()
	else
		cur.edit.failed = true
		result = { text = err, frames = RESULT_FRAMES }
	end
end

-- Returns the length of line added
local function add_point( stroke, x, y, final )
	cur.edit.erase_index = nil
	if cur.edit.point_count >= MAX_POINTS then return 0 end
	local last = stroke[#stroke]
	local d = 0
	if last then
		-- fill gaps so fast mouse movement still draws a continuous line; the line's very end counts even when it is
		-- less than a unit away (a small tick would come out shorter than drawn)
		d = math.sqrt( ( x - last.x ) ^ 2 + ( y - last.y ) ^ 2 )
		if d < ( final and 0.3 or 1 ) then return 0 end
		local steps = math.floor( d )
		for i = 1, steps - 1 do
			local t = i / steps
			stroke[#stroke + 1] = { x = last.x + ( x - last.x ) * t, y = last.y + ( y - last.y ) * t }
		end
		cur.edit.point_count = cur.edit.point_count + steps - 1
	end
	stroke[#stroke + 1] = { x = x, y = y }
	cur.edit.point_count = cur.edit.point_count + 1
	promote_blank()
	return d
end

local function end_stroke()
	is_drawing = false
	-- A closed ring is checked after every completed stroke, including corrections to a failed seal.
	if seal_ring_closed( cur.edit.strokes ) then finish_sigil() end
	if cur.edit.draft == "1" then save_seal( cur, cur.edit_face - cur.def.intro ) end
end

-- Finish an eraser gesture once: split lines at removed points, then check and save the edited page.
function witch_notebook_finish_erase()
	local page = cur and cur.edit
	if not page or not page.erase_dirty then return end
	local kept = {}
	for _, stroke in ipairs( page.strokes ) do
		local piece = { ink = stroke.ink }
		for _, p in ipairs( stroke ) do
			if p.erased then
				if #piece > 0 then kept[#kept + 1] = piece; piece = { ink = stroke.ink } end
			else
				piece[#piece + 1] = p
			end
		end
		if #piece > 0 then kept[#kept + 1] = piece end
	end
	page.strokes, page.erase_dirty = kept, nil
	page.erase_index = nil
	if not seal_ring_closed( kept ) then page.failed = false end
	if page.draft == "1" then save_seal( cur, cur.edit_face - cur.def.intro ) end
end

-- Index editable points in page-sized cells. An eraser move only tests cells crossed by its circular tip.
local function erase_index( page )
	if page.erase_index then return page.erase_index end
	local cells = {}
	for _, stroke in ipairs( page.strokes ) do
		for _, p in ipairs( stroke ) do
			local ix, iy = math.floor( p.x / ( 2 * ERASER_RADIUS ) ), math.floor( p.y / ( 2 * ERASER_RADIUS ) )
			cells[ix] = cells[ix] or {}
			cells[ix][iy] = cells[ix][iy] or {}
			local bucket = cells[ix][iy]
			bucket[#bucket + 1] = p
		end
	end
	page.erase_index = cells
	return cells
end

-- Mark points under the swept circular tip; the split and save happen when the gesture ends.
function witch_notebook_erase_at( x, y, from_x, from_y )
	from_x, from_y = from_x or x, from_y or y
	if from_x == x and from_y == y and cur.erase_last_x then return end
	local dx, dy = x - from_x, y - from_y
	local length2 = dx * dx + dy * dy
	local cells = erase_index( cur.edit )
	local cell_size = 2 * ERASER_RADIUS
	local min_x = math.floor( ( math.min( x, from_x ) - ERASER_RADIUS ) / cell_size )
	local max_x = math.floor( ( math.max( x, from_x ) + ERASER_RADIUS ) / cell_size )
	local min_y = math.floor( ( math.min( y, from_y ) - ERASER_RADIUS ) / cell_size )
	local max_y = math.floor( ( math.max( y, from_y ) + ERASER_RADIUS ) / cell_size )
	for ix = min_x, max_x do
		local column = cells[ix]
		if column then
			for iy = min_y, max_y do
				local bucket = column[iy]
				if bucket then
					for _, p in ipairs( bucket ) do
						if not p.erased then
							local t = length2 > 0 and math.max( 0, math.min( 1, ( ( p.x - from_x ) * dx + ( p.y - from_y ) * dy ) / length2 ) ) or 0
							local ex, ey = from_x + t * dx, from_y + t * dy
							if ( p.x - ex ) ^ 2 + ( p.y - ey ) ^ 2 <= ERASER_RADIUS ^ 2 then
								p.erased = true
								cur.edit.point_count = cur.edit.point_count - 1
								cur.edit.erase_dirty = true
								result = nil
							end
						end
					end
				end
			end
		end
	end
end

---- where the open book lies ----

-- A book lies open as a spread: two pages side by side, the spine between; the words over it and under it. It sits a
-- little higher when the screen is short for the words under a big book.
local function layout_spread( def, sw, sh )
	local size, m, spine = def.page, def.margin, 2 * def.gap
	local left_x = math.floor( ( sw - 2 * size - spine ) / 2 )
	local page_y = math.floor( math.max( m + 14, math.min( ( sh - size ) / 2, sh - size - m - 72 ) ) )
	local width = 2 * size + spine
	return {
		def = def, size = size, vertical = false, gap = def.gap, strips = def.strips, strip = size / def.strips,
		hinge = left_x + size + def.gap, across0 = page_y,
		back = { x = left_x, y = page_y }, front = { x = left_x + size + spine, y = page_y },
		cover = { x = left_x - m, y = page_y - m },
		head = { x = left_x, y = page_y - m - 12, w = width },
		foot = { x = left_x, y = page_y + size + m + 13, w = width, row = true },
		panel = { x = left_x - m - 6 - BOOK_BOTTLE_W, y = page_y + 8 },
		right = left_x + width + m,
	}
end

-- The Palm Quire lies open as the manga draws it: the lid above, the pad of leaves below, the hinge between; the words
-- in a column on its right
local function layout_quire( def, sw, sh )
	local size = def.page
	local case = quire_case_geometry( def )
	local column = math.min( 230, math.floor( sw / 2 ) - 40 )
	local x = math.floor( ( sw - size - column - 24 ) / 2 )
	local lid_y = math.floor( ( sh - 2 * size - 2 * def.gap ) / 2 )
	local pad_y = lid_y + size + 2 * def.gap
	local cx = x + size + BOOK_LOOKS.quire.side + 12
	return {
		def = def, size = size, vertical = true, gap = def.gap, strips = def.strips, strip = size / def.strips,
		hinge = pad_y - def.gap, across0 = x,
		back = { x = x, y = lid_y }, front = { x = x, y = pad_y },
		cover = { x = x - BOOK_LOOKS.quire.side, y = lid_y - BOOK_LOOKS.quire.top, h = case.h },
		head = { x = cx, y = lid_y - 6, w = column },
		labels = { x = cx, y = pad_y + 4, w = column },
		foot = { x = cx, y = pad_y + 53, w = column, grouped = true },
		panel = { x = x - BOOK_LOOKS.quire.side - 6 - BOOK_BOTTLE_W, y = lid_y + 8 },
		right = cx + column,
	}
end

local function over_page( pos, mx, my )
	local size = view.size
	if view.def.round then
		return ( mx - pos.x - size / 2 ) ^ 2 + ( my - pos.y - size / 2 ) ^ 2 <= ( size / 2 ) ^ 2
	end
	return mx >= pos.x and my >= pos.y and mx <= pos.x + size and my <= pos.y + size
end

-- a point of the page where the pen draws: not over its edge
local function drawable( x, y )
	local size = view.size
	if view.def.round then return ( x - size / 2 ) ^ 2 + ( y - size / 2 ) ^ 2 <= ( size / 2 - 5 ) ^ 2 end
	return x >= 6 and y >= 6 and x <= size - 6 and y <= size - 6
end

---- drawing the book: the pages (the pen's kit, the hints and the front pages are in book_pages.lua) ----

local function paragraph( x, y, width, str, color ) return D.wrapped( D.SCREEN, x, y, width, str, color ) end

-- A page of the Test Book: the seal a little smaller, what it is over it, the sign tried under it
local TEST_SEAL_SCALE = 0.86
local function draw_test_content( s, entry )
	local color = paper_color( wiki_color( entry ) )
	draw_strokes( s, wiki_page_strokes( entry ), color, nil, nil, true, TEST_SEAL_SCALE )
	local look = cur.look
	centered_on( s, look.name_y, entry.title, color, entry.key == cur.active_wiki and 2 * look.ribbon.x - 2 or 12 )
	centered_on( s, view.size - 24, entry.sign, NOTE_COLOR )
end

-- A page of the wiki's grimoire: the seal, its name and its tier (the quire's small leaves: the seal only)
local function draw_wiki_content( s, p )
	local entry = wiki_entry( p )
	if not entry then return end
	if entry.test then return draw_test_content( s, entry ) end
	local color = paper_color( wiki_color( entry ) )
	draw_strokes( s, wiki_page_strokes( entry ), color, nil, nil, true )
	if cur.def.round then return end
	local look = cur.look
	centered_on( s, look.name_y, entry.name, color, entry.key == cur.active_wiki and 2 * look.ribbon.x - 2 or 30 )
	local tier = entry_tier( entry.key )
	if tier then s:text( look.label.x, look.name_y, sheet_tier_name( tier ), NOTE_COLOR ) end
end

-- A seal's page: the seal as it was drawn (or as the sheet has it), its name above the ring and a little bottle for its
-- dyed ink (its quality is written under the book while the mouse is over it; the quire's leaves are too small for more
-- than the seal)
local function draw_seal_content( s, i )
	local size, look = view.size, cur.look
	local seal = cur.seals[i]
	local sheet = seal.sheet ~= ""
	draw_strokes( s, seal.strokes, nil, nil, sheet and seal.inks ~= "" and seal.inks or nil, sheet, sheet and cur.def.sheet_scale )
	if cur.def.round then return end
	local dark = sheet and page_kind( cur.def.intro + i ) == "dark"
	centered_on( s, sheet and look.sheet_name_y or look.name_y, seal.name, dark and { 0.22, 0.04, 0.04 } or paper_color( seal.color ),
		i == cur.active and 2 * look.ribbon.x - 2 or ( sheet and 36 or 12 ) )
	local mix = ink_mix( ( seal.spell:match( "^[^&]*" ) or "" ):match( "ink=([^;]*)" ) )
	local best, share = nil, 0
	for key, v in pairs( mix ) do
		if v > share then best, share = INK_BY_KEY[key], v end
	end
	if best then draw_bottle( s, size - look.bottle.x, size - look.bottle.y, best, share, 21, 0.8 ) end
end

-- The back of the quire's leaf 'p', lying on the lid: its drawing shows through, mirrored and faint
local function draw_leaf_back( s, p )
	local seal = not wiki and cur.seals[p]
	local entry = wiki_entry( p )
	local list, grimoire, scale
	if entry then list, grimoire = wiki_page_strokes( entry ), true
	elseif seal then list, grimoire, scale = seal.strokes, seal.sheet ~= "", seal.sheet ~= "" and cur.def.sheet_scale or nil
	elseif not wiki and editable_page( p ) then list = editable_page( p ).strokes end
	if not list then return end
	local size = view.size
	local k = grimoire and size / SEAL_PAGE_SIZE * ( scale or 1 ) or 1
	local c = grimoire and SEAL_PAGE_SIZE / 2 or size / 2
	D.strokes( s, list, function() return INK_COLOR, 0.1 end, nil, 26, nil, { c = c, k = k, ky = -k, to = size / 2 } )
end

-- The page's number in the parted bottom line of its frame (book_gfx.lua): the pages up to the blank one, the
-- grimoire's pages; the quire's leaves have none
local function draw_page_number( s, p )
	if cur.def.round or p > ( wiki and #wiki_list() or last_blank_page() ) then return end
	if not wiki then
		if p <= FRONT_PAGES and cur.def.intro >= FRONT_PAGES then return end -- the cover and the title page have none
		p = p - math.min( FRONT_PAGES, cur.def.intro )
	end
	local digits = tostring( p )
	local w = #digits * ( BOOK_DIGIT_W + 1 ) - 1
	local x = math.floor( ( view.size - w ) / 2 )
	local y = view.size - cur.look.number_y - math.ceil( BOOK_DIGIT_H / 2 )
	for k = 1, #digits do
		s:image( x + ( k - 1 ) * ( BOOK_DIGIT_W + 1 ), y, book_digit_image( digits:sub( k, k ) ), 24, NUMBER_COLOR )
	end
end

-- the ribbon marks the active page: on the page, or over its top edge
local function ribbon_on( s, behind )
	local r = cur.look.ribbon
	local file = book_ribbon_image( cur.def )
	if cur.def.round and s.map then
		-- The quire shifts each row differently when held; draw rows separately so the ribbon follows without changing width.
		local cx, py = view.size - r.x + r.w / 2, -r.y
		for row = 0, r.h - 1 do
			local y0, y1 = py + row, py + row + 1
			local i0, i1 = s:locate( cx, y0 ), s:locate( cx, y1 )
			local seen = s:seen( i0 ) and s:seen( i1 )
			if seen or behind then
				local x = select( 1, s:map( cx, py + row + 0.5 ) )
				local _, screen_y0 = s:map( cx, y0 )
				local _, screen_y1 = s:map( cx, y1 )
				local z = seen and ( s:zc( i0, i1 ) - 0.001 ) or math.max( s:z( i0 ), s:z( i1 ) ) + 0.0005
				local shade = s:shade( { 1, 1, 1 }, i0 )
				local height = math.max( 0.25, math.abs( screen_y1 - screen_y0 ) + 0.1 )
				local left, top = x - r.w / 2, math.min( screen_y0, screen_y1 ) - 0.05
				D.image( left, top, book_ribbon_row_image( cur.def, row ), z, shade, 1, 1, height )
			end
		end
		return
	end
	s:image( view.size - r.x, -r.y, file, 18, nil, nil, nil, nil, behind )
end

local function is_active_face( face )
	if face <= 0 then return false end
	local entry = wiki_entry( face )
	if wiki then return entry ~= nil and entry.key == cur.active_wiki end
	return cur.active > 0 and face == cur.def.intro + cur.active
end

-- a seal that failed just now is drawn in red - only the strokes it fails on, when it knows them (they stay red)
local function failed_color( face )
	return result and face == cur.edit_face and not cur.edit.marked and ERROR_COLOR or nil
end

-- what is drawn on a face, onto any surface (a turning page draws its faces with it)
local function draw_face_content( s, face )
	if face < 0 then return draw_leaf_back( s, -face ) end
	draw_page_number( s, face )
	if wiki then return draw_wiki_content( s, face ) end
	local i = face - cur.def.intro
	if face <= cur.def.intro then
		if face <= FRONT_PAGES then P.front_page( s, face, cur.key, cur.look ) else P.hint_page( s, face - FRONT_PAGES ) end
	elseif cur.seals[i] and cur.seals[i].draft == "1" then
		draw_strokes( s, cur.seals[i].strokes, failed_color( face ) )
	elseif cur.seals[i] then
		draw_seal_content( s, i )
	elseif editable_page( face ) then
		draw_strokes( s, editable_page( face ).strokes, failed_color( face ) )
	end
end

-- A seal under the mouse - drawn, pasted in from a sheet or a page of the grimoire: the part of it nearest the mouse is
-- lit and what it was read as is written under it, with what it does in this seal. A drawn seal's sign that does
-- nothing there is told faded (seal_spell.lua leaves it out); a wiki's seal is cast as a whole, its parts are told by
-- what they mean. Not on the quire's small leaves.
local PART_REACH = 7                    -- page units: a part's line this close to the mouse is the one under it
local PART_GLOW = { 0.78, 0.5, 0.08 }   -- the part under the mouse, drawn over in this
local PART_FADED = { 0.45, 0.42, 0.38 } -- what a sign that does nothing here is told in
local PART_BACK = { 0.95, 0.91, 0.82 }  -- the paper behind the words, so the lines under them don't show through
-- what a part does in a seal of 'data' (its behaviors 'acts'), or nil: nothing; 'named': a wiki's seal - a part that
-- adds nothing of its own to the spell is told by what it means
local function part_does( sym, data, acts, named )
	if sym.kind == "sigil" then
		local def = DICTIONARY_SIGILS[sym.key] or {}
		if def.manifest or def.shape then return def.hint or "its own way" end
		return "the element"
	end
	local def = DICTIONARY_SIGNS[sym.key]
	if not def then return nil end
	local way = sym.inverted and def.invertible ~= false and def.inverted or def
	if way.behavior == "still" and data:find( "form=field", 1, true ) then return "holds the wave round you: a field" end
	if way.form then return way == def and def.hint or DICTIONARY_FORMS[way.form] end
	if way.condense then return way.condense > 0 and "compresses the element" or "loosens the element" end
	if way.behavior == "regions" then return def.hint end
	local b = way.behavior and acts[way.behavior] and DICTIONARY_BEHAVIOR[way.behavior]
	if b then return b.text or def.hint end
	if named then
		local meant = way.behavior and DICTIONARY_BEHAVIOR[way.behavior]
		return meant and meant.text or def.hint
	end
end

-- The parts of a wiki's seal on its grimoire page or sheet: read once by tools/make_grimoire_parts.py (reading a page
-- here would take seconds), over its page's strokes; kept with the entry
local function wiki_parts( entry )
	if entry.parts then return entry.parts end
	if not GRIMOIRE_PARTS then dofile_once( "mods/witch_notebook/files/grimoire_parts.lua" ) end
	local strokes, parts = wiki_page_strokes( entry ), {}
	for item in ( GRIMOIRE_PARTS[entry.key] or "" ):gmatch( "[^;]+" ) do
		local kind, key, inverted, ids = item:match( "^(%a+):([%w_%-]+):(%d):([%d,]+)$" )
		if kind then
			local part = { kind = kind, key = key, inverted = inverted == "1", strokes = {} }
			for i in ids:gmatch( "%d+" ) do part.strokes[#part.strokes + 1] = strokes[tonumber( i )] end
			parts[#parts + 1] = part
		end
	end
	entry.parts = parts
	return parts
end

-- The parts of a seal drawn in the book: the reading made when it awoke (finish_sigil); a page from before (a saved run)
-- is read again - kept only if it reads as the same element, its saved points being rounded. A wiki's seal drawn by
-- hand is told the way its grimoire page is (seal.lua seal_parts).
local function drawn_parts( seal, data )
	if seal.parts_of == seal.strokes and seal.parts_data == data then return seal.parts end
	local named = data:match( "named=([%w_]+)" )
	local entry = named and GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[named]
	local ok, tree, _, partial = pcall( parse_seal, seal.strokes )
	tree = ok and ( tree or ( entry and partial ) ) or nil
	local parts = {}
	if entry then
		parts = seal_parts( seal.strokes, tree, entry )
	elseif tree then
		local same = compile_spell( tree )
		if same and same.element == data:match( "element=([%w_]+)" ) then parts = tree.symbols end
	end
	seal.parts, seal.parts_of, seal.parts_data = parts, seal.strokes, data
	return parts
end

-- 'parts' of a seal of spell 'data' on the surface 's', the mouse at 'px', 'py' on the page; 'frame': where the parts'
-- strokes lie on the page ({ c, k, to }: page = to + ( point - c ) * k; nil: page units); 'named': a wiki's seal, its
-- name - a part of kind 'mark' (grimoire_parts.lua) is one of its own glyphs, not in the book's lists
local function draw_parts( s, parts, data, px, py, frame, named )
	if cur.def.round or #parts == 0 then return end
	local c, k, to = 0, 1, 0
	if frame then c, k, to = frame.c, frame.k, frame.to end
	local gx, gy = c + ( px - to ) / k, c + ( py - to ) / k
	-- the part whose line passes nearest the mouse
	local part, nearest = nil, ( PART_REACH / k ) ^ 2
	for _, sym in ipairs( parts ) do
		for _, stroke in ipairs( sym.strokes or {} ) do
			for _, p in ipairs( stroke ) do
				local d = ( p.x - gx ) ^ 2 + ( p.y - gy ) ^ 2
				if d < nearest then part, nearest = sym, d end
			end
		end
	end
	if not part then return end
	local acts = {}
	for key in ( data:match( "b=([^;]*)" ) or "" ):gmatch( "(%w+):" ) do acts[key] = true end
	local name
	if part.kind == "mark" then
		name = "A sign of " .. ( type( named ) == "string" and ( named .. "'s own" ) or "this seal's own" )
	elseif part.kind == "sigil" then
		local def = DICTIONARY_SIGILS[part.key] or {}
		local element = def.element and DICTIONARY_ELEMENTS[def.element]
		name = def.name or element and element.name
	else
		local def = DICTIONARY_SIGNS[part.key]
		name = def and ( def.name .. ( part.inverted and def.inverted and " (facing out)" or "" ) )
	end
	if not name then return end
	local does = part.kind == "mark" or part_does( part, data, acts, named )
	local lines = { part.kind == "mark" and name or ( name .. ": " .. ( does or "does nothing in this seal" ) ) }
	D.strokes( s, part.strokes, function() return PART_GLOW, 1 end, nil, 24, nil, frame )
	local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
	for _, stroke in ipairs( part.strokes ) do
		for _, p in ipairs( stroke ) do
			minx, maxx = math.min( minx, p.x ), math.max( maxx, p.x )
			miny, maxy = math.min( miny, p.y ), math.max( maxy, p.y )
		end
	end
	minx, maxx, miny, maxy = to + ( minx - c ) * k, to + ( maxx - c ) * k, to + ( miny - c ) * k, to + ( maxy - c ) * k
	local size = view.size
	-- too wide for the page: the name over what it does
	if GuiGetTextDimensions( gui, lines[1] ) > size - 6 and part.kind ~= "mark" then
		lines = { name .. ":", does or "does nothing in this seal" }
	end
	local h = 11 * #lines
	local y = maxy + 3
	if y + h > size - 3 then y = miny - h - 1 end -- no room under it: over it
	for i, line in ipairs( lines ) do
		local w = GuiGetTextDimensions( gui, line )
		local x = math.max( 2, math.min( size - w - 2, ( minx + maxx - w ) / 2 ) )
		local ly = y + 11 * ( i - 1 )
		s:image( x - 2, ly - 1, NOTEBOOK_INK_IMAGE, 19, PART_BACK, 0.95, ( w + 4 ) / 2, 5.5 )
		s:text( x, ly, line, does and P.TEXT_COLOR or PART_FADED, 18 )
	end
end
-- where a grimoire's page lies on the book's page (book_pages.lua P.strokes)
local function grimoire_frame( scale )
	return { c = SEAL_PAGE_SIZE / 2, k = view.size / SEAL_PAGE_SIZE * ( scale or 1 ), to = view.size / 2 }
end

-- A face lying still: its paper and what is on it; with the mouse over it, what it is. 'still': the page lies under a
-- turning sheet - no buttons or hints under it.
local function draw_page( face, pos, mx, my, still )
	if face == 0 then return end -- the quire's lid: the case shows it
	local size = view.size
	local s = D.flat( pos.x, pos.y, cur.def, pos == view.front )
	s:page( page_kind( face ) )
	draw_face_content( s, face )
	if face < 0 then return end
	local label = view.labels or { x = pos.x, y = pos.y + size + cur.look.label_gap, w = size }
	local label_x = view.labels and label.x or pos.x
	if is_active_face( face ) then ribbon_on( s ) end
	if wiki then
		local entry = wiki_entry( face )
		if not entry then
			if face == 1 and cur.def.round then
				D.wrapped( s, 24, 42, size - 48, "The small seals you learn will be here.", NOTE_COLOR )
			elseif face == 1 then
				D.wrapped( s, 12, 60, size - 24, "The seals you learn will be here: seal sheets lie around the world and are sold in the Holy Mountains, forbidden ones only in Hell and Heaven.", NOTE_COLOR )
			end
			return
		end
		if still then return end
		local over = over_page( pos, mx, my )
		if over then
			hover_entry = entry
			if not entry.test then
				draw_parts( s, wiki_parts( entry ), ( entry.spell or "" ):match( "^[^&]*" ) or "", mx - pos.x, my - pos.y, grimoire_frame(),
					entry.name )
			end
		end
		if over and entry.key ~= cur.active_wiki then
			D.text( label_x, label.y, ( full_grimoire() or cur.def.test ) and "LMB - choose" or "learned", NOTE_COLOR )
		end
		return
	end
	local i = face - cur.def.intro
	local seal = cur.seals[i]
	if seal and awakening and awakening.page == face and not still then awaken_draw( awakening.state, s, 20 ) end
	if editable_page( face ) and not still then
		if result and face == cur.edit_face then
			if view.labels then paragraph( label.x, label.y, label.w, result.text, { 0.95, 0.4, 0.3 } )
			else centered_on( s, size - 19, result.text, ERROR_COLOR ) end
		elseif #editable_page( face ).strokes == 0 then
			local str = "New seal"
			if cur.def.round then s:text( ( size - GuiGetTextDimensions( gui, str ) ) / 2, 14, str, NOTE_COLOR )
			else s:text( cur.look.label.x, cur.look.label.y, str, NOTE_COLOR ) end
		end
	end
	if still or not seal or seal.draft == "1" then return end
	-- by the page: a seal's quality or choosing it, a new sheet's word and a button to tear it out
	local over = over_page( pos, mx, my )
	if over and i ~= cur.active then
		D.text( label_x, label.y, "LMB - choose", NOTE_COLOR )
	end
	if over then
		local entry = seal.sheet ~= "" and GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[seal.sheet]
		local inks = ink_mix_text( ink_mix( ( seal.spell:match( "^[^&]*" ) or "" ):match( "ink=([^;]*)" ) ) )
		local function sentence( str ) return str:find( "[%.!?]$" ) and str or ( str .. "." ) end
		hover_text = sentence( entry and entry.effect or seal.name ) .. ( seal.quality ~= "" and ( " " .. sentence( seal.quality ) ) or "" )
			.. ( inks and ( " Ink: " .. inks .. "." ) or "" )
		local data = seal.spell:match( "^[^&]*" ) or ""
		if entry then
			draw_parts( s, wiki_parts( entry ), data, mx - pos.x, my - pos.y, grimoire_frame( cur.def.sheet_scale ), entry.name )
		else
			hover_seal = seal
			local named = data:match( "named=([%w_]+)" )
			named = named and GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[named]
			draw_parts( s, drawn_parts( seal, data ), data, mx - pos.x, my - pos.y, nil, named and named.name )
		end
	end
	local row_y = label.y + ( view.labels and 11 or 0 )
	if seal.fresh == "1" then
		if view.labels then D.text( label.x, row_y, "new sheet", GOLD_COLOR ) else D.centered( pos.x, size, label.y, "new sheet", GOLD_COLOR ) end
	end
	local asking = tear and tear.seal == i
	local text = asking and "[really tear out?]" or "[tear out]"
	local c = asking and { 0.95, 0.4, 0.3 } or { 0.55, 0.55, 0.55 }
	GuiColorSetForNextWidget( gui, c[1], c[2], c[3], 1 )
	local tear_x = view.labels and label.x or pos.x + size - GuiGetTextDimensions( gui, text )
	local tear_y = view.labels and row_y + 11 or row_y
	if seal.sheet == "" then
		local edit_w = GuiGetTextDimensions( gui, "[edit]" )
		local edit_x = view.labels and tear_x + GuiGetTextDimensions( gui, text ) + 6 or tear_x - edit_w - 6
		GuiColorSetForNextWidget( gui, 0.55, 0.55, 0.55, 1 )
		if GuiButton( gui, BUTTON.EDIT + ( face + 1 ) % 2, edit_x, tear_y, "[edit]" ) then
			tear = nil
			edit_seal( i )
			return
		end
	end
	if GuiButton( gui, BUTTON.TEAR + ( face + 1 ) % 2, tear_x, tear_y, text ) then
		if asking then
			tear = nil
			tear_out( i )
		else
			tear = { seal = i, frames = TEAR_FRAMES }
		end
	end
end

---- turning pages, drawn ----

-- The pages turning: the pages the sheets uncover and cover lie under them, the sheets over them. Only what shows is
-- drawn: nothing under a sheet that covers it.
local function draw_flips()
	local frames = cur.def.flip_frames
	-- the sheets in the book's order
	local order = {}
	for k, f in ipairs( flips ) do order[k] = f end
	table.sort( order, function( a, b ) return math.max( a.from, a.to ) < math.max( b.from, b.to ) end )
	local shapes = {}
	for rank, f in ipairs( order ) do shapes[rank] = T.geometry( view, f, rank - 1, frames ) end
	T.hide_covered( view, shapes )
	D.covered = T.covered( view, shapes )
	local lo, hi = spreads_in_air()
	draw_page( ( spread_faces( lo ) ), view.back, 0, 0, true )
	draw_page( select( 2, spread_faces( hi ) ), view.front, 0, 0, true )
	D.covered = nil
	for _, shape in ipairs( shapes ) do
		local faces = sheet_faces( shape.f )
		for _, face in ipairs( faces ) do face.kind = page_kind( face.face ) end
		T.draw_sheet( view, shape, faces, function( s, face, seen )
			if seen then draw_face_content( s, face ) end
			-- the ribbon of the active page: turned away, the paper hides it but for its end past the edge
			if is_active_face( face ) then ribbon_on( s, true ) end
		end )
	end
end

---- around the pages ----

-- Only inks in the witch's flasks are shown. The eraser below them removes parts of the unfinished drawing.
local function draw_ink_panel( mx, my, clicked )
	local x = view.panel.x
	local step = 24
	local row = 0
	for _, ink in ipairs( INKS ) do
		local have = amounts[ink.key] or 0
		if have >= 1 then
			local y = view.panel.y + row * step
			row = row + 1
			local selected = not cur.eraser_selected and ink.key == selected_ink
			local over = mx >= x - 3 and mx <= x + BOOK_BOTTLE_W + 3 and my >= y - 2 and my <= y + BOOK_BOTTLE_H + 2
			if selected then
				local c = ink.liquid
				D.image( x + BOOK_BOTTLE_W / 2 - 12.5, y + BOOK_BOTTLE_H / 2 - 12.5, BOOK_GLOW_IMAGE, 24, { c[1] / 255, c[2] / 255, c[3] / 255 }, 0.9 )
			end
			local bob = selected and -1 or 0
			draw_bottle( D.SCREEN, x, y + bob, ink, math.min( 1, have / INK_FLASK ), 22, 1, false )
			if selected then D.rect( x + 1, y + BOOK_BOTTLE_H + 1, BOOK_BOTTLE_W - 2, 1, GOLD_COLOR, 22 ) end
			if over then
				hover_text = ink.name .. " - " .. tostring( have ) .. " of " .. INK_FLASK .. ". " .. ink.text
				if clicked then
					selected_ink = ink.key
					cur.eraser_selected = false
					GlobalsSetValue( INK_VAR, selected_ink )
				end
			end
		end
	end
	local y = view.panel.y + row * step
	-- GuiButton fires on release: a line drawn from the page and let go over Clear must not wipe it
	local function pressed( id, bx, by, label )
		local w, h = GuiGetTextDimensions( gui, label )
		notebook_button_rects[id] = { bx, by, w, h }
		local p = press_at
		return GuiButton( gui, id, bx, by, label ) and p ~= nil
			and p[1] >= bx - 2 and p[1] <= bx + w + 2 and p[2] >= by - 2 and p[2] <= by + h + 2
	end
	local color = cur.eraser_selected and GOLD_COLOR or GREY
	GuiColorSetForNextWidget( gui, color[1], color[2], color[3], 1 )
	if pressed( BUTTON.ERASER, x - 3, y, "Erase" ) then cur.eraser_selected = true end
	local back, front = spread_faces( cur.spread )
	if not turning() and ( back == cur.edit_face or front == cur.edit_face ) then
		if pressed( BUTTON.CLEAR, x - 3, y + 12, "Clear" ) then clear_page() end
		if cur.edit.failed and pressed( BUTTON.RETRY, x - 3, y + 24, "Try seal" ) then finish_sigil() end
	end
end

-- When the selected ink has run dry, the book takes another the flasks hold
local function pick_available_ink()
	if ( amounts[selected_ink] or 0 ) >= 1 then return end
	for _, ink in ipairs( INKS ) do
		if ( amounts[ink.key] or 0 ) >= 1 then
			selected_ink = ink.key
			GlobalsSetValue( INK_VAR, selected_ink )
			return
		end
	end
end

-- a warning when the selected ink has run out (the bottles left of the book show how much is left); returns the y below it
local function draw_ink_warning( x, y, width )
	local ink = INK_BY_KEY[selected_ink] or INKS[1]
	if ( amounts[ink.key] or 0 ) >= 1 then return y end
	local any = false
	for _, n in pairs( amounts ) do if n >= 1 then any = true end end
	return paragraph( x, y, width, any and "This ink has run out - choose another on the left of the book" or "The ink has run out - find a flask of Conjuring Ink",
		{ 0.9, 0.3, 0.2 } )
end

-- the grimoire's sections: { name, page } of the first page of each
local wiki_tabs, wiki_tabs_key
local function wiki_sections()
	local list = wiki_list()
	if wiki_tabs and wiki_tabs_key == wiki_list_key then return wiki_tabs end
	wiki_tabs, wiki_tabs_key = {}, wiki_list_key
	local seen = {}
	for i, entry in ipairs( list ) do
		if not seen[entry.category] then
			seen[entry.category] = true
			wiki_tabs[#wiki_tabs + 1] = { name = entry.category, page = i }
		end
	end
	return wiki_tabs
end

-- Buttons side by side from x, a new row when the next doesn't fit before x + width: { label, color, id } - returns the
-- index of the one clicked, and the y below the rows
local function button_rows( x, y, width, buttons )
	local cx, clicked = x, nil
	for k, b in ipairs( buttons ) do
		local w = GuiGetTextDimensions( gui, b.label )
		if cx > x and cx + w > x + width then
			cx = x
			y = y + 11
		end
		if b.id then
			GuiZSetForNextWidget( gui, 20 )
			GuiColorSetForNextWidget( gui, b.color[1], b.color[2], b.color[3], b.alpha or 1 )
			if GuiButton( gui, b.id, cx, y, b.label ) then clicked = k end
		else
			D.text( cx, y, b.label, b.color )
		end
		cx = cx + w + 8
	end
	return clicked, y + 11
end

-- Under the book in the grimoire: its sections to jump to, and what the seal under the mouse does. Returns the y below.
local function draw_wiki_footer( x, y, width )
	if not full_grimoire() then
		y = paragraph( x, y, width, "Seals learned: " .. #wiki_list() .. " of " .. #( GRIMOIRE or {} )
			.. " - sheets lie around the world and are sold in the Holy Mountains", NOTE_COLOR )
	end
	local great = wiki_too_great()
	if great > 0 then y = paragraph( x, y, width, great .. " more too great for the " .. cur.def.name .. "'s pages", NOTE_COLOR ) end
	local tabs = wiki_sections()
	local page = spread_faces( cur.spread )
	if cur.def.round then page = cur.spread end
	local buttons = {}
	for k, tab in ipairs( tabs ) do
		local next_page = tabs[k + 1] and tabs[k + 1].page or math.huge
		local last_on_view = cur.def.round and page or page + 1
		local here = last_on_view >= tab.page and page < next_page
		buttons[k] = { label = here and ( "[" .. tab.name .. "]" ) or tab.name, color = here and GOLD_COLOR or GREY, id = BUTTON.TAB + k, page = tab.page, here = here }
	end
	local clicked
	clicked, y = button_rows( x, y, width, buttons )
	if clicked and not buttons[clicked].here then turn_pages( spread_of( buttons[clicked].page ) - cur.spread ) end
	y = y + 3
	if hover_entry then y = paragraph( x, y, width, hover_entry.effect, LIGHT_TEXT ) end
	return y
end

---- the Test Book's sections (test_book.lua TestBook.sections): its groups and the group's items over the book, the
---- item's parts (its forms) under it; a click turns to the first page of one ----

-- how many rows button_rows lays these buttons out in
local function rows_count( width, buttons )
	local cx, rows = 0, 1
	for _, b in ipairs( buttons ) do
		local w = GuiGetTextDimensions( gui, b.label )
		if cx > 0 and cx + w > width then cx, rows = 0, rows + 1 end
		cx = cx + w + 8
	end
	return rows
end

-- the pages on view: the first and the last
local function pages_on_view()
	local back, front = spread_faces( cur.spread )
	if cur.def.round then back = front end
	return math.max( 1, back ), math.min( front, #wiki_list() )
end

-- which of the sections (each { name, page }) holds page 'p'
local function section_at( list, p )
	local at = 1
	for k, sec in ipairs( list ) do if sec.page <= p then at = k end end
	return at
end

-- buttons for sections that run until the next one begins ('stop': the page after the last one's end): those on view
-- in gold; 'label': a word before them
local function section_buttons( list, stop, id, label )
	local first, last = pages_on_view()
	local buttons = {}
	if label then buttons[1] = { label = label, color = NOTE_COLOR } end
	for k, sec in ipairs( list ) do
		local here = sec.page <= last and ( list[k + 1] and list[k + 1].page or stop ) > first
		buttons[#buttons + 1] = { label = here and ( "[" .. sec.name .. "]" ) or sec.name, color = here and GOLD_COLOR or GREY,
			id = id + k, page = sec.page }
	end
	return buttons
end

-- the group, the item and where the item ends, by the last page on view
local function test_here()
	local sections, stop = TestBook.sections(), #wiki_list() + 1
	local _, last = pages_on_view()
	local g = section_at( sections, last )
	local group = sections[g]
	local group_stop = sections[g + 1] and sections[g + 1].page or stop
	local i = section_at( group.items, last )
	return sections, group, group_stop, group.items[i], group.items[i + 1] and group.items[i + 1].page or group_stop
end

local function turn_to_section( buttons, clicked )
	if clicked and buttons[clicked].page then turn_pages( spread_of( buttons[clicked].page ) - cur.spread - queued ) end
end

-- the groups and the group's items in rows ending over y; returns the top of the rows
local function draw_test_head( x, y, width )
	local sections, group, group_stop = test_here()
	local groups = section_buttons( sections, #wiki_list() + 1, BUTTON.TEST )
	local items = section_buttons( group.items, group_stop, BUTTON.TEST + 20 )
	local top = y - 11 * ( rows_count( width, groups ) + rows_count( width, items ) ) - 2
	local clicked, below = button_rows( x, top, width, groups )
	turn_to_section( groups, clicked )
	turn_to_section( items, ( button_rows( x, below, width, items ) ) )
	return top
end

-- under the book: the item's parts. Returns the y below.
local function draw_test_footer( x, y, width )
	local _, _, _, item, item_stop = test_here()
	local parts = section_buttons( item.parts, item_stop, BUTTON.TEST + 40, item.name .. ":" )
	local clicked
	clicked, y = button_rows( x, y, width, parts )
	turn_to_section( parts, clicked )
	return y
end

-- Beside each page: what its seal does (test_book.lua TestBook.notes): what appears and its numbers, each sign and what
-- shows it, what the sign changed, what the seal is drawn of
local NOTE_LOOK = { head = { GOLD_COLOR, 0 }, body = { LIGHT_TEXT, 0 }, sign = { { 0.75, 0.88, 1 }, 4 }, test = { GREY, 0 },
	diff = { { 0.98, 0.78, 0.5 }, 4 }, drawn = { GREY, 4 }, ink = { { 0.85, 0.75, 1 }, 4 } }
local NOTES_WIDTH = 210 -- at most

-- how many lines D.wrapped makes of 'str' in 'width'
local function line_count( str, width )
	local line, n = "", 0
	for word in str:gmatch( "%S+" ) do
		local try = line == "" and word or ( line .. " " .. word )
		if line ~= "" and GuiGetTextDimensions( gui, try ) > width then n, line = n + 1, word else line = try end
	end
	return n + ( line ~= "" and 1 or 0 )
end

-- the drawn seal's notes, told close: what appears with its numbers and the seal's quality if it isn't flawless, then
-- each sign ('hints': with what shows it), the inks, the seals cast with it
local function seal_rows( seal, hints )
	if seal.notes_of ~= seal.spell then seal.notes, seal.notes_of = spell_notes( seal.spell ), seal.spell end
	local what, rows = {}, {}
	for _, line in ipairs( seal.notes ) do
		if line.kind == "head" or line.kind == "body" then
			what[#what + 1] = line.text
		elseif line.kind == "test" then
			if hints and #rows > 0 then rows[#rows].text = rows[#rows].text .. " - " .. line.text end
		else
			rows[#rows + 1] = { text = line.text, look = NOTE_LOOK[line.kind] or NOTE_LOOK.body }
		end
	end
	local quality = ( seal.quality ~= "" and seal.quality ~= "Flawless seal!" ) and ( ". " .. seal.quality ) or ""
	table.insert( rows, 1, { text = table.concat( what, "; " ):gsub( "; ", ": ", 1 ) .. quality, look = NOTE_LOOK.body } )
	return rows
end

-- Under the book, the drawn seal under the mouse: what it does (spell_notes.lua). Where the screen is too short for it,
-- beside the book ('beside': x, y, w of a column there), and then without what shows the signs. Returns the y below.
local function draw_seal_notes( x, y, width, seal, beside )
	local _, sh = GuiGetScreenDimensions( gui )
	local places = {}
	for _, hints in ipairs( { true, false } ) do
		places[#places + 1] = { x, y, width, hints }
		if beside then places[#places + 1] = { beside.x, beside.y, beside.w, hints } end
	end
	local at, rows
	for _, place in ipairs( places ) do
		rows = seal_rows( seal, place[4] )
		local lines = 0
		for _, row in ipairs( rows ) do lines = lines + line_count( row.text, place[3] ) end
		at = place
		if place[2] + 10 * lines <= sh - 2 then break end
	end
	x, y, width = at[1], at[2], at[3]
	for _, row in ipairs( rows ) do y = paragraph( x, y, width, row.text, row.look[1] ) end
	return y
end
local function draw_test_notes( face, x, width )
	local entry = face > 0 and wiki_entry( face )
	if not entry then return end
	local y = view.back.y
	for _, line in ipairs( TestBook.notes( entry ) ) do
		local look = NOTE_LOOK[line.kind] or NOTE_LOOK.body
		y = paragraph( x, y + look[2], width, line.text, look[1] )
	end
end

-- The pages' edges under the open book, more on the side with more pages; the quire's leaves stacked under the pad's
-- top leaf and over the lid (while pages turn, under the sheets in the air)
local function draw_page_stacks()
	local size = view.size
	local lo, hi = spreads_in_air()
	local before = cur.def.round and ( lo - 1 ) or 2 * ( lo - 1 )
	local after = cur.def.round and ( last_spread() - hi ) or 2 * ( last_spread() - hi )
	local edge = cur.look.edge
	local function stack( count, pos, dx, dy )
		local layers = math.min( 4, math.ceil( count / 3 ) )
		for k = layers, 1, -1 do
			local shade = 1 - 0.07 * k
			local color = { edge[1] * shade, edge[2] * shade, edge[3] * shade }
			if cur.def.round then
				D.image( pos.x + dx * k, pos.y + dy * k, QUIRE_EDGE_IMAGE, 36 - k * 0.1, color )
			else
				D.rect( pos.x + dx * k, pos.y + dy * k, size, size, color, 36 - k * 0.1 )
			end
		end
	end
	if cur.def.round then
		stack( before, view.back, 0, -1 )
		stack( after, view.front, 0, 1 )
	else
		stack( before, view.back, -1, 0.5 )
		stack( after, view.front, 1, 0.5 )
	end
end

-- The ribbon bookmark of an active page out of view: it lies on its page inside the closed pages as it lay on view, its
-- end showing over their edge.
local function active_page()
	if wiki then
		for p, entry in ipairs( wiki_list() ) do
			if entry.key == cur.active_wiki then return p end
		end
		return nil
	end
	return cur.active > 0 and cur.def.intro + cur.active or nil
end

local function draw_ribbon_end( mx, my, clicked )
	local p = active_page()
	if not p then return end
	-- the pages on view: while pages turn, all from the lowest spread in the air to the highest
	local lo, hi = spreads_in_air()
	if cur.def.round then
		if p >= lo and p <= hi then return end
		local r = cur.look.ribbon
		local pos = p < lo and view.back or view.front
		local x = pos.x + view.size - r.x
		local y = pos.y - r.y
		local file = book_ribbon_image( cur.def )
		if p < lo then
			-- Match the ribbon's bounding box when the quire leaf has finished turning onto the lid.
			y = pos.y + view.size - r.h + r.y
			file = book_ribbon_flipped_image( cur.def )
		end
		local over = mx >= x - 2 and mx <= x + r.w + 2 and my >= y - 3 and my <= y + r.h + 2
		D.image( x, y, file, 31, over and { 1.15, 1.1, 1.1 } or nil )
		if over then
			hover_text = "Bookmark: the active seal's page - click to open it"
			if clicked and not turning() then turn_pages( p - cur.spread - queued ) end
		end
		return
	end
	if p >= 2 * lo - 1 and p <= 2 * hi then return end
	local on = math.ceil( p / 2 )
	local size, r = view.size, cur.look.ribbon
	local left = on < lo
	local face_up = ( p % 2 == 1 ) == left
	local x = ( left and view.back.x or view.front.x ) + ( face_up and size - r.x or r.x - r.w )
	local y = view.back.y - r.y
	local over = mx >= x - 2 and mx <= x + r.w + 2 and my >= y - 3 and my <= view.back.y + 2
	-- under the pages on top of it: only its end past their edge shows
	D.image( x, y, book_ribbon_image( cur.def ), 31, over and { 1.15, 1.1, 1.1 } or nil )
	if over then
		hover_text = "Bookmark: the active seal's page - click to open it"
		if clicked then turn_pages( on - cur.spread - queued ) end
	end
end

-- The bottom outer corner of a page under the mouse turns up (a dog-ear) and a click there turns the page: -1 - the
-- left page's corner (back), 1 - the right page's (on), nil. The quire: the bottom of its leaf curls up (on), the top of
-- the leaves on its lid curls down (back). Not on the blank page: that one is drawn on.
local function corner_at( mx, my )
	if turning() then return nil end
	local size = view.size
	local back, front = spread_faces( cur.spread )
	local can_back = cur.spread > 1
	local can_on = cur.spread < last_spread()
	if cur.def.round then
		local cx, half = view.front.x + size / 2, cur.look.curl / 2
		if math.abs( mx - cx ) > half then return nil end
		if can_on and my >= view.front.y + size - 14 and my <= view.front.y + size + 2 then return 1 end
		if can_back and my >= view.back.y - 2 and my <= view.back.y + 14 then return -1 end
		return nil
	end
	local n = cur.look.dogear
	local bottom = view.back.y + size
	if my < bottom - n or my > bottom then return nil end
	if can_back and mx >= view.back.x and mx <= view.back.x + n then return -1 end
	if can_on and mx >= view.front.x + size - n and mx <= view.front.x + size then return 1 end
end

local function draw_corner( corner )
	local size = view.size
	if cur.def.round then
		local w = cur.look.curl
		if corner > 0 then
			D.image( view.front.x + ( size - w ) / 2, view.front.y + size - 14, QUIRE_CURL_IMAGE, 17 )
		else
			D.image( view.back.x + ( size - w ) / 2, view.back.y, QUIRE_CURL_UP_IMAGE, 17 )
		end
		hover_text = ( corner < 0 and "Flip the leaf back down" or "Flip the leaf up" ) .. ": click, or drag its edge"
		return
	end
	local n = cur.look.dogear
	D.image( corner < 0 and view.back.x or view.front.x + size - n, view.back.y + size - n, book_dogear_image( cur.def, corner > 0 ), 17 )
	hover_text = ( corner < 0 and "Turn back" or "Turn forward" ) .. ": click, or drag the corner"
end

-- the books the witch carries, by size: the one open in gold, the others to switch to
local function draw_book_tabs( x, y, width, carried )
	local buttons = {}
	local keys = {}
	for i, key in ipairs( BOOK_SHELF ) do
		if carried[key] then
			local open = key == cur.key
			buttons[#buttons + 1] = { label = open and BOOKS[key].name or ( "[" .. BOOKS[key].name .. "]" ), color = open and GOLD_COLOR or GREY,
				id = not open and BUTTON.BOOK + i or nil }
			keys[#buttons] = key
		end
	end
	if GRIMOIRE and not cur.def.test then
		buttons[#buttons + 1] = { label = wiki and "[My Seals]" or "[Grimoire]", color = GOLD_COLOR, id = BUTTON.WIKI }
		keys[#buttons] = "wiki"
	end
	local clicked, below = button_rows( x, y, width, buttons )
	if turning() then clicked = nil end
	return clicked and keys[clicked], below
end

local function draw_book( mx, my, clicked, carried )
	local size = view.size
	D.begin( gui )
	hover_entry, hover_text, hover_seal = nil, nil, nil

	-- the names over the book: the books the witch carries, the grimoire; recalibration on the right
	local recalibrate = "[Line not under the cursor?]"
	local recal_w = GuiGetTextDimensions( gui, recalibrate )
	local switch, head_below = draw_book_tabs( view.head.x, view.head.y, view.head.w - ( view.def.round and 0 or recal_w + 10 ), carried )
	local top = math.min( view.head.y, view.cover.y )
	if cur.def.test then top = math.min( top, draw_test_head( view.head.x, view.head.y, view.head.w ) ) end
	local recal_x, recal_y = view.head.x + view.head.w - recal_w, view.head.y
	if view.def.round then recal_x, recal_y = view.head.x, head_below + 2 end
	GuiZSetForNextWidget( gui, 20 )
	GuiColorSetForNextWidget( gui, 0.6, 0.6, 0.6, 1 )
	if GuiButton( gui, BUTTON.RECALIBRATE, recal_x, recal_y, recalibrate ) and not turning() then
		M.start()
	end

	-- the cover (the quire's case, its strap swinging under it) and the pages' edges
	D.image( view.cover.x, view.cover.y, book_cover_image( cur.def ), 45 )
	if cur.def.round then
		if #flips > 0 and not strap_flipping then QuireStrap.jolt( 0.8, -1.2 ) end
		strap_flipping = #flips > 0
		local vx, vy = witch_speed()
		QuireStrap.update( cur.def, view.cover.x, view.cover.y, vx, vy, mx, my )
		QuireStrap.draw()
	end
	draw_page_stacks()
	if #flips > 0 then
		draw_flips()
	else
		local back, front = spread_faces( cur.spread )
		draw_page( back, view.back, mx, my )
		draw_page( front, view.front, mx, my )
	end
	local corner = corner_at( mx, my )
	if corner then draw_corner( corner ) end
	draw_ribbon_end( mx, my, clicked )
	if not wiki then draw_ink_panel( mx, my, clicked ) end
	-- the Test Book: what the seals on view do, beside their pages
	local left, right = view.panel.x - 4, view.right + 4
	if cur.def.test then
		local sw = GuiGetScreenDimensions( gui )
		local lw, rw = math.min( NOTES_WIDTH, view.cover.x - 14 ), math.min( NOTES_WIDTH, sw - view.right - 14 )
		left, right = view.cover.x - 10 - lw, view.right + 8 + rw + 2
		if not turning() then
			local back, front = spread_faces( cur.spread )
			draw_test_notes( back, view.cover.x - 8 - lw, lw )
			draw_test_notes( front, view.right + 8, rw )
		end
	end
	if not wiki and not turning() and ( cur.eraser_selected or InputIsMouseButtonDown( MOUSE_RIGHT ) ) then
		local back, front = spread_faces( cur.spread )
		local pos = back == cur.edit_face and view.back or front == cur.edit_face and view.front
		if pos and over_page( pos, mx, my ) then
			D.image( mx - ERASER_RADIUS - 1, my - ERASER_RADIUS - 1, NOTEBOOK_ERASER_IMAGE, 18,
				NOTE_COLOR, 0.8, 1 / NOTEBOOK_BRUSH_RES )
		end
	end

	-- turning the pages, what to do, the ink, what is under the mouse
	local foot = view.foot
	local can_back, can_on = cur.spread > 1, cur.spread < last_spread()
	local back_label, on_label = "< [A]", "[D] >"
	if cur.def.round then back_label, on_label = "[A] Flip down", "[D] Flip up" end
	if foot.grouped then D.text( foot.x, foot.y - 12, "Pages", NOTE_COLOR ) end
	GuiColorSetForNextWidget( gui, GREY[1], GREY[2], GREY[3], can_back and 1 or 0.35 )
	if GuiButton( gui, BUTTON.BACK, foot.x, foot.y, back_label ) and can_back then turn_pages( -1 ) end
	GuiColorSetForNextWidget( gui, GREY[1], GREY[2], GREY[3], can_on and 1 or 0.35 )
	local on_x = foot.grouped and foot.x + GuiGetTextDimensions( gui, back_label ) + 12
		or foot.x + foot.w - GuiGetTextDimensions( gui, on_label )
	if GuiButton( gui, BUTTON.ON, on_x, foot.y, on_label ) and can_on then turn_pages( 1 ) end
	local open_hint = book_open_key_hint()
	local hint = wiki and ( ( full_grimoire() or cur.def.test ) and "LMB on a page - make it active, " .. open_hint .. " - close"
		or "Study and redraw the seals, " .. open_hint .. " - close" )
		or ( ( cur.eraser_selected and "LMB - erase, click an ink to draw" or "LMB - draw, RMB - erase" ) .. ", " .. open_hint .. " - close" )
	local y = foot.y + 12
	if foot.row then
		D.centered( foot.x, foot.w, foot.y, hint, nil, 70 )
	else
		y = paragraph( foot.x, y, foot.w, hint, GREY ) + 2
	end
	local bottom
	if wiki then
		bottom = ( cur.def.test and draw_test_footer or draw_wiki_footer )( foot.x, y + 2, foot.w ) + 4
		if note then bottom = paragraph( foot.x, bottom, foot.w, note.text, GOLD_COLOR ) end
	else
		y = draw_ink_warning( foot.x, y, foot.w )
		if note then
			y = paragraph( foot.x, y, foot.w, note.text, GOLD_COLOR )
		elseif hover_seal then
			local sw = GuiGetScreenDimensions( gui )
			local w = math.min( NOTES_WIDTH, sw - view.right - 14 )
			y = draw_seal_notes( foot.x, y, foot.w, hover_seal, w >= 80 and { x = view.right + 8, y = view.back.y, w = w } or nil )
		elseif hover_text then
			y = paragraph( foot.x, y, foot.w, hover_text, LIGHT_TEXT )
		end
		bottom = math.max( foot.y + 36, y + 2 )
	end

	notebook_box = { x0 = left, y0 = top - 2, x1 = right,
		y1 = math.max( bottom, view.cover.y + ( view.cover.h or size + 2 * cur.def.margin ) ) }

	if switch == "wiki" then
		toggle_wiki()
	elseif switch then
		put_away()
		open_book( switch )
	end
end

---- the game's calls ----

-- For the offline tests: where the open book lies (the layout) and which of its faces on view, "back" or "front", is
-- the blank page
function notebook_view()
	if not is_open or not view then return nil end
	local back, front = spread_faces( cur.spread )
	return view, ( not wiki and ( back == blank_page() or back == last_blank_page() ) and "back" )
		or ( not wiki and ( front == blank_page() or front == last_blank_page() ) and "front" ) or nil
end

function notebook_on_player_spawned( player )
	shown_open_key = nil
	-- the game may have been saved while the book was open
	set_controls_enabled( player, true )
	-- every run starts with the Spellbook
	if not GameHasFlagRun( BOOK_GIVEN_FLAG ) then
		GameAddFlagRun( BOOK_GIVEN_FLAG )
		book_set_owned( "book" )
		local x, y = EntityGetTransform( player )
		GamePickUpInventoryItem( player, EntityLoad( BOOKS.book.entity, x, y ), false )
	end
	-- while the mod is made: the other two books lie beside the witch
	books_spawn_for_testing( player )
end

-- Esc opens the pause menu (mods can't prevent that), it also closes the book
function notebook_on_pause()
	if is_open then close_notebook( get_player() ) end
end

local function any_key( keys, except )
	for _, key in ipairs( keys ) do
		if key ~= except and InputIsKeyJustDown( key ) then return true end
	end
	return false
end

-- the pages seen with the book open are no longer new
local function mark_seen()
	if wiki or turning() then return end
	local back, front = spread_faces( cur.spread )
	for _, face in ipairs( { back, front } ) do
		local i = face - cur.def.intro
		local seal = face > 0 and cur.seals[i]
		if seal and seal.fresh == "1" then
			seal.seen_frames = ( seal.seen_frames or 0 ) + 1
			if seal.seen_frames > 90 then
				seal.fresh = ""
				GlobalsSetValue( seal_var( cur, i, "fresh" ), "" )
			end
		end
	end
end

function notebook_update()
	gui = gui or GuiCreate()
	GuiStartFrame( gui )

	-- sheets picked up are pasted in, open or not
	paste_pending_sheets()

	local player = get_player()
	show_recharge( player )
	local carried = carried_books( player )
	local open_key = book_open_key()
	local open_rmb = book_open_rmb()
	local open_binds = open_key .. ( open_rmb and "+rmb" or "" )
	if player and shown_open_key ~= open_binds then
		for key in pairs( carried ) do name_book_items( load_book( key ) ) end
		shown_open_key = open_binds
	end
	local requested = GlobalsGetValue( BOOK_OPEN_REQUEST_VAR, "" )
	if requested ~= "" then GlobalsSetValue( BOOK_OPEN_REQUEST_VAR, "" ) end
	if InputIsKeyJustDown( open_key ) and player then
		if is_open then
			close_notebook( player )
		else
			local key = book_to_open( player, carried )
			if key then open_notebook( key ) end
		end
	elseif player and open_rmb and not is_open and not wait_release and not GameIsInventoryOpen()
		and InputIsMouseButtonJustDown( MOUSE_RIGHT ) then
		local key = book_to_open( player, carried, true )
		if key then open_notebook( key ) end
	elseif requested ~= "" and player and carried[requested] and not is_open then
		open_notebook( requested )
	end
	if wait_release and not InputIsMouseButtonDown( MOUSE_LEFT ) and not InputIsMouseButtonDown( MOUSE_RIGHT ) then
		wait_release = false
		if not is_open then set_controls_enabled( player, true ) end
	end
	if not is_open then return end
	if not player or GameIsInventoryOpen() or not carried[cur.key] then
		close_notebook( player )
		return
	end

	set_controls_enabled( player, false )

	local sw, sh = GuiGetScreenDimensions( gui )
	if M.calibrating then
		local ended = M.calibrate( gui, sw, sh )
		if ended == "done" then
			wait_release = true -- the click on the cross doesn't start a line on the page
			is_drawing = false
		elseif ended == "cancelled" then
			wait_release = InputIsMouseButtonDown( MOUSE_LEFT )
		end
		return
	end
	view = cur.def.round and layout_quire( cur.def, sw, sh ) or layout_spread( cur.def, sw, sh )
	P.begin( view.size )
	local size = view.size
	amounts = ink_amounts( player )
	if not is_drawing then pick_available_ink() end
	local ink = amounts[selected_ink] or 0
	local mx, my = M.position( sw, sh )
	if InputIsMouseButtonJustDown( MOUSE_LEFT ) then press_at = { mx, my } end
	local clicked = not wait_release and InputIsMouseButtonJustDown( MOUSE_LEFT )

	if notebook_box and clicked then
		local b = notebook_box
		if mx < b.x0 or my < b.y0 or mx > b.x1 or my > b.y1 then
			close_notebook( player )
			return
		end
	end

	-- a key assigned to open the book closes it instead of turning a page
	if any_key( KEYS_BACK, open_key ) or InputIsMouseButtonJustDown( WHEEL_UP ) then turn_pages( -1 ) end
	if any_key( KEYS_ON, open_key ) or InputIsMouseButtonJustDown( WHEEL_DOWN ) then turn_pages( 1 ) end
	if tear then
		tear.frames = tear.frames - 1
		if tear.frames <= 0 then tear = nil end
	end
	if note then
		note.frames = note.frames - 1
		if note.frames <= 0 then note = nil end
	end
	update_flips()
	mark_seen()

	-- a page's turned-up corner: held, the page follows the mouse; a click turns it
	if drag then update_drag( mx, my ) end
	local corner = corner_at( mx, my )
	if clicked and corner then
		grab_corner( corner, mx, my )
		clicked = false
	end

	-- a click on a seal's page makes it active
	local back, front = spread_faces( cur.spread )
	if clicked and not turning() then
		for _, face in ipairs( { back, front } ) do
			local pos = face == back and view.back or view.front
			if face > 0 and over_page( pos, mx, my ) then
				local entry = wiki_entry( face )
				if entry then
					if full_grimoire() or cur.def.test then
						set_active_wiki( cur, entry.key )
					else
						note = { text = "A learned seal: redraw it on a blank page - the book will recognize it and cast it.", frames = NOTE_FRAMES }
					end
				elseif not wiki and cur.seals[face - cur.def.intro] and cur.seals[face - cur.def.intro].draft ~= "1" then
					set_active( cur, face - cur.def.intro )
				end
			end
		end
	end

	-- Any unfinished page can take more ink. Select it when drawing or erasing on that face.
	if not wiki and not turning() and not is_drawing then
		if InputIsMouseButtonDown( MOUSE_LEFT ) or InputIsMouseButtonDown( MOUSE_RIGHT ) then
			if editable_page( back ) and drawable( mx - view.back.x, my - view.back.y ) then select_edit_page( back )
			elseif editable_page( front ) and drawable( mx - view.front.x, my - view.front.y ) then select_edit_page( front ) end
		elseif back ~= cur.edit_face and front ~= cur.edit_face then
			select_edit_page( editable_page( front ) and front or back )
		end
	end
	local edit_pos = not wiki and ( ( back == cur.edit_face and view.back ) or ( front == cur.edit_face and view.front ) )
	if not edit_pos then witch_notebook_finish_erase() end
	if result then
		-- the message fades; the drawing remains for correction
		result.frames = result.frames - 1
		if result.frames <= 0 then result = nil end
	end
	if edit_pos and not turning() then
		local x, y = mx - edit_pos.x, my - edit_pos.y
		local inside = drawable( x, y )
		local erase_down = InputIsMouseButtonDown( MOUSE_RIGHT ) or ( cur.eraser_selected and InputIsMouseButtonDown( MOUSE_LEFT ) )
		if erase_down and inside and not wait_release then
			if is_drawing then end_stroke() end
			witch_notebook_erase_at( x, y, cur.erase_last_x, cur.erase_last_y )
			cur.erase_last_x, cur.erase_last_y = x, y
		else
			cur.erase_last_x, cur.erase_last_y = nil, nil
			witch_notebook_finish_erase()
			local down = not cur.eraser_selected and InputIsMouseButtonDown( MOUSE_LEFT )
			if down and inside and ink >= 1 and not wait_release then
				if not is_drawing then
					result = nil
					cur.edit.strokes[#cur.edit.strokes + 1] = { ink = selected_ink }
					is_drawing = true
				end
				ink_debt = ink_debt + add_point( cur.edit.strokes[#cur.edit.strokes], x, y ) * INK_PER_UNIT
				if ink_debt >= 1 then
					local spent = ink_spend( player, math.floor( ink_debt ), cur.edit.strokes[#cur.edit.strokes].ink )
					ink_debt = ink_debt - spent
					amounts[selected_ink] = ( amounts[selected_ink] or 0 ) - spent
					if spent < 1 then amounts[selected_ink] = 0 end -- the flasks ran dry
				end
			elseif is_drawing then
				if inside and #cur.edit.strokes > 0 then add_point( cur.edit.strokes[#cur.edit.strokes], x, y, true ) end
				end_stroke() -- released the button, left the page or ran out of ink
			end
		end
	end

	draw_book( mx, my, clicked, carried )
end
