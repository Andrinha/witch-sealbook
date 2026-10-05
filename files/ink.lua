-- Witch ink: the notebook draws with conjuring ink from the flasks in the quick inventory. Mixed in a flask with a dye
-- - blood, concentrated mana, invisiblium, gold, oil or acceleratium - conjuring ink turns into an ink of its own
-- (materials.xml; the wiki's Magical Dyes: blood makes a spell stronger and wilder, azuremoon flowers make it last,
-- blushing bride scales hide it, golden blaze wyrm scales make it glow, roaming scallop shells keep it from running).
-- The book draws with the ink chosen in it; a seal takes on the inks it is drawn with, each by its share of the
-- line (cast.lua applies them). Every stroke spends ink by its length. Flasks of ink lie around the world
-- (potion_append.lua) and now and then sold in the Holy Mountains (temple_append.lua); a new run starts with one.

INK_MATERIAL = "witch_ink"
INK_FLASK = 1000     -- cells in a full flask
INK_PER_UNIT = 0.1   -- cells spent per gui unit of line: a typical sigil costs about 65
INK_VAR = "witch_notebook.ink" -- the ink the book draws with
local STARTING_FLAG = "witch_notebook_starting_ink"
local FLASK_ENTITY = "mods/witch_notebook/files/entities/potion_ink.xml"

-- key, material, name, color on paper (0..1), the liquid's color (0..255), the dye it is mixed with, what it does to a
-- seal ('text'; 'hint': the same in short, for the book's page of inks). Effects (cast.lua ink_apply), for a seal drawn with the ink only (a share of it does its share):
--   force: added force, and 'power' times the power; 'wild': how much that varies from cast to cast;
--   'backlash': chance (percent) that the ink boils over and hurts the caster; lifetime: added lifetime;
--   range: added range, 'haste': share of the delay between casts saved; hidden, glow, waterproof - see cast.lua
INKS = {
	{ key = "ink", material = "witch_ink", name = "Conjuring Ink", short = "conjuring", color = { 0.12, 0.1, 0.2 },
		liquid = { 58, 42, 138 }, text = "Plain ink for seals: flasks lie around the world and are sold in the Holy Mountains." },
	{ key = "blood", material = "witch_ink_blood", name = "Blood Ink", short = "blood", color = { 0.52, 0.05, 0.12 },
		liquid = { 150, 18, 46 }, dye = "blood", force = 1.2, power = 0.6, wild = 0.5, backlash = 6,
		hint = "twice the power, but it jumps; may hurt the witch",
		text = "The seal is twice as strong and big, but unpredictable: its power jumps, and the ink may boil and hurt the witch." },
	{ key = "azure", material = "witch_ink_azure", name = "Azure Ink", short = "azure", color = { 0.1, 0.36, 0.78 },
		liquid = { 40, 130, 235 }, dye = "concentrated mana", lifetime = 1.4,
		hint = "the spell lasts twice as long",
		text = "The spell lasts twice as long: fire burns, shields stand, sculptures live." },
	{ key = "clear", material = "witch_ink_clear", name = "Clear Ink", short = "clear", color = { 0.42, 0.52, 0.68 },
		liquid = { 170, 200, 235 }, alpha = 0.4, dye = "invisiblium", hidden = true,
		hint = "the seal is invisible, the Knights Moralis are blind to it",
		text = "The seal is invisible: no flash, projectiles barely show, the Knights Moralis do not see forbidden magic." },
	{ key = "gold", material = "witch_ink_gold", name = "Golden Ink", short = "golden", color = { 0.64, 0.46, 0.06 },
		liquid = { 235, 190, 60 }, dye = "gold", glow = true,
		hint = "the seal and its magic glow in the dark",
		text = "Glows in the dark: the seal and its magic light up everything around." },
	{ key = "oil", material = "witch_ink_oil", name = "Oil Ink", short = "oil", color = { 0.1, 0.24, 0.2 },
		liquid = { 40, 90, 80 }, dye = "oil", waterproof = true,
		hint = "does not run, even if the witch is wet",
		text = "Does not run: a wet witch casts at full strength, water does not spoil the ink in the flask." },
	{ key = "swift", material = "witch_ink_swift", name = "Swift Ink", short = "swift", color = { 0.08, 0.46, 0.3 },
		liquid = { 90, 220, 150 }, dye = "acceleratium", range = 1, haste = 0.45,
		hint = "magic flies faster and farther, the book casts more often",
		text = "Magic flies faster and farther, and the book casts more often." },
}
INK_BY_KEY, INK_BY_MATERIAL = {}, {}
for _, ink in ipairs( INKS ) do
	INK_BY_KEY[ink.key] = ink
	INK_BY_MATERIAL[ink.material] = ink
end

local function ink_containers( player )
	local list = {}
	for _, child in ipairs( EntityGetAllChildren( player ) or {} ) do
		if EntityGetName( child ) == "inventory_quick" then
			for _, item in ipairs( EntityGetAllChildren( child ) or {} ) do
				local comp = EntityGetFirstComponentIncludingDisabled( item, "MaterialInventoryComponent" )
				if comp then list[#list + 1] = { entity = item, comp = comp } end
			end
		end
	end
	return list
end

-- count_per_material_type is indexed by material id + 1
local material_ids = {}
local function material_index( material )
	local id = material_ids[material]
	if not id then
		id = CellFactory_GetType( material ) + 1
		material_ids[material] = id
	end
	return id
end
local function ink_in( container, material, counts )
	counts = counts or ComponentGetValue2( container.comp, "count_per_material_type" )
	return counts and math.floor( counts[material_index( material )] or 0 ) or 0
end

-- How much of every ink the flasks hold: { key = cells }
function ink_amounts( player )
	local out = {}
	for _, ink in ipairs( INKS ) do out[ink.key] = 0 end
	for _, container in ipairs( ink_containers( player ) ) do
		local counts = ComponentGetValue2( container.comp, "count_per_material_type" )
		for _, ink in ipairs( INKS ) do out[ink.key] = out[ink.key] + ink_in( container, ink.material, counts ) end
	end
	return out
end

-- Takes up to 'amount' cells of the ink 'key' (conjuring ink by default) from the flasks, returns how much was taken
function ink_spend( player, amount, key )
	local material = ( INK_BY_KEY[key or "ink"] or INKS[1] ).material
	local spent = 0
	for _, container in ipairs( ink_containers( player ) ) do
		if spent >= amount then break end
		local have = ink_in( container, material )
		if have > 0 then
			local take = math.min( have, amount - spent )
			if have - take > 0 then
				AddMaterialInventoryMaterial( container.entity, material, have - take ) -- sets the count
			else
				RemoveMaterialInventoryMaterial( container.entity, material )
			end
			spent = spent + take
		end
	end
	return spent
end

-- The dyed inks a seal is drawn with, as the book keeps them in its spell: "blood:0.62,gold:0.2" (the rest is conjuring
-- ink), from { key = share }
function ink_mix_data( shares )
	local parts = {}
	for _, ink in ipairs( INKS ) do
		local share = shares[ink.key] or 0
		if ink.key ~= "ink" and share >= 0.05 then parts[#parts + 1] = ink.key .. ":" .. math.floor( share * 100 + 0.5 ) / 100 end
	end
	return table.concat( parts, "," )
end

function ink_mix( data )
	local shares = {}
	for key, share in ( data or "" ):gmatch( "(%w+):([%d.]+)" ) do
		if INK_BY_KEY[key] then shares[key] = tonumber( share ) end
	end
	return shares
end

-- The dyed inks of a seal in words: "blood", "blood and golden"
function ink_mix_text( shares )
	local names = {}
	for _, ink in ipairs( INKS ) do
		if ink.key ~= "ink" and ( shares[ink.key] or 0 ) >= 0.05 then names[#names + 1] = ink.short end
	end
	if #names == 0 then return nil end
	if #names == 1 then return names[1] end
	return table.concat( names, ", ", 1, #names - 1 ) .. " and " .. names[#names]
end

-- A flask full of the ink 'key': the flask of conjuring ink with its material changed, made at mod init (ink_create_flasks)
function ink_flask_entity( key )
	if not key or key == "ink" then return FLASK_ENTITY end
	return "mods/witch_notebook/files/entities/potion_ink_" .. key .. ".xml"
end

-- the picture of a flask of the ink standing for sale in a shop (drawn at init in book_gfx.lua, shown by shop.lua)
INK_SHOP_W, INK_SHOP_H = 9, 11
function ink_shop_image( key ) return "mods/witch_notebook/files/gfx/shop_flask_" .. key .. ".png" end

function ink_create_flasks()
	local flask = ModTextFileGetContent( FLASK_ENTITY )
	for _, ink in ipairs( INKS ) do
		if ink.key ~= "ink" then
			ModTextFileSetContent( ink_flask_entity( ink.key ), ( flask:gsub( 'value_string="witch_ink"', 'value_string="' .. ink.material .. '"' ) ) )
		end
	end
end

function ink_on_player_spawned( player )
	if GameHasFlagRun( STARTING_FLAG ) then return end
	GameAddFlagRun( STARTING_FLAG )
	local x, y = EntityGetTransform( player )
	local flask = EntityLoad( FLASK_ENTITY, x, y )
	AddMaterialInventoryMaterial( flask, INK_MATERIAL, INK_FLASK )
	GamePickUpInventoryItem( player, flask, false )
end
