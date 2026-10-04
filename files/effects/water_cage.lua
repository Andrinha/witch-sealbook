-- Water Cage: a sphere of water swells where it was cast and stands there, in the air. It is real water that stands
-- still (materials.xml witch_cage_water, and witch_cage_rim for its skin and the gleam on it), put cell by cell by
-- the game's picture emitters (entities/water_cage_<r>.xml): they fill the sphere from its middle out, never through
-- a wall, and go on mending it while it stands. Creatures in it or near its skin are drawn into its middle and
-- sealed there (effects/held.lua): they float, cannot move or act, are soaked and choke. When the spell's time is up
-- the sphere bursts into water that falls and dries away, and they are let go.

local BODY = "mods/witch_notebook/files/entities/water_cage_"
local SIZES = { 16, 21, 27, 34 }   -- the radii the pictures are made for (tools/make_gfx.py WATER_CAGE_SIZES)
local GROW = 24                    -- frames the sphere takes to swell; the pictures' time runs 0..255 over them
local SPEED = 255 / GROW           -- (make_gfx.py WATER_CAGE_GROW)
local PULL = 26                    -- how far outside its skin a creature is still drawn in
local STAND, BURST = 0, 1

local function body_of( e )
	for _, child in ipairs( EntityGetAllChildren( e ) or {} ) do
		if EntityHasTag( child, "witch_water_cage_body" ) then return child end
	end
end

-- Whoever is in the sphere or near its skin, with nothing solid between, is sealed for as long as the cage lasts.
local function seal( e, p, age, x, y )
	local caught = 0
	for _, id in ipairs( creatures_in( x, y, p.r + PULL, p.owner ) ) do
		if not held_as( id, "water" ) then
			local ex, ey = EntityGetTransform( id )
			local oy = creature_body( id )
			if not RaytraceSurfaces( x, y, ex, ey + oy ) then
				hold_creature( id, p.frames - age, "water", "water", p.owner, { cage = e, cx = x, cy = y, oy = oy } )
				caught = caught + 1
			end
		end
	end
	return caught
end

local MODES = {}

MODES.sphere = function( e, p, age, x, y )
	if age == 0 then
		-- the smallest sphere that is as big as asked
		local r = SIZES[#SIZES]
		for i = #SIZES, 1, -1 do
			if SIZES[i] >= p.r then r = SIZES[i] end
		end
		p.r = r
		effect_set( e, "r", r )
		EntityAddChild( e, EntityLoad( BODY .. r .. ".xml", x, y ) )
		EntityAddComponent2( e, "LightComponent", { radius = r * 3, r = 90, g = 160, b = 255, fade_out_time = 0.4 } )
		effect_sound( "magic", x, y )
	end
	if ( p.phase or STAND ) == BURST then
		if age >= p.ends then EntityKill( e ) end
		return
	end
	if age >= p.frames then
		-- The emitters stop; the standing water turns into water that falls and soon dries away.
		local body = body_of( e )
		if body then EntityKill( body ) end
		EntityAddComponent2( e, "MagicConvertMaterialComponent", { from_material_array = "witch_cage_water,witch_cage_rim",
			to_material_array = "water_fading,water_fading", radius = p.r + 3, is_circle = true,
			steps_per_frame = math.ceil( p.r / 4 ), loop = false, kill_when_finished = false } )
		fx_burst( x, y, fx_color( "water", 0.8 ), 30, 70, 0.5 )
		effect_set( e, "phase", BURST )
		effect_set( e, "ends", age + 12 )
		return
	end
	if age < GROW then
		-- the skin of the swelling sphere
		fx_ring( x, y, p.r * ( age + 1 ) / GROW, fx_color( "water", 0.7, 0.9 ), 18, 0, 0.06 )
	elseif ( p.grown or 0 ) == 0 then
		-- Grown: the emitters go round four times slower, mending what is knocked or boiled out of it.
		for _, emitter in ipairs( EntityGetComponentIncludingDisabled( body_of( e ) or e, "ParticleEmitterComponent" ) or {} ) do
			ComponentSetValue2( emitter, "image_animation_speed", SPEED / 4 )
		end
		effect_set( e, "grown", 1 )
	end
	if age % 4 == 0 and seal( e, p, age, x, y ) > 0 then effect_sound( "magic", x, y ) end
	if age % 9 == 0 then
		-- a bubble rises through it
		local a, d = Random( 0, 628 ) / 100, p.r * 0.7 * math.sqrt( Random( 0, 1000 ) / 1000 )
		fx_dot( x + math.cos( a ) * d, y + math.abs( math.sin( a ) ) * d, fx_color( "water", 0.9, 0.8 ), 0, -18, 0.5 )
	end
end

EFFECT_MODES.water_cage = MODES
