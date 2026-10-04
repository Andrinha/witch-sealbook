-- Loading this mode through run.lua prepares the very VM used by real casts.
dofile_once( "mods/witch_notebook/files/effects/flame.lua" )
EFFECT_MODES.prepare = { fluid = FlameShot.prepare }
