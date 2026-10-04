-- Builds the seal projectiles ("carriers") of every element from its look in dictionary.lua: for each
-- element a bolt (column), a slow orb (levitation), a field (a seal without signs) and, with a
-- material, a cloud (dispersion). Called from init.lua: virtual files and images can only be made
-- during mod init. Templates: entities/templates/bolt.xml and field.xml, the cloud is the game's.

local TEMPLATES = "mods/witch_notebook/files/entities/templates/"
local GFX = "mods/witch_notebook/files/gfx/"
local DAMAGE_TYPES = { fire = "DAMAGE_FIRE", ice = "DAMAGE_ICE", projectile = "DAMAGE_PROJECTILE", slice = "DAMAGE_SLICE",
	explosion = "DAMAGE_EXPLOSION", electricity = "DAMAGE_ELECTRICITY" }
local BASE = DICTIONARY_CARRIER_BASE -- their lifetimes, the field's radius and damage

local FIRE_LOOP = [[
	<AudioLoopComponent file="data/audio/Desktop/projectiles.bank"
		event_name="player_projectiles/torch/loop" auto_play="1" />
]]

local function fire_audio( content, element, projectile )
	if element ~= "fire" then return content end
	local audio = FIRE_LOOP
	if projectile then
		audio = audio .. [[
	<AudioComponent file="data/audio/Desktop/projectiles.bank"
		event_root="player_projectiles/bullet_fire_heavy" />
]]
	end
	return ( content:gsub( "</Entity>%s*$", audio .. "</Entity>" ) )
end

local function fill( template, fields )
	return ( template:gsub( "{{([%w_]+)}}", function( key )
		assert( fields[key] ~= nil, "carrier field missing: " .. key )
		return tostring( fields[key] )
	end ) )
end

local function copy( t, extra )
	local out = {}
	for k, v in pairs( t ) do out[k] = v end
	for k, v in pairs( extra ) do out[k] = v end
	return out
end

-- a glowing dot in the element's color, size x size
local function make_sprite( path, size, color )
	local id = ModImageMakeEditable( path, size, size )
	if id == 0 then return end
	local c = ( size - 1 ) / 2
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local d = math.sqrt( ( x - c ) ^ 2 + ( y - c ) ^ 2 ) / ( c + 0.5 )
			local pixel = 0
			if d < 1 then
				local white = math.max( 0, 1 - d * 2.2 ) -- a hot white core
				local r = color[1] + ( 255 - color[1] ) * white
				local g = color[2] + ( 255 - color[2] ) * white
				local b = color[3] + ( 255 - color[3] ) * white
				pixel = color_abgr_merge( math.floor( r ), math.floor( g ), math.floor( b ), math.floor( 255 * ( 1 - d * d ) ) )
			end
			ModImageSetPixel( id, x, y, pixel )
		end
	end
end

function carriers_create()
	local bolt = ModTextFileGetContent( TEMPLATES .. "bolt.xml" )
	local field = ModTextFileGetContent( TEMPLATES .. "field.xml" )
	local cloud = ModTextFileGetContent( "data/entities/projectiles/deck/cloud_water.xml" )

	for key, look in pairs( DICTIONARY_LOOKS ) do
		local color = DICTIONARY_ELEMENTS[key].color
		local damage_attrs, main_type, main_amount = {}, "projectile", 0
		for kind, amount in pairs( look.damage or {} ) do
			damage_attrs[#damage_attrs + 1] = kind .. '="' .. amount .. '"'
			if amount > main_amount then main_type, main_amount = kind, amount end
		end
		local explode = ( look.explode or 0 ) > 0
		local common = {
			material = look.material or "air",
			spark = look.spark or "spark_white",
			r = color[1], g = color[2], b = color[3],
			status = look.status or "",
			damage_by_type = table.concat( damage_attrs, " " ),
			damage = 0,
			knockback = look.knockback or 0,
			speed = look.speed or 200,
			gravity = look.gravity or 0,
			air_friction = 0,
			explode = explode and 1 or 0,
			radius = look.explode or 0,
			explosion_damage = explode and main_amount * 2 or 0,
			cell_probability = ( explode and look.material ) and 30 or 0,
			hole = look.hole and 1 or 0,
			ray_energy = look.hole and 50000 or 1000,
			splash = look.material and 1 or 0,
			splash_count = look.splash or 0,
			trail = look.material and 1 or 0,
		}

		local bolt_sprite, orb_sprite = GFX .. "bolt_" .. key .. ".png", GFX .. "orb_" .. key .. ".png"
		make_sprite( bolt_sprite, 5, color )
		make_sprite( orb_sprite, 9, color )

		ModTextFileSetContent( carrier_file( key, "bolt" ), fire_audio( fill( bolt, copy( common, {
			lifetime = BASE.bolt_lifetime, die_on_low_velocity = 1, sprite = bolt_sprite, sprite_offset = 2,
			trail_count = 1, trail_interval = 3, light_radius = 40,
		} ) ), key, true ) )
		-- the orb: bigger and brighter, lingers and sheds more of its material; cast.lua slows it down
		ModTextFileSetContent( carrier_file( key, "orb" ), fire_audio( fill( bolt, copy( common, {
			lifetime = BASE.orb_lifetime, die_on_low_velocity = 0, sprite = orb_sprite, sprite_offset = 4,
			trail_count = 3, trail_interval = 1, light_radius = 70,
		} ) ), key, true ) )
		ModTextFileSetContent( carrier_file( key, "field" ), fire_audio( fill( field, copy( common, {
			field_radius = BASE.field_radius, field_lifetime = BASE.field_lifetime, field_interval = 1,
			field_damage = main_amount * BASE.field_damage, field_every = BASE.field_every,
			field_damage_type = DAMAGE_TYPES[main_type] or "DAMAGE_PROJECTILE",
			light_radius = 60,
		} ) ), key, false ) )
		if look.material then
			-- the game's rain cloud, raining the element's material
			local content = cloud:gsub( 'emitted_material_name="water"', 'emitted_material_name="' .. look.material .. '"', 1 )
			ModTextFileSetContent( carrier_file( key, "cloud" ), fire_audio( content, key, false ) )
		end
	end
end
