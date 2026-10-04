-- Smooth, normalized kernels reconstruct colored gas with a weak additive glow.
-- One owned entity reuses a bounded SpriteComponent pool; no per-frame spawns.
FlameFluidDraw = {}
local D = FlameFluidDraw
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local sizes = { 4, 6, 8, 12, 16, 24, 32, 48 }
local heat_levels = { 0.06, 0.12, 0.24, 0.42, 0.7, 1.1, 1.8, 3.0 }
-- Integral of the truncated Gaussian used by make_fluid_flame_sprites.py,
-- divided by diameter squared. Overlapping kernels conserve sheet radiance.
local edge = math.exp( -2 )
local kernel_area = math.pi / 8 * ( 1 - 3 * edge ) / ( 1 - edge )
-- The world grid is drawn at z 0. The body lies just behind it, so terrain
-- cuts the gas pixel by pixel; `spill` is how far a kernel may reach under a
-- wall at least that thick. The weak glow stays in front and lights that rim.
D.body_z, D.spill = 0.3, 4
local sprites = { orange = {}, violet = {} }
for palette, paths in pairs( sprites ) do
	for size, diameter in ipairs( sizes ) do
		paths[size] = {}
		for band = 1, #heat_levels do
			paths[size][band] = "mods/witch_notebook/files/gfx/fluid_flame/" .. palette .. "_" .. diameter .. "_" .. band .. ".png"
		end
	end
end

local function pool( s )
	if s.draw_pool then return end
	local e
	for _, child in ipairs( EntityGetAllChildren( s.entity ) or {} ) do
		if EntityHasTag( child, "witch_fluid_fire_visual" ) then e = child; break end
	end
	if not e then
		e = EntityCreateNew( "fluid fire visual" )
		EntityAddTag( e, "witch_fluid_fire_visual" )
		EntityAddChild( s.entity, e )
	end
	s.visual, s.draw_pool, s.draw_slots = e, {}, {}
	-- Claim saved engine components when the Lua state is rebuilt. Each slot
	-- has a translucent body and a weak additive glow drawn in front of it.
	local bodies = EntityGetComponentIncludingDisabled( e, "SpriteComponent", "witch_fluid_fire_body" ) or {}
	local glows = EntityGetComponentIncludingDisabled( e, "SpriteComponent", "witch_fluid_fire_glow" ) or {}
	for i, c in ipairs( bodies ) do
		-- Pools saved by older versions drew the body in front of terrain.
		ComponentSetValue2( c, "z_index", D.body_z )
		s.draw_pool[#s.draw_pool + 1] = { c = c, glow = glows[i], visible = ComponentGetValue2( c, "visible" ), fresh = true }
	end
end

local function hide( entry )
	if entry.visible then
		ComponentSetValue2( entry.c, "visible", false )
		ComponentSetValue2( entry.glow, "visible", false )
		entry.visible = false
	end
end

local function paint( s, entry, path, radius, sx, sy, opacity, glow_opacity, ox, oy )
	local refresh = entry.fresh
	if entry.path ~= path then
		ComponentSetValue2( entry.c, "image_file", path )
		ComponentSetValue2( entry.glow, "image_file", path ); entry.path = path
		if entry.radius ~= radius then
			for _, c in ipairs( { entry.c, entry.glow } ) do
				ComponentSetValue2( c, "offset_x", radius )
				ComponentSetValue2( c, "offset_y", radius )
			end
			entry.radius = radius
		end
		refresh = true
	end
	if entry.sx ~= sx then
		ComponentSetValue2( entry.c, "special_scale_x", sx ); ComponentSetValue2( entry.glow, "special_scale_x", sx )
		entry.sx = sx
		refresh = true
	end
	if entry.sy ~= sy then
		ComponentSetValue2( entry.c, "special_scale_y", sy ); ComponentSetValue2( entry.glow, "special_scale_y", sy )
		entry.sy = sy
		refresh = true
	end
	if not entry.x or math.abs( entry.x - ox ) > 0.000001 or math.abs( entry.y - oy ) > 0.000001 then
		ComponentSetValue2( entry.c, "transform_offset", ox, oy )
		ComponentSetValue2( entry.glow, "transform_offset", ox, oy ); entry.x, entry.y = ox, oy
		refresh = true
	end
	if entry.alpha ~= opacity then ComponentSetValue2( entry.c, "alpha", opacity ); entry.alpha = opacity end
	if entry.glow_alpha ~= glow_opacity then ComponentSetValue2( entry.glow, "alpha", glow_opacity ); entry.glow_alpha = glow_opacity end
	if not entry.visible then
		ComponentSetValue2( entry.c, "visible", true )
		ComponentSetValue2( entry.glow, "visible", true ); entry.visible = true
	end
	if refresh then
		-- Refresh after all geometry changes, including the first offset, so a
		-- newly claimed sprite cannot briefly render at the field's center.
		EntityRefreshSprite( s.visual, entry.c ); EntityRefreshSprite( s.visual, entry.glow )
		entry.fresh = nil
	end
end

local function footprint( s, wx, wy, radius )
	local b = s.air_bounds
	if s.open_air and b then
		-- The window's empty-space proof also permits rectangular kernels at
		-- its edges. Do not scan beyond it or squeeze the free tangent axis.
		local hx = min( radius, wx - b[1] - 1, b[3] - wx - 1 )
		local hy = min( radius, wy - b[2] - 1, b[4] - wy - 1 )
		if hx >= 0.5 and hy >= 0.5 then return hx * 2, hy * 2 end
		return 0, 0
	end
	local F = s.model
	-- The coarse tile proof is enough for interior kernels. It must not size
	-- kernels beside terrain: its 8-pixel tiles leave dark blocks along walls.
	if F.clear( s, wx - radius, wy - radius, wx + radius, wy + radius ) then return radius * 2, radius * 2 end
	local depth = D.spill
	local free, _, left, right = F.span( s, wx, wy, depth )
	if not free then return 0, 0 end
	-- Grow a centered rectangle one pixel row at a time, on its shorter side.
	-- Every covered row has an exact free run, widened under thick terrain: the
	-- world grid hides that part of the body, so fire meets the wall at nearly
	-- full strength instead of fading out before it. Keep the largest rectangle.
	local half, row = min( radius, wx - left, right - wx ), floor( wy )
	local up, down = wy - row, row + 1 - wy
	local best, width, height, sealed_up, sealed_down = 0, 0, 0
	while half >= 0.5 do
		local reach = min( up, down, radius )
		if reach >= 0.5 and half * reach > best then best, width, height = half * reach, half * 2, reach * 2 end
		if reach >= radius then break end
		local above = up <= down
		if above and sealed_up or not above and sealed_down then break end
		local edge, step = above and wy - up or wy + down, 1
		free, _, left, right = F.span( s, wx, above and edge - 0.5 or edge + 0.5, depth )
		if free then half = min( half, wx - left, right - wx )
		else
			-- A floor or ceiling: reach under it once, if it is thick enough.
			if not F.solid( s, wx, above and edge - depth + 0.5 or edge + depth - 0.5 ) then break end
			step = depth
			if above then sealed_up = true else sealed_down = true end
		end
		if above then up = up + step else down = down + step end
	end
	return width, height
end

function D.draw( s, p, frame, options, alpha )
	local F, count, active = s.model, 0, 0
	pool( s )
	local threshold = options.render_floor or 0.035
	local visibility = ( p.hidden == 1 and 0.12 or 1 ) * ( alpha or 1 )
	for i, d in ipairs( s.d ) do if not s.solid[i] and d > threshold then active = active + 1 end end
	local stride = max( 1, ceil( active / options.pixels ) )
	-- Thin a crowded field on a fixed lattice of cells. Counting candidates in
	-- scan order instead would shift every later sample whenever one cell
	-- heats or cools, rebuilding most sprites each tick.
	local W = F.width
	local function sampled( i, skew )
		return ( ( i - 1 ) % W + floor( ( i - 1 ) / W ) * skew ) % stride == 0
	end
	local skew = floor( math.sqrt( stride ) + 0.5 )
	while stride > 1 do
		local chosen = 0
		for i, d in ipairs( s.d ) do
			if not s.solid[i] and d > threshold and sampled( i, skew ) then chosen = chosen + 1 end
		end
		if chosen <= options.pixels then break end
		stride = stride + 1
		skew = floor( math.sqrt( stride ) + 0.5 )
	end
	local size = 1
	-- Wider, low-opacity kernels suppress the cell lattice in the colored
	-- body. Linear texture filtering avoids pixel-grid bands when magnified.
	local spacing = s.cell * math.sqrt( stride )
	local diameter = spacing * 3.4
	while size < #sizes and sizes[size] < diameter do size = size + 1 end
	local world_diameter = min( diameter, sizes[size] )
	local coverage = s.cell * s.cell * stride / ( kernel_area * world_diameter ^ 2 )
	local paths = options.violet and sprites.violet or sprites.orange
	local cells = s.draw_cells or {}
	s.draw_cells = cells
	s.draw_stamp = ( s.draw_stamp or 0 ) + 1
	local stamp = s.draw_stamp
	-- Keep cells in their slots: translating a field only moves its parent.
	-- Release unused slots before allocation, preserving the fixed budget.
	for i, d in ipairs( s.d ) do
		if visibility > 0 and not s.solid[i] and d > threshold then
			if ( stride == 1 or sampled( i, skew ) ) and ( not options.render_floor or d - threshold >= heat_levels[1] * 0.5 ) then
				count = count + 1; cells[count] = i
				local entry = s.draw_slots[i]
				if entry then entry.stamp = stamp end
				if count >= options.pixels then break end
			end
		end
	end
	local free, cx, cy = s.draw_free or {}
	s.draw_free = free
	local available = 0
	for _, entry in ipairs( s.draw_pool ) do
		if entry.stamp ~= stamp then
			hide( entry )
			if entry.cell then s.draw_slots[entry.cell], entry.cell = nil, nil end
			available = available + 1; free[available] = entry
		end
	end
	-- Footprints depend only on the mask, the window position and the kernel
	-- size, so a resting field reuses them until its next mask.
	local ax, ay = F.world( s, frame, 1, 1 )
	if s.foot_gen ~= s.mask_gen or s.foot_x ~= ax or s.foot_y ~= ay or s.foot_size ~= world_diameter then
		s.foot_gen, s.foot_x, s.foot_y, s.foot_size = s.mask_gen, ax, ay, world_diameter
		s.foot_epoch = ( s.foot_epoch or 0 ) + 1
		s.foot_at, s.foot_w, s.foot_h = s.foot_at or {}, s.foot_w or {}, s.foot_h or {}
	end
	local foot_at, foot_w, foot_h, epoch = s.foot_at, s.foot_w, s.foot_h, s.foot_epoch
	for n = 1, count do
		local i, d = cells[n], s.d[cells[n]]
		local gx, gy = ( i - 1 ) % F.width + 1, floor( ( i - 1 ) / F.width ) + 1
		local wx, wy = F.world( s, frame, gx, gy )
		local heat = options.render_floor and d - threshold or d
		local band = 1
		while band < #heat_levels and heat > ( heat_levels[band] + heat_levels[band + 1] ) * 0.5 do band = band + 1 end
		local width, height
		if foot_at[i] == epoch then width, height = foot_w[i], foot_h[i]
		else
			width, height = footprint( s, wx, wy, world_diameter / 2 )
			foot_at[i], foot_w[i], foot_h[i] = epoch, width, height
		end
		if width > 0 then
			if not cx then
				cx, cy = F.world( s, frame, ( F.width + 1 ) / 2, ( F.height + 1 ) / 2 )
				-- These ellipse axes and their clearance proofs use world X/Y.
				EntitySetTransform( s.visual, cx, cy, 0 )
			end
			local path, radius = paths[size][band], sizes[size] / 2
			local sx, sy = width / sizes[size], height / sizes[size]
			-- Clipping removes visible gas; it must not concentrate its original
			-- radiance into a tiny bright bead. Fade isolated corner kernels that
			-- cannot overlap neighboring samples even along their longer axis.
			local continuity = min( 1, max( width, height ) / ( 2 * spacing ) ) ^ 2
			local opacity = visibility * min( 1, 1.4 * coverage ) * continuity
			local glow_opacity = visibility * 0.12 * min( 1, coverage ) * continuity
			local entry = s.draw_slots[i]
			if not entry then
				if available > 0 then entry = free[available]; free[available] = nil; available = available - 1
				else
					local body = EntityAddComponent2( s.visual, "SpriteComponent", {
						_tags = "witch_fluid_fire_body", image_file = path, offset_x = radius, offset_y = radius,
						alpha = opacity, visible = true, additive = false, emissive = true,
						has_special_scale = true, special_scale_x = sx, special_scale_y = sy,
						smooth_filtering = true, z_index = D.body_z,
					} )
					local glow = EntityAddComponent2( s.visual, "SpriteComponent", {
						_tags = "witch_fluid_fire_glow", image_file = path, offset_x = radius, offset_y = radius,
						alpha = glow_opacity, visible = true, additive = true, emissive = true,
						has_special_scale = true, special_scale_x = sx, special_scale_y = sy,
						smooth_filtering = true, z_index = -1,
					} )
					entry = { c = body, glow = glow, path = path, radius = radius, sx = sx, sy = sy, fresh = true,
						alpha = opacity, glow_alpha = glow_opacity, visible = true }
					s.draw_pool[#s.draw_pool + 1] = entry
				end
				s.draw_slots[i], entry.cell = entry, i
			end
			paint( s, entry, path, radius, sx, sy, opacity, glow_opacity, wx - cx, wy - cy )
		else
			local entry = s.draw_slots[i]
			if entry then hide( entry ); s.draw_slots[i], entry.cell = nil, nil end
			-- Collision-aware pixels preserve narrow gaps without glowing disks
			-- covering thin walls or water.
			local hot = min( 1, heat / 2.4 )
			local r, g, b = 255, floor( 65 + hot * 185 ), floor( 8 + hot * hot * 145 )
			if options.violet then r, g, b = floor( 180 + hot * 65 ), floor( 60 + hot * 150 ), 255 end
			local opacity = visibility * min( 1, 1.4 * coverage ) / max( 1, s.cell * s.cell * stride )
			local color = color_abgr_merge( r, g, b, floor( 255 * min( 0.95, heat ^ 0.65 ) * opacity ) )
			GameCreateCosmeticParticle( FX_SPARK, wx, wy, 1, 0, 0, color,
				1 / 60, 1 / 60, true, true, true, false, 0, 0 )
		end
	end
	return count
end
