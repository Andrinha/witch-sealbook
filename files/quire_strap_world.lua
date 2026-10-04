-- The Palm Quire's strap in the world (entities/quire_strap.xml, two ends): hanging from the bottom of the book lying
-- about or held in hand, gone while it is in the inventory. init.lua's OnWorldPostUpdate runs it every frame for every
-- quire - not a LuaComponent of the book's, which the game doesn't run in every state of an item. The ends are not the
-- book's children - a book's children would be taken for the spells in its deck - but kept by their ids in the book;
-- each one knows its book, so one left over (the book gone, or a stale id after loading) is never moved
-- (quire_strap_check.lua kills it).

local STRAP_FILE = "mods/witch_notebook/files/entities/quire_strap.xml"
local STRAPS_VAR = "witch_quire_straps"
local ENDS = { -2, 2 }       -- across the book's bottom, from its middle
local BOTTOM_HAND = 4        -- the book's bottom below its position: held (the sprite's offset 4, 7 of 9 x 12)
local BOTTOM_WORLD = 5.5     -- ... lying about (its physics shape centered)

-- 'held', 'world' or nil (in the inventory)
function quire_strap_state( book )
	local root = EntityGetRootEntity( book )
	if root == book then return "world" end
	local inv = EntityGetFirstComponentIncludingDisabled( root, "Inventory2Component" )
	if inv and ComponentGetValue2( inv, "mActiveItem" ) == book then return "held" end
end

local function store_of( book, make )
	for _, c in ipairs( EntityGetComponentIncludingDisabled( book, "VariableStorageComponent" ) or {} ) do
		if ComponentGetValue2( c, "name" ) == STRAPS_VAR then return c end
	end
	if make then return EntityAddComponent2( book, "VariableStorageComponent", { name = STRAPS_VAR, value_string = "" } ) end
end

-- whether 'strap' hangs from 'book' (quire_strap_check.lua)
function quire_strap_kept( book, strap )
	local store = EntityGetIsAlive( book ) and store_of( book )
	return store and ( "," .. ComponentGetValue2( store, "value_string" ) .. "," ):find( "," .. strap .. ",", 1, true ) ~= nil
end

local function update_book( book )
	local state = quire_strap_state( book )
	local store = store_of( book, state ~= nil )
	if not store then return end
	-- the ends hanging from this book now (ids that still are its straps)
	local ends = {}
	for id in string.gmatch( ComponentGetValue2( store, "value_string" ), "%d+" ) do
		local e = tonumber( id )
		if EntityGetIsAlive( e ) and EntityGetName( e ) == "witch_quire_strap" then
			local v = EntityGetFirstComponentIncludingDisabled( e, "VariableStorageComponent" )
			if v and ComponentGetValue2( v, "value_int" ) == book then ends[#ends + 1] = e end
		end
	end
	if not state then
		for _, e in ipairs( ends ) do EntityKill( e ) end
		if ComponentGetValue2( store, "value_string" ) ~= "" then ComponentSetValue2( store, "value_string", "" ) end
		return
	end

	local x, y, rot, sx, sy = EntityGetTransform( book )
	rot, sx, sy = rot or 0, sx or 1, sy or 1
	local bottom = state == "held" and BOTTOM_HAND or BOTTOM_WORLD
	local c, s = math.cos( rot ), math.sin( rot )
	local function anchor( across )
		local ox, oy = across * sx, bottom * sy
		return x + c * ox - s * oy, y + s * ox + c * oy
	end

	if #ends ~= #ENDS then
		for _, e in ipairs( ends ) do EntityKill( e ) end
		ends = {}
		local ids = {}
		for i, across in ipairs( ENDS ) do
			local ax, ay = anchor( across )
			local e = EntityLoad( STRAP_FILE, ax, ay )
			local v = EntityGetFirstComponentIncludingDisabled( e, "VariableStorageComponent" )
			if v then ComponentSetValue2( v, "value_int", book ) end
			ends[i], ids[i] = e, tostring( e )
		end
		ComponentSetValue2( store, "value_string", table.concat( ids, "," ) )
	end
	for i, e in ipairs( ends ) do
		local ax, ay = anchor( ENDS[i] )
		EntitySetTransform( e, ax, ay )
	end
end

-- every frame: the straps of every Palm Quire there is
function quire_straps_update()
	for _, book in ipairs( EntityGetWithTag( BOOK_TAG ) or {} ) do
		if book_key_of( book ) == "quire" then update_book( book ) end
	end
end
