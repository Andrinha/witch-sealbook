-- LuaComponent of a flask or a book standing for sale (entities/shop_stand.xml, shop.lua shop_stand): bought, the stand
-- is gone and the thing itself is in the witch's hands - a flask full of its ink, a book that becomes theirs.
dofile_once( "mods/witch_notebook/files/ink.lua" )
dofile_once( "mods/witch_notebook/files/books.lua" )

local function var( entity, name )
	for _, comp in ipairs( EntityGetComponentIncludingDisabled( entity, "VariableStorageComponent" ) or {} ) do
		if ComponentGetValue2( comp, "name" ) == name then return ComponentGetValue2( comp, "value_string" ) end
	end
end

function item_pickup( entity_item, entity_who_picked, item_name )
	local file, ink, book = var( entity_item, "witch_shop_file" ), var( entity_item, "witch_shop_ink" ), var( entity_item, "witch_shop_book" )
	EntityKill( entity_item )
	if not file or file == "" then return end
	local x, y = EntityGetTransform( entity_who_picked )
	local thing = EntityLoad( file, x, y - 4 )
	if ink and INK_BY_KEY[ink] then AddMaterialInventoryMaterial( thing, INK_BY_KEY[ink].material, INK_FLASK ) end
	GamePickUpInventoryItem( entity_who_picked, thing, false )
	if book and BOOKS[book] then book_first_pickup( book, entity_who_picked ) end
end
