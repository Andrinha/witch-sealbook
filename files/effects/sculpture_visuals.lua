-- Creature silhouettes in particles, independent of the symbols written on paper.
-- Coordinates face right; the caller supplies scale, direction and animation age.
-- 'style' is optional: the effect's parameters. The renderer reads grow, shrink, strong, still, pierce, mimic
-- and glow to show the signs that made the sculpture; movement and damage stay in mover.lua.
-- Particles are budgeted: line spacing grows with the silhouette, fills are sparse, and an element accents it
-- with only a few dots a frame.
function sculpture_brush( x, y, scale, angle, flip, element, fade, boost )
	local cs, sn = math.cos( angle or 0 ), math.sin( angle or 0 )
	local dir = flip and -1 or 1
	local spacing = math.max( 1, scale )
	boost = boost or 0
	local function point( u, v )
		u, v = u * scale * dir, v * scale
		return x + u * cs - v * sn, y + u * sn + v * cs
	end
	local function line( ax, ay, bx, by, white, step )
		local px, py = point( ax, ay )
		local qx, qy = point( bx, by )
		fx_line( px, py, qx, qy, effect_color( element, math.min( 1, ( white or 0.4 ) + boost ), ( fade or 1 ) * 0.8 ),
			( step or 1.15 ) * spacing, 0.06 )
	end
	local function oval( cx, cy, rx, ry, white, filled, step )
		step = step or 1.5
		if filled then
			for row = -ry, ry, step do
				local w = rx * math.sqrt( math.max( 0, 1 - ( row / ry ) ^ 2 ) )
				line( cx - w, cy + row, cx + w, cy + row, white, step )
			end
		end
		local n = math.max( 8, math.ceil( ( rx + ry ) * 1.5 ) )
		for i = 1, n do
			local a, b = ( i - 1 ) / n * math.pi * 2, i / n * math.pi * 2
			line( cx + math.cos( a ) * rx, cy + math.sin( a ) * ry,
				cx + math.cos( b ) * rx, cy + math.sin( b ) * ry, ( white or 0.4 ) + 0.15, 1.1 )
		end
	end
	return line, oval, point
end

local function style_of( params )
	if type( params ) ~= "table" then params = {} end
	local size_sign = ( params.grow or 0 ) - ( params.shrink or 0 )
	return {
		grow = math.max( 0, size_sign ),
		shrink = math.max( 0, -size_sign ),
		strong = math.min( 1, ( params.strong or 0 ) * 0.5 ),
		still = math.min( 1, ( params.still or 0 ) * 0.5 ),
		pierce = params.pierce or 0,
		mimic = params.mimic == 1,
		glow = params.glow or 0,
	}
end

-- Elements that leave a similar mark: a flame, a drop, a gust, a grain, a wisp or a spark. Mixes follow the
-- matter or the nature of the element they are named for.
local FAMILY = {}
local function family( list, name )
	for _, key in ipairs( list ) do FAMILY[key] = name end
end
family( { "fire", "lava", "sunfire", "firestorm", "fireworks", "plasma", "phantasm" }, "fire" )
family( { "water", "storm", "shimmer", "mud" }, "water" )
family( { "wind", "air", "vacuum", "sandstorm" }, "wind" )
family( { "steam", "steamblast" }, "smoke" )
family( { "earth", "sand", "stone" }, "earth" )
family( { "crystal", "ice", "frost" }, "crystal" )
family( { "smoke", "smog" }, "smoke" )
family( { "thunder", "ball_lightning", "flicker", "beam" }, "spark" )

-- a few particles of the element at a tip or a hoof: the silhouette stays legible, the element shows at its edges
local function breath( x, y, big, dir, age, element, fade, kind )
	local fam = FAMILY[element] or "light"
	local a = math.max( 0, math.min( 1, fade or 1 ) )
	local c = effect_color( element, 0.35, 0.75 * a )
	local hot = effect_color( element, 0.9, 0.85 * a )
	local k = math.max( 0.6, math.min( 2, big or 1 ) )
	local up = kind == "wing" and -4 or 0
	if fam == "fire" then
		local sway = math.sin( age * 0.32 ) * 2 * k
		fx_dot( x + sway, y, c, dir * 2 * k, ( -10 + up ) * k, 0.2 )
		fx_dot( x - dir * 1.5 * k + sway, y - 2 * k, hot, -dir * 2 * k, ( -16 + up ) * k, 0.16 )
	elseif fam == "water" then
		fx_dot( x, y, c, dir * 3 * k, k, 0.22, 170 )
		if age % 3 == 0 then fx_dot( x - dir * 2 * k, y - k, hot, -dir * 5 * k, 5 * k, 0.18, 190 ) end
	elseif fam == "wind" then
		fx_dot( x, y, c, -dir * ( 18 + 4 * math.sin( age * 0.2 ) ) * k, ( -2 + up ) * k, 0.14 )
		if age % 3 == 0 then fx_dot( x - dir * 3 * k, y - k, hot, -dir * 26 * k, ( -3 + up ) * k, 0.12 ) end
	elseif fam == "earth" then
		fx_dot( x, y, c, Random( -4, 4 ) * k, 4 * k, 0.24, 120 )
		if age % 4 == 0 then fx_dot( x + Random( -3, 3 ) * k, y, hot, Random( -2, 2 ) * k, 8 * k, 0.2, 90 ) end
	elseif fam == "crystal" then
		if age % 4 == 0 then
			fx_dot( x + Random( -3, 3 ) * k, y - Random( 0, 4 ) * k, hot, 0, -4 * k, 0.2 )
			fx_dot( x - Random( -2, 2 ) * k, y, c, 0, 3 * k, 0.22, 80 )
		end
	elseif fam == "smoke" then
		fx_dot( x, y, c, dir * 2 * k, -6 * k, 0.32 )
		if age % 4 == 0 then fx_dot( x + Random( -3, 3 ) * k, y - 2 * k, hot, 0, -9 * k, 0.28 ) end
	elseif fam == "spark" then
		if ( element == "thunder" or element == "ball_lightning" ) and age % 9 == 0 then
			local bend = Random( -3, 3 ) * k
			local mx, my = x - dir * 3 * k, y - 2 * k + bend
			fx_line( x, y, mx, my, hot, 1.2 * k, 0.07 )
			fx_line( mx, my, x - dir * 7 * k, y + bend, c, 1.2 * k, 0.07 )
		elseif age % 3 == 0 then
			fx_dot( x + Random( -3, 3 ) * k, y - Random( 0, 3 ) * k, hot,
				Random( -8, 8 ) * k, Random( -4, 2 ) * k, 0.1 )
		end
	else
		if age % 4 == 0 then fx_dot( x + Random( -4, 4 ) * k, y - Random( 0, 6 ) * k, hot, 0, -3 * k, 0.22 ) end
		fx_dot( x, y, c, 0, 0, 0.06 )
	end
end

-- the signs that are not size or count: a brighter core, a settled ring, growth rings, a gilded mote, an echo
local function cues( x, y, big, dir, age, element, style, fade )
	local a = math.max( 0, math.min( 1, fade or 1 ) )
	if style.strong > 0 and age % 6 == 0 then
		fx_dot( x + dir * 2, y - 2, effect_color( element, 1, 0.9 * a ), dir * 8, -7, 0.12 )
	end
	if style.still > 0 and age % 16 == 0 then
		fx_ring( x, y + 9 * big, 3.5 * big, effect_color( element, 0.65, 0.5 * a ), 6, 0, 0.2 )
	end
	if style.grow > 0 and age % 24 == 0 then
		fx_ring( x, y, 3 * big, effect_color( element, 0.7, 0.45 * a ), 7, 10, 0.22 )
	elseif style.shrink > 0 and age % 24 == 0 then
		fx_ring( x, y, 9 * big, effect_color( element, 0.7, 0.45 * a ), 7, -8, 0.22 )
	end
	if style.glow > 0 and age % 10 == 0 then
		fx_dot( x + Random( -6, 6 ), y - Random( 0, 10 ), color_abgr_merge( 255, 214, 120, math.floor( 220 * a ) ), 0, -6, 0.3 )
	end
	if style.pierce > 0 and age % 8 == 0 then
		fx_dot( x - dir * 5, y, effect_color( element, 0.7, 0.35 * a ), -dir * 12, 0, 0.16 )
	end
end

function sculpture_quadruped( shape, x, y, big, dir, age, element, fade, style )
	local st = style_of( style )
	local line, oval, point = sculpture_brush( x, y, big, 0, dir < 0, element, fade, st.strong * 0.18 )
	local wolf, stag, goat, ram = shape == "scalewolf", shape == "torchstag", shape == "liongoat", shape == "frillram"
	local gait = ( wolf and 0.36 or ram and 0.27 or goat and 0.24 or 0.3 ) * ( 1 - 0.4 * st.still )
	local rx = wolf and 12 or ram and 8.5 or 10.5
	local ry = wolf and 3.4 or ram and 5.4 or 4.3
	local bx, by = wolf and -2 or -1, wolf and 1 or 0
	-- body: low and long for the wolf, round for the ram, deep-chested for the horse
	oval( bx, by, rx, ry, 0.14, true, 1.5 )
	-- four jointed legs; the still sign shortens the stride
	local hips = wolf and { -9, -6, 4, 7 } or ram and { -6.5, -3.5, 3, 6 } or { -8, -5, 4, 7 }
	local top = by + ry * 0.35
	local knee_y, hoof_y = by + 6, by + 11
	for i = 1, 4 do
		local phase = ( i % 2 ) * math.pi + ( i > 2 and math.pi or 0 )
		local swing = math.sin( age * gait + phase ) * ( 1 - 0.55 * st.still )
		local hip = hips[i]
		local knee = hip + swing * ( wolf and 2.2 or 2.6 )
		local hoof = hip + swing * ( wolf and 3.6 or 4.4 )
		local lift = math.max( 0, swing ) * ( wolf and 3 or ram and 5 or 4 )
		line( hip, top, knee, knee_y, i % 2 == 0 and 0.2 or 0.5, 1.6 )
		line( knee, knee_y, hoof, hoof_y - lift, 0.42, 1.4 )
		line( hoof - 1.4, hoof_y - lift, hoof + 1.8, hoof_y - lift, 0.8, 1.1 )
	end
	-- neck and a long head with a clear muzzle and ears (the wolf's head is low and forward)
	local hx = wolf and 10 or ram and 8.8 or 9.8
	local hy = wolf and -3.5 or stag and -9 or goat and -7.5 or ram and -6.5 or -9.5
	local shoulder_x, shoulder_y = bx + rx * 0.5, by - ry * 0.5
	line( shoulder_x - 1, shoulder_y, hx - 1, hy + 1, 0.55, 1.3 )
	line( shoulder_x + 2, shoulder_y + 2, hx + 1, hy + 2, 0.5, 1.3 )
	line( shoulder_x + 0.5, shoulder_y + 1, hx, hy + 3, 0.2, 1.7 )
	oval( hx, hy, wolf and 2.5 or 2.3, wolf and 2.1 or 2, 0.42, true, 1.4 )
	local mx, my = hx + ( wolf and 4.4 or 3.8 ), hy + ( wolf and 2 or 1.4 )
	line( hx + 0.8, hy + 1, mx, my, 0.7, 1.15 )
	line( mx, my, mx - 0.6, hy - 0.4, 0.55, 1.15 )
	oval( mx - 0.6, my - 0.3, 1.6, 1.1, 0.35, true, 1.4 )
	oval( mx + 0.6, my - 0.35, 0.45, 0.45, 0.9 )
	local ex, ey = hx + 0.6, hy - 0.5
	oval( ex, ey, 0.6, 0.6, 0.95 )
	if st.mimic then oval( ex, ey, 1.1, 1.1, 0.8 ) end
	if not ram and not goat then
		line( hx - 1, hy - 1.5, hx - 1.8, hy - 4.5, 0.75, 1.2 )
		line( hx + 0.5, hy - 1.8, hx + 0.7, hy - 4.2, 0.65, 1.2 )
	end
	-- the horse's mane runs down the neck; the goat's is a ruff
	if not wolf and not ram then
		for i = 0, 4 do
			local t = i / 4
			local nx = shoulder_x - 1 + ( hx - 2 - shoulder_x ) * t
			local ny = shoulder_y - 1 + ( hy + 1 - shoulder_y ) * t
			local sway = math.sin( age * 0.24 + i ) * 0.8 * ( 1 - 0.5 * st.still )
			line( nx, ny, nx - ( goat and 2.8 or 2.1 ) + sway, ny - 2.2, 0.48 + i * 0.07, 1.4 )
		end
	end
	-- tail: flowing for the horse, bushy for the wolf, a tuft for the goat, a flick for the stag or ram
	local tx, ty = bx - rx + 1, by - 1
	local wag = math.sin( age * 0.18 ) * 2 * ( 1 - 0.5 * st.still )
	if wolf then
		line( tx, ty, tx - 7, ty - 4 + wag, 0.5, 1.5 )
		line( tx, ty + 1, tx - 8, ty + 2 + wag, 0.4, 1.5 )
		for i = 0, 2 do line( tx - 2, ty - 1 + i, tx - 9 - i * 1.5, ty - 5 + i * 3 + wag, 0.55, 1.6 ) end
	elseif goat then
		line( tx, ty, tx - 5, ty - 2 + wag, 0.55, 1.4 )
		oval( tx - 6, ty - 2 + wag, 1.6, 1.6, 0.55, true, 1.5 )
	elseif stag or ram then
		line( tx, ty, tx - 4, ty - 3 + wag, 0.55, 1.4 )
	else
		line( tx, ty, tx - 7, ty - 3 + wag, 0.55, 1.4 )
		line( tx, ty + 1, tx - 6, ty + 5 + wag, 0.45, 1.4 )
		for i = 0, 2 do line( tx - 2, ty + 0.2 * i, tx - 8 - i * 2, ty - 2 + i * 2 + wag, 0.35 + i * 0.08, 1.7 ) end
	end
	-- species marks: scales, antlers and diamonds, a lion's mane and beard, a ram's fleece and curled horn
	if wolf then
		for row = 0, 1 do for col = 0, 4 do
			local sx, sy = bx - 7 + col * 3.5 + row * 1.8, by - 1 + row * 2.6
			line( sx - 1.2, sy - 1, sx, sy + 1, 0.6, 1.3 )
			line( sx, sy + 1, sx + 1.2, sy - 1, 0.6, 1.3 )
		end end
	elseif stag then
		for side = -1, 1, 2 do
			local ax = hx - 2 + side
			line( ax, hy - 2, ax - 2, hy - 9, 0.85, 1.2 )
			line( ax - 2, hy - 9, ax + side * 3, hy - 13, 0.8, 1.2 )
			line( ax - 1, hy - 6, ax + side * 4, hy - 8, 0.8, 1.2 )
		end
		for i = 0, 2 do
			local sx, sy = bx - 5 + i * 4, by - 1
			line( sx, sy, sx + 1.5, sy + 2, 0.8, 1.2 )
			line( sx + 1.5, sy + 2, sx, sy + 4, 0.8, 1.2 )
			line( sx, sy + 4, sx - 1.5, sy + 2, 0.8, 1.2 )
			line( sx - 1.5, sy + 2, sx, sy, 0.8, 1.2 )
		end
	elseif goat then
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			local sx, sy = hx - 3 + math.cos( a ) * 3.5, hy + 3 + math.sin( a ) * 4
			line( sx, sy, sx + math.cos( a ) * 2.2, sy + math.sin( a ) * 2.5, 0.65, 1.4 )
		end
		line( hx - 1, hy - 2, hx - 4, hy - 5, 0.85, 1.2 )
		line( hx - 4, hy - 5, hx - 6, hy - 4, 0.75, 1.2 )
		line( hx + 2.5, hy + 2, hx + 2, hy + 5, 0.7, 1.3 )
	elseif ram then
		oval( hx - 3, hy + 2, 5, 6, 0.4, false, 1.6 )
		for i = 0, 9 do
			local a = i / 10 * math.pi * 2
			local sx, sy = hx - 3 + math.cos( a ) * 4, hy + 2 + math.sin( a ) * 5
			line( sx, sy, sx + math.cos( a ) * 3, sy + math.sin( a ) * 3, 0.7, 1.4 )
		end
		for i = 0, 5 do
			local a = i / 6 * math.pi * 1.6
			local rr = 4 - i * 0.45
			line( hx - 1 + math.cos( a ) * rr, hy - 3 + math.sin( a ) * rr,
				hx - 1 + math.cos( a + 0.5 ) * rr, hy - 3 + math.sin( a + 0.5 ) * rr, 0.8, 1.2 )
		end
	end
	local tx2, ty2 = point( bx - rx - 4, by - 1 + wag )
	local fx, fy = point( 5, by + 11 )
	local cx, cy = point( bx, by - ry - 4 )
	breath( tx2, ty2, big, dir, age, element, fade, "tail" )
	breath( fx, fy, big, dir, age, element, fade, "foot" )
	cues( cx, cy, big, dir, age, element, st, fade )
end

function sculpture_bird( x, y, big, flip, age, element, fade, style )
	local st = style_of( style )
	local dir = flip and -1 or 1
	local bob = math.sin( age * 0.18 ) * 0.6
	local line, oval, point = sculpture_brush( x, y + bob * big, big, 0, flip, element, fade, st.strong * 0.18 )
	local flap = math.sin( age * 0.3 * ( 1 - 0.45 * st.still ) ) * ( 1 - 0.45 * st.still )
	-- far wing first, so the body hides its root
	local prev_x, prev_y
	for k = 0, 3 do
		local t = k / 3
		local tipx, tipy = -4 - k * 1.5, -3 - flap * 3 - t * 2
		line( -1, -1, tipx, tipy, 0.24 + t * 0.08, 1.5 )
		if prev_x then line( prev_x, prev_y, tipx, tipy, 0.2, 1.8 ) end
		prev_x, prev_y = tipx, tipy
	end
	-- body, neck and head
	oval( 0, 0, 5.2, 2.4, 0.2, true, 1.5 )
	line( 2.5, -1.5, 5, -2.4, 0.45, 1.3 )
	oval( 5.7, -2.8, 2.2, 1.9, 0.45, true, 1.4 )
	line( 7.3, -3.1, 10.3, -2.6, 0.9, 1.0 )
	line( 7.2, -2.2, 9.6, -1.9, 0.7, 1.05 )
	line( 9.6, -1.9, 10.1, -2.5, 0.6, 1.0 )
	oval( 6.2, -3.2, 0.55, 0.55, 0.95 )
	if st.mimic then oval( 6.2, -3.2, 1.05, 1.05, 0.8 ) end
	line( 5.2, -4.4, 4.3, -6.3, 0.65, 1.3 )
	line( 4.7, -4.5, 3.7, -5.8, 0.55, 1.3 )
	-- near wing: a fan of primaries with a scalloped trailing edge
	prev_x, prev_y = nil, nil
	for k = 0, 4 do
		local t = k / 4
		local tipx, tipy = -3 - k * 1.7, -5 - flap * 5 - k * 0.9
		line( 1, -1, tipx, tipy, 0.45 + t * 0.1, 1.35 )
		if prev_x then line( prev_x, prev_y, tipx, tipy, 0.3, 1.7 ) end
		prev_x, prev_y = tipx, tipy
	end
	line( 1, -1, -7, -9 - flap * 5, 0.7, 1.3 )
	-- tail fan, waving
	local wag = math.sin( age * 0.22 ) * 1.2 * ( 1 - 0.4 * st.still )
	line( -4.5, -0.6, -8.5, -2.6 + wag, 0.55, 1.4 )
	line( -4.5, 0.6, -8.5, 2.6 + wag, 0.45, 1.4 )
	for k = 0, 3 do
		local t = k / 3
		line( -4.5, 0, -9.5 - t * 1.5, -2.4 + t * 5 + wag * ( 0.4 + t * 0.6 ), 0.32 + t * 0.1, 1.5 )
	end
	-- feet tucked under the body
	line( 1.5, 2.1, 1.2, 3.5, 0.7, 1.1 )
	line( 3, 2.1, 3.2, 3.5, 0.65, 1.1 )
	local tx, ty = point( -9, 0.5 + wag )
	local wx, wy = point( -5, -8 - flap * 4 )
	local cx, cy = point( 0, -2 )
	breath( tx, ty, big, dir, age, element, fade, "tail" )
	breath( wx, wy, big, dir, age, element, fade, "wing" )
	cues( cx, cy, big, dir, age, element, st, fade )
end

function sculpture_fish( x, y, big, angle, age, element, fade, style )
	local st = style_of( style )
	local line, oval, point = sculpture_brush( x, y, big, angle, false, element, fade, st.strong * 0.18 )
	local dir = math.cos( angle or 0 ) >= 0 and 1 or -1
	oval( 0, 0, 7, 3.5, 0.2, true, 1.6 )
	oval( 4, -1, 0.7, 0.7, 0.95 )
	if st.mimic then oval( 4, -1, 1.2, 1.2, 0.8 ) end
	local tail = math.sin( age * 0.35 ) * 2
	line( -6, 0, -12, -4 + tail, 0.6, 1.4 )
	line( -12, -4 + tail, -12, 4 + tail, 0.45, 1.4 )
	line( -12, 4 + tail, -6, 0, 0.6, 1.4 )
	line( -3, -3, 0, -6, 0.65, 1.4 )
	line( 0, -6, 3, -3, 0.65, 1.4 )
	line( 0, 1, -3, 5, 0.6, 1.4 )
	line( -3, 5, 3, 2, 0.45, 1.4 )
	line( 3, -2, 2, 2, 0.7, 1.3 )
	local tx, ty = point( -12, 3 + tail )
	local cx, cy = point( 0, -2 )
	breath( tx, ty, big, dir, age, element, fade, "tail" )
	cues( cx, cy, big, dir, age, element, st, fade )
end

function sculpture_owlcat( x, y, big, flip, age, element, fade, style )
	local st = style_of( style )
	local dir = flip and -1 or 1
	local line, oval, point = sculpture_brush( x, y, big, 0, flip, element, fade, st.strong * 0.18 )
	oval( 0, 1, 8, 8, 0.25, true, 1.7 )
	for side = -1, 1, 2 do
		line( side * 3, -5, side * 6, -11, 0.65 ); line( side * 6, -11, side * 7, -3, 0.65 )
		oval( side * 3, -1, 2.5, 2.7, 0.8 )
		oval( side * 3, -1, 0.7, 1.1, 0.95 )
		if st.mimic then oval( side * 3, -1, 1.2, 1.5, 0.8 ) end
		local flap = math.sin( age * 0.2 ) * 3
		for k = 0, 2 do line( side * 6, 1, side * ( 11 + k ), 4 + flap + k, 0.4 + k * 0.1 ) end
		line( side * 2, 8, side * 2, 10, 0.8 )
		for k = 0, 2 do line( side * 5, 3, side * ( 10 + k ), 2 + k * 2, 0.7 ) end
	end
	line( -1, 1, 0, 3, 0.9 ); line( 0, 3, 1, 1, 0.9 )
	local wx, wy = point( 10, 4 + math.sin( age * 0.2 ) * 3 )
	local cx, cy = point( 0, -2 )
	breath( wx, wy, big, dir, age, element, fade, "wing" )
	cues( cx, cy, big, dir, age, element, st, fade )
end

function sculpture_dragon_head( x, y, big, angle, element, fade, style, age )
	age = age or 0
	local st = style_of( style )
	local line, oval, point = sculpture_brush( x, y, big, angle, false, element, fade, st.strong * 0.18 )
	local sway = math.sin( age * 0.12 ) * 0.6
	local jaw = math.sin( age * 0.18 ) * 0.5
	oval( 0, 0, 5, 4, 0.3, true )
	line( 1, -3, 10, -2, 0.7 ); line( 10, -2, 11, 1, 0.8 )
	line( 11, 1, 1, 3 + jaw, 0.7 ); line( 3, 1, 10, 1 + jaw, 0.9 )
	oval( 3, -2, 1, 1, 0.95 )
	if st.mimic then oval( 3, -2, 1.4, 1.4, 0.8 ) end
	for side = -1, 1, 2 do
		line( -1, side * 3, -6, side * ( 8 + sway ), 0.9 )
		line( -6, side * ( 8 + sway ), -9, side * 7, 0.8 )
		line( 7, side * 2, 5, side * 6, 0.65 )
		line( 5, side * 6, -2, side * 7, 0.65 )
	end
	local dir = math.cos( angle or 0 ) >= 0 and 1 or -1
	local cx, cy = point( 0, -2 )
	cues( cx, cy, big, dir, age, element, st, fade )
end

function sculpture_leech( x, y, big, age, element, fade, style )
	local st = style_of( style )
	local line, oval, point = sculpture_brush( x, y, big, 0, false, element, fade, st.strong * 0.18 )
	local nodes = {}
	for row = 0, 2 do for col = 0, 2 do
		local i = row * 3 + col + 1
		nodes[i] = { ( col - 1 ) * 8 + math.sin( age * 0.06 + i ) * 1.5,
			( row - 1 ) * 7 + math.cos( age * 0.05 + i ) * 1.5 }
	end end
	for row = 0, 2 do for col = 0, 2 do
		local q = nodes[row * 3 + col + 1]
		if col < 2 then local b = nodes[row * 3 + col + 2]; line( q[1], q[2], b[1], b[2], 0.55 ) end
		if row < 2 then local b = nodes[( row + 1 ) * 3 + col + 1]; line( q[1], q[2], b[1], b[2], 0.55 ) end
		if row ~= 1 or col ~= 1 then
			local tx, ty = q[1] + ( col - 1 ) * 5, q[2] + ( row - 1 ) * 5
			line( q[1], q[2], tx, ty, 0.7 ); oval( tx, ty, 1.3, 1.3, 0.8 )
		end
	end end
	local tip = nodes[9]
	local ax, ay = point( tip[1] + 5, tip[2] + 5 )
	local cx, cy = point( 0, 0 )
	breath( ax, ay, big, 1, age, element, fade, "tail" )
	cues( cx, cy, big, 1, age, element, st, fade )
end
