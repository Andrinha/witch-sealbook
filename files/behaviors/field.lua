-- A field round the caster (the form "field": Dispersion held still, the "circle of" an element; carriers.lua makes it
-- from entities/templates/field.xml). Its element's matter rises on its circle, where the circle can be reached from its
-- middle - not through walls, and never farther out: a field stays where a wave runs on. Every so often whoever is
-- inside takes the element's touch (burns, wets, freezes, shocks, blinds). Its radius is its damage area's, so the
-- circle Expansion makes bigger has the matter on it too. Matter that sets solid (Crystal's ice, DICTIONARY_FIELD_SOLID)
-- would wall the caster in: its sparks alone mark the circle; an element that shines with a glow of its own (Plasma,
-- DICTIONARY_LOOKS 'glow') shines with it in place of its matter. "witch_field_material", "witch_field_status",
-- "witch_field_glow": what its element leaves, does and shines with.
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local TOUCH_EVERY = 40 -- frames between the touches of the creatures inside
local GLOW = 3         -- glowing motes on the circle each time

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform( e )
local area = EntityGetFirstComponentIncludingDisabled( e, "AreaDamageComponent" )
local r = area and ComponentGetValue2( area, "circle_radius" ) or 32
-- a word the field keeps ("" when it keeps none: hit_var gives an empty word's number)
local function word( name )
	local v = hit_var( e, name )
	return type( v ) == "string" and v or ""
end
-- a point of the circle the middle reaches, or nil
local function on_circle()
	local a = Random( 0, 1000 ) / 1000 * 2 * math.pi
	local px, py = x + math.cos( a ) * r, y + math.sin( a ) * r
	if not RaytraceSurfaces( x, y, px, py ) then return px, py, math.cos( a ), math.sin( a ) end
end
local glow = word( "witch_field_glow" )
local material = word( "witch_field_material" )
if glow ~= "" then
	for _ = 1, GLOW do
		local px, py, c, s = on_circle()
		if px then GameCreateCosmeticParticle( glow, px, py, 1, c * 6, s * 6, 0, 0.3, 0.7, true, true, false, true, 0, 0 ) end
	end
elseif material ~= "" and material ~= "air" and not DICTIONARY_FIELD_SOLID[material] then
	local px, py = on_circle()
	if px then GameCreateParticle( material, px, py, 1, 0, 0, false, false, false ) end
end
local status = word( "witch_field_status" )
if status ~= "" and GameGetFrameNum() % TOUCH_EVERY < 2 then
	for _, id in ipairs( EntityGetInRadiusWithTag( x, y, r, "enemy" ) or {} ) do give_effect( id, status ) end
end
