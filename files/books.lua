-- The witch's books of seals. In Witch Hat Atelier witches keep a Palm Quire - a round notepad strapped to the hand, for
-- small seals drawn discreetly and closed on the go - and notebooks for bigger seals; the grandest seals, like the
-- Petrification Coco copied from a picture book, need a great book. Here each is an item of its own with its own
-- pages, kept in the run's globals: notebook.lua opens and draws them, spellbook.lua casts from the one in hand.
--   Palm Quire - round pages, small seals only, casts quickly. Sold now and then in the Holy Mountains.
--   Spellbook  - every run starts with it.
--   Great Tome - big pages, holds every seal, casts slowly. The first boss the witch kills leaves one; the deeper
--                Holy Mountains sell one, rarely.
--   Test Book  - while the mod is made: every sigil with every sign, drawn in advance (test_book.lua), to try them out.
-- A wiki seal needs a book big enough for it (grimoire.lua 'book', from how intricate its drawing is: make_grimoire.py).

dofile_once( "mods/witch_notebook/files/shop.lua" )
dofile_once( "mods/witch_notebook/files/book_key.lua" )

BOOK_ENTITIES = "mods/witch_notebook/files/entities/"
BOOK_SPRITES = "mods/witch_notebook/files/gfx/"
BOOK_TAG = "witch_spellbook" -- every book item has it
BOOK_KEY_VAR = "witch_book"  -- the book item's VariableStorageComponent: which book it is
BOOK_OPEN_VAR = "witch_notebook.open_book"         -- the book opened last
BOOK_OPEN_REQUEST_VAR = "witch_notebook.open_request" -- a click with no active seal asks notebook.lua to open this book
SHEET_PENDING_VAR = "witch_notebook.pending_sheets"  -- sheets picked up, not yet pasted in: "key:ink;key:ink;"
SHEETS_WAITING_VAR = "witch_notebook.waiting_sheets" -- ... and those that no book of the witch holds yet
BOOKS_AT_SPAWN_SETTING = "witch_notebook.books_at_spawn"
TEST_BOOK_AT_SPAWN_SETTING = "witch_notebook.test_book_at_spawn"

-- key, name, size (a book holds the seals of its size and smaller), the item's entity, icon and picture in the world
-- (and its size), what it is ('about', and 'found': said when the witch first picks it up), the delay between casts
-- (frames); how it lies open (notebook.lua, book_gfx.lua): the page's size, round pages, from the hinge to a page, the
-- cover around the pages, strips a turning sheet is cut into, its images' prefix, frames a sheet takes to turn, pages
-- before the seals, how much smaller a sheet pasted in shows its seal
BOOKS = {
	quire = {
		key = "quire", name = "Palm Quire", size = 1,
		entity = BOOK_ENTITIES .. "palm_quire.xml", icon = BOOK_SPRITES .. "palm_quire_icon.png",
		image = BOOK_SPRITES .. "palm_quire.png", image_size = { 9, 12 },
		about = "A round notepad strapped to the hand: small seals only, but it casts quickly.",
		found = "Small seals, cast quickly - %s to open it",
		cast_delay = 18,
		page = 120, round = true, gap = 3, margin = 5, strips = 40, gfx = "quire_", flip_frames = 22, intro = 0,
		sheet_scale = 0.84,
	},
	book = {
		key = "book", name = "Spellbook", size = 2,
		entity = BOOK_ENTITIES .. "spellbook.xml", icon = BOOK_SPRITES .. "spellbook_icon.png",
		image = BOOK_SPRITES .. "spellbook.png", image_size = { 8, 10 },
		about = "The witch's sketchbook of seals.",
		found = "%s to open it and draw a seal",
		cast_delay = 30,
		page = 180, gap = 4, margin = 7, strips = 60, gfx = "", flip_frames = 28, intro = 14,
		sheet_scale = 0.86,
	},
	tome = {
		key = "tome", name = "Great Tome", size = 3,
		entity = BOOK_ENTITIES .. "great_tome.xml", icon = BOOK_SPRITES .. "great_tome_icon.png",
		image = BOOK_SPRITES .. "great_tome.png", image_size = { 12, 14 },
		about = "A copy from the Tower of Tomes: its pages hold the grandest seals. Heavy - it casts slowly.",
		found = "Its pages hold the grandest seals - %s to open it",
		cast_delay = 48,
		page = 240, gap = 6, margin = 11, strips = 60, gfx = "tome_", flip_frames = 36, intro = 2,
		sheet_scale = 0.88,
	},
	-- the Spellbook's pages, which test_book.lua fills; nothing is drawn in it and no sheet goes into it
	test = {
		key = "test", name = "Test Book", size = 3, test = true,
		entity = BOOK_ENTITIES .. "test_book.xml", icon = BOOK_SPRITES .. "test_book_icon.png",
		about = "Every sigil with every sign, drawn in advance - for testing.",
		found = "Every sigil with every sign - %s to open it, click a page to cast it",
		cast_delay = 12,
		page = 180, gap = 4, margin = 7, strips = 60, gfx = "", flip_frames = 28, intro = 0,
		sheet_scale = 0.86,
	},
}
BOOK_ORDER = { "quire", "book", "tome" } -- by size; the books of the game
BOOK_SHELF = { "quire", "book", "tome", "test" } -- the names over an open book

-- The wiki's seals the witch has learned - drawn, or found on a sheet: in the run's globals, "key,key"; every one is
-- also kept for good in a hidden mod setting, which the grimoire shows in later runs too (setting grimoire_remembers)
BOOK_LEARNED_VAR = "witch_notebook.learned"
BOOK_LEARNED_EVER_SETTING = "witch_notebook.learned_ever"
GRIMOIRE_REMEMBERS_SETTING = "witch_notebook.grimoire_remembers"

local function list_has( list, key )
	return ( "," .. ( list or "" ) .. "," ):find( "," .. key .. ",", 1, true ) ~= nil
end

local function list_add( list, key )
	list = list or ""
	return list == "" and key or ( list .. "," .. key )
end

-- learned in this run
function book_seal_learned( key )
	return list_has( GlobalsGetValue( BOOK_LEARNED_VAR, "" ), key )
end

-- the seals of earlier runs the grimoire remembers: "key,key", or "" with the setting off
function book_learned_before()
	if ModSettingGet( GRIMOIRE_REMEMBERS_SETTING ) == false then return "" end
	return tostring( ModSettingGet( BOOK_LEARNED_EVER_SETTING ) or "" )
end

-- in the grimoire: learned in this run, or in an earlier one it remembers
function book_seal_known( key )
	return book_seal_learned( key ) or list_has( book_learned_before(), key )
end

function book_learn_seal( key )
	if not key or key == "" then return end
	local ever = tostring( ModSettingGet( BOOK_LEARNED_EVER_SETTING ) or "" )
	if not list_has( ever, key ) then ModSettingSet( BOOK_LEARNED_EVER_SETTING, list_add( ever, key ) ) end
	if book_seal_learned( key ) then return end
	GlobalsSetValue( BOOK_LEARNED_VAR, list_add( GlobalsGetValue( BOOK_LEARNED_VAR, "" ), key ) )
end

-- The run's global 'name' of a book: the spellbook keeps the names it always had
function book_var( key, name )
	if key == "book" then return "witch_notebook." .. name end
	return "witch_notebook." .. key .. "." .. name
end

-- the smallest book a wiki seal fits in (grimoire.lua)
function seal_book( entry )
	return entry and BOOKS[entry.book or ""] and entry.book or "book"
end

-- whether the book 'key' holds a seal that needs the book 'need'
function book_holds( key, need )
	return ( BOOKS[key] or BOOKS.book ).size >= ( BOOKS[need] or BOOKS.book ).size
end

-- a book in words: "the Great Tome"
function book_named( key )
	return "the " .. ( BOOKS[key] or BOOKS.book ).name
end

-- which book an item is (its VariableStorageComponent BOOK_KEY_VAR; the spellbook of runs begun before there were
-- three has none)
function book_key_of( item )
	for _, comp in ipairs( EntityGetComponentIncludingDisabled( item, "VariableStorageComponent" ) or {} ) do
		if ComponentGetValue2( comp, "name" ) == BOOK_KEY_VAR then
			local key = ComponentGetValue2( comp, "value_string" )
			if BOOKS[key] then return key end
		end
	end
	return "book"
end

-- The books the witch has had in this run: sheets go into them, the shops and the bosses stop offering them
local function owned_flag( key ) return "witch_notebook_has_" .. key end
function book_owned( key )
	return GameHasFlagRun( owned_flag( key ) ) or ( key == "book" and GameHasFlagRun( "witch_notebook_spellbook" ) )
end
-- A book picked up (book_pickup.lua) or bought (shop_stand_pickup.lua): the first time in the run it becomes theirs
function book_first_pickup( key, who )
	if not EntityHasTag( who, "player_unit" ) or book_owned( key ) then return end
	book_set_owned( key )
	GamePrintImportant( BOOKS[key].name, string.format( BOOKS[key].found, book_open_key_hint() ) )
end
function book_set_owned( key )
	GameAddFlagRun( owned_flag( key ) )
	-- the sheets that waited for a book big enough are pasted in (notebook.lua)
	local waiting = GlobalsGetValue( SHEETS_WAITING_VAR, "" )
	if waiting ~= "" then
		GlobalsSetValue( SHEETS_WAITING_VAR, "" )
		GlobalsSetValue( SHEET_PENDING_VAR, GlobalsGetValue( SHEET_PENDING_VAR, "" ) .. waiting )
	end
end

---- where the books come from ----

-- The testing settings: the two books to be found, and the Test Book, each lie beside the witch when a run starts. Off
-- unless set: the game never stores a setting's default of false (mod_settings.lua), so a player who never touched one
-- reads nil. The Test Book has a flag of its own: it comes to a run begun before it was made, too.
function books_spawn_for_testing( player )
	local x, y = EntityGetTransform( player )
	if ModSettingGet( BOOKS_AT_SPAWN_SETTING ) == true and not GameHasFlagRun( "witch_notebook_books_at_spawn" ) then
		GameAddFlagRun( "witch_notebook_books_at_spawn" )
		EntityLoad( BOOKS.quire.entity, x - 18, y - 6 )
		EntityLoad( BOOKS.tome.entity, x + 18, y - 6 )
	end
	if ModSettingGet( TEST_BOOK_AT_SPAWN_SETTING ) == true and not GameHasFlagRun( "witch_notebook_test_book_at_spawn" ) then
		GameAddFlagRun( "witch_notebook_test_book_at_spawn" )
		EntityLoad( BOOKS.test.entity, x + 30, y - 6 )
	end
end

-- The bosses whose death may leave a Great Tome (the Kolmisilmä's ends the run anyway)
local BOSSES = {
	"data/entities/animals/boss_alchemist/boss_alchemist.xml", "data/entities/animals/boss_dragon.xml",
	"data/entities/animals/boss_ghost/boss_ghost.xml", "data/entities/animals/boss_limbs/boss_limbs.xml",
	"data/entities/animals/boss_meat/boss_meat.xml", "data/entities/animals/boss_pit/boss_pit.xml",
	"data/entities/animals/boss_robot/boss_robot.xml", "data/entities/animals/boss_sky/boss_sky.xml",
	"data/entities/animals/boss_spirit/islandspirit.xml", "data/entities/animals/boss_wizard/boss_wizard.xml",
}
local BOSS_DEATH = "mods/witch_notebook/files/boss_death.lua"

-- At mod init: every boss gets a death script (boss_death.lua) - into its root entity, after the others' changes
function books_patch_bosses()
	for _, file in ipairs( BOSSES ) do
		local xml = ModTextFileGetContent( file )
		local at
		for pos in ( xml or "" ):gmatch( "()</Entity>" ) do at = pos end
		if at and not xml:find( BOSS_DEATH, 1, true ) then
			ModTextFileSetContent( file, xml:sub( 1, at - 1 ) .. '\t<LuaComponent script_death="' .. BOSS_DEATH .. '" ></LuaComponent>\n'
				.. xml:sub( at ) )
		end
	end
end

-- A boss is dead: the first one the witch kills leaves a Great Tome, unless they have one
function book_boss_drop( boss )
	if book_owned( "tome" ) or GameHasFlagRun( "witch_notebook_tome_dropped" ) then return end
	GameAddFlagRun( "witch_notebook_tome_dropped" )
	local x, y = EntityGetTransform( boss )
	EntityLoad( BOOKS.tome.entity, x, y - 12 )
	EntityLoad( "data/entities/particles/image_emitters/magical_symbol_fast.xml", x, y - 12 )
	GamePrintImportant( "A Great Tome falls", "A copy from the Tower of Tomes: the grandest seals fit its pages" )
end

-- The Holy Mountain's shop (temple_append.lua): now and then a book the witch doesn't have yet, in place of a spell
-- or a wand. Which book this mountain sells, if any (uses the current random seed): the quire anywhere, the tome
-- from the fourth mountain on.
local SHOP = {
	quire = { chance = 30, from_tier = 1, price = function( tier ) return 150 + 40 * tier end },
	tome = { chance = 15, from_tier = 4, price = function( tier ) return 600 + 150 * tier end },
}
function book_for_shop( tier )
	for _, key in ipairs( { "tome", "quire" } ) do
		local shop = SHOP[key]
		if not book_owned( key ) and tier >= shop.from_tier and Random( 1, 100 ) <= shop.chance then return key end
	end
end

-- The book 'key' for sale at x, y, falling onto the shelf at 'shelf' ('cheap': on sale at half price); its price hangs
-- where the shop's cards have theirs, 28 over the shelf
function book_shop_item( key, x, y, tier, cheap, shelf )
	shelf = shelf or ( y + 11 )
	local def = BOOKS[key]
	local middle = shelf - math.ceil( def.image_size[2] / 2 )
	local e = shop_stand( def.entity, x, middle, def.image, def.image_size[1], def.image_size[2], def.name, def.about )
	shop_stand_set( e, "witch_shop_book", key )
	local price = SHOP[key].price( tier )
	if cheap then
		price = price * 0.5
		EntityLoad( "data/entities/misc/sale_indicator.xml", x, y )
	end
	shop_for_sale( e, math.floor( price / 10 ) * 10, middle - ( shelf - 28 ) )
	return e
end
