-- The Repetition Seal's effect (manifest.lua M.repeat): the seal the Repetition's sigil was drawn in - already
-- cast once, by the seal itself - comes again, as many times as the sigil was drawn ('times'), each from where the
-- caster is and aims at that moment. The seal is handed over as it was cast ('spell_data'): nested, so its price
-- was paid once, by the casting itself.
dofile_once( "mods/witch_notebook/files/cast.lua" )

local MODES = {}

MODES.cast = function( e, p, age, x, y )
	local owner = effect_owner( p )
	if not owner or age > math.max( 1, math.floor( p.times or 1 ) ) * 20 then
		EntityKill( e )
		return
	end
	if age == 0 or age % 20 ~= 0 then return end
	local data = p.spell_data or ""
	local controls = EntityGetFirstComponent( owner, "ControlsComponent" )
	if data == "" or not controls then
		EntityKill( e )
		return
	end
	local ox, oy = EntityGetTransform( owner )
	local aim_x, aim_y = ComponentGetValue2( controls, "mAimingVectorNormalized" )
	local tx, ty = ComponentGetValue2( controls, "mMousePosition" )
	cast_spell( owner, parse_spell_data( data ), ox, oy - 4, aim_x, aim_y, tx, ty, run_frame(), nil, true )
	fx_ring( ox, oy - 4, 10, fx_color( "light", 0.7 ), 16, 30, 0.3 )
end

EFFECT_MODES["repeat"] = MODES
