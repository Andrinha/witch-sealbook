-- The mod's things for sale in the Holy Mountain (sheets.lua, books.lua): the price tag and the purchase, as
-- generate_shop_item.lua makes them for the shop's cards.

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
