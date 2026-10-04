-- Appended to data/scripts/items/potion.lua: some random flasks in the world hold witch ink; deeper down some of those
-- hold an ink already dyed (ink.lua INKS)

local WITCH_INK_CHANCE = 10 -- percent
local DYED_CHANCE = 25      -- percent of the ink flasks below the Coal Pits
local DYED_FROM = 3072      -- depth
local DYED = { "witch_ink_azure", "witch_ink_oil", "witch_ink_swift", "witch_ink_gold", "witch_ink_blood", "witch_ink_clear" }

local witch_notebook_potion_init = init
function init( entity_id )
	witch_notebook_potion_init( entity_id )

	-- flasks with a fixed material keep it
	for _, comp in ipairs( EntityGetComponent( entity_id, "VariableStorageComponent" ) or {} ) do
		if ComponentGetValue2( comp, "name" ) == "potion_material" then return end
	end

	local x, y = EntityGetTransform( entity_id )
	SetRandomSeed( x + 1733, y - 919 )
	if Random( 1, 100 ) <= WITCH_INK_CHANCE then
		local capacity = tonumber( GlobalsGetValue( "EXTRA_POTION_CAPACITY_LEVEL", "1000" ) ) or 1000
		local material = "witch_ink"
		if y >= DYED_FROM and Random( 1, 100 ) <= DYED_CHANCE then material = DYED[Random( 1, #DYED )] end
		RemoveMaterialInventoryMaterial( entity_id )
		AddMaterialInventoryMaterial( entity_id, material, capacity )
	end
end
