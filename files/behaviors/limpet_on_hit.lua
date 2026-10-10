-- Limpet (resonances.lua): an Entwining shot swollen by Expansion sticks to whoever it hits - or where it ends - and
-- after a while bursts there in a wave of its element
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local target, x, y = hit_target( e, 16 )
local dx, dy = 0, 0
if target then
	local tx, ty = EntityGetTransform( target )
	dx, dy = x - tx, y - ty
end
local a = RESONANCE_AMOUNTS.limpet()
effect_spawn( "resonance", "limpet", x, y, { owner = hit_shooter( e ), target = target or 0, frames = a.frames, r = a.r,
	element = hit_var( e, "witch_limpet_element" ) or "light", power = hit_var( e, "witch_limpet_power" ) or 1, dx = dx, dy = dy } )
