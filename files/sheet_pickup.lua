-- LuaComponent of a sheet with a seal (entities/sheet.xml, sheets.lua): picked up, the sheet goes to the witch's books -
-- the next frame notebook.lua pastes it into a book that holds its seal (or keeps it until the witch has one) and says
-- where it went - and is gone.
dofile_once( "data/scripts/lib/utilities.lua" )
dofile_once( "mods/witch_notebook/files/sheets.lua" )

local function var( entity, name )
	for _, comp in ipairs( EntityGetComponentIncludingDisabled( entity, "VariableStorageComponent" ) or {} ) do
		if ComponentGetValue2( comp, "name" ) == name then return ComponentGetValue2( comp, "value_string" ) end
	end
end

function item_pickup( entity_item, entity_who_picked, item_name )
	local key = var( entity_item, "witch_sheet_key" )
	if key and key ~= "" then
		GlobalsSetValue( SHEET_PENDING_VAR, GlobalsGetValue( SHEET_PENDING_VAR, "" ) .. key .. ":" .. ( var( entity_item, "witch_sheet_ink" ) or "ink" ) .. ";" )
		local x, y = EntityGetTransform( entity_item )
		for i = 1, 16 do
			local a = i / 16 * 2 * math.pi
			GameCreateCosmeticParticle( "spark_white_bright", x, y, 1, math.cos( a ) * 30, math.sin( a ) * 30 - 10,
				color_abgr_merge( 255, 230, 170, 255 ), 0.5, 0.7, true, true, false, false, 0, 0 )
		end
	end
	EntityKill( entity_item )
end
