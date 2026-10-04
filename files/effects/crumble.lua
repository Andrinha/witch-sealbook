-- A piece of the seals' solid magic (entities/solid/*.xml) ends: it scatters into dust and a little of its material
dofile_once( "mods/witch_notebook/files/fx.lua" )

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local material, radius = "sand", 4
for _, comp in ipairs( EntityGetComponentIncludingDisabled( e, "VariableStorageComponent" ) or {} ) do
	if ComponentGetValue2( comp, "name" ) == "crumble" then
		material = ComponentGetValue2( comp, "value_string" )
		radius = math.max( 2, ComponentGetValue2( comp, "value_int" ) )
	end
end
SetRandomSeed( x + GameGetFrameNum(), y )
for i = 1, radius * 3 do
	local px, py = x + Random( -radius, radius ), y + Random( -radius, radius ) * 0.5
	GameCreateCosmeticParticle( material, px, py, 1, Random( -20, 20 ), Random( -30, 5 ), 0, 0.5, 1.2, true, false, true, true, 0, 60 )
end
if material == "sand" or material == "snow" or material == "water" then
	for i = 1, radius do
		GameCreateParticle( material, x + Random( -radius, radius ), y + Random( -2, 2 ), 1, 0, 0, false, false, true )
	end
end
