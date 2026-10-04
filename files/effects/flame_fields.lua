-- Small fluid presets for burst jets, expanding rings and persistent flames.
-- Field motion/rendering/material supply live here; spell timing and damage
-- remain in their original effect handlers. Every entity owns its own buffers.
dofile_once( "mods/witch_notebook/files/effects/fluid.lua" )
dofile_once( "mods/witch_notebook/files/effects/fluid_draw.lua" )

FlameFields = { states = {}, slots = {} }
local S = FlameFields
local floor, min, max, sqrt, exp = math.floor, math.min, math.max, math.sqrt, math.exp

local function ring_vortices( s, p )
	local F, psi = s.model, {}
	local W, H, cx, cy = F.width, F.height, ( F.width + 1 ) / 2, ( F.height + 1 ) / 2
	for i = 1, W * H do psi[i] = 0 end
	local phase = ( s.seed * 0.61803398875 % 1 ) * math.pi * 2
	local radius = p.r / s.cell
	local impulse = p.blast and 320 or 260 -- pixels/second, applied once
	for vortex = 0, 7 do
		local angle = vortex * math.pi / 4 + phase
		local orbit = radius * ( 0.76 + 0.1 * math.sin( vortex * 2.39996 + phase ) )
		local x, y = cx + math.cos( angle ) * orbit, cy + math.sin( angle ) * orbit
		local core = 1.8 + 0.3 * ( 1 + math.sin( vortex * 3.17 + phase ) )
		local spin = vortex % 2 == 0 and 1 or -1
		local strength = spin * impulse / s.cell * core * ( 0.85 + 0.15 * math.sin( vortex + phase ) )
		for gy = max( 1, floor( y - core * 3 ) ), min( H, math.ceil( y + core * 3 ) ) do
			for gx = max( 1, floor( x - core * 3 ) ), min( W, math.ceil( x + core * 3 ) ) do
				local i = ( gy - 1 ) * W + gx
				if not s.solid[i] then
					psi[i] = psi[i] + strength * exp( -( ( gx - x ) ^ 2 + ( gy - y ) ^ 2 ) / ( 2 * core ^ 2 ) )
				end
			end
		end
	end
	-- A stream-function impulse seeds circulation that survives projection.
	-- Its centers are never animated: the solver moves/deforms the vortices.
	local cap = F.tuning.max_velocity
	for y = 1, H do for x = 1, W do
		local i = ( y - 1 ) * W + x
		if not s.solid[i] then
			local left, right = x > 1 and psi[i - 1] or psi[i], x < W and psi[i + 1] or psi[i]
			local top, bottom = y > 1 and psi[i - W] or psi[i], y < H and psi[i + W] or psi[i]
			s.u[i] = max( -cap, min( cap, s.u[i] + ( bottom - top ) * 0.5 ) )
			s.v[i] = max( -cap, min( cap, s.v[i] - ( right - left ) * 0.5 ) )
		end
	end end
end

local function ring_source( s, p, age, dt )
	if age > p.grow and not p.bootstrap then return end
	if age == 0 or p.bootstrap then ring_vortices( s, p ) end
	local F, cx, cy = s.model, ( s.model.width + 1 ) / 2, ( s.model.height + 1 ) / 2
	local t = min( 1, age / p.grow )
	local radius = p.r * ( 1 - ( 1 - t ) ^ 2 ) / s.cell
	local width = max( 1, 4 / s.cell )
	local phase = ( s.seed * 0.61803398875 % 1 ) * math.pi * 2
	for y = 1, F.height do for x = 1, F.width do
		local i = ( y - 1 ) * F.width + x
		if not s.solid[i] then
			local dx, dy = x - cx, y - cy
			local distance = sqrt( dx * dx + dy * dy )
			local weight = exp( -( ( distance - radius ) / width ) ^ 2 )
			if weight > 0.005 then
				local wx, wy = F.world( s, p, x, y )
				if not F.blocked( s, p.ox, p.oy, wx, wy ) then
					-- Uneven, stationary inlet heat gives circulation a sheet to
					-- roll up; a saturated circular refill would hide its motion.
					local inlet = 0.32 + 0.68 * ( 0.5 + 0.5 * math.sin( x * 1.35 + math.sin( y * 1.1 + phase ) + phase ) ) ^ 2
					s.d[i] = min( F.tuning.density_cap, s.d[i] + 110 * weight * inlet * dt )
					local nx, ny = dx / max( 0.5, distance ), dy / max( 0.5, distance )
					local force = weight * dt / s.cell
					s.u[i] = s.u[i] + nx * 80 * force
					s.v[i] = s.v[i] + ny * 80 * force
				end
			end
		end
	end end
end

-- Flame Burst's fireball. A round head is heated and pushed against the
-- oncoming air: gas wraps around it and streams into a tail that cools from
-- white through orange and narrows as its faint edges fade first. A slow,
-- uneven sideways sway at the head makes that tail waver like a flame.
local function fireball_source( s, p, age, dt )
	local F = s.model
	local cx, cy = F.width - F.tuning.front_cells - 2, ( F.height + 1 ) / 2
	local radius = max( 1.6, p.r * 0.45 / s.cell )
	local sx, sy = F.world( s, p, cx, cy )
	local phase = ( s.seed * 0.61803398875 % 1 ) * math.pi * 2
	local sway = math.sin( age * 0.55 + phase ) + 0.6 * math.sin( age * 0.93 + phase * 2 )
	local puff = 1 + 0.35 * math.sin( age * 0.9 + phase * 3 )
	-- Cold air eats the flame from outside: a cell loses heat in proportion to
	-- its excess over its coldest neighbor. The wake narrows steadily behind
	-- the head and ends in a pointed tongue instead of a wide, faint smear.
	local W, H, d, cold = F.width, F.height, s.d, s.fireball_cold or {}
	s.fireball_cold = cold
	for i = 1, W * H do
		local x, here = ( i - 1 ) % W, d[i]
		cold[i] = here > 0 and min( x > 0 and d[i - 1] or here, x < W - 1 and d[i + 1] or here,
			d[i - W] or here, d[i + W] or here ) or 0
	end
	local keep = exp( -12 * dt )
	for i = 1, W * H do
		if d[i] > 0 then d[i] = cold[i] + ( d[i] - cold[i] ) * keep end
	end
	local extent = math.ceil( radius * 2.4 )
	for y = max( 1, floor( cy - extent ) ), min( F.height, math.ceil( cy + extent ) ) do
		for x = max( 1, floor( cx - extent ) ), min( F.width, math.ceil( cx + extent ) ) do
			local i = ( y - 1 ) * F.width + x
			if not s.solid[i] then
				local dx, dy = ( x - cx ) / radius, ( y - cy ) / radius
				local weight = exp( -( dx * dx + dy * dy ) )
				local wx, wy = F.world( s, p, x, y )
				if weight > 0.005 and not F.blocked( s, sx, sy, wx, wy ) then
					s.d[i] = min( F.tuning.density_cap, s.d[i] + 70 * puff * weight * dt )
					s.u[i] = s.u[i] + 150 * weight * dt
					s.v[i] = s.v[i] + 220 * sway * weight * dt
				end
			end
		end
	end
end

local function plume_source( s, p, age, dt )
	local F = s.model
	local cx, cy = ( F.width + 1 ) / 2, ( F.height + 1 ) / 2 + 2
	local width, rate = p.inlet_width or 1.3, p.inlet_heat or 38
	local extent = p.inlet_width and math.ceil( width * 3 ) or 4
	local wx, wy = F.world( s, p, cx, cy )
	if F.blocked( s, wx, wy - 1, wx, wy + 1 ) then return end
	for y = max( 1, floor( cy - extent ) ), min( F.height, math.ceil( cy + extent ) ) do
	for x = max( 1, floor( cx - extent ) ), min( F.width, math.ceil( cx + extent ) ) do
		local i = ( y - 1 ) * F.width + x
		if not s.solid[i] then
			local weight = exp( -( ( x - cx ) ^ 2 + ( y - cy ) ^ 2 ) / ( 2 * width ^ 2 ) )
			local tx, ty = F.world( s, p, x, y )
			if weight > 0.005 and not F.blocked( s, wx, wy, tx, ty ) then
				s.d[i] = min( F.tuning.density_cap, s.d[i] + rate * weight * dt )
				-- A small asymmetric inlet lets the confined vorticity roll up
				-- the rising plume instead of preserving perfect mirror symmetry.
				s.u[i] = s.u[i] + ( y - cy + 0.4 ) * 4 * weight * dt
				s.v[i] = s.v[i] - 24 * weight * dt
			end
		end
	end end
end

S.presets = {
	ring = { model = FlameFluid.create({ width = 32, height = 32, iterations = 16, max_courant = 2,
		tuning = { front_cells = 15.5, drift = 0, heat_decay = 3.5, velocity_decay = 0.35,
			vorticity = 12, vorticity_decay = 0, buoyancy = 18, max_velocity = 40 }, source = ring_source }),
		period = 2, pixels = 512, sources = 6, fuel = 4, fuel_period = 3,
		render_floor = 0.3 },
	burst = { model = FlameFluid.create({ width = 28, height = 18, iterations = 16, max_courant = 2,
		tuning = { front_cells = 5, drift = 0.36, heat_decay = 3, velocity_decay = 0.8,
			vorticity = 10, vorticity_decay = 0, buoyancy = 12, max_velocity = 60 }, source = fireball_source }),
		period = 2, pixels = 256, sources = 4, fuel = 1, fuel_period = 6 },
	violet = { model = FlameFluid.create({ width = 20, height = 24, iterations = 12, max_courant = 2,
		tuning = { front_cells = 9.5, drift = 0, heat_decay = 2.5, velocity_decay = 0.7,
			vorticity = 3, vorticity_decay = 0, buoyancy = 12, max_velocity = 35 }, source = plume_source }),
		period = 4, pixels = 160, sources = 3, fuel = 1, fuel_period = 12, violet = true },
	pyreball = { model = FlameFluid.create({ width = 24, height = 28, iterations = 12, cell_size = 2, max_courant = 2,
		tuning = { front_cells = 11.5, drift = 0, heat_decay = 2.5, velocity_decay = 0.7,
			vorticity = 3, vorticity_decay = 0, buoyancy = 12, max_velocity = 35 }, source = plume_source }),
		period = 4, pixels = 256, sources = 4, fuel = 4, fuel_period = 6,
		scaled_fuel = true, world_fuel = true, legacy_tag = "witch_pyreball_plume" },
}

local function save( e, s, name, value )
	if not s.vars then
		s.vars = {}
		for _, comp in ipairs( EntityGetComponent( e, "VariableStorageComponent" ) or {} ) do
			s.vars[ComponentGetValue2( comp, "name" )] = comp
		end
	end
	local field = type( value ) == "number" and "value_float" or "value_string"
	if s.vars[name] then ComponentSetValue2( s.vars[name], field, value )
	else s.vars[name] = EntityAddComponent2( e, "VariableStorageComponent", { name = name, [field] = value } ) end
end

function S.clear( e ) S.states[e] = nil end

function S.advance( e, p, age, frame, style, profile )
	local preset, started = S.presets[style], profile and profile:begin()
	local F, now = preset.model, GameGetFrameNum()
	if not S.next_cleanup or now >= S.next_cleanup then
		for id in pairs( S.states ) do if not EntityGetIsAlive( id ) then S.clear( id ) end end
		S.next_cleanup = now + 60
	end
	frame.cell = p.fluid_cell or frame.cell
	local s = S.states[e]
	local fresh = not s or s.model ~= F or s.saved ~= p.fluid_state
	if fresh then
		s = F.restore( frame, p.fluid_state, e )
		s.mask_head, s.saved = p.fluid_head or s.mask_head, p.fluid_state
		s.ox, s.oy = p.fluid_ox or frame.ox, p.fluid_oy or frame.oy
		S.states[e] = s
		EntityAddTag( e, "witch_fluid_fire" )
		if profile then profile:count( "restores", 1 ); if type( p.fluid_state ) ~= "string" then profile:count( "starts", 1 ) end end
	end
	s.entity, s.meter = e, profile
	if profile then profile:finish( "restore", started ); started = profile:begin() end
	local phase = p.fluid_phase
	if phase == nil then
		local slot = S.slots[preset.period] or now % preset.period
		S.slots[preset.period] = ( slot + 1 ) % preset.period
		phase = ( slot - p.born ) % preset.period
		save( e, s, "fluid_phase", phase )
	end
	local dirty = false
	frame.lead = ( frame.frame_velocity or 0 ) / 60 * ( preset.period - 1 )
	if s.ox ~= frame.ox or s.oy ~= frame.oy then
		-- Mimicry may translate a stationary source in either axis. Sweep the
		-- old gas separately; head-based masking already handles burst motion.
		dirty = F.mask( s, frame )
		for i, d in ipairs( s.d ) do
			if d > 0 then
				local wx, wy = F.world( s, frame, ( i - 1 ) % F.width + 1, floor( ( i - 1 ) / F.width ) + 1 )
				if F.blocked( s, wx + s.ox - frame.ox, wy + s.oy - frame.oy, wx, wy ) then
					s.d[i], s.u[i], s.v[i], dirty = 0, 0, 0, true
				end
			end
		end
	end
	if age == 0 or age % preset.period == phase or ( fresh and type( p.fluid_state ) ~= "string" ) then
		local dt = ( age == 0 and phase > 0 and phase or preset.period ) / 60
		frame.bootstrap = fresh and type( p.fluid_state ) ~= "string"
		if profile then profile:finish( "mask", started ) end
		F.step( s, frame, age, dt, nil, profile )
		frame.bootstrap, dirty = nil, true
	else
		-- Between solver ticks a field beside terrain keeps its mask: a moving
		-- one sweeps its gas, a resting one probes it. Open air (a few row
		-- scans) and restored fields still take the full mask.
		if not s.air_bounds or s.open_air then dirty = F.mask( s, frame ) or dirty
		elseif frame.head ~= s.mask_head then dirty = F.sweep( s, frame ) or dirty
		else dirty = F.settle( s, frame ) or dirty end
		if profile then profile:finish( "mask", started ) end
	end
	s.ox, s.oy, s.dirty = frame.ox, frame.oy, dirty
	return s, preset
end

local function hot_cells( s )
	if s.dirty or not s.cells then
		s.cells = s.cells or {}
		local count, previous = 0, #s.cells
		for i, d in ipairs( s.d ) do
			if not s.solid[i] and d > 0.08 then count = count + 1; s.cells[count] = i end
		end
		for i = count + 1, previous do s.cells[i] = nil end
	end
	return s.cells
end

local function native( e, s, p, frame, age, preset )
	local F, cells = s.model, hot_cells( s )
	local fuel = preset.scaled_fuel and min( preset.fuel, max( 1, math.ceil( frame.r ^ 2 * 0.004 * frame.power ) ) ) or preset.fuel
	local fuel_frame = preset.world_fuel and GameGetFrameNum() or age
	if not s.pool then
		s.pool = {}
		for _, child in ipairs( EntityGetAllChildren( e ) or {} ) do
			if preset.legacy_tag and EntityHasTag( child, preset.legacy_tag ) then
				EntityKill( child ) -- Replace the saved native-only Pyreball plume.
			elseif EntityHasTag( child, "witch_fluid_fire_emitter" ) then
				if #s.pool < preset.sources then
					s.pool[#s.pool + 1] = { entity = child, emitter = EntityGetFirstComponentIncludingDisabled( child, "ParticleEmitterComponent" ) }
					if s.meter then s.meter:count( "reused_sources", 1 ) end
				else EntityKill( child ) end
			end
		end
	end
	for slot = 1, preset.sources do
		local entry = s.pool[slot]
		if entry and not EntityGetIsAlive( entry.entity ) then entry, s.pool[slot] = nil, nil end
		if not entry and #cells > 0 then
			local child = EntityLoad( "mods/witch_notebook/files/entities/flame_shot_fire.xml", frame.ox, frame.oy )
			EntityAddTag( child, "witch_fluid_fire_emitter" ); EntityAddChild( e, child )
			entry = { entity = child, emitter = EntityGetFirstComponent( child, "ParticleEmitterComponent" ) }
			s.pool[slot] = entry
			if s.meter then s.meter:count( "new_sources", 1 ) end
		end
		if entry then
			local active = #cells > 0
			if entry.active ~= active then ComponentSetValue2( entry.emitter, "is_emitting", active ); entry.active = active end
			if active then
				local index = floor( ( slot - 1 + ( age * 0.137 % 1 ) ) / preset.sources * #cells ) + 1
				local i = cells[min( #cells, index )]
				local gx, gy = ( i - 1 ) % F.width + 1, floor( ( i - 1 ) / F.width ) + 1
				local x, y = F.world( s, frame, gx, gy )
				local u, v = F.flow( s, frame, gx, gy )
				local along, across = ( frame.frame_velocity or 0 ) + u * s.cell, v * s.cell
				local vx, vy = frame.dx * along - frame.dy * across, frame.dy * along + frame.dx * across
				EntitySetTransform( entry.entity, x, y )
				ComponentSetValue2( entry.emitter, "x_vel_min", vx - 2 ); ComponentSetValue2( entry.emitter, "x_vel_max", vx + 2 )
				ComponentSetValue2( entry.emitter, "y_vel_min", vy - 2 ); ComponentSetValue2( entry.emitter, "y_vel_max", vy + 2 )
				ComponentSetValue2( entry.emitter, "custom_alpha", p.hidden == 1 and 0.02 or 0.2 )
				if not entry.configured then
					ComponentSetValue2( entry.emitter, "area_circle_radius", 0, 0 )
					ComponentSetValue2( entry.emitter, "count_max", 1 ); entry.configured = true
				end
				if slot <= fuel and fuel_frame % preset.fuel_period == 0 then
					GameCreateParticle( "fire", x, y, 1, 0, 0, false, false, false )
				end
			end
		end
	end
	return #cells
end

function S.draw( s, p, frame, age, preset, alpha )
	return FlameFluidDraw.draw( s, p, frame, preset, alpha )
end

function S.finish( e, s, p, frame, age, preset, alpha, profile )
	local started = profile and profile:begin()
	local total = native( e, s, p, frame, age, preset )
	if profile then profile:finish( "emitters", started ); started = profile:begin() end
	local pixels = S.draw( s, p, frame, age, preset, alpha )
	if profile then profile:finish( "draw", started ); profile:count( "pixels", pixels ); started = profile:begin() end
	if s.dirty then
		s.saved = s.model.pack( s ); save( e, s, "fluid_state", s.saved )
		if profile then profile:count( "snapshot_bytes", #s.saved ) end
	end
	save( e, s, "fluid_head", s.mask_head ); save( e, s, "fluid_cell", s.cell )
	save( e, s, "fluid_ox", s.ox ); save( e, s, "fluid_oy", s.oy )
	if profile then profile:finish( "save", started ) end
	return total
end
