-- Flame Burst drawn round another element's sigil (cast.lua cast_burst_shot): where its shot ends - against whatever it
-- hits, or at the end of its flight - it bursts into a wave of its element (effects/nova.lua). "witch_burst_element",
-- "witch_burst_r", "witch_burst_damage": the wave's element, radius and damage.
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local element = hit_var( e, "witch_burst_element" )
if type( element ) ~= "string" or not DICTIONARY_ELEMENTS[element] then element = "light" end
effect_spawn( "nova", "nova", x, y, { owner = hit_shooter( e ), element = element, r = hit_var( e, "witch_burst_r" ) or 48,
	grow = 14, damage = hit_var( e, "witch_burst_damage" ) or 0.4, power = 1 } )
fx_flash( x, y, element, 90, 10 )
