-- Appended to data/scripts/items/chest_random.lua: an opened chest may hold a sheet with a seal too (sheets.lua); in
-- Hell and Heaven more often, and with a forbidden seal

local witch_notebook_drop_random_reward = drop_random_reward
function drop_random_reward( x, y, entity_id, rand_x, rand_y, set_rnd_ )
	local good = witch_notebook_drop_random_reward( x, y, entity_id, rand_x, rand_y, set_rnd_ )
	dofile_once( "mods/witch_notebook/files/sheets.lua" )
	sheet_from_chest( x, y )
	return good
end
