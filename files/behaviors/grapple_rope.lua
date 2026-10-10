-- Grapple (resonances.lua): a ribbon runs from the caster's hand to the shot while it flies
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local shooter = hit_shooter( e )
if shooter == 0 or not EntityGetIsAlive( shooter ) then return end
local x, y = EntityGetTransform( e )
local sx, sy = EntityGetTransform( shooter )
fx_line( sx, sy - 4, x, y, effect_color( "light", 0.9, 0.8 ), 4, 0.04, 0 )
