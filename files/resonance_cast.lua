-- How the resonances (resonances.lua) are cast. For a seal that resonates cast.lua calls, on each projectile it makes,
-- RESONANCE_CAST[key].prepare (before it is shot) and .twist (after the signs' own behaviors); a resonance that makes
-- magic of its own has .cast instead, called in place of the seal's carriers (it may return nil: then the carriers come
-- as usual). The wave's and the ring's resonances are their manifestations' own (manifest.lua: Quake, Collapse, Tide,
-- Chain Storm, Rampart; Halo, Blade Dance, Guardian Lights), Magma is the Sign of Crushing's (cast.lua). 'kit': cast.lua's helpers - spawn (a carrier tuned by
-- the seal, with its signs), raw (a projectile as it is), add_script, add_var, add_death_script, convert, scale_size,
-- place (where at the cursor).

dofile_once( "mods/witch_notebook/files/resonances.lua" )

RESONANCE_CAST = {}
local C = RESONANCE_CAST
local RA = RESONANCE_AMOUNTS
local DECK = "data/entities/projectiles/deck/"
local DAMAGE_KINDS = { "projectile", "fire", "ice", "slice", "explosion", "electricity", "melee", "drill", "radioactive", "poison" }

local function comp( e, kind ) return EntityGetFirstComponentIncludingDisabled( e, kind ) end
local function nature( element, key ) return ( RESONANCE_NATURES[element] or {} )[key] == true end
local function aim_angle( ctx ) return math.atan2( ctx.aim_y, ctx.aim_x ) end

local function faster( e, k )
	local v = comp( e, "VelocityComponent" )
	if v then
		local vx, vy = ComponentGetValue2( v, "mVelocity" )
		ComponentSetValue2( v, "mVelocity", vx * k, vy * k )
	end
end

local function longer( e, k, add )
	local p = comp( e, "ProjectileComponent" )
	if p then
		local life = ComponentGetValue2( p, "lifetime" )
		if life > 0 then ComponentSetValue2( p, "lifetime", math.max( 1, math.floor( life * k + ( add or 0 ) ) ) ) end
	end
end

-- every kind of damage it deals, and its blast's, times k
local function harder( e, k )
	local p = comp( e, "ProjectileComponent" )
	if not p then return end
	ComponentSetValue2( p, "damage", ComponentGetValue2( p, "damage" ) * k )
	for _, kind in ipairs( DAMAGE_KINDS ) do
		local v = ComponentObjectGetValue2( p, "damage_by_type", kind )
		if type( v ) == "number" and v ~= 0 then ComponentObjectSetValue2( p, "damage_by_type", kind, v * k ) end
	end
	local blast = ComponentObjectGetValue2( p, "config_explosion", "damage" )
	if type( blast ) == "number" and blast ~= 0 then ComponentObjectSetValue2( p, "config_explosion", "damage", blast * k ) end
end

-- the resonance's own numbers (resonances.lua): how long its shot lasts, how fast it flies, how hard it strikes
local function tuned( e, key )
	local r = RESONANCE_BY_KEY[key]
	local p = comp( e, "ProjectileComponent" )
	if r.lasts and p then
		local life = ComponentGetValue2( p, "lifetime" )
		if life > 0 then ComponentSetValue2( p, "lifetime", r.lasts( life ) ) end
	end
	if r.speed then faster( e, r.speed ) end
	if r.damage and p then ComponentSetValue2( p, "damage", ComponentGetValue2( p, "damage" ) * r.damage ) end
end

local function bounces( e, n, energy )
	local p = comp( e, "ProjectileComponent" )
	if not p then return end
	ComponentSetValue2( p, "bounces_left", n )
	ComponentSetValue2( p, "bounce_always", true )
	ComponentSetValue2( p, "bounce_at_any_angle", true )
	ComponentSetValue2( p, "bounce_energy", energy )
end

-- the element a carrier of the mod's own can be made of: the spell's, or light
local function made_of( spell ) return DICTIONARY_LOOKS[spell.element] and spell.element or "light" end

---- shots ----

C.ricochet = { twist = function( kit, e, b )
	local p = comp( e, "ProjectileComponent" )
	if p then ComponentSetValue2( p, "collide_with_world", true ) end -- a ghostly shot too: it bounces off the walls
	bounces( e, RA.ricochet( b.reflect or 1 ).bounces, 0.9 )
	tuned( e, "ricochet" )
end }

C.drill = { twist = function( kit, e, b )
	local p = comp( e, "ProjectileComponent" )
	if p then
		ComponentSetValue2( p, "penetrate_world", true )
		ComponentSetValue2( p, "penetrate_world_velocity_coeff", 0.8 )
		ComponentSetValue2( p, "die_on_low_velocity", false )
	end
	tuned( e, "drill" )
	kit.convert( e, SIGN_CONVERTS.crush.from, SIGN_CONVERTS.crush.to, RA.drill( b.crush or 1 ).r )
	kit.add_script( e, "drill.lua", 2 )
end }

C.boomerang = { twist = function( kit, e, b )
	local p = comp( e, "ProjectileComponent" )
	local out = RA.boomerang( p and ComponentGetValue2( p, "lifetime" ) or 90 ).out
	tuned( e, "boomerang" )
	if p then
		ComponentSetValue2( p, "penetrate_entities", true )
		ComponentSetValue2( p, "die_on_low_velocity", false )
	end
	bounces( e, 4, 0.85 )
	kit.add_var( e, "witch_boomerang", out )
	kit.add_var( e, "witch_boomerang_turn", ( b.spin or 1 ) < 0 and -1 or 1 )
	kit.add_script( e, "boomerang.lua" )
end }

C.grapple = { twist = function( kit, e )
	local p = comp( e, "ProjectileComponent" )
	if p then ComponentSetValue2( p, "penetrate_entities", false ) end -- an airy shot too: the ribbon holds the first it strikes
	tuned( e, "grapple" )
	kit.add_script( e, "grapple_rope.lua" )
	kit.add_death_script( e, "grapple_on_hit.lua" )
end }

-- the game's own teleporting bolt does it: the component has to be there when the shot is fired
C.blink = {
	prepare = function( kit, e )
		EntityAddComponent2( e, "TeleportProjectileComponent", { min_distance_from_wall = 4, actionable_lifetime = 3,
			reset_shooter_y_vel = true } )
	end,
	twist = function( kit, e ) tuned( e, "blink" ) end,
}

-- the game's swapper does it: the creature the shot strikes and its shooter change places
C.exchange = {
	prepare = function( kit, e ) EntityAddComponent2( e, "HitEffectComponent", { effect_hit = "SWAPPER" } ) end,
	twist = function( kit, e ) tuned( e, "exchange" ) end,
}

C.limpet = { twist = function( kit, e, b, spell, carrier, ctx )
	kit.add_var( e, "witch_limpet_element", made_of( spell ) )
	kit.add_var( e, "witch_limpet_power", ctx.power or 1 )
	kit.add_death_script( e, "limpet_on_hit.lua" )
end }

C.swarm = { cast = function( kit, ctx, effect, px, py )
	local spell = ctx.spell
	local n = RA.swarm( spell.behaviors.pierce or 2 ).motes
	local base = aim_angle( ctx )
	local made = {}
	for i = 1, n do
		local a = base + ( ( i - 0.5 ) / n - 0.5 ) * math.rad( 150 ) + Random( -100, 100 ) / 100 * 0.08
		local e = kit.spawn( ctx, effect.file, px, py, math.cos( a ), math.sin( a ), spell, effect )
		kit.scale_size( e, 0.6 )
		harder( e, 0.45 )
		faster( e, 0.7 )
		longer( e, 1, 45 )
		local homing = comp( e, "HomingComponent" )
		if homing then
			ComponentSetValue2( homing, "homing_targeting_coeff", ComponentGetValue2( homing, "homing_targeting_coeff" ) * 2.5 )
			ComponentSetValue2( homing, "detect_distance", 220 )
		end
		made[#made + 1] = effect.file
	end
	return made
end }

C.cluster = { twist = function( kit, e, b, spell )
	kit.add_var( e, "witch_cluster", RA.cluster( b.pierce or 2 ).fragments )
	kit.add_var( e, "witch_cluster_element", made_of( spell ) )
	kit.add_death_script( e, "cluster_on_hit.lua" )
end }

C.satellite = { twist = function( kit, e, b, spell, carrier, ctx )
	local p = comp( e, "ProjectileComponent" )
	if p then
		ComponentSetValue2( p, "penetrate_entities", true )
		ComponentSetValue2( p, "die_on_low_velocity", false )
		ComponentSetValue2( p, "collide_with_world", false ) -- it circles its caster through the walls
	end
	local v = comp( e, "VelocityComponent" )
	if v then ComponentSetValue2( v, "gravity_y", 0 ) end
	tuned( e, "satellite" )
	kit.add_var( e, "witch_satellite_r", RA.satellite( b.grow ).r )
	kit.add_var( e, "witch_satellite_a", aim_angle( ctx ) )
	kit.add_var( e, "witch_satellite_turn", ( b.spin or 1 ) < 0 and -1 or 1 )
	kit.add_var( e, "witch_satellite_element", made_of( spell ) )
	kit.add_var( e, "witch_satellite_power", ctx.power or 1 )
	kit.add_script( e, "satellite.lua" )
end }

-- a breath: the game's real flames for a hot element, its freezing gaze for a cold one; any other blows its own drops
-- out in a quick spray
local BREATHS = {
	{ nature = "hot", file = DECK .. "flamethrower.xml", count = 3, cone = 20 },
	{ nature = "cold", file = DECK .. "freezing_gaze_beam.xml", count = 5, cone = 36 },
}
C.breath = { cast = function( kit, ctx, effect, px, py )
	local spell = ctx.spell
	local base = aim_angle( ctx )
	local made = {}
	for _, kind in ipairs( BREATHS ) do
		if nature( spell.element, kind.nature ) then
			for i = 1, kind.count do
				local a = base + ( ( i - 0.5 ) / kind.count - 0.5 ) * math.rad( kind.cone ) + Random( -100, 100 ) / 100 * 0.03
				kit.raw( ctx, kind.file, px, py, px + math.cos( a ) * 100, py + math.sin( a ) * 100 )
				made[#made + 1] = kind.file
			end
			return made
		end
	end
	if not DICTIONARY_LOOKS[spell.element] then return nil end
	local spray = { file = carrier_file( spell.element, "splash" ), carrier = "bolt", splash = true }
	local gusty = nature( spell.element, "airy" )
	for i = 1, 9 do
		local a = base + ( ( i - 0.5 ) / 9 - 0.5 ) * math.rad( 30 ) + Random( -100, 100 ) / 100 * 0.04
		local e = kit.spawn( ctx, spray.file, px, py, math.cos( a ), math.sin( a ), spell, spray )
		faster( e, 1.6 + Random( 0, 40 ) / 100 )
		longer( e, 2.5, 4 )
		local p = comp( e, "ProjectileComponent" )
		if p and gusty then ComponentSetValue2( p, "knockback_force", ComponentGetValue2( p, "knockback_force" ) + 120 ) end
		made[#made + 1] = spray.file
	end
	return made
end }

C.lance = { twist = function( kit, e )
	local p = comp( e, "ProjectileComponent" )
	if p then
		ComponentSetValue2( p, "penetrate_entities", true )
		ComponentSetValue2( p, "ground_penetration_coeff", 4 )
		ComponentSetValue2( p, "velocity_sets_rotation", true )
	end
	tuned( e, "lance" )
	local v = comp( e, "VelocityComponent" )
	if v then
		ComponentSetValue2( v, "mass", 0.6 )
		ComponentSetValue2( v, "air_friction", -0.3 )
	end
	for _, sprite in ipairs( EntityGetComponentIncludingDisabled( e, "SpriteComponent" ) or {} ) do
		local sx, sy = ComponentGetValue2( sprite, "special_scale_x" ), ComponentGetValue2( sprite, "special_scale_y" )
		ComponentSetValue2( sprite, "has_special_scale", true )
		ComponentSetValue2( sprite, "special_scale_x", ( sx or 1 ) * 3 )
		ComponentSetValue2( sprite, "special_scale_y", ( sy or 1 ) * 0.8 )
	end
end }

-- the game's sawblade, cutting with the element's own touch (it freezes, it burns...)
C.sawblade = { cast = function( kit, ctx, effect, px, py )
	local spell = ctx.spell
	local file = DECK .. "disc_bullet.xml"
	local n = math.max( 1, math.floor( spell.behaviors.pierce or 1 ) )
	local status = ( DICTIONARY_LOOKS[spell.element] or {} ).status
	local base = aim_angle( ctx )
	local made = {}
	for i = 1, n do
		local a = base + ( n > 1 and ( ( i - 1 ) / ( n - 1 ) - 0.5 ) * math.rad( 6 * n ) or 0 )
		local e = kit.spawn( ctx, file, px, py, math.cos( a ), math.sin( a ), spell, { carrier = "bolt", file = file } )
		local p = comp( e, "ProjectileComponent" )
		if p and status then
			ComponentSetValue2( p, "damage_game_effect_entities", ( ComponentGetValue2( p, "damage_game_effect_entities" ) or "" ) .. status .. "," )
		end
		made[#made + 1] = file
	end
	return made
end }

-- fire turned cold: ice in place of fire, freezing in place of burning, nothing alight, blue
local HOT_MATTER = { fire = true, lava = true }
C.frostfire = { twist = function( kit, e )
	local p = comp( e, "ProjectileComponent" )
	if p then
		local fire = ComponentObjectGetValue2( p, "damage_by_type", "fire" )
		if type( fire ) == "number" and fire > 0 then
			ComponentObjectSetValue2( p, "damage_by_type", "fire", 0 )
			local ice = ComponentObjectGetValue2( p, "damage_by_type", "ice" )
			ComponentObjectSetValue2( p, "damage_by_type", "ice", ( type( ice ) == "number" and ice or 0 ) + fire )
		end
		local effects = ( ComponentGetValue2( p, "damage_game_effect_entities" ) or "" ):gsub( "effect_apply_on_fire", "effect_frozen_short" )
		ComponentSetValue2( p, "damage_game_effect_entities", effects )
		ComponentObjectSetValue2( p, "config_explosion", "create_cell_probability", 0 )
		ComponentSetValue2( p, "on_death_emit_particle", false )
	end
	for _, em in ipairs( EntityGetComponentIncludingDisabled( e, "ParticleEmitterComponent" ) or {} ) do
		local m = ComponentGetValue2( em, "emitted_material_name" )
		if HOT_MATTER[m] then
			ComponentSetValue2( em, "is_emitting", false )
		elseif type( m ) == "string" and m:find( "^spark" ) then
			ComponentSetValue2( em, "emitted_material_name", "spark_blue" )
		end
	end
	for _, light in ipairs( EntityGetComponentIncludingDisabled( e, "LightComponent" ) or {} ) do
		ComponentSetValue2( light, "r", 110 )
		ComponentSetValue2( light, "g", 190 )
		ComponentSetValue2( light, "b", 255 )
	end
end }

---- an element's own way with a sign ----

-- Ice Coffin, Entomb, Cyclone: what the element does to whoever the shot strikes (behaviors/wrap_on_hit.lua)
local function wrap( key, amounts )
	return { twist = function( kit, e, b, spell )
		kit.add_var( e, "witch_wrap", key )
		kit.add_var( e, "witch_wrap_frames", amounts( b.envelop or 1 ).frames )
		kit.add_var( e, "witch_wrap_element", made_of( spell ) )
		kit.add_death_script( e, "wrap_on_hit.lua" )
	end }
end
C.ice_coffin = wrap( "coffin", RA.coffin )
C.entomb = wrap( "entomb", RA.entomb )
C.cyclone = wrap( "cyclone", RA.cyclone )

C.wisp = { twist = function( kit, e, b )
	tuned( e, "wisp" )
	local a = RA.wisp( b.homing or 1 )
	EntityAddComponent2( e, "HomingComponent", { homing_targeting_coeff = 160, homing_velocity_multiplier = 0.9, detect_distance = a.reach } )
	kit.add_var( e, "witch_wisp_confuse", a.confuse )
	kit.add_script( e, "wisp.lua", 4 )
end }

-- the game's fireworks: rockets that fly up and burst in colours (they don't hurt the caster here)
local FIREWORKS = { "firework_pink.xml", "firework_blue.xml", "firework_green.xml", "firework_orange.xml" }
C.fireworks = { cast = function( kit, ctx, effect, px, py )
	local n = RA.fireworks( ctx.spell.behaviors.pierce or 2 ).rockets
	local base = aim_angle( ctx )
	local made = {}
	for i = 1, n do
		local file = DECK .. "fireworks/" .. FIREWORKS[( i - 1 ) % #FIREWORKS + 1]
		local a = base + ( n > 1 and ( ( i - 1 ) / ( n - 1 ) - 0.5 ) * math.rad( 30 ) or 0 )
		local e = kit.raw( ctx, file, px, py, px + math.cos( a ) * 100, py + math.sin( a ) * 100 )
		local p = comp( e, "ProjectileComponent" )
		if p then ComponentSetValue2( p, "explosion_dont_damage_shooter", true ) end
		made[#made + 1] = file
	end
	return made
end }

-- Pillar: Solidification sets a column of blocks where the shot ends (behaviors/solid_on_hit.lua)
C.pillar = { twist = function( kit, e, b ) kit.add_var( e, "witch_solid_count", RA.pillar( b.solid or 1 ).blocks ) end }

C.sunburst = { twist = function( kit, e, b, spell )
	local a = RA.sunburst( b.grow or 1 )
	kit.add_var( e, "witch_sunburst_r", a.r )
	kit.add_var( e, "witch_sunburst_element", made_of( spell ) )
	kit.add_death_script( e, "sunburst_on_hit.lua" )
end }

---- hanging orbs ----

C.sentry = { twist = function( kit, e, b, spell )
	kit.add_var( e, "witch_sentry_element", made_of( spell ) )
	kit.add_var( e, "witch_sentry_every", RA.sentry( b.strong ).every )
	kit.add_script( e, "sentry.lua", 3 )
	tuned( e, "sentry" )
end }

C.mine = { twist = function( kit, e, b, spell, carrier, ctx )
	tuned( e, "mine" )
	for _, sprite in ipairs( EntityGetComponentIncludingDisabled( e, "SpriteComponent" ) or {} ) do
		ComponentSetValue2( sprite, "alpha", 0.35 )
	end
	for _, light in ipairs( EntityGetComponentIncludingDisabled( e, "LightComponent" ) or {} ) do
		ComponentSetValue2( light, "radius", math.floor( ComponentGetValue2( light, "radius" ) * 0.3 ) )
	end
	kit.add_var( e, "witch_mine_element", made_of( spell ) )
	kit.add_var( e, "witch_mine_power", ctx.power or 1 )
	kit.add_script( e, "mine.lua", 3 )
end }

-- the orb pours out its element's matter, real particles of it, while it hangs
C.fountain = { twist = function( kit, e, b, spell )
	local material = ( DICTIONARY_LOOKS[spell.element] or {} ).material
	if not material then return end
	tuned( e, "fountain" )
	EntityAddComponent2( e, "ParticleEmitterComponent", { emitted_material_name = material, create_real_particles = true,
		emit_cosmetic_particles = false, count_min = 2, count_max = 3, emission_interval_min_frames = 1, emission_interval_max_frames = 1,
		x_pos_offset_min = -2, x_pos_offset_max = 2, y_pos_offset_min = 0, y_pos_offset_max = 3, x_vel_min = -25, x_vel_max = 25,
		y_vel_min = 10, y_vel_max = 50, lifetime_min = 4, lifetime_max = 8, is_emitting = true } )
end }

C.tether = { twist = function( kit, e, b, spell )
	tuned( e, "tether" )
	kit.add_var( e, "witch_tether_r", RA.tether().r )
	kit.add_var( e, "witch_tether_element", made_of( spell ) )
	kit.add_script( e, "tether.lua", 2 )
end }

C.vortex = { twist = function( kit, e, b )
	kit.add_var( e, "witch_vortex_r", RA.vortex( b.pull or 1 ).r )
	kit.add_var( e, "witch_vortex_turn", ( ( b.whirl or 0 ) + ( b.spin or 0 ) ) < 0 and -1 or 1 )
	kit.add_script( e, "vortex.lua" )
	tuned( e, "vortex" )
end }

---- fields, rain, the splash ----

-- Updraft: the wind rises round the caster - they fly without tiring while it lasts
C.updraft = { cast = function( kit, ctx )
	local a = RA.updraft( ctx.spell.behaviors.strong )
	return { effect_spawn( "resonance", "updraft", ctx.x, ctx.y, { owner = ctx.shooter, frames = a.frames, r = a.r,
		element = made_of( ctx.spell ) } ) }
end }

-- Barrage: shots of the element fall round the cursor from above, one after another
C.barrage = { cast = function( kit, ctx )
	local x, y = kit.place( ctx, "sky" )
	local a = RA.barrage( ctx.spell.behaviors.pierce or 1 )
	return { effect_spawn( "resonance", "barrage", x, y, { owner = ctx.shooter, element = made_of( ctx.spell ), shots = a.shots,
		every = a.every, power = ctx.power or 1 } ) }
end }

-- Fissure: a crack runs along the ground the way the caster aims
C.fissure = { cast = function( kit, ctx )
	local dir = ctx.aim_x >= 0 and 1 or -1
	local gx, gy = ground_below( ctx.x + dir * 8, ctx.y - 6, 40 )
	if not gy then return nil end -- nothing underfoot: a splash as ever
	return { effect_spawn( "resonance", "fissure", gx, gy, { owner = ctx.shooter, dx = dir, element = made_of( ctx.spell ),
		length = RA.fissure( ctx.spell.behaviors.crush or 1 ).length, frames = 90, power = ctx.power or 1 } ) }
end }

---- fields and rain: the game's own ----

local function game_field( file, at_target )
	return { cast = function( kit, ctx )
		local x, y = ctx.x, ctx.y
		if at_target then x, y = kit.place( ctx, "target" ) end
		kit.raw( ctx, DECK .. file, x, y, x, y )
		return { DECK .. file }
	end }
end
C.healing_spring = game_field( "regeneration_field.xml" )
C.frenzy = game_field( "berserk_field.xml", true )
C.charm = game_field( "charm_field.xml", true )

-- the game's meteors, falling round the cursor now and then (effects/resonance.lua meteors); they spare the caster
C.meteors = { cast = function( kit, ctx )
	local x, y = kit.place( ctx, "target" )
	return { effect_spawn( "resonance", "meteors", x, y, { owner = ctx.shooter, frames = RA.meteors( ctx.spell.behaviors.strong ).frames } ) }
end }

C.acid_rain = { cast = function( kit, ctx )
	local x, y = kit.place( ctx, "target" )
	local e = kit.raw( ctx, DECK .. "cloud_acid.xml", x, y, x, y )
	local p = comp( e, "ProjectileComponent" )
	if p then ComponentSetValue2( p, "lifetime", RA.acid( ctx.spell.behaviors.strong ).frames ) end
	return { DECK .. "cloud_acid.xml" }
end }
