-- Drill (resonances.lua): the shot spins as it bores through rock - sparks whirl round its tip
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local t = GameGetFrameNum() * 0.7
for k = 0, 2 do
	local a = t + k * 2.09
	fx_dot( x + math.cos( a ) * 5, y + math.sin( a ) * 5, effect_color( "earth", 0.6 ), -math.sin( a ) * 30, math.cos( a ) * 30, 0.15 )
end
