-- Original CPU gas solver; force/pressure/velocity/dye order inspired by
-- Pavel Dobryakov's WebGL Fluid Simulation. Velocity is in cells/second.
local DEFAULT_TUNING = { drift = 0.06, vorticity = 5, eddy_force = 160,
	heat_decay = 1.4, velocity_decay = 0.35, inlet_heat = 72, density_cap = 3.2,
	inlet_width = 1.25, inlet_depth = 1.7, launch_impulse = 55,
	packet_drag = 1.6, emit_frames = 8, vorticity_decay = 1.2,
	front_cells = 10, eddy_radius = 1.2, eddy_separation = 1.5,
	buoyancy = 12, max_velocity = 90 }

local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local abs, sqrt, exp = math.abs, math.sqrt, math.exp

-- Each model closes over its own grid and settings. Sharing a model across
-- spells is safe; all changing fields, masks and work buffers belong to states.
local function create( options )
	options = options or {}
	local F = { width = options.width or 48, height = options.height or 28,
		iterations = options.iterations or 24, cell_size = options.cell_size,
		max_courant = options.max_courant or 0.65, source = options.source, tuning = {} }
	assert( F.width >= 2 and F.width == floor( F.width ), "fluid width must be an integer >= 2" )
	assert( F.height >= 2 and F.height == floor( F.height ), "fluid height must be an integer >= 2" )
	assert( F.iterations >= 1 and F.iterations == floor( F.iterations ), "fluid iterations must be a positive integer" )
	assert( not F.cell_size or F.cell_size > 0, "fluid cell_size must be positive" )
	assert( not F.source or type( F.source ) == "function", "fluid source must be a function" )
	assert( F.max_courant > 0 and F.max_courant < math.huge, "fluid max_courant must be finite and positive" )
	for name, value in pairs( DEFAULT_TUNING ) do F.tuning[name] = value end
	for name, value in pairs( options.tuning or {} ) do
		assert( DEFAULT_TUNING[name] ~= nil and type( value ) == "number", "unknown or nonnumeric fluid tuning: " .. name )
		F.tuning[name] = value
	end
	local W, H = F.width, F.height
	local N = W * H
	local left, right, top, bottom = {}, {}, {}, {}
	local flat_left, flat_right, flat_top, flat_bottom = {}, {}, {}, {}
	for y = 1, H do for x = 1, W do
		local i = ( y - 1 ) * W + x
		left[i], right[i] = x > 1 and i - 1 or 0, x < W and i + 1 or 0
		top[i], bottom[i] = y > 1 and i - W or 0, y < H and i + W or 0
		flat_left[i], flat_right[i] = left[i] == 0 and i or left[i], right[i] == 0 and i or right[i]
		flat_top[i], flat_bottom[i] = top[i] == 0 and i or top[i], bottom[i] == 0 and i or bottom[i]
	end end
	local function clamp( v, lo, hi ) return max( lo, min( hi, v ) ) end
	local function array()
		local a = {}
		for i = 1, N do a[i] = 0 end
		return a
	end

	-- Scratch storage belongs to a shot, never to the module: interleaved shots
	-- must not overwrite each other's fields. Every pass initializes its outputs.
	local function buffer( s, name )
		if not s[name] then s[name] = array() end
		return s[name]
	end

	function F.new( p, seed, prepared )
		local s = prepared or { model = F, d = array(), u = array(), v = array(), solid = {}, curl = array() }
		assert( s.model == F, "prepared fluid state belongs to another model" )
		if prepared then
			for i = 1, N do s.d[i], s.u[i], s.v[i], s.curl[i], s.solid[i] = 0, 0, 0, 0, false end
			s.stencil_ready, s.stencil_dirty, s.raycast, s.meter = false, true, nil, nil
			s.air_rows_l, s.air_rows_r, s.terrain, s.air_bounds, s.open_air, s.row_runs = nil, nil, nil, nil, nil, nil
		end
		s.cell, s.seed, s.mask_head = p.cell or F.cell_size or max( 2, ( p.length + 16 ) / W ), seed or 1, p.head or 0
		return s
	end

	function F.world( s, p, x, y )
		local along = p.head + ( x - ( W - F.tuning.front_cells ) ) * s.cell
		local across = ( y - ( H + 1 ) / 2 ) * s.cell
		return p.ox + p.dx * along - p.dy * across, p.oy + p.dy * along + p.dx * across, along
	end

	local function sample( a, solid, x, y, open_air )
		if x < 1 or x > W or y < 1 or y > H then return 0 end
		-- Bilinear support extends into neighboring cells. A point inside a solid
		-- cell must still be zero, even if one interpolation donor is hot air.
		if not open_air then
			local nearest = ( floor( y + 0.5 ) - 1 ) * W + floor( x + 0.5 )
			if solid[nearest] then return 0 end
		end
		local ix, iy = floor( x ), floor( y )
		local fx, fy = x - ix, y - iy
		local i = ( iy - 1 ) * W + ix
		local j, k = ix < W and i + 1 or i, iy < H and i + W or i
		local l = ix < W and k + 1 or k
		local ai, aj, ak, al = a[i], a[j], a[k], a[l]
		if not open_air then
			ai, aj = solid[i] and 0 or ai, solid[j] and 0 or aj
			ak, al = solid[k] and 0 or ak, solid[l] and 0 or al
		end
		return ( ai * ( 1 - fx ) + aj * fx ) * ( 1 - fy )
			+ ( ak * ( 1 - fx ) + al * fx ) * fy
	end

	function F.density( s, p, x, y )
		local dx, dy = x - p.ox, y - p.oy
		local along, across = dx * p.dx + dy * p.dy, -dx * p.dy + dy * p.dx
		return sample( s.d, s.solid, ( along - p.head ) / s.cell + W - F.tuning.front_cells,
			across / s.cell + ( H + 1 ) / 2, s.open_air )
	end

	local function sample_velocity( s, x, y )
		if x < 1 or x > W or y < 1 or y > H then return 0, 0 end
		local solid = s.solid
		if not s.open_air then
			local nearest = ( floor( y + 0.5 ) - 1 ) * W + floor( x + 0.5 )
			if solid[nearest] then return 0, 0 end
		end
		-- Both velocity components use the same donors and interpolation weights.
		local ix, iy = floor( x ), floor( y )
		local fx, fy = x - ix, y - iy
		local i = ( iy - 1 ) * W + ix
		local j, k = ix < W and i + 1 or i, iy < H and i + W or i
		local l = ix < W and k + 1 or k
		local u, v = s.u, s.v
		local ui, uj, uk, ul = u[i], u[j], u[k], u[l]
		local vi, vj, vk, vl = v[i], v[j], v[k], v[l]
		if not s.open_air then
			ui, uj, uk, ul = solid[i] and 0 or ui, solid[j] and 0 or uj, solid[k] and 0 or uk, solid[l] and 0 or ul
			vi, vj, vk, vl = solid[i] and 0 or vi, solid[j] and 0 or vj, solid[k] and 0 or vk, solid[l] and 0 or vl
		end
		return ( ui * ( 1 - fx ) + uj * fx ) * ( 1 - fy ) + ( uk * ( 1 - fx ) + ul * fx ) * fy,
			( vi * ( 1 - fx ) + vj * fx ) * ( 1 - fy ) + ( vk * ( 1 - fx ) + vl * fx ) * fy
	end

	function F.flow( s, p, x, y )
		local u, v = sample_velocity( s, x, y )
		return u - ( p.frame_velocity or p.velocity or p.speed ) * F.tuning.drift / s.cell, v
	end

	function F.heat( s, x, y ) return sample( s.d, s.solid, x, y, s.open_air ) end

	-- A reusable local-grid source: Gaussian density/velocity increments, clipped
	-- to fluid cells. The caller scales rates by dt; no fire entities are created.
	function F.splat( s, x, y, radius, density, u, v )
		assert( radius > 0, "fluid splat radius must be positive" )
		for gy = max( 1, floor( y - radius * 3 ) ), min( H, ceil( y + radius * 3 ) ) do
			for gx = max( 1, floor( x - radius * 3 ) ), min( W, ceil( x + radius * 3 ) ) do
				local i = ( gy - 1 ) * W + gx
				if not s.solid[i] then
					local dx, dy = ( gx - x ) / radius, ( gy - y ) / radius
					local weight = exp( -( dx * dx + dy * dy ) * 0.5 )
					s.d[i] = clamp( s.d[i] + ( density or 0 ) * weight, 0, F.tuning.density_cap )
					s.u[i] = clamp( s.u[i] + ( u or 0 ) * weight, -F.tuning.max_velocity, F.tuning.max_velocity )
					s.v[i] = clamp( s.v[i] + ( v or 0 ) * weight, -F.tuning.max_velocity, F.tuning.max_velocity )
				end
			end
		end
	end

	local function ray( s, x1, y1, x2, y2 )
		if s.meter then s.meter:count( "rays", 1 ) end
		-- Preparation uses a state-local synthetic world; live states use the
		-- engine. Never replace the engine function or another state's queries.
		return ( s.raycast or RaytraceSurfacesAndLiquiform )( x1, y1, x2, y2 )
	end

	-- Noita terrain/liquid cells occupy the world pixel grid. Scan every pixel
	-- row of an 8x8 tile, with a one-pixel guard; a clear tile proves that any
	-- short segment inside it is clear. Occupied tiles retain the exact ray test.
	-- The cache is rebuilt each frame, so moving liquids/destruction stay visible.
	local TILE = 8
	local function clear_tiles( s, terrain, x1, y1, x2, y2 )
		for ty = floor( min( y1, y2 ) / TILE ), floor( max( y1, y2 ) / TILE ) do
			local row = terrain[ty]
			if not row then row = {}; terrain[ty] = row end
			for tx = floor( min( x1, x2 ) / TILE ), floor( max( x1, x2 ) / TILE ) do
				local clear = row[tx]
				if clear == nil then
					clear = true
					for y = ty * TILE - 1, ( ty + 1 ) * TILE do
						if ray( s, tx * TILE - 1, y + 0.5, ( tx + 1 ) * TILE + 1, y + 0.5 ) then
							clear = false; break
						end
					end
					row[tx] = clear
				end
				if not clear then return false end
			end
		end
		return true
	end

	function F.clear( s, x1, y1, x2, y2 )
		local b = s.air_bounds
		if s.open_air and b and x1 >= b[1] and x2 >= b[1] and x1 <= b[3] and x2 <= b[3]
			and y1 >= b[2] and y2 >= b[2] and y1 <= b[4] and y2 <= b[4] then return true end
		-- Reuse the clear prefixes/suffixes proved by the mask's horizontal
		-- scans. Guard the entire segment's pixel rectangle, including corners.
		local lo, hi = floor( min( x1, x2 ) ) - 1, ceil( max( x1, x2 ) ) + 1
		local first, last = floor( min( y1, y2 ) ) - 1, ceil( max( y1, y2 ) )
		if s.air_rows_l and first >= s.air_first and last <= s.air_last and lo >= s.air_left and hi <= s.air_right then
			local clear = true
			for y = first, last do
				if hi > s.air_rows_l[y] and lo < s.air_rows_r[y] then clear = false; break end
			end
			if clear then return true end
		end
		s.terrain = s.terrain or {}
		return clear_tiles( s, s.terrain, x1, y1, x2, y2 )
	end

	function F.blocked( s, x1, y1, x2, y2 )
		return not F.clear( s, x1, y1, x2, y2 ) and ray( s, x1, y1, x2, y2 )
	end

	function F.solid( s, x, y ) return ray( s, x, y, x, y ) and true or false end

	-- Exact free run of one world pixel row around x: its left and right edges,
	-- or nil inside terrain and outside the masked window. The mask's row scan
	-- seeds the outer runs; an inner run costs three rays and is then shared by
	-- every query in that row until the next mask.
	-- With `depth`, two more values widen the run by that many pixels at each
	-- end whose terrain is at least that thick: a sprite drawn behind the world
	-- grid may reach under such a wall, but never through a thinner one.
	function F.span( s, x, y, depth )
		local row = floor( y )
		if not s.row_runs or row < s.air_first or row > s.air_last or x < s.air_left or x > s.air_right then return nil end
		local runs, cy = s.row_runs[row], row + 0.5
		if not runs then
			runs = {}
			s.row_runs[row] = runs
			local l, r = s.air_rows_l[row], s.air_rows_r[row]
			-- Four slots per run: its edges, then the lazily widened edges.
			if l >= s.air_right then runs[1], runs[2], runs[3], runs[4] = s.air_left, s.air_right, false, false
			else
				runs[1], runs[2], runs[3], runs[4] = s.air_left, floor( l + 1 ), false, false
				runs[5], runs[6], runs[7], runs[8] = floor( r - 1 ) + 1, s.air_right, false, false
			end
		end
		local found
		for i = 1, #runs, 4 do
			if x >= runs[i] and x <= runs[i + 1] then found = i; break end
		end
		if not found then
			local px = floor( x )
			if runs.blocked and runs.blocked[px] then return nil end
			if F.solid( s, x, cy ) then
				runs.blocked = runs.blocked or {}
				runs.blocked[px] = true
				return nil
			end
			-- The query point is free, so a hit reported in its own pixel still
			-- leaves a run that contains it.
			local hit, hx = ray( s, x, cy, s.air_right, cy )
			local right = hit and max( x, floor( hx or x ) ) or s.air_right
			hit, hx = ray( s, x, cy, s.air_left, cy )
			local left = hit and min( x, floor( hx or x ) + 1 ) or s.air_left
			found = #runs + 1
			runs[found], runs[found + 1], runs[found + 2], runs[found + 3] = left, right, false, false
		end
		local left, right = runs[found], runs[found + 1]
		if not depth then return left, right end
		if not runs[found + 2] then
			runs[found + 2] = left > s.air_left and F.solid( s, left - depth + 0.5, cy ) and left - depth or left
			runs[found + 3] = right < s.air_right and F.solid( s, right + depth - 0.5, cy ) and right + depth or right
		end
		return left, right, runs[found + 2], runs[found + 3]
	end

	function F.mask( s, p )
		local shift = p.head - ( s.mask_head or p.head )
		s.terrain, s.open_air, s.row_runs = {}, true, {}
		s.mask_gen = ( s.mask_gen or 0 ) + 1 -- lets callers reuse work derived from this mask
		local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
		-- p.lead is the distance a moving window travels before its next mask;
		-- rows scanned ahead keep F.span and F.clear valid for those frames.
		local lead = p.lead or 0
		for _, x in ipairs( { 0.5, W + 0.5 } ) do for _, y in ipairs( { 0.5, H + 0.5 } ) do
			local wx, wy = F.world( s, p, x, y )
			minx, miny = min( minx, wx, wx - p.dx * shift, wx + p.dx * lead ), min( miny, wy, wy - p.dy * shift, wy + p.dy * lead )
			maxx, maxy = max( maxx, wx, wx - p.dx * shift, wx + p.dx * lead ), max( maxy, wy, wy - p.dy * shift, wy + p.dy * lead )
		end end
		s.air_bounds = { minx, miny, maxx, maxy }
		s.air_rows_l, s.air_rows_r = s.air_rows_l or {}, s.air_rows_r or {}
		s.air_first, s.air_last = floor( miny ) - 1, ceil( maxy )
		s.air_left, s.air_right = floor( minx ) - 1, ceil( maxx ) + 1
		for y = s.air_first, s.air_last do
			local hit, hx = ray( s, s.air_left, y + 0.5, s.air_right, y + 0.5 )
			if hit then
				s.open_air = false
				s.air_rows_l[y] = ( hx or s.air_left ) - 1
				local reverse, rx = ray( s, s.air_right, y + 0.5, s.air_left, y + 0.5 )
				s.air_rows_r[y] = reverse and ( rx or s.air_right ) + 1 or s.air_right + 1
			else
				s.air_rows_l[y], s.air_rows_r[y] = s.air_right, s.air_left
			end
		end
		if s.open_air then
			for i = 1, N do
				if s.solid[i] then s.stencil_dirty = true end
				s.solid[i] = false
			end
			s.mask_head = p.head
			return false
		end
		local changed = false
		for y = 1, H do for x = 1, W do
			local i = ( y - 1 ) * W + x
			local wx, wy = F.world( s, p, x, y )
			local h = s.cell * 0.5
			-- Only local terrain is solid. A ray from the muzzle would erase
			-- unobstructed air in an obstacle's shadow and prevent flow around it.
			local solid = not not ( F.blocked( s, wx - p.dx * h, wy - p.dy * h, wx + p.dx * h, wy + p.dy * h )
				or F.blocked( s, wx + p.dy * h, wy - p.dx * h, wx - p.dy * h, wy + p.dx * h ) )
			if solid ~= not not s.solid[i] then s.stencil_dirty = true end
			s.solid[i] = solid
			if s.solid[i] then
				changed = changed or s.d[i] ~= 0 or s.u[i] ~= 0 or s.v[i] ~= 0
				s.d[i], s.u[i], s.v[i] = 0, 0, 0
			end
			-- The window itself moves through the world. Sweep that displacement
			-- too, otherwise it can carry hot gas across a thin wall in one frame.
			if shift ~= 0 and s.d[i] > 0 and F.blocked( s,
				wx - p.dx * shift, wy - p.dy * shift, wx, wy ) then
				changed = true
				s.d[i], s.u[i], s.v[i] = 0, 0, 0
			end
		end end
		s.mask_head = p.head
		return changed
	end

	-- A moving window keeps its mask between solver ticks too, one frame stale.
	-- Its gas must still never be carried across terrain: sweep each hot cell
	-- along this frame's displacement, exactly as the full mask does, with a
	-- real ray: the cached proofs are a frame old and would miss new terrain.
	-- A cell that ran into terrain stays solid until the next mask, so
	-- samplers and the renderer ignore it.
	function F.sweep( s, p )
		local shift, changed = p.head - ( s.mask_head or p.head ), false
		local d, u, v, solid = s.d, s.u, s.v, s.solid
		if shift ~= 0 then
			for i = 1, N do
				if d[i] > 0 then
					local wx, wy = F.world( s, p, ( i - 1 ) % W + 1, floor( ( i - 1 ) / W ) + 1 )
					if ray( s, wx - p.dx * shift, wy - p.dy * shift, wx, wy ) then
						d[i], u[i], v[i], solid[i], changed = 0, 0, 0, true, true
						s.stencil_dirty = true
					end
				end
			end
		end
		s.mask_head = p.head
		return changed
	end

	-- A window that has not moved keeps its mask between solver ticks. Terrain
	-- or liquid that newly covers visible gas must still remove it at once, so
	-- probe the visible cells and rebuild the mask only when one is covered.
	function F.settle( s, p )
		local d, solid = s.d, s.solid
		for i = 1, N do
			if d[i] > 0.035 and not solid[i] then
				local wx, wy = F.world( s, p, ( i - 1 ) % W + 1, floor( ( i - 1 ) / W ) + 1 )
				if F.solid( s, wx, wy ) then return F.mask( s, p ) end
			end
		end
		return false
	end

	local function neighbor( a, s, i, dx, dy, reflect )
		local j = dx == -1 and left[i] or dx == 1 and right[i] or dy == -1 and top[i] or bottom[i]
		-- Extrapolate velocity into open air, reflect normal velocity at terrain.
		if j == 0 then return a[i] end
		if s.solid[j] then return reflect and -a[i] or a[i] end
		return a[j]
	end

	function F.project( s )
		assert( s.model == F, "fluid state belongs to another model" )
		local div, pressure, next_pressure = buffer( s, "div" ), buffer( s, "pressure_a" ), buffer( s, "pressure_b" )
		local pl, pr, pt, pb = buffer( s, "pl" ), buffer( s, "pr" ), buffer( s, "pt" ), buffer( s, "pb" )
		if not s.stencil_ready or s.stencil_dirty then
			local spans, edges = s.pressure_spans or {}, s.pressure_edges or {}
			s.pressure_spans, s.pressure_edges = spans, edges
			local span_count, edge_count, first = 0, 0
			for i = 1, N do
				pl[i], pr[i] = s.solid[left[i]] and i or left[i], s.solid[right[i]] and i or right[i]
				pt[i], pb[i] = s.solid[top[i]] and i or top[i], s.solid[bottom[i]] and i or bottom[i]
				local x = ( i - 1 ) % W + 1
				local direct = not s.solid[i] and x > 1 and x < W
					and not ( s.solid[left[i]] or s.solid[right[i]] or s.solid[top[i]] or s.solid[bottom[i]] )
				if direct then
					first = first or i
				else
					if first then spans[span_count + 1], spans[span_count + 2] = first, i - 1; span_count, first = span_count + 2, nil end
					if not s.solid[i] then edge_count = edge_count + 1; edges[edge_count] = i end
				end
			end
			if first then spans[span_count + 1], spans[span_count + 2] = first, N; span_count = span_count + 2 end
			for i = span_count + 1, #spans do spans[i] = nil end
			for i = edge_count + 1, #edges do edges[i] = nil end
			s.stencil_ready, s.stencil_dirty = true, false
		end
		-- Direct row arithmetic uses zero-valued open-edge ghosts. Terrain
		-- neighbors still use the cached Neumann stencil, including wall edges.
		for i = 1 - W, 0 do pressure[i], next_pressure[i] = 0, 0 end
		for i = N + 1, N + W do pressure[i], next_pressure[i] = 0, 0 end
		local u, v, solid = s.u, s.v, s.solid
		for i = 1, N do
			-- Start each solve at zero; recycled pressure must never warm-start it.
			div[i], pressure[i], next_pressure[i] = 0, 0, 0
			if not solid[i] then
				local l, r, t, b = flat_left[i], flat_right[i], flat_top[i], flat_bottom[i]
				local ui, vi = u[i], v[i]
				div[i] = 0.5 * ( ( solid[r] and -ui or u[r] ) - ( solid[l] and -ui or u[l] )
					+ ( solid[b] and -vi or v[b] ) - ( solid[t] and -vi or v[t] ) )
			end
		end
		-- Most cells use ordinary neighbors. Row spans remove four stencil
		-- table lookups and the solid branch from each Jacobi iteration.
		local spans, edges = s.pressure_spans, s.pressure_edges
		for _ = 1, F.iterations do
			for span = 1, #spans, 2 do
				for i = spans[span], spans[span + 1] do
					next_pressure[i] = ( pressure[i - 1] + pressure[i + 1] + pressure[i - W] + pressure[i + W] - div[i] ) * 0.25
				end
			end
			for edge = 1, #edges do
				local i = edges[edge]
				next_pressure[i] = ( pressure[pl[i]] + pressure[pr[i]] + pressure[pt[i]] + pressure[pb[i]] - div[i] ) * 0.25
			end
			pressure, next_pressure = next_pressure, pressure
		end
		for i = 1, N do
			if not solid[i] then
				u[i] = u[i] - 0.5 * ( pressure[pr[i]] - pressure[pl[i]] )
				v[i] = v[i] - 0.5 * ( pressure[pb[i]] - pressure[pt[i]] )
				if solid[left[i]] or solid[right[i]] then u[i] = 0 end
				if solid[top[i]] or solid[bottom[i]] then v[i] = 0 end
			end
		end
	end

	local function trace( s, p, x, y, dt, density, drift )
		-- Every characteristic starts at an integer, nonsolid grid cell.
		-- Reading that cell is exactly the integer-coordinate interpolation.
		local i = ( y - 1 ) * W + x
		local u = s.u[i] - drift
		local v = s.v[i]
		local mu, mv = sample_velocity( s, x - u * dt * 0.5, y - v * dt * 0.5 )
		mu = mu - drift
		local bx, by = x - mu * dt, y - mv * dt
		-- An empty donor and destination cannot produce dye or correction.
		-- Avoid an engine collision query for a characteristic carrying nothing.
		local value = density and sample( density, s.solid, bx, by, s.open_air )
		if density and value == 0 and density[i] == 0 then return nil end
		if s.open_air and bx >= 0.5 and bx <= W + 0.5 and by >= 0.5 and by <= H + 0.5 then return bx, by, value end
		local wx, wy = F.world( s, p, x, y )
		local tx, ty = F.world( s, p, bx, by )
		if F.blocked( s, wx, wy, tx, ty ) then return nil end
		return bx, by, value
	end

	local function advect_velocity( s, p, dt )
		local u, v = buffer( s, "advected_u" ), buffer( s, "advected_v" )
		local decay = exp( -F.tuning.velocity_decay * dt )
		local drift = ( p.frame_velocity or p.velocity or p.speed ) * F.tuning.drift / s.cell
		for y = 1, H do for x = 1, W do
			local i = ( y - 1 ) * W + x
			u[i], v[i] = 0, 0
			if not s.solid[i] then
				local bx, by = trace( s, p, x, y, dt, nil, drift )
				if bx then
					local su, sv = sample_velocity( s, bx, by )
					u[i], v[i] = su * decay, sv * decay
				end
			end
		end end
		s.advected_u, s.advected_v, s.u, s.v = s.u, s.v, u, v
	end

	local function advect_density( s, p, dt )
		local predicted, out, bx, by = buffer( s, "predicted" ), buffer( s, "advected_d" ),
			buffer( s, "back_x" ), buffer( s, "back_y" )
		local mass, glow, minx, miny, maxx, maxy = 0, 0, W + 1, H + 1, 0, 0
		local drift = ( p.frame_velocity or p.velocity or p.speed ) * F.tuning.drift / s.cell
		local maxu, maxv = abs( drift ), 0
		for i = 1, N do
			predicted[i], out[i], bx[i], by[i] = 0, 0, false, false
			mass, glow = mass + s.d[i], glow + s.d[i] ^ 1.5
			maxu, maxv = max( maxu, abs( s.u[i] - drift ) ), max( maxv, abs( s.v[i] ) )
			if s.d[i] > 0 then
				local x, y = ( i - 1 ) % W + 1, floor( ( i - 1 ) / W ) + 1
				minx, miny, maxx, maxy = min( minx, x ), min( miny, y ), max( maxx, x ), max( maxy, y )
			end
		end
		-- RK2 interpolation is bounded by the field's component extrema. Add
		-- bilinear donor support; cells outside this rectangle stay exactly zero.
		minx, miny = max( 1, floor( minx - maxu * dt ) - 1 ), max( 1, floor( miny - maxv * dt ) - 1 )
		maxx, maxy = min( W, ceil( maxx + maxu * dt ) + 1 ), min( H, ceil( maxy + maxv * dt ) + 1 )
		for y = miny, maxy do for x = minx, maxx do
			local i = ( y - 1 ) * W + x
			if not s.solid[i] then
				local value
				bx[i], by[i], value = trace( s, p, x, y, dt, s.d, drift )
				if bx[i] then predicted[i] = value end
			end
		end end
		local decay, new_mass, new_glow = exp( -F.tuning.heat_decay * dt ), 0, 0
		for y = miny, maxy do for x = minx, maxx do
			local i = ( y - 1 ) * W + x
			if bx[i] then
				local value = predicted[i]
				-- Limited MacCormack dye transport retains rolled-up sheets.
				-- No correction at open edges or terrain: never invent hot inflow.
				local fx, fy
				if value > 0 or s.d[i] > 0 then fx, fy = trace( s, p, x, y, -dt, nil, drift ) end
				if fx and fx >= 1 and fx <= W and fy >= 1 and fy <= H
					and bx[i] >= 1 and bx[i] < W and by[i] >= 1 and by[i] < H then
					local ix, iy = floor( bx[i] ), floor( by[i] )
					local j = ( iy - 1 ) * W + ix
					if not ( s.solid[j] or s.solid[j + 1] or s.solid[j + W] or s.solid[j + W + 1] ) then
						local lo = min( s.d[j], s.d[j + 1], s.d[j + W], s.d[j + W + 1] )
						local hi = max( s.d[j], s.d[j + 1], s.d[j + W], s.d[j + W + 1] )
						value = clamp( value + 0.5 * ( s.d[i] - sample( predicted, s.solid, fx, fy, s.open_air ) ), lo, hi )
					end
				end
				out[i] = value * decay
				new_mass, new_glow = new_mass + out[i], new_glow + out[i] ^ 1.5
			end
		end end
		-- Approximate pressure and dye correction must never create heat/light.
		local scale = min( 1, mass * decay / max( new_mass, 1e-12 ),
			( glow * decay ^ 1.5 / max( new_glow, 1e-12 ) ) ^ ( 2 / 3 ) )
		for i = 1, N do out[i] = out[i] * scale end
		s.advected_d, s.d = s.d, out
	end

	local function curl( s )
		local u, v, solid, out = s.u, s.v, s.solid, s.curl
		for i = 1, N do
			if solid[i] then out[i] = 0
			else
				local l, r, t, b = flat_left[i], flat_right[i], flat_top[i], flat_bottom[i]
				local ui, vi = u[i], v[i]
				out[i] = 0.5 * ( ( solid[r] and vi or v[r] ) - ( solid[l] and vi or v[l] )
					- ( solid[b] and ui or u[b] ) + ( solid[t] and ui or u[t] ) )
			end
		end
	end

	local function launch( s, p, age, dt )
		if age >= F.tuning.emit_frames or p.stop ~= nil then return end
		dt = min( dt, ( F.tuning.emit_frames - age ) / 60 )
		local cx, cy = W - F.tuning.front_cells - 2, ( H + 1 ) / 2
		local width = max( 2, p.r * F.tuning.inlet_width / s.cell )
		local radius = max( 2.5, p.r * F.tuning.eddy_radius / s.cell )
		local separation = p.r * F.tuning.eddy_separation / s.cell
		local psi
		if age == 0 then psi = array() end
		for y = 1, H do for x = 1, W do
			local i = ( y - 1 ) * W + x
			if not s.solid[i] then
				if age < F.tuning.emit_frames and p.stop == nil then
					local across, along = ( y - cy ) / width, ( x - cx ) / F.tuning.inlet_depth
					local hot = exp( -( across * across + along * along ) )
					local sx, sy = F.world( s, p, cx, cy )
					local wx, wy = F.world( s, p, x, y )
					if hot > 0.0001 and not F.blocked( s, sx, sy, wx, wy ) then
						s.d[i] = min( F.tuning.density_cap, s.d[i] + hot * F.tuning.inlet_heat * dt )
						if age == 0 then s.u[i] = s.u[i] + F.tuning.launch_impulse * hot / s.cell end
					end
				end
				-- Seed a counter-rotating pair ONCE as a stream function. Its
				-- circulation evolves with the gas; there are no animated paths.
				if age == 0 and p.stop == nil then
					for side = -1, 1, 2 do
						local ax, ay = ( x - cx ) / radius, ( y - cy - side * separation ) / radius
						psi[i] = psi[i] + side * F.tuning.eddy_force / s.cell * radius
							* exp( -( ax * ax + ay * ay ) * 0.5 )
					end
				end
			end
		end end
		if age == 0 then
			for i = 1, N do
				if not s.solid[i] then
					s.u[i] = s.u[i] + 0.5 * ( neighbor( psi, s, i, 0, 1 ) - neighbor( psi, s, i, 0, -1 ) )
					s.v[i] = s.v[i] - 0.5 * ( neighbor( psi, s, i, 1, 0 ) - neighbor( psi, s, i, -1, 0 ) )
				end
			end
		end
	end

	-- A custom source replaces the fire nozzle; it runs after terrain masking.
	-- Velocity uses cells/second, dt uses seconds, age uses game frames.
	function F.step( s, p, age, dt, source, meter )
		assert( s.model == F, "fluid state belongs to another model" )
		local previous_meter = s.meter
		if meter then s.meter = meter end
		local started = meter and meter:begin()
		F.mask( s, p )
		if meter then meter:finish( "mask", started ); started = meter:begin() end
		local emit = source or F.source or launch
		emit( s, p, age, dt )
		if meter then meter:finish( "injection", started ) end
		local max_speed_squared = 0
		local drift = ( p.frame_velocity or p.velocity or p.speed ) * F.tuning.drift / s.cell
		for i = 1, N do
			local u, v = s.u[i] - drift, s.v[i]
			max_speed_squared = max( max_speed_squared, u * u + v * v )
		end
		-- Semi-Lagrangian RK2 advection does not require a sub-cell CFL for
		-- stability. Keep an accuracy bound, plus exact terrain segment tests.
		local steps = min( 6, max( 1, ceil( sqrt( max_speed_squared ) * dt / F.max_courant ) ) )
		if meter then meter:count( "substeps", steps ); meter:count( "solver_ticks", 1 ) end
		local subdt = dt / steps
		local absolute = buffer( s, "absolute_curl" )
		local confinement = F.tuning.vorticity * exp( -F.tuning.vorticity_decay * age / 60 )
		for _ = 1, steps do
			if meter then started = meter:begin() end
			curl( s )
			local c, u, v, d, solid = s.curl, s.u, s.v, s.d, s.solid
			local max_velocity, buoyancy, cell, px, py = F.tuning.max_velocity, F.tuning.buoyancy, s.cell, p.dx, p.dy
			for i = 1, N do absolute[i] = abs( c[i] ) end
			for i = 1, N do
				if not solid[i] then
					local l, r, t, b = flat_left[i], flat_right[i], flat_top[i], flat_bottom[i]
					local a = absolute[i]
					local gx = ( solid[r] and a or absolute[r] ) - ( solid[l] and a or absolute[l] )
					local gy = ( solid[b] and a or absolute[b] ) - ( solid[t] and a or absolute[t] )
					local norm = sqrt( gx * gx + gy * gy ) + 0.0001
					local force = confinement * c[i] * subdt / norm
					u[i] = clamp( u[i] + gy * force - py * d[i] * buoyancy / cell * subdt, -max_velocity, max_velocity )
					v[i] = clamp( v[i] - gx * force - px * d[i] * buoyancy / cell * subdt, -max_velocity, max_velocity )
				end
			end
			if meter then meter:finish( "forces", started ); started = meter:begin() end
			F.project( s )
			if meter then meter:finish( "pressure", started ); started = meter:begin() end
			advect_velocity( s, p, subdt )
			if meter then meter:finish( "velocity", started ); started = meter:begin() end
			F.project( s )
			if meter then meter:finish( "pressure", started ); started = meter:begin() end
			advect_density( s, p, subdt )
			if meter then meter:finish( "density", started ) end
		end
		curl( s )
		s.meter = previous_meter
	end

	-- Integer text avoids thousands of floating-point printf conversions and
	-- temporary per-cell strings. Power-of-two scales retain 42 bits relative
	-- to the model's caps (fire: <= 4.55e-13 density, 1.46e-11 velocity error).
	-- Only snapshots are rounded; live numerical fields retain full precision.
	function F.pack( s )
		local parts = s.packed_parts or {}
		s.packed_parts = parts
		local _, de = math.frexp( max( 1, F.tuning.density_cap ) )
		local _, ve = math.frexp( max( 1, F.tuning.max_velocity ) )
		local ds, vs = 2 ^ ( 42 - de ), 2 ^ ( 42 - ve )
		local d, u, v = s.d, s.u, s.v
		for i = 1, N do
			local j = ( i - 1 ) * 3 + 1
			parts[j], parts[j + 1], parts[j + 2] = floor( d[i] * ds + 0.5 ), floor( u[i] * vs + 0.5 ), floor( v[i] * vs + 0.5 )
		end
		return "3:" .. s.seed .. ":" .. W .. ":" .. H .. ":" .. string.format( "%.12g", s.mask_head )
			.. ":" .. de .. ":" .. ve .. ";" .. table.concat( parts, "," ) .. ","
	end

	-- A save of other dimensions, or not one at all, gives a fresh field.
	function F.restore( p, text, seed, prepared )
		local s = F.new( p, seed, prepared )
		if type( text ) ~= "string" then return s end
		local saved_seed, w, h, head, de, ve, values = text:match( "^3:(%d+):(%d+):(%d+):([^:]+):(%d+):(%d+);(.*)$" )
		if not saved_seed then return s end
		de, ve = tonumber( de ), tonumber( ve )
		if tonumber( w ) ~= W or tonumber( h ) ~= H or de > 1024 or ve > 1024 then return s end
		s.seed, s.mask_head = tonumber( saved_seed ), tonumber( head ) or p.head
		local ds, vs, i = 2 ^ ( de - 42 ), 2 ^ ( ve - 42 ), 0
		for d, u, v in values:gmatch( "([^,]+),([^,]+),([^,]+)," ) do
			i = i + 1
			if i > N then break end
			s.d[i], s.u[i], s.v[i] = ( tonumber( d ) or 0 ) * ds, ( tonumber( u ) or 0 ) * vs, ( tonumber( v ) or 0 ) * vs
		end
		return s
	end

	return F
end

FlameFluid = create({ max_courant = 2 })
FlameFluid.create = create
