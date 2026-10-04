-- The Sign of the Orb (cast.lua, the Water Orb): the sphere holds the liquid it gathers - seen as a ball of it swirling
-- inside; when the sphere ends, it spills.
dofile_once( "mods/witch_notebook/files/fx.lua" )

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local inv = EntityGetFirstComponent( e, "MaterialInventoryComponent" )
local counts = inv and ComponentGetValue2( inv, "count_per_material_type" ) or {}
local total, main, most = 0, nil, 0
for i, n in pairs( counts ) do
	total = total + n
	if n > most then main, most = i - 1, n end
end
local r = 4 + math.min( 10, math.sqrt( total ) * 0.35 )
local t = GameGetFrameNum() * 0.1
-- the sphere's thin skin, and what it holds swirling inside
for k = 0, 9 do
	local a = t + k / 10 * 2 * math.pi
	GameCreateCosmeticParticle( FX_SPARK, x + math.cos( a ) * r, y + math.sin( a ) * r, 1, 0, 0,
		color_abgr_merge( 170, 220, 255, 110 ), 0.1, 0.1, true, false, false, false, 0, 0 )
end
if main and total > 0 then
	local material = CellFactory_GetName( main )
	for k = 1, math.min( 8, 1 + math.floor( total / 40 ) ) do
		local a = -t * 1.5 + k * 0.8
		local rr = r * 0.7 * ( k % 3 + 1 ) / 3
		GameCreateCosmeticParticle( material, x + math.cos( a ) * rr, y + math.sin( a ) * rr, 1, 0, 0, 0, 0.08, 0.1, true, false, false, false, 0, 0 )
	end
end
