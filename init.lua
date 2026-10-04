dofile_once( "data/scripts/lib/utilities.lua" )
dofile_once( "mods/witch_notebook/files/templates.lua" )
dofile_once( "mods/witch_notebook/files/dictionary.lua" )
dofile_once( "mods/witch_notebook/files/sigils.lua" )
dofile_once( "mods/witch_notebook/files/recognizer.lua" )
dofile_once( "mods/witch_notebook/files/grimoire.lua" )
dofile_once( "mods/witch_notebook/files/seal.lua" )
dofile_once( "mods/witch_notebook/files/seal_canon.lua" )
dofile_once( "mods/witch_notebook/files/seal_spell.lua" )
dofile_once( "mods/witch_notebook/files/books.lua" )
dofile_once( "mods/witch_notebook/files/cast.lua" )
dofile_once( "mods/witch_notebook/files/carriers.lua" )
dofile_once( "mods/witch_notebook/files/ink.lua" )
dofile_once( "mods/witch_notebook/files/sheets.lua" )
dofile_once( "mods/witch_notebook/files/book_gfx.lua" )
dofile_once( "mods/witch_notebook/files/book_draw.lua" )
dofile_once( "mods/witch_notebook/files/page_turn.lua" )
dofile_once( "mods/witch_notebook/files/awaken.lua" )
dofile_once( "mods/witch_notebook/files/strokes.lua" )
dofile_once( "mods/witch_notebook/files/book_store.lua" )
dofile_once( "mods/witch_notebook/files/book_mouse.lua" )
dofile_once( "mods/witch_notebook/files/book_pages.lua" )
dofile_once( "mods/witch_notebook/files/quire_strap.lua" )
dofile_once( "mods/witch_notebook/files/quire_strap_world.lua" )
dofile_once( "mods/witch_notebook/files/spell_notes.lua" )
dofile_once( "mods/witch_notebook/files/test_book.lua" )
dofile_once( "mods/witch_notebook/files/notebook.lua" )
dofile_once( "mods/witch_notebook/files/effects/profiler.lua" )

ModLuaFileAppend( "data/scripts/items/potion.lua", "mods/witch_notebook/files/potion_append.lua" )
-- the Holy Mountain's shop: sheets, flasks of ink and now and then a book (sheets.lua, books.lua)
ModLuaFileAppend( "data/scripts/biomes/temple_altar.lua", "mods/witch_notebook/files/temple_append.lua" )
-- sheets with seals: where flasks lie, in chests, in Hell and Heaven (sheets.lua)
ModLuaFileAppend( "data/scripts/item_spawnlists.lua", "mods/witch_notebook/files/spawnlist_append.lua" )
ModLuaFileAppend( "data/scripts/items/chest_random.lua", "mods/witch_notebook/files/chest_append.lua" )
ModLuaFileAppend( "data/scripts/biomes/the_end.lua", "mods/witch_notebook/files/the_end_append.lua" )
ModMaterialsFileAdd( "mods/witch_notebook/files/materials.xml" )
books_patch_bosses() -- the first boss killed leaves a Great Tome (books.lua)

-- In-memory images (the books' pages, legend) and virtual files can only be made during mod init
sigils_create_images()
book_gfx_create() -- the books' paper, covers, ribbons and bottles (book_gfx.lua)
sheets_create()   -- the seals ranked into tiers for the sheets found in the world, and the sheets' pictures
ink_create_flasks() -- flasks of every dyed ink
carriers_create() -- the seal projectiles of every element

function OnPlayerSpawned( player_entity )
	notebook_on_player_spawned( player_entity )
	ink_on_player_spawned( player_entity )
	local prepare = EntityGetWithTag( "witch_fluid_prepare" )[1]
	if not prepare then
		local x, y = EntityGetTransform( player_entity )
		prepare = effect_spawn( "prepare", "fluid", x, y, {} )
		EntityAddTag( prepare, "witch_fluid_prepare" )
	else
		-- A loaded game gets a fresh script VM but can reuse its disabled pool.
		local component = EntityGetFirstComponentIncludingDisabled( prepare, "LuaComponent" )
		if component then EntitySetComponentIsEnabled( prepare, component, true ) end
	end
end

function OnWorldPostUpdate()
	notebook_update()
	quire_straps_update() -- the Palm Quire's strap hanging under it in the world (quire_strap_world.lua)
	EffectProfiler.world_update()
end

function OnPausedChanged( is_paused, is_inventory_pause )
	EffectProfiler.pause()
	if is_paused then notebook_on_pause() end
end
