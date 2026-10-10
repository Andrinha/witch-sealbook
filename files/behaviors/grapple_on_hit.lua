-- Grapple (resonances.lua): where the shot ends, the ribbon takes hold - an enemy it struck is dragged to the caster,
-- a wall it struck pulls the caster to it. Ending in the air, it holds nothing.
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local shooter = hit_shooter( e )
if shooter == 0 or not EntityGetIsAlive( shooter ) then return end
local target, x, y = hit_target( e, 16 )
local a = RESONANCE_AMOUNTS.grapple()
if target then
	effect_spawn( "resonance", "tow", x, y, { owner = shooter, target = target, frames = a.frames, speed = a.tow } )
	return
end
-- something solid within a few pixels
for i = 0, 7 do
	local angle = i / 8 * 2 * math.pi
	if RaytraceSurfaces( x, y, x + math.cos( angle ) * 5, y + math.sin( angle ) * 5 ) then
		effect_spawn( "resonance", "reel", x, y, { owner = shooter, ax = x, ay = y, frames = a.frames, speed = a.speed } )
		return
	end
end
fx_burst( x, y, effect_color( "light", 0.8 ), 8, 30, 0.3 )
