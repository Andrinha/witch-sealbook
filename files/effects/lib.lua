-- The seals' magic that lasts (manifest.lua): an effect entity keeps its parameters in VariableStorageComponents and
-- effects/run.lua runs it every frame by its kind and mode - effects/<kind>.lua registers the modes of a kind in
-- EFFECT_MODES[kind]. A mode is function( e, p, age, x, y ): p its parameters, age frames since it was made; it ends
-- the effect itself (EntityKill) when its time is up. Shared helpers for the modes.

dofile_once( "data/scripts/lib/utilities.lua" )
dofile_once( "mods/witch_notebook/files/dictionary.lua" )
dofile_once( "mods/witch_notebook/files/fx.lua" )
dofile_once( "mods/witch_notebook/files/resonances.lua" ) -- how much the resonances' lasting magic does

EFFECTS = "mods/witch_notebook/files/effects/"
SOLID = "mods/witch_notebook/files/entities/solid/"
EFFECT_MODES = EFFECT_MODES or {}
MISC = "data/entities/misc/"

-- Creates an effect of 'kind' (effects/<kind>.lua) and 'mode'; params: numbers, strings or booleans
function effect_spawn( kind, mode, x, y, params, every )
	local e = EntityCreateNew( "witch_" .. kind .. "_" .. mode )
	EntitySetTransform( e, x, y )
	params = params or {}
	params.kind, params.mode = kind, mode -- 'born' is set when it first runs (run.lua): its first frame is age 0
	for k, v in pairs( params ) do
		if type( v ) == "number" then
			EntityAddComponent2( e, "VariableStorageComponent", { name = k, value_float = v } )
		elseif type( v ) == "boolean" then
			EntityAddComponent2( e, "VariableStorageComponent", { name = k, value_bool = v } )
		else
			EntityAddComponent2( e, "VariableStorageComponent", { name = k, value_string = tostring( v ) } )
		end
	end
	EntityAddComponent2( e, "LuaComponent", { script_source_file = EFFECTS .. "run.lua", execute_every_n_frame = every or 1,
		vm_type = "SHARED_BY_MANY_COMPONENTS" } )
	-- a seal drawn with golden ink: its magic shines in the dark
	if ( params.glow or 0 ) > 0 then
		EntityAddComponent2( e, "LightComponent", { radius = math.floor( 80 + 120 * params.glow ), r = 255, g = 205, b = 110,
			fade_out_time = 0.5 } )
	end
	return e
end

-- The effect's parameters: name -> number, string or boolean (as 1 / 0)
function effect_params( e )
	local out = {}
	for _, comp in ipairs( EntityGetComponent( e, "VariableStorageComponent" ) or {} ) do
		local name = ComponentGetValue2( comp, "name" )
		local s = ComponentGetValue2( comp, "value_string" )
		if s ~= nil and s ~= "" then
			out[name] = s
		else
			local f = ComponentGetValue2( comp, "value_float" )
			if f ~= 0 then out[name] = f else out[name] = ComponentGetValue2( comp, "value_bool" ) and 1 or 0 end
		end
	end
	return out
end

function effect_set( e, name, value )
	for _, comp in ipairs( EntityGetComponent( e, "VariableStorageComponent" ) or {} ) do
		if ComponentGetValue2( comp, "name" ) == name then
			if type( value ) == "number" then ComponentSetValue2( comp, "value_float", value )
			else ComponentSetValue2( comp, "value_string", tostring( value ) ) end
			return
		end
	end
	if type( value ) == "number" then
		EntityAddComponent2( e, "VariableStorageComponent", { name = name, value_float = value } )
	else
		EntityAddComponent2( e, "VariableStorageComponent", { name = name, value_string = tostring( value ) } )
	end
end

-- a text parameter (a list kept as text): an empty one comes back as 0
function effect_text( v )
	return type( v ) == "string" and v or ""
end

-- Local illumination uses the same fog-mask SpriteComponent as vanilla torches.
-- Keep it on the source entity so motion, expiry and destruction affect both.
function effect_light_visibility( e, vars )
	vars = vars or effect_params( e )
	for _, light in ipairs( EntityGetComponentIncludingDisabled( e, "LightComponent" ) or {} ) do
		-- LightComponent ignores later radius/offset changes unless this is enabled.
		ComponentSetValue2( light, "update_properties", true )
		local radius = ComponentGetIsEnabled( light ) and ComponentGetValue2( light, "radius" ) or 0
		local dx, dy = ComponentGetValue2( light, "offset_x" ), ComponentGetValue2( light, "offset_y" )
		local key = "fog_light_" .. tostring( light )
		local sprite = vars[key]
		if not sprite or sprite == 0 then
			sprite = EntityAddComponent2( e, "SpriteComponent", { _tags = "witch_light_visibility",
				image_file = "data/particles/fog_of_war_hole_128.xml", fog_of_war_hole = true,
				alpha = 0.85, smooth_filtering = true, has_special_scale = true,
				update_transform = true, update_transform_rotation = false, visible = false } )
			effect_set( e, key, sprite )
		end
		local scale = math.max( 0.001, radius / 64 )
		local ox, oy = ComponentGetValue2( sprite, "transform_offset" )
		local changed = ComponentGetValue2( sprite, "special_scale_x" ) ~= scale
			or ox ~= dx or oy ~= dy or ComponentGetValue2( sprite, "visible" ) ~= ( radius > 0 )
		ComponentSetValue2( sprite, "transform_offset", dx, dy )
		ComponentSetValue2( sprite, "special_scale_x", scale )
		ComponentSetValue2( sprite, "special_scale_y", scale )
		ComponentSetValue2( sprite, "visible", radius > 0 )
		if changed then EntityRefreshSprite( e, sprite ) end
	end
end

-- A moving point on a larger effect, e.g. the remote end of a Light Tracer.
function effect_point_light( e, key, x, y, radius )
	local comp = effect_params( e )["point_light_" .. key]
	if not comp or comp == 0 then
		comp = EntityAddComponent2( e, "LightComponent", { update_properties = true, radius = 0,
			r = 255, g = 240, b = 180, fade_out_time = 0.5 } )
		effect_set( e, "point_light_" .. key, comp )
	end
	local ex, ey = EntityGetTransform( e )
	ComponentSetValue2( comp, "offset_x", x - ex )
	ComponentSetValue2( comp, "offset_y", y - ey )
	ComponentSetValue2( comp, "radius", radius )
	return comp
end

-- frames since the effect was made
function effect_age( p )
	return GameGetFrameNum() - ( p.born or 0 )
end

-- Some PhysicsBody2 props discard their entity after initialization. A tracer
-- marker can follow the remaining Box2D body without modifying the prop itself.
function effect_tracer_position( id )
	local body = tonumber( effect_params( id ).witch_tracer_body )
	if body and body ~= 0 then
		local px, py = PhysicsBodyIDGetWorldCenter( math.floor( body ) )
		if not px then EntityKill( id ); return end
		local x, y = PhysicsPosToGamePos( px, py )
		EntitySetTransform( id, x, y )
		return x, y
	end
	return EntityGetTransform( EntityGetRootEntity( id ) )
end

-- the caster (or whoever the effect is on), if still there
function effect_owner( p )
	local id = math.floor( ( p.owner or 0 ) + 0.5 )
	if id > 0 and EntityGetIsAlive( id ) then return id end
end

-- Its time is up: the effect ends. True when it did.
function effect_done( e, p, age )
	if age >= p.frames then
		EntityKill( e )
		return true
	end
end

-- a light of the effect's own, fading out over 'fade' seconds when it ends
function effect_glow( e, r, g, b, radius, fade )
	return EntityAddComponent2( e, "LightComponent", { radius = radius, r = r, g = g, b = b, fade_out_time = fade } )
end

-- the effect follows its owner; returns the owner's position, or nil when the owner is gone (the effect ends)
function effect_follow( e, p, dy )
	local owner = effect_owner( p )
	if not owner then
		EntityKill( e )
		return
	end
	local x, y = EntityGetTransform( owner )
	EntitySetTransform( e, x, y + ( dy or 0 ) )
	return owner, x, y + ( dy or 0 )
end

function player_entity()
	return EntityGetWithTag( "player_unit" )[1]
end

-- the element's color for particles; 'element' may be empty (a misfire, a seal without a sigil)
function effect_color( element, white, alpha )
	if not element or element == "" or not DICTIONARY_ELEMENTS[element] then element = "light" end
	return fx_color( element, white, alpha )
end

-- living creatures around x, y except the caster and what the caster's magic made for enemies to attack (the golem,
-- the puppets: 'witch_decoy'): enemies, animals, and the player too when 'with_player'
function creatures_in( x, y, r, caster, with_player )
	local out, seen = {}, {}
	for _, tag in ipairs( { "enemy", "mortal" } ) do
		for _, id in ipairs( EntityGetInRadiusWithTag( x, y, r, tag ) or {} ) do
			if not seen[id] and id ~= caster and not EntityHasTag( id, "witch_decoy" ) and ( with_player or not EntityHasTag( id, "player_unit" ) )
				and EntityGetFirstComponent( id, "DamageModelComponent" ) then
				seen[id] = true
				out[#out + 1] = id
			end
		end
	end
	return out
end

-- the creature nearest to x, y within r (not the caster, not the player)
function nearest_creature( x, y, r, caster )
	local best, best_d
	for _, id in ipairs( creatures_in( x, y, r, caster ) ) do
		local ex, ey = EntityGetTransform( id )
		local d = ( ex - x ) ^ 2 + ( ey - y ) ^ 2
		if not best_d or d < best_d then best, best_d = id, d end
	end
	return best
end

-- a creature's body by its hitbox: how far its middle is from its feet (negative: up), and half its diagonal
function creature_body( id )
	local box = EntityGetFirstComponentIncludingDisabled( id, "HitboxComponent" )
	if box then
		local x0, x1 = ComponentGetValue2( box, "aabb_min_x" ), ComponentGetValue2( box, "aabb_max_x" )
		local y0, y1 = ComponentGetValue2( box, "aabb_min_y" ), ComponentGetValue2( box, "aabb_max_y" )
		if type( x0 ) == "number" and type( x1 ) == "number" and type( y0 ) == "number" and type( y1 ) == "number" and y0 < y1 then
			return ( y0 + y1 ) / 2, math.sqrt( ( x1 - x0 ) ^ 2 + ( y1 - y0 ) ^ 2 ) / 2
		end
	end
	return -5, 8
end

-- a creature's own velocity (characters) or nil
function creature_velocity( id )
	local cd = EntityGetFirstComponent( id, "CharacterDataComponent" )
	if cd then return cd, ComponentGetValue2( cd, "mVelocity" ) end
	local v = EntityGetFirstComponent( id, "VelocityComponent" )
	if v then return v, ComponentGetValue2( v, "mVelocity" ) end
end

function push_creature( id, vx, vy, set )
	local comp, ox, oy = creature_velocity( id )
	if not comp then return end
	if set then ComponentSetValue2( comp, "mVelocity", vx, vy ) else ComponentSetValue2( comp, "mVelocity", ox + vx, oy + vy ) end
end

-- pushes a creature away from (or, negative, towards) x, y
function push_from( id, x, y, strength )
	local ex, ey = EntityGetTransform( id )
	local dx, dy = ex - x, ey - y
	local d = math.max( 1, math.sqrt( dx * dx + dy * dy ) )
	push_creature( id, dx / d * strength, dy / d * strength )
end

-- Holds a creature where it is for 'frames' (bound by a ribbon, frozen in time, sealed with wax, in a ball of water):
-- effects/held.lua keeps it in place and lets it go by itself. look: ribbon, time, wax, water, sand. 'extra': more
-- parameters for the look (the Water Cage's: which cage, and where its middle is)
function hold_creature( id, frames, look, element, caster, extra )
	if not EntityGetIsAlive( id ) then return end
	local was = held_as( id, look or "ribbon" )
	if was then EntityKill( was ) end
	local x, y = EntityGetTransform( id )
	local params = { frames = frames, element = element or "light", hx = x, hy = y, owner = id, caster = caster or 0 }
	for k, v in pairs( extra or {} ) do params[k] = v end
	local e = effect_spawn( "held", look or "ribbon", x, y, params )
	EntityAddChild( id, e )
	return e
end

-- how a creature held by an element looks (hold_creature): water and sand have their own, the rest stand still in time
HIT_LOOK = { water = "water", ice = "water", storm = "water", steam = "water", sand = "sand", earth = "sand", stone = "sand",
	mud = "sand", sandstorm = "sand" }

-- Reflection (a field, a sphere, a wave): enemies' projectiles between lo and hi from x, y that are coming in turn back
-- the way they came, as the caster's own
function reflect_projectiles( x, y, lo, hi, owner )
	local genome = owner ~= 0 and EntityGetFirstComponent( owner, "GenomeDataComponent" )
	for _, id in ipairs( EntityGetInRadiusWithTag( x, y, hi, "projectile" ) or {} ) do
		local proj = EntityGetFirstComponent( id, "ProjectileComponent" )
		local vel = EntityGetFirstComponent( id, "VelocityComponent" )
		if proj and vel and ComponentGetValue2( proj, "mWhoShot" ) ~= owner then
			local px, py = EntityGetTransform( id )
			local dx, dy = px - x, py - y
			local vx, vy = ComponentGetValue2( vel, "mVelocity" )
			if dx * dx + dy * dy >= lo * lo and dx * vx + dy * vy < 0 then
				ComponentSetValue2( vel, "mVelocity", -vx, -vy )
				ComponentSetValue2( proj, "mWhoShot", owner )
				if genome then ComponentSetValue2( proj, "mShooterHerdId", ComponentGetValue2( genome, "herd_id" ) ) end
				fx_burst( px, py, fx_color( "air", 1 ), 8, 40, 0.3 )
			end
		end
	end
end

-- the effect that holds the creature with this look, if any
function held_as( id, look )
	for _, child in ipairs( EntityGetAllChildren( id ) or {} ) do
		if EntityGetName( child ) == "witch_held_" .. look then return child end
	end
end

-- Damage done by the seal's caster
function seal_damage( target, amount, kind, caster, x, y )
	if not EntityGetIsAlive( target ) then return end
	local tx, ty = EntityGetTransform( target )
	EntityInflictDamage( target, amount, kind or "DAMAGE_PROJECTILE", "Seal", "NONE", 0, 0, caster or 0, x or tx, y or ty, 0 )
end

-- A status effect (data/entities/misc/effect_*.xml) for 'frames'
function give_effect( target, file, frames )
	local eff = LoadGameEffectEntityTo( target, file )
	if eff and eff ~= 0 and frames then
		local comp = EntityGetFirstComponentIncludingDisabled( eff, "GameEffectComponent" )
		if comp then ComponentSetValue2( comp, "frames", math.floor( frames ) ) end
	end
	return eff
end

-- Ends game effects (FROZEN, ON_FIRE, BLINDNESS...) and stains (WET, OILED...) on the target
function clear_effects( target, names )
	for _, name in ipairs( names ) do
		local comp = GameGetGameEffect( target, name )
		if comp and comp ~= 0 then ComponentSetValue2( comp, "frames", 1 ) end
		EntityRemoveStainStatusEffect( target, name, 0 )
	end
end
DIRT = { "WET", "OILED", "BLOODY", "SLIMY", "RADIOACTIVE", "POISONED", "ON_FIRE", "JARATE" }

-- where a ray from x, y going dx, dy first hits ground, within 'len' (or the end of the ray)
function ground_along( x, y, dx, dy, len )
	local hit, hx, hy = RaytraceSurfaces( x, y, x + dx * len, y + dy * len )
	if hit then return hx, hy, true end
	return x + dx * len, y + dy * len, false
end

-- the ground under x, y (within 'depth'), or nil
function ground_below( x, y, depth )
	local hit, hx, hy = RaytracePlatforms( x, y, x, y + ( depth or 200 ) )
	if hit then return hx, hy end
end

-- the solid piece an element sets into (Solidification, the Rampart): its kind, stone by default
SOLID_PIECES = { water = "ice_block", ice = "ice_block", storm = "ice_block", frost = "ice_block", crystal = "crystal_block",
	sand = "sand_block", sandstorm = "sand_block", mud = "sand_block", light = "light_plank", beam = "light_plank" }

-- A solid piece (entities/solid/<kind>.xml: a static body one can stand on) at x, y; it crumbles after 'frames'
function solid_piece( kind, x, y, frames )
	local e = EntityLoad( SOLID .. kind .. ".xml", x, y )
	if frames then EntityAddComponent2( e, "LifetimeComponent", { lifetime = math.floor( frames ) } ) end
	return e
end

-- Turns materials around the effect into others while it lasts (the game's own conversion, a circle)
function convert_around( e, from, to, radius, steps )
	return EntityAddComponent2( e, "MagicConvertMaterialComponent", {
		from_material_array = from, to_material_array = to, radius = math.floor( radius ), is_circle = true,
		loop = true, kill_when_finished = false, steps_per_frame = steps or 4,
	} )
end

-- Material sets for conversions: every name must exist (tests/effects_smoke.py checks them)
MELTS = { from = "snow,snow_sticky,ice_static,ice,ice_glass,ice_cold_static,ice_cold_glass,ice_blood_static,ice_slime_static",
	to = "water,water,water,water,water,water,water,blood,slime" }
FOULS = { from = "water_swamp,swamp,radioactive_liquid,poison,slime,water_salt,pus,cursed_liquid,mud,urine,acid",
	to = "water,water,water,water,water,water,water,water,water,water,water" }
-- Purify: what the seal on the waste purification pot makes clean - acid, poison and toxic sludge, slimes, foul
-- and salt water, blood and other filth. Every cell becomes a cell of water; none is added.
PURIFIES = { from = FOULS.from .. ",radioactive_liquid_yellow,radioactive_liquid_fading,slime_green,slime_yellow,vomit,blood,blood_fungi,blood_worm,blood_cold,material_darkness",
	to = FOULS.to .. ",water,water,water,water,water,water,water,water,water,water" }
-- Integration: loose sand and earth come back together into stone, loose snow into packed snow - cell for cell,
-- the Wall Breaker's work undone. Nothing is added.
INTEGRATES = { from = "sand,sand_blue,sand_surface,soil,soil_lush,soil_dead,soil_dark,soil_lush_dark,fungisoil,snow,snow_sticky",
	to = "rock_static,rock_static,rock_static,rock_static,rock_static,rock_static,rock_static,rock_static,rock_static,snow_static,snow_static" }
BOILS = { from = "water,water_salt,water_swamp,swamp,water_ice,blood_cold,mud,urine",
	to = "steam,steam,steam,steam,steam,steam,steam,steam" }
FREEZES = { from = "water,water_salt,water_swamp,swamp,blood,slime,mud",
	to = "ice_static,ice_static,ice_static,ice_static,ice_blood_static,ice_slime_static,ice_static" }

function effect_sound( event, x, y )
	local banks = { magic = { "data/audio/Desktop/projectiles.bank", "projectiles/magic/create" },
		fire_jet = { "data/audio/Desktop/projectiles.bank", "player_projectiles/flamethrower/create" },
		fire_shot = { "data/audio/Desktop/projectiles.bank", "player_projectiles/bullet_fire_heavy/create" },
		fire_ring = { "data/audio/Desktop/projectiles.bank", "player_projectiles/circle_of/create" },
		fire_blast = { "data/audio/Desktop/explosion.bank", "explosions/magic_rocket_big" },
		laser = { "data/audio/Desktop/projectiles.bank", "player_projectiles/bullet_laser/create" },
		teleport = { "data/audio/Desktop/misc.bank", "misc/teleport_use" },
		grow = { "data/audio/Desktop/misc.bank", "misc/root_grow" },
		curse = { "data/audio/Desktop/game_effect.bank", "game_effect/polymorph/create" },
		angry = { "data/audio/Desktop/event_cues.bank", "event_cues/angered_the_gods/create" },
		statue = { "data/audio/Desktop/animals.bank", "animals/statue/appear" },
		earth = { "data/audio/Desktop/projectiles.snd", "player_projectiles/crumbling_earth/create" },
		beam = { "data/audio/Desktop/misc.bank", "misc/beam_from_sky_hit" },
		heart = { "data/audio/Desktop/event_cues.bank", "event_cues/heart_fullhp/create" },
	}
	local s = banks[event] or banks.magic
	GamePlaySound( s[1], s[2], x, y )
end

-- A looping sound owned by the source, so movement and destruction also
-- move/stop it. Reuse the saved component on renewal and after reload.
-- Disabled sources (e.g. a plume submerged in water) can resume without stacking.
function effect_loop( e, active, file, event )
	local comp
	for _, c in ipairs( EntityGetComponentIncludingDisabled( e, "AudioLoopComponent" ) or {} ) do
		if ComponentGetValue2( c, "event_name" ) == event then comp = c; break end
	end
	if not comp then
		comp = EntityAddComponent2( e, "AudioLoopComponent", { _enabled = active, file = file, event_name = event,
			auto_play_if_enabled = true, play_on_component_enable = true } )
	end
	if ComponentGetIsEnabled( comp ) ~= active then EntitySetComponentIsEnabled( e, comp, active ) end
end

-- Vanilla torch crackle.
function effect_fire_loop( e, active )
	effect_loop( e, active, "data/audio/Desktop/projectiles.bank", "player_projectiles/torch/loop" )
end

-- A spell held with a book (cast.lua spellbook_use sets channel_book and channel_spell): the caster and their
-- controls while fire is still held with that book in hand and that page active, nil once it is let go.
-- Live controls are read here, so releasing or switching items ends the spell even if the book's own
-- enabled_in_hand script is disabled, or its entity is dropped or deleted.
function effect_channel( p )
	dofile_once( "mods/witch_notebook/files/books.lua" )
	local owner = effect_owner( p )
	local book = p.channel_book
	local controls = owner and EntityGetFirstComponent( owner, "ControlsComponent" )
	local inv = owner and EntityGetFirstComponent( owner, "Inventory2Component" )
	if not controls or not inv or not EntityGetIsAlive( book )
		or EntityGetRootEntity( book ) ~= owner
		or ComponentGetValue2( inv, "mActiveItem" ) ~= book
		or ComponentGetValue2( controls, "enabled" ) == false
		or not ComponentGetValue2( controls, "mButtonDownFire" )
		or GlobalsGetValue( book_var( book_key_of( book ), "active_spell" ), "" ) ~= p.channel_spell
		or GameGetFrameNum() < ( tonumber( GlobalsGetValue( "witch_notebook.busy_until", "0" ) ) or 0 ) then
		return
	end
	return owner, controls
end

-- A sigil's shape as points (templates.lua TEMPLATES_SIGILS): { { x, y } } around 0, 0 within -0.5..0.5, for the
-- sculptures drawn in the air with particles; cached
local shapes = {}
function sigil_points( key, step )
	local cached = shapes[key]
	if cached then return cached end
	dofile_once( "mods/witch_notebook/files/templates.lua" )
	local variants = TEMPLATES_SIGILS and TEMPLATES_SIGILS[key]
	local template = variants and variants[1] -- its first drawing: a list of strokes of { x, y }
	local pts = {}
	if template then
		local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
		for _, stroke in ipairs( template ) do
			for _, q in ipairs( stroke ) do
				minx, maxx = math.min( minx, q[1] ), math.max( maxx, q[1] )
				miny, maxy = math.min( miny, q[2] ), math.max( maxy, q[2] )
			end
		end
		local size = math.max( maxx - minx, maxy - miny, 1e-6 )
		local cx, cy = ( minx + maxx ) / 2, ( miny + maxy ) / 2
		step = ( step or 0.035 ) * size
		for _, stroke in ipairs( template ) do
			for i = 1, #stroke do
				local a, b = stroke[i], stroke[i + 1] or stroke[i]
				local d = math.sqrt( ( b[1] - a[1] ) ^ 2 + ( b[2] - a[2] ) ^ 2 )
				local n = math.max( 1, math.floor( d / step ) )
				for k = 0, n - 1 do
					local t = k / n
					pts[#pts + 1] = { ( a[1] + ( b[1] - a[1] ) * t - cx ) / size, ( a[2] + ( b[2] - a[2] ) * t - cy ) / size }
				end
			end
		end
	end
	if #pts == 0 then
		for i = 0, 23 do pts[#pts + 1] = { 0.4 * math.cos( i / 24 * 2 * math.pi ), 0.4 * math.sin( i / 24 * 2 * math.pi ) } end
	end
	shapes[key] = pts
	return pts
end

-- The shape drawn with particles at x, y: 'size' pixels big, turned by 'angle', mirrored when 'flip'
function draw_shape( pts, x, y, size, angle, flip, color, life, share, vx, vy )
	local c, s = math.cos( angle or 0 ), math.sin( angle or 0 )
	local fx = flip and -1 or 1
	for i = 1, #pts do
		if not share or Random( 0, 1000 ) < share * 1000 then
			local px, py = pts[i][1] * size * fx, pts[i][2] * size
			fx_dot( x + px * c - py * s, y + px * s + py * c, color, vx or 0, vy or 0, life or 0.1 )
		end
	end
end
