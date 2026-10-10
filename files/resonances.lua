-- Resonances: seals whose element, form and signs together make something none of them makes alone - as the wiki's
-- seals are more than their parts (Flame Shot is not just a shot of fire). A seal read sign by sign that holds one of
-- these combinations resonates: compile_spell (seal_spell.lua) keeps the resonance in the spell ('resonance=key'), and
-- with it the signs it is made of, even those that alone would do nothing on that carrier; cast.lua casts it
-- (resonance_cast.lua); the summary and the notes (spell_notes.lua) name it; a resonance drawn for the first time is
-- announced and kept among the witch's discoveries. A wiki seal is its page and never resonates; nor does a seal that
-- manifests in a way of its own (a special sigil, a frame, a creature).
--   key, name; title: its name for an element ("Breath of %s"), else the name
--   on: the carriers it resonates on (dictionary.lua's, and "splash" for a sigil without a sign of form)
--   own: only the mod's own carriers, not the game's projectiles (a laser, a black hole)
--   natures: the elements' natures it takes (RESONANCE_NATURES); left out, any element; matter: only an element of
--           matter (one with a material: water, sand, lava...)
--   needs: { behavior = the least weight } - all of them; any: one of these besides (Spiraling Wind or turned signs)
--   consumes: the behaviors it takes for itself - their usual effect is left out of the cast
--   replaces: it makes its own magic in place of the carrier (resonance_cast.lua 'cast'), not a twist on it
--   forbidden: magic on the body or the mind - the Knights Moralis come; recharge: frames beyond the carrier's
--   text: what it does in a few words (the summary); about( spell ): told, with its numbers (the notes)
--   lasts( frames ): how long its shot lasts, from how long it would; speed, damage: its speed and its damage (the seal's
--           own, not the element's) times this - resonance_cast.lua does it, the notes tell it
--   recipe: what the Test Book draws it of ({ forms = the Test Book's forms, signs = sign keys drawn in pairs, "~": facing
--           out, turned: the signs of form turned sideways, element: the sigil of its page among the discoveries });
--           hint: a clue for one not found yet (the discoveries)
-- The most particular resonance a seal holds wins (the most behaviors and conditions), the first listed on a tie.

-- What an element is like: the natures a resonance asks for. A mix is both its elements.
RESONANCE_NATURES = {}
for element, list in pairs( {
	fire = "hot", water = "wet", wind = "airy", earth = "earthen", light = "bright", crystal = "cold,earthen", smoke = "murky",
	thunder = "electric", flicker = "sparkling,bright", air = "airy", sand = "earthen", phantasm = "ghostly",
	plasma = "hot,bright", ice = "cold,wet", vacuum = "airy", stone = "earthen", beam = "bright", ball_lightning = "electric",
	steam = "hot,wet", steamblast = "hot,wet", firestorm = "hot,airy", lava = "hot,earthen", sunfire = "hot,bright",
	storm = "wet,airy", mud = "wet,earthen", shimmer = "wet,bright", sandstorm = "airy,earthen", frost = "cold,airy",
	smog = "hot,murky", fireworks = "hot,sparkling,bright",
} ) do
	RESONANCE_NATURES[element] = {}
	for nature in list:gmatch( "%a+" ) do RESONANCE_NATURES[element][nature] = true end
end
RESONANCE_NATURE_NAMES = { hot = "hot", wet = "wet", cold = "cold", airy = "airy", earthen = "earthen", bright = "bright",
	electric = "electric", murky = "murky", sparkling = "sparkling", ghostly = "ghostly" }

-- How much a resonance does, by the weight of its signs (1 = one ordinary sign): resonance_cast.lua does it, the notes
-- tell it
RESONANCE_AMOUNTS = {
	ricochet = function( w ) return { bounces = math.floor( 2 + 2 * math.min( w, 3 ) ) } end,
	drill = function( w ) return { r = math.floor( 8 + 4 * math.min( w, 3 ) ), life = 2 } end,
	boomerang = function( life ) return { out = math.max( 12, math.floor( math.max( life or 90, 30 ) * 0.4 ) ) } end,
	grapple = function() return { speed = 260, tow = 220, frames = 50 } end,
	swarm = function( pierce ) return { motes = math.min( 10, 2 * math.floor( pierce ) ) } end,
	cluster = function( pierce ) return { fragments = math.min( 10, 2 * math.floor( pierce ) ) } end,
	magma = function( w ) return { r = math.floor( 3 + 2 * math.min( w, 3 ) ) } end,
	sentry = function( strong ) return { every = math.floor( 45 / ( 1 + 0.3 * math.min( strong or 0, 2 ) ) ), reach = 160 } end,
	mine = function() return { wait = 900, near = 20, r = 32 } end,
	vortex = function( w ) return { r = math.floor( 60 + 20 * math.min( w, 3 ) ) } end,
	quake = function( w ) return { frames = 45 + math.floor( 15 * math.min( w, 2 ) ) } end,
	collapse = function( w ) return { wider = 1.4 + 0.2 * math.min( w, 3 ) } end,
	meteors = function( strong ) return { frames = 150 + math.floor( 60 * math.min( strong or 0, 2 ) ) } end,
	acid = function( strong ) return { frames = 240 + math.floor( 60 * math.min( strong or 0, 2 ) ) } end,
	fountain = function() return { per_frame = 2.5 } end,
	satellite = function( grow ) return { r = math.floor( 26 + 8 * math.min( grow or 0, 2 ) ), every = 10 } end,
	rampart = function( grow ) return { pieces = 12, r = math.floor( 36 + 10 * math.min( grow or 0, 2 ) ), frames = 600 } end,
	barrage = function( pierce ) return { shots = math.min( 19, 4 + 3 * math.floor( pierce ) ), every = 5 } end,
	guardian = function() return { reach = 80, every = 15 } end,
	tether = function() return { r = 90, held = 3, thread = 36 } end,
	updraft = function( strong ) return { frames = 360 + math.floor( 120 * math.min( strong or 0, 2 ) ), r = 40 } end,
	chain_storm = function( w ) return { pulses = 2 + math.floor( math.min( w, 2 ) ), reach = 90 } end,
	fissure = function( w ) return { length = math.floor( 110 + 40 * math.min( w, 2 ) ) } end,
	limpet = function() return { frames = 75, r = 40 } end,
	coffin = function( w ) return { frames = math.floor( 240 + 60 * math.min( w, 2 ) ) } end,
	entomb = function( w ) return { frames = math.floor( 180 + 60 * math.min( w, 2 ) ), pieces = 6, r = 11 } end,
	cyclone = function( w ) return { frames = math.floor( 120 + 30 * math.min( w, 2 ) ), height = 40 } end,
	wisp = function( w ) return { life = 3, reach = 260, confuse = math.floor( 120 + 60 * math.min( w, 2 ) ) } end,
	fireworks = function( pierce ) return { rockets = math.max( 2, math.min( 5, math.floor( pierce ) ) ) } end,
	pillar = function( w ) return { blocks = math.floor( 3 + math.min( w, 2 ) ) } end,
	sunburst = function( w ) return { r = math.floor( 50 + 20 * math.min( w, 2 ) ), blind = 180 } end,
}
local RA = RESONANCE_AMOUNTS

local function set( list )
	local out = {}
	for key in list:gmatch( "[%w_]+" ) do out[key] = true end
	return out
end
local function name_of( element )
	local e = DICTIONARY_ELEMENTS and DICTIONARY_ELEMENTS[element]
	return e and e.name:lower() or element
end
local function w( spell, key ) return math.abs( ( spell.behaviors or {} )[key] or 0 ) end

RESONANCES = {
	---- the splash: a sigil without a sign of form ----
	{ key = "fissure", name = "Fissure", on = set( "splash" ), natures = set( "earthen" ), needs = { crush = 0.5 }, consumes = { "crush" },
		replaces = true, text = "a crack runs along the ground", recharge = 60,
		about = function( s ) return "Earth that crushes, splashed on the ground: a crack runs " .. RA.fissure( w( s, "crush" ) ).length
			.. " px along it the way you aim, grinding the rock into sand and throwing up and hurting whoever stands over it" end,
		recipe = { forms = { "Splash" }, signs = { "crush" }, element = "earth" },
		hint = "The simplest seal of earth, with a sign that crushes." },
	---- shots ----
	{ key = "ricochet", name = "Ricochet", on = set( "bolt,orb" ), own = true, needs = { reflect = 0.5 },
		text = "bounces off walls", recharge = 10, lasts = function( life ) return math.floor( life * 1.5 + 30 ) end,
		about = function( s ) return "Reflection turns the shot back off the walls: it bounces instead of breaking, up to "
			.. RA.ricochet( w( s, "reflect" ) ).bounces .. " times" end,
		recipe = { forms = { "Column", "Orb" }, signs = { "reflection" }, element = "light" },
		hint = "What turns projectiles back might turn a shot back off a wall." },
	-- before Magma: a hot drill still bores a tunnel to walk through
	{ key = "drill", name = "Drill", on = set( "bolt,orb" ), own = true, needs = { crush = 0.5 }, any = { "whirl", "spin" },
		consumes = { "whirl", "spin" }, text = "bores a wide tunnel", recharge = 20,
		lasts = function( life ) return math.floor( life * 2 + 30 ) end,
		about = function( s ) return "The shot spins as it crushes: it bores through rock and earth for twice as long, grinding a "
			.. 2 * RA.drill( w( s, "crush" ) ).r .. " px wide tunnel into sand" end,
		recipe = { forms = { "Column" }, signs = { "crush", "windsign" }, element = "earth" },
		hint = "Crushing alone breaks rock; crushing that spins would bore through it." },
	{ key = "boomerang", name = "Boomerang", on = set( "bolt,orb" ), own = true, needs = { pull = 0.5, spin = 0.3 },
		consumes = { "pull", "spin" }, text = "flies out and comes back", recharge = 10,
		lasts = function( life ) return 4 * RA.boomerang( life ).out + 60 end,
		about = function() return "Pulling turned sideways curls the shot back: it flies out, turns and returns to your hand, "
			.. "striking every enemy on its way there and back, bouncing off walls" end,
		recipe = { forms = { "Column" }, signs = { "pull" }, turned = true, element = "water" },
		hint = "A shot that pulls, its signs turned aside, might not stay away." },
	{ key = "grapple", name = "Grapple", on = set( "bolt" ), own = true, needs = { bind = 0.5, pull = 0.5 },
		consumes = { "bind", "pull" }, text = "pulls you to where it strikes", recharge = 30, speed = 1.4,
		about = function() return "An Entwining ribbon on the shot, reeled in by Pulling: where it strikes a wall it pulls you "
			.. "there; an enemy it strikes is dragged to you" end,
		recipe = { forms = { "Column" }, signs = { "entwine", "pull" }, element = "light" },
		hint = "A ribbon on a shot, and something to reel it in." },
	{ key = "blink", name = "Blink", on = set( "bolt" ), own = true, needs = { project = 0.5 }, consumes = { "project" },
		text = "you appear where it ends", recharge = 45, speed = 1.3,
		about = function() return "Projection carries you with the shot: where it ends, you stand" end,
		recipe = { forms = { "Column" }, signs = { "projection" }, element = "wind" },
		hint = "Projection puts magic where it is sent. Send yourself with a shot." },
	-- Blink's Projection and Link besides: the more particular, it wins over Blink
	{ key = "exchange", name = "Exchange", on = set( "bolt" ), own = true, needs = { project = 0.5, link = 0.5 },
		consumes = { "project", "link" }, text = "you change places with whom it strikes", recharge = 45, speed = 1.3,
		about = function() return "Projection and Link: you change places with the first creature the shot strikes" end,
		recipe = { forms = { "Column" }, signs = { "projection", "link" }, element = "light" },
		hint = "Send yourself with a shot - and link yourself to whoever it meets." },
	{ key = "limpet", name = "Limpet", on = set( "bolt" ), own = true, needs = { bind = 0.5, grow = 0.5 }, consumes = { "bind" },
		text = "sticks, then bursts", recharge = 30,
		about = function( s )
			local a = RA.limpet()
			return string.format( "Entwining and Expansion: the swollen shot sticks to whoever it strikes - or where it ends - and "
				.. "after %.1f s bursts there in a wave of %s", a.frames / 60, name_of( s.element ) )
		end,
		recipe = { forms = { "Column" }, signs = { "entwine", "expansion" }, element = "fire" },
		hint = "A ribbon that holds on, and a shot swollen until it must burst." },
	{ key = "swarm", name = "Seeker Swarm", on = set( "bolt" ), own = true, needs = { pierce = 2, homing = 0.5 },
		consumes = { "pierce" }, replaces = true, text = "a swarm of seeking motes", recharge = 20,
		about = function( s ) return "Piercing splits the shot into " .. RA.swarm( w( s, "pierce" ) ).motes
			.. " small motes that fan out wide and each seek an enemy (Crosshair)" end,
		recipe = { forms = { "Column" }, signs = { "pierce", "crosshair" }, element = "fire" },
		hint = "Many shots, each with an eye for an enemy." },
	{ key = "cluster", name = "Cluster", on = set( "bolt,orb" ), own = true, needs = { grow = 0.5, pierce = 2 },
		consumes = { "pierce" }, text = "bursts into fragments", recharge = 20,
		about = function( s ) return "Expansion swells one shot in place of many: where it ends it bursts into "
			.. RA.cluster( w( s, "pierce" ) ).fragments .. " fragments (Piercing)" end,
		recipe = { forms = { "Column", "Orb" }, signs = { "expansion", "pierce" }, element = "earth" },
		hint = "Not many shots, but one big enough to hold them." },
	{ key = "satellite", name = "Satellite", on = set( "orb" ), own = true, needs = { link = 0.5 }, consumes = { "link" },
		text = "circles round you", recharge = 30, lasts = function( life ) return math.max( life, 300 ) end,
		about = function( s ) return "Link ties the orb to you: it circles round you while it lasts, " .. RA.satellite( w( s, "grow" ) ).r
			.. " px out, striking whoever it passes" end,
		recipe = { forms = { "Orb" }, signs = { "link" }, element = "fire" },
		hint = "An orb that flies - linked to its caster." },
	{ key = "breath", name = "Breath", title = "Breath of %s", on = set( "bolt" ), own = true, needs = { gust = 0.5 }, consumes = { "gust" },
		replaces = true, text = "a short cone of the element", recharge = 20,
		about = function( s )
			local n = RESONANCE_NATURES[s.element] or {}
			local what = n.hot and "real flames" or n.cold and "freezing beams" or ( "a spray of " .. name_of( s.element ) )
			return "Aeriforms Defined blow the shot apart into a breath: " .. what .. " in a short cone before you"
		end,
		recipe = { forms = { "Column" }, signs = { "aeriform" }, element = "fire" },
		hint = "A gust on a shot of fire might make it a breath of fire." },
	{ key = "lance", name = "Lance", on = set( "bolt" ), own = true, needs = { point = 0.5, strong = 0.5 },
		text = "a spear through everything", recharge = 15, damage = 1.5,
		about = function() return "Pointed and strengthened, the shot flies as a long spear: it passes through every enemy "
			.. "and drives deep into rock" end,
		recipe = { forms = { "Column" }, signs = { "pointing", "strengthen" }, element = "light" },
		hint = "Sharp and strong at once." },
	{ key = "sawblade", name = "Sawblade", on = set( "bolt" ), own = true, natures = set( "cold,earthen" ), needs = { spin = 0.3 },
		consumes = { "spin" }, replaces = true, text = "a spinning saw", recharge = 20,
		about = function( s ) return "Turned signs set a blade of " .. name_of( s.element ) .. " spinning: a saw that bounces "
			.. "and cuts through enemies" .. ( w( s, "grow" ) >= 1 and ", bigger with Expansion" or "" ) end,
		recipe = { forms = { "Column" }, signs = {}, turned = true, element = "crystal" },
		hint = "Something hard and sharp, set spinning." },
	{ key = "magma", name = "Magma", on = set( "bolt,orb,hover,nova" ), own = true, natures = set( "hot" ), needs = { crush = 0.5 },
		text = "melts rock into lava", recharge = 15,
		about = function( s ) return "Hot Crushing melts the rock round it into lava and the sand into molten glass, within "
			.. RA.magma( w( s, "crush" ) ).r .. " px" end,
		recipe = { forms = { "Column", "Wave" }, signs = { "crush" }, element = "fire" },
		hint = "Crushing breaks rock into sand. What would a hot element make of it?" },
	{ key = "frostfire", name = "Frostfire", on = set( "bolt,orb,hover" ), own = true, natures = set( "hot" ), needs = { cool = 0.5 },
		text = "flames that freeze", recharge = 0,
		about = function() return "Cooling turns the fire inside out: cold blue flames that deal ice in place of fire, freeze "
			.. "whom they touch and set nothing alight" end,
		recipe = { forms = { "Column", "Hanging" }, signs = { "cooling" }, element = "fire" },
		hint = "A fire that is told to be cold." },
	---- hanging orbs ----
	{ key = "sentry", name = "Sentry", on = set( "hover" ), own = true, any = { "sense", "homing" }, consumes = { "sense", "homing" },
		text = "shoots at enemies near it", recharge = 90, lasts = function( life ) return math.min( life, 300 ) end,
		about = function( s )
			local a = RA.sentry( w( s, "strong" ) )
			return string.format( "The hanging orb watches for enemies: every %.1f s it shoots %s at the nearest one it can see "
				.. "within %d px", a.every / 60, name_of( s.element ), a.reach )
		end,
		recipe = { forms = { "Hanging" }, signs = { "detection" }, element = "fire" },
		hint = "An orb that hangs still, with eyes for enemies." },
	{ key = "mine", name = "Mine", on = set( "hover" ), own = true, needs = { shrink = 0.5 }, text = "waits, then bursts", recharge = 20,
		lasts = function( life ) return life + RA.mine().wait end,
		about = function( s )
			local a = RA.mine()
			return "Made small, the hanging orb lies in wait for up to " .. math.floor( a.wait / 60 ) .. " s; when an enemy comes "
				.. "within " .. a.near .. " px it bursts in a wave of " .. name_of( s.element )
		end,
		recipe = { forms = { "Hanging" }, signs = { "expansion~" }, element = "fire" },
		hint = "Something small and still, waiting." },
	{ key = "vortex", name = "Vortex", on = set( "hover" ), own = true, needs = { pull = 0.5 }, any = { "whirl", "spin" },
		consumes = { "pull", "whirl", "spin" }, text = "a vortex that draws all in", recharge = 40,
		lasts = function( life ) return math.min( life, 300 ) + 60 end,
		about = function( s ) return "Pulling that whirls: the orb becomes a vortex - creatures, loose things and enemy shots within "
			.. RA.vortex( w( s, "pull" ) ).r .. " px are drawn in and swept round it" end,
		recipe = { forms = { "Hanging" }, signs = { "pull", "windsign" }, element = "wind" },
		hint = "Pulling, with a wind that spirals." },
	{ key = "fountain", name = "Fountain", on = set( "hover" ), own = true, matter = true, needs = { scatter = 0.5 },
		consumes = { "scatter" }, text = "pours out its matter", recharge = 60, lasts = function( life ) return math.min( life, 360 ) end,
		about = function( s )
			local m = ( ( DICTIONARY_LOOKS[s.element] or {} ).material or "matter" ):gsub( "_", " " )
			return "Scattering held still: the hanging orb pours out " .. m .. " without end while it lasts - a spring, a sandfall, "
				.. "a flow of lava"
		end,
		recipe = { forms = { "Hanging" }, signs = { "collection~" }, element = "water" },
		hint = "An orb that hangs still and scatters what it is made of." },
	{ key = "tether", name = "Tether", on = set( "hover" ), own = true, needs = { link = 0.5 }, consumes = { "link" },
		text = "threads hold creatures to it", recharge = 40, lasts = function( life ) return math.min( life, 360 ) end,
		about = function()
			local a = RA.tether()
			return "Link threads the hanging orb to the " .. a.held .. " creatures nearest it within " .. a.r .. " px: they can get "
				.. "no farther from it than " .. a.thread .. " px, and the thread stings"
		end,
		recipe = { forms = { "Hanging" }, signs = { "link" }, element = "light" },
		hint = "An orb that hangs still, linked to whoever comes near." },
	---- waves ----
	{ key = "quake", name = "Quake", on = set( "nova" ), natures = set( "earthen" ), needs = { crush = 0.5 },
		text = "the ground quakes", recharge = 60,
		about = function( s ) return string.format( "Earth and Crushing in a wave: the ground shakes for %.1f s - creatures "
			.. "standing on it are thrown up and hurt, the rock cracks into sand", RA.quake( w( s, "crush" ) ).frames / 60 ) end,
		recipe = { forms = { "Wave" }, signs = { "crush" }, element = "earth" },
		hint = "A wave of earth that crushes." },
	{ key = "collapse", name = "Collapse", on = set( "nova" ), needs = { pull = 0.5, grow = 0.5 },
		text = "draws in, then bursts out", recharge = 30,
		about = function( s ) return "The wave rushes in to its middle (Pulling), then bursts out again "
			.. math.floor( 100 * ( RA.collapse( w( s, "grow" ) ).wider - 1 ) + 0.5 ) .. "% wider and harder (Expansion)" end,
		recipe = { forms = { "Wave" }, signs = { "pull", "expansion" }, element = "water" },
		hint = "A wave that draws in, and something to make it bigger." },
	{ key = "tide", name = "Tide", on = set( "nova" ), natures = set( "wet" ), needs = { gust = 0.5 }, consumes = { "gust" },
		text = "rolling waves either way", recharge = 40,
		about = function( s ) return "Aeriforms drive the wave of " .. name_of( s.element ) .. " along the ground: two rolling "
			.. "waves run out either way, carrying enemies off" end,
		recipe = { forms = { "Wave" }, signs = { "aeriform" }, element = "water" },
		hint = "Wind behind a wave of water." },
	{ key = "chain_storm", name = "Chain Storm", on = set( "nova" ), natures = set( "electric" ), needs = { link = 0.5 },
		consumes = { "link" }, text = "lightning leaps to every enemy near", recharge = 60,
		about = function( s )
			local a = RA.chain_storm( w( s, "link" ) )
			return "Link in a wave of lightning: " .. a.pulses .. " times it leaps from you to every enemy you can see within "
				.. a.reach .. " px"
		end,
		recipe = { forms = { "Wave" }, signs = { "link" }, element = "lightning" },
		hint = "A wave of lightning, linked to all it reaches." },
	{ key = "rampart", name = "Rampart", on = set( "nova" ), needs = { solid = 0.5 }, consumes = { "solid" },
		text = "a ring of walls round you", recharge = 60,
		about = function( s )
			local a = RA.rampart( w( s, "grow" ) )
			return "Solidification in the wave: where it stops, " .. a.pieces .. " blocks of its element set in a ring round you, "
				.. a.r .. " px out, for " .. math.floor( a.frames / 60 ) .. " s"
		end,
		recipe = { forms = { "Wave" }, signs = { "solidify" }, element = "earth" },
		hint = "A wave that sets solid where it stops." },
	---- fields ----
	{ key = "healing_spring", name = "Healing Spring", on = set( "field" ), natures = set( "wet" ), needs = { purify = 0.5 },
		consumes = { "purify" }, replaces = true, forbidden = true, text = "heals - forbidden", recharge = 240,
		about = function() return "Purified water held round you: a spring that heals whoever stands in it. Magic on the body - "
			.. "the Knights Moralis will come" end,
		recipe = { forms = { "Field" }, signs = { "purify" }, element = "water" },
		hint = "Clean water that stays round you. Some magic is forbidden for a reason." },
	{ key = "frenzy", name = "Frenzy", on = set( "field" ), natures = set( "hot" ), needs = { strong = 0.5 }, consumes = { "strong" },
		replaces = true, forbidden = true, text = "drives creatures mad - forbidden", recharge = 180,
		about = function() return "Strengthened fire held at the cursor: the creatures in it fly into a rage and fall on whatever is "
			.. "near them. Magic on the mind - the Knights Moralis will come" end,
		recipe = { forms = { "Field" }, signs = { "strengthen" }, element = "fire" },
		hint = "A circle of fire, made stronger still. It burns minds." },
	{ key = "charm", name = "Charm", on = set( "field" ), natures = set( "sparkling,ghostly" ), needs = { mimic = 0.5 },
		consumes = { "mimic" }, replaces = true, forbidden = true, text = "charms creatures - forbidden", recharge = 240,
		about = function() return "Lights at the cursor that the creatures in them follow (Mimicry): they fight on your side for a "
			.. "while. Magic on the mind - the Knights Moralis will come" end,
		recipe = { forms = { "Field" }, signs = { "mimicry" }, element = "flicker" },
		hint = "Dazzling lights in a circle, and a sign that makes others copy." },
	{ key = "updraft", name = "Updraft", on = set( "field" ), natures = set( "airy" ), needs = { gust = 0.5 }, consumes = { "gust" },
		replaces = true, text = "you fly as long as it lasts", recharge = 120,
		about = function( s )
			local a = RA.updraft( w( s, "strong" ) )
			return string.format( "Aeriforms rising in a held circle of wind: for %.0f s you fly without tiring, and creatures "
				.. "within %d px of you are blown up", a.frames / 60, a.r )
		end,
		recipe = { forms = { "Field" }, signs = { "aeriform" }, element = "wind" },
		hint = "A circle of wind round you, and a gust in it." },
	---- rain ----
	{ key = "meteors", name = "Meteor Shower", on = set( "cloud" ), natures = set( "earthen" ), needs = { grow = 0.5 },
		consumes = { "grow" }, replaces = true, text = "meteors fall from the sky", recharge = 300,
		about = function( s ) return string.format( "Expansion makes the rain of earth a shower of meteors that crash down round "
			.. "the cursor for %.1f s", RA.meteors( w( s, "strong" ) ).frames / 60 ) end,
		recipe = { forms = { "Rain" }, signs = { "expansion" }, element = "earth" },
		hint = "Rain of earth, made bigger." },
	{ key = "acid_rain", name = "Acid Rain", on = set( "cloud" ), natures = set( "wet,murky" ), needs = { crush = 0.5 },
		consumes = { "crush" }, replaces = true, text = "rains acid", recharge = 90,
		about = function( s ) return string.format( "Crushing in the rain cloud: it rains acid that eats through rock and flesh "
			.. "for %.1f s", RA.acid( w( s, "strong" ) ).frames / 60 ) end,
		recipe = { forms = { "Rain" }, signs = { "crush" }, element = "water" },
		hint = "Rain that crushes what it falls on." },
	{ key = "barrage", name = "Barrage", title = "Barrage of %s", on = set( "cloud" ), own = true, needs = { pierce = 1 },
		consumes = { "pierce" }, replaces = true, text = "shots fall from the sky", recharge = 90,
		about = function( s )
			local a = RA.barrage( w( s, "pierce" ) )
			return string.format( "Piercing in the rain: %d shots of %s fall round the cursor from above, one after another, "
				.. "over %.1f s", a.shots, name_of( s.element ), a.shots * a.every / 60 )
		end,
		recipe = { forms = { "Rain" }, signs = { "pierce" }, element = "crystal" },
		hint = "Rain made of shots." },
	---- an element's own way with a sign (after the rest: on a tie a resonance of any element wins) ----
	{ key = "ice_coffin", name = "Ice Coffin", on = set( "bolt,orb" ), own = true, natures = set( "cold" ), needs = { envelop = 0.5 },
		consumes = { "envelop" }, text = "freezes whom it strikes solid", recharge = 30,
		about = function( s ) return string.format( "Cold that envelops: whoever the shot strikes is frozen solid in ice for %.0f s",
			RA.coffin( w( s, "envelop" ) ).frames / 60 ) end,
		recipe = { forms = { "Column" }, signs = { "envelop" }, element = "crystal" },
		hint = "Something cold that wraps round whom it strikes." },
	{ key = "entomb", name = "Entomb", on = set( "bolt,orb" ), own = true, natures = set( "earthen" ), needs = { envelop = 0.5 },
		consumes = { "envelop" }, text = "walls in whom it strikes", recharge = 30,
		about = function( s )
			local a = RA.entomb( w( s, "envelop" ) )
			return string.format( "Earth that envelops: whoever the shot strikes is walled in by %d blocks of %s and held for "
				.. "%.0f s", a.pieces, name_of( s.element ), a.frames / 60 )
		end,
		recipe = { forms = { "Column" }, signs = { "envelop" }, element = "earth" },
		hint = "Earth that wraps round whom it strikes." },
	{ key = "cyclone", name = "Cyclone", on = set( "bolt,orb" ), own = true, natures = set( "airy" ), needs = { envelop = 0.5 },
		consumes = { "envelop" }, text = "whirls whom it strikes up into the air", recharge = 30,
		about = function( s ) return string.format( "Wind that envelops: whoever the shot strikes is caught up in a whirl %d px "
			.. "into the air for %.1f s, then let fall", RA.cyclone( w( s, "envelop" ) ).height, RA.cyclone( w( s, "envelop" ) ).frames / 60 ) end,
		recipe = { forms = { "Column" }, signs = { "envelop" }, element = "wind" },
		hint = "Wind that wraps round whom it strikes." },
	{ key = "wisp", name = "Wisp", on = set( "bolt,orb" ), own = true, natures = set( "ghostly" ), needs = { homing = 0.5 },
		consumes = { "homing" }, text = "a ghost flame that hunts through walls", recharge = 20,
		lasts = function( life ) return life * 3 + 60 end, speed = 0.6,
		about = function( s ) return string.format( "An unburning flame with eyes for enemies: slow and long, it passes through "
			.. "the walls hunting them within %d px; whoever it touches is bewildered for %.0f s", RA.wisp( w( s, "homing" ) ).reach,
			RA.wisp( w( s, "homing" ) ).confuse / 60 ) end,
		recipe = { forms = { "Column" }, signs = { "crosshair" }, element = "unburning" },
		hint = "A flame that burns nothing, sent to find someone." },
	{ key = "fireworks", name = "Fireworks", on = set( "bolt" ), own = true, natures = set( "sparkling" ), needs = { pierce = 2 },
		consumes = { "pierce" }, replaces = true, text = "a volley of fireworks", recharge = 60,
		about = function( s ) return "Piercing sparkles: " .. RA.fireworks( w( s, "pierce" ) ).rockets .. " rockets of fireworks "
			.. "fly up before you and burst in colours" end,
		recipe = { forms = { "Column" }, signs = { "pierce" }, element = "flicker" },
		hint = "Sparkling light, many shots of it." },
	{ key = "pillar", name = "Pillar", on = set( "bolt,orb,hover" ), own = true, natures = set( "earthen" ), needs = { solid = 0.5 },
		text = "a pillar rises where it ends", recharge = 20,
		about = function( s ) return "Earth that sets solid: where the shot ends a pillar of " .. RA.pillar( w( s, "solid" ) ).blocks
			.. " blocks of " .. name_of( s.element ) .. " rises - a step, a wall" end,
		recipe = { forms = { "Column" }, signs = { "solidify" }, element = "earth" },
		hint = "Earth that hardens where it lands." },
	{ key = "sunburst", name = "Sunburst", on = set( "bolt,orb" ), own = true, natures = set( "bright" ), needs = { grow = 0.5 },
		text = "a blinding flash where it ends", recharge = 30,
		about = function( s )
			local a = RA.sunburst( w( s, "grow" ) )
			return string.format( "Light swollen by Expansion: where the shot ends it bursts in a flash that blinds every creature "
				.. "within %d px for %.0f s", a.r, a.blind / 60 )
		end,
		recipe = { forms = { "Column" }, signs = { "expansion" }, element = "light" },
		hint = "Light, made bigger." },
	---- the ring of lights ----
	{ key = "halo", name = "Halo", on = set( "ring" ), needs = { reflect = 0.5 }, text = "lights turn shots back", recharge = 20,
		about = function() return "Reflection in the ring of lights: enemy projectiles that reach the ring turn back" end,
		recipe = { forms = { "Ring" }, signs = { "reflection" }, element = "light" },
		hint = "A ring of lights that reflects." },
	{ key = "blades", name = "Blade Dance", on = set( "ring" ), needs = { point = 0.5 }, text = "orbiting blades", recharge = 20,
		about = function() return "Pointing sharpens the lights round you into blades that cut whoever they pass" end,
		recipe = { forms = { "Ring" }, signs = { "pointing" }, element = "crystal" },
		hint = "The lights round you, made sharp." },
	{ key = "guardian", name = "Guardian Lights", on = set( "ring" ), needs = { sense = 0.5 }, consumes = { "sense" },
		text = "lights fly at enemies that come near", recharge = 40,
		about = function( s )
			local a = RA.guardian()
			return "Detection in the ring: when an enemy comes within " .. a.reach .. " px, a light leaves the ring and flies at it "
				.. "as a shot of " .. name_of( s.element ) .. ", one after another until none is left"
		end,
		recipe = { forms = { "Ring" }, signs = { "detection" }, element = "light" },
		hint = "The lights round you, with eyes for enemies." },
}
RESONANCE_BY_KEY = {}
for i, r in ipairs( RESONANCES ) do
	r.order = i
	RESONANCE_BY_KEY[r.key] = r
	r.uses = {}
	for key in pairs( r.needs or {} ) do r.uses[key] = true end
	for _, key in ipairs( r.any or {} ) do r.uses[key] = true end
	r.consumed = {}
	for _, key in ipairs( r.consumes or {} ) do r.consumed[key] = true end
end

-- What an element in a form is carried by, as a resonance sees it: the carrier ("splash" for a sigil without a sign of
-- form) and whether it is the mod's own (not the game's projectile)
function resonance_carrier( element, form, floats )
	local effect = dictionary_effect( element, form, floats )
	if not effect then return nil end
	if effect.splash then return "splash", true end
	local own = ( effect.file or "" ):find( "/carriers/", 1, true ) ~= nil or effect.carrier == "nova" or effect.carrier == "ring"
	return effect.carrier, own
end

-- The resonance a spell of this element in this form holds with these behaviors ({ key = weight }, before the ones
-- that do nothing on its carrier are left out), or nil
function resonance_find( element, form, floats, behaviors )
	local carrier, own = resonance_carrier( element, form, floats )
	if not carrier then return nil end
	local natures = RESONANCE_NATURES[element] or {}
	local best, best_score
	for _, r in ipairs( RESONANCES ) do
		local fits = r.on[carrier] and ( own or not r.own )
		if fits and r.natures then
			fits = false
			for nature in pairs( r.natures ) do if natures[nature] then fits = true end end
		end
		if fits and r.matter and not ( DICTIONARY_LOOKS[element] or {} ).material then fits = false end
		local score = ( r.natures and 1 or 0 ) + ( r.matter and 1 or 0 )
		if fits then
			for key, least in pairs( r.needs or {} ) do
				if math.abs( behaviors[key] or 0 ) < least then fits = false; break end
				score = score + 1
			end
		end
		if fits and r.any then
			local found = false
			for _, key in ipairs( r.any ) do if math.abs( behaviors[key] or 0 ) >= 0.3 then found = true end end
			fits, score = found, score + 1
		end
		if fits and ( not best or score > best_score ) then best, best_score = r, score end
	end
	return best
end

-- its name, for the element it is cast in
function resonance_title( r, element )
	return r.title and string.format( r.title, name_of( element ) ) or r.name
end

-- what it is drawn of, in words: "Column with Reflection", "Wave with Pulling and Expansion"
function resonance_recipe_text( r )
	local names = {}
	for _, key in ipairs( r.recipe.signs ) do
		local sign = DICTIONARY_SIGNS[key:gsub( "~$", "" )]
		names[#names + 1] = sign.name .. ( key:find( "~$" ) and " facing out" or "" )
	end
	if r.recipe.turned then names[#names + 1] = "the signs turned sideways" end
	local forms = table.concat( r.recipe.forms, " or " )
	local natures = {}
	for nature in pairs( r.natures or {} ) do natures[#natures + 1] = nature end
	table.sort( natures )
	local element = #natures > 0 and ( "a " .. table.concat( natures, " or " ) .. " element, " ) or ""
	return element .. forms .. ( #names > 0 and ( ", " .. table.concat( names, " and " ) ) or "" )
end

-- what it is drawn of, short, for under its page: "Column + Crushing + Spiraling Wind", "Column turned sideways"
function resonance_recipe_short( r )
	local parts = { r.recipe.forms[1] .. ( r.recipe.turned and " turned sideways" or "" ) }
	for _, key in ipairs( r.recipe.signs ) do
		parts[#parts + 1] = DICTIONARY_SIGNS[key:gsub( "~$", "" )].name .. ( key:find( "~$" ) and " facing out" or "" )
	end
	return table.concat( parts, " + " )
end

---- the witch's discoveries: the resonances drawn so far, kept for good (like the grimoire's learned seals) ----

RESONANCE_FOUND_SETTING = "witch_notebook.resonances_found"

function resonance_found()
	local out = {}
	for key in ( ModSettingGet( RESONANCE_FOUND_SETTING ) or "" ):gmatch( "[%w_]+" ) do out[key] = true end
	return out
end

-- A seal holding this resonance was drawn: true when it is the first time
function resonance_discover( key )
	if not RESONANCE_BY_KEY[key] then return false end
	local found = ModSettingGet( RESONANCE_FOUND_SETTING ) or ""
	for k in found:gmatch( "[%w_]+" ) do if k == key then return false end end
	ModSettingSet( RESONANCE_FOUND_SETTING, found == "" and key or ( found .. "," .. key ) )
	return true
end
