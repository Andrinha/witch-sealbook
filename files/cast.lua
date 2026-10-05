-- Casting with a book of seals (books.lua; entities/spellbook.xml and the others): the spell on the book's active page
-- (serialize_spell in seal_spell.lua) becomes magic in the world. First the seal itself flares up in the air before the
-- caster, drawn in light from the page; then
--   - a spell with a way of manifesting of its own (the wiki's named seals, special sigils and frames, decorative
--     sigils) runs its manifestation (manifest.lua MANIFESTS);
--   - otherwise its form makes the element's carriers (carriers.lua) or, for unique mechanics, the game's projectiles
--     (dictionary_effect in dictionary.lua), tuned by the spell's parameters, with the signs' behaviors added
--     (BEHAVIORS).
-- Seals drawn inside the seal and linked seals are cast with it. The inks the seal is drawn with change it (ink.lua
-- INKS, ink_apply). Runs in the book's own Lua context (spellbook.lua).

dofile_once( "mods/witch_notebook/files/dictionary.lua" )
dofile_once( "mods/witch_notebook/files/books.lua" )
dofile_once( "mods/witch_notebook/files/fx.lua" )
dofile_once( "mods/witch_notebook/files/ink.lua" )
dofile_once( "mods/witch_notebook/files/strokes.lua" )
dofile_once( "mods/witch_notebook/files/effects/lib.lua" )
dofile_once( "mods/witch_notebook/files/manifest.lua" )
dofile_once( "mods/witch_notebook/files/sheets.lua" ) -- the wiki seals' tiers, for how long they recharge

local SPARK = "data/entities/projectiles/deck/light_bullet.xml" -- a fizzled seal
local SLOPPY = 0.35                -- keep in sync with SEAL_SLOPPY in seal_spell.lua
local MAX_MISFIRE_CHANCE = 50      -- percent, for a seal with zero precision
local UNSTABLE_MISFIRE_CHANCE = 30 -- percent, for a seal with zero stability
local MISFIRE_ELEMENTS = { "fire", "water", "wind", "earth", "light" }
local HAND_OFFSET = 8              -- projectiles leave this far from the caster, towards the aim
local MAX_TARGET_DISTANCE = 180    -- clouds appear at the cursor, but not farther than this
local HOVER_DISTANCE = 60          -- a sphere floating in place hangs this far towards the aim at most
local DRIFT = 220                  -- how hard a lopsided seal pushes its magic sideways (pixels per second squared)
local BEHAVIOR_SCRIPTS = "mods/witch_notebook/files/behaviors/"
local GRIMOIRE_FILE = "mods/witch_notebook/files/grimoire.lua"
PULL_VAR = "witch_pull" -- strength of the Sign of Pulling on a projectile (behaviors/pull.lua)
SPIN_VAR = "witch_spin" -- spin of turned signs on a projectile (behaviors/spin.lua)
-- a book's run globals (books.lua book_var) "active_spell": its active page's spell (notebook.lua), "active_strokes": its
-- drawing, to light it up in the air
SPELLBOOK_NEXT_CAST_VAR = "witch_notebook_next_cast" -- on the book: the frame it can cast again ('value_int') and how
                                                     -- long it waits since the last cast ('value_float', frames)
LAST_SPELL_VAR = "witch_notebook.last_cast" -- the last spell cast, for the Repetition Seal
AMPLIFY_VAR = "witch_notebook.amplify" -- casts left that the Amplification Scroll strengthens
REMOTE_VAR = "witch_notebook.remote" -- the cloak (Sasaran's Cloak) the next spells are cast from

local FIELDS_NUMBERS = { force = true, focus = true, spread = true, range = true, lifetime = true, heavy = true, tilt = true,
	push_x = true, push_y = true, stability = true, precision = true, layers = true, glaives = true, span = true }

-- one "element=ice;form=column;...;b=pull:1.2,spin:-0.8" -> table
local function parse_one( data )
	local spell = { element = "", form = "column", force = 0, focus = 0, spread = 0, range = 0, lifetime = 0,
		heavy = 0, tilt = 0, push_x = 0, push_y = 0, stability = 1, precision = 0.5, behaviors = {}, subs = {}, links = {} }
	for key, value in ( data or "" ):gmatch( "(%w+)=([^;]*)" ) do
		if key == "b" then
			for name, w in value:gmatch( "(%w+):([-%d.]+)" ) do spell.behaviors[name] = tonumber( w ) end
		elseif FIELDS_NUMBERS[key] then
			spell[key] = tonumber( value ) or 0
		elseif value == "true" then
			spell[key] = true
		else
			spell[key] = value
		end
	end
	if not dictionary_effect( spell.element, spell.form, spell.floats ) and not spell.manifest and not spell.shape then spell.element = "" end
	-- seals drawn before signs had behaviors
	if not ( data or "" ):find( "b=", 1, true ) and spell.form == "levitation" then spell.behaviors.float = 1 end
	return spell
end

-- the page's spell with the seals inside it ("&sub:...") and linked to it ("&link:...")
function parse_spell_data( data )
	data = data or ""
	local first = data:find( "&", 1, true )
	local spell = parse_one( first and data:sub( 1, first - 1 ) or data )
	if first then
		for kind, part in ( data:sub( first ) ):gmatch( "&(%a+):([^&]*)" ) do
			local list = kind == "sub" and spell.subs or spell.links
			list[#list + 1] = parse_one( part )
		end
	end
	return spell
end

-- A page keeps the spell of the wiki's seal as the grimoire had it when the page was made (seal_page_data in seal_spell.lua).
-- How the seal manifests is the grimoire's to say, as it reads now: its page's spell, or nil for a seal it doesn't have.
-- The book's own Lua context loads the grimoire when it first casts one of its seals.
local page_spells = {}
local function page_spell( key )
	if page_spells[key] == nil then
		if not GRIMOIRE_BY_KEY then dofile_once( GRIMOIRE_FILE ) end
		local entry = GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[key]
		page_spells[key] = entry and parse_one( entry.spell:match( "^[^&]*" ) ) or false
	end
	return page_spells[key] or nil
end

-- How long a seal recharges after it is cast, beyond the book's own delay (frames): the more it makes, the longer. A
-- wiki seal by its tier (sheets.lua SHEET_TIER; the forbidden are VII); one of the witch's own by what it makes; the
-- seals inside it and linked to it add half of theirs. The book in hand shows it under the cursor (notebook.lua).
SEAL_RECHARGE_BY_TIER = { 0, 20, 45, 80, 130, 200, 300 }
local RECHARGE_BY_CARRIER = { bolt = 0, orb = 0, hover = 10, nova = 30, cloud = 60, ring = 60, field = 90 }
local RECHARGE_SCULPTURE = 130 -- a creature of the element, drawn freely
local RECHARGE_MANIFEST = 45   -- a special sigil's own way, drawn freely
local RECHARGE_GAME = 45       -- the game's own projectiles: black holes, lasers, lightning
local RECHARGE_COPY = 6        -- each shot beyond the first that Piercing adds
local UNLISTED_TIER = 4
function seal_recharge( spell )
	local frames = 0
	if spell.named then
		local page = page_spell( spell.named )
		local tier = page and page.forbidden and #SEAL_RECHARGE_BY_TIER or ( SHEET_TIER or {} )[spell.named] or UNLISTED_TIER
		frames = SEAL_RECHARGE_BY_TIER[tier]
	elseif spell.shape then
		frames = RECHARGE_SCULPTURE
	elseif spell.manifest then
		frames = RECHARGE_MANIFEST
	elseif spell.element ~= "" and spell.element ~= "shockwave" then
		local effect = dictionary_effect( spell.element, spell.form, spell.floats )
		if effect then
			local own = ( effect.file or "" ):find( "/carriers/", 1, true ) or effect.carrier == "nova" or effect.carrier == "ring"
			frames = own and ( RECHARGE_BY_CARRIER[effect.carrier] or 0 ) or RECHARGE_GAME
			frames = frames + RECHARGE_COPY * math.max( 0, math.floor( ( spell.behaviors or {} ).pierce or 0 ) - 1 )
		end
	end
	for _, list in ipairs( { spell.subs or {}, spell.links or {} } ) do
		for _, sub in ipairs( list ) do frames = frames + 0.5 * seal_recharge( sub ) end
	end
	return math.floor( frames )
end

-- The book's wait after a cast of 'spell' (frames): its own delay and the seal's recharge, the swift ink shortens both
function seal_cast_delay( book, spell )
	return math.floor( ( book.cast_delay + seal_recharge( spell ) ) * ( 1 - ink_haste( spell ) ) )
end

function misfire_chance( spell )
	local chance = 0
	if spell.precision < SLOPPY then chance = chance + ( SLOPPY - spell.precision ) / SLOPPY * MAX_MISFIRE_CHANCE end
	return chance + ( 1 - spell.stability ) * UNSTABLE_MISFIRE_CHANCE
end

local function scale_value( comp, field, k )
	if comp then ComponentSetValue2( comp, field, ComponentGetValue2( comp, field ) * k ) end
end

-- How big the effect is: blast, damage area and sprite
local function scale_size( projectile, k )
	local proj = EntityGetFirstComponentIncludingDisabled( projectile, "ProjectileComponent" )
	if proj then
		local radius = ComponentObjectGetValue2( proj, "config_explosion", "explosion_radius" ) or 0
		ComponentObjectSetValue2( proj, "config_explosion", "explosion_radius", radius * k )
	end
	local area = EntityGetFirstComponentIncludingDisabled( projectile, "AreaDamageComponent" )
	if area then
		local r = ComponentGetValue2( area, "circle_radius" ) * k
		ComponentSetValue2( area, "circle_radius", r )
		ComponentSetValue2( area, "aabb_min", -r, -r )
		ComponentSetValue2( area, "aabb_max", r, r )
	end
	for _, sprite in ipairs( EntityGetComponentIncludingDisabled( projectile, "SpriteComponent" ) or {} ) do
		ComponentSetValue2( sprite, "has_special_scale", true )
		ComponentSetValue2( sprite, "special_scale_x", k )
		ComponentSetValue2( sprite, "special_scale_y", k )
	end
end

local function add_script( projectile, file, every )
	EntityAddComponent2( projectile, "LuaComponent", { script_source_file = BEHAVIOR_SCRIPTS .. file, execute_every_n_frame = every or 1 } )
end

local function add_var( projectile, name, value )
	if type( value ) == "number" then
		EntityAddComponent2( projectile, "VariableStorageComponent", { name = name, value_float = value } )
	else
		EntityAddComponent2( projectile, "VariableStorageComponent", { name = name, value_string = tostring( value ) } )
	end
end

-- a script that runs when the projectile ends (hits something or runs out)
local function add_death_script( projectile, file )
	EntityAddComponent2( projectile, "LuaComponent", { script_source_file = BEHAVIOR_SCRIPTS .. file, execute_on_removed = true,
		execute_every_n_frame = -1 } )
end

local function convert( projectile, from, to, radius, loop )
	EntityAddComponent2( projectile, "MagicConvertMaterialComponent", {
		from_material_array = from, to_material_array = to, radius = math.floor( radius ), is_circle = true,
		loop = loop ~= false, kill_when_finished = false, steps_per_frame = 4,
	} )
end

-- How much a sign does, by its weight 'w' (the signs' summed size, 1 = one ordinary sign): BEHAVIORS below and the wave
-- (manifest.lua) do it, spell_notes.lua tells it
SIGN_AMOUNTS = {
	homing = function( w ) return { turn = 60 + 70 * w, reach = 100 + 50 * w } end,
	sense = function( w ) return { turn = 40 + 40 * w, reach = 220 + 80 * w } end,
	pull = function( w ) return { reach = 40 + 25 * w } end, -- behaviors/pull.lua: RADIUS + RADIUS_PER_SIGN * strength
	gust = function( w ) return { knock = 60 * w, push = 0.5 * w } end,
	crush = function( w ) return { r = 5 + 3 * w } end,
	build = function( w ) return { r = 6 + 4 * w } end,
	soften = function( w ) return { r = 5 + 3 * w } end,
	purify = function( w ) return { r = 12 + 8 * w } end,
	refuse = function( w ) return { r = 10 + 6 * w } end,
	cool = function( w ) return { r = 6 + 4 * w } end,
	grow = function( w ) return { size = 1 + 0.5 * w, damage = 1 + 0.3 * w, slow = 1 + 0.25 * w } end, -- speed / slow
	shrink = function( w ) return { size = 1 / ( 1 + 0.5 * w ), damage = 1 / ( 1 + 0.2 * w ), speed = 1 + 0.3 * w } end,
	strong = function( w ) return { damage = 1 + 0.3 * w, lifetime = 1 + 0.25 * w } end,
	point = function( w ) return { damage = 1 + 0.2 * w, speed = 1 + 0.25 * w } end,
	still = function( w ) return { friction = 2 + 2 * w, frames = math.floor( 120 * w ) } end,
	hold = function( w ) return { frames = 60 + 60 * w } end,
	bind = function( w ) return { frames = 90 + 60 * w } end,
	link = function( w ) return { jumps = math.floor( 1 + 2 * w ) } end,
	gather = function( w ) return { cells = math.floor( 150 + 250 * w ) } end,
	contain = function( w ) return { cells = math.floor( 300 + 300 * w ) } end,
	launch = function( w ) return { speed = 1.8 + 0.4 * w } end,
	reflect = function( w ) return { r = 14 + 6 * w } end, -- on a sphere; a field and a wave reflect within their own
}
local A = SIGN_AMOUNTS

-- What the signs add to a projectile: behavior key -> function( projectile, weight, spell, carrier, ctx ). Weight: the
-- signs' summed size (1 = one ordinary sign), pierce: their number, spin: -1..1 (the way it turns).
-- 'thrust' and 'float' shape the flight in spawn(); 'pierce' also makes copies in cast_form().
-- hard rock and temple bricks withstand it; earth of every kind is ground into sand like stone
local CRUSHED = { from = "rock_static,rock_static_intro,rock_static_noedge,rock_static_glow,sand_static,sandstone,snowrock_static,snow_static"
		.. ",soil,soil_lush,soil_dead,soil_dark,soil_lush_dark,fungisoil",
	to = "sand,sand,sand,sand,sand,sand,sand,snow,sand,sand,sand,sand,sand,sand" }
local REFORMED = { from = "sand,soil,snow,snow_sticky", to = "sand_static,sand_static,snow_static,snow_static" }
local SOFTENED = { from = "rock_static,rock_static_noedge,sandstone,snowrock_static,ice_static,glass_static",
	to = "soil,soil,sand,snow,snow,glass_broken" }
local PURIFIED = { from = FOULS.from .. ",blood", to = FOULS.to .. ",water" } -- what is foul (effects/lib.lua), and blood
local FROZEN = { from = "water,water_salt,water_swamp,blood,slime,fire,lava",
	to = "ice_static,ice_static,ice_static,ice_blood_static,ice_slime_static,air,rock_static" }
local REFUSE = { from = "blood,pus,slime,poo,vomit,rotten_meat", to = "air,air,air,air,air,air" }
-- what each sign turns into what (spell_notes.lua names them; the wave does them too: wave_converts)
SIGN_CONVERTS = { crush = CRUSHED, build = REFORMED, soften = SOFTENED, purify = PURIFIED, cool = FROZEN, refuse = REFUSE }
local BEHAVIORS = {
	pierce = function( projectile )
		local proj = EntityGetFirstComponentIncludingDisabled( projectile, "ProjectileComponent" )
		if proj then ComponentSetValue2( proj, "penetrate_entities", true ) end
	end,
	homing = function( projectile, w, spell, carrier, ctx )
		-- a cloud drifts after the enemies under it (the shots of a rain from the sky home in as shots do)
		if carrier == "cloud" and ctx.at ~= "sky" then
			add_var( projectile, "witch_follow", w )
			add_script( projectile, "follow.lua", 2 )
			return
		end
		if carrier ~= "bolt" and carrier ~= "orb" and carrier ~= "cloud" then return end -- elsewhere it chooses where the magic appears (cast_form)
		local a = A.homing( w )
		EntityAddComponent2( projectile, "HomingComponent", {
			homing_targeting_coeff = a.turn, homing_velocity_multiplier = 0.86, detect_distance = a.reach,
		} )
	end,
	-- Sights Set: the spell goes exactly where the caster looks and bursts there
	aim = function( projectile, w, spell, carrier, ctx )
		if carrier ~= "bolt" and carrier ~= "orb" then return end
		add_var( projectile, "witch_aim_x", ctx.tx )
		add_var( projectile, "witch_aim_y", ctx.ty )
		add_script( projectile, "aim.lua" )
	end,
	-- Detection: it seeks the enemies it senses, far away too
	sense = function( projectile, w, spell, carrier )
		if carrier ~= "bolt" and carrier ~= "orb" then return end
		local a = A.sense( w )
		EntityAddComponent2( projectile, "HomingComponent", {
			homing_targeting_coeff = a.turn, homing_velocity_multiplier = 0.92, detect_distance = a.reach,
		} )
	end,
	-- Mimicry: it follows the cursor while it flies
	mimic = function( projectile, w, spell, carrier )
		add_var( projectile, "witch_mimic", w )
		add_script( projectile, "mimic.lua" )
	end,
	pull = function( projectile, w )
		add_var( projectile, PULL_VAR, w )
		add_script( projectile, "pull.lua" )
	end,
	push = function( projectile, w )
		add_var( projectile, PULL_VAR, -w )
		add_script( projectile, "pull.lua" )
	end,
	-- Aeriforms Defined: a gust that throws what it hits
	gust = function( projectile, w )
		local proj = EntityGetFirstComponentIncludingDisabled( projectile, "ProjectileComponent" )
		local a = A.gust( w )
		if proj then ComponentSetValue2( proj, "knockback_force", ComponentGetValue2( proj, "knockback_force" ) + a.knock ) end
		add_var( projectile, PULL_VAR, -a.push )
		add_script( projectile, "pull.lua" )
	end,
	-- Wall Breaker: bores through rock and earth, crushing them into sand
	crush = function( projectile, w )
		local proj = EntityGetFirstComponentIncludingDisabled( projectile, "ProjectileComponent" )
		if proj then
			ComponentSetValue2( proj, "penetrate_world", true )
			ComponentSetValue2( proj, "penetrate_world_velocity_coeff", 0.5 )
		end
		convert( projectile, CRUSHED.from, CRUSHED.to, A.crush( w ).r )
	end,
	-- Integration: loose sand and snow around it set solid (with earth's own sand: a path of stone)
	build = function( projectile, w )
		convert( projectile, REFORMED.from, REFORMED.to, A.build( w ).r )
	end,
	-- Coil: hard rock around it softens into soil and sand
	soften = function( projectile, w )
		convert( projectile, SOFTENED.from, SOFTENED.to, A.soften( w ).r )
	end,
	grow = function( projectile, w )
		local a = A.grow( w )
		scale_size( projectile, a.size )
		scale_value( EntityGetFirstComponentIncludingDisabled( projectile, "ProjectileComponent" ), "damage", a.damage )
		local velocity = EntityGetFirstComponentIncludingDisabled( projectile, "VelocityComponent" )
		if velocity then
			local vx, vy = ComponentGetValue2( velocity, "mVelocity" )
			ComponentSetValue2( velocity, "mVelocity", vx / a.slow, vy / a.slow )
		end
	end,
	shrink = function( projectile, w )
		local a = A.shrink( w )
		scale_size( projectile, a.size )
		scale_value( EntityGetFirstComponentIncludingDisabled( projectile, "ProjectileComponent" ), "damage", a.damage )
		local velocity = EntityGetFirstComponentIncludingDisabled( projectile, "VelocityComponent" )
		if velocity then
			local vx, vy = ComponentGetValue2( velocity, "mVelocity" )
			ComponentSetValue2( velocity, "mVelocity", vx * a.speed, vy * a.speed )
		end
	end,
	-- Strengthening: harder and longer
	strong = function( projectile, w )
		local a = A.strong( w )
		local proj = EntityGetFirstComponentIncludingDisabled( projectile, "ProjectileComponent" )
		if proj then
			ComponentSetValue2( proj, "damage", ComponentGetValue2( proj, "damage" ) * a.damage )
			local lifetime = ComponentGetValue2( proj, "lifetime" )
			if lifetime > 0 then ComponentSetValue2( proj, "lifetime", math.floor( lifetime * a.lifetime ) ) end
		else
			-- a field
			scale_value( EntityGetFirstComponentIncludingDisabled( projectile, "AreaDamageComponent" ), "damage_per_frame", a.damage )
			local life = EntityGetFirstComponentIncludingDisabled( projectile, "LifetimeComponent" )
			if life then ComponentSetValue2( life, "lifetime", math.floor( ComponentGetValue2( life, "lifetime" ) * a.lifetime ) ) end
		end
	end,
	-- Pointing: a sharp tip - faster, narrower, through one more enemy
	point = function( projectile, w )
		local a = A.point( w )
		local proj = EntityGetFirstComponentIncludingDisabled( projectile, "ProjectileComponent" )
		if proj then
			ComponentSetValue2( proj, "damage", ComponentGetValue2( proj, "damage" ) * a.damage )
			ComponentSetValue2( proj, "penetrate_entities", true )
		end
		local velocity = EntityGetFirstComponentIncludingDisabled( projectile, "VelocityComponent" )
		if velocity then
			local vx, vy = ComponentGetValue2( velocity, "mVelocity" )
			ComponentSetValue2( velocity, "mVelocity", vx * a.speed, vy * a.speed )
		end
	end,
	-- turned signs: the spell circles around its path as it flies, curling in loops (behaviors/spin.lua)
	spin = function( projectile, spin )
		add_var( projectile, SPIN_VAR, spin )
		add_script( projectile, "spin.lua" )
	end,
	-- the Sign of Spiraling Wind: the same curling flight (its curl is the way it turns)
	whirl = function( projectile, w, spell, carrier )
		if carrier ~= "bolt" and carrier ~= "orb" then return end
		add_var( projectile, SPIN_VAR, math.max( -1, math.min( 1, w ) ) )
		add_script( projectile, "spin.lua" )
	end,
	-- Stability and Level Planes: it slows down and hangs in the air where it stopped, a trap
	still = function( projectile, w )
		local a = A.still( w )
		local velocity = EntityGetFirstComponentIncludingDisabled( projectile, "VelocityComponent" )
		if velocity then
			ComponentSetValue2( velocity, "air_friction", a.friction )
			ComponentSetValue2( velocity, "gravity_y", 0 )
		end
		local proj = EntityGetFirstComponentIncludingDisabled( projectile, "ProjectileComponent" )
		if proj then
			ComponentSetValue2( proj, "die_on_low_velocity", false )
			local lifetime = ComponentGetValue2( proj, "lifetime" )
			if lifetime > 0 then ComponentSetValue2( proj, "lifetime", lifetime + a.frames ) end
		end
	end,
	-- Binding, Immobility: it holds whatever it hits in place
	hold = function( projectile, w, spell )
		add_var( projectile, "witch_hold", A.hold( w ).frames )
		add_var( projectile, "witch_hold_element", spell.element )
		add_death_script( projectile, "hold_on_hit.lua" )
	end,
	-- Entwining: a ribbon wraps whatever it hits and holds it
	bind = function( projectile, w )
		add_var( projectile, "witch_bind", A.bind( w ).frames )
		add_death_script( projectile, "bind_on_hit.lua" )
	end,
	-- Envelopment: where it hits, its element wraps around in a ring
	envelop = function( projectile, w, spell )
		add_var( projectile, "witch_envelop", spell.element )
		add_var( projectile, "witch_envelop_w", w )
		add_death_script( projectile, "envelop_on_hit.lua" )
	end,
	-- Link: from the one it hits it jumps on to the next enemy
	link = function( projectile, w, spell )
		add_var( projectile, "witch_link", A.link( w ).jumps )
		add_var( projectile, "witch_link_element", spell.element )
		add_death_script( projectile, "link_on_hit.lua" )
	end,
	-- Solidification: where it ends, its element sets solid - a foothold
	solid = function( projectile, w, spell )
		add_var( projectile, "witch_solid", spell.element )
		add_death_script( projectile, "solid_on_hit.lua" )
	end,
	-- Gathering, Collection: it draws in the liquid around it as it flies and pours it out where it ends
	gather = function( projectile, w, spell, carrier )
		EntityAddComponent2( projectile, "MaterialInventoryComponent", { drop_as_item = false, on_death_spill = true,
			leak_on_damage_percent = 0 } )
		EntityAddComponent2( projectile, "MaterialSuckerComponent", { material_type = 0, barrel_size = A.gather( w ).cells,
			num_cells_sucked_per_frame = 3 } )
	end,
	scatter = function( projectile, w )
		local proj = EntityGetFirstComponentIncludingDisabled( projectile, "ProjectileComponent" )
		if proj then ComponentSetValue2( proj, "on_death_emit_particle_count", ( ComponentGetValue2( proj, "on_death_emit_particle_count" ) or 0 ) * 3 ) end
	end,
	-- the Sign of Orb: a container for the liquid it gathers (the Water Orb)
	contain = function( projectile, w, spell, carrier )
		EntityAddComponent2( projectile, "MaterialInventoryComponent", { drop_as_item = false, on_death_spill = true,
			leak_on_damage_percent = 0 } )
		EntityAddComponent2( projectile, "MaterialSuckerComponent", { material_type = 0, barrel_size = A.contain( w ).cells,
			num_cells_sucked_per_frame = 4 } )
		add_script( projectile, "contain.lua", 2 )
	end,
	purify = function( projectile, w )
		local r = A.purify( w ).r
		convert( projectile, PURIFIED.from, PURIFIED.to, r )
		EntityAddComponent2( projectile, "MagicConvertMaterialComponent", { radius = math.floor( r ), is_circle = true,
			clean_stains = true, loop = true, kill_when_finished = false, steps_per_frame = 4 } )
	end,
	refuse = function( projectile, w )
		convert( projectile, REFUSE.from, REFUSE.to, A.refuse( w ).r )
	end,
	cool = function( projectile, w )
		convert( projectile, FROZEN.from, FROZEN.to, A.cool( w ).r )
		local proj = EntityGetFirstComponentIncludingDisabled( projectile, "ProjectileComponent" )
		if proj then
			local effects = ComponentGetValue2( proj, "damage_game_effect_entities" ) or ""
			ComponentSetValue2( proj, "damage_game_effect_entities", effects .. "data/entities/misc/effect_frozen_short.xml," )
		end
	end,
	-- Reflection: a field or a sphere hanging in place turns enemies' projectiles back at them
	reflect = function( projectile, w, spell, carrier, ctx )
		local area = EntityGetFirstComponentIncludingDisabled( projectile, "AreaDamageComponent" )
		add_var( projectile, "witch_owner", ctx.shooter )
		add_var( projectile, "witch_reflect_r", area and ComponentGetValue2( area, "circle_radius" ) or A.reflect( w ).r )
		add_script( projectile, "reflect.lua" )
	end,
	-- Partition, Regions pointing inwards: the field's edge keeps creatures on their side of it
	bound = function( projectile, w, spell, carrier, ctx )
		local area = EntityGetFirstComponentIncludingDisabled( projectile, "AreaDamageComponent" )
		add_var( projectile, "witch_owner", ctx.shooter )
		add_var( projectile, "witch_bound_r", area and ComponentGetValue2( area, "circle_radius" ) or 32 )
		add_script( projectile, "bound.lua", 2 )
	end,
	-- Launch: a powerful but short burst
	launch = function( projectile, w )
		local velocity = EntityGetFirstComponentIncludingDisabled( projectile, "VelocityComponent" )
		if velocity then
			local vx, vy = ComponentGetValue2( velocity, "mVelocity" )
			local speed = A.launch( w ).speed
			ComponentSetValue2( velocity, "mVelocity", vx * speed, vy * speed )
			ComponentSetValue2( velocity, "air_friction", ComponentGetValue2( velocity, "air_friction" ) + 1.5 )
		end
	end,
}

---- the inks (ink.lua INKS): a seal drawn with a dyed ink takes on its dye, each ink by its share of the line ----

local WET_RUNS = 0.45       -- precision an ordinary ink loses when the caster is wet: the ink runs
local WILD_SIGNS = { "grow", "spin", "pierce", "scatter" } -- what blood may add on its own

-- the caster is wet or in a liquid
local function caster_wet( shooter )
	if GameGetGameEffectCount and GameGetGameEffectCount( shooter, "WET" ) > 0 then return true end
	local model = EntityGetFirstComponent( shooter, "DamageModelComponent" )
	return model ~= nil and ( ComponentGetValue2( model, "mLiquidCount" ) or 0 ) > 3
end

-- The inks change the spell before it is cast: stronger, longer, farther; ctx learns how it looks (hidden, glowing)
-- and what it risks (the ink boiling over). 'nested': a seal inside the seal - the risks are the main seal's.
local function ink_apply( ctx, nested )
	local spell = ctx.spell
	local shares = ink_mix( spell.ink )
	ctx.ink = shares
	for key, share in pairs( shares ) do
		local ink = INK_BY_KEY[key]
		if ink.force then
			-- blood: much stronger and bigger, by how much - it can't be told
			local surge = 1 + ( ink.wild or 0 ) * Random( -100, 100 ) / 100
			spell.force = spell.force + ink.force * share * surge
			ctx.power = ctx.power * ( 1 + ( ink.power or 0 ) * share * surge )
			spell.layers = ( spell.layers or 0 ) + share
			if Random( 1, 100 ) <= 30 * share then
				local sign = WILD_SIGNS[Random( 1, #WILD_SIGNS )]
				spell.behaviors = spell.behaviors or {}
				spell.behaviors[sign] = ( spell.behaviors[sign] or 0 ) + ( sign == "spin" and ( Random( 0, 1 ) * 2 - 1 ) * 0.8 or 1 )
			end
			if not nested and Random( 1, 1000 ) <= 10 * ( ink.backlash or 0 ) * share then ctx.backlash = true end
		end
		if ink.lifetime then spell.lifetime = spell.lifetime + ink.lifetime * share end
		if ink.range then spell.range = spell.range + ink.range * share end
		if ink.hidden and share >= 0.5 then ctx.hidden = true end
		if ink.glow then ctx.glow = math.max( ctx.glow or 0, share ) end
		if ink.waterproof then ctx.waterproof = ( ctx.waterproof or 0 ) + share end
	end
	-- a wet caster's ink runs, all but the oily
	local runs = 1 - math.min( 1, ctx.waterproof or 0 )
	if not nested and runs > 0.05 and caster_wet( ctx.shooter ) then
		local before = spell.precision
		spell.precision = spell.precision * ( 1 - WET_RUNS * runs )
		ctx.power = ctx.power * ( 0.5 + spell.precision ) / ( 0.5 + before )
		spell.force = spell.force - 0.5 * runs
		GamePrint( "The ink ran in the water - the seal is weaker" )
	end
end

-- The share of the delay between casts the inks save
function ink_haste( spell )
	local haste = 0
	for key, share in pairs( ink_mix( spell.ink ) ) do haste = haste + ( INK_BY_KEY[key].haste or 0 ) * share end
	return math.min( 0.6, haste )
end

-- the color of the seal's dyed ink (the largest share), for the flash and the glow, or nil
local function ink_color( ctx, white )
	local best, share = nil, 0
	for key, s in pairs( ctx.ink or {} ) do
		if s > share then best, share = INK_BY_KEY[key], s end
	end
	if not best then return nil end
	local c = best.liquid
	white = white or 0
	return color_abgr_merge( math.floor( c[1] + ( 255 - c[1] ) * white ), math.floor( c[2] + ( 255 - c[2] ) * white ),
		math.floor( c[3] + ( 255 - c[3] ) * white ), 255 ), c
end

-- What the inks do to a projectile's look: gold makes it shine, the clear ink hides it
function ink_look( projectile, ctx )
	if ( ctx.glow or 0 ) > 0 then
		EntityAddComponent2( projectile, "LightComponent", { radius = math.floor( 70 + 110 * ctx.glow ), r = 255, g = 205, b = 110,
			fade_out_time = 0.5 } )
	end
	if ctx.hidden then
		for _, sprite in ipairs( EntityGetComponentIncludingDisabled( projectile, "SpriteComponent" ) or {} ) do
			ComponentSetValue2( sprite, "alpha", 0.2 )
		end
		for _, light in ipairs( EntityGetComponentIncludingDisabled( projectile, "LightComponent" ) or {} ) do
			ComponentSetValue2( light, "radius", 8 )
		end
	end
end

-- Blood boiled over in the ink: the seal bursts at the caster
local function backlash( ctx )
	GamePrint( "The blood in the ink boiled!" )
	fx_material( "blood", ctx.x, ctx.y - 4, 30, 6, 0, -40 )
	fx_burst( ctx.x, ctx.y - 4, color_abgr_merge( 200, 20, 40, 255 ), 24, 90, 0.5 )
	seal_damage( ctx.shooter, 0.2, "DAMAGE_EXPLOSION", 0, ctx.x, ctx.y )
end

-- What a seal's parameters make of its carrier's own numbers ('power': a clean seal hits harder, ctx.power) - spawn
-- tunes the projectile by them, spell_notes.lua tells them: damage and the blast's radius added, frames added to a
-- projectile's life (range: farther; levitation: longer; a sphere floating in place lingers), its speed (a share: range
-- faster, levitation slow, a sphere floating in place stops where it was cast), a field's damage (a share) and frames
-- added to its life; 'float': levitation against columns, how much it floats rather than flies (1: a slow floating orb)
function spell_tuning( spell, power )
	local b = spell.behaviors or {}
	local float = ( b.float or 0 ) > 0 and b.float / ( b.float + ( b.thrust or 0 ) ) or 0
	if spell.floats then float = 1 end
	local lifetime = math.floor( 60 * spell.lifetime + 20 * spell.range + 60 * float )
	if spell.floats then lifetime = lifetime + 300 end
	local speed = math.max( 0.2, math.min( 1 + spell.range, 5 ) ) * ( 1 - 0.7 * float )
	if spell.floats then speed = 0 end
	return { float = float, damage = 0.4 * spell.force * power, blast = 10 * spell.force * power, lifetime = lifetime,
		speed = speed, field_damage = math.max( 0.3, 1 + 0.5 * spell.force ) * ( 0.5 + 0.5 * power ) / 1.2,
		field_lifetime = math.floor( 60 * spell.lifetime ) }
end

-- The projectile an effect spawns, tuned by the spell
local function spawn( ctx, file, x, y, dir_x, dir_y, spell, effect )
	local projectile = EntityLoad( file, x, y )
	GameShootProjectile( ctx.shooter, x, y, x + dir_x * 100, y + dir_y * 100, projectile, true )
	local b = spell.behaviors or {}
	local tuned = spell_tuning( spell, ctx.power )
	local float = tuned.float

	-- a splash's drops stay by the seal: they take only a share of its reach and of a shot's damage
	if effect.splash then
		local base = DICTIONARY_CARRIER_BASE
		tuned.lifetime = math.floor( tuned.lifetime * base.splash_reach )
		tuned.damage, tuned.blast = tuned.damage * base.splash_damage, tuned.blast * base.splash_damage
	end
	local comp = EntityGetFirstComponentIncludingDisabled( projectile, "ProjectileComponent" )
	if comp then
		ComponentSetValue2( comp, "damage", ComponentGetValue2( comp, "damage" ) + tuned.damage )
		local radius = ComponentObjectGetValue2( comp, "config_explosion", "explosion_radius" ) or 0
		if radius > 0 then
			ComponentObjectSetValue2( comp, "config_explosion", "explosion_radius", radius + tuned.blast )
		end
		local lifetime = ComponentGetValue2( comp, "lifetime" )
		if lifetime > 0 then ComponentSetValue2( comp, "lifetime", math.max( 1, lifetime + tuned.lifetime ) ) end
		if effect.knockback then ComponentSetValue2( comp, "knockback_force", ComponentGetValue2( comp, "knockback_force" ) + effect.knockback ) end
	else
		-- a field: no projectile, its damage is the area's and it lasts its own time
		local area = EntityGetFirstComponentIncludingDisabled( projectile, "AreaDamageComponent" )
		scale_value( area, "damage_per_frame", tuned.field_damage )
		local life = EntityGetFirstComponentIncludingDisabled( projectile, "LifetimeComponent" )
		if area and life then
			ComponentSetValue2( life, "lifetime", math.max( 30, ComponentGetValue2( life, "lifetime" ) + tuned.field_lifetime ) )
		end
	end

	local velocity = EntityGetFirstComponentIncludingDisabled( projectile, "VelocityComponent" )
	if velocity then
		local vx, vy = ComponentGetValue2( velocity, "mVelocity" )
		ComponentSetValue2( velocity, "mVelocity", vx * tuned.speed, vy * tuned.speed )
		-- a lopsided seal pushes its magic the way its signs point (the Sign Length Demo); one aimed on purpose flies
		-- straight; inverted levitation weighs it down, levitation lifts it
		local drift = spell.directed and 0 or DRIFT * spell.tilt
		local gx = drift * ( spell.push_x or 0 )
		local gy = drift * ( spell.push_y or 0 ) + 600 * spell.heavy - 300 * float
		if spell.floats then gy = -ComponentGetValue2( velocity, "gravity_y" ) end
		ComponentSetValue2( velocity, "gravity_y", ComponentGetValue2( velocity, "gravity_y" ) + gy )
		ComponentSetValue2( velocity, "gravity_x", ComponentGetValue2( velocity, "gravity_x" ) + gx )
		if spell.floats then
			ComponentSetValue2( velocity, "air_friction", 4 )
			add_script( projectile, "hover.lua" )
		end
	end

	local carrier = effect.carrier or "bolt"
	for _, behavior in ipairs( DICTIONARY_BEHAVIORS ) do
		local w, apply = b[behavior.key], BEHAVIORS[behavior.key]
		if w and apply and dictionary_behavior_works( behavior.key, carrier ) then apply( projectile, w, spell, carrier, ctx ) end
	end
	ink_look( projectile, ctx )
	return projectile
end

-- The seal flares up in the air in front of the caster, drawn in light from the book's page (in the color of its dyed
-- ink; golden ink glows on; the clear ink shows nothing)
local function seal_flash( ctx )
	if ctx.hidden then return end
	local strokes = ctx.strokes
	local color = ink_color( ctx, 0.3 ) or fx_color( ctx.spell.element ~= "" and ctx.spell.element or "light", 0.35 )
	local x, y = ctx.x + ctx.aim_x * 14, ctx.y + ctx.aim_y * 14
	local life = ( ctx.glow or 0 ) > 0 and 0.35 + 1.2 * ctx.glow or 0.35
	if strokes and #strokes > 0 then
		fx_seal( strokes, x, y, 11, color, math.atan2( ctx.aim_y, ctx.aim_x ) + math.pi / 2, life, 0.5 )
	else
		fx_ring( x, y, 11, color, 28, 0, life )
	end
	if ( ctx.glow or 0 ) > 0 then
		-- a golden seal lights up the cave around the caster for a while
		local e = fx_flash( x, y, "light", math.floor( 120 + 160 * ctx.glow ), math.floor( 120 + 240 * ctx.glow ) )
		local light = EntityGetFirstComponent( e, "LightComponent" )
		if light then
			ComponentSetValue2( light, "r", 255 ); ComponentSetValue2( light, "g", 205 ); ComponentSetValue2( light, "b", 110 )
		end
	else
		fx_flash( x, y, ctx.spell.element, 60, 8 )
	end
end

-- What the wave's signs do to the ground and liquids it runs over: the game's conversion spreading out with it
local WAVE_GROUND = { crush = true, build = true, soften = true } -- rock and sand: a smaller circle than the liquids'
function wave_converts( wave, b )
	if not wave then return end
	local p = effect_params( wave )
	local r, grow = p.r or 55, p.grow or 22
	for _, key in ipairs( { "crush", "build", "soften", "purify", "cool", "refuse" } ) do
		local w = b[key]
		if w then
			local radius = math.floor( WAVE_GROUND[key] and math.min( r, 20 + 10 * w ) or r )
			EntityAddComponent2( wave, "MagicConvertMaterialComponent", {
				from_material_array = SIGN_CONVERTS[key].from, to_material_array = SIGN_CONVERTS[key].to, radius = radius,
				is_circle = true, loop = false, kill_when_finished = false, steps_per_frame = math.max( 1, math.ceil( radius / grow ) ),
				clean_stains = key == "purify",
			} )
		end
	end
end

-- Where a spell that appears somewhere appears: at the caster, at the cursor (not farther than it can reach), in
-- the sky over the cursor
local function place( ctx, at )
	if at == "self" then return ctx.x, ctx.y end
	local dx, dy = ctx.tx - ctx.x, ctx.ty - ctx.y
	local d = math.sqrt( dx * dx + dy * dy )
	if d > MAX_TARGET_DISTANCE then dx, dy = dx / d * MAX_TARGET_DISTANCE, dy / d * MAX_TARGET_DISTANCE end
	local px, py = ctx.x + dx, ctx.y + dy
	if at == "sky" then
		local hit, hx, hy = Raytrace( px, py, px, py - 90 )
		py = hit and hy + 6 or py - 90
	end
	return px, py
end

-- A spell of an element in a form: its carriers from the hand, around the caster or at the cursor
local function cast_form( ctx )
	local spell = ctx.spell
	local effect = dictionary_effect( spell.element, spell.form, spell.floats )
	if not effect then
		spawn( ctx, SPARK, ctx.x + ctx.aim_x * HAND_OFFSET, ctx.y + ctx.aim_y * HAND_OFFSET, ctx.aim_x, ctx.aim_y, spell, {} )
		return { SPARK }
	end
	local b = spell.behaviors or {}
	-- where it appears; a field aimed with a crosshair, Sights Set or Projection appears at the target
	local px, py = ctx.x + ctx.aim_x * HAND_OFFSET, ctx.y + ctx.aim_y * HAND_OFFSET
	local at = effect.at
	if ( effect.carrier == "field" or effect.carrier == "nova" ) and ( b.homing or b.aim or b.project ) then at = "target" end
	-- Detection: a field, a wave or a cloud appears at the enemy nearest the caster, if one is in reach (a cloud over it)
	if b.sense and ( effect.carrier == "field" or effect.carrier == "nova" or effect.carrier == "cloud" ) then
		local enemy = nearest_creature( ctx.x, ctx.y, MAX_TARGET_DISTANCE, ctx.shooter )
		if enemy then
			local ex, ey = EntityGetTransform( enemy )
			ctx.tx, ctx.ty = ex, ey - ( effect.carrier == "cloud" and 36 or 4 )
			if at ~= "sky" then at = "target" end
		end
	end
	ctx.at = at
	if effect.carrier == "hover" then
		-- a sphere floating in place hangs in front of the caster, towards the cursor
		local dx, dy = ctx.tx - ctx.x, ctx.ty - ctx.y
		local d = math.sqrt( dx * dx + dy * dy )
		local k = math.min( d, HOVER_DISTANCE ) / math.max( d, 1 )
		px, py = ctx.x + dx * k, ctx.y + dy * k
		at = nil
	end
	if at then px, py = place( ctx, at ) end

	if effect.carrier == "nova" then
		if spell.element == "shockwave" then return MANIFESTS.shockwave( ctx ) end
		local made = MANIFESTS.nova( ctx, px, py )
		wave_converts( made[1], b )
		return made
	elseif effect.carrier == "ring" then
		return MANIFESTS.orbit_ring( ctx, px, py )
	end

	-- direction: the aim, spread by the seal's parameters, copies fanned out
	local base = math.atan2( ctx.aim_y, ctx.aim_x )
	if at == "sky" then base = math.pi / 2 end
	local spread = math.rad( math.max( 0, 2 + 20 * ( spell.spread - spell.focus ) + 15 * ( spell.directed and 0 or spell.tilt ) ) )
	-- piercing signs: as many projectiles as signs
	local pierce = b.pierce or 0
	local copies = math.max( effect.copies or 1, pierce )
	local pattern = math.rad( ( effect.copies or 1 ) >= pierce and effect.pattern or 6 * pierce )
	local cast = {}
	for i = 1, copies do
		local fan = copies > 1 and ( ( i - 1 ) / ( copies - 1 ) - 0.5 ) * pattern or 0
		local angle = base + fan + ( Random( 0, 1000 ) / 1000 - 0.5 ) * spread
		local sx = at == "sky" and px + ( i - ( copies + 1 ) / 2 ) * 14 or px
		spawn( ctx, effect.file, sx, py, math.cos( angle ), math.sin( angle ), spell, effect )
		cast[#cast + 1] = effect.file
	end
	return cast
end

-- The forbidden: magic on the body. The Knights Moralis come for whoever casts it (Stevari, the Holy Mountain's
-- guardians, stand in for them)
local KNIGHTS_VAR = "witch_notebook.knights_next"
local function forbidden_price( ctx )
	local now = ctx.frame
	if now < ( tonumber( GlobalsGetValue( KNIGHTS_VAR, "0" ) ) or 0 ) then return end
	GlobalsSetValue( KNIGHTS_VAR, tostring( now + 60 * 120 ) )
	GamePrintImportant( "Forbidden Magic", "The Knights Moralis are coming for you" )
	effect_spawn( "knights", "come", ctx.x, ctx.y, { owner = ctx.shooter, delay = 240 } )
end

-- Casts the spell from x, y towards the aim; returns the projectiles' files (for tests)
function cast_spell( shooter, spell, x, y, aim_x, aim_y, target_x, target_y, frame, strokes, nested )
	SetRandomSeed( frame + x, frame + y )
	local page = spell.named and page_spell( spell.named )
	if page then spell.manifest, spell.shape, spell.forbidden = page.manifest, page.shape, page.forbidden end
	local ctx = { shooter = shooter, spell = spell, x = x, y = y, aim_x = aim_x, aim_y = aim_y, tx = target_x, ty = target_y,
		frame = frame, strokes = strokes, power = 0.5 + spell.precision }
	-- the Amplification Scroll strengthens the next spells
	if not nested then
		local amplified = tonumber( GlobalsGetValue( AMPLIFY_VAR, "0" ) ) or 0
		if amplified > 0 then
			GlobalsSetValue( AMPLIFY_VAR, tostring( amplified - 1 ) )
			ctx.power = ctx.power * 2
			spell.force = spell.force + 1
		end
	end
	ink_apply( ctx, nested )
	-- a sloppy or lopsided seal may misfire: it fizzles into a spark or releases a wrong element
	if not nested and Random( 1, 100 ) <= misfire_chance( spell ) then
		spell.element = Random( 1, 2 ) == 1 and "" or MISFIRE_ELEMENTS[Random( 1, #MISFIRE_ELEMENTS )]
		spell.manifest, spell.shape = nil, nil
		ctx.misfire = true
	end
	if not nested then seal_flash( ctx ) end
	ctx.tx, ctx.ty = target_x, target_y

	local cast
	local manifest = spell.manifest and MANIFESTS and MANIFESTS[spell.manifest]
	if manifest then
		cast = manifest( ctx ) or { "manifest:" .. spell.manifest }
	elseif spell.shape and MANIFESTS and MANIFESTS.sculpture then
		cast = MANIFESTS.sculpture( ctx ) or { "sculpture:" .. spell.shape }
	else
		cast = cast_form( ctx )
	end
	-- the seals inside it and linked to it act together with it (a wiki's seal with a way of manifesting of its own is
	-- one spell as a whole: its small seals are part of it)
	local parts = ( spell.named and spell.manifest ) and {} or { spell.subs or {}, spell.links or {} }
	for _, list in ipairs( parts ) do
		for _, other in ipairs( list ) do
			other.ink = other.ink or spell.ink -- drawn with the same ink
			local more = cast_spell( shooter, other, x, y, aim_x, aim_y, target_x, target_y, frame + 1, nil, true )
			for _, f in ipairs( more ) do cast[#cast + 1] = f end
		end
	end
	if ctx.backlash then backlash( ctx ) end
	-- the Knights Moralis don't see a seal drawn with the clear ink
	if spell.forbidden and not nested and not ctx.hidden then forbidden_price( ctx ) end
	return cast
end

local function item_var( item, name )
	for _, comp in ipairs( EntityGetComponentIncludingDisabled( item, "VariableStorageComponent" ) or {} ) do
		if ComponentGetValue2( comp, "name" ) == name then return comp end
	end
end

-- The holder clicked with a book in hand: its active page casts, as often as the book's delay allows (the Palm Quire
-- strapped to the hand casts quickly, the heavy Great Tome slowly)
function spellbook_use( item, holder, controls, frame )
	local next_var = item_var( item, SPELLBOOK_NEXT_CAST_VAR )
	local book = BOOKS[book_key_of( item )]
	local data = GlobalsGetValue( book_var( book.key, "active_spell" ), "" )
	if data == "" then
		GlobalsSetValue( BOOK_OPEN_REQUEST_VAR, book.key )
		return
	end
	if not next_var then return end
	-- a wait longer than the book last set is left from another session (the frame count starts again): it is over
	local ready = ComponentGetValue2( next_var, "value_int" )
	if ready - frame > math.max( ComponentGetValue2( next_var, "value_float" ) or 0, book.cast_delay ) then
		ComponentSetValue2( next_var, "value_int", frame )
	elseif frame < ready then
		-- still recharging: the seal only fizzles in the hand
		local x, y = EntityGetTransform( holder )
		local ax, ay = ComponentGetValue2( controls, "mAimingVectorNormalized" )
		for _ = 1, 5 do
			GameCreateCosmeticParticle( "spark_white", x + ax * HAND_OFFSET, y - 4 + ay * HAND_OFFSET, 1, ax * 20 + Random( -15, 15 ),
				ay * 20 + Random( -20, 5 ), 0, 0.3, 0.5, false, false, false, false, 0, 0 )
		end
		return
	end
	-- the quill of water (Wand of Water) draws with the button while it lasts
	if frame < ( tonumber( GlobalsGetValue( BUSY_VAR, "0" ) ) or 0 ) then return end
	-- the stronger the seal, the longer it recharges; the swift ink casts more often
	local delay = seal_cast_delay( book, parse_spell_data( data ) )
	ComponentSetValue2( next_var, "value_int", frame + delay )
	ComponentSetValue2( next_var, "value_float", delay )
	local x, y = EntityGetTransform( holder )
	local aim_x, aim_y = ComponentGetValue2( controls, "mAimingVectorNormalized" )
	local target_x, target_y = ComponentGetValue2( controls, "mMousePosition" )
	-- Sasaran's Cloak: the spell comes out of the cloak
	local remote = tonumber( GlobalsGetValue( REMOTE_VAR, "0" ) ) or 0
	if remote > 0 and EntityGetIsAlive( remote ) then
		x, y = EntityGetTransform( remote )
		local dx, dy = target_x - x, target_y - y
		local d = math.sqrt( dx * dx + dy * dy )
		if d > 0 then aim_x, aim_y = dx / d, dy / d end
		y = y + 4
	end
	local strokes = strokes_decode( GlobalsGetValue( book_var( book.key, "active_strokes" ), "" ) )
	local spell = parse_spell_data( data )
	if spell.manifest ~= "repeat" then GlobalsSetValue( LAST_SPELL_VAR, data ) end
	local made = cast_spell( holder, spell, x, y - 4, aim_x, aim_y, target_x, target_y, frame, strokes )
	for _, e in ipairs( made ) do
		if type( e ) == "number" and EntityGetIsAlive( e ) then
			local p = effect_params( e )
			-- Spells held with the book: they last while fire is held (effects/lib.lua effect_channel).
			local tag = p.kind == "flame" and p.mode == "spiral" and "witch_spiraling_stream"
				or p.kind == "aura" and p.mode == "pour" and "witch_water_pour"
			if tag then
				-- One sustained spell of a kind per caster, including when switching between books.
				for _, old in ipairs( EntityGetWithTag( tag ) or {} ) do
					if effect_params( old ).owner == holder then EntityKill( old ) end
				end
				EntityAddTag( e, tag )
				effect_set( e, "channel_book", item )
				effect_set( e, "channel_spell", data )
				if p.kind == "flame" then effect_set( e, "reveal", 1 ) end
			end
		end
	end
	return made
end
