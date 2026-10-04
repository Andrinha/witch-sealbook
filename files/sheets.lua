-- Sheets with the wiki's seals ready drawn (grimoire.lua), found in the world and sold in the Holy Mountains. Picked
-- up (sheet_pickup.lua), a sheet is pasted into one of the witch's books that holds its seal (books.lua) as a page of
-- its own, cast like a drawn seal, and the seal is learned: the books' grimoire shows it to study and redraw
-- (notebook.lua). A sheet is as big as the book its seal needs: a round leaf for the Palm Quire, a page, a folio for the
-- Great Tome.
-- The deeper, the stronger the seals: every seal has a tier I-VII (SHEET_TIER, set by hand by what its magic does for
-- the witch), a tier for every stretch of the world between two Holy Mountains (TIER_DEPTHS). Forbidden seals are
-- found only in Hell and Heaven, drawn in blood.
-- The list needs the whole grimoire, so the mod makes it once at init (sheets_create) and writes it to a small
-- virtual file, SHEET_LIST_FILE, which the scripts that spawn sheets (world generation, chests, the Holy Mountain) read;
-- the file on disk holds the same list (tools/make_sheet_list.py).

dofile_once( "mods/witch_notebook/files/ink.lua" )
dofile_once( "mods/witch_notebook/files/books.lua" )

SHEET_ENTITY = "mods/witch_notebook/files/entities/sheet.xml"
SHEET_LIST_FILE = "mods/witch_notebook/files/sheet_list.lua"
SHEET_TIERS = 7
local TIER_NAMES = { "I", "II", "III", "IV", "V", "VI", "VII" }
local TIER_DEPTHS = { 1536, 3072, 5120, 6656, 8704, 10752 } -- where tiers II..VII begin: the Coal Pits, the Snowy Depths...
local PRICES = { 90, 150, 230, 330, 460, 620, 820 }
local FOUND_CHANCE = 30   -- percent of chests that hold a sheet too
local HELL_CHANCE = 55    -- ... in Hell and Heaven
SHOP_REPLACE_CHANCE = 10  -- percent of the Holy Mountain shop's spells replaced by a sheet or a flask of ink
local SHOP_INK_CHANCE = 35 -- percent of those that are a flask of ink rather than a sheet
local SHOP_DYED_CHANCE = 40 -- ... a flask of dyed ink, from tier III on

function sheet_gfx( key ) return "mods/witch_notebook/files/gfx/sheets/" .. key .. ".png" end
function sheet_tier_name( tier ) return TIER_NAMES[tier] or "?" end

-- Every seal's tier, by what its magic does for the witch. Each stretch of the world offers some fighting, some way
-- over the ground and some help; the sights and lights lie mostly near the surface, where they cost little. Warmth
-- and snow come before the Snowy Depths; lifts and bridges early, dashes and levitation in the Jungle, true flight,
-- windows and time at the bottom. A seal only the Great Tome holds is tier IV or more: there is no tome before.
-- The forbidden seals are not here: they are tier VII, only in Hell and Heaven.
SHEET_TIER = {
	-- I, the Mines: water to throw, small helpers, lights and sights
	watershot = 1, flying_watersculptures = 1, watersculpture = 1, phantasmal_fireball = 1, flowers_of_sand = 1,
	floating_drops = 1, washbarrel = 1, sewer_grate = 1, rainflinger = 1, floatglow = 1, light_beam = 1,
	flowers_of_light = 1, glowstone_path = 1, rainbringer = 1, water_rose = 1, loop_chalice = 1, playland_of_sand = 1,
	forbidden_glow = 1,
	-- II, the Coal Pits: first fire, decoys, footholds, warmth before the snow
	ring_of_fire = 2, pyreball = 2, water_horse = 2, glowing_owlcat = 2, grasping_wind = 2, smokesculpture = 2,
	bird_of_light = 2, makeover_mask = 2, everflow = 2, crystal_ribbon = 2, boulder_stretch = 2, billow_cluster = 2,
	snow_walking = 2, purify = 2, integration = 2, snugstone = 2, snowfending = 2, warmth_retention = 2,
	looking_glass = 2, vapor_bubble = 2, leech_of_light = 2, floatglow_anchored = 2,
	-- III, the Snowy Depths: bolts, lures and blinds, lifts and bridges
	flame_shot = 3, water_bolt_27 = 3, sourcewater = 3, forbidden_flames = 3, river_ferry = 3, pouch_of_calling = 3,
	giant_water_puppet = 3, flying_puppet = 3, smoke_cloud = 3, mist_basin = 3, rising_platform = 3, earth_lift = 3,
	sand_bridge = 3, icy_road = 3, replication = 3, wall_bend = 3, bubble_carriage = 3, water_orb = 3,
	waterflinger = 3, wash_spring = 3, pouch_guidance = 3, wand_of_water = 3, carousel = 3,
	-- IV, the Hiisi Base: strong attacks, digging, holding one enemy, wards
	spiraling_flame = 4, water_bolt_archives = 4, lightning_spell = 4, spike = 4, torchstag = 4, wall_breaker = 4,
	capture_pennant = 4, sand_cage = 4, sprite_winged = 4, illusion_cloak = 4, fish_guidance = 4, rising_wave = 4,
	frozen_path = 4, serpents_bed = 4, beastwarding = 4, rainwarding = 4, wallwarding = 4, tracking = 4,
	light_reducing = 4, light_tracer = 4, ancient_light_beacon = 4,
	-- V, the Jungle: blasts and waves, binding and drowning, dashes and levitation
	flame_burst = 5, water_bolt = 5, crystal_shard = 5, raincleaver = 5, rushing_wave = 5, dragon_smokesculpture = 5,
	torrential_flow = 5, lockwax = 5, water_cage = 5, smokesculpting = 5, wayward_whorlwind = 5, skysoaring = 5,
	levitation_spell = 5, sealchair = 5, wind_wall = 5, handheld_windowway = 5, sasaran_cloak = 5, garmentglimpse = 5,
	-- VI, the Vault: unmaking, hiding, flight, windows
	spell_of_reduction = 6, leech_counterclock = 6, borrowshade = 6, mirror_cloak = 6, sylph_shoes = 6,
	expansion_levitation = 6, windowway = 6, advanced_beastwarding = 6, mirror = 6, amplification = 6,
	-- VII, the Temple of the Art and below: the dragons and what bends the rules of the world
	water_dragon = 7, boilfire_dragon = 7, time_stop = 7, pegasus_carriage = 7, doorknob = 7, counterclock = 7,
	magic_cookpot = 7,
}
local UNLISTED_TIER = 4 -- a seal new to the grimoire and not yet in SHEET_TIER (the tests ask for it to be put there)

-- the forbidden seals, and the wiki's section of them (the Brimmed Caps' seals)
function sheet_entry_forbidden( entry )
	return entry.forbidden == true or entry.category == "Forbidden"
end

-- The seals in tiers: { key, name, element, tier, book (the smallest that holds it), forbidden }, by tier; the
-- forbidden ones are tier VII, last
function sheets_rank( grimoire )
	local ranked, forbidden = {}, {}
	for _, entry in ipairs( grimoire or {} ) do
		local row = { key = entry.key, name = entry.name, element = ( entry.spell or "" ):match( "element=([%w_]+)" ) or "light",
			book = seal_book( entry ) }
		if sheet_entry_forbidden( entry ) then
			row.forbidden, row.tier = true, SHEET_TIERS
			forbidden[#forbidden + 1] = row
		else
			row.tier = SHEET_TIER[entry.key] or UNLISTED_TIER
			ranked[#ranked + 1] = row
		end
	end
	table.sort( ranked, function( a, b ) if a.tier ~= b.tier then return a.tier < b.tier end return a.key < b.key end )
	for _, row in ipairs( forbidden ) do ranked[#ranked + 1] = row end
	return ranked
end

-- The list as the Lua source of SHEET_LIST_FILE
function sheets_list_source( rows )
	local out = { "-- Made by sheets.lua at mod init (sheets_create): the seals a sheet may carry, in tiers\nSHEET_LIST = {\n" }
	for _, row in ipairs( rows ) do
		out[#out + 1] = string.format( "\t{ key = %q, name = %q, element = %q, tier = %d%s%s },\n", row.key, row.name,
			row.element, row.tier, row.book ~= "book" and ( ", book = %q" ):format( row.book ) or "",
			row.forbidden and ", forbidden = true" or "" )
	end
	out[#out + 1] = "}\n"
	return table.concat( out )
end

---- the sheet's picture: a scrap of parchment with the seal on it, in its element's color (the forbidden in blood) ----

local function rgba( r, g, b, a )
	return color_abgr_merge( math.floor( r ), math.floor( g ), math.floor( b ), a or 255 )
end

-- a sheet is as big as the book its seal needs: the quire's round leaf, a page, a tome's folio (with a darker edge)
SHEET_PICTURES = {
	quire = { w = 11, h = 11, round = true },
	book = { w = 13, h = 15 },
	tome = { w = 17, h = 19, border = true },
}

local function draw_sheet_picture( key, strokes, color, forbidden, book )
	local pic = SHEET_PICTURES[book] or SHEET_PICTURES.book
	local w, h = pic.w, pic.h
	local id = ModImageMakeEditable( sheet_gfx( key ), w, h )
	if id == 0 then return end
	local paper = forbidden and { 150, 104, 84 } or { 236, 222, 184 }
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local c = 0
			local grain = ( ( x * 7 + y * 13 ) % 5 ) * 3
			if pic.round then
				local d = math.sqrt( ( x - ( w - 1 ) / 2 ) ^ 2 + ( y - ( h - 1 ) / 2 ) ^ 2 )
				if d <= w / 2 - 0.3 then
					local k = d > w / 2 - 1.3 and 0.72 or 1
					c = rgba( ( paper[1] - grain ) * k, ( paper[2] - grain ) * k, ( paper[3] - grain ) * k )
				end
			else
				local edge = math.min( x, y, w - 1 - x, h - 1 - y )
				local folded = x - ( w - 4 ) > y -- the top right corner is folded down
				if not folded then
					local k = edge == 0 and 0.72 or ( pic.border and edge == 1 and 0.86 or 1 )
					c = rgba( ( paper[1] - grain ) * k, ( paper[2] - grain ) * k, ( paper[3] - grain ) * k )
				elseif x - ( w - 4 ) == y + 1 then
					c = rgba( paper[1] * 0.8, paper[2] * 0.78, paper[3] * 0.74 )
				end
			end
			ModImageSetPixel( id, x, y, c )
		end
	end
	-- the seal, the grimoire's page (SEAL_PAGE_SIZE) squeezed into the sheet
	local ink = rgba( color[1] * 0.8, color[2] * 0.8, color[3] * 0.8 )
	local side = pic.round and w - 2 or w - 3
	local k, ox, oy = side / 180, ( w - side ) / 2, ( h - side ) / 2
	for _, stroke in ipairs( strokes ) do
		for i = 1, #stroke, 2 do
			local p = stroke[i]
			local x, y = math.floor( ox + p.x * k + 0.5 ), math.floor( oy + p.y * k + 0.5 )
			if x >= 1 and y >= 1 and x < w - 1 and y < h - 1 then ModImageSetPixel( id, x, y, ink ) end
		end
	end
end

-- At mod init: ranks the seals, writes SHEET_LIST_FILE and draws every sheet's picture
function sheets_create()
	if not GRIMOIRE then return end
	local rows = sheets_rank( GRIMOIRE )
	SHEET_LIST = rows -- the book shows the tiers
	ModTextFileSetContent( SHEET_LIST_FILE, sheets_list_source( rows ) )
	for _, row in ipairs( rows ) do
		local entry = GRIMOIRE_BY_KEY[row.key]
		local color = row.forbidden and { 190, 30, 50 } or sigil_icon_color( row.element )
		draw_sheet_picture( row.key, grimoire_strokes( entry ), color, row.forbidden, row.book )
	end
	return rows
end

---- where sheets are and what they carry ----

-- The tier of a place: a tier for every stretch of the world between two Holy Mountains; the parallel worlds and a
-- new game+ one more
function sheet_tier_at( x, y )
	local tier = 1
	for _, depth in ipairs( TIER_DEPTHS ) do
		if y >= depth then tier = tier + 1 end
	end
	if GetParallelWorldPosition and GetParallelWorldPosition( x, y ) ~= 0 then tier = tier + 1 end
	local ng = SessionNumbersGetValue and tonumber( SessionNumbersGetValue( "NEW_GAME_PLUS_COUNT" ) ) or 0
	if ( ng or 0 ) > 0 then tier = tier + 1 end
	return math.max( 1, math.min( SHEET_TIERS, tier ) )
end

-- Hell and Heaven (the Work's two worlds, beneath the Laboratory and over the mountain): the only places of the forbidden
function sheet_forbidden_place( x, y )
	local name = BiomeMapGetName and BiomeMapGetName( x, y ) or ""
	return tostring( name ):find( "victoryroom", 1, true ) ~= nil
end

local function load_list()
	if not SHEET_LIST then dofile_once( SHEET_LIST_FILE ) end
	return SHEET_LIST or {}
end

-- A seal for a sheet of 'tier' (weighted towards the tier, a lower one is common, a higher one rare; seals not learned yet
-- come up more often); in the forbidden places mostly the forbidden ones. The weights are the tiers', shared by their
-- seals: a tier of many seals comes up no more often than a tier of few. Uses the current random seed.
local TIER_WEIGHT = { [0] = 6, [-1] = 4, [-2] = 2, [1] = 1 } -- by how far the seal's tier is from the place's
local LOWER_WEIGHT = 0.6    -- every tier lower still
local FORBIDDEN_WEIGHT = 8  -- all the forbidden seals together, in Hell and Heaven
function sheet_pick( tier, forbidden_place )
	local list, sizes = load_list(), {}
	for _, row in ipairs( list ) do
		local group = row.forbidden and "forbidden" or row.tier
		sizes[group] = ( sizes[group] or 0 ) + 1
	end
	local choices, total = {}, 0
	for _, row in ipairs( list ) do
		local w
		if row.forbidden then
			w = forbidden_place and FORBIDDEN_WEIGHT / sizes.forbidden or 0
		else
			local d = row.tier - tier
			w = ( TIER_WEIGHT[d] or ( d < 0 and LOWER_WEIGHT or 0 ) ) / sizes[row.tier]
			if forbidden_place then w = w * 0.3 end
		end
		if w > 0 and not book_seal_learned( row.key ) then w = w * 3 end
		if w > 0 then
			total = total + w
			choices[#choices + 1] = { row = row, w = w }
		end
	end
	if total <= 0 then return nil end
	local r = Random( 1, 100000 ) / 100000 * total
	for _, c in ipairs( choices ) do
		r = r - c.w
		if r <= 0 then return c.row end
	end
	return choices[#choices].row
end

-- The ink a sheet is drawn with: forbidden seals in blood; deeper, more often a dyed ink
local DYED_BY_TIER = { { 2, "azure" }, { 2, "oil" }, { 3, "swift" }, { 4, "gold" }, { 5, "clear" }, { 6, "blood" } }
function sheet_pick_ink( row, tier )
	if row.forbidden then return "blood" end
	if Random( 1, 100 ) > 4 + 4 * tier then return "ink" end
	local inks = {}
	for _, d in ipairs( DYED_BY_TIER ) do
		if tier >= d[1] then inks[#inks + 1] = d[2] end
	end
	if #inks == 0 then return "ink" end
	return inks[Random( 1, #inks )]
end

local INK_NAMES = { ink = nil, blood = "Blood", azure = "Azure", clear = "Clear", gold = "Golden", oil = "Oil", swift = "Swift" }

-- what book a sheet's seal needs, in words
local BOOK_WORDS = { quire = "Small enough for the Palm Quire", book = "Pasted into a book", tome = "Only a Great Tome's page holds it" }

-- A sheet with the seal 'row' in 'ink' at x, y, hovering; returns the entity
function sheet_spawn( x, y, row, ink )
	local e = EntityLoad( SHEET_ENTITY, x, y )
	local name = "Seal Sheet: " .. row.name
	local ink_text = INK_NAMES[ink] and ( ", " .. INK_NAMES[ink] .. " Ink" ) or ""
	local description = ( row.forbidden and "Forbidden Magic. " or "" ) .. "Tier " .. sheet_tier_name( row.tier ) .. ink_text
		.. ". " .. ( BOOK_WORDS[row.book or "book"] or BOOK_WORDS.book ) .. ": the seal can be cast and studied."
	local pic = SHEET_PICTURES[row.book or "book"] or SHEET_PICTURES.book
	EntityAddComponent2( e, "SpriteComponent", { image_file = sheet_gfx( row.key ), offset_x = pic.w / 2, offset_y = pic.h / 2,
		update_transform = true, update_transform_rotation = false, z_index = 20 } )
	EntityAddComponent2( e, "UIInfoComponent", { name = name } )
	EntityAddComponent2( e, "ItemComponent", { item_name = name, ui_description = description, ui_display_description_on_pick_up_hint = true,
		play_spinning_animation = false, play_hover_animation = false, play_pick_sound = true, stats_count_as_item_pick_up = false } )
	EntityAddComponent2( e, "SpriteOffsetAnimatorComponent", { sprite_id = -1, x_amount = 0, x_phase = 0, x_phase_offset = 0,
		x_speed = 0, y_amount = 2, y_speed = 2.5 } )
	for field, value in pairs( { witch_sheet_key = row.key, witch_sheet_ink = ink or "ink", witch_sheet_name = row.name } ) do
		EntityAddComponent2( e, "VariableStorageComponent", { name = field, value_string = value } )
	end
	return e
end

-- A sheet found at x, y (a flask's place, beside a chest): its tier from the depth
function sheet_spawn_found( x, y, forbidden_place )
	SetRandomSeed( x + 91, y - 57 )
	forbidden_place = forbidden_place or sheet_forbidden_place( x, y )
	local tier = forbidden_place and SHEET_TIERS or sheet_tier_at( x, y )
	local row = sheet_pick( tier, forbidden_place )
	if not row then return nil end
	return sheet_spawn( x, y, row, sheet_pick_ink( row, tier ) )
end

-- An opened chest may hold a sheet too
function sheet_from_chest( x, y )
	SetRandomSeed( x + 311, y - 71 )
	local hell = sheet_forbidden_place( x, y )
	if Random( 1, 100 ) > ( hell and HELL_CHANCE or FOUND_CHANCE ) then return nil end
	return sheet_spawn_found( x + Random( -8, 8 ), y - 12, hell )
end

function sheet_price( row, ink )
	local price = PRICES[row.tier] or PRICES[#PRICES]
	if ink and ink ~= "ink" then price = price * 1.3 end
	return math.floor( price / 10 ) * 10
end

-- A thing of the mod for sale in the Holy Mountain at x, y, where the shop's spell would stand (temple_append.lua), over
-- the shelf at 'shelf': a sheet of the tier of the stretch above or a flask of ink, dyed now and then from tier III on;
-- 'cheap' - on sale at half price, as the shop marks it. Uses the current random seed.
-- The shop's cards fall onto the shelf and lie with their middle 12 over it and the price 28 over it; the sheet hovers
-- as high, the flask falls onto the shelf like them (its middle 4 over it).
local SHOP_FLASKS = { "azure", "oil", "swift", "gold" }
function sheet_shop_item( x, y, cheap, shelf )
	shelf = shelf or ( y + 11 )
	local tier = sheet_tier_at( x, y )
	local e, price, middle
	if Random( 1, 100 ) <= SHOP_INK_CHANCE then
		local ink = "ink"
		if tier >= 3 and Random( 1, 100 ) <= SHOP_DYED_CHANCE then ink = SHOP_FLASKS[Random( 1, #SHOP_FLASKS )] end
		middle = shelf - 4
		e = EntityLoad( ink_flask_entity( ink ), x, middle - 1 )
		price = ink == "ink" and ( 100 + 20 * math.max( 0, math.floor( y / 512 ) ) ) or ( 120 + 40 * tier )
	else
		local row = sheet_pick( tier, false )
		if not row then return nil end
		local ink = sheet_pick_ink( row, tier )
		middle = shelf - 12
		e = sheet_spawn( x, middle, row, ink )
		price = sheet_price( row, ink )
	end
	if cheap then
		price = price * 0.5
		EntityLoad( "data/entities/misc/sale_indicator.xml", x, y )
	end
	shop_for_sale( e, math.floor( price / 10 ) * 10, middle - ( shelf - 28 ) )
	return e
end
