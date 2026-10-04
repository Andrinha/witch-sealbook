-- Light sources and sculptures, pressure-lit stones, threads joining marked fragments,
-- and the separate guidance spells. Light itself neither burns nor deals projectile damage.

local MODES = {}

local done = effect_done

-- Solid luminous forms: close particle spacing gives a core with a soft edge.
local function orb( x, y, r, age, alpha )
	alpha = alpha or 1
	for i = -math.floor( r ), math.floor( r ) do
		local h = math.sqrt( math.max( 0, r * r - i * i ) )
		fx_line( x + i, y - h, x + i, y + h, effect_color( "light", 0.55, alpha * 0.6 ), 1, 0.055 )
	end
	fx_ring( x, y, r + 0.5, effect_color( "light", 0.25, alpha * 0.45 ), 22, 0, 0.06 )
	fx_dot( x - 1, y - 1, effect_color( "light", 1, alpha ), 0, 0, 0.07 )
end

-- A lamp part by its top-left pixel: the centers of odd-sized images fall
-- between pixels, and a whole-number center would blur or shift them.
local function part( name, left, top, w, h )
	GameCreateSpriteForXFrames( "mods/witch_notebook/files/gfx/floatglow_" .. name .. ".png",
		left + w / 2, top + h / 2, true, 0, 0, 1, false )
end

-- The Floatglow Lamp contraption (Vol. 12): the seal's page lines a shallow
-- tray and the conical top floats over the light, held by a chain. `tray` is
-- the tray's rim, `lift` the gap up to the top's rim: at 0 the lamp is shut.
-- `wall` is the offset to a wall face that the tray's bracket reaches, or 0.
-- A physics tray draws itself: `tip` is then the end of its rim, where the
-- chain hangs, and `tip.level` tells whether the tray lies flat.
local LAMP_HOLES = { { 3, 3 }, { 2, 5 }, { 4, 6 } }
local function lamp_body( x, tray, lift, wall, glow, age, tip )
	x, tray, lift = math.floor( x + 0.5 ), math.floor( tray + 0.5 ), math.floor( lift + 0.5 )
	local top = tray - lift - 8
	if not tip then part( "tray", x - 6, tray, 13, 5 ) end
	part( "cone", x - 3, top, 7, 9 )
	-- The chain keeps its length: it droops while the top sits low.
	-- Open, it bows out around the light.
	local ex, ey = tip and tip.x or x + 6, tip and tip.y or tray
	local slack = math.max( 0, 17 - lift )
	local mx, my = x + 10 + slack * 0.1, tray - lift / 2 + slack * 0.35
	for i = 1, 8 do
		local t = i / 9
		local a, b, c = ( 1 - t ) ^ 2, 2 * t * ( 1 - t ), t * t
		part( "link", math.floor( a * ( x + 3 ) + b * mx + c * ex + 0.5 ),
			math.floor( a * ( tray - lift ) + b * my + c * ey + 0.5 ), 1, 1 )
	end
	if wall and wall ~= 0 then
		local side = wall > 0 and 1 or -1
		local face = x + wall
		part( "plate", side > 0 and face - 2 or face + 1, tray + 1, 2, 7 )
		for ax = x + side * 2, face - side * 3, side do part( "link", ax, tray + 4, 1, 1 ) end
	end
	if glow <= 0 then return end
	-- The lit page inside the tray, and light escaping through the top's holes.
	if not tip or tip.level then
		fx_line( x - 4.5, tray + 1.5, x + 5.5, tray + 1.5, effect_color( "light", 0.6, glow * 0.3 ), 1, 0.05 )
	end
	for i, hole in ipairs( LAMP_HOLES ) do
		local hx, hy = x - 2.5 + hole[1], top + hole[2] + 0.5
		fx_dot( hx, hy, effect_color( "light", 0.9, glow * ( 0.6 + 0.3 * math.sin( age * 0.11 + i * 2 ) ) ), 0, 0, 0.05 )
		if ( age + i * 7 ) % 21 == 0 then
			fx_dot( hx, hy, effect_color( "light", 0.7, glow * 0.6 ), ( hole[1] - 3 ) * 5 + ( i - 2 ) * 2, -4, 0.45 )
		end
	end
end

-- The nearest wall beside a lamp's tray that its bracket can reach: the offset
-- to its first solid pixel column, or 0. The rays start past the tray's rim:
-- the tray is a solid body itself.
local function lamp_wall( x, y )
	x = math.floor( x + 0.5 )
	for side = 1, -1, -2 do
		local hit, hx = RaytraceSurfaces( x + side * 7, y, x + side * 16, y )
		if hit and math.abs( hx - x ) >= 8 then
			return side > 0 and math.floor( hx ) - x or math.ceil( hx ) - 1 - x
		end
	end
	return 0
end

-- The manga's glow: dotted rings widening around the ball. They turn slowly in
-- opposite directions; dots that would cover the tray or the top are left out.
local function halo( x, y, r, age, alpha, top, bottom )
	for ring = 1, 3 do
		local radius = r + ring * 3.4 + math.sin( age * 0.04 + ring ) * 0.5
		local count = 8 + ring * 6
		local turn = age * 0.008 * ( ring % 2 == 0 and -1 or 1 ) + ring
		for i = 1, count do
			local a = turn + i / count * 2 * math.pi
			local px, py = x + math.cos( a ) * radius, y + math.sin( a ) * radius
			if math.abs( px - x ) > 7 or ( py > top and py < bottom ) then
				fx_dot( px, py, effect_color( "light", 0.5, alpha * ( 0.62 - ring * 0.14 ) ), 0, 0, 0.05 )
			end
		end
	end
end

MODES.column = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	-- Direction is captured at cast time; without an aim vector the column stands upright.
	local dx, dy = p.dx or 0, p.dy or -1
	local height = p.height * math.min( 1, ( age + 1 ) / 18 )
	local shift = p.suspended == 1 and height / 2 or 0
	local bx, by = x - dx * shift, y - dy * shift
	local function lit_length( sx, sy, length )
		local hit, hx, hy = RaytraceSurfaces( sx, sy, sx + dx * length, sy + dy * length )
		if hit then return math.max( 0, math.min( length, ( hx - sx ) * dx + ( hy - sy ) * dy - 1 ) ) end
		return length
	end
	local length = lit_length( bx, by, height )
	if effect_text( p.lights ) == "" then
		local lights = {}
		for h = 0, p.height, 60 do
			local comp = EntityAddComponent2( e, "LightComponent", { radius = 0,
				r = 255, g = 245, b = 200, fade_out_time = 0.8 } )
			lights[#lights + 1] = string.format( "%d,%d", comp, h )
		end
		p.lights = table.concat( lights, ";" )
		effect_set( e, "lights", p.lights )
		effect_sound( "beam", x, y )
	end
	local fade = math.min( 1, ( p.frames - age ) / 30 )
	local width = p.ancient == 1 and 5 or 2.5
	-- Update every frame so turning or newly blocked beams leave no lit masks
	-- along the previous path. Visibility follows these offsets in run.lua.
	for comp, h in effect_text( p.lights ):gmatch( "(%d+),(%d+)" ) do
		comp, h = tonumber( comp ), tonumber( h )
		ComponentSetValue2( comp, "offset_x", bx + dx * h - x )
		ComponentSetValue2( comp, "offset_y", by + dy * h - y )
		ComponentSetValue2( comp, "radius", length > 0 and h <= length and fade * 80 or 0 )
	end
	if length <= 0 then return end
	for k = -2, 2 do
		local offset = k * width / 2
		local sx, sy = bx - dy * offset, by + dx * offset
		local rail = lit_length( sx, sy, length )
		fx_line( sx, sy, sx + dx * rail, sy + dy * rail, effect_color( "light", k == 0 and 1 or 0.25,
			fade * ( k == 0 and 0.85 or 0.3 ) ), k == 0 and 1 or 2, 0.06 )
	end
	for i = 1, 3 do
		local offset = Random( -6, 6 )
		local sx, sy = bx - dy * offset, by + dx * offset
		local rail = lit_length( sx, sy, length )
		local h = Random( 0, math.floor( rail ) )
		local speed = math.min( 12, math.max( 0, rail - h - 1 ) / ( 0.35 * 1.4 ) )
		fx_dot( sx + dx * h, sy + dy * h, effect_color( "light", 0.5, fade * 0.5 ),
			dx * speed, dy * speed, 0.35 )
	end
	if age % 3 == 0 then fx_ring( bx, by, width * 2, effect_color( "light", 0.6, fade * 0.5 ), 24, 0, 0.08 ) end
end

-- Floatglow Lamp (Ch. 28) is a lantern: it flies after its caster and hangs
-- beside their head, on the side it happens to be. It never passes through
-- terrain; left far behind, it goes out there and lights up again at hand.
local function lantern_follow( p, x, y )
	local owner = effect_owner( p )
	if not owner then return x, y end
	local ox, oy = EntityGetTransform( owner )
	local side = x < ox and -1 or 1
	local tx, ty = ox + side * math.max( 12, math.min( 16, math.abs( x - ox ) ) ), oy - 24
	local dx, dy = tx - x, ty - y
	local d = math.sqrt( dx * dx + dy * dy )
	if d > 260 then
		fx_burst( x, y, effect_color( "light", 0.7 ), 12, 30, 0.35 )
		return tx, ty
	end
	if d < 0.5 then return x, y end
	-- It eases towards its place, at most 360 pixels a second.
	local step = math.min( d, 6, math.max( 0.5, d * 0.1 ) )
	local nx, ny = x + dx / d * step, y + dy / d * step
	if RaytraceSurfaces( x, y, nx, ny ) then
		-- Slide along the wall rather than stop dead at it.
		if not RaytraceSurfaces( x, y, nx, y ) then ny = y
		elseif not RaytraceSurfaces( x, y, x, ny ) then nx = x
		else nx, ny = x, y end
	end
	return nx, ny
end

-- A Wall-Anchored lamp's tray is a physics body of its own entity. Entity ids
-- change when the world reloads, so the effect and its tray share a saved key.
-- Returns the tray, and whether it was just found again; nil once it is gone.
local TRAYS = {}
local function lamp_tray( e, p, x, y, create )
	local tray = TRAYS[e]
	if tray and EntityGetIsAlive( tray ) then return tray end
	TRAYS[e] = nil
	local key = effect_text( p.tray )
	if key == "" then
		if not create then return end
		-- The tray's image is 13 x 5; its rim lies eight pixels under the ball.
		tray = EntityLoad( "mods/witch_notebook/files/entities/floatglow_tray.xml",
			math.floor( x + 0.5 ) + 0.5, math.floor( y + 0.5 ) + 10.5 )
		key = GameGetFrameNum() .. "_" .. e
		EntityAddComponent2( tray, "VariableStorageComponent", { name = "witch_lamp", value_string = key } )
		effect_set( e, "tray", key )
		p.tray = key
		TRAYS[e] = tray
		return tray
	end
	for _, id in ipairs( EntityGetWithTag( "witch_lamp_tray" ) or {} ) do
		if effect_params( id ).witch_lamp == key then
			TRAYS[e] = id
			return id, true
		end
	end
end

-- Both Floatglow Lamps: a ball of light floats between the lamp's tray and its
-- conical top, and shines for a long time.
-- The Ch. 28 seal (`lantern`) lights a lantern that flies after its caster.
-- The Wall-Anchored lamp is a thing in the world: a wall close beside its tray
-- holds it on a bracket; without one the tray falls, and can be pushed and
-- kicked about, with its light floating over it wherever it comes to rest.
MODES.lamp = function( e, p, age, x, y )
	if age >= p.frames then
		local tray = p.lantern ~= 1 and lamp_tray( e, p )
		if tray then EntityKill( tray ) end
		TRAYS[e] = nil
		EntityKill( e )
		return
	end
	if age == 0 then EntityAddComponent2( e, "LightComponent", { radius = 170, r = 255, g = 235, b = 170, fade_out_time = 1.5 } ) end
	local bob = math.sin( age * 0.05 ) * 1.5
	local rim, wall, tip = 0, 0
	if p.lantern == 1 then
		x, y = lantern_follow( p, x, y )
		EntitySetTransform( e, x, y )
		rim = math.floor( y + 0.5 ) + 8
	else
		local tray, found = lamp_tray( e, p, x, y, true )
		if not tray then
			-- The tray was destroyed: the seal's page is gone, and its light with it.
			fx_burst( x, y, effect_color( "light", 0.7 ), 14, 40, 0.4 )
			TRAYS[e] = nil
			EntityKill( e )
			return
		end
		local tx, ty, turn = EntityGetTransform( tray )
		x, rim = math.floor( tx ), math.floor( ty - 2 )
		if p.hold == 2 then
			-- A reloaded body starts as its file says: let a fallen tray go again.
			if found then PhysicsSetStatic( tray, false ) end
		else
			wall = p.wall or 0
			if p.hold ~= 1 or age % 30 == 0 then
				wall = lamp_wall( x, rim + 4 )
				if wall ~= ( p.wall or 0 ) then effect_set( e, "wall", wall ) end
			end
			if wall ~= 0 then
				if p.hold ~= 1 then effect_set( e, "hold", 1 ) end
			elseif age > 0 then
				-- No wall to hang on, or it was dug away: the tray drops.
				PhysicsSetStatic( tray, false )
				effect_set( e, "hold", 2 )
			end
		end
		local c, s = math.cos( turn or 0 ), math.sin( turn or 0 )
		tip = { x = math.floor( tx + 6 * c + 2 * s ), y = math.floor( ty + 6 * s - 2 * c ), level = math.abs( s ) < 0.2 and c > 0 }
		y = rim - 8
		EntitySetTransform( e, x, y + bob )
	end
	-- The top lifts off the tray as the seal lights, and settles as it goes out.
	local open = math.max( 0, math.min( 1, ( age + 1 ) / 24, ( p.frames - age ) / 24 ) )
	open = open * open * ( 3 - 2 * open )
	local fade = math.min( 1, ( p.frames - age ) / 60 )
	lamp_body( x, rim, ( 16 + math.sin( age * 0.03 ) ) * open, wall, fade * open, age, tip )
	-- The ball rises out of the tray with the top.
	local ball = rim - 2 + ( y + bob - rim + 2 ) * open
	local r = ( 4 + math.sin( age * 0.035 ) * 0.25 ) * open
	orb( x, ball, r, age, fade )
	if age % 2 == 0 then halo( x, ball, r, age, fade * open, rim - 16, rim ) end
	if age % 6 == 0 then fx_dot( x + Random( -5, 5 ), ball, effect_color( "light", 0.6, 0.4 * open ), 0, -5, 0.5 ) end
end

-- Glowstone Path: glowing stones light up on the ground ahead of the caster and burn for a long time
MODES.glowpath = function( e, p, age, x, y )
	if age == 0 then
		local stones, px, py = {}, x, y
		local dir = ( p.dx or 1 ) >= 0 and 1 or -1
		for i = 1, 12 do
			px = px + dir * 11
			local gx, gy = ground_below( px, py - 20, 80 )
			if not gx then break end
			local sx, sy = math.floor( px + 0.5 ), math.floor( gy - 0.5 )
			py = gy - 6
			local comp = EntityAddComponent2( e, "LightComponent", { radius = 0, r = 190, g = 255, b = 170,
				offset_x = sx - x, offset_y = sy - y - 2, fade_out_time = 0.5 } )
			stones[#stones + 1] = string.format( "%d,%d,%d", sx, sy, comp )
		end
		effect_set( e, "stones", table.concat( stones, ";" ) )
		p.stones = table.concat( stones, ";" )
		effect_sound( "grow", x, y )
	end
	if done( e, p, age ) then return end
	if age % 4 ~= 0 then return end
	local i = 0
	for sx, sy, comp in effect_text( p.stones ):gmatch( "(-?%d+),(-?%d+),(%d+)" ) do
		i = i + 1
		sx, sy, comp = tonumber( sx ), tonumber( sy ), tonumber( comp )
		local pressed = false
		for _, id in ipairs( EntityGetInRadiusWithTag( sx, sy, 18, "mortal" ) or {} ) do
			local ix, iy = EntityGetTransform( id )
			local box = EntityGetFirstComponent( id, "HitboxComponent" )
			local feet = iy + ( box and ComponentGetValue2( box, "aabb_max_y" ) or 2 )
			if math.abs( ix - sx ) <= 7 and math.abs( feet - sy ) <= 4 then pressed = true end
		end
		local last = p["lit" .. i] or -300
		if pressed then
			if age - last > 12 then fx_burst( sx, sy - 2, effect_color( "light", 0.7 ), 12, 18, 0.35 ) end
			last = age
			effect_set( e, "lit" .. i, age )
		end
		local fade = math.max( 0, 1 - ( age - last ) / 180 )
		ComponentSetValue2( comp, "radius", fade * 45 )
		fx_line( sx - 4, sy - 1, sx + 4, sy - 1, effect_color( "light", 0.2, 0.08 + fade * 0.65 ), 1, 0.1 )
		if fade > 0 then fx_dot( sx + Random( -3, 3 ), sy - 2, effect_color( "light", 0.6, fade ), 0, -4, 0.4 ) end
	end
end

-- Compatibility for effects created with the earlier pillar mode.
MODES.pillar = function( e, p, age, x, y )
    p.height, p.ancient = 320, 1
    MODES.column( e, p, age, x, y )
end

-- things worth finding, not in anyone's inventory
local function free( id )
	return EntityGetRootEntity( id ) == id
end

local function tracer_thread( x, y, tx, ty, age, fade, samples )
    local dx, dy = tx - x, ty - y
    local d = math.sqrt( dx * dx + dy * dy )
    if d < 1 then return end
    local n = math.max( 2, math.min( samples, math.ceil( d / 1.5 ) ) )
    -- Distribute a frame's samples along every connection. Their short-lived
    -- trails fill the gaps over three frames when a large graph needs fewer dots.
    for i = 0, n - 1 do
        local t = ( i + ( age % 3 ) / 3 ) / n
        local px, py = x + dx * t, y + dy * t
        fx_dot( px, py, effect_color( "light", 1, fade * 0.9 ), 0, 0, 0.07 )
        if i % 3 == 0 then
            local wave = math.sin( t * 12 - age * 0.075 ) * 1.5 * math.sin( t * math.pi )
            fx_dot( px - dy / d * wave, py + dx / d * wave,
                effect_color( "light", 0.35, fade * 0.4 ), 0, 0, 0.09 )
        end
    end
    if age % 4 == 0 then
        local t = ( age % 70 ) / 70
        fx_dot( x + dx * t, y + dy * t, effect_color( "light", 1, fade ), 0, 0, 0.1 )
    end
end

-- Each pair of marked targets in a group gets one connection. A held book
-- adds the caster as a node; switching items removes only the caster's rays.
MODES.tracer = function( e, p, age )
    if done( e, p, age ) then return end
    local nodes = {}
    for _, id in ipairs( EntityGetWithTag( "witch_light_fragment" ) or {} ) do
        if EntityGetIsAlive( id ) and effect_params( id ).witch_fragment_group == p.group then
            local x, y = effect_tracer_position( id )
            if x then nodes[#nodes + 1] = { id = id, x = x, y = y } end
        end
    end
    if #nodes == 0 then EntityKill( e ); return end
    table.sort( nodes, function( a, b ) return a.id < b.id end )
    local source, anchor = math.floor( p.source or 0 ), nodes[1]
    for _, node in ipairs( nodes ) do if node.id == source then anchor = node; break end end
    if anchor.id ~= source then effect_set( e, "source", anchor.id ) end
    local x, y = anchor.x, anchor.y
    EntitySetTransform( e, x, y )
    local fade = math.min( 1, ( p.frames - age ) / 30 )
    -- Reset lights when a target dies or leaves the group.
    for _, comp in ipairs( EntityGetComponent( e, "LightComponent" ) or {} ) do ComponentSetValue2( comp, "radius", 0 ) end
    local owner = effect_owner( p )
    if owner then
        local inv = EntityGetFirstComponentIncludingDisabled( owner, "Inventory2Component" )
        local held = inv and ComponentGetValue2( inv, "mActiveItem" ) or 0
        if held ~= 0 and EntityGetIsAlive( held ) and EntityHasTag( held, "witch_spellbook" ) then
            local ox, oy = EntityGetTransform( owner )
            nodes[#nodes + 1] = { x = ox + ( p.book_dx or 0 ), y = oy + ( p.book_dy or -4 ) }
        end
    end
    local links = {}
    for i, a in ipairs( nodes ) do
        if a.id then
            effect_point_light( e, "fragment_" .. tostring( a.id ), a.x, a.y, 45 * fade )
            orb( a.x, a.y, 2, age, fade * 0.6 )
        end
        for j = i + 1, #nodes do
            local b = nodes[j]
            local d2 = ( b.x - a.x ) ^ 2 + ( b.y - a.y ) ^ 2
            if d2 > 1 and d2 <= 450 ^ 2 then
                links[#links + 1] = { a, b }
            end
        end
    end
    -- Keep every pair, reducing particle density as the graph grows rather
    -- than dropping targets or drawing duplicate connections.
    local samples = math.max( 2, math.min( 300, math.floor( 1800 / math.max( 1, #links ) ) ) )
    for _, link in ipairs( links ) do
        local a, b = link[1], link[2]
        tracer_thread( a.x, a.y, b.x, b.y, age, fade, samples )
    end
end

-- A decorative valance leech: a net of tentacles with open cells and suckers.
-- The species is lattice-shaped, rather than an ordinary worm. It is a light
-- sculpture rather than a hunting creature or a parasitic damage effect.
MODES.leech = function( e, p, age, x, y )
    if done( e, p, age ) then return end
    if age == 0 then EntityAddComponent2( e, "LightComponent", { radius = 85, r = 255, g = 240, b = 180, fade_out_time = 1 } ) end
    local scale = p.big * math.min( 1, ( age + 1 ) / 25 )
    local fade = math.min( 1, ( p.frames - age ) / 40 )
    local nodes = { {-17,-10}, {0,-13}, {16,-9}, {-19,2}, {1,0}, {18,3}, {-15,13}, {-1,15}, {17,12},
        {-25,-16}, {-2,-23}, {25,-15}, {-29,5}, {29,5}, {-23,23}, {-2,26}, {25,22} }
    local edges = { {1,2}, {2,3}, {4,5}, {5,6}, {7,8}, {8,9}, {1,4}, {4,7}, {2,5}, {5,8}, {3,6}, {6,9},
        {1,10}, {2,11}, {3,12}, {4,13}, {6,14}, {7,15}, {8,16}, {9,17} }
    for i, q in ipairs( nodes ) do
        q[1] = x + ( q[1] + math.sin( age * 0.04 + i * 1.3 ) * 1.5 ) * scale
        q[2] = y + ( q[2] + math.cos( age * 0.035 + i ) * 1.5 ) * scale
    end
    for _, edge in ipairs( edges ) do
        local a, b = nodes[edge[1]], nodes[edge[2]]
        local d = math.sqrt( ( b[1]-a[1] ) ^ 2 + ( b[2]-a[2] ) ^ 2 )
        for k = 0, math.max( 1, math.ceil( d ) ) do
            local t = k / math.max( 1, math.ceil( d ) )
            local bend = math.sin( t * math.pi ) * math.sin( age * 0.04 + edge[1] ) * 2 * scale
            local px, py = a[1] + ( b[1]-a[1] ) * t, a[2] + ( b[2]-a[2] ) * t + bend
            fx_dot( px, py - 0.7 * scale, effect_color( "light", 0.4, fade * 0.6 ), 0, 0, 0.06 )
            fx_dot( px, py + 0.7 * scale, effect_color( "light", 0.7, fade * 0.5 ), 0, 0, 0.06 )
        end
    end
    for i = 10, #nodes do fx_ring( nodes[i][1], nodes[i][2], 1.5 * scale,
        effect_color( "light", 0.7, fade * 0.8 ), 10, 0, 0.06 ) end
end

-- Tracking Spell: marks round the caster point to the nearest chest, wand and orb
local KINDS = {
	{ tag = "chest", color = { 255, 210, 90 } },
	{ tag = "wand", color = { 200, 130, 255 } },
	{ tag = "hittable", color = { 120, 230, 255 }, test = function( id ) return EntityGetFirstComponent( id, "OrbComponent" ) ~= nil end },
}
MODES.tracking = function( e, p, age )
	local owner, x, y = effect_follow( e, p, -6 )
	if not owner or done( e, p, age ) then return end
	if age % 90 == 0 then
		for k, kind in ipairs( KINDS ) do
			local best, best_d = 0, nil
			for _, id in ipairs( EntityGetWithTag( kind.tag ) or {} ) do
				if free( id ) and ( not kind.test or kind.test( id ) ) then
					local ix, iy = EntityGetTransform( id )
					local d = ( ix - x ) ^ 2 + ( iy - y ) ^ 2
					if not best_d or d < best_d then best, best_d = id, d end
				end
			end
			effect_set( e, "t" .. k, best )
			p["t" .. k] = best
		end
	end
	if age % 2 ~= 0 then return end
	for k, kind in ipairs( KINDS ) do
		local id = math.floor( ( p["t" .. k] or 0 ) + 0.5 )
		if id ~= 0 and EntityGetIsAlive( id ) then
			local ix, iy = EntityGetTransform( id )
			local dx, dy = ix - x, iy - y
			local d = math.sqrt( dx * dx + dy * dy )
			if d > 30 then
				dx, dy = dx / d, dy / d
				local r = 26 + 4 * k
				local c = color_abgr_merge( kind.color[1], kind.color[2], kind.color[3], 230 )
				-- an arrowhead at the mark's distance; closer things get a bigger mark
				local size = d < 300 and 3 or 2
				local ax, ay = x + dx * r, y + dy * r
				fx_dot( ax + dx * size, ay + dy * size, c, 0, 0, 0.05 )
				for s = -1, 1, 2 do
					fx_dot( ax - dx * size + dy * size * s, ay - dy * size - dx * size * s, c, 0, 0, 0.05 )
					fx_dot( ax + dy * size * 0.5 * s, ay - dx * size * 0.5 * s, c, 0, 0, 0.05 )
				end
			end
		end
	end
end

-- Sigil of Guidance: a guiding mark shines where it was cast; far from it, an arrow by the caster points the way
MODES.beacon = function( e, p, age, x, y )
	if done( e, p, age ) then return end
	if age == 0 then EntityAddComponent2( e, "LightComponent", { radius = 70, r = 200, g = 255, b = 230, fade_out_time = 1 } ) end
	local c = effect_color( p.element, 0.6 )
	-- a slowly turning star with a column of light
	for i = 0, 4 do
		local a = age * 0.03 + i / 5 * 2 * math.pi
		fx_dot( x + math.cos( a ) * 6, y + math.sin( a ) * 6, c, 0, 0, 0.06 )
		fx_dot( x + math.cos( a + 0.63 ) * 3, y + math.sin( a + 0.63 ) * 3, c, 0, 0, 0.06 )
	end
	if age % 3 == 0 then fx_dot( x + Random( -1, 1 ), y - Random( 4, 30 ), c, 0, -20, 0.4 ) end
	local owner = effect_owner( p )
	if owner and age % 3 == 0 then
		local ox, oy = EntityGetTransform( owner )
		local dx, dy = x - ox, y - oy
		local d = math.sqrt( dx * dx + dy * dy )
		if d > 80 then
			dx, dy = dx / d, dy / d
			for k = 0, 3 do fx_dot( ox + dx * ( 20 + k * 2 ), oy - 6 + dy * ( 20 + k * 2 ), c, 0, 0, 0.08 ) end
		end
	end
end

-- a flower drawn with particles: petals round a center, 'open' 0..1
local function flower( x, y, size, open, petal, center, spin, life, detail )
	detail = detail or 5
	for k = 0, 4 do
		local a = spin + k / 5 * 2 * math.pi
		for s = 0, detail do
			local t = s / detail
			local w = math.sin( t * math.pi ) * 0.45
			local r = size * open * t
			fx_dot( x + math.cos( a + w ) * r, y + math.sin( a + w ) * r, petal, 0, 0, life )
			fx_dot( x + math.cos( a - w ) * r, y + math.sin( a - w ) * r, petal, 0, 0, life )
		end
	end
	fx_dot( x, y, center, 0, 0, life )
end

-- The Flower frame: flowers bloom where it was cast - of light they shine long, of water a rose opens and splashes,
-- of sand they set solid to stand on, of fire they burn
local FLOWER_KIND = { water = "water", storm = "water", ice = "water", shimmer = "water", steam = "water", mud = "water",
	sand = "sand", earth = "sand", stone = "sand", crystal = "sand", sandstorm = "sand",
	fire = "fire", plasma = "fire", lava = "fire", firestorm = "fire", smog = "fire" }
MODES.bloom = function( e, p, age, x, y )
	local kind = FLOWER_KIND[p.element] or "light"
	if age == 0 then
		local spots = {}
		local count = kind == "water" and 1 or 4
		for i = 1, count do
			local spacing = kind == "light" and 24 or 13
			local fx, fy = x + ( count > 1 and ( i - ( count + 1 ) / 2 ) * spacing or 0 ), y
			if kind == "sand" then
				local gx, gy = ground_below( fx, fy - 20, 60 )
				if gy then fy = gy - 6 end
				solid_piece( "sand_flower", fx, fy, p.frames )
			elseif kind ~= "water" then
				fy = fy + Random( -5, 5 )
			end
			spots[#spots + 1] = string.format( "%d,%d", math.floor( fx + 0.5 ), math.floor( fy + 0.5 ) )
		end
		effect_set( e, "spots", table.concat( spots, ";" ) )
		p.spots = table.concat( spots, ";" )
		if kind == "light" then EntityAddComponent2( e, "LightComponent", { radius = 110, r = 255, g = 240, b = 180, fade_out_time = 1 } ) end
		effect_sound( "grow", x, y )
	end
	if age >= p.frames then
		if kind == "water" then fx_material( "water", x, y, 80, 10, 0, 30 ) end
		EntityKill( e )
		return
	end
	local open = math.min( 1, age / 40 )
	local i = 0
	for fx, fy in effect_text( p.spots ):gmatch( "(-?%d+),(-?%d+)" ) do
		i = i + 1
		fx, fy = tonumber( fx ), tonumber( fy )
		if kind == "water" then
			-- a rose of water turning slowly, bigger and bigger
			local c = fx_color( "water", 0.3 + 0.3 * open, 0.9 )
			flower( fx, fy, 16, open, c, fx_color( "water", 0.9 ), age * 0.02, 0.05 )
			flower( fx, fy, 9, open, fx_color( "water", 0.6 ), c, -age * 0.03 + 0.6, 0.05 )
		elseif kind == "fire" then
			if age % 2 == 0 then flower( fx, fy, 8, open, fx_color( "fire", 0.2 ), fx_color( "fire", 0.9 ), age * 0.05 + i, 0.08 ) end
			if age % 8 == 0 and open >= 1 then GameCreateParticle( "fire", fx + Random( -6, 6 ), fy + Random( -6, 6 ), 1, 0, -10, false, false, true ) end
		elseif kind == "sand" then
			if age < 50 and age % 2 == 0 then flower( fx, fy, 8, open, fx_color( "sand", 0.2 ), fx_color( "sand", 0.6 ), i, 0.1 ) end
		else
			local unfurl = math.min( 1, math.max( 0, ( age - i * 7 ) / 35 ) )
			local fade = math.min( 1, ( p.frames - age ) / 60 )
			local cy = fy + math.sin( age * 0.035 + i ) * 1.2
			flower( fx, cy, 9, unfurl, effect_color( p.element, 0.45, 0.5 * fade ),
				effect_color( p.element, 1, fade ), i * 1.3, 0.06, 12 )
			flower( fx, cy, 5, unfurl, effect_color( p.element, 0.7, 0.2 * fade ),
				effect_color( p.element, 1, fade ), i * 1.3 + math.pi / 5, 0.06, 8 )
			if ( age + i * 3 ) % 9 == 0 and unfurl > 0 then
				fx_dot( fx + Random( -6, 6 ), cy, effect_color( p.element, 0.5, fade * 0.4 ), 0, -8, 0.65 )
			end
		end
	end
end

EFFECT_MODES.light = MODES
