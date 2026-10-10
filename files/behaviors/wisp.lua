-- Wisp (resonances.lua): the unburning flame hunting through the walls bewilders whoever it touches - once each, for
-- "witch_wisp_confuse" frames - and they shy away from it
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local shooter = hit_shooter( e )
local touched = {}
for id in effect_text( hit_var( e, "witch_wisp_touched" ) ):gmatch( "%d+" ) do touched[tonumber( id )] = true end
local any = false
for _, id in ipairs( creatures_in( x, y, 10, shooter ) ) do
	if not touched[id] then
		touched[id], any = true, true
		give_effect( id, MISC .. "effect_confusion.xml", hit_var( e, "witch_wisp_confuse" ) or 120 )
		push_from( id, x, y, 90 )
		fx_burst( x, y, effect_color( "phantasm", 0.7 ), 10, 30, 0.4 )
	end
end
if any then
	local ids = {}
	for id in pairs( touched ) do ids[#ids + 1] = id end
	effect_set( e, "witch_wisp_touched", table.concat( ids, "," ) )
end
