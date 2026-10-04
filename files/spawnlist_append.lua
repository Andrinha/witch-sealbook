-- Appended to data/scripts/item_spawnlists.lua: a few of the places where flasks lie hold a sheet with a seal instead
-- (sheets.lua), of the tier of the depth
local SHEET_SHARE = 0.07 -- of the places of a list

local function witch_notebook_add_sheets( list )
	if not list or not list.spawns then return end
	local from = ( list.rnd_max or 100 ) + 1
	local extra = math.max( 1, math.floor( ( list.rnd_max or 100 ) * SHEET_SHARE + 0.5 ) )
	list.rnd_max = from + extra - 1
	table.insert( list.spawns, 1, {
		value_min = from,
		value_max = from + extra - 1,
		load_entity_func = function( data, x, y )
			dofile_once( "mods/witch_notebook/files/sheets.lua" )
			sheet_spawn_found( x, y - 8 )
		end,
	} )
end

witch_notebook_add_sheets( spawnlists.potion_spawnlist )
witch_notebook_add_sheets( spawnlists.potion_spawnlist_liquidcave )
