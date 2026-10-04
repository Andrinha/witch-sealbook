-- Creature silhouettes in particles, independent of the symbols written on paper.
-- Coordinates face right; the caller supplies scale, direction and animation age.
function sculpture_brush( x, y, scale, angle, flip, element, fade )
	local cs, sn = math.cos( angle or 0 ), math.sin( angle or 0 )
	local dir = flip and -1 or 1
	local function point( u, v )
		u, v = u * scale * dir, v * scale
		return x + u * cs - v * sn, y + u * sn + v * cs
	end
	local function line( ax, ay, bx, by, white )
		local px, py = point( ax, ay )
		local qx, qy = point( bx, by )
		fx_line( px, py, qx, qy, effect_color( element, math.min( 1, white or 0.4 ), ( fade or 1 ) * 0.8 ), 1, 0.06 )
	end
	local function oval( cx, cy, rx, ry, white, filled )
		if filled then
			for row = -ry, ry, 1.5 do
				local w = rx * math.sqrt( math.max( 0, 1 - ( row / ry ) ^ 2 ) )
				line( cx - w, cy + row, cx + w, cy + row, white )
			end
		end
		local n = math.max( 12, math.ceil( ( rx + ry ) * 2 ) )
		for i = 1, n do
			local a, b = ( i - 1 ) / n * math.pi * 2, i / n * math.pi * 2
			line( cx + math.cos( a ) * rx, cy + math.sin( a ) * ry,
				cx + math.cos( b ) * rx, cy + math.sin( b ) * ry, ( white or 0.4 ) + 0.15 )
		end
	end
	return line, oval
end

function sculpture_quadruped( shape, x, y, big, dir, age, element, fade )
	local line, oval = sculpture_brush( x, y, big, 0, dir < 0, element, fade )
	local wolf, goat, ram, stag = shape == "scalewolf", shape == "liongoat", shape == "frillram", shape == "torchstag"
	local rx, ry = wolf and 10 or ram and 10 or 11, ram and 6 or 4.5
	oval( -2, 0, rx, ry, 0.15, true )
	-- Four jointed legs alternate diagonally, keeping the feet below the body.
	for i = 1, 4 do
		local hip = i <= 2 and -9 or 5
		local step = math.sin( age * ( wolf and 0.36 or 0.3 ) + ( i % 2 ) * math.pi + ( i > 2 and math.pi or 0 ) )
		local knee = hip + step * 3
		local hoof = hip + step * 6
		line( hip, 3, knee, 7, i % 2 == 0 and 0.2 or 0.55 )
		line( knee, 7, hoof, 11 - math.max( 0, step ) * 3, 0.45 )
		line( hoof - 1, 11 - math.max( 0, step ) * 3, hoof + 1.5, 11 - math.max( 0, step ) * 3, 0.8 )
	end
	local hx, hy = wolf and 11 or ram and 9 or 10, wolf and -3 or ram and -4 or -10
	line( 6, -1, hx - 1, hy, 0.65 )
	line( 4, -3, hx - 3, hy - 2, 0.4 )
	oval( hx, hy, wolf and 4 or 3, 2.7, 0.35, true )
	line( hx + 1, hy + 1, hx + 6, hy + 1.5, 0.8 )
	line( hx + 6, hy + 1.5, hx + 5, hy - 1, 0.55 )
	oval( hx + 1, hy - 1, .65, .65, 0.95 )
	line( hx - 1, hy - 2, hx - 2, hy - 6, 0.75 )
	line( hx - 2, hy - 6, hx + 1, hy - 3, 0.6 )
	-- Species details: scales and bushy tail, deer antlers, mane, or fleece ruff.
	if wolf then
		for row = 0, 1 do for col = 0, 4 do
			local sx, sy = -9 + col * 4 + row * 2, -2 + row * 3
			line( sx - 1.5, sy - 1, sx, sy + 1, 0.65 )
			line( sx, sy + 1, sx + 1.5, sy - 1, 0.65 )
		end end
		local wag = math.sin( age * .18 ) * 2
		line( -11, 0, -18, -3 + wag, 0.5 )
		line( -18, -3 + wag, -22, -1 + wag, 0.7 )
		line( -11, 2, -18, 1 + wag, 0.3 )
	elseif stag then
		for side = -1, 1, 2 do
			local ax = hx - 2 + side
			line( ax, hy - 2, ax - 2, hy - 9, .85 )
			line( ax - 2, hy - 9, ax + side * 3, hy - 13, .8 )
			line( ax - 1, hy - 6, ax + side * 4, hy - 8, .8 )
		end
		for i = 0, 2 do
			local sx = -7 + i * 4
			line( sx, -2, sx + 1.5, 0, .8 ); line( sx + 1.5, 0, sx, 2, .8 )
			line( sx, 2, sx - 1.5, 0, .8 ); line( sx - 1.5, 0, sx, -2, .8 )
		end
		line( -12, -1, -15, -4, .7 )
	elseif goat or ram then
		oval( hx - 3, hy + 2, ram and 5 or 4, ram and 6 or 5, .45 )
		for i = 0, 9 do
			local a = i / 10 * math.pi * 2
			local sx, sy = hx - 3 + math.cos( a ) * 4, hy + 2 + math.sin( a ) * 5
			line( sx, sy, sx + math.cos( a ) * ( ram and 3 or 2 ), sy + math.sin( a ) * 3, .7 )
		end
		oval( hx - 2, hy - 3, 2.5, 2.5, .8 )
		line( hx + 2, hy + 2, hx + 1, hy + 5, .75 )
		line( -12, 0, -16, -2, .6 )
		if goat then oval( -17, -2, 1.7, 1.7, .55, true ) end
	else
		for i = 0, 4 do line( 6, -4 - i, 8 - i, -5 - i, .5 ) end
		local wag = math.sin( age * .17 ) * 2
		for i = 0, 2 do line( -12, -1, -17 - i, 5 + i + wag, .3 + i * .15 ) end
	end
end

function sculpture_bird( x, y, big, flip, age, element, fade )
	local line, oval = sculpture_brush( x, y, big, 0, flip, element, fade )
	oval( 0, 0, 5, 2.2, .4, true )
	oval( 5, -2, 2, 2, .7, true )
	line( 7, -2, 9, -1.5, .95 )
	for k = 0, 3 do
		line( -3, 1, -8 - k, k - 1, .35 + k * .1 )
		local wing = math.sin( age * .25 ) * ( 8 + k * 1.5 )
		line( 0, 0, -3 - k * 1.5, -wing, .45 + k * .1 )
		line( -3 - k * 1.5, -wing, -6 - k * 1.5, -wing + 3, .6 )
	end
end

function sculpture_fish( x, y, big, angle, age, element, fade )
	local line, oval = sculpture_brush( x, y, big, angle, false, element, fade )
	oval( 0, 0, 7, 3.5, .2, true )
	oval( 4, -1, .7, .7, .95 )
	local tail = math.sin( age * .35 ) * 2
	line( -6, 0, -12, -4 + tail, .6 ); line( -12, -4 + tail, -12, 4 + tail, .45 )
	line( -12, 4 + tail, -6, 0, .6 )
	line( -3, -3, 0, -6, .65 ); line( 0, -6, 3, -3, .65 )
	line( 0, 1, -3, 5, .6 ); line( -3, 5, 3, 2, .45 )
	line( 3, -2, 2, 2, .7 )
end

function sculpture_owlcat( x, y, big, flip, age, element, fade )
	local line, oval = sculpture_brush( x, y, big, 0, flip, element, fade )
	oval( 0, 1, 8, 8, .25, true )
	for dir = -1, 1, 2 do
		line( dir * 3, -5, dir * 6, -11, .65 ); line( dir * 6, -11, dir * 7, -3, .65 )
		oval( dir * 3, -1, 2.5, 2.7, .8 )
		oval( dir * 3, -1, .7, 1.1, .95 )
		local flap = math.sin( age * .2 ) * 3
		for k = 0, 2 do line( dir * 6, 1, dir * ( 11 + k ), 4 + flap + k, .4 + k * .1 ) end
		line( dir * 2, 8, dir * 2, 10, .8 )
		for k = 0, 2 do line( dir * 5, 3, dir * ( 10 + k ), 2 + k * 2, .7 ) end
	end
	line( -1, 1, 0, 3, .9 ); line( 0, 3, 1, 1, .9 )
end

function sculpture_dragon_head( x, y, big, angle, element, fade )
	local line, oval = sculpture_brush( x, y, big, angle, false, element, fade )
	oval( 0, 0, 5, 4, .3, true )
	line( 1, -3, 10, -2, .7 ); line( 10, -2, 11, 1, .8 )
	line( 11, 1, 1, 3, .7 ); line( 3, 1, 10, 1, .9 )
	oval( 3, -2, 1, 1, .95 )
	for dir = -1, 1, 2 do
		line( -1, dir * 3, -6, dir * 8, .9 )
		line( -6, dir * 8, -9, dir * 7, .8 )
		line( 7, dir * 2, 5, dir * 6, .65 )
		line( 5, dir * 6, -2, dir * 7, .65 )
	end
end

function sculpture_leech( x, y, big, age, element, fade )
	local line, oval = sculpture_brush( x, y, big, 0, false, element, fade )
	local nodes = {}
	for row = 0, 2 do for col = 0, 2 do
		local i = row * 3 + col + 1
		nodes[i] = { ( col - 1 ) * 8 + math.sin( age * .06 + i ) * 1.5,
			( row - 1 ) * 7 + math.cos( age * .05 + i ) * 1.5 }
	end end
	for row = 0, 2 do for col = 0, 2 do
		local q = nodes[row * 3 + col + 1]
		if col < 2 then local b = nodes[row * 3 + col + 2]; line( q[1], q[2], b[1], b[2], .55 ) end
		if row < 2 then local b = nodes[( row + 1 ) * 3 + col + 1]; line( q[1], q[2], b[1], b[2], .55 ) end
		if row ~= 1 or col ~= 1 then
			local tx, ty = q[1] + ( col - 1 ) * 5, q[2] + ( row - 1 ) * 5
			line( q[1], q[2], tx, ty, .7 ); oval( tx, ty, 1.3, 1.3, .8 )
		end
	end end
end
