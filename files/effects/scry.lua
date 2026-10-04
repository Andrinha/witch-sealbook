-- The Looking Glass (manifest.lua): the caster's gaze flies ahead - for a few seconds the camera looks far away where
-- they aimed, and the fog of war there clears; then it comes back.

local MODES = {}

MODES.gaze = function( e, p, age, x, y )
	local owner = effect_owner( p )
	local frames = p.frames or 150
	if not owner or age >= frames then
		GameSetCameraFree( false )
		EntityKill( e )
		return
	end
	local ox, oy = EntityGetTransform( owner )
	if age == 0 then
		GameSetCameraFree( true )
		EntityAddComponent2( e, "FogOfWarRemoverComponent", { radius = 180 } )
		EntitySetTransform( e, p.tx, p.ty )
	end
	-- out, a look, and back
	local t
	if age < 30 then t = age / 30 elseif age > frames - 30 then t = ( frames - age ) / 30 else t = 1 end
	t = t * t * ( 3 - 2 * t )
	GameSetCameraPos( ox + ( p.tx - ox ) * t, oy + ( p.ty - oy ) * t )
	if age % 3 == 0 then
		fx_ring( p.tx, p.ty, 12 + math.sin( age * 0.1 ) * 2, fx_color( "light", 0.7, 0.5 ), 20, 0, 0.1 )
	end
end

EFFECT_MODES.scry = MODES
