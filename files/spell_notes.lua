-- What a spell does, told so that it can be checked in the game: what appears and where, its numbers, what each of its
-- signs does, how much, and what it needs to show - most signs only act on a creature they strike or on the ground and
-- liquids around - and, beside the same seal without them, what the signs changed. The numbers are what cast.lua does
-- (spell_tuning, SIGN_AMOUNTS, SIGN_CONVERTS; manifest.lua MANIFEST_SCALE) to the carriers' own (DICTIONARY_CARRIER_BASE),
-- for the seal as drawn, in its inks (on average: blood's power jumps). The Test Book writes them beside its pages
-- (test_book.lua), a book under a drawn seal the mouse is over (notebook.lua).
--   spell_notes( data, plain ) -> { { text = , kind = "head" | "body" | "sign" | "test" | "diff" }, ... }
--   ('data', 'plain': what pages keep, serialize_spell; 'plain': the seal without the signs tried, or nil)

local HP = 25 -- the game's damage 1 is 25 hit points

local function name_of( element )
	local e = DICTIONARY_ELEMENTS[element]
	return e and e.name:lower() or element
end

local function seconds( frames ) return string.format( "%.1f s", frames / 60 ) end
local function times( k ) return ( string.format( "x%.2f", k ):gsub( "0$", "" ) ) end

-- what a status effect file does to whom it hits
local STATUS = { on_fire = "sets on fire", wet = "wets", frozen = "freezes", blindness = "blinds", electricity = "shocks" }
local function status_word( file )
	for key, word in pairs( STATUS ) do
		if ( file or "" ):find( key, 1, true ) then return word end
	end
end

-- Which signs give a behavior, by name
local GIVEN_BY
local function given_by( key )
	if not GIVEN_BY then
		GIVEN_BY = { spin = "Signs turned sideways", launch = "One Regions facing out", bound = "Regions, Partition",
			purify = "Purification" }
		for _, sign in ipairs( DICTIONARY_SIGN_ORDER ) do
			local def = DICTIONARY_SIGNS[sign]
			-- drawn facing the middle, and facing outwards when that is another behavior
			for i, way in ipairs( { { def.behavior, def.name }, { def.inverted and def.inverted.behavior, def.name .. " facing out" } } ) do
				local b = way[1]
				if b and b ~= "regions" and b ~= "thrust" and b ~= "float" and not ( i == 2 and b == def.behavior ) then
					if not GIVEN_BY[b] then GIVEN_BY[b] = way[2]
					elseif not GIVEN_BY[b]:find( way[2], 1, true ) then GIVEN_BY[b] = GIVEN_BY[b] .. ", " .. way[2] end
				end
			end
		end
	end
	return GIVEN_BY[key] or key
end

---- what appears, and its numbers ----

-- How a spell manifests: { carrier, effect (dictionary_effect), at ("hand", "self", "target", "enemy", "sky", "front") }
local function manifestation( spell )
	local effect = dictionary_effect( spell.element, spell.form, spell.floats )
	if not effect then return nil end
	local b, carrier = spell.behaviors, effect.carrier
	local at = effect.at or "hand"
	if ( carrier == "field" or carrier == "nova" ) and ( b.homing or b.aim or b.project ) then at = "target" end
	if b.sense and ( carrier == "field" or carrier == "nova" or carrier == "cloud" ) then at = "enemy" end
	if carrier == "hover" then at = "front" end
	return { carrier = carrier, effect = effect, at = at, own = ( effect.file or "" ):find( "/carriers/", 1, true ) ~= nil }
end

-- The numbers of what appears: { key = value } and the order to tell them in
local function numbers( spell, how, power )
	local b, look = spell.behaviors, DICTIONARY_LOOKS[spell.element] or {}
	local tuned = spell_tuning( spell, power )
	local function amount( key ) return b[key] and SIGN_AMOUNTS[key]( b[key] ) or nil end
	local grow, shrink, strong, point = amount( "grow" ), amount( "shrink" ), amount( "strong" ), amount( "point" )
	local size = ( grow and grow.size or 1 ) * ( shrink and shrink.size or 1 )
	local base, n, carrier = DICTIONARY_CARRIER_BASE, {}, how.carrier
	local ctx = { spell = spell, power = power }
	if carrier == "field" and how.own then
		local main = 0
		for _, v in pairs( look.damage or {} ) do main = math.max( main, v ) end
		local life = math.max( 30, base.field_lifetime + tuned.field_lifetime )
		if strong then life = math.floor( life * strong.lifetime ) end
		n.radius, n.lasts = base.field_radius * size, life
		n.dps = main * base.field_damage * tuned.field_damage * ( strong and strong.damage or 1 ) * 60 / base.field_every * HP
	elseif how.own and ( carrier == "bolt" or carrier == "orb" or carrier == "hover" or how.at == "sky" ) then
		local life = math.max( 1, ( how.effect.file:find( "/orb_", 1, true ) and base.orb_lifetime or base.bolt_lifetime ) + tuned.lifetime )
		if strong then life = math.floor( life * strong.lifetime ) end
		if b.still and amount( "still" ) then life = life + amount( "still" ).frames end
		n.lasts = life
		local speed = ( look.speed or 200 ) * tuned.speed / ( grow and grow.slow or 1 ) * ( shrink and shrink.speed or 1 )
			* ( point and point.speed or 1 ) * ( b.launch and amount( "launch" ).speed or 1 )
		if speed > 0 then n.speed = speed end
		local generic = tuned.damage * ( grow and grow.damage or 1 ) * ( shrink and shrink.damage or 1 ) * ( strong and strong.damage or 1 )
			* ( point and point.damage or 1 )
		local hit = generic
		for _, v in pairs( look.damage or {} ) do hit = hit + v end
		n.hit = hit * HP
		if ( look.explode or 0 ) > 0 then n.blast = ( look.explode + tuned.blast ) * size end
		n.shots = math.max( how.effect.copies or 1, b.pierce or 0 )
		local spread = 2 + 20 * ( spell.spread - spell.focus ) + 15 * ( spell.directed and 0 or spell.tilt )
		if spread >= 1 and carrier ~= "hover" then n.spread = spread end
	elseif carrier == "nova" and spell.element ~= "shockwave" then
		n.radius = MANIFEST_SCALE.size( ctx, 55 )
	elseif carrier == "ring" then
		n.lights = 10 + 2 * math.min( 4, math.floor( b.pierce or 0 ) )
		n.radius, n.lasts = 24 * MANIFEST_SCALE.grown( ctx ), MANIFEST_SCALE.secs( ctx, 10 )
	end
	return n
end

-- the numbers, in this order: how each is told ("%s": its value)
local NUMBER_ORDER = { "shots", "lights", "radius", "lasts", "speed", "hit", "dps", "blast", "spread" }
local NUMBER_TEXT = { shots = "%s shots", lights = "%s lights", radius = "radius %s", lasts = "lasts %s", speed = "speed %s",
	hit = "hits for %s", dps = "%s damage a second", blast = "blast radius %s", spread = "scatter %s" }
local function value_text( key, v )
	if key == "lasts" then return seconds( v ) end
	if key == "spread" then return math.floor( v + 0.5 ) .. " deg" end
	return tostring( math.floor( v + 0.5 ) )
end
local function number_text( key, v ) return ( NUMBER_TEXT[key]:gsub( "%%s", value_text( key, v ) ) ) end
-- a change worth telling: a count, or a twentieth and more
local function same_number( key, a, b )
	if key == "shots" or key == "lights" then return a == b end
	return math.abs( a - b ) < 0.05 * math.max( math.abs( a ), math.abs( b ), 1 )
end

local WHERE = { hand = "flies from the hand", self = "around you", target = "at the cursor", enemy = "at the nearest enemy",
	sky = "falls from above the cursor", front = "hangs before you, towards the cursor" }
local function where( at ) return ( at == "hand" or at == "sky" or at == "front" ) and ( " " .. WHERE[at] ) or ( ", " .. WHERE[at] ) end

-- what appears and where, in a few words
local function heading( spell, how )
	local element = name_of( spell.element )
	if spell.shape then return "A sculpture: " .. DICTIONARY_SIGILS[spell.shape].name:lower() .. " of " .. element .. ", at the cursor" end
	if spell.manifest then
		return ( MANIFEST_NAMES[spell.manifest] or spell.manifest ):gsub( "^%l", string.upper ) .. " (element: " .. element .. ")"
	end
	if spell.element == "shockwave" then return "A shockwave from the seal: it pushes creatures away, harms nothing" end
	local carrier, at = how.carrier, how.at
	if not how.own then
		-- the game's own projectile: its words say where, or they are told
		local text = how.effect.text:gsub( "^%l", string.upper )
		if not ( text:find( " at the ", 1, true ) or text:find( " over the ", 1, true ) or text:find( " from ", 1, true ) ) then
			text = text .. where( at )
		end
		return text .. " (the game's own spell)"
	end
	if carrier == "bolt" and at ~= "sky" then return "A shot of " .. element .. where( at ) end
	if carrier == "orb" then return "A slow orb of " .. element .. where( at ) end
	if carrier == "hover" then return "An orb of " .. element .. where( at ) .. ", and stays" end
	if carrier == "nova" then return "A wave of " .. element .. " runs out from you" .. ( at ~= "self" and ( ", " .. WHERE[at] ) or "" ) end
	if carrier == "ring" then return "Lights of " .. element .. " circle around you" end
	if carrier == "cloud" and at == "sky" then return "Shots of " .. element .. " rain from above the cursor" end
	if carrier == "cloud" then
		return "A cloud " .. ( at == "enemy" and "over the nearest enemy" or "over the cursor" ) .. " rains " .. name_of( spell.element )
	end
	return "A field of " .. element .. ( at == "self" and " around you" or where( at ) )
end

-- what it does to whom it hits and leaves behind (the ring of lights only strikes, its matter is for show)
local function touch( spell, how )
	local look = DICTIONARY_LOOKS[spell.element]
	if not look or not how.own or spell.manifest or spell.shape then return nil end
	if how.carrier == "ring" then return table.concat( { "strikes whom it touches", status_word( look.status ) }, ", " ) end
	local parts = {}
	local types = {}
	for kind in pairs( look.damage or {} ) do types[#types + 1] = kind end
	table.sort( types )
	if #types > 0 then parts[#parts + 1] = table.concat( types, "+" ) .. " damage" end
	parts[#parts + 1] = status_word( look.status )
	if look.material then parts[#parts + 1] = "leaves " .. look.material:gsub( "_", " " ) end
	if ( look.knockback or 0 ) >= 60 then parts[#parts + 1] = "knocks back" end
	return #parts > 0 and table.concat( parts, ", " ) or nil
end

---- the signs ----

-- what a sign does on this carrier, with its amount, and what it needs to show: text, test
local function sign_text( key, w, spell, how )
	local a = SIGN_AMOUNTS[key] and SIGN_AMOUNTS[key]( w )
	local carrier, element = how.carrier, name_of( spell.element )
	local placed = carrier == "field" or carrier == "nova"
	local own = spell.manifest or spell.shape
	if own then
		local ctx = { spell = spell, power = 1.5 }
		if key == "grow" or key == "shrink" then return ( key == "grow" and "bigger, " or "smaller, " ) .. times( MANIFEST_SCALE.grown( ctx ) ) end
		if key == "still" then return "lasts longer, " .. times( 1 + 0.4 * math.min( 2, w ) ) end
		if key == "pierce" then return "more of it: +" .. math.min( 4, math.floor( w ) ) end
		if key == "strong" then return "stronger" end
		if key == "mimic" then return "follows the cursor", "move the mouse after casting" end
	end
	if key == "pierce" then
		if carrier == "ring" then return "more lights" end
		return math.floor( w ) .. " shots at once, each passes through enemies", "shoot into a group of enemies"
	elseif key == "homing" then
		if placed then return "appears at the cursor instead", "aim away from yourself" end
		if carrier == "cloud" and how.at ~= "sky" then return "drifts to hang over the enemy nearest to it", "cast it beside an enemy" end
		return "turns towards enemies within " .. math.floor( a.reach ) .. " px", "shoot past an enemy, not at it"
	elseif key == "aim" then
		if placed then return "appears at the cursor instead", "aim away from yourself" end
		return "flies straight to the point aimed at and bursts there", "aim at empty air: it stops at the cursor"
	elseif key == "sense" then
		if placed or carrier == "cloud" then return "appears at the enemy nearest to you, within 180 px", "stand near an enemy, aim elsewhere" end
		return "seeks enemies up to " .. math.floor( a.reach ) .. " px away", "shoot towards a distant enemy"
	elseif key == "mimic" then
		return "follows the cursor while it lasts", "move the mouse after casting"
	elseif key == "pull" or key == "push" then
		if carrier == "nova" then return key == "pull" and "the wave rushes in from its edge" or "the wave throws harder" end
		return ( key == "pull" and "draws creatures and loose things in" or "pushes creatures and loose things away" )
			.. ", within " .. math.floor( SIGN_AMOUNTS.pull( w ).reach ) .. " px", "pass close to an enemy or loose items"
	elseif key == "gust" then
		if carrier == "nova" then return "the wave throws harder", "an enemy in its path" end
		return "throws whom it hits harder (+" .. math.floor( a.knock ) .. " knockback) and blows things away", "hit an enemy"
	elseif key == "crush" or key == "build" or key == "soften" or key == "purify" or key == "refuse" or key == "cool" then
		local r = carrier == "nova" and "as it passes" or ( "within " .. math.floor( a.r ) .. " px" )
		local what = {
			crush = { "grinds rock and earth into sand " .. r .. ( ( carrier == "bolt" or carrier == "orb" ) and ", bores through" or "" ),
				"hit a rock wall" },
			build = { "loose sand and snow set solid " .. r, "cast at sand or snow" },
			soften = { "hard rock and ice soften into soil and sand " .. r, "hit a rock wall" },
			purify = { "foul liquids turn clean, blood into water, " .. r, "cast at a pool of sludge or blood" },
			refuse = { "clears blood, pus, slime and vomit " .. r, "where blood was spilled" },
			cool = { "freezes water, blood and slime " .. r .. ", chills whom it hits", "cast at water or an enemy" },
		}
		return what[key][1], what[key][2]
	elseif key == "grow" then
		if carrier == "ring" then return "a wider ring" end
		return "bigger, " .. times( a.size ) .. ( placed and "" or ( ", hits " .. times( a.damage ) .. ", slower" ) )
	elseif key == "shrink" then
		if carrier == "ring" then return "a tighter ring" end
		return "smaller, " .. times( a.size ) .. ( placed and "" or ( ", faster " .. times( a.speed ) ) )
	elseif key == "strong" then
		return "hits " .. times( a.damage ) .. ", lasts " .. times( a.lifetime )
	elseif key == "point" then
		return "faster " .. times( a.speed ) .. ", hits " .. times( a.damage ) .. ", passes through enemies"
	elseif key == "spin" or key == "whirl" then
		return "curls in loops as it flies"
	elseif key == "still" then
		if carrier == "ring" then return "lasts longer" end
		return "slows to a stop and hangs in the air, " .. seconds( a.frames ) .. " longer"
	elseif key == "hold" then
		return "holds whom it strikes in " .. element .. " for " .. seconds( a.frames ), "hit an enemy"
	elseif key == "bind" then
		return "a ribbon binds whom it strikes for " .. seconds( a.frames ), "hit an enemy"
	elseif key == "envelop" then
		return "where it hits, " .. element .. " wraps round the target in a ring and keeps striking", "hit an enemy"
	elseif key == "link" then
		return "from the enemy it hits it jumps on to " .. a.jumps .. " more", "hit one of several enemies"
	elseif key == "gather" then
		return "draws in the liquid it passes, up to " .. a.cells .. " cells, and pours it out where it ends", "send it through a pool"
	elseif key == "scatter" then
		local look = DICTIONARY_LOOKS[spell.element] or {}
		return "spills three times as much " .. ( look.material or "matter" ):gsub( "_", " " ) .. " where it ends", "watch where it lands"
	elseif key == "contain" then
		return "fills with the liquid around it, up to " .. a.cells .. " cells, and spills it when it ends", "cast it over water"
	elseif key == "solid" then
		return "where it ends, its " .. element .. " sets into a solid block for a while", "hit the floor or a wall"
	elseif key == "reflect" then
		if carrier == "nova" then return "turns enemies' projectiles back as it passes", "cast it under fire" end
		return "turns enemies' projectiles back" .. ( carrier == "hover" and ( " within " .. math.floor( a.r ) .. " px" ) or "" ),
			"stand in it under fire"
	elseif key == "project" then
		return "appears at the cursor instead", "aim away from yourself"
	elseif key == "bound" then
		return "its edge keeps creatures out of the circle round you (in, at the target)", "let an enemy walk into it"
	elseif key == "launch" then
		return "a short, hard dash: speed " .. times( a.speed ) .. ", then it slows"
	end
	local b = DICTIONARY_BEHAVIOR[key]
	return b and b.text or key
end

---- the notes ----

-- The dyed inks the seal is drawn with do to it what cast.lua's ink_apply does, on average (blood's power jumps around
-- it): returns the power, and the inks in words
local function with_inks( spell, power )
	local shares, words = ink_mix( spell.ink ), {}
	for _, ink in ipairs( INKS ) do
		local share = shares[ink.key] or 0
		if ink.key ~= "ink" and share >= 0.05 then
			if ink.force then
				spell.force = spell.force + ink.force * share
				power = power * ( 1 + ( ink.power or 0 ) * share )
				spell.layers = ( spell.layers or 0 ) + share
			end
			if ink.lifetime then spell.lifetime = spell.lifetime + ink.lifetime * share end
			if ink.range then spell.range = spell.range + ink.range * share end
			words[#words + 1] = ink.name .. ( share < 0.95 and ( " (" .. math.floor( share * 100 + 0.5 ) .. "%)" ) or "" ) .. ": " .. ink.hint
				.. ( ink.wild and ", the numbers are its average" or "" )
		end
	end
	return power, words
end

local function prepared( data )
	local spell = parse_spell_data( data )
	local power, inks = with_inks( spell, 0.5 + ( spell.precision or 1 ) )
	return spell, power, inks
end

-- the numbers alone, as numbers() has them (the tests hold them against what is cast)
function spell_numbers( data )
	local spell, power = prepared( data )
	local how = manifestation( spell )
	if not how or spell.manifest or spell.shape then return {} end
	return numbers( spell, how, power )
end

function spell_notes( data, plain )
	local spell, power, inks = prepared( data )
	local out = {}
	local function add( text, kind ) if text and text ~= "" then out[#out + 1] = { text = text, kind = kind } end end
	local how = manifestation( spell )
	if not how and not spell.manifest and not spell.shape then
		add( "A spark: the seal holds no element", "head" )
		return out
	end
	how = how or { carrier = "field", effect = {}, at = "self", own = false }
	-- one of the wiki's seals: its own words
	local entry = spell.named and GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[spell.named]
	if entry then
		add( entry.name, "head" )
		add( entry.effect, "body" )
	else
		add( heading( spell, how ), "head" )
	end
	local n = ( spell.manifest or spell.shape ) and {} or numbers( spell, how, power )
	local said = {}
	for _, key in ipairs( NUMBER_ORDER ) do
		if n[key] and not ( key == "shots" and n[key] == 1 ) then said[#said + 1] = number_text( key, n[key] ) end
	end
	add( table.concat( said, ", " ), "body" )
	add( touch( spell, how ), "body" )
	for _, b in ipairs( DICTIONARY_BEHAVIORS ) do
		local w = spell.behaviors[b.key]
		if w and b.key ~= "thrust" and b.key ~= "float" then
			local text, test = sign_text( b.key, w, spell, how )
			add( given_by( b.key ) .. ": " .. text, "sign" )
			if test then add( "try: " .. test, "test" ) end
		end
	end
	-- the seals drawn inside it and linked to it are cast with it
	for _, part in ipairs( { { spell.subs, "Inside it, cast with it: " }, { spell.links, "Linked, cast with it: " } } ) do
		for _, other in ipairs( part[1] or {} ) do
			local how_other = manifestation( other )
			if how_other or other.manifest or other.shape then
				add( part[2] .. heading( other, how_other or { carrier = "field", effect = {}, at = "self", own = false } ):gsub( "^%u", string.lower ), "sign" )
			end
		end
	end
	for _, words in ipairs( inks ) do add( words, "ink" ) end
	-- beside the seal without the signs: the numbers they changed
	if plain then
		local before, before_power = prepared( plain )
		local was = ( before.manifest or before.shape ) and {} or numbers( before, manifestation( before ) or how, before_power )
		local changed = {}
		for _, key in ipairs( NUMBER_ORDER ) do
			if n[key] and was[key] and not same_number( key, n[key], was[key] ) then
				changed[#changed + 1] = number_text( key, n[key] ) .. " (was " .. value_text( key, was[key] ) .. ")"
			end
		end
		if #changed > 0 then add( "Changed: " .. table.concat( changed, ", " ), "diff" ) end
	end
	local misfire = math.floor( misfire_chance( spell ) + 0.5 )
	if misfire >= 5 then add( "Misfires " .. misfire .. "% of the casts", "diff" ) end
	return out
end
