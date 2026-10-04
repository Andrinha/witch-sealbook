-- Lights and drops circling the caster (manifest.lua): the Carousel of Lights, a ring of the element (regions
-- pointing at each other: the magic on the ring's line), Floating Drops.

local MODES = {}

local function circle( e, p, age, n, radius, draw, touch )
	local owner, x, y = effect_follow( e, p, -6 )
	if not owner then return end
	if age >= p.frames then
		EntityKill( e )
		return
	end
	local grow = math.min( 1, age / 20 )
	for i = 0, n - 1 do
		local a = age * ( p.speed or 0.06 ) + i / n * 2 * math.pi
		local r = radius( i, age ) * grow
		local px, py = x + math.cos( a ) * r, y + math.sin( a ) * r * ( p.flat or 0.8 )
		draw( px, py, a, i )
		if age % 4 == i % 4 then
			for _, id in ipairs( creatures_in( px, py, 7, owner ) ) do touch( id, px, py ) end
		end
	end
	return owner
end

-- Carousel of Lights: orbiting illumination, an interpretation of the redraw.
MODES.carousel = function( e, p, age )
	local owner = circle( e, p, age, p.count or 6, function( i, age ) return 22 + 6 * math.sin( age * 0.05 + i ) end,
		function( px, py, a, i )
			local fade = math.min( 1, ( p.frames - age ) / 40 )
			fx_ring( px, py, 2, effect_color( "light", 0.6, fade * 0.7 ), 12, 0, 0.06 )
			fx_dot( px, py, effect_color( "light", 1, fade ), 0, 0, 0.08 )
			for k = 1, 5 do
				fx_dot( px + math.sin( a ) * k, py - math.cos( a ) * k * 0.8,
					effect_color( "light", 0.3, fade * ( 1 - k / 6 ) * 0.4 ), 0, 0, 0.08 )
			end
		end,
		function() end )
	if owner and age == 0 then EntityAddComponent2( e, "LightComponent", { radius = 90, r = 255, g = 230, b = 170, fade_out_time = 1 } ) end
end

-- a ring of the element round the caster: it strikes what it touches; water puts out fire on the caster
MODES.ring = function( e, p, age )
	local look = DICTIONARY_LOOKS[p.element] or {}
	local owner = circle( e, p, age, p.count or 10, function( i, age ) return p.radius or 24 end,
		function( px, py, a, i )
			fx_dot( px, py, effect_color( p.element, 0.3 ), 0, 0, 0.06 )
			if i % 2 == 0 then fx_dot( px, py, effect_color( p.element, 0.8, 0.8 ), -math.sin( a ) * 15, math.cos( a ) * 15, 0.2 ) end
			if look.material and Random( 1, 40 ) == 1 then GameCreateCosmeticParticle( look.material, px, py, 1, 0, 0, 0, 0.3, 0.5, true, false, false, false, 0, 0 ) end
		end,
		function( id, px, py )
			seal_damage( id, 0.1 * ( p.power or 1 ), "DAMAGE_PROJECTILE", p.owner, px, py )
			if look.status and look.status ~= "" then give_effect( id, look.status ) end
			push_from( id, px, py, 60 )
		end )
	if owner and age % 30 == 0 and ( p.element == "water" or p.element == "storm" or p.element == "ice" ) then
		clear_effects( owner, { "ON_FIRE" } )
	end
end

-- Envelopment: the element wraps round the creature a projectile hit and keeps striking it
MODES.envelop = function( e, p, age )
	local target, x, y = effect_follow( e, p, -5 )
	if not target then return end
	if age >= p.frames then
		fx_burst( x, y, effect_color( p.element, 0.6 ), 16, 40, 0.4 )
		EntityKill( e )
		return
	end
	local look = DICTIONARY_LOOKS[p.element] or {}
	local r = 10 - 3 * math.min( 1, age / 20 )
	for i = 0, 7 do
		local a = age * 0.15 + i / 8 * 2 * math.pi
		fx_dot( x + math.cos( a ) * r, y + math.sin( a ) * r * 0.8, effect_color( p.element, 0.4 ), 0, 0, 0.06 )
	end
	if age % 20 == 0 then
		local kind = look.damage and look.damage.fire and "DAMAGE_FIRE" or "DAMAGE_PROJECTILE"
		seal_damage( target, 0.1 * ( p.power or 1 ), kind, p.caster, x, y )
		if look.status and look.status ~= "" then give_effect( target, look.status ) end
	end
end

EFFECT_MODES.orbit = MODES
