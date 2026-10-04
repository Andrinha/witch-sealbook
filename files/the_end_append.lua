-- Appended to data/scripts/biomes/the_end.lua, the script of Hell and Heaven: the only places where sheets with the
-- forbidden seals lie (sheets.lua) - beside the chests and over the wand altars

local witch_notebook_spawn_chest = spawn_chest
function spawn_chest( x, y )
	witch_notebook_spawn_chest( x, y )
	dofile_once( "mods/witch_notebook/files/sheets.lua" )
	SetRandomSeed( x + 57, y - 311 )
	if Random( 1, 100 ) <= 50 then sheet_spawn_found( x + 16, y - 10, true ) end
end

local witch_notebook_spawn_items = spawn_items
function spawn_items( x, y )
	witch_notebook_spawn_items( x, y )
	dofile_once( "mods/witch_notebook/files/sheets.lua" )
	SetRandomSeed( x - 57, y + 311 )
	if Random( 1, 100 ) <= 25 then sheet_spawn_found( x, y - 30, true ) end
end
