-- Reading a drawn seal without stopping the game (notebook.lua). A reading (seal_spell.lua read_spell) takes a few tenths
-- of a second, more than a second for a drawing of many lines: here it is a coroutine that goes on a share of each
-- frame - recognizer.lua recognizer_pause lets the frame go on - while the book stays open to drawing, erasing, marking
-- and turning its pages. One coroutine is under way at a time: the readings share what they make (seal.lua's templates,
-- seal_canon.lua's clouds), so one given up is never resumed - it starts over.
--   BookReading.read( st, page )     the drawing on 'page' (a draft of the book 'st') is read, after those waiting
--   BookReading.step( open )         every frame: what is being read goes on for the frame's share; a reading done is told
--                                    to BookReading.on_read (notebook.lua): the page awakens, or tells what is wrong
--   BookReading.reading( page )      whether the drawing on 'page', as it is, waits to be read or is being read
--   BookReading.parts( seal, data )  a drawn seal's parts for the mouse over it (notebook.lua draw_parts), nil till read
--   BookReading.look( page )         what tells if a page's lines changed
-- A reading goes on with the drawing as it was when the reading began; the page's lines changed, it is given up (the book
-- reads the page again, notebook.lua). It goes on with the book shut or another one open. A page waiting to be read keeps
-- 'reading' with the run (book_store.lua): left so when the game was saved, it is read as its book opens.

BookReading = {}
local R = BookReading

local SLICE_OPEN = 0.008  -- seconds of a frame the reading takes with the book open ...
local SLICE_SHUT = 0.004  -- ... and with it shut: the game goes on around the witch
local CHECK_EVERY = 8     -- the clock is looked at every this many templates matched (one is some 20 microseconds) ...
local MOST_WORK = 500     -- ... and a frame goes on after this many, whatever the clock says
local DEBUG_HISTORY = 10  -- recent drawings kept for offline debugging (R.record)
local DOUBT_READINGS = 2  -- a symbol the seal fails on: what it looks most like, told by it (read_done)

-- a reading done: 'job' { st, page, index }, the page as it was read (a draft, still the book's page 'index');
-- 'out' { spell, err, seal, tree, parts, state } (seal_spell.lua read_spell, awaken.lua awaken_new)
R.on_read = function( job, out ) end

local queue = {} -- the pages to read in turn: { st, page, look, strokes, of, run, co }; the first one is under way
local warm       -- what every reading uses, made in the background before the first one (R.prepare); false: made
local side       -- a drawn seal's parts, read for the mouse over it while nothing else is (R.parts)
local running    -- the job whose coroutine is under way
local slice_end, work, next_check = 0, 0, 0

-- the game's clock in seconds; the offline tests have none: a reading there runs through at once
local function clock()
	local now = GameGetRealWorldTimeSinceStarted
	return type( now ) == "function" and now() or nil
end

-- recognizer_pause while a job goes on: 'weight' - the work done since, in templates matched
local function pause( weight )
	work = work + ( weight or 1 )
	if work < next_check then return end
	next_check = work + CHECK_EVERY
	if work >= MOST_WORK or GameGetRealWorldTimeSinceStarted() >= slice_end then coroutine.yield() end
end

-- a page's lines, how many and their marks: what tells if they changed
function R.look( page )
	return #page.strokes .. "|" .. ( page.point_count or 0 ) .. "|" .. strokes_encode_marks( page.strokes )
end

-- the drawing's lines as they are, for a reading to go on with while the page is drawn on; 'of': the page's line of each
local function copy_lines( strokes )
	local list, of = {}, {}
	for i, stroke in ipairs( strokes ) do
		local line = { ink = stroke.ink, mark = stroke.mark }
		for k, p in ipairs( stroke ) do line[k] = p end
		list[i], of[line] = line, stroke
	end
	return list, of
end

-- where 'page' lies among its book's pages while it is a draft there (not awoken, put back as it was or torn out)
local function index_of( st, page )
	if page.draft ~= "1" then return nil end
	for i, seal in ipairs( st.seals ) do
		if seal == page then return i end
	end
end

-- a reading of the page as it is now
local function current( job )
	return index_of( job.st, job.page ) ~= nil and R.look( job.page ) == job.look
end

-- the page no longer waits to be read: the run keeps it so
local function done_waiting( job )
	local page = job.page
	if page.reading ~= "1" then return end
	page.reading = ""
	for i, seal in ipairs( job.st.seals ) do
		if seal == page then GlobalsSetValue( BookStore.seal_var( job.st, i, "reading" ), "" ) end
	end
end

---- a page's reading ----

-- a wiki's seal too great for the book's pages: why it doesn't awaken
local function too_great( st, spell )
	local entry = spell and spell.named and GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[spell.named]
	local need = entry and seal_book( entry )
	if need and not book_holds( st.key, need ) then
		return "Too great for the " .. st.def.name .. ": " .. book_named( need ) .. " holds it"
	end
end

-- where an angle on the page points (radians, 0: right, y down), in words
local DIRECTIONS = { "on the right", "at the bottom right", "at the bottom", "at the bottom left", "on the left", "at the top left",
	"at the top", "at the top right" }
local function direction_name( angle )
	return DIRECTIONS[math.floor( angle / ( math.pi / 4 ) + 0.5 ) % 8 + 1]
end

-- One of the wiki's seals is known at a glance, as a whole (and casts as the wiki's spell); any other seal is read
-- symbol by symbol (seal_spell.lua). A spell's tree tells its parts (notebook.lua draw_parts; a wiki's seal as its pages
-- are told) and lights it up as it awakens.
local function read_lines( job )
	local strokes = job.strokes
	local spell, err, seal = read_spell( strokes )
	err = too_great( job.st, spell ) or err
	if err and spell then spell = nil end
	local out = { spell = spell, err = err, seal = seal }
	if spell then
		local tree = seal or parse_seal( strokes )
		local entry = spell.named and GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[spell.named]
		if tree then out.parts = entry and seal_parts( strokes, tree, entry ) or tree.symbols end
		out.tree, out.state = tree, awaken_new( strokes, tree, spell.element )
	elseif seal and seal.doubt then
		-- failed on one symbol the witch could mark: the two readings it looks most like, as "Mark" offers them
		out.doubt = seal_mark_readings( strokes, seal.doubt, DOUBT_READINGS )
	end
	return out
end

-- Every drawing read is kept in the run's globals, which the game saves in world_state.xml (Save & Quit):
-- python tests/debug_sigil.py reads them back and explains the recognition
function R.record( st, page, text )
	local n = ( tonumber( GlobalsGetValue( "witch_notebook.debug_next", "0" ) ) or 0 ) + 1
	GlobalsSetValue( "witch_notebook.debug_next", tostring( n ) )
	local data = "n=" .. n .. ";frame=" .. GameGetFrameNum() .. ";book=" .. st.key .. ";result=" .. text .. ";strokes=" .. strokes_encode( page.strokes )
	-- what the witch marked lines as: the book's misreadings, told by the player
	local marks = strokes_encode_marks( page.strokes )
	if marks ~= "" then data = data .. ";marks=" .. marks end
	GlobalsSetValue( "witch_notebook.debug_" .. ( ( n - 1 ) % DEBUG_HISTORY + 1 ), data )
end

-- A reading done: the strokes it couldn't read stay marked until the seal is read again; an open ring tells where its
-- gap is (its strokes are marked). A seal failing on one symbol keeps what it looks most like while its lines stay as
-- they are (page.doubt { strokes, items, look }: notebook.lua tells it under them, book_marks.lua K.draw_doubt).
local function read_done( job, out )
	local page, seal = job.page, out.seal
	for _, stroke in ipairs( page.strokes ) do stroke.trouble = nil end
	page.marked, page.doubt = nil, nil
	if not out.spell and seal and seal.trouble and #seal.trouble > 0 then
		for _, stroke in ipairs( seal.trouble ) do ( job.of[stroke] or stroke ).trouble = true end
		page.marked = true
	end
	if not out.spell and out.doubt and #out.doubt > 0 then
		local lines, all = {}, true
		for i, stroke in ipairs( seal.doubt ) do
			lines[i] = job.of[stroke]
			if not lines[i] then all = false end
		end
		if all then page.doubt = { strokes = lines, items = out.doubt, look = job.look } end
	end
	local spell = out.spell
	local said = out.fault and ( out.err .. " (" .. out.fault:gsub( "[;\r\n]+", " " ) .. ")" ) or out.err
	R.record( job.st, page, spell and ( spell.summary .. " / " .. ( spell.data or serialize_spell( spell ) ) ) or said )
	local gap = not spell and seal and seal.gap_at
	if gap then out.err = out.err .. " - its gap is " .. direction_name( gap ) end
	R.on_read( job, out )
	if not spell then done_waiting( job ) end
end

-- The drawing on 'page' of the book 'st' is read after the pages waiting; a reading of it as it was is given up
function R.read( st, page )
	local look = R.look( page )
	for k = #queue, 1, -1 do
		if queue[k].page == page then
			if queue[k].look == look then return end -- read as it is already
			table.remove( queue, k )
		end
	end
	local strokes, of = copy_lines( page.strokes )
	queue[#queue + 1] = { st = st, page = page, look = look, strokes = strokes, of = of, run = read_lines }
	page.reading = "1"
end

function R.reading( page )
	if not page then return false end
	for _, job in ipairs( queue ) do
		if job.page == page then return job.look == R.look( page ) end
	end
	return false
end

-- how many pages wait to be read (the offline tests wait for them)
function R.waiting()
	return #queue
end

-- Pages left waiting to be read when the game was saved are read as their book opens - those whose ring is still closed
function R.resume( st )
	for i, page in ipairs( st.seals ) do
		if page.reading == "1" and not R.reading( page ) then
			if page.draft == "1" and #page.strokes > 0 and seal_ring_closed( page.strokes ) then
				R.read( st, page )
			else
				page.reading = ""
				GlobalsSetValue( BookStore.seal_var( st, i, "reading" ), "" )
			end
		end
	end
end

---- in the background ----

-- What every reading uses - the templates (seal.lua), the wiki's pages as clouds (seal_canon.lua) - is made as the witch
-- comes into the world, before her first seal: the first reading would take longer
function R.prepare()
	if warm == nil then warm = { run = function() SealRead.template_sets() seal_canon_prepare() end } end
end

-- A drawn seal's parts, what the mouse over it lights: as read when it awoke (notebook.lua); a page from before (a saved
-- run) is read again, in the background - kept only if it reads as the same element, its saved points being rounded. A
-- wiki's seal drawn by hand is told the way its grimoire page is (seal.lua seal_parts).
local function read_parts( job )
	local named = job.data:match( "named=([%w_]+)" )
	local entry = named and GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[named]
	local ok, tree, _, partial = pcall( parse_seal, job.lines )
	tree = ok and ( tree or ( entry and partial ) ) or nil
	if entry then return seal_parts( job.lines, tree, entry ) end
	if tree then
		local same = compile_spell( tree )
		if same and same.element == job.data:match( "element=([%w_]+)" ) then return tree.symbols end
	end
	return {}
end

-- 'seal' of spell 'data': its parts, or nil while they are read (the last seal asked about is read)
function R.parts( seal, data )
	if seal.parts_of == seal.strokes and seal.parts_data == data then return seal.parts end
	if not side or side.seal ~= seal or side.data ~= data or side.strokes ~= seal.strokes then
		side = { seal = seal, data = data, strokes = seal.strokes, lines = ( copy_lines( seal.strokes ) ), run = read_parts }
	end
	return nil
end

---- every frame ----

-- what goes on now: the first page to read, else what readings use, else (the book open) a seal's parts
local function next_job( open )
	while queue[1] and not current( queue[1] ) do done_waiting( table.remove( queue, 1 ) ) end
	if queue[1] then return queue[1] end
	if warm then return warm end
	-- a seal opened to be drawn on, or drawn anew, since its parts were asked for: they are read when asked again
	if side and ( side.seal.draft == "1" or side.seal.strokes ~= side.strokes ) then side = nil end
	return open and side or nil
end

-- 'open': the book is open - its reading may take more of the frame
function R.step( open )
	local job = next_job( open )
	if running and running ~= job then running.co = nil end -- given up: when its turn comes again it starts over
	running = job
	if not job then return end
	job.co = job.co or coroutine.create( job.run )
	local now = clock()
	slice_end, work, next_check = ( now or 0 ) + ( open and SLICE_OPEN or SLICE_SHUT ), 0, CHECK_EVERY
	recognizer_pause = now and pause or nil
	local ok, out = coroutine.resume( job.co, job )
	recognizer_pause = nil
	if ok and coroutine.status( job.co ) ~= "dead" then return end
	running = nil
	if job == warm then
		warm = false
	elseif job == side then
		side = nil
		if ok then job.seal.parts, job.seal.parts_of, job.seal.parts_data = out, job.strokes, job.data end
	else
		table.remove( queue, 1 )
		job.index = index_of( job.st, job.page )
		-- a mistake in the reading: the page tells it, the record and the game's log what it was
		if ok then read_done( job, out ) else read_done( job, { err = "The book could not read this drawing", fault = tostring( out ) } ) end
	end
	if not ok then
		error( debug and debug.traceback and debug.traceback( job.co, tostring( out ) ) or tostring( out ), 0 )
	end
end
