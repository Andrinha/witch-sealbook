-- A seal's meaning: the spell of a read drawing, by the rules in dictionary.lua. Loaded after seal.lua (parse_seal:
-- the seal tree) and seal_canon.lua (the wiki's seal the drawing is).
--   read_spell( strokes )      -> spell (or nil and why not), seal tree: what the book makes of a finished drawing
--   compile_spell( seal )      -> spell, or nil and why not
--   seal_named_spell( strokes, unread ) -> the spell of a wiki's seal known by its shape alone
--   seal_page_data( spell ), serialize_spell( spell ) -> what a book's page keeps and cast.lua reads back

local clamp, round2 = SealRead.clamp, SealRead.round2
local MAX_ROUNDNESS, SPAN, FRAME_SCORE = SealRead.MAX_ROUNDNESS, SealRead.SPAN, SealRead.FRAME_SCORE

local SIGIL_SIZE = 0.5       -- sigil size (share of the radius) of an ordinary spell
local SIGN_SIZE = 0.25       -- sign size (share of the radius) that counts once
local SIGN_MIN_SIZE = 0.06   -- a few pixels of erased ink cannot stand for a full modifier
local SIGN_MIN_MARGIN = 0.025 -- weak signs need a clear winner among different symbol keys
local UNBALANCED_TILT = 0.35 -- tilt from which the spell is shown as lopsided ...
local DIRECTED = 0.75        -- ... and from which it is aimed on purpose
local SPIN_TURN = math.rad( 45 ) -- signs turned this much sideways on average spin the spell fully
local MIN_SPIN = 0.4         -- share of SPIN_TURN from which the spell spins (~18 degrees)
local SIMPLE_SEAL = 4        -- signs a seal holds without losing precision
local SIGN_COST = 0.03       -- precision lost for every sign beyond that
local SAME_SIGNS_FULL = 4    -- this many signs of one kind count whole (a cross, as in the manga)
local SAME_SIGN_RETURN = 0.6 -- each further one adds this share of the one before: at most 5.5 signs' worth
local MAX_PIERCE = 5         -- projectiles from piercing signs
local CANCELLED = 0.35       -- what is left of two opposite behaviors below this (a third of a sign: hands draw unevenly) is nothing
local MIN_READING_QUALITY = 0.42 -- a weak ring and mostly weak symbols cannot hold a spell
local MIN_SYMBOL_QUALITY = 0.35 -- check the whole reading independently of the ring
local MIN_SIGIL_QUALITY = 0.65 -- check the element sigils together, independently of their modifiers
local SPECIAL_ONLY_MIN_SCORE = 0.6 -- a weak resemblance to a special sigil cannot make an element from nothing: torn
                                  -- pieces of an element sigil read as one (a wind sigil's S as Repetition)
local SCULPTURE_ONLY_MIN_SCORE = 0.5 -- ... a creature's: its many strokes never match as closely
SEAL_FLAWLESS = 0.75         -- precision from which a seal is flawless
SEAL_SLOPPY = 0.35           -- precision below which a seal may misfire
SEAL_UNSTABLE = 0.7          -- stability below which a seal may misfire

local PARAMS = { "force", "focus", "spread", "range", "lifetime" }
local FORM_ORDER = { "column", "dispersion", "levitation", "rain", "ring" }

-- Does a sign's behavior do something to a spell of this element on this carrier, or (given) in its own way of
-- manifesting? Scattering scatters the element's matter: an element without one has nothing to scatter.
local function sign_works( key, element, carrier, own )
	if key == "scatter" and not own and not ( DICTIONARY_LOOKS[element] or {} ).material then return false end
	return dictionary_behavior_works( key, carrier, own )
end

-- Returns the spell { element, form, force, focus, spread, range, lifetime, heavy, tilt, push_x, push_y,
-- stability, precision, behaviors = { key = weight }, shape, manifest, frame, layers, glaives, subs, links,
-- summary, quality } or nil and an error text
function compile_spell( seal )
	local sigils, signs, specials = {}, {}, {}
	for _, symbol in ipairs( seal.symbols ) do
		if symbol.kind == "sigil" then
			local def = DICTIONARY_SIGILS[symbol.key] or {}
			if def.element then sigils[#sigils + 1] = symbol end
			if def.manifest or def.shape or def.behavior then specials[#specials + 1] = symbol end
		else
			-- Keep ambiguous candidates in the parse so segmentation can finish, but do not silently
			-- turn them into effects. The player can correct the sign and retry the closed seal.
			if symbol.size < SIGN_MIN_SIZE then return nil, "A sign is too small" end
			if symbol.score < SEAL_GOOD_SCORE and symbol.margin and symbol.margin < SIGN_MIN_MARGIN then
				return nil, "A sign is ambiguous"
			end
			signs[#signs + 1] = symbol
		end
	end
	if #sigils == 0 and #specials > 0 then
		local strong = false
		for _, symbol in ipairs( specials ) do
			local least = DICTIONARY_SIGILS[symbol.key].shape and SCULPTURE_ONLY_MIN_SCORE or SPECIAL_ONLY_MIN_SCORE
			if symbol.score >= least then strong = true; break end
		end
		if not strong then return nil, "The sigil is too faint" end
	end
	local spell = { force = 0, focus = 0, spread = 0, range = 0, lifetime = 0, heavy = 0 }
	local frame = seal.frames and seal.frames[1]
	local frame_def = frame and DICTIONARY_FRAMES[frame.key]

	-- special sigils: a way of manifesting (the first one drawn biggest), a creature's shape, a behavior
	table.sort( specials, function( a, b ) return a.size > b.size end )
	for _, symbol in ipairs( specials ) do
		local def = DICTIONARY_SIGILS[symbol.key]
		if def.shape and not spell.shape then spell.shape = def.shape end
		if def.manifest and not spell.manifest then spell.manifest = def.manifest end
		if def.forbidden then spell.forbidden = true end
	end
	if frame_def and frame_def.manifest and not spell.manifest then spell.manifest = frame_def.manifest end
	if seal.band == "windows" then spell.manifest = "portal" end

	-- element: the sigil; two different sigils mix into a third (DICTIONARY_MIXES), more don't hold;
	-- the same sigil again adds power, bigger sigils a bigger effect
	local element
	if #sigils == 0 then
		if #signs > 0 and not spell.manifest and not spell.shape then return nil, "No element sigil" end
		element = ( spell.manifest or spell.shape ) and "light" or "shockwave" -- the wiki: closing an empty ring makes a shockwave
		if spell.manifest == "shadow" or spell.manifest == "oblivion" then element = "smoke" end
		if spell.manifest == "cloud" then element = "sand" end
	else
		local kinds, seen, area, weight = {}, {}, 0, {}
		for _, sigil in ipairs( sigils ) do
			local e = DICTIONARY_SIGILS[sigil.key].element
			if not seen[e] then seen[e] = true; kinds[#kinds + 1] = e end
			weight[e] = ( weight[e] or 0 ) + sigil.size * sigil.size
			area = area + sigil.size * sigil.size
		end
		if #kinds > 3 or ( #kinds == 3 and not spell.manifest and not spell.shape ) then
			return nil, "Too many elements - the ring will not hold"
		end
		local order = {}
		for i, key in ipairs( DICTIONARY_SIGIL_ORDER ) do order[key] = i end
		-- the two biggest elements mix; a third one (only with a special sigil) lends its parameters
		table.sort( kinds, function( a, b ) return weight[a] > weight[b] end )
		if #kinds >= 2 then
			local a, b = kinds[1], kinds[2]
			if order[a] > order[b] then a, b = b, a end
			element = DICTIONARY_MIXES[a .. "+" .. b] or kinds[1]
		else
			element = kinds[1]
		end
		-- a mix takes the average of both elements' parameters
		for _, key in ipairs( kinds ) do
			for _, p in ipairs( PARAMS ) do spell[p] = spell[p] + ( DICTIONARY_ELEMENTS[key][p] or 0 ) / #kinds end
		end
		-- two small sigils side by side count like one big one
		local size = math.sqrt( area / ( #sigils - #kinds + 1 ) )
		spell.force = spell.force + 0.3 * ( #sigils - #kinds ) + 0.5 * ( clamp( size / SIGIL_SIZE, 0.5, 1.6 ) - 1 )
	end

	-- signs: parameters, votes for the form, behaviors, condensing, direction, spin and balance
	local votes, condense, behaviors = {}, 0, {}
	local dir_x, dir_y, dir_w, pos_x, pos_y, turn, turned_signs = 0, 0, 0, 0, 0, 0, 0
	local regions = {}
	-- more of the same sign gives less and less: the four biggest count whole, each next one 0.6 of the one
	-- before, so a seal can't be made endlessly strong by piling up one sign (balance still uses all)
	local by_size = {}
	for i, sign in ipairs( signs ) do by_size[i] = sign end
	table.sort( by_size, function( a, b ) return a.size > b.size end )
	local same = {}
	local span = 0
	for _, sign in ipairs( by_size ) do
		local def = DICTIONARY_SIGNS[sign.key]
		local inverted = sign.inverted and def.invertible ~= false
		local effect = ( inverted and def.inverted ) or def
		local w = clamp( sign.size / SIGN_SIZE, 0.5, 1.8 )
		local kind = sign.key .. ( inverted and "~" or "" )
		local share = SAME_SIGN_RETURN ^ math.max( 0, ( same[kind] or 0 ) + 1 - SAME_SIGNS_FULL )
		same[kind] = ( same[kind] or 0 ) + 1
		for _, p in ipairs( PARAMS ) do spell[p] = spell[p] + ( effect[p] or 0 ) * w * share end
		if effect.form then votes[effect.form] = ( votes[effect.form] or 0 ) + ( effect.vote or 1 ) * w end
		local behavior = effect.behavior
		if behavior == "regions" then
			regions[#regions + 1] = { dir = sign.dir or 0, angle = sign.angle, inverted = inverted, w = w }
		elseif behavior == "whirl" then
			-- the spiraling wind: which way it curls is which way it spins
			behaviors.whirl = ( behaviors.whirl or 0 ) + ( sign.mirror and -1 or 1 ) * w * share
		elseif behavior then
			-- piercing: the number of signs is the number of projectiles (the wiki)
			behaviors[behavior] = ( behaviors[behavior] or 0 ) + ( behavior == "pierce" and 1 or w * share )
		end
		condense = condense + ( effect.condense or 0 ) * w
		spell.heavy = spell.heavy + ( effect.heavy or 0 ) * w * share
		if def.type == "directional" and behavior ~= "regions" then
			-- a directional sign pushes where it points (towards the other side of the ring, if it faces
			-- the center) - the Sign Length Demo: a longer column pushes the water away from it
			local d = sign.dir or ( sign.angle + math.pi )
			dir_x = dir_x + math.cos( d ) * w
			dir_y = dir_y + math.sin( d ) * w
			dir_w = dir_w + w
			turn = turn + ( sign.turn or 0 ) * w
			if math.abs( sign.turn or 0 ) >= MIN_SPIN * SPIN_TURN then turned_signs = turned_signs + 1 end
		end
		if sign.size >= SPAN then span = math.max( span, sign.size ) end
		pos_x, pos_y = pos_x + math.cos( sign.angle ), pos_y + math.sin( sign.angle )
	end
	-- Regions (the wiki's Region Sign Demo): all pointing in or out of the ring confine the magic to the
	-- ring or send it outwards, pointing at each other they put it on the ring line, pointing one way they
	-- send it that way; alone, pointing out, it launches (Bird of Light Beacon)
	if #regions > 0 then
		local sx, sy, inward, outward, total = 0, 0, 0, 0, 0
		for _, r in ipairs( regions ) do
			sx, sy, total = sx + math.cos( r.dir ) * r.w, sy + math.sin( r.dir ) * r.w, total + r.w
			if r.inverted then outward = outward + r.w else inward = inward + r.w end
		end
		local aligned = math.sqrt( sx * sx + sy * sy ) / total
		if #regions >= 2 and aligned >= 0.75 then
			votes.column = ( votes.column or 0 ) + total * 0.8
			dir_x, dir_y, dir_w = dir_x + sx, dir_y + sy, dir_w + total
			behaviors.thrust = ( behaviors.thrust or 0 ) + total * 0.5
		elseif inward > 0 and outward > 0 and math.abs( inward - outward ) <= 0.35 * total then
			votes.ring = ( votes.ring or 0 ) + total
		elseif outward > inward then
			if #regions == 1 then
				behaviors.launch = ( behaviors.launch or 0 ) + total
			else
				votes.dispersion = ( votes.dispersion or 0 ) + outward * 0.8
			end
		else
			spell.focus = spell.focus + 0.15 * inward
			behaviors.bound = ( behaviors.bound or 0 ) + inward * 0.5
		end
	end
	-- At least two directional signs must turn sideways together; one imperfect arrow only directs the spell.
	local spin = dir_w > 0 and clamp( turn / dir_w / SPIN_TURN, -1, 1 ) or 0
	if turned_signs >= 2 and math.abs( spin ) >= MIN_SPIN then behaviors.spin = spin end
	if behaviors.whirl then
		if math.abs( behaviors.whirl ) < CANCELLED then behaviors.whirl = nil end
	end
	if behaviors.pierce then behaviors.pierce = math.min( behaviors.pierce, MAX_PIERCE ) end
	-- a sign and the same sign inverted cancel out: only the difference is left
	for _, b in ipairs( DICTIONARY_BEHAVIORS ) do
		if b.opposite then
			local net = ( behaviors[b.key] or 0 ) - ( behaviors[b.opposite] or 0 )
			behaviors[b.key], behaviors[b.opposite] = nil, nil
			if net >= CANCELLED then behaviors[b.key] = net elseif net <= -CANCELLED then behaviors[b.opposite] = -net end
		end
	end
	-- a special sigil's own behavior (the Sigil of Purification purifies)
	for _, symbol in ipairs( specials ) do
		local def = DICTIONARY_SIGILS[symbol.key]
		if def.behavior then behaviors[def.behavior] = ( behaviors[def.behavior] or 0 ) + 1 end
	end
	-- a sign spanning the whole seal (Flame Shot, Skysoaring) drives it far
	if span > 0 then
		spell.range = spell.range + 0.6 * ( span - SPAN + 0.3 )
		spell.span = round2( span )
	end
	spell.behaviors = behaviors

	spell.form = "burst"
	local best_vote = 0
	if frame_def and frame_def.form then votes[frame_def.form] = ( votes[frame_def.form] or 0 ) + 3 end
	for _, form in ipairs( FORM_ORDER ) do
		if ( votes[form] or 0 ) > best_vote then spell.form, best_vote = form, votes[form] end
	end
	local base = DICTIONARY_ELEMENTS[element]
	if condense > 0 and base.condensed then element = base.condensed end
	spell.element = element
	-- levitation alone (the Pyreball Seal): the sphere hangs over the seal instead of flying away
	spell.floats = spell.form == "levitation" and ( behaviors.thrust or 0 ) < 0.5 * ( ( behaviors.float or 0 ) + ( behaviors.contain or 0 ) ) or nil

	-- only what works on the spell's carrier (a field doesn't fly, so it can't pierce or spin), or what its own way of
	-- manifesting takes from the signs
	local effect = dictionary_effect( element, spell.form, spell.floats )
	local carrier = effect and effect.carrier or "field"
	for key in pairs( behaviors ) do
		if not sign_works( key, element, carrier, spell.manifest or spell.shape ) then behaviors[key] = nil end
	end
	if behaviors.spin then spell.range = spell.range - 0.3 * math.abs( behaviors.spin ) end

	spell.tilt = dir_w > 0 and math.sqrt( dir_x * dir_x + dir_y * dir_y ) / dir_w or 0
	spell.push_x = dir_w > 0 and dir_x / dir_w or 0
	spell.push_y = dir_w > 0 and dir_y / dir_w or 0
	-- all directional signs pointing one way (Flame Shot, Skysoaring, the Water Bolt's regions): the seal is
	-- aimed on purpose - it flies where the caster aims, it isn't lopsided
	if spell.tilt >= DIRECTED and dir_w >= 1 then spell.directed = true end
	local symmetry = #signs > 0 and math.sqrt( pos_x * pos_x + pos_y * pos_y ) / #signs or 0
	spell.stability = clamp( 1 - 0.5 * symmetry, 0, 1 )

	-- an extra ring endows the spell with stronger magic (the wiki's Vapor Bubble, Sand Bridge)
	spell.layers = #seal.layers
	spell.force = spell.force + 0.3 * #seal.layers
	spell.lifetime = spell.lifetime + 0.1 * #seal.layers
	if seal.glaives > 0 then spell.glaives = seal.glaives; spell.forbidden = true end
	if frame then spell.frame = frame.key end

	-- seals drawn inside the seal and seals linked to it: spells of their own, cast with it
	spell.subs, spell.links = {}, {}
	for _, list in ipairs( { { seal.subs, spell.subs }, { seal.links, spell.links } } ) do
		for _, sub in ipairs( list[1] ) do
			local s = compile_spell( sub )
			if s then list[2][#list[2] + 1] = s end
		end
	end

	-- precision: how round the ring is and how cleanly the symbols are drawn
	local ring_quality = clamp( 1 - seal.ring.roundness / MAX_ROUNDNESS, 0, 1 )
	local precision = ring_quality
	local count = #seal.symbols + ( frame and 1 or 0 )
	local symbol_quality = 1 -- an empty ring has no symbols to validate
	if count > 0 then
		local q = 0
		for _, symbol in ipairs( seal.symbols ) do
			q = q + clamp( ( symbol.score - SEAL_MIN_SCORE ) / ( SEAL_GOOD_SCORE - SEAL_MIN_SCORE ), 0, 1 )
		end
		if frame then q = q + clamp( ( frame.score - FRAME_SCORE ) / 0.25, 0, 1 ) end
		symbol_quality = q / count
		precision = ( ring_quality + symbol_quality ) / 2
	end
	local reading_quality = precision
	-- the price of complexity: every sign beyond a few is one more chance to slip
	local complexity_cost = SIGN_COST * math.max( 0, #signs - SIMPLE_SEAL )
	precision = math.max( 0, precision - complexity_cost )
	spell.precision = round2( precision )
	for _, p in ipairs( { "force", "focus", "spread", "range", "lifetime", "heavy", "tilt", "push_x", "push_y", "stability" } ) do
		spell[p] = round2( spell[p] )
	end
	for key, w in pairs( behaviors ) do behaviors[key] = round2( w ) end

	-- the wiki's seal this one is, if the drawing is close enough to one (grimoire.lua)
	local named, distance = seal_name( seal )
	if named then
		spell.named = named
		-- a faithful drawing of a known seal is a clean one, however many signs it has
		if distance then spell.precision = round2( math.max( spell.precision, seal_canon_precision( distance ) ) ) end
		local entry = GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[named]
		if entry and entry.manifest then spell.manifest = entry.manifest end
		if entry and entry.forbidden then spell.forbidden = true end
		spell.extras = entry and extra_behaviors( seal, entry )
	end
	if not named and count > 0 then
		local sigil_quality, sigil_count = 0, 0
		for _, symbol in ipairs( seal.symbols ) do
			if symbol.kind == "sigil" then
				sigil_quality = sigil_quality + clamp( ( symbol.score - SEAL_MIN_SCORE ) / ( SEAL_GOOD_SCORE - SEAL_MIN_SCORE ), 0, 1 )
				sigil_count = sigil_count + 1
			end
		end
		if sigil_count > 0 and sigil_quality / sigil_count < MIN_SIGIL_QUALITY then return nil, "The sigil is too imprecise" end
		if symbol_quality - complexity_cost < MIN_SYMBOL_QUALITY then return nil, "The symbols are too imprecise" end
		if reading_quality < MIN_READING_QUALITY then return nil, "The seal is too imprecise" end
	end

	spell.summary = spell_summary( spell, carrier )
	if spell.precision < SEAL_SLOPPY then
		spell.quality = "Uneven seal - it may misfire"
	elseif spell.stability < SEAL_UNSTABLE then
		spell.quality = "Asymmetric seal - unstable"
	elseif spell.precision >= SEAL_FLAWLESS then
		spell.quality = "Flawless seal!"
	else
		spell.quality = "Precision " .. math.floor( spell.precision * 100 + 0.5 ) .. "%"
	end
	return spell
end

-- The spell in words: the wiki's name, if it is one of its seals, or what it does
function spell_summary( spell, carrier )
	local entry = spell.named and GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[spell.named]
	if entry then
		-- and what the signs drawn on top of it add
		local parts = { entry.name }
		for _, b in ipairs( DICTIONARY_BEHAVIORS ) do
			if spell.extras and spell.extras[b.key] and b.text then parts[#parts + 1] = b.text end
		end
		return table.concat( parts, ", " )
	end
	carrier = carrier or ( dictionary_effect( spell.element, spell.form, spell.floats ) or {} ).carrier or "field"
	local parts = { DICTIONARY_ELEMENTS[spell.element] and DICTIONARY_ELEMENTS[spell.element].name or spell.element }
	local manifest = spell.manifest and MANIFEST_NAMES and MANIFEST_NAMES[spell.manifest]
	if spell.shape then
		parts[#parts + 1] = "sculpture: " .. DICTIONARY_SIGILS[spell.shape].name:lower()
	elseif manifest then
		parts[#parts + 1] = manifest
	elseif spell.element ~= "shockwave" then
		parts[#parts + 1] = spell.floats and "floats in place" or DICTIONARY_FORMS[spell.form]
	end
	for _, b in ipairs( DICTIONARY_BEHAVIORS ) do
		local text = b["text_" .. carrier] or b.text
		local w = spell.behaviors[b.key]
		if text and w then
			parts[#parts + 1] = text .. ( b.key == "pierce" and w > 1 and " x" .. w or "" )
		end
	end
	if spell.directed then
		parts[#parts + 1] = "directed"
	elseif spell.tilt >= UNBALANCED_TILT then
		parts[#parts + 1] = "lopsided"
	end
	return table.concat( parts, ", " ) -- Noita's font has no middle dot
end

-- Signs drawn on a wiki's seal beyond its own (read with confidence): what they add to its spell, { behavior = weight }
-- or nil. Signs that make the form (columns, levitation, regions) don't reshape a wiki's seal.
local EXTRA_SURE = 0.7
function extra_behaviors( seal, entry )
	-- what the page's spell is carried by, or its own way of manifesting: only the signs that work on it count
	local page = ( entry.spell or "" ):match( "^[^&]*" )
	local element = page:match( "element=([%w_]+)" ) or ""
	local carried = dictionary_effect( element, page:match( "form=(%w+)" ) or "burst", page:find( "floats=true", 1, true ) and true or nil )
	local carrier, own = carried and carried.carrier or "field", entry.manifest or page:match( "manifest=([%w_]+)" ) or page:match( "shape=(%w+)" )
	local want = {}
	for _, signature in ipairs( { entry.symbols or "", entry.recipe or "" } ) do
		for k, n in signature:gmatch( "([%w_:]+)=(%d+)" ) do want[k] = math.max( want[k] or 0, tonumber( n ) ) end
	end
	local have, extras = {}, {}
	for _, sym in ipairs( seal.symbols or {} ) do
		if sym.kind == "sign" and sym.score >= EXTRA_SURE then
			local k = "sign:" .. sym.key
			have[k] = ( have[k] or 0 ) + 1
			if have[k] > ( want[k] or 0 ) then
				local def = DICTIONARY_SIGNS[sym.key]
				local effect = ( sym.inverted and def.invertible ~= false and def.inverted ) or def
				local b = effect.behavior
				if b and b ~= "regions" and b ~= "thrust" and b ~= "float" and sign_works( b, element, carrier, own ) then
					extras[b] = ( extras[b] or 0 ) + ( b == "pierce" and 1 or clamp( sym.size / SIGN_SIZE, 0.5, 1.8 ) )
				end
			end
		end
	end
	return next( extras ) and extras or nil
end

-- What the book keeps on a seal's page and casts (cast.lua parse_spell_data): a seal of the wiki (grimoire.lua) casts as
-- the wiki's spell - the one its own page in the book reads as - with the precision and balance of this drawing
-- the wiki's spell with the signs drawn on top of it added: "b=pull:1" becomes "b=pull:1,pierce:2"
local function add_behaviors( data, extras )
	local main, rest = data:match( "^([^&]*)(.*)$" )
	local order, weight = {}, {}
	local b = main:match( ";?b=([^;]*)" )
	for key, w in ( b or "" ):gmatch( "(%w+):([-%d.]+)" ) do
		order[#order + 1] = key
		weight[key] = tonumber( w )
	end
	for _, behavior in ipairs( DICTIONARY_BEHAVIORS ) do
		local w = extras[behavior.key]
		if w then
			if not weight[behavior.key] then order[#order + 1] = behavior.key end
			weight[behavior.key] = ( weight[behavior.key] or 0 ) + w
		end
	end
	local list = {}
	for i, key in ipairs( order ) do list[i] = key .. ":" .. round2( weight[key] ) end
	main = main:gsub( ";?b=[^;]*", "" ) .. ";b=" .. table.concat( list, "," )
	return main .. rest
end

function seal_page_data( spell )
	local entry = spell.named and GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[spell.named]
	if not entry or entry.spell == "" then return serialize_spell( spell ) end
	local data = entry.spell
	if spell.extras then data = add_behaviors( data, spell.extras ) end
	local precision, stability = tostring( spell.precision or 1 ), tostring( spell.stability or 1 )
	if data:find( "precision=", 1, true ) then
		data = data:gsub( "precision=[-%d.]+", "precision=" .. precision )
	else
		data = data:gsub( "^([^&]*)", "%1;precision=" .. precision )
	end
	if data:find( "stability=", 1, true ) then
		data = data:gsub( "stability=[-%d.]+", "stability=" .. stability )
	else
		data = data:gsub( "^([^&]*)", "%1;stability=" .. stability )
	end
	return data
end

-- A drawing that is one of the wiki's seals as a whole: the spell of its page (grimoire.lua), or nil. Known by its
-- shape alone: a seal the book can't read symbol by symbol, and - when the drawing's signs didn't read ('unread') -
-- a faithful copy of a seal of signs
function seal_named_spell( strokes, unread )
	local key, distance, second = seal_canonical( { strokes = strokes } )
	local entry = key and GRIMOIRE_BY_KEY[key]
	if not entry then return nil end
	if ( entry.symbols or "" ) == "" then
		if not whole_alike( distance, second ) then return nil end
	elseif not ( unread and whole_sure( distance, second ) ) then
		return nil
	end
	local precision = round2( seal_canon_precision( distance ) )
	local page, element = seal_middle( strokes, entry )
	local spell
	if element then
		-- the seal with a sigil no page of the wiki has in its middle: the page's spell in that sigil's element, and
		-- no seal of the wiki's
		spell = { element = element, form = "burst", manifest = page.manifest, precision = precision, stability = 1,
			behaviors = {}, tilt = 0 }
		spell.summary = spell_summary( spell )
		spell.data = seal_page_data( { named = page.key, precision = precision, stability = 1 } )
			:gsub( "element=[%w_]+", "element=" .. element, 1 ):gsub( ";named=[%w_]+", "", 1 )
	else
		spell = { named = page.key, summary = page.name, precision = precision, stability = 1,
			element = page.spell:match( "element=([%w_]+)" ) or "light" }
		spell.data = seal_page_data( spell )
	end
	spell.quality = precision >= SEAL_FLAWLESS and "Flawless seal!" or ( "Precision " .. math.floor( precision * 100 + 0.5 ) .. "%" )
	return spell
end

-- What the book makes of a finished drawing: one of the wiki's seals known at a glance, as a whole; else the seal read
-- symbol by symbol; else, when its symbols don't read, a faithful copy of one of the wiki's seals of signs.
-- Returns the spell (or nil and why not) and the seal tree when the drawing was read symbol by symbol
function read_spell( strokes )
	local spell = seal_named_spell( strokes )
	if spell then return spell end
	local seal, err = parse_seal( strokes )
	if seal then spell, err = compile_spell( seal ) end
	if not spell then
		local copy = seal_named_spell( strokes, true )
		if copy then return copy, nil, seal end
	end
	return spell, err, seal
end

local SPELL_FIELDS = { "element", "form", "force", "focus", "spread", "range", "lifetime", "heavy", "tilt", "push_x", "push_y",
	"stability", "precision", "floats", "directed", "shape", "manifest", "named", "frame", "layers", "glaives", "forbidden", "span" }

-- Stored on the spellbook's page and read back when it is cast (cast.lua): "element=fire;...;b=pull:1.2,spin:-0.8".
-- Seals inside the seal and linked seals follow, each after "&".
function serialize_spell( spell )
	local parts, b = {}, {}
	for _, key in ipairs( SPELL_FIELDS ) do
		local v = spell[key]
		if v ~= nil and v ~= false then parts[#parts + 1] = key .. "=" .. tostring( v ) end
	end
	for _, behavior in ipairs( DICTIONARY_BEHAVIORS ) do
		local w = ( spell.behaviors or {} )[behavior.key]
		if w then b[#b + 1] = behavior.key .. ":" .. tostring( w ) end
	end
	if #b > 0 then parts[#parts + 1] = "b=" .. table.concat( b, "," ) end
	local out = table.concat( parts, ";" )
	for _, sub in ipairs( spell.subs or {} ) do out = out .. "&sub:" .. serialize_spell( sub ) end
	for _, link in ipairs( spell.links or {} ) do out = out .. "&link:" .. serialize_spell( link ) end
	return out
end
