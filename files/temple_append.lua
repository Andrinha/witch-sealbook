-- Appended to data/scripts/biomes/temple_altar.lua: now and then the Holy Mountain's shop sells a sheet with a seal or
-- a flask of witch ink (sheets.lua sheet_shop_item) in place of one of its spells, and now and then a book the witch
-- doesn't have yet (books.lua book_for_shop) in place of a spell or a wand - the second thing of the lower row

dofile_once( "mods/witch_notebook/files/sheets.lua" )

-- the shop's spells stand in two rows: over the shelf of the altar (11 below the first row) and over the ledges
-- of shop_second_row.png, 30 higher (8 below them)
local witch_notebook_shop_y, witch_notebook_book, witch_notebook_place
local witch_notebook_spawn_all_shopitems = spawn_all_shopitems
function spawn_all_shopitems( x, y )
	witch_notebook_shop_y = y
	SetRandomSeed( x + 71, y - 1297 )
	witch_notebook_book = book_for_shop( sheet_tier_at( x, y ) )
	witch_notebook_place = 0
	witch_notebook_spawn_all_shopitems( x, y )
	witch_notebook_shop_y, witch_notebook_book = nil, nil
end

-- the mountain's book, in the lower row's second place
local function witch_notebook_book_here( x, y, cheap_item )
	if not witch_notebook_book or ( witch_notebook_shop_y and y < witch_notebook_shop_y ) then return false end
	witch_notebook_place = witch_notebook_place + 1
	if witch_notebook_place ~= 2 then return false end
	book_shop_item( witch_notebook_book, x, y, sheet_tier_at( x, y ), cheap_item, y + 11 )
	return true
end

-- generate_shop_item.lua, dofile'd by temple_altar.lua; it seeds the random itself, item by item
local witch_notebook_generate_shop_item = generate_shop_item
function generate_shop_item( x, y, cheap_item, biomeid_, is_stealable )
	if witch_notebook_book_here( x, y, cheap_item ) then return end
	SetRandomSeed( x + 523, y - 311 )
	if Random( 1, 100 ) <= SHOP_REPLACE_CHANCE then
		local second_row = witch_notebook_shop_y and y < witch_notebook_shop_y
		if sheet_shop_item( x, y, cheap_item, y + ( second_row and 8 or 11 ) ) then return end
	end
	return witch_notebook_generate_shop_item( x, y, cheap_item, biomeid_, is_stealable )
end

local witch_notebook_generate_shop_wand = generate_shop_wand
function generate_shop_wand( x, y, cheap_item, biomeid_ )
	if witch_notebook_book_here( x, y, cheap_item ) then return end
	return witch_notebook_generate_shop_wand( x, y, cheap_item, biomeid_ )
end
