-- A column of fire with rotating coils, released from the book (Spiraling Flame).
-- Only the flame rotates. Its axis travels straight towards the chosen point.
-- Position, distance and hits live on the entity, so saving/reloading keeps the flight intact.

dofile_once( "mods/witch_notebook/files/books.lua" )
dofile_once( "mods/witch_notebook/files/effects/flame_shot.lua" )
dofile_once( "mods/witch_notebook/files/effects/flame_fields.lua" )

local TAU = math.pi * 2

local function color( r, g, b, alpha )
	return color_abgr_merge( r, g, b, math.floor( 255 * alpha ) )
end

local function point( p, along, across )
	return p.ox + p.dx * along - p.dy * across, p.oy + p.dy * along + p.dx * across
end

-- Draw the helix in a plane containing its axis. Depth changes the brightness and
-- width of each winding, giving it a volume rather than a flat sine-wave outline.
local function draw( p, age, tail, head )
	local alpha = p.hidden == 1 and 0.12 or 1
	local n = math.max( 1, math.ceil( ( head - tail ) / 1.5 ) )
	local phase = age * 0.24 * p.spin
	for i = 0, n do
		local along = tail + ( head - tail ) * i / n
		local behind = head - along
		local taper = math.min( 1, behind / 10, ( along - tail ) / 13 )
		local envelope = math.sqrt( math.max( 0, taper ) )
		local radius = p.r * envelope * ( 0.86 + 0.14 * math.sin( along * 0.21 - age * 0.35 ) )
		local flutter = math.sin( along * 0.37 - age * 0.51 ) * 0.6 * envelope
		-- A dim, narrow spine connects the bright windings.
		local cx, cy = point( p, along, flutter )
		fx_dot( cx, cy, color( 255, 105, 16, 0.35 * alpha ), p.dx * 14, p.dy * 14, 0.035 )
		for strand = 0, 2 do
			local angle = behind / p.length * TAU * 2.15 - phase + strand * TAU / 3
			local depth = ( math.cos( angle ) + 1 ) / 2
			local wave = math.sin( angle ) * radius + flutter
			local width = ( 0.65 + 1.15 * depth ) * envelope
			local px, py = point( p, along, wave )
			local opacity = ( 0.3 + 0.7 * depth ) * alpha * envelope
			-- Red-orange edges, gold body, then the hottest filament in front.
			for side = -1, 1, 2 do
				local ex, ey = point( p, along, wave + side * width )
				fx_dot( ex, ey, color( 255, 72, 8, opacity * 0.8 ), p.dx * 22, p.dy * 22, 0.045 )
			end
			fx_dot( px, py, color( 255, 165, 32, opacity ), p.dx * 18, p.dy * 18, 0.035 )
			if depth > 0.55 then
				fx_dot( px, py, color( 255, 244, 170, opacity ), p.dx * 12, p.dy * 12, 0.025 )
			end
			-- Thin tongues peel off the coil; longer-lived sparks trail behind it.
			if ( i + age + strand * 3 ) % 13 == 0 then
				local outward = math.sin( angle ) * 14
				fx_dot( px, py, color( 255, 117, 20, opacity * 0.8 ),
					p.dx * 32 - p.dy * outward, p.dy * 32 + p.dx * outward - 9, 0.14, -12 )
			end
		end
	end
end

local function burn( e, p, age, tail, head )
	local mx, my = point( p, ( tail + head ) / 2, 0 )
	for _, id in ipairs( creatures_in( mx, my, ( head - tail ) / 2 + p.r + 20, p.owner, true ) ) do
		local ex, ey = EntityGetTransform( id )
		local box = EntityGetFirstComponent( id, "HitboxComponent" )
		local padding = 3
		if box then
			local x0, x1 = ComponentGetValue2( box, "aabb_min_x" ), ComponentGetValue2( box, "aabb_max_x" )
			local y0, y1 = ComponentGetValue2( box, "aabb_min_y" ), ComponentGetValue2( box, "aabb_max_y" )
			ex, ey = ex + ( x0 + x1 ) / 2, ey + ( y0 + y1 ) / 2
			padding = math.min( 20, math.max( padding, ( x1 - x0 ) / 2, ( y1 - y0 ) / 2 ) )
		end
		local along = ( ex - p.ox ) * p.dx + ( ey - p.oy ) * p.dy
		local nearest = math.max( tail, math.min( head, along ) )
		local px, py = point( p, nearest, 0 )
		local hit_key = "hit_" .. id
		if ( ex - px ) ^ 2 + ( ey - py ) ^ 2 <= ( p.r + padding ) ^ 2
			and age >= ( p[hit_key] or -6 ) + 6 and not RaytraceSurfaces( px, py, ex, ey ) then
			seal_damage( id, 0.12 * p.power, "DAMAGE_FIRE", p.owner, px, py )
			if p[hit_key] == nil then give_effect( id, DICTIONARY_LOOKS.fire.status ) end
			effect_set( e, hit_key, age )
		end
	end
end

local function fire_plume( e, x, y, tag, path )
	for _, child in ipairs( EntityGetAllChildren( e ) or {} ) do
		if EntityHasTag( child, tag ) then
			EntitySetTransform( child, x, y )
			return EntityGetFirstComponent( child, "ParticleEmitterComponent" )
		end
	end
	local child = EntityLoad( path, x, y )
	EntityAddChild( e, child )
	return EntityGetFirstComponent( child, "ParticleEmitterComponent" )
end

-- Project an expanding 3D helix onto the game's plane. Every particle keeps its
-- own launch origin, axis and phase; neither the nozzle nor the cursor steers it.
local function helix_point( p, t )
	local life = p.length / p.speed
	t = math.min( t, life )
	local along = math.min( p.length, p.speed * t )
	local phase = p.phase + TAU * p.turns * p.spin * t / life
	local across = 2 * p.r * along / p.length * math.sin( phase )
	return p.ox + p.dx * along - p.dy * across,
		p.oy + p.dy * along + p.dx * across - 12.5 * t * t, phase
end

-- A helix particle of a held cast burns the creatures it passes through. The pause between hits is kept on the
-- creature, so the many particles of one stream hurt it as the straight column does (burn), not once each.
local function ember_burn( p, x, y )
	local frame = GameGetFrameNum()
	for _, id in ipairs( creatures_in( x, y, 24, p.owner, true ) ) do
		local ex, ey = EntityGetTransform( id )
		local box = EntityGetFirstComponent( id, "HitboxComponent" )
		local padding = 3
		if box then
			local x0, x1 = ComponentGetValue2( box, "aabb_min_x" ), ComponentGetValue2( box, "aabb_max_x" )
			local y0, y1 = ComponentGetValue2( box, "aabb_min_y" ), ComponentGetValue2( box, "aabb_max_y" )
			ex, ey = ex + ( x0 + x1 ) / 2, ey + ( y0 + y1 ) / 2
			padding = math.min( 20, math.max( padding, ( x1 - x0 ) / 2, ( y1 - y0 ) / 2 ) )
		end
		if ( ex - x ) ^ 2 + ( ey - y ) ^ 2 <= ( padding + 4 ) ^ 2 then
			local last
			for _, comp in ipairs( EntityGetComponent( id, "VariableStorageComponent" ) or {} ) do
				if ComponentGetValue2( comp, "name" ) == "witch_spiral_hit" then last = comp; break end
			end
			if not last or frame >= ComponentGetValue2( last, "value_int" ) + 6 then
				seal_damage( id, 0.12 * ( p.power or 1 ), "DAMAGE_FIRE", p.owner, x, y )
				if last then ComponentSetValue2( last, "value_int", frame )
				else
					give_effect( id, DICTIONARY_LOOKS.fire.status )
					EntityAddComponent2( id, "VariableStorageComponent", { name = "witch_spiral_hit", value_int = frame } )
				end
			end
		end
	end
end

local function helix_ember( e, p, age, x, y )
	if age >= p.frames then EntityKill( e ); return end
	local nx, ny, phase, hit
	local px, py = x, y
	-- Sweep four short sections of the curved path, including the arc between
	-- frame positions. A thin wall at the crest must block the particle too.
	for i = 1, 4 do
		nx, ny, phase = helix_point( p, ( age + i / 4 ) / 60 )
		local hx, hy
		hit, hx, hy = RaytraceSurfacesAndLiquiform( px, py, nx, ny )
		if hit then
			local vx, vy = nx - px, ny - py
			local distance = math.sqrt( vx * vx + vy * vy )
			if distance > 0 then nx, ny = hx - vx / distance, hy - vy / distance end
			break
		end
		px, py = nx, ny
	end
	if p.fuel == 1 and ( hit or GameGetFrameNum() % 6 == 0 )
		and not RaytraceSurfacesAndLiquiform( nx, ny - 1, nx, ny + 1 )
		and not RaytraceSurfacesAndLiquiform( x, y, nx, ny ) then
		GameCreateParticle( "fire", nx, ny, 1, 0, 0, false, false, false )
	end
	EntitySetTransform( e, nx, ny )
	if hit then EntityKill( e ); return end
	ember_burn( p, nx, ny )
	local plume = fire_plume( e, nx, ny, "witch_spiraling_particle_fire",
		"mods/witch_notebook/files/entities/spiraling_particle_fire.xml" )
	local depth = ( math.cos( phase ) + 1 ) / 2
	local count = math.max( 1, math.min( 2, math.ceil( ( p.power or 1 ) * 0.5 ) ) )
	-- Short-lived native fire surrounds the rotating particle instead of filling
	-- a straight beam. It inherits a little of the local tangent, then rises/fades.
	ComponentSetValue2( plume, "x_vel_min", ( nx - x ) * 9 - 3 )
	ComponentSetValue2( plume, "x_vel_max", ( nx - x ) * 9 + 3 )
	ComponentSetValue2( plume, "y_vel_min", ( ny - y ) * 9 - 3 )
	ComponentSetValue2( plume, "y_vel_max", ( ny - y ) * 9 + 3 )
	ComponentSetValue2( plume, "custom_alpha", ( p.hidden == 1 and 0.12 or 1 ) * ( 0.45 + 0.55 * depth ) )
	ComponentSetValue2( plume, "count_min", count )
	ComponentSetValue2( plume, "count_max", count + 1 )
	ComponentSetValue2( plume, "is_emitting", true )
	local light = EntityGetFirstComponent( e, "LightComponent" )
	if light then
		ComponentSetValue2( light, "update_properties", true )
		ComponentSetValue2( light, "radius", ( p.hidden == 1 and 6 or 18 ) * ( 0.6 + 0.4 * depth ) )
	end
end

-- Sparse ignition carriers move independently from the nozzle and survive its
-- release. They supply grid fire along the moving plume and burn what they pass
-- (ember_burn); walls and liquids stop them, so nothing burns through water.
local function ember( e, p, age, x, y )
	if p.turns then helix_ember( e, p, age, x, y ); return end
	if age >= p.frames then EntityKill( e ); return end
	local vx, vy = p.vx, p.vy - 25 * age / 60
	local nx, ny = x + vx / 60, y + vy / 60
	local hit, hx, hy = RaytraceSurfacesAndLiquiform( x, y, nx, ny )
	if hit then
		local speed = math.sqrt( vx * vx + vy * vy )
		nx, ny = hx - vx / speed, hy - vy / speed
	end
	if ( hit or GameGetFrameNum() % 6 == 0 )
		and not RaytraceSurfacesAndLiquiform( nx, ny - 1, nx, ny + 1 )
		and not RaytraceSurfacesAndLiquiform( x, y, nx, ny ) then
		GameCreateParticle( "fire", nx, ny, 1, 0, 0, false, false, false )
	end
	EntitySetTransform( e, nx, ny )
	if hit then EntityKill( e ) end
end

-- A book cast steers only the births of native moving fire particles, for as
-- long as it is held (lib.lua effect_channel).
local function stream( e, p, age )
	local owner, controls = effect_channel( p )
	if not owner then
		EntityKill( e )
		return
	end
	local x, y = EntityGetTransform( owner )
	local remote = tonumber( GlobalsGetValue( "witch_notebook.remote", "0" ) ) or 0
	if remote > 0 and EntityGetIsAlive( remote ) then x, y = EntityGetTransform( remote ); y = y + 4 end
	y = y - 4
	local tx, ty = ComponentGetValue2( controls, "mMousePosition" )
	local dx, dy = tx - x, ty - y
	local distance = math.sqrt( dx * dx + dy * dy )
	if distance < 0.001 then
		dx, dy = ComponentGetValue2( controls, "mAimingVectorNormalized" )
		local n = math.sqrt( dx * dx + dy * dy )
		if n < 0.001 then dx, dy, n = 1, 0, 1 end
		dx, dy = dx / n, dy / n
	else dx, dy = dx / distance, dy / distance end
	-- Cursor distance only selects a direction; muzzle and range stay fixed.
	p.dx, p.dy, p.ox, p.oy = dx, dy, x + dx * 8, y + dy * 8
	local hit, wx, wy = RaytraceSurfacesAndLiquiform( x, y, p.ox, p.oy )
	if hit then
		p.ox, p.oy = wx - dx * 2, wy - dy * 2
	end
	EntitySetTransform( e, p.ox, p.oy )
	for _, key in ipairs( { "dx", "dy", "ox", "oy" } ) do effect_set( e, key, p[key] ) end
	local open = not hit and not RaytraceSurfacesAndLiquiform( p.ox, p.oy - 1, p.ox, p.oy + 1 )
	effect_fire_loop( e, open )
	-- Flamethrower/create is a short sound, not a loop. Renew it while the
	-- nozzle emits, including after unblocking; individual embers stay silent.
	local frame = GameGetFrameNum()
	if open then
		if frame >= ( p.fire_sound_next or 0 ) then
			effect_sound( "fire_jet", p.ox, p.oy )
			effect_set( e, "fire_sound_next", frame + 12 )
		end
	elseif ( p.fire_sound_next or 0 ) ~= 0 then
		effect_set( e, "fire_sound_next", 0 )
	end
	local radius = math.max( 0.5, p.r * 0.22 )
	for i = 0, 7 do
		local a = i * TAU / 8
		local blocked, hx, hy = RaytraceSurfacesAndLiquiform( p.ox, p.oy,
			p.ox + math.cos( a ) * radius, p.oy + math.sin( a ) * radius )
		if blocked then
			local distance = math.sqrt( ( hx - p.ox ) ^ 2 + ( hy - p.oy ) ^ 2 )
			radius = math.min( radius, math.max( 0, distance * math.cos( math.pi / 8 ) - 1 ) )
		end
	end
	local plume = fire_plume( e, p.ox, p.oy, "witch_spiraling_plume",
		"mods/witch_notebook/files/entities/spiraling_plume.xml" )
	local life = math.max( 0.1, math.min( 1, p.length / p.speed ) )
	-- A small native muzzle flame, like Pyreball. The moving helix particles below
	-- carry the main plume; a long straight emission here would hide their turns.
	ComponentSetValue2( plume, "area_circle_radius", 0, radius )
	ComponentSetValue2( plume, "x_vel_min", -3 )
	ComponentSetValue2( plume, "x_vel_max", 3 )
	ComponentSetValue2( plume, "y_vel_min", -8 )
	ComponentSetValue2( plume, "y_vel_max", -3 )
	ComponentSetValue2( plume, "direction_random_deg", 0 )
	ComponentSetValue2( plume, "lifetime_min", 0.04 )
	ComponentSetValue2( plume, "lifetime_max", 0.06 )
	ComponentSetValue2( plume, "gravity", 0, -25 )
	ComponentSetValue2( plume, "count_min", 1 )
	ComponentSetValue2( plume, "count_max", 1 )
	ComponentSetValue2( plume, "custom_alpha", p.hidden == 1 and 0.12 or 1 )
	ComponentSetValue2( plume, "is_emitting", open )
	local lights = EntityGetComponent( e, "LightComponent" ) or {}
	local light = lights[#lights]
	if light then
		ComponentSetValue2( light, "update_properties", true )
		ComponentSetValue2( light, "radius", p.hidden == 1 and 12 or 80 )
	end
	-- Three independent strands every four world frames, at most 45 births/sec.
	-- Only one in each twelve-frame group supplies sparse grid fire.
	if not open or frame % 4 ~= 0 then return end
	SetRandomSeed( e, frame )
	local phase = age * 0.16 * p.spin + Randomf( -0.12, 0.12 )
	for strand = 0, 2 do
		local spark = effect_spawn( "flame", "ember", p.ox, p.oy, { owner = p.owner,
			ox = p.ox, oy = p.oy, dx = dx, dy = dy, speed = p.speed, length = p.length, r = p.r,
			vx = dx * p.speed, vy = dy * p.speed, phase = phase + strand * TAU / 3, turns = 1.5,
			spin = p.spin, hidden = p.hidden == 1, fuel = frame % 12 == 0 and strand == 0 and 1 or 0,
			power = p.power,
			frames = math.ceil( life * 60 ), reveal = 1 } )
		EntityAddTag( spark, "witch_spiraling_ember" )
		EntityAddComponent2( spark, "LightComponent", { radius = p.hidden == 1 and 6 or 18,
			r = 255, g = 135, b = 40, fade_out_time = 0.15 } )
	end
end

local function column( e, p, age, x, y )
	if p.mode == "spiral" and ( p.channel_book or 0 ) > 0 then stream( e, p, age ); return end
	if age >= p.frames then EntityKill( e ); return end
	local travel = ( p.travel or 0 ) + p.speed / 60
	local limit = p.stop or p.reach
	local head = math.min( travel, limit )
	local hx, hy = point( p, head, 0 )
	-- Sweep the advancing tip so it cannot skip through a thin wall.
	if p.stop == nil and head > ( p.head or 0 ) then
		local hit, wx, wy = RaytraceSurfaces( x, y, hx, hy )
		if hit then
			head = math.max( 0, ( wx - p.ox ) * p.dx + ( wy - p.oy ) * p.dy - 1 )
			hx, hy = point( p, head, 0 )
			effect_set( e, "stop", head )
			fx_burst( hx, hy, color( 255, 160, 40, p.hidden == 1 and 0.1 or 0.9 ), 16, 40, 0.2, -25 )
		end
	end
	local tail = math.max( 0, travel - p.length )
	if tail >= head then EntityKill( e ); return end
	EntitySetTransform( e, hx, hy )
	effect_fire_loop( e, true )
	if age == 0 then effect_sound( "fire_jet", x, y ) end
	effect_set( e, "travel", travel )
	effect_set( e, "head", head )
	draw( p, age, tail, head )
	-- Include the distance swept this frame when applying damage.
	burn( e, p, age, math.max( 0, tail - p.speed / 60 ), head )
	-- A few real fire cells ignite wood/oil. The hundreds of drawing particles
	-- remain cosmetic; this makes one cast affordable and avoids a liquid-fire flood.
	if age % 3 == 0 then
		local px, py = point( p, ( tail + head ) / 2, math.sin( age * 0.7 ) * p.r * 0.5 )
		if not RaytraceSurfaces( hx, hy, px, py ) then
			GameCreateParticle( "fire", px, py, 2, p.dx * 25, p.dy * 25 - 12, false )
		end
	end
end

-- Pyreball shares Forbidden Flames' persistent gas inlet in an orange palette.
-- Lifetime renewal leaves the field, solver clock and owned fire sources intact.
local function ball( e, p, age, x, y, profile )
	if age >= p.frames then FlameFields.clear( e ); EntityKill( e ); return end
	local x, y = p.ox, p.oy
	EntitySetTransform( e, x, y )
	-- effect_spawn may add a gold-ink light first; fire_effect adds the source last.
	local lights = EntityGetComponent( e, "LightComponent" ) or {}
	local light = lights[#lights]
	if light then
		local radius = p.hidden == 1 and 12 or 80
		if ComponentGetValue2( light, "radius" ) ~= radius then
			ComponentSetValue2( light, "update_properties", true )
			ComponentSetValue2( light, "radius", radius )
		end
	end
	local born = p.fluid_born
	if born == nil then born = GameGetFrameNum(); effect_set( e, "fluid_born", born ) end
	local fluid_age = GameGetFrameNum() - born
	local power = math.max( 0.5, math.min( 2, p.power or 1 ) )
	local frame = { ox = x, oy = y, dx = 1, dy = 0, head = 0, speed = 0, frame_velocity = 0,
		cell = 2, r = p.r, power = power, inlet_width = math.max( 0.8, p.r * 0.22 / 2 ), inlet_heat = 38 * power }
	local s, preset = FlameFields.advance( e, p, fluid_age, frame, "pyreball", profile )
	local total = FlameFields.finish( e, s, p, frame, fluid_age, preset, 1, profile )
	effect_fire_loop( e, total > 0 )
	s.meter = nil
end

local function ring( e, p, age, x, y, profile )
	if age >= p.frames then FlameFields.clear( e ); EntityKill( e ); return end
	if age == 0 then effect_sound( p.blast == 1 and "fire_blast" or "fire_ring", x, y ) end
	local t = math.min( 1, age / p.grow )
	local r = p.r * ( 1 - ( 1 - t ) ^ 2 )
	local last = p.r * ( 1 - ( 1 - math.min( 1, math.max( 0, age - 1 ) / p.grow ) ) ^ 2 )
	local alpha = 1 - math.max( 0, age - p.grow ) / ( p.frames - p.grow )
	local frame = { ox = x, oy = y, dx = 1, dy = 0, head = 0, speed = 0, frame_velocity = 0,
		r = p.r, grow = p.grow, blast = p.blast == 1, cell = math.max( 2, p.r * 2.8 / 32 ) }
	local s, preset = FlameFields.advance( e, p, age, frame, "ring", profile )
	FlameFields.finish( e, s, p, frame, age, preset, alpha, profile )
	local F = s.model
	local function visible( px, py ) return not F.blocked( s, x, y, px, py ) end
	local started = profile and profile:begin()
	if age <= p.grow then
		for _, id in ipairs( creatures_in( x, y, r + 5, p.owner, true ) ) do
			local ex, ey = EntityGetTransform( id )
			local d = math.sqrt( ( ex - x ) ^ 2 + ( ey - y ) ^ 2 )
			local key = "hit_" .. id
			if d >= math.max( 0, last - 5 ) and p[key] == nil and visible( ex, ey )
				and F.density( s, frame, ex, ey ) > 0.08 then
				seal_damage( id, p.damage * p.power, p.blast == 1 and "DAMAGE_EXPLOSION" or "DAMAGE_FIRE", p.owner, x, y )
				give_effect( id, DICTIONARY_LOOKS.fire.status )
				push_from( id, x, y, p.push or 90 )
				effect_set( e, key, 1 )
			end
		end
	end
	if profile then profile:finish( "damage", started ) end
	s.meter = nil
end

-- Olruggio's two-part spell: an opening ring, then a forward jet and a larger blast.
local function burst( e, p, age, x, y, profile )
	if age >= p.frames then FlameFields.clear( e ); EntityKill( e ); return end
	if age == 0 then
		effect_sound( "fire_shot", x, y )
		effect_spawn( "flame", "ring", x, y, { owner = p.owner, power = p.power, hidden = p.hidden == 1,
			r = 24, grow = 12, frames = 22, damage = 0.15, push = 35 } )
	end
	local started = profile and profile:begin()
	local travel = math.min( ( p.travel or 0 ) + p.speed / 60, p.reach )
	local hx, hy = point( p, travel, 0 )
	local hit, wx, wy = RaytraceSurfacesAndLiquiform( x, y, hx, hy )
	if profile then profile:count( "rays", 1 ); profile:finish( "movement", started ) end
	if hit or travel >= p.reach then
		if hit then hx, hy = wx - p.dx, wy - p.dy end
		effect_spawn( "flame", "ring", hx, hy, { owner = p.owner, power = p.power, hidden = p.hidden == 1,
			r = p.blast_r, grow = 16, frames = 48, damage = 0.65 + 0.2 * p.force, push = 180, blast = true } )
		fx_burst( hx, hy, color( 255, 220, 100, p.hidden == 1 and 0.12 or 1 ), 24, 75, 0.25, -20 )
		FlameFields.clear( e )
		EntityKill( e )
		return
	end
	EntitySetTransform( e, hx, hy )
	effect_set( e, "travel", travel )
	-- Embers peel off the tail and fall behind. Cosmetic: they burn nothing.
	if age % 2 == 0 then
		SetRandomSeed( e, age )
		local back, side, hot = Randomf( 3, 12 ), Randomf( -1, 1 ), Randomf( 0, 1 )
		local sx, sy = point( p, math.max( 0, travel - back ), side * p.r * 0.4 )
		fx_dot( sx, sy, color( 255, math.floor( 120 + 110 * hot ), math.floor( 30 + 90 * hot ), p.hidden == 1 and 0.12 or 0.9 ),
			p.dx * p.speed * 0.12 - p.dy * side * 35, p.dy * p.speed * 0.12 + p.dx * side * 35 - 10, Randomf( 0.3, 0.55 ), 90 )
	end
	local frame = { ox = p.ox, oy = p.oy, dx = p.dx, dy = p.dy, head = travel,
		speed = p.speed, frame_velocity = p.speed, r = p.r, cell = math.max( 2, ( p.length + 26 ) / 28 ) }
	local s, preset = FlameFields.advance( e, p, age, frame, "burst", profile )
	FlameFields.finish( e, s, p, frame, age, preset, 1, profile )
	s.meter = nil
end

EFFECT_MODES.flame = { spiral = column, ember = ember, shot = FlameShot.update, ball = ball, ring = ring, burst = burst }
