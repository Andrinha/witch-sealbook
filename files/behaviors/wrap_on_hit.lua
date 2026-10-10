-- Ice Coffin, Entomb, Cyclone (resonances.lua): what an element that envelops does to whoever its shot strikes.
-- "witch_wrap": which ("coffin", "entomb", "cyclone"), "witch_wrap_frames": how long, "witch_wrap_element": the element.
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local target, x, y = hit_target( e, 16 )
local kind = hit_var( e, "witch_wrap" ) or "coffin"
local frames = math.floor( hit_var( e, "witch_wrap_frames" ) or 180 )
local element = hit_var( e, "witch_wrap_element" ) or "light"
local shooter = hit_shooter( e )
if not target then
	fx_burst( x, y, effect_color( element, 0.7 ), 10, 40, 0.3 )
	return
end
local tx, ty = EntityGetTransform( target )
local middle = creature_body( target )
if kind == "coffin" then
	-- frozen solid where it stands
	give_effect( target, MISC .. "effect_frozen.xml", frames )
	hold_creature( target, frames, "time", element, shooter )
	fx_burst( tx, ty + middle, effect_color( "ice", 0.9 ), 18, 40, 0.5 )
elseif kind == "entomb" then
	-- blocks of the element close round it, and it is held
	local a = RESONANCE_AMOUNTS.entomb( 1 )
	local piece = SOLID_PIECES[element] or "stone_block"
	for i = 0, a.pieces - 1 do
		local angle = i / a.pieces * 2 * math.pi
		local px, py = tx + math.cos( angle ) * a.r, ty + middle + math.sin( angle ) * a.r
		if not RaytraceSurfaces( tx, ty + middle, px, py ) then solid_piece( piece, px, py, frames ) end
	end
	hold_creature( target, frames, HIT_LOOK[element] or "sand", element, shooter )
else
	effect_spawn( "resonance", "cyclone", tx, ty, { owner = shooter, target = target, frames = frames, cx = tx, cy = ty,
		height = RESONANCE_AMOUNTS.cyclone( 1 ).height, element = element } )
end
