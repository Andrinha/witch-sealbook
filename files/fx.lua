-- Looks of the seals' magic, shared by casting (cast.lua) and the effects' scripts (effects/*.lua): glowing
-- particles along shapes - a ring, a spiral, the seal itself drawn in the air - in an element's colors.
-- Cosmetic particles only: they don't touch the world and cost little.

dofile_once( "data/scripts/lib/utilities.lua" )

FX_SPARK = "spark_white_bright" -- a cosmetic particle material that glows; its color is set per particle

-- An element's color as the particle color value (ABGR), a little brighter towards white by 'white' (0..1)
function fx_color( element, white, alpha )
	local def = DICTIONARY_ELEMENTS and DICTIONARY_ELEMENTS[element]
	local c = def and def.color or { 230, 200, 120 }
	white = white or 0
	local r = c[1] + ( 255 - c[1] ) * white
	local g = c[2] + ( 255 - c[2] ) * white
	local b = c[3] + ( 255 - c[3] ) * white
	return color_abgr_merge( math.floor( r ), math.floor( g ), math.floor( b ), math.floor( ( alpha or 1 ) * 255 ) )
end

-- one glowing particle
function fx_dot( x, y, color, vx, vy, life, gravity, front )
	GameCreateCosmeticParticle( FX_SPARK, x, y, 1, vx or 0, vy or 0, color, life or 0.4, ( life or 0.4 ) * 1.4, true, front ~= false,
		false, false, 0, gravity or 0 )
end

-- particles on a circle; 'drift': how fast they move out (negative: in)
function fx_ring( x, y, r, color, count, drift, life )
	count = count or math.max( 8, math.floor( r * 0.8 ) )
	local phase = Random( 0, 1000 ) / 1000 * 2 * math.pi
	for i = 1, count do
		local a = phase + 2 * math.pi * i / count
		local c, s = math.cos( a ), math.sin( a )
		fx_dot( x + c * r, y + s * r, color, c * ( drift or 0 ), s * ( drift or 0 ), life )
	end
end

-- a burst of particles flying out in every direction
function fx_burst( x, y, color, count, speed, life, gravity )
	for i = 1, count do
		local a = Random( 0, 1000 ) / 1000 * 2 * math.pi
		local v = ( speed or 60 ) * ( 0.3 + Random( 0, 700 ) / 1000 )
		fx_dot( x, y, color, math.cos( a ) * v, math.sin( a ) * v, life or 0.5, gravity )
	end
end

-- a line of particles from x1, y1 to x2, y2, one every 'step' pixels
function fx_line( x1, y1, x2, y2, color, step, life, jitter )
	local d = math.sqrt( ( x2 - x1 ) ^ 2 + ( y2 - y1 ) ^ 2 )
	local n = math.max( 1, math.floor( d / ( step or 3 ) ) )
	for i = 0, n do
		local t = i / n
		local j = jitter or 0
		fx_dot( x1 + ( x2 - x1 ) * t + ( Random( -100, 100 ) / 100 ) * j, y1 + ( y2 - y1 ) * t + ( Random( -100, 100 ) / 100 ) * j, color, 0, 0, life )
	end
end

-- The seal drawn in the air, glowing: 'strokes' in the grimoire's page units (SEAL_PAGE_SIZE: 180 x 180, the ring around
-- 90, 90 - notebook.lua brings every book's drawings to them), placed so
-- that the ring's center is at x, y and its radius is 'radius' pixels; turned by 'angle'. 'share' of the points
-- are drawn (a big seal needn't draw all).
function fx_seal( strokes, x, y, radius, color, angle, life, share )
	if not strokes or #strokes == 0 then return end
	local k = radius / 70
	local c, s = math.cos( angle or 0 ), math.sin( angle or 0 )
	share = share or 1
	local count = 0
	for _, stroke in ipairs( strokes ) do
		for i, p in ipairs( stroke ) do
			if i == 1 or Random( 0, 1000 ) / 1000 < share then
				local px, py = ( p.x - 90 ) * k, ( p.y - 90 ) * k
				fx_dot( x + px * c - py * s, y + px * s + py * c, color, 0, 0, life or 0.5 )
				count = count + 1
				if count > 900 then return end
			end
		end
	end
end

-- a spiral of particles around x, y: arms turning 'turns' times from r0 to r1
function fx_spiral( x, y, r0, r1, turns, color, count, phase, life, drift )
	count = count or 24
	phase = phase or 0
	for i = 0, count - 1 do
		local t = i / ( count - 1 )
		local a = phase + t * turns * 2 * math.pi
		local r = r0 + ( r1 - r0 ) * t
		local c, s = math.cos( a ), math.sin( a )
		fx_dot( x + c * r, y + s * r, color, -s * ( drift or 0 ), c * ( drift or 0 ), life )
	end
end

-- a soft light flash where the seal awakens
function fx_flash( x, y, element, radius, frames )
	local c = DICTIONARY_ELEMENTS and DICTIONARY_ELEMENTS[element] and DICTIONARY_ELEMENTS[element].color or { 230, 200, 120 }
	local e = EntityCreateNew( "witch_flash" )
	EntitySetTransform( e, x, y )
	EntityAddComponent2( e, "LightComponent", { radius = radius or 90, r = c[1], g = c[2], b = c[3], fade_out_time = 0.4 } )
	EntityAddComponent2( e, "LifetimeComponent", { lifetime = frames or 10 } )
	return e
end

-- Living flame: hot cores, orange edges and tongues that change shape every frame.
-- Cold flames use the same shapes in blue; every particle here is cosmetic.
local function flame_color( hot, alpha, cold )
	local a, b = { 255, 75, 9 }, { 255, 247, 175 }
	if cold then a, b = { 65, 120, 255 }, { 210, 245, 255 } end
	return color_abgr_merge( math.floor( a[1] + ( b[1] - a[1] ) * hot ),
		math.floor( a[2] + ( b[2] - a[2] ) * hot ), math.floor( a[3] + ( b[3] - a[3] ) * hot ), math.floor( 255 * alpha ) )
end

function fx_flame_ball( x, y, r, age, cold, alpha )
	alpha = alpha or 1
	for tongue = 0, 8 do
		local phase = tongue * 2.4 + age * 0.19
		local side = ( tongue - 4 ) / 4
		local base_x = x + side * r * 0.85
		local base_y = y + math.sqrt( math.max( 0, 1 - side * side ) ) * r * 0.35
		local height = r * ( 1.25 + 0.45 * math.sin( phase ) ) * ( 1 - 0.25 * math.abs( side ) )
		for j = 0, 7 do
			local t = j / 7
			local width = ( 1 - t ) * r * 0.22
			local px = base_x + math.sin( phase + t * 3.5 ) * t * r * 0.22
			local py = base_y - t * height
			for dir = -1, 1, 2 do
				fx_dot( px + dir * width, py, flame_color( 0.08, alpha * ( 1 - t * 0.7 ), cold ), 0, -8, 0.065 )
			end
			fx_dot( px, py, flame_color( 0.5 + 0.45 * ( 1 - t ), alpha * ( 1 - t * 0.5 ), cold ), 0, -6, 0.045 )
		end
	end
	for i = -3, 3 do
		local side = i / 3
		fx_dot( x + side * r * 0.5, y - r * 0.25, flame_color( 1, alpha * 0.9, cold ), 0, -4, 0.04 )
	end
	if age % 4 == 0 then
		fx_dot( x + math.sin( age * 1.7 ) * r * 0.8, y - r * 0.5, flame_color( 0.4, alpha * 0.7, cold ),
			math.sin( age * 0.9 ) * 8, -20, 0.35 )
	end
end

-- Real material particles (water, sand, fire): 'count' of them spread over a circle
function fx_material( material, x, y, count, r, vx, vy )
	if not material or material == "" or material == "air" then return end
	for i = 1, count do
		local a = Random( 0, 1000 ) / 1000 * 2 * math.pi
		local d = ( r or 0 ) * math.sqrt( Random( 0, 1000 ) / 1000 )
		GameCreateParticle( material, x + math.cos( a ) * d, y + math.sin( a ) * d, 1, vx or 0, vy or 0, false, false, true )
	end
end
