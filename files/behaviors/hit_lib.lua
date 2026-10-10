-- Shared by the scripts that run when a seal projectile ends (cast.lua add_death_script): where it ended, what it
-- carried, whom it hit.
dofile_once( "mods/witch_notebook/files/effects/lib.lua" )
dofile_once( "mods/witch_notebook/files/resonances.lua" ) -- what the resonances' scripts do, and how much

function hit_var( e, name )
	for _, comp in ipairs( EntityGetComponentIncludingDisabled( e, "VariableStorageComponent" ) or {} ) do
		if ComponentGetValue2( comp, "name" ) == name then
			local s = ComponentGetValue2( comp, "value_string" )
			if s and s ~= "" then return s end
			return ComponentGetValue2( comp, "value_float" )
		end
	end
end

function hit_shooter( e )
	local proj = EntityGetFirstComponentIncludingDisabled( e, "ProjectileComponent" )
	return proj and ComponentGetValue2( proj, "mWhoShot" ) or 0
end

-- the creature the projectile ended on (or the nearest to where it ended)
function hit_target( e, r )
	local x, y = EntityGetTransform( e )
	return nearest_creature( x, y, r or 14, hit_shooter( e ) ), x, y
end

