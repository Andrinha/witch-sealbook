-- The mod's things for sale in the Holy Mountain (sheets.lua, books.lua): the price tag and the purchase, as
-- generate_shop_item.lua makes them for the shop's cards.

-- A flask or a book would roll, break or be kicked out of the shop: on the shelf it stands as its picture, with no body
-- and nothing to break, and bought it becomes the thing itself in the witch's hands (shop_stand_pickup.lua). 'file': the
-- thing's entity; 'image': its picture, 'w' by 'h', with its middle at x, y
function shop_stand( file, x, y, image, w, h, name, description )
	local e = EntityLoad( "mods/witch_notebook/files/entities/shop_stand.xml", x, y )
	EntityAddComponent2( e, "SpriteComponent", { image_file = image, offset_x = math.floor( w / 2 ), offset_y = math.floor( h / 2 ),
		update_transform = true, update_transform_rotation = false, z_index = 20 } )
	EntityAddComponent2( e, "HitboxComponent", { aabb_min_x = -w / 2 - 1, aabb_max_x = w / 2 + 1, aabb_min_y = -h / 2 - 1,
		aabb_max_y = h / 2 + 1, is_item = true, is_enemy = false, is_player = false } )
	EntityAddComponent2( e, "UIInfoComponent", { name = name } )
	EntityAddComponent2( e, "ItemComponent", { item_name = name, ui_description = description, ui_display_description_on_pick_up_hint = true,
		play_spinning_animation = false, play_hover_animation = false, play_pick_sound = true, stats_count_as_item_pick_up = false } )
	shop_stand_set( e, "witch_shop_file", file )
	return e
end
function shop_stand_set( e, name, value )
	EntityAddComponent2( e, "VariableStorageComponent", { name = name, value_string = value } )
end

-- 'e' costs 'price'; its price tag hangs 'offset_y' over it
function shop_for_sale( e, price, offset_y )
	local text = tostring( price )
	local width = 0
	for i = 1, #text do width = width + ( text:sub( i, i ) == "1" and 3 or 6 ) end
	EntityAddComponent2( e, "SpriteComponent", { _tags = "shop_cost,enabled_in_world", image_file = "data/fonts/font_pixel_white.xml",
		is_text_sprite = true, offset_x = width * 0.5 - 0.5, offset_y = offset_y or 17, update_transform = true,
		update_transform_rotation = false, text = text, z_index = -1 } )
	EntityAddComponent2( e, "ItemCostComponent", { _tags = "shop_cost,enabled_in_world", cost = price, stealable = true } )
	EntityAddComponent2( e, "LuaComponent", { script_item_picked_up = "data/scripts/items/shop_effect.lua" } )
end
