dofile_once( "mods/witch_notebook/files/effects/fluid.lua" )
dofile_once( "mods/witch_notebook/files/effects/fluid_draw.lua" )

FlameShot = { states = {}, sources = 12, pixels = 512 }
local S, F = FlameShot, FlameFluid

local function save_value( e, s, name, value )
	if not s.vars then
		s.vars = {}
		for _, comp in ipairs( EntityGetComponent( e, "VariableStorageComponent" ) or {} ) do
			s.vars[ComponentGetValue2( comp, "name" )] = comp
		end
	end
	local field = type( value ) == "number" and "value_float" or "value_string"
	local comp = s.vars[name]
	if comp then ComponentSetValue2( comp, field, value )
	else s.vars[name] = EntityAddComponent2( e, "VariableStorageComponent", { name = name, [field] = value } ) end
end

local function advect_tracer( s, p, x, y, tick )
	local u, v = F.flow( s, p, x, y )
	local steps = math.min( 8, math.max( 1, math.ceil( math.sqrt( u * u + v * v ) * tick / 0.65 ) ) )
	local dt = tick / steps
	for _ = 1, steps do
		u, v = F.flow( s, p, x, y )
		local mu, mv = F.flow( s, p, x + u * dt / 2, y + v * dt / 2 )
		local nx, ny = x + mu * dt, y + mv * dt
		if F.heat( s, nx, ny ) < 0.035 then return nil end
		local wx, wy = F.world( s, p, x, y )
		local tx, ty = F.world( s, p, nx, ny )
		if not s.open_air and F.blocked( s, wx, wy, tx, ty ) then return nil end
		x, y = nx, ny
	end
	-- The window carries the tracer too; it must not be carried through terrain.
	local step = p.lead or 0
	if step > 0 then
		local wx, wy = F.world( s, p, x, y )
		if F.blocked( s, wx - p.dx * step, wy - p.dy * step, wx, wy ) then return nil end
	end
	return x, y
end

local function source_entry( child )
	local vars = {}
	for _, comp in ipairs( EntityGetComponent( child, "VariableStorageComponent" ) or {} ) do
		vars[ComponentGetValue2( comp, "name" )] = comp
	end
	local function coordinate( name )
		return vars[name] or EntityAddComponent2( child, "VariableStorageComponent", { name = name, value_float = 0 } )
	end
	if not vars.fluid_tracer then
		EntityAddComponent2( child, "VariableStorageComponent", { name = "fluid_tracer", value_float = 1 } )
	end
	return { entity = child, emitter = EntityGetFirstComponent( child, "ParticleEmitterComponent" ),
		x = coordinate( "fluid_x" ), y = coordinate( "fluid_y" ) }
end

-- Executed by run.lua's shared VM before combat. One numerical tick or one
-- disabled emitter per frame spreads preparation instead of delaying a cast.
function S.prepare( e, p, age, x, y, profile )
	local started = profile and profile:begin()
	if S.prepare_owner ~= e then
		S.prepare_owner, S.prepare_ticks, S.prepared_sources = e, 0, {}
		for _, child in ipairs( EntityGetAllChildren( e ) or {} ) do
			if EntityGetParent( child ) == e and EntityHasTag( child, "witch_flame_shot_fire" ) then
				S.prepared_sources[#S.prepared_sources + 1] = source_entry( child )
			end
		end
	end
	if #EntityGetWithTag( "witch_flame_shot" ) > 0 or #EntityGetWithTag( "witch_fluid_fire" ) > 0 then return end
	if S.prepare_ticks < 4 then
		local frame = { length = 88, speed = 360, r = 6, head = 0, ox = 0, oy = 0, dx = 1, dy = 0 }
		local s = S.preparing_state or F.new( frame, 1 )
		S.preparing_state = s
		-- Exercise air and wall stencils without querying or changing terrain.
		local barrier = F.world( s, frame, F.width - 2, F.height / 2 )
		local wall = S.prepare_ticks >= 2
		s.raycast = function( x1, y1, x2, y2 )
			if wall and x1 ~= x2 and ( x1 - barrier ) * ( x2 - barrier ) <= 0 then
				return true, barrier, y1 + ( y2 - y1 ) * ( barrier - x1 ) / ( x2 - x1 )
			end
			return false, x2, y2
		end
		F.step( s, frame, S.prepare_ticks, 1 / 240 )
		S.prepare_ticks = S.prepare_ticks + 1
		if S.prepare_ticks == 4 then
			F.pack( s ) -- prepare the serialization path and its parts buffer
			S.prepared_state, S.preparing_state = s, nil
		end
	elseif #S.prepared_sources < S.sources then
		local child = EntityLoad( "mods/witch_notebook/files/entities/flame_shot_fire.xml", x, y )
		if profile then profile:count( "new_sources", 1 ) end
		EntityAddChild( e, child )
		S.prepared_sources[#S.prepared_sources + 1] = source_entry( child )
	else
		local component = EntityGetFirstComponent( e, "LuaComponent" )
		if component then EntitySetComponentIsEnabled( e, component, false ) end
	end
	if profile then profile:finish( "warmup", started ) end
end

local function sources( e, s, p, age, dirty )
	if not s.pool then
		s.pool = {}
		for _, child in ipairs( EntityGetAllChildren( e ) or {} ) do
			if EntityHasTag( child, "witch_flame_shot_fire" ) then
				if #s.pool < S.sources then s.pool[#s.pool + 1] = source_entry( child )
				else EntityKill( child ) end -- trim pools saved by the older 48-source version
			end
		end
	end
	if dirty or not s.weights then
		s.cells, s.weights = s.cells or {}, s.weights or {}
		local previous, count = #s.cells, 0
		s.total = 0
		for i, d in ipairs( s.d ) do
			if not s.solid[i] and d > 0.055 then
				count = count + 1
				s.total = s.total + d ^ 1.5
				s.cells[count], s.weights[count] = i, s.total
			end
		end
		for i = count + 1, previous do s.cells[i], s.weights[i] = nil, nil end
	end
	local cells, weights, total = s.cells, s.weights, s.total
	local cursor = 1
	local phase = ( ( s.seed + age * 37 ) % 101 ) / 101
	local bulk = p.frame_velocity or p.velocity or p.speed
	for slot = 1, S.sources do
		local entry = s.pool[slot]
		if entry and not EntityGetIsAlive( entry.entity ) then entry = nil; s.pool[slot] = nil end
		if not entry and total > 0 then
			local ready = S.prepared_sources
			while ready and #ready > 0 and not entry do
				local candidate = table.remove( ready )
				if EntityGetIsAlive( candidate.entity ) and EntityGetParent( candidate.entity ) == S.prepare_owner then entry = candidate end
			end
			if entry then
				EntityRemoveFromParent( entry.entity )
				if s.meter then s.meter:count( "reused_sources", 1 ) end
			else
				local child = EntityLoad( "mods/witch_notebook/files/entities/flame_shot_fire.xml", p.ox, p.oy )
				if s.meter then s.meter:count( "new_sources", 1 ) end
				entry = source_entry( child )
			end
			EntityAddChild( e, entry.entity )
			s.pool[slot] = entry
		end
		if entry then
			local child, emitter = entry.entity, entry.emitter
			if entry.emitting ~= ( total > 0 ) then
				ComponentSetValue2( emitter, "is_emitting", total > 0 )
				entry.emitting = total > 0
			end
			if total > 0 then
				-- Cached component IDs avoid repeated entity/component enumeration.
				-- Read the saved floats directly so external edits and reloads work.
				local gx, gy = advect_tracer( s, p, ComponentGetValue2( entry.x, "value_float" ),
					ComponentGetValue2( entry.y, "value_float" ), 1 / 60 )
				if not gx then
					local target = ( slot - 1 + phase ) / S.sources * total
					while cursor < #cells and weights[cursor] < target do cursor = cursor + 1 end
					local i = cells[cursor]
					gx, gy = ( i - 1 ) % F.width + 1, math.floor( ( i - 1 ) / F.width ) + 1
				end
				ComponentSetValue2( entry.x, "value_float", gx )
				ComponentSetValue2( entry.y, "value_float", gy )
				local x, y = F.world( s, p, gx, gy )
				EntitySetTransform( child, x, y )
				local u, v = F.flow( s, p, gx, gy )
				local along, across = bulk + u * s.cell, v * s.cell
				local vx, vy = p.dx * along - p.dy * across, p.dy * along + p.dx * across
				ComponentSetValue2( emitter, "x_vel_min", vx - 2 )
				ComponentSetValue2( emitter, "x_vel_max", vx + 2 )
				ComponentSetValue2( emitter, "y_vel_min", vy - 3 )
				ComponentSetValue2( emitter, "y_vel_max", vy + 1 )
				if entry.power ~= p.power then
					ComponentSetValue2( emitter, "area_circle_radius", 0, math.min( 0.6, s.cell * 0.15 ) )
					ComponentSetValue2( emitter, "count_max", math.min( 2, math.max( 1, math.ceil( p.power ) ) ) )
					entry.power = p.power
				end
				ComponentSetValue2( emitter, "custom_alpha", ( p.hidden == 1 and 0.04 or 0.35 )
					* math.min( 0.95, ( F.heat( s, gx, gy ) / 0.65 ) ^ 1.7 ) )
				-- Preserve the ignition budget despite the smaller native pool.
				if slot <= 2 and age % 6 == 0 then
					GameCreateParticle( "fire", x, y, 1, 0, 0, false, false, false )
				end
			end
		end
	end
	return total
end
-- Reconstruct the hot dye every frame. Native fire is free to burn terrain,
-- while the visible sheets and curls stay attached to the simulated gas.
function S.draw( s, p, age )
	return FlameFluidDraw.draw( s, p, p, S )
end

local function burn( e, s, p, age )
	local mid = ( p.tail + p.head ) / 2
	local mx, my = p.ox + p.dx * mid, p.oy + p.dy * mid
	for _, id in ipairs( creatures_in( mx, my, ( p.head - p.tail ) / 2 + F.height * s.cell / 2 + 20, p.owner, true ) ) do
		local x, y = EntityGetTransform( id )
		local box = EntityGetFirstComponent( id, "HitboxComponent" )
		if box then
			x = x + ( ComponentGetValue2( box, "aabb_min_x" ) + ComponentGetValue2( box, "aabb_max_x" ) ) / 2
			y = y + ( ComponentGetValue2( box, "aabb_min_y" ) + ComponentGetValue2( box, "aabb_max_y" ) ) / 2
		end
		local key = "hit_" .. id
		if F.density( s, p, x, y ) > 0.08 and age >= ( p[key] or -6 ) + 6 then
			seal_damage( id, 0.12 * p.power, "DAMAGE_FIRE", p.owner, x, y )
			if p[key] == nil then give_effect( id, DICTIONARY_LOOKS.fire.status ) end
			effect_set( e, key, age )
		end
	end
end

function S.update( e, p, age, x, y, profile )
	local started = profile and profile:begin()
	if age % 60 == 0 then
		for id in pairs( S.states ) do if not EntityGetIsAlive( id ) then S.states[id] = nil end end
	end
	if age >= p.frames then S.states[e] = nil; EntityKill( e ); return end
	local s = S.states[e]
	if not s or s.saved ~= p.fluid_state then
		local prepared
		if type( p.fluid_state ) ~= "string" then
			prepared, S.prepared_state = S.prepared_state, nil
			if profile then profile:count( "starts", 1 ) end
		end
		s = F.restore( p, p.fluid_state, e, prepared )
		s.mask_head = p.fluid_head or s.mask_head
		S.states[e] = s
		s.saved = p.fluid_state
		if profile then profile:count( "restores", 1 ) end
	end
	s.entity, s.meter = e, profile
	if profile then profile:finish( "restore", started ); started = profile:begin() end
	-- Choose alternating GLOBAL frame slots, even when casts have different
	-- birth frames. Save the age parity so reload keeps the same cadence.
	local phase = p.fluid_phase
	if phase == nil then
		phase = 0 -- older snapshots used even ages
		if type( p.fluid_state ) ~= "string" then
			local slot = S.next_slot or GameGetFrameNum() % 2
			S.next_slot = 1 - slot
			phase = ( slot - ( p.born or GameGetFrameNum() ) ) % 2
		end
		p.fluid_phase = phase
		save_value( e, s, "fluid_phase", phase )
	end
	local velocity = ( p.velocity or p.speed ) * math.exp( -( p.drag or F.tuning.packet_drag ) / 60 )
	local travel = ( p.travel or 0 ) + velocity / 60
	p.velocity = velocity
	save_value( e, s, "velocity", velocity )
	local head = math.min( travel, p.stop or p.reach )
	local hx, hy = p.ox + p.dx * head, p.oy + p.dy * head
	if p.stop == nil and head > ( p.head or 0 ) then
		if profile then profile:count( "rays", 1 ) end
		local hit, wx, wy = RaytraceSurfacesAndLiquiform( x, y, hx, hy )
		if hit then
			head = math.max( 0, ( wx - p.ox ) * p.dx + ( wy - p.oy ) * p.dy - 1 )
			hx, hy = p.ox + p.dx * head, p.oy + p.dy * head
			p.stop = head
			save_value( e, s, "stop", head )
		end
	end
	p.frame_velocity = ( head - ( p.head or 0 ) ) * 60
	save_value( e, s, "frame_velocity", p.frame_velocity )
	p.tail, p.head = math.max( 0, travel - p.length ), head
	if p.tail >= head then S.states[e] = nil; EntityKill( e ); return end
	EntitySetTransform( e, hx, hy )
	EntityAddTag( e, "witch_flame_shot" )
	save_value( e, s, "travel", travel )
	save_value( e, s, "head", head )
	save_value( e, s, "tail", p.tail )
	if age == 0 then effect_sound( "fire_shot", x, y ) end
	if profile then profile:finish( "movement", started ); started = profile:begin() end
	local dirty
	p.lead = math.max( 0, p.frame_velocity / 60 )
	if age == 0 or age % 2 == phase or type( p.fluid_state ) ~= "string" then
		-- An opposite-slot shot starts with a half tick; it does not wait to
		-- appear, and the next tick advances the normal two-frame interval.
		F.step( s, p, age, age == 0 and phase == 1 and 1 / 60 or 2 / 60, nil, profile )
		dirty = true
	else
		-- Between solver ticks the shot keeps its mask; see FlameFields.
		if not s.air_bounds or s.open_air then dirty = F.mask( s, p )
		elseif p.head ~= s.mask_head then dirty = F.sweep( s, p )
		else dirty = F.settle( s, p ) end
		if profile then profile:finish( "mask", started ) end
	end
	if profile then started = profile:begin() end
	local total = sources( e, s, p, age, dirty )
	if profile then profile:finish( "emitters", started ) end
	if total == 0 and age >= F.tuning.emit_frames then
		S.states[e] = nil
		EntityKill( e )
		return
	end
	effect_fire_loop( e, total > 0 )
	local lights = EntityGetComponent( e, "LightComponent" ) or {}
	local light = lights[#lights]
	if light then
		ComponentSetValue2( light, "update_properties", true )
		ComponentSetValue2( light, "radius", ( p.hidden == 1 and 12 or 80 ) * math.min( 1, math.sqrt( total / 25 ) ) )
	end
	if profile then started = profile:begin() end
	local pixels = S.draw( s, p, age )
	if profile then profile:finish( "draw", started ); profile:count( "pixels", pixels ); started = profile:begin() end
	burn( e, s, p, age )
	if profile then profile:finish( "damage", started ); started = profile:begin() end
	-- Between solver ticks only changed fields need a new snapshot.
	-- The small head value preserves exact swept masking after a cache reload.
	if dirty then
		s.saved = F.pack( s )
		save_value( e, s, "fluid_state", s.saved )
		if profile then profile:count( "snapshot_bytes", #s.saved ) end
	end
	save_value( e, s, "fluid_head", s.mask_head )
	if profile then profile:finish( "save", started ) end
	s.meter = nil
end
