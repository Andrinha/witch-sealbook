-- Meaning of sigils, signs and frames (their shapes are in templates.lua), shared by the book (seal.lua) and
-- the book in hand (cast.lua, its own Lua context). Based on the Independent Witch Hat Atelier Wiki (Sigils
-- Explained, Signs Explained, Spells); parameter deltas follow wha-spell-simulator. See docs/architecture.md.
--
-- Parameters: force (damage, blast), focus (narrower), spread (wider), range (speed, reach),
-- lifetime (how long the effect lasts). Each sign adds its deltas scaled by its size.

-- Elements. 'condensed' is what convergence compresses the element into.
DICTIONARY_ELEMENTS = {
	fire  = { name = "Fire",   color = { 255, 120, 40 },  condensed = "plasma",
	          force = 0.12, focus = 0.04, spread = 0.08, range = 0.02, lifetime = -0.03 },
	water = { name = "Water",  color = { 60, 130, 255 },  condensed = "ice",
	          force = 0.02, focus = -0.04, spread = 0.12, range = 0.04, lifetime = 0.08 },
	wind  = { name = "Wind",   color = { 150, 230, 190 }, condensed = "vacuum",
	          force = 0.08, focus = 0.08, spread = 0.02, range = 0.14, lifetime = -0.02 },
	earth = { name = "Earth",  color = { 190, 140, 80 },  condensed = "stone",
	          force = 0.1, focus = 0.1, spread = -0.06, range = -0.02, lifetime = 0.12 },
	light = { name = "Light",  color = { 255, 240, 150 }, condensed = "beam",
	          force = 0.02, focus = 0.16, spread = 0.04, range = 0.16, lifetime = 0.02 },
	-- sigils of their own (Sigils Explained: Crystalize, Smoke, Flickering Light, Lightning, Aeriforms, Sand,
	-- Unburning Flames)
	crystal   = { name = "Crystal",         color = { 170, 210, 255 }, condensed = "ice",
	              force = 0.14, focus = 0.12, spread = 0.02, range = 0.04, lifetime = 0.1 },
	smoke     = { name = "Smoke",           color = { 150, 150, 160 },
	              force = -0.05, focus = -0.1, spread = 0.2, range = 0.0, lifetime = 0.2 },
	thunder   = { name = "Lightning",       color = { 255, 235, 80 }, condensed = "ball_lightning",
	              force = 0.18, focus = 0.1, spread = 0.02, range = 0.2, lifetime = -0.05 },
	flicker   = { name = "Flickering Light", color = { 255, 150, 230 },
	              force = 0.04, focus = -0.1, spread = 0.2, range = 0.06, lifetime = 0.0 },
	air       = { name = "Air",             color = { 200, 240, 255 },
	              force = 0.0, focus = 0.0, spread = 0.14, range = 0.06, lifetime = 0.16 },
	sand      = { name = "Sand",            color = { 225, 190, 120 }, condensed = "stone",
	              force = 0.08, focus = 0.04, spread = 0.0, range = -0.02, lifetime = 0.14 },
	phantasm  = { name = "Phantasmal Flame", color = { 140, 190, 255 },
	              force = -0.1, focus = 0.0, spread = 0.06, range = 0.04, lifetime = 0.3 },
	-- condensed variants
	plasma = { name = "Plasma", color = { 255, 90, 160 } },
	ice    = { name = "Ice",    color = { 150, 225, 255 } },
	vacuum = { name = "Vacuum", color = { 190, 90, 255 } },
	stone  = { name = "Stone",  color = { 150, 140, 130 } },
	beam   = { name = "Beam",   color = { 255, 255, 220 } },
	-- a closed ring with nothing inside
	shockwave = { name = "Shockwave", color = { 230, 200, 120 } },
	-- mixes: two different sigils in one ring (DICTIONARY_MIXES); their parameters are the average of
	-- both elements'
	steam     = { name = "Steam",             color = { 220, 230, 240 }, condensed = "steamblast" },
	firestorm = { name = "Hot Wind",          color = { 255, 150, 60 } },
	lava      = { name = "Lava",              color = { 255, 80, 20 } },
	sunfire   = { name = "Sunfire",           color = { 255, 210, 90 } },
	storm     = { name = "Spray",             color = { 110, 170, 230 } },
	mud       = { name = "Mud",               color = { 120, 90, 60 } },
	shimmer   = { name = "Shimmering Water",  color = { 180, 240, 255 } },
	sandstorm = { name = "Sandstorm",         color = { 220, 190, 120 } },
	steamblast     = { name = "Steam Blast",    color = { 240, 240, 250 } },
	ball_lightning = { name = "Ball Lightning", color = { 255, 245, 150 } },
	frost     = { name = "Frost",             color = { 200, 235, 255 } },
	smog      = { name = "Smog",              color = { 120, 110, 100 } },
	fireworks = { name = "Fireworks",         color = { 255, 170, 90 } },
}
-- the element sigils, in the order mixes name them
DICTIONARY_SIGIL_ORDER = { "fire", "water", "wind", "earth", "light", "crystal", "smoke", "thunder", "flicker", "air", "sand", "phantasm" }

-- Two different element sigils in one ring mix into a third element. Keys: the two elements in
-- DICTIONARY_SIGIL_ORDER order. Convergence then compresses a mix that has a condensed variant (steam,
-- lightning, crystal); the others only take its parameters. Pairs that aren't here: the bigger sigil leads
-- and the other one only lends its parameters.
DICTIONARY_MIXES = {
	["fire+water"] = "steam",   ["fire+wind"] = "firestorm", ["fire+earth"] = "lava",   ["fire+light"] = "sunfire",
	["water+wind"] = "storm",   ["water+earth"] = "mud",     ["water+light"] = "shimmer",
	["wind+earth"] = "sandstorm", ["wind+light"] = "thunder",
	["earth+light"] = "crystal",
	["water+crystal"] = "ice",  ["wind+crystal"] = "frost",  ["fire+smoke"] = "smog",   ["fire+flicker"] = "fireworks",
	["light+flicker"] = "fireworks", ["wind+sand"] = "sandstorm", ["water+sand"] = "mud", ["fire+sand"] = "lava",
	["wind+smoke"] = "smoke",   ["water+thunder"] = "storm", ["wind+air"] = "air",
}

-- Every symbol that can stand in the center (templates.lua TEMPLATES_SIGILS): what it gives the spell.
--   element: the element it adds (element sigils)
--   manifest: a way of manifesting of its own (cast.lua MANIFESTS), e.g. the Sigil of Wind Underfoot lifts
--        the caster, Whorling Wind makes a whirlwind
--   shape: a decorative sigil - the spell takes the creature's shape (a sculpture)
--   hint: in the book's legend
DICTIONARY_SIGILS = {
	fire = { element = "fire" }, water = { element = "water" }, wind = { element = "wind" }, earth = { element = "earth" },
	light = { element = "light" },
	crystal   = { element = "crystal", name = "Crystalize", hint = "ice and crystal" },
	smoke     = { element = "smoke", name = "Smoke", hint = "smokescreen" },
	lightning = { element = "thunder", name = "Lightning", hint = "electricity" },
	flicker   = { element = "flicker", name = "Flickering Light", hint = "fireworks" },
	aeriforms = { element = "air", manifest = "bubble", name = "Aeriforms", hint = "air bubble" },
	sand      = { element = "sand", name = "Sand", hint = "sand" },
	unburning = { element = "phantasm", name = "Unburning Flames", hint = "cold fire" },
	underfoot = { element = "wind", manifest = "sylph", name = "Wind Underfoot", hint = "flight" },
	whorl     = { element = "wind", manifest = "whirlwind", name = "Whorling Wind", hint = "whirlwind" },
	repetition = { manifest = "repeat", name = "Repetition", hint = "repeats" },
	guidance  = { manifest = "beacon", name = "Guidance", hint = "beacon" },
	calling   = { manifest = "lure", name = "Calling", hint = "lure" },
	purification = { element = "water", behavior = "purify", name = "Purification", hint = "clean water" },
	sword     = { manifest = "blade", name = "Sword", hint = "blade" },
	bridging  = { manifest = "bridge", name = "Bridging", hint = "bridge" },
	undulation = { manifest = "wave", name = "Undulation", hint = "wave" },
	obliviation = { manifest = "oblivion", name = "Obliviation", hint = "forbidden", forbidden = true },
	concealment = { manifest = "shadow", name = "Concealment", hint = "invisibility" },
	billow    = { manifest = "cloud", name = "Billow", hint = "cloud" },
	selection = { manifest = "book", name = "Selection", hint = "on oneself" },
	-- decorative sigils (Decorative Sigils): the spell takes the creature's shape and moves like it
	dragon = { shape = "dragon", name = "Dragon", hint = "sculpture" },
	horse  = { shape = "horse",  name = "Horse",  hint = "sculpture" },
	bird   = { shape = "bird",   name = "Bird",   hint = "sculpture" },
	fish   = { shape = "fish",   name = "Fish",   hint = "sculpture" },
	owlcat = { shape = "owlcat", name = "Owlcat", hint = "sculpture" },
	leech  = { shape = "leech",  name = "Valance Leech", hint = "sculpture" },
	scalewolf = { shape = "scalewolf", name = "Scalewolf", hint = "sculpture" },
	torchstag = { shape = "torchstag", name = "Torchstag", hint = "sculpture" },
	liongoat = { shape = "liongoat", name = "Liongoat", hint = "sculpture" },
	frillram = { shape = "frillram", name = "Frillram", hint = "sculpture" },
}
-- every center symbol, in the order the recognizer and the legend take them
DICTIONARY_CENTER_ORDER = { "fire", "water", "wind", "earth", "light", "crystal", "smoke", "lightning", "flicker", "aeriforms", "sand",
	"unburning", "underfoot", "whorl", "repetition", "guidance", "calling", "purification", "sword", "bridging", "undulation",
	"obliviation", "concealment", "billow", "selection", "dragon", "horse", "bird", "fish", "owlcat", "leech",
	"scalewolf", "torchstag", "liongoat", "frillram" }

-- Signs (the wiki's Signs Explained). Their effects add up: every sign adds its parameter deltas,
-- scaled by its size, and its behavior - what it does to the spell's projectiles (cast.lua).
--   type: "directional" - points somewhere: pushes the spell towards where it points (unbalanced -> the
--         spell drifts), two or more turned sideways together spin the spell; "semi" - no direction, but drawn facing
--         outwards it acts the other way round; "none" - acts the same any way round
--   form: the carrier it votes for (a bolt, a floating orb, a burst outwards); none of them: a splash from the seal;
--         Dispersion held by a sign that keeps it (Stability, Stillness): a field round the caster (seal_spell.lua)
--   condense: pulls the element into its condensed variant
--   behavior: what it adds (DICTIONARY_BEHAVIORS); inverted: the sign drawn facing outwards
--   hint: what it does, in the book's legend
--   symmetry: how many times the sign looks the same in one turn around (1: never; 2: turned upside
--         down too - it can't be inverted; 3: a triangle - turned 60 degrees it is inverted)
--   mirror: the sign has a mirrored twin that means the other way round (the spiraling wind)
DICTIONARY_SIGNS = {
	column = {
		name = "Column", hint = "flies", type = "directional", form = "column", behavior = "thrust",
		force = 0.3, focus = 0.35, spread = -0.24, range = 0.18,
		-- inverted columns manifest sideways, outwards from the seal, like dispersion (Crystal Shard, Smoke Cloud)
		inverted = { form = "dispersion", force = 0.1, spread = 0.3, range = 0.05 },
	},
	dispersion = {
		name = "Dispersion", hint = "wave outwards", type = "semi", form = "dispersion",
		force = 0.02, focus = -0.2, spread = 0.3, range = 0.1, lifetime = 0.1,
		-- the wiki has seen both, the difference is unclear
		inverted = { form = "dispersion", focus = -0.2, spread = 0.3, range = 0.1, lifetime = 0.1 },
	},
	levitation = {
		name = "Levitation", hint = "floats", type = "directional", form = "levitation", behavior = "float",
		force = 0.12, focus = 0.02, spread = 0.08, range = 0.18, lifetime = 0.28,
		-- inverted levitation cancels levitation: the effect grows heavy
		inverted = { form = "levitation", vote = -1, heavy = 1 },
	},
	convergence = {
		name = "Convergence", hint = "compresses", type = "semi", symmetry = 3, condense = 1,
		force = 0.08, focus = 0.36, spread = -0.32, range = -0.04, lifetime = 0.08,
		-- never seen inverted: it loosens instead of compressing
		inverted = { condense = -1, focus = -0.2, spread = 0.2 },
	},
	pull = {
		name = "Pulling", hint = "pulls", type = "directional", behavior = "pull", focus = 0.05, lifetime = 0.05,
		-- the wiki: pulls when it points inwards, so pointing outwards it pushes away
		inverted = { behavior = "push", focus = 0.05, lifetime = 0.05 },
	},
	crush = {
		name = "Crushing", hint = "crushes", type = "semi", behavior = "crush", force = 0.1,
		-- the Wall Breaker crushes, the Integration seal (the same signs inverted) reforms
		inverted = { behavior = "build", lifetime = 0.1 },
	},
	pierce = {
		name = "Piercing", hint = "projectiles", type = "none", symmetry = 2, behavior = "pierce", force = 0.05, focus = 0.1, range = 0.05,
	},
	crosshair = {
		name = "Crosshair", hint = "homes in", type = "none", symmetry = 4, behavior = "homing", focus = 0.1,
	},
	expansion = {
		name = "Expansion", hint = "bigger", type = "semi", behavior = "grow", force = 0.1, lifetime = 0.05,
		inverted = { behavior = "shrink", range = 0.1 },
	},
	stability = {
		name = "Stability", hint = "hangs still", type = "none", symmetry = 2, behavior = "still", lifetime = 0.2,
	},
	-- signs of the wiki's other spells (Signs Explained)
	regions = {
		name = "Regions", hint = "where it appears", type = "directional", behavior = "regions", focus = 0.08, range = 0.06,
		-- pointing outwards the magic manifests outside the ring; alone it launches (Bird of Light Beacon)
		inverted = { behavior = "regions", spread = 0.12 },
	},
	sights = { name = "Sights Set", hint = "to the aim point", type = "none", invertible = false, behavior = "aim", focus = 0.2, range = 0.1 },
	strengthen = { name = "Strengthening", hint = "stronger", type = "none", invertible = false, behavior = "strong", force = 0.3, lifetime = 0.1 },
	entwine = { name = "Entwining", hint = "binds", type = "none", symmetry = 2, behavior = "bind", lifetime = 0.05 },
	detection = { name = "Detection", hint = "seeks enemies", type = "none", invertible = false, behavior = "sense", focus = 0.1, range = 0.05 },
	partition = { name = "Partition", hint = "bounds", type = "none", invertible = false, behavior = "bound", focus = 0.1, lifetime = 0.15 },
	refuse = { name = "Refuse", hint = "gathers filth", type = "none", invertible = false, behavior = "refuse" },
	solidify = { name = "Solidification", hint = "hardens", type = "none", symmetry = 2, behavior = "solid", lifetime = 0.1 },
	binding = { name = "Binding", hint = "holds", type = "semi", behavior = "hold", lifetime = 0.15,
		inverted = { behavior = "hold", lifetime = 0.15 } },
	envelop = { name = "Envelopment", hint = "envelops the target", type = "none", invertible = false, behavior = "envelop", spread = 0.1 },
	immobility = { name = "Immobility", hint = "freezes", type = "semi", behavior = "hold", lifetime = 0.2,
		inverted = { behavior = "hold", lifetime = 0.2 } },
	pointing = { name = "Pointing", hint = "pointed", type = "none", invertible = false, behavior = "point", focus = 0.15, range = 0.1 },
	mimicry = { name = "Mimicry", hint = "follows the cursor", type = "semi", behavior = "mimic",
		inverted = { behavior = "mimic" } },
	collection = { name = "Collection", hint = "collects matter", type = "semi", behavior = "gather",
		inverted = { behavior = "scatter", spread = 0.2 } },
	gathering = { name = "Gathering", hint = "draws in matter", type = "semi", behavior = "gather",
		inverted = { behavior = "scatter", spread = 0.2 } },
	-- the wiki doesn't know what it does: it is read, and does nothing
	diamond = { name = "Diamond", hint = "meaning unknown", type = "none", symmetry = 4 },
	-- the Water Orb: a sphere over the seal where the spell's material collects
	orb = { name = "Orb", hint = "container", type = "none", symmetry = 2, form = "levitation", behavior = "contain", lifetime = 0.2 },
	purify = { name = "Purification", hint = "purifies", type = "none", invertible = false, behavior = "purify" },
	link = { name = "Link", hint = "in a chain", type = "none", invertible = false, behavior = "link" },
	stillness = { name = "Stillness", hint = "keeps in place", type = "semi", behavior = "still", lifetime = 0.3,
		inverted = { behavior = "still", lifetime = 0.3 } },
	projection = { name = "Projection", hint = "at the target", type = "semi", behavior = "project", range = 0.1,
		inverted = { behavior = "project", range = 0.1 } },
	cooling = { name = "Cooling", hint = "cold", type = "none", symmetry = 2, behavior = "cool" },
	coil = { name = "Coil", hint = "softens", type = "none", symmetry = 2, behavior = "soften" },
	reflection = { name = "Reflection", hint = "reflects", type = "none", symmetry = 2, behavior = "reflect" },
	windsign = { name = "Spiraling Wind", hint = "spins", type = "none", invertible = false, mirror = true, behavior = "whirl" },
	aeriform = { name = "Aeriforms Defined", hint = "gust", type = "semi", behavior = "gust", range = 0.08,
		inverted = { behavior = "gust", range = 0.08 } },
}
DICTIONARY_SIGN_ORDER = { "column", "dispersion", "levitation", "convergence", "pull", "crush", "pierce", "crosshair",
	"expansion", "stability", "regions", "sights", "strengthen", "entwine", "detection", "partition", "refuse", "solidify",
	"binding", "envelop", "immobility", "pointing", "mimicry", "collection", "gathering", "diamond", "orb", "purify", "link",
	"stillness", "projection", "cooling", "coil", "reflection", "windsign", "aeriform" }
-- the signs the first pages of the book explain; the others are in the wiki's pages of the book
DICTIONARY_BASIC_SIGNS = { "column", "dispersion", "levitation", "convergence", "pull", "crush", "pierce", "crosshair",
	"expansion", "stability" }

-- Frames: big signs drawn around the sigil (TEMPLATES_FRAMES)
DICTIONARY_FRAMES = {
	rain     = { name = "Rain", hint = "rain over the target", form = "rain" },
	rainward = { name = "Inverted Rain", hint = "rain dome", manifest = "umbrella" },
	holding  = { name = "Holding", hint = "keeps its shape", manifest = "wand" },
	weave    = { name = "Stretch", hint = "ribbon", manifest = "ribbon" },
	dancing  = { name = "Dancing Puppets", hint = "decoy puppet", manifest = "puppet" },
	flower   = { name = "Flower", hint = "flowers", manifest = "bloom" },
}

-- How the ways of manifesting of their own (manifest.lua) are named in a spell's summary
MANIFEST_NAMES = {
	warmth = "warmth around", phantasm = "cold flame", snowfend = "warm dome", lamp = "lamp on a wall bracket",
	glowpath = "stones light underfoot", beacon_pillar = "pillar of light", tracer = "threads between linked items", tracking = "marks to treasures",
	floatglow = "flying lantern", light_beam = "upward beam of light", light_bird = "bird of light", light_leech = "decorative light leech",
	beacon = "guiding mark", bloom = "flowers", carousel = "carousel of lights", amplify = "strengthens seals",
	dragon_water = "water dragon", dragon_steam = "steam dragon", water_pour = "water pours from the book", water_rose = "growing rose of water", purify = "purifies foul liquid", integration = "sand sets into stone", geyser = "geyser underfoot", wave_ride = "wave carries",
	disc = "water disc", whirlpool = "whirlpool", water_cage = "water cage", vapor = "ball of clean water",
	dry = "dries", boil = "boils away", wash_spring = "cleansing around", wave = "wave", guidance_fish = "fish to the mark",
	chalice = "liquid in the air", mist = "mist", wand = "water pen", stone_wall = "stone wall",
	sand_cage = "sand cage", lift = "earth lift", bridge = "bridge", ribbon = "ribbon bridge", cloud = "cloud",
	sand_cloud = "cloud of sand", sandcastle = "sandcastle", stone_arm = "stone arm", spikes = "stone spikes",
	wallward = "hollow in the wall", ice_road = "icy road", sylph = "flight", pegasus = "long flight",
	skysoar = "wind dash", levitate = "levitation", book = "flying book", chair = "walking chair", gale = "steady wind",
	wind_wall = "wind wall", whirlwind = "whirlwind", bubble = "air bubble", umbrella = "rain dome",
	guidance_items = "draws items in", ["repeat"] = "repeats a seal", capture = "capture ribbon", lockwax = "lockwax",
	cookpot = "flask out of time", washbarrel = "water whirl", makeover = "sparkle",
	reduction = "shrinks", counterclock = "time runs back", counterclock_creatures = "time runs back for creatures", time_stop = "time stop",
	warmth_zone = "steady warmth", disguise = "beast's guise", scry = "far sight", shadow = "shadow", smoke_cloak = "cloak of smoke",
	smoke_copies = "smoke copies", smoke_clone = "smoke double", smoke_fairy = "smoke sprite", puppet = "decoy puppet",
	lure = "calling pouch", remote_cloak = "Sasaran's cloak", mirror = "mirror sphere", shade = "eye shield",
	xray = "through walls", walk_liquid = "walks on water", beastward = "wards off beasts", beastward_strong = "wards off beasts",
	forbidden_fire = "unquenchable flame", portal = "window", portal_small = "windows for projectiles", doorknob = "door back",
	petrify = "petrification", labyrinth = "closed space", oblivion = "obliviation", heal = "healing",
	golem = "golem", wolf_curse = "wolf curse", unpolymorph = "undoes transformation",
	slime = "into slime", blade = "blade", sculpture = "sculpture", spiraling_flame = "spiraling flame",
	pyreball = "floating bonfire", flame_shot = "flame column", flame_burst = "fire ring and blast", ring_of_fire = "ring of flame",
}

DICTIONARY_FRAME_ORDER = { "rain", "rainward", "holding", "weave", "dancing", "flower" }

-- What signs add to the spell's projectiles, in the order cast.lua applies them. The pierce count is
-- the number of signs, spin comes from signs turned sideways (seal_spell.lua), the others weigh by the
-- signs' size.
--   text: names it in the spell's summary (thrust and float show as the form); text_<carrier>: on
--         that carrier
--   carriers: what it works on (the Carriers below); elsewhere the sign does nothing
--   opposite: the inverted sign's behavior: a seal with both keeps only the difference (the wiki: a
--         spell and the same spell inverted cancel out)
-- Carriers: bolt - a shot, orb - a floating sphere, hover - a sphere hanging in place, nova - a wave out
-- from the seal, cloud - hangs over the target, ring - a ring around the caster, field - around the caster
-- (or, aimed with a crosshair, at the target). tests/test_sign_effects.py casts every pair: a sign listed for a
-- carrier changes what it makes, the others are left out of the spell.
local FLYING = { bolt = true, orb = true }
local MOVING = { bolt = true, orb = true, hover = true }
local ALL = { bolt = true, orb = true, hover = true, nova = true, cloud = true, ring = true, field = true }
-- what creatures and the ground meet: all but the ring of lights round the caster
local BODIES = { bolt = true, orb = true, hover = true, nova = true, cloud = true, field = true }
-- what ends somewhere, spilling what it gathered or setting there
local ENDING = { bolt = true, orb = true, hover = true, cloud = true, field = true }
-- what finds its target: a shot steers, a wave and a field appear there, a cloud drifts after enemies
local SEEKING = { bolt = true, orb = true, nova = true, cloud = true, field = true }
local PLACED = { bolt = true, orb = true, nova = true, field = true }
DICTIONARY_BEHAVIORS = {
	{ key = "thrust", carriers = FLYING },
	{ key = "float", carriers = FLYING },
	{ key = "pierce", text = "pierces", text_ring = "more lights", carriers = { bolt = true, orb = true, ring = true } },
	{ key = "homing", text = "homing", text_field = "at the target", text_nova = "at the target", text_cloud = "follows enemies",
		carriers = SEEKING },
	{ key = "aim", text = "to the aim point", carriers = PLACED },
	{ key = "sense", text = "seeks enemies", text_field = "at the nearest enemy", text_nova = "at the nearest enemy",
		text_cloud = "over the nearest enemy", carriers = SEEKING },
	{ key = "mimic", text = "follows the cursor", carriers = MOVING },
	{ key = "pull", text = "pulls", text_nova = "rushes in", carriers = BODIES, opposite = "push" },
	{ key = "push", text = "pushes away", carriers = BODIES },
	{ key = "gust", text = "gust of wind", carriers = BODIES },
	{ key = "crush", text = "crushes rock", carriers = BODIES, opposite = "build" },
	{ key = "build", text = "binds sand", carriers = BODIES },
	{ key = "soften", text = "softens rock", carriers = BODIES },
	{ key = "grow", text = "big", carriers = ALL, opposite = "shrink" },
	{ key = "shrink", text = "small", carriers = ALL },
	{ key = "strong", text = "strengthened", carriers = ALL },
	{ key = "point", text = "sharp", carriers = FLYING },
	{ key = "spin", text = "spins", carriers = FLYING },
	{ key = "whirl", text = "whirls", carriers = FLYING },
	{ key = "still", text = "hangs still", text_ring = "lasts longer", carriers = { bolt = true, orb = true, ring = true } },
	{ key = "hold", text = "holds", carriers = BODIES },
	{ key = "bind", text = "binds", carriers = BODIES },
	{ key = "envelop", text = "envelops the target", carriers = FLYING },
	{ key = "link", text = "in a chain", carriers = FLYING },
	{ key = "gather", text = "gathers matter", carriers = ENDING, opposite = "scatter" },
	-- it scatters its element's matter: an element without one has nothing to scatter (seal_spell.lua)
	{ key = "scatter", text = "scatters", carriers = { bolt = true, orb = true, hover = true, cloud = true } },
	{ key = "contain", text = "holds liquid", carriers = { orb = true, hover = true } },
	{ key = "purify", text = "purifies", carriers = BODIES },
	{ key = "refuse", text = "clears filth", carriers = BODIES },
	{ key = "cool", text = "chills", carriers = BODIES },
	{ key = "solid", text = "hardens", carriers = ENDING },
	{ key = "reflect", text = "reflects projectiles", carriers = { hover = true, nova = true, field = true } },
	{ key = "project", text = "at the target", carriers = { nova = true, field = true } },
	-- the field's edge keeps creatures on their side of it: out of the circle round the caster, in the one at the target
	{ key = "bound", text = "within bounds", carriers = { field = true } },
	{ key = "launch", text = "in a dash", carriers = FLYING },
}
DICTIONARY_BEHAVIOR = {}
for _, b in ipairs( DICTIONARY_BEHAVIORS ) do DICTIONARY_BEHAVIOR[b.key] = b end

-- Signs round a seal that manifests in a way of its own (a special sigil, a frame, a decorative sigil, a wiki's seal;
-- manifest.lua): what each way takes from them - Expansion and its inverse its size, Stability and Stillness how long
-- it lasts, Piercing how many there are, Strengthening how hard it strikes, Mimicry that it follows the cursor. The
-- other signs do nothing there and are left out of the spell; a way not listed takes none. Keys: the way of
-- manifesting, or the decorative sigil's shape. tests/test_sign_effects.py checks it against manifest.lua.
local MANIFEST_SIGN_GROUPS = {
	{ "grow,shrink,still,pierce,strong,mimic", "fish" },
	{ "grow,shrink,still,pierce,strong", "frillram,horse,leech,liongoat,scalewolf,torchstag" },
	{ "grow,shrink,still,strong,mimic", "dragon,dragon_steam,dragon_water" },
	{ "grow,shrink,still,mimic", "beastward,beastward_strong,gale,labyrinth,mist,oblivion,petrify,puppet,reduction,"
		.. "snowfend,time_stop,warmth_zone,whirlpool" },
	{ "grow,shrink,still,pierce", "bird,owlcat" },
	{ "grow,shrink,still,strong", "flame_shot,pyreball,water_pour" },
	{ "grow,shrink,mimic", "boil,counterclock_creatures,dry,guidance_items,integration,purify,unpolymorph,wallward,"
		.. "wash_spring" },
	{ "grow,shrink,still", "bridge,ice_road,light_beam,light_bird,light_leech,water_cage,water_rose,wind_wall" },
	{ "grow,shrink,strong", "blade,flame_burst,ring_of_fire,spiraling_flame" },
	{ "grow,shrink", "wave" },
	{ "still,mimic", "forbidden_fire,smoke_copies,whirlwind" },
	{ "still,pierce", "carousel" },
	{ "still,strong", "golem,stone_wall" },
	{ "strong,mimic", "spikes,vapor" },
	{ "mimic", "chalice,guidance_fish,slime,wolf_curse" },
	{ "still", "beacon,beacon_pillar,bloom,book,bubble,capture,chair,cloud,cookpot,disc,disguise,floatglow,glowpath,"
		.. "lamp,levitate,lift,lockwax,lure,mirror,pegasus,phantasm,portal,portal_small,remote_cloak,ribbon,"
		.. "sand_cage,sand_cloud,sandcastle,shade,shadow,smoke_cloak,smoke_clone,smoke_fairy,stone_arm,sylph,"
		.. "tracer,tracking,umbrella,walk_liquid,wand,warmth,xray" },
}
DICTIONARY_MANIFEST_SIGNS = {}
for _, group in ipairs( MANIFEST_SIGN_GROUPS ) do
	for key in group[2]:gmatch( "[%w_]+" ) do
		DICTIONARY_MANIFEST_SIGNS[key] = {}
		for sign in group[1]:gmatch( "%w+" ) do DICTIONARY_MANIFEST_SIGNS[key][sign] = true end
	end
end

-- Does the behavior work on the carrier, or (given) on that way of manifesting of its own?
function dictionary_behavior_works( key, carrier, manifest )
	if manifest then return ( DICTIONARY_MANIFEST_SIGNS[manifest] or {} )[key] == true end
	local b = DICTIONARY_BEHAVIOR[key]
	return b ~= nil and b.carriers[carrier] == true
end

-- The carriers' own numbers before a seal tunes them (carriers.lua builds them, spell_notes.lua tells them): a shot's
-- and an orb's life (frames), a field's radius, life, damage (a share of its element's main damage) and how often it
-- strikes (frames); a splash's drops: their life, the share of a shot's damage each deals, the share of the seal's
-- lifetime and range they take (they stay by the seal), how many and how wide they fan out (degrees)
DICTIONARY_CARRIER_BASE = { bolt_lifetime = 90, orb_lifetime = 240, field_radius = 32, field_lifetime = 180, field_damage = 0.25,
	field_every = 10, splash_lifetime = 14, splash_damage = 0.35, splash_reach = 0.25, splash_drops = 3, splash_pattern = 40 }

DICTIONARY_FORMS = { burst = "splash", column = "column", dispersion = "wave outwards", levitation = "floats", rain = "rain",
	ring = "in a ring", field = "circle around" }

-- How elements manifest. Each element has a look: its own projectiles are built from it by init.lua
-- (carriers.lua, templates in entities/templates) - a bolt for the column, a slow floating orb for
-- levitation, a splash of a few short drops for a seal without a sign of form, a field around the caster for
-- Dispersion held still, a wave out from the seal for dispersion and a cloud over the target for the Sign of Rain.
--   material  - what it is made of and leaves behind (real particles); nil: none
--   spark     - cosmetic sparks in its color
--   damage    - damage by type, as ProjectileComponent.damage_by_type (1 = 25 hp)
--   status    - game effect on hit (data/entities/misc/*.xml)
--   explode   - blast radius on hit, 0: none; hole: it digs
--   speed, gravity, knockback, splash (material particles on hit)
--   rain      - what the cloud of this element drops (a material or, for elements without one, a projectile)
local EFFECT = "data/entities/misc/"
DICTIONARY_LOOKS = {
	fire   = { material = "fire", spark = "spark_red_bright", damage = { fire = 0.4 }, status = EFFECT .. "effect_apply_on_fire.xml",
	           explode = 12, speed = 170, gravity = 100, splash = 20 },
	water  = { material = "water", spark = "spark_blue", damage = { projectile = 0.2 }, status = EFFECT .. "effect_apply_wet.xml",
	           speed = 200, gravity = 200, splash = 60 },
	wind   = { spark = "spark_white", damage = { projectile = 0.15 }, knockback = 80, speed = 320, gravity = 0 },
	earth  = { material = "sand", spark = "spark", damage = { projectile = 0.5 }, knockback = 20, speed = 150, gravity = 350, splash = 60 },
	light  = { spark = "spark_yellow", damage = { projectile = 0.25 }, status = EFFECT .. "effect_blindness.xml", speed = 380, gravity = 0 },
	plasma = { material = "fire", spark = "spark_purple_bright", damage = { fire = 0.9 }, status = EFFECT .. "effect_apply_on_fire.xml",
	           explode = 24, hole = true, speed = 200, gravity = 50, splash = 30 },
	ice    = { material = "blood_cold", spark = "spark_teal", damage = { ice = 0.6 }, status = EFFECT .. "effect_frozen_short.xml",
	           speed = 180, gravity = 150, splash = 30 },
	stone  = { material = "sand", spark = "spark", damage = { projectile = 1.1, slice = 0.2 }, knockback = 40, explode = 8, hole = true,
	           speed = 140, gravity = 400, splash = 40 },
	steam  = { material = "steam", spark = "spark_white", damage = { fire = 0.15 }, status = EFFECT .. "effect_apply_wet.xml",
	           speed = 160, gravity = -30, splash = 60 },
	steamblast = { material = "steam", spark = "spark_white_bright", damage = { explosion = 0.4 }, explode = 32, hole = true,
	           speed = 150, gravity = 50, splash = 80 },
	firestorm = { material = "fire", spark = "spark_red_bright", damage = { fire = 0.3 }, status = EFFECT .. "effect_apply_on_fire.xml",
	           knockback = 70, speed = 280, gravity = 0, splash = 10 },
	lava   = { material = "lava", spark = "spark_red", damage = { fire = 0.5 }, status = EFFECT .. "effect_apply_on_fire.xml",
	           speed = 140, gravity = 300, splash = 40 },
	sunfire = { material = "fire", spark = "spark_yellow", damage = { fire = 0.45 }, status = EFFECT .. "effect_blindness.xml",
	           explode = 16, speed = 300, gravity = 0, splash = 15 },
	storm  = { material = "water", spark = "spark_blue_dark", damage = { projectile = 0.3 }, status = EFFECT .. "effect_apply_wet.xml",
	           knockback = 80, speed = 260, gravity = 100, splash = 80 },
	mud    = { material = "mud", spark = "spark", damage = { projectile = 0.35 }, speed = 150, gravity = 300, splash = 60 },
	shimmer = { material = "magic_liquid_invisibility", spark = "spark_teal", damage = { projectile = 0.1 }, speed = 200, gravity = 150, splash = 60 },
	sandstorm = { material = "sand", spark = "spark", damage = { slice = 0.3 }, knockback = 60, speed = 260, gravity = 100, splash = 60 },
	crystal = { material = "ice_static", spark = "spark_teal", damage = { slice = 0.6, ice = 0.2 }, status = EFFECT .. "effect_frozen_short.xml",
	           speed = 260, gravity = 50, splash = 12 },
	smoke  = { material = "smoke", spark = "spark_white", damage = { projectile = 0.05 }, status = EFFECT .. "effect_blindness.xml",
	           speed = 160, gravity = -20, splash = 120 },
	thunder = { spark = "spark_electric", damage = { electricity = 0.6 }, status = EFFECT .. "effect_electricity.xml", explode = 10,
	           speed = 420, gravity = 0 },
	flicker = { spark = "spark_purple_bright", damage = { fire = 0.15 }, explode = 6, speed = 240, gravity = 60 },
	fireworks = { spark = "spark_yellow", damage = { fire = 0.25 }, explode = 10, speed = 260, gravity = 60 },
	air    = { spark = "spark_white", damage = { projectile = 0.05 }, knockback = 140, speed = 300, gravity = 0 },
	sand   = { material = "sand", spark = "spark", damage = { projectile = 0.4, slice = 0.1 }, knockback = 30, speed = 180, gravity = 300, splash = 80 },
	phantasm = { spark = "spark_blue", damage = { projectile = 0.0 }, speed = 150, gravity = -10 },
	frost  = { material = "snow", spark = "spark_white", damage = { ice = 0.35 }, status = EFFECT .. "effect_frozen_short.xml", knockback = 50,
	           speed = 280, gravity = 40, splash = 40 },
	smog   = { material = "smoke", spark = "spark_red", damage = { fire = 0.2 }, status = EFFECT .. "effect_apply_on_fire.xml", speed = 170,
	           gravity = -20, splash = 80 },
}

-- Where Noita has a unique mechanic of its own, it is used instead: black holes, lasers, lightning,
-- an empty ring's shockwave. A form left out here is the element's own (the wave, the ring of lights) when it has
-- one, else the burst.
local DECK = "data/entities/projectiles/deck/"
DICTIONARY_OVERRIDES = {
	vacuum = {
		column = { file = DECK .. "black_hole.xml", text = "black hole" },
		dispersion = { file = DECK .. "projectile_gravity_field.xml", at = "self", text = "field that draws projectiles" },
		levitation = { file = DECK .. "black_hole.xml", carrier = "orb", text = "slow black hole" },
		burst = { file = DECK .. "black_hole.xml", text = "black hole" },
		rain = { file = DECK .. "black_hole.xml", at = "sky", carrier = "cloud", copies = 3, pattern = 20, text = "black holes from the sky" },
	},
	beam = {
		column = { file = DECK .. "laser.xml", text = "laser" },
		dispersion = { file = DECK .. "laser.xml", copies = 3, pattern = 30, text = "fan of three lasers" },
		levitation = { file = DECK .. "orb_laseremitter_weak.xml", carrier = "orb", text = "floating laser emitter" },
		burst = { file = DECK .. "explosion_light.xml", at = "self", text = "flash" },
		rain = { file = DECK .. "laser.xml", at = "sky", carrier = "cloud", copies = 5, pattern = 30, text = "rain of lasers" },
	},
	thunder = {
		column = { file = DECK .. "lightning.xml", text = "lightning" },
		levitation = { file = DECK .. "ball_lightning.xml", carrier = "orb", text = "ball lightning" },
		burst = { file = DECK .. "electrocution_field.xml", at = "target", carrier = "field", text = "electric field at the target" },
		rain = { file = DECK .. "cloud_thunder.xml", at = "target", carrier = "cloud", text = "thundercloud over the target" },
	},
	ball_lightning = {
		column = { file = DECK .. "ball_lightning.xml", copies = 2, pattern = 10, text = "two ball lightnings" },
		dispersion = { file = DECK .. "ball_lightning.xml", copies = 4, pattern = 60, text = "fan of ball lightnings" },
		levitation = { file = DECK .. "ball_lightning.xml", carrier = "orb", text = "ball lightning" },
		burst = { file = DECK .. "ball_lightning.xml", copies = 3, pattern = 120, text = "three ball lightnings" },
		rain = { file = DECK .. "ball_lightning.xml", at = "sky", carrier = "cloud", copies = 4, pattern = 30, text = "ball lightnings from the sky" },
	},
	shockwave = {
		burst = { carrier = "nova", at = "self", text = "shockwave from the seal" },
	},
}

local CARRIERS = "mods/witch_notebook/files/entities/carriers/"
function carrier_file( element, carrier )
	return CARRIERS .. carrier .. "_" .. element .. ".xml"
end

-- What an element does in a form: { file, carrier (the Carriers above), copies, pattern (degrees),
-- at ("self": around the caster, "target": at the cursor, default: shot from the hand), knockback, text }.
-- 'floats': levitation without columns - the sphere hangs where it was cast instead of flying.
function dictionary_effect( element, form, floats )
	local overrides = DICTIONARY_OVERRIDES[element]
	-- a ring of lights round the caster takes any element's colour (effects/orbit.lua)
	if form == "ring" and element ~= "shockwave" and DICTIONARY_ELEMENTS[element] and not ( overrides and overrides.ring ) then
		local name = DICTIONARY_ELEMENTS[element].name:lower()
		return { file = carrier_file( element, "ring" ), carrier = "ring", at = "self", text = "ring around: " .. name }
	end
	if overrides and not overrides[form] and form == "dispersion" and DICTIONARY_LOOKS[element] then overrides = nil end
	if overrides then
		local effect = overrides[form] or overrides.burst or overrides.column
		-- the game's projectiles: fly from the hand, hang at the target or stand around the caster
		effect.carrier = effect.carrier or ( effect.at == "self" and "field" ) or ( effect.at == "target" and "cloud" ) or "bolt"
		return effect
	end
	local look = DICTIONARY_LOOKS[element]
	if not look then return nil end
	local name = DICTIONARY_ELEMENTS[element].name:lower()
	if form == "column" then
		return { file = carrier_file( element, "bolt" ), carrier = "bolt", text = "projectile: " .. name }
	elseif form == "levitation" then
		if floats then
			return { file = carrier_file( element, "orb" ), carrier = "hover", at = "target", text = "orb floating in place: " .. name }
		end
		return { file = carrier_file( element, "orb" ), carrier = "orb", text = "slow floating orb: " .. name }
	elseif form == "dispersion" then
		return { file = carrier_file( element, "nova" ), carrier = "nova", at = "self", text = "wave from the seal: " .. name }
	elseif form == "rain" then
		if look.material then
			return { file = carrier_file( element, "cloud" ), carrier = "cloud", at = "target", text = "rain over the target: " .. name }
		end
		return { file = carrier_file( element, "bolt" ), carrier = "cloud", at = "sky", copies = 7, pattern = 40, text = "rain of projectiles: " .. name }
	elseif form == "field" then
		return { file = carrier_file( element, "field" ), carrier = "field", at = "self", text = "field around: " .. name }
	end
	-- a sigil without a sign of form only splashes its element from the seal, as a first seal does in the manga: a few
	-- short, weak drops - shots that stay by the seal, taking what shots take
	local base = DICTIONARY_CARRIER_BASE
	return { file = carrier_file( element, "splash" ), carrier = "bolt", splash = true, copies = base.splash_drops,
		pattern = base.splash_pattern, text = "splash: " .. name }
end
