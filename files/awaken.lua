-- The seal awakens: when a drawn seal is recognized, its lines heat up in a wave from the top left to the bottom right - ink turning to the
-- element's color, white hot at the wave's front - and give off sparks. The sparks ride an unseen flow inside the ring,
-- a small 2D gas simulation (stable fluids, Stam), and the signs stir it as they would the spell: directional signs
-- (columns, levitation, regions) blow where they point, the spiraling wind whirls it, pulling and gathering signs draw it
-- in, dispersion and expansion drive it out, stillness calms it. Pure Lua: notebook.lua steps it and draws it.
--   awaken_new( strokes, seal, element ) -> state;  awaken_step( a ) -> false once over;  awaken_draw( a, s, z )

local N = 34              -- grid cells across the ring
local ITERATIONS = 14     -- pressure solve
local IGNITE = 70         -- frames the heat takes to cross the seal, top left to bottom right
local WAVE_X, WAVE_Y = math.cos( math.rad( 20 ) ), math.sin( math.rad( 20 ) ) -- the wave's way, 20 degrees below the right
local FRONT = 0.18        -- width of the wave's glowing front (share of the seal's width)
local SPARK_SHADOW = 0.6  -- how far a spark's shadow falls, down and to the right (page units)
local SOURCES_END = 130   -- the sigil breathes until then
local FADE_START = 165
local LENGTH = 205        -- the whole show, about 3.4 s
local MAX_SPARKS = 220
local DENSITY_KEEP = 0.988
local VELOCITY_KEEP = 0.995

-- how the element's gas moves by itself: rises (< 0), sinks (> 0), flickers
local BUOYANCY = { fire = -0.035, plasma = -0.03, phantasm = -0.03, light = -0.02, beam = -0.02, steam = -0.03, smoke = -0.02,
	water = 0.02, ice = 0.015, earth = 0.03, sand = 0.03, stone = 0.035 }
local TURBULENT = { wind = 0.06, air = 0.05, thunder = 0.08, flicker = 0.07, vacuum = 0.04 }

local INWARD = { pull = true, gather = true, contain = true, envelop = true, refuse = true }
local OUTWARD = { grow = true, launch = true, gust = true }
local CALM = { still = true, hold = true, solid = true, bound = true }

local function clamp( v, lo, hi ) return math.max( lo, math.min( hi, v ) ) end

local function grid( v )
	local t = {}
	for i = 0, ( N + 2 ) * ( N + 2 ) - 1 do t[i] = v or 0 end
	return t
end
local function at( x, y ) return y * ( N + 2 ) + x end

-- a value between the cells (bilinear)
local function sample( f, x, y )
	x, y = clamp( x, 0.5, N + 0.5 ), clamp( y, 0.5, N + 0.5 )
	local i, j = math.floor( x ), math.floor( y )
	local s, t = x - i, y - j
	return ( 1 - t ) * ( ( 1 - s ) * f[at( i, j )] + s * f[at( i + 1, j )] ) + t * ( ( 1 - s ) * f[at( i, j + 1 )] + s * f[at( i + 1, j + 1 )] )
end

local function advect( a, f )
	local out = a.tmp
	local u, v, solid = a.u, a.v, a.solid
	for y = 1, N do
		for x = 1, N do
			local k = at( x, y )
			out[k] = solid[k] and 0 or sample( f, x - u[k], y - v[k] )
		end
	end
	for y = 1, N do for x = 1, N do local k = at( x, y ); f[k] = out[k] end end
end

-- makes the flow free of divergence: gas can't pile up or vanish, it swirls
local function project( a )
	local u, v, p, div, solid = a.u, a.v, a.p, a.div, a.solid
	for y = 1, N do
		for x = 1, N do
			local k = at( x, y )
			div[k] = solid[k] and 0 or -0.5 * ( u[k + 1] - u[k - 1] + v[k + N + 2] - v[k - N - 2] )
			p[k] = 0
		end
	end
	for _ = 1, ITERATIONS do
		for y = 1, N do
			for x = 1, N do
				local k = at( x, y )
				if not solid[k] then
					-- a wall's pressure is the cell's own (no flow through it)
					local l, r, d, t = k - 1, k + 1, k - N - 2, k + N + 2
					local pk = p[k]
					p[k] = ( div[k] + ( solid[l] and pk or p[l] ) + ( solid[r] and pk or p[r] ) + ( solid[d] and pk or p[d] )
						+ ( solid[t] and pk or p[t] ) ) / 4
				end
			end
		end
	end
	for y = 1, N do
		for x = 1, N do
			local k = at( x, y )
			if solid[k] then
				u[k], v[k] = 0, 0
			else
				local pk = p[k]
				local function pr( j ) return solid[j] and pk or p[j] end
				u[k] = u[k] - 0.5 * ( pr( k + 1 ) - pr( k - 1 ) )
				v[k] = v[k] - 0.5 * ( pr( k + N + 2 ) - pr( k - N - 2 ) )
			end
		end
	end
end

-- the strokes as one fuse: every dot's place and how far along the drawing it lies
local function fuse( strokes )
	local dots, total = {}, 0
	for _, stroke in ipairs( strokes ) do
		local last
		for _, p in ipairs( stroke ) do
			if last then
				local d = math.sqrt( ( p.x - last.x ) ^ 2 + ( p.y - last.y ) ^ 2 )
				local n = math.max( 1, math.floor( d / 1.5 ) )
				for i = 1, n do
					total = total + d / n
					dots[#dots + 1] = { x = last.x + ( p.x - last.x ) * i / n, y = last.y + ( p.y - last.y ) * i / n, at = total }
				end
			else
				dots[#dots + 1] = { x = p.x, y = p.y, at = total }
			end
			last = p
		end
		total = total + 12 -- the fire jumps from one line to the next
	end
	-- the wave runs a little downwards: from the top left to the bottom right
	local minx, maxx = math.huge, -math.huge
	for _, d in ipairs( dots ) do
		d.along = d.x * WAVE_X + d.y * WAVE_Y
		minx, maxx = math.min( minx, d.along ), math.max( maxx, d.along )
	end
	for _, d in ipairs( dots ) do d.at = ( d.along - minx ) / math.max( maxx - minx, 1 ) end
	return dots
end

-- 'seal': parse_seal's tree (nil for a seal known only as a whole); 'element': the spell's element key
function awaken_new( strokes, seal, element )
	local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
	for _, stroke in ipairs( strokes ) do
		for _, p in ipairs( stroke ) do
			minx, maxx, miny, maxy = math.min( minx, p.x ), math.max( maxx, p.x ), math.min( miny, p.y ), math.max( maxy, p.y )
		end
	end
	local ring = seal and seal.ring or { x = ( minx + maxx ) / 2, y = ( miny + maxy ) / 2, r = math.max( maxx - minx, maxy - miny ) / 2 }
	local e = DICTIONARY_ELEMENTS and DICTIONARY_ELEMENTS[element]
	local c = e and e.color or { 200, 220, 255 }
	local a = {
		frame = 0, ring = ring, cell = 2 * ring.r / N, color = { c[1] / 255, c[2] / 255, c[3] / 255 },
		dots = fuse( strokes ), sparks = {}, seed = 12345,
		u = grid(), v = grid(), d = grid(), p = grid(), div = grid(), tmp = grid(), solid = {},
		buoyancy = BUOYANCY[element] or -0.01, turbulence = TURBULENT[element] or 0,
		sources = {}, jets = {}, twinkles = {}, radial = 0, whirl = 0, calm = 0,
		blast = element == "shockwave" and 1 or 0,
	}
	-- the ring is the vessel's wall
	for y = 0, N + 1 do
		for x = 0, N + 1 do
			local dx, dy = x - ( N + 1 ) / 2, y - ( N + 1 ) / 2
			a.solid[at( x, y )] = dx * dx + dy * dy > ( N / 2 - 0.5 ) ^ 2 or nil
		end
	end
	local function place( sym )
		local r = sym.dist * ring.r
		return ring.x + math.cos( sym.angle ) * r, ring.y + math.sin( sym.angle ) * r
	end
	for _, sym in ipairs( seal and seal.symbols or {} ) do
		local x, y = place( sym )
		local size = math.max( sym.size or 0.2, 0.1 )
		if sym.kind == "sigil" then
			a.sources[#a.sources + 1] = { x = x, y = y, w = size }
		else
			local def = DICTIONARY_SIGNS and DICTIONARY_SIGNS[sym.key] or {}
			local inverted = sym.inverted and def.invertible ~= false
			local effect = ( inverted and def.inverted ) or def
			local behavior = effect.behavior
			local w = clamp( size / 0.25, 0.5, 1.8 )
			if def.type == "directional" then
				local d = sym.dir or ( sym.angle + math.pi )
				a.jets[#a.jets + 1] = { x = x, y = y, dx = math.cos( d ), dy = math.sin( d ), w = w }
			elseif behavior == "whirl" then
				a.whirl = a.whirl + ( sym.mirror and -1 or 1 ) * w
			elseif INWARD[behavior] or ( effect.condense or 0 ) > 0 then
				a.radial = a.radial - w
			elseif OUTWARD[behavior] or effect.form == "dispersion" then
				a.radial = a.radial + w
			elseif CALM[behavior] then
				a.calm = a.calm + w
			else
				a.twinkles[#a.twinkles + 1] = { x = x, y = y, w = w, phase = #a.twinkles * 1.7 }
			end
		end
	end
	if #a.sources == 0 then a.sources[1] = { x = ring.x, y = ring.y, w = 0.5 } end
	return a
end

local function random( a )
	a.seed = ( a.seed * 1103515245 + 12345 ) % 2147483648
	return a.seed / 2147483648
end

-- page coordinates -> grid
local function to_grid( a, x, y )
	return ( x - a.ring.x + a.ring.r ) / a.cell + 0.5, ( y - a.ring.y + a.ring.r ) / a.cell + 0.5
end

-- adds to the cells around a point: density 'dd', push ( fu, fv ), within 'radius' cells
local function splat( a, x, y, radius, dd, fu, fv )
	local gx, gy = to_grid( a, x, y )
	for j = math.max( 1, math.floor( gy - radius ) ), math.min( N, math.ceil( gy + radius ) ) do
		for i = math.max( 1, math.floor( gx - radius ) ), math.min( N, math.ceil( gx + radius ) ) do
			local k = at( i, j )
			local q = 1 - ( ( i - gx ) ^ 2 + ( j - gy ) ^ 2 ) / ( radius * radius )
			if q > 0 and not a.solid[k] then
				a.d[k] = a.d[k] + dd * q
				a.u[k] = a.u[k] + fu * q
				a.v[k] = a.v[k] + fv * q
			end
		end
	end
end

local function spark( a, x, y, vx, vy, life )
	if #a.sparks >= MAX_SPARKS then table.remove( a.sparks, 1 ) end
	a.sparks[#a.sparks + 1] = { x = x, y = y, vx = vx, vy = vy, life = life, age = 0 }
end

function awaken_step( a )
	a.frame = a.frame + 1
	local f = a.frame
	if f > LENGTH then return false end
	local u, v, d = a.u, a.v, a.d
	local c = ( N + 1 ) / 2

	-- the hot lines throw sparks: many at the wave's front, a few from what glows behind it
	local head = f / IGNITE * ( 1 + FRONT )
	if f <= FADE_START then
		for _, dot in ipairs( a.dots ) do
			local behind = head - dot.at
			if behind >= 0 then
				local chance = behind < FRONT and 0.12 or 0.012
				if random( a ) < chance then
					spark( a, dot.x, dot.y, ( random( a ) - 0.5 ) * 0.5, ( random( a ) - 0.5 ) * 0.5 - 0.15, 25 + random( a ) * 35 )
				end
			end
		end
	end

	-- sources: the sigils breathe out, the signs push
	local start = IGNITE * 0.3
	if f >= start then
		local grow = clamp( ( f - start ) / 25, 0, 1 )
		local breath = f <= SOURCES_END and grow or 0
		for _, s in ipairs( a.sources ) do
			local wobble = f * 0.13 + s.x
			splat( a, s.x, s.y, 2.5 + 3 * s.w, 0.1 * breath, math.cos( wobble ) * 0.05 * breath, math.sin( wobble ) * 0.05 * breath )
		end
		if a.blast > 0 and f == math.floor( start ) + 1 then
			for k = 0, 15 do
				local ang = k * math.pi / 8
				splat( a, a.ring.x + math.cos( ang ) * a.cell * 3, a.ring.y + math.sin( ang ) * a.cell * 3, 3, 0.6, math.cos( ang ) * 1.2, math.sin( ang ) * 1.2 )
			end
		end
		local push = f <= SOURCES_END + 20 and grow or grow * 0.3
		for _, j in ipairs( a.jets ) do
			local pulse = 0.75 + 0.25 * math.sin( f * 0.2 )
			splat( a, j.x, j.y, 3.2, 0.1 * breath * j.w, j.dx * 0.3 * push * j.w * pulse, j.dy * 0.3 * push * j.w * pulse )
			if random( a ) < 0.12 * push then
				spark( a, j.x + ( random( a ) - 0.5 ) * 6, j.y + ( random( a ) - 0.5 ) * 6, j.dx * 0.8, j.dy * 0.8, 30 )
			end
		end
		for _, t in ipairs( a.twinkles ) do
			local beat = math.max( 0, math.sin( f * 0.15 + t.phase ) )
			splat( a, t.x, t.y, 2.4, 0.1 * beat * breath * t.w, 0, 0 )
		end
		-- fields over the whole ring: whirl, in and out, buoyancy, flicker
		local whirl, radial = a.whirl * 0.012 * push, a.radial * 0.01 * push
		local calm = 1 - clamp( a.calm * 0.04, 0, 0.3 )
		for y = 1, N do
			for x = 1, N do
				local k = at( x, y )
				if not a.solid[k] then
					local dx, dy = x - c, y - c
					local r = math.sqrt( dx * dx + dy * dy ) + 1e-6
					local fall = r / c
					u[k] = ( u[k] - dy / r * whirl * fall + dx / r * radial ) * calm
					v[k] = ( v[k] + dx / r * whirl * fall + dy / r * radial + a.buoyancy * math.min( d[k], 1.5 ) ) * calm
					if a.turbulence > 0 then
						u[k] = u[k] + math.sin( y * 0.7 + f * 0.11 ) * a.turbulence * 0.3
						v[k] = v[k] + math.cos( x * 0.7 - f * 0.09 ) * a.turbulence * 0.3
					end
				end
			end
		end
	end

	-- the flow
	for i = 0, ( N + 2 ) * ( N + 2 ) - 1 do
		u[i], v[i] = clamp( u[i] * VELOCITY_KEEP, -2, 2 ), clamp( v[i] * VELOCITY_KEEP, -2, 2 )
	end
	project( a )
	local u0, v0 = a.u, a.v
	-- velocity carries itself: copy first, advect from the copy
	a.u, a.v = {}, {}
	for i = 0, ( N + 2 ) * ( N + 2 ) - 1 do a.u[i], a.v[i] = u0[i], v0[i] end
	local cu, cv = a.u, a.v
	a.u, a.v = u0, v0
	advect( a, cu ); advect( a, cv )
	a.u, a.v = cu, cv
	project( a )
	advect( a, a.d )
	local keep = f > FADE_START and 0.93 or DENSITY_KEEP
	for i = 0, ( N + 2 ) * ( N + 2 ) - 1 do d[i] = math.min( d[i] * keep, 3 ) end
	a.d = d

	-- sparks ride the flow
	for i = #a.sparks, 1, -1 do
		local s = a.sparks[i]
		s.age = s.age + 1
		if s.age >= s.life then
			table.remove( a.sparks, i )
		else
			local gx, gy = to_grid( a, s.x, s.y )
			s.vx = s.vx * 0.9 + sample( a.u, gx, gy ) * a.cell * 0.12
			s.vy = s.vy * 0.9 + sample( a.v, gx, gy ) * a.cell * 0.12
			s.x, s.y = s.x + s.vx, s.y + s.vy
		end
	end
	return true
end

-- Draws onto a page surface (notebook.lua: s:image( px, py, file, z, color, alpha, sx, sy )); 'z': above the ink
function awaken_draw( a, s, z )
	local f = a.frame
	local fade = f > FADE_START and clamp( 1 - ( f - FADE_START ) / ( LENGTH - FADE_START ), 0, 1 ) or 1
	local col = a.color
	local function hot( t ) -- the element's color, whiter where it burns brighter
		t = clamp( t, 0, 1 )
		return { col[1] + ( 1 - col[1] ) * t, col[2] + ( 1 - col[2] ) * t, col[3] + ( 1 - col[3] ) * t }
	end
	local img, half = AWAKEN_GLOW_IMAGE, AWAKEN_GLOW_SIZE / 2

	-- the lines: behind the wave they glow in the element's color (a slow shimmer), at its front they burn white
	local head = f / IGNITE * ( 1 + FRONT )
	local lk = 3.4 / AWAKEN_GLOW_SIZE
	for n, dot in ipairs( a.dots ) do
		local behind = head - dot.at
		if behind > -0.02 then
			local heat = clamp( behind / FRONT, 0, 1 )      -- 0 at the front, 1 well behind it
			local front = 1 - heat
			local shimmer = 0.85 + 0.15 * math.sin( f * 0.12 + n * 0.37 )
			local kk = lk * ( 1 + front * 0.8 )
			local alpha = clamp( ( behind + 0.02 ) / 0.04, 0, 1 ) * ( 0.75 + 0.25 * front ) * shimmer * fade
			s:image( dot.x - half * kk, dot.y - half * kk, img, z, hot( front * 0.85 ), alpha, kk, kk )
			if front > 0.3 and n % 3 == 0 then -- a soft halo around the burning front
				local hk = 11 * front / AWAKEN_GLOW_SIZE
				s:image( dot.x - half * hk, dot.y - half * hk, img, z + 1, hot( 0.3 ), 0.35 * front * fade, hk, hk )
			end
		end
	end

	-- sparks, cooling and shrinking as they fly: square pixels (NOTEBOOK_INK_IMAGE is 2x2) with a small shadow of the
	-- element's color down and to the right, so a light spark shows on light paper too
	local shadow = { col[1] * 0.25, col[2] * 0.2, col[3] * 0.25 }
	for _, sp in ipairs( a.sparks ) do
		local t = 1 - sp.age / sp.life
		local size = 1 + 1.5 * t
		local x, y, k = sp.x - size / 2, sp.y - size / 2, size / 2
		local alpha = math.min( 1, t * 1.5 ) * fade
		s:image( x + SPARK_SHADOW, y + SPARK_SHADOW, NOTEBOOK_INK_IMAGE, z - 1, shadow, 0.7 * alpha, k, k )
		s:image( x, y, NOTEBOOK_INK_IMAGE, z - 2, hot( 0.4 * t ), alpha, k, k )
	end
end
