-- Solidification (cast.lua): where the projectile ends, its element sets solid - a foothold that lasts a while
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local element = hit_var( e, "witch_solid" ) or "earth"
local PIECE = { water = "ice_block", ice = "ice_block", storm = "ice_block", frost = "ice_block", crystal = "crystal_block",
	sand = "sand_block", sandstorm = "sand_block", mud = "sand_block", light = "light_plank", beam = "light_plank" }
solid_piece( PIECE[element] or "stone_block", x, y, 60 * 20 )
fx_burst( x, y, effect_color( element, 0.5 ), 12, 40, 0.4 )
