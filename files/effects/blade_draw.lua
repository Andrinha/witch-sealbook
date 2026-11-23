-- The Sigil of the Sword drawn in pixels (manifest.lua M.blade): a steel-and-gold hilt and a tapered blade of the
-- seal's element with a white-hot core. A band of light runs from the guard to the tip as the stroke goes on
-- (progress); the edge takes the element's own shape - flame licks, water drops, ice barbs, stone chips, lightning
-- forks, wisps or sparks - and the sword leaves afterimages of its own motion. wn_blade_draw is called by the
-- blade's effect every active tick. It draws only cosmetic particles on the world's pixel grid and spends at most
-- 238 of them a tick (44 spine, 28 wake, 120 blade, 46 hilt).
--
--   wn_blade_draw( e, p, age, x, y, angle, reach, progress, style )
--     x, y      the current hilt
--     angle     where the blade points, radians
--     reach     the blade's current length, from hilt to tip
--     progress  the active stroke, 0..1
--     style     "sweep", "thrust" or "spin" ("slash" is read as a sweep)
--     p.element the element the blade is made of

dofile_once( "mods/witch_notebook/files/effects/lib.lua" )

local fx_dot = fx_dot
local effect_color = effect_color
local color_abgr_merge = color_abgr_merge
local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
local sin, cos = math.sin, math.cos

local SPINE_BUDGET, STYLE_BUDGET, BLADE_BUDGET, HILT_BUDGET = 44, 28, 120, 46

-- the hilt is the same for every element: dark leather, cool steel and old gold
local STEEL = color_abgr_merge( 148, 162, 184, 235 )
local STEEL_HOT = color_abgr_merge( 236, 246, 255, 255 )
local STEEL_DARK = color_abgr_merge( 86, 98, 120, 230 )
local GOLD = color_abgr_merge( 255, 194, 86, 245 )
local GOLD_HOT = color_abgr_merge( 255, 242, 190, 255 )
local LEATHER = color_abgr_merge( 102, 68, 48, 235 )

-- the shape language of an element's edge
local FAMILY = {
	fire = "flame", plasma = "flame", lava = "flame", firestorm = "flame", sunfire = "flame", smog = "flame",
	water = "liquid", storm = "liquid", mud = "liquid", shimmer = "liquid", steam = "liquid", steamblast = "liquid",
	ice = "frost", frost = "frost", crystal = "frost",
	earth = "earth", stone = "earth", sand = "earth", sandstorm = "earth",
	thunder = "storm", ball_lightning = "storm",
	smoke = "wisp", vacuum = "wisp", phantasm = "wisp",
	flicker = "spark", fireworks = "spark",
	wind = "air", air = "air", light = "air", beam = "air", shockwave = "air",
}

-- the blade's half-width in pixels: a stepped taper, so its silhouette reads at a glance
local function blade_profile( t, style, family, curve )
	local base = style == "thrust" and 2.5 or style == "sweep" and 3.3 or 3.0
	local width, bend = base * ( 1 - t * t ), curve * t * t
	local taper = sin( math.pi * t )
	if family == "liquid" then
		bend = bend + 4 * taper * t
		width = width * ( 0.5 + t )
	elseif family == "flame" then
		bend = bend + 1.8 * sin( t * 4 * math.pi ) * taper
	elseif family == "storm" then
		bend = bend + 2.4 * ( 4 * abs( ( t * 3 ) % 1 - 0.5 ) - 1 ) * taper
	elseif family == "frost" then
		width = width * ( 0.55 + 0.8 * ( 1 - abs( 2 * t - 0.65 ) ) )
	elseif family == "earth" then
		width = base * min( 1.4, ( 1 - t ) * 6 )
	end
	return max( 0, floor( width + 0.45 ) ), bend
end

-- Each part of the drawing has its own small budget; the sword is never truncated by its own afterimages.
local spent, limit = 0, 0
local function phase( cap )
	spent, limit = 0, cap
end

-- a cosmetic particle on the pixel grid
local function dot( x, y, color, vx, vy, life, gravity, front )
	if spent >= limit then return end
	spent = spent + 1
	fx_dot( floor( x + 0.5 ), floor( y + 0.5 ), color, vx or 0, vy or 0, life or 0.06, gravity or 0, front )
end

-- The blade: dim outer edge, element laminae, white-hot core, a bright band at progress, and an edge shaped by element.
local function blade( x, y, angle, reach, style, progress, element, family, age, curve_dir )
	local fx, fy = cos( angle ), sin( angle )
	local rx, ry = -fy, fx
	local base = 3
	local length = max( 1, reach - base )
	local step = max( 2, ceil( length / 18 ) )
	local curve = min( 3, ( style == "sweep" and 0.07 or style == "spin" and 0.04 or 0 ) * length ) * curve_dir
	local surge = base + length * progress
	local shimmer = 0.92 + 0.08 * sin( age * 0.55 )
	local c_white = effect_color( element, 1, shimmer )
	local c_core = effect_color( element, 0.82, 0.9 * shimmer )
	local c_mid = effect_color( element, 0.38, 0.72 * shimmer )
	local c_edge = effect_color( element, 0, 0.87 * shimmer )
	local c_soft = effect_color( element, 0.16, 0.32 * shimmer )
	local i = 0
	for d = base, reach - 0.001, step do
		local t = min( 1, ( d - base ) / length )
		local hw, bend = blade_profile( t, style, family, curve )
		local cx, cy = x + fx * d + rx * bend, y + fy * d + ry * bend
		local hot = abs( d - surge ) <= max( 2, step * 1.4 )
		-- the dim outer edge of the element
		if hw > 0 then
			dot( cx + rx * hw, cy + ry * hw, c_edge, 0, 0, 0.05 )
			dot( cx - rx * hw, cy - ry * hw, c_edge, 0, 0, 0.05 )
		end
		-- inner laminae, dithered so the blade keeps a pixel texture
		if hw >= 2 and i % 2 == 0 then
			dot( cx + rx * ( hw - 1 ), cy + ry * ( hw - 1 ), c_mid, 0, 0, 0.05 )
			dot( cx - rx * ( hw - 1 ), cy - ry * ( hw - 1 ), c_mid, 0, 0, 0.05 )
		end
		-- the core, hottest where the stroke's charge has reached
		dot( cx, cy, hot and c_white or c_core, 0, 0, hot and 0.08 or 0.06 )
		if hot and hw > 0 then
			dot( cx + rx * ( hw + 1 ), cy + ry * ( hw + 1 ), c_mid, 0, 0, 0.06 )
			dot( cx - rx * ( hw + 1 ), cy - ry * ( hw + 1 ), c_mid, 0, 0, 0.06 )
		end
		-- the element's own edge
		local side = i % 2 == 0 and 1 or -1
		if family == "flame" then
			local lick = sin( age * 0.55 + i * 1.9 )
			if i % 2 == 0 then
				dot( cx + rx * ( hw + 1 ) * side + fx * lick, cy + ry * ( hw + 1 ) * side + fy * lick,
					c_soft, rx * side * 14 + fx * 10, ry * side * 14 + fy * 10, 0.1 )
			end
			if i % 5 == 0 then
				dot( cx - fx * 2 + rx * ( hw + 1 ) * side, cy - fy * 2 + ry * ( hw + 1 ) * side,
					c_mid, 0, -12, 0.18, -15 )
			end
		elseif family == "liquid" then
			if i % 4 == 0 then
				dot( cx + rx * ( hw + 1 ) * side, cy + ry * ( hw + 1 ) * side,
					c_mid, rx * side * 8, ry * side * 8 + 14, 0.12, 50 )
			end
			if i % 6 == 0 then
				dot( cx - fx * 3 + rx * ( hw + 1 ) * side, cy - fy * 3 + ry * ( hw + 1 ) * side,
					c_soft, 0, 10, 0.16, 70 )
			end
		elseif family == "frost" then
			if i % 3 == 0 then
				local spike = i % 6 == 0 and 2 or 1
				for k = 1, spike do
					dot( cx + rx * ( hw + k ) * side, cy + ry * ( hw + k ) * side,
						k == spike and c_white or c_mid, 0, 0, 0.06 )
				end
			end
		elseif family == "earth" then
			if i % 3 == 0 then
				dot( cx + rx * ( hw + 1 ) * side, cy + ry * ( hw + 1 ) * side, c_mid, 0, 0, 0.05 )
				if i % 6 == 0 then
					dot( cx - fx * 2 + rx * ( hw + 1 ) * side, cy - fy * 2 + ry * ( hw + 1 ) * side,
						c_soft, 0, 10, 0.15, 60 )
				end
			end
		elseif family == "storm" then
			if i % 3 == 0 then
				local fork = i % 6 == 0 and 3 or 2
				for k = 1, fork do
					local jag = k % 2 == 0 and 1 or 0
					dot( cx + rx * ( hw + k ) * side + fx * jag, cy + ry * ( hw + k ) * side + fy * jag,
						k == fork and c_white or c_mid, 0, 0, 0.05 )
				end
			end
		elseif family == "wisp" then
			if i % 2 == 0 then
				dot( cx + rx * ( hw + 1 ) * side - fx * 2, cy + ry * ( hw + 1 ) * side - fy * 2,
					c_soft, 0, -4, 0.12 )
				if i % 4 == 0 then
					dot( cx + rx * ( hw + 2 ) * side - fx * 4, cy + ry * ( hw + 2 ) * side - fy * 4,
						c_soft, 0, -8, 0.16 )
				end
			end
		elseif family == "spark" then
			if i % 2 == 0 then
				dot( cx + rx * ( hw + 1 ) * side, cy + ry * ( hw + 1 ) * side, c_white, 0, 0, 0.06 )
			end
			if i % 5 == 0 then
				dot( cx + rx * ( hw + 2 ) * side + fx * 2, cy + ry * ( hw + 2 ) * side + fy * 2,
					c_soft, 0, -8, 0.14 )
			end
		else
			if i % 4 == 0 then
				dot( cx + rx * ( hw + 1 ) * side, cy + ry * ( hw + 1 ) * side, c_white, 0, 0, 0.06 )
			end
		end
		i = i + 1
	end
	-- the point: sharp for most elements, a flame tongue, a drip, a crystal star, a blunt stone or a fork
	local tx, ty = x + fx * reach + rx * curve, y + fy * reach + ry * curve
	dot( tx, ty, c_white, 0, 0, 0.08 )
	if family == "flame" then
		for k = 0, 2 do
			local a = age * 0.3 + k * 2.1
			dot( tx + fx * ( 2 + k ) + rx * sin( a ) * ( 1 + k * 0.5 ),
				ty + fy * ( 2 + k ) + ry * sin( a ) * ( 1 + k * 0.5 ),
				k == 0 and c_white or c_soft, fx * 12, fy * 12 - 6, 0.12, -20 )
		end
	elseif family == "liquid" then
		dot( tx + fx * 2, ty + fy * 2, c_mid, fx * 10, fy * 10 + 20, 0.14, 60 )
		dot( tx - fx, ty - fy, c_soft, 0, 20, 0.18, 60 )
	elseif family == "frost" then
		for k = 0, 3 do
			local a = k / 4 * 2 * math.pi
			dot( tx + cos( a ) * 2, ty + sin( a ) * 2, c_white, cos( a ) * 12, sin( a ) * 12, 0.07 )
		end
	elseif family == "storm" then
		dot( tx + fx * 2 + rx * 2, ty + fy * 2 + ry * 2, c_white, rx * 20, ry * 20, 0.06 )
		dot( tx + fx * 3 - rx * 2, ty + fy * 3 - ry * 2, c_mid, -rx * 20, -ry * 20, 0.06 )
	elseif family == "earth" then
		dot( tx + fx, ty + fy, c_mid, 0, 0, 0.06 )
		dot( tx - fx * 2, ty - fy * 2, c_soft, 0, 12, 0.14, 50 )
	elseif family == "wisp" then
		dot( tx + fx * 2, ty + fy * 2, c_soft, fx * 8, fy * 8 - 6, 0.14 )
	elseif family == "spark" then
		for k = 0, 3 do
			local a = k / 4 * 2 * math.pi + age * 0.1
			dot( tx + cos( a ) * 2, ty + sin( a ) * 2, c_white, cos( a ) * 15, sin( a ) * 15, 0.08 )
		end
	else
		dot( tx + fx, ty + fy, c_white, fx * 10, fy * 10, 0.08 )
	end
	if progress > 0.85 then
		local flare = ( progress - 0.85 ) / 0.15
		for k = 0, 3 do
			local a = k / 4 * 2 * math.pi + age * 0.05
			dot( tx + cos( a ) * ( 2 + 3 * flare ), ty + sin( a ) * ( 2 + 3 * flare ),
				c_white, cos( a ) * 24, sin( a ) * 24, 0.08 )
		end
	end
	-- A continuous bright spine keeps the current blade legible over older, fading sparks.
	phase( SPINE_BUDGET )
	local steps = min( SPINE_BUDGET - 1, max( 1, ceil( length ) ) )
	for j = 0, steps do
		local t = j / steps
		local d = base + t * length
		local width, bend = blade_profile( t, style, family, curve )
		bend = bend + 0.45 * width
		dot( x + fx * d + rx * bend, y + fy * d + ry * bend, c_core, 0, 0, 0.033 )
	end
end

-- The hilt: leather grip, steel ferrules, a gold pommel and a crossguard that turns with the style of the stroke.
local function hilt( x, y, angle, style, age, progress, element, parrying )
	local fx, fy = cos( angle ), sin( angle )
	local rx, ry = -fy, fx
	local function hilt_dot( d, side, color, life )
		dot( x + fx * d + rx * side, y + fy * d + ry * side, color, 0, 0, life )
	end
	for d = -8, -2 do
		local side = d % 2 == 0 and 1 or -1
		hilt_dot( d, 0, d % 3 == 0 and STEEL_DARK or LEATHER, 0.05 )
		if d % 3 == 0 then hilt_dot( d, side, STEEL, 0.05 ) end
	end
	hilt_dot( -9, 0, STEEL_HOT, 0.06 )
	hilt_dot( -10, 0, GOLD, 0.06 )
	hilt_dot( -9, 1, STEEL_DARK, 0.05 )
	hilt_dot( -9, -1, STEEL_DARK, 0.05 )
	for side = -1, 1 do hilt_dot( -1, side, GOLD_HOT, 0.06 ) end
	-- forward tips for a sweep, swept-back tips for a thrust, a pinwheel guard for a spin
	local span = parrying and 8 or style == "thrust" and 4 or style == "spin" and 7 or 6
	local gem = effect_color( element, 0.9, 0.75 + 0.25 * sin( age * 0.45 + progress * math.pi ) )
	local gem_soft = effect_color( element, 0.35, 0.5 )
	for side = -span, span do
		local bend = 0
		if parrying then bend = floor( side * side / 12 )
		elseif style == "sweep" then bend = floor( abs( side ) * 0.45 )
		elseif style == "thrust" then bend = -floor( abs( side ) * 0.5 )
		elseif style == "spin" then bend = ( side >= 0 and 1 or -1 ) * floor( abs( side ) * 0.3 ) end
		hilt_dot( 1 + bend, side, parrying and STEEL_HOT or abs( side ) == span and GOLD_HOT or GOLD, 0.06 )
		if abs( side ) < span and side % 2 == 0 then hilt_dot( 2 + bend, side, STEEL_DARK, 0.05 ) end
	end
	hilt_dot( 2, 0, gem, 0.07 )
	hilt_dot( 3, 0, gem_soft, 0.06 )
	hilt_dot( 2, 1, gem_soft, 0.06 )
	hilt_dot( 2, -1, gem_soft, 0.06 )
	if style == "spin" then
		hilt_dot( 1, span + 1, gem_soft, 0.06 )
		hilt_dot( 1, -span - 1, gem_soft, 0.06 )
	end
end

-- Sample this tick's arc. The preceding ticks' particles linger at their original positions.
local function sweep_arc( x, y, angle, reach, previous, element, progress )
	local delta = angle - previous
	if abs( delta ) < 0.002 then return end
	local dir = delta > 0 and 1 or -1
	local count = 12
	for j = 0, count - 1 do
		local t = j / ( count - 1 )
		local a = angle - delta * t
		local ca, sa = cos( a ), sin( a )
		local fade = ( 1 - t ) * ( 0.6 + 0.4 * progress )
		local vx, vy = -sa * dir, ca * dir
		dot( x + ca * reach * ( 0.58 + 0.36 * t ), y + sa * reach * ( 0.58 + 0.36 * t ),
			effect_color( element, 0.35, 0.32 * fade ), vx * 70, vy * 70, 0.08 )
		if j % 3 == 1 then
			dot( x + ca * reach * ( 0.48 + 0.28 * t ), y + sa * reach * ( 0.48 + 0.28 * t ),
				effect_color( element, 0.08, 0.16 * fade ), vx * 45, vy * 45, 0.07 )
		end
	end
	local a = angle - delta * 0.08
	dot( x + cos( a ) * reach * 0.95, y + sin( a ) * reach * 0.95,
		effect_color( element, 0.9, 0.5 ), -sin( a ) * dir * 80, cos( a ) * dir * 80, 0.08 )
end

-- A spin draws the circle the blade is cutting: bright where the steel passes, a dim rotor elsewhere.
local function spin_ring( x, y, angle, reach, element, age, turn )
	local count = 16
	for j = 0, count - 1 do
		local a = j / count * 2 * math.pi
		local near = 0.5 + 0.5 * cos( a - angle )
		local r = reach * 0.76
		dot( x + cos( a ) * r, y + sin( a ) * r,
			effect_color( element, 0.2 + 0.5 * near * near, 0.1 + 0.26 * near * near ),
			-sin( a ) * 20 * turn, cos( a ) * 20 * turn, 0.06 )
	end
	for j = 0, 7 do
		local a = j / 8 * 2 * math.pi - age * 0.04 * turn
		local r = reach * 0.42
		dot( x + cos( a ) * r, y + sin( a ) * r, effect_color( element, 0.5, 0.1 ),
			-sin( a ) * 12 * turn, cos( a ) * 12 * turn, 0.06 )
	end
	for k = 0, 3 do
		local a = k / 4 * 2 * math.pi + age * 0.12 * turn
		dot( x + cos( a ) * 3, y + sin( a ) * 3, effect_color( element, 0.9, 0.35 ),
			cos( a ) * 18, sin( a ) * 18, 0.06 )
	end
end

-- A thrust pushes a narrow cone of air ahead of the point and pulls speed lines from the hilt.
local function thrust_lines( x, y, angle, reach, element, age, progress )
	local fx, fy = cos( angle ), sin( angle )
	local rx, ry = -fy, fx
	local push = 0.35 + 0.65 * progress
	for k = 1, 4 do
		local d = reach + 2 + k * 2.4
		local side = ( k % 2 == 0 and 1 or -1 ) * ( 0.6 + 0.5 * sin( age * 0.3 + k * 1.7 ) )
		local fade = 1 - k / 5
		dot( x + fx * d + rx * side, y + fy * d + ry * side,
			effect_color( element, 0.55, 0.24 * fade * push ), fx * 90, fy * 90, 0.06 )
	end
	for k = 1, 3 do
		local side = k % 2 == 0 and 1 or -1
		dot( x - fx * ( 4 + k * 3 ) + rx * side, y - fy * ( 4 + k * 3 ) + ry * side,
			effect_color( element, 0.2, 0.16 * push ), -fx * 50, -fy * 50, 0.05 )
	end
	for k = 0, 5 do
		local a = k / 6 * 2 * math.pi
		dot( x + fx * reach + cos( a ) * 2.5, y + fy * reach + sin( a ) * 2.5,
			effect_color( element, 0.7, 0.18 * push ), cos( a ) * 12, sin( a ) * 12, 0.05 )
	end
	dot( x + fx * ( reach + 4 ), y + fy * ( reach + 4 ), effect_color( element, 1, 0.5 * push ),
		fx * 100, fy * 100, 0.07 )
end

function wn_blade_draw( e, p, age, x, y, angle, reach, progress, style, previous, turn )
	if type( x ) ~= "number" or type( y ) ~= "number" or type( angle ) ~= "number" then return end
	p = p or {}
	age = age or 0
	reach = max( 4, reach or 0 )
	progress = min( 1, max( 0, progress or 0 ) )
	if style == "slash" then style = "sweep" end
	if style ~= "thrust" and style ~= "spin" then style = "sweep" end
	local element = DICTIONARY_ELEMENTS[p.element] and p.element or "light"
	local family = FAMILY[element] or "air"
	previous = previous or angle
	local curve_dir = -( turn or 1 )

	phase( STYLE_BUDGET )
	if style == "thrust" then
		thrust_lines( x, y, angle, reach, element, age, progress )
	elseif style == "spin" then
		spin_ring( x, y, angle, reach, element, age, p.turn or 1 )
	else
		sweep_arc( x, y, angle, reach, previous, element, progress )
	end

	phase( BLADE_BUDGET )
	blade( x, y, angle, reach, style, progress, element, family, age, curve_dir )
	phase( HILT_BUDGET )
	hilt( x, y, angle, style, age, progress, element, ( p.reflect or 0 ) > 0 )

	-- The effect entity carries the light at the tip throughout the stroke.
	if e and age == 0 then
		local c = DICTIONARY_ELEMENTS[element].color
		effect_glow( e, c[1], c[2], c[3], min( 90, 30 + ( p.r or reach ) * 0.75 ), 0.12 )
	end
end
