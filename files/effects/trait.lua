-- What an element's nature leaves where its shot ends (element_traits.lua, behaviors/trait_end.lua): a bright element's
-- flare, a murky one's cloud of smoke.

local MODES = {}

-- the place lit up for a while, the light fading out
MODES.flare = function( e, p, age, x, y )
	if age == 0 then
		local c = ( DICTIONARY_ELEMENTS[p.element] or DICTIONARY_ELEMENTS.light ).color
		EntityAddComponent2( e, "LightComponent", { radius = 90, r = c[1], g = c[2], b = c[3], fade_out_time = 1.5 } )
		fx_burst( x, y, effect_color( p.element, 0.8 ), 14, 50, 0.5 )
	end
	if effect_done( e, p, age ) then return end
	if age % 4 == 0 then fx_dot( x + Random( -3, 3 ), y + Random( -3, 3 ), effect_color( p.element, 0.9, 0.8 ), 0, -6, 0.5 ) end
end

-- a cloud of smoke: whoever is in it but the caster is blinded
MODES.puff = function( e, p, age, x, y )
	if effect_done( e, p, age ) then return end
	local fade = math.min( 1, age / 10, ( p.frames - age ) / 40 )
	for _ = 1, 3 do
		local a = Random( 0, 628 ) / 100
		local rr = p.r * math.sqrt( Random( 0, 1000 ) / 1000 )
		GameCreateCosmeticParticle( FX_SPARK, x + math.cos( a ) * rr, y + math.sin( a ) * rr * 0.7, 1, Random( -5, 5 ), Random( -4, 2 ),
			color_abgr_merge( 150, 150, 160, math.floor( 170 * fade ) ), 1, 1.8, true, true, false, false, 0, 0 )
	end
	if age % 30 == 0 then
		for _, id in ipairs( creatures_in( x, y, p.r, p.owner ) ) do give_effect( id, MISC .. "effect_blindness.xml", 60 ) end
	end
end

EFFECT_MODES.trait = MODES
