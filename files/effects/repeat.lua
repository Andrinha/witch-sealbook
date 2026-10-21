-- The Repetition Seal (manifest.lua): the last seal the book cast comes again, three times in a row, each from where
-- the caster is and aims at that moment.
dofile_once( "mods/witch_notebook/files/cast.lua" )

local MODES = {}

-- The seal again without its own Repetition - a small seal of it inside or linked to it: repeated, it would repeat the
-- seal three times more each time, without end (a Workshop player's game froze). So the seal is cast four times.
local function without_repetition( spell )
	for _, list in ipairs( { spell.subs or {}, spell.links or {} } ) do
		for k = #list, 1, -1 do
			if list[k].manifest == "repeat" then table.remove( list, k ) end
		end
	end
	return spell
end

MODES.cast = function( e, p, age, x, y )
	local owner = effect_owner( p )
	if not owner or age > ( p.times or 3 ) * 20 then
		EntityKill( e )
		return
	end
	if age == 0 or age % 20 ~= 0 then return end
	local data = GlobalsGetValue( LAST_SPELL_VAR, "" )
	local controls = EntityGetFirstComponent( owner, "ControlsComponent" )
	if data == "" or not controls then
		EntityKill( e )
		return
	end
	local ox, oy = EntityGetTransform( owner )
	local aim_x, aim_y = ComponentGetValue2( controls, "mAimingVectorNormalized" )
	local tx, ty = ComponentGetValue2( controls, "mMousePosition" )
	cast_spell( owner, without_repetition( parse_spell_data( data ) ), ox, oy - 4, aim_x, aim_y, tx, ty, run_frame(), nil, true )
	fx_ring( ox, oy - 4, 10, fx_color( "light", 0.7 ), 16, 30, 0.3 )
end

EFFECT_MODES["repeat"] = MODES
