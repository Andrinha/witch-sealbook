-- A book's pages as the run keeps them: in the run's globals (books.lua book_var), saved with the world. The state of
-- a book, which notebook.lua works on:
--   key, def (books.lua BOOKS), look (book_gfx.lua BOOK_LOOKS)
--   seals: the finished pages and the unfinished drafts (draft = "1"), a page each - what SEAL_FIELDS names
--   blank, blank_next: the pair of empty pages after them; edit, edit_face: the page being drawn on
--   active, active_wiki: the seal the book casts; spread, own_spread, wiki_spread: where it lies open
-- Strokes are kept as text (strokes.lua); a sheet's page keeps only its seal's key, its drawing is the grimoire's.

BookStore = {}
local S = BookStore

local SEAL_FIELDS = { "spell", "name", "quality", "color", "strokes", "inks", "sheet", "tier", "fresh", "draft" }
local shelf = {}        -- the witch's books: key -> state
local wiki_strokes = {} -- lighter copies of the grimoire's pages, made when first shown

function S.seal_var( st, i, field ) return book_var( st.key, "seal_" .. i .. "_" .. field ) end

-- a page of the grimoire, or of the Test Book (test_book.lua): its drawing in SEAL_PAGE_SIZE units
function S.entry_strokes( entry )
	return entry.test and TestBook.strokes( entry ) or grimoire_strokes( entry )
end

-- the grimoire's page (SEAL_PAGE_SIZE units), a lighter copy made when first shown
function S.wiki_page_strokes( entry )
	local cached = wiki_strokes[entry.key]
	if not cached then
		cached = strokes_even( S.entry_strokes( entry ), 1.45 )
		wiki_strokes[entry.key] = cached
	end
	return cached
end

-- An unfinished drawing stays on the page when the book is closed, and is saved with the run
function S.save_page( st )
	GlobalsSetValue( book_var( st.key, "page" ), strokes_encode( st.blank.strokes ) )
	GlobalsSetValue( book_var( st.key, "page_inks" ), strokes_encode_inks( st.blank.strokes ) )
	GlobalsSetValue( book_var( st.key, "page_failed" ), st.blank.failed and "1" or "" )
	GlobalsSetValue( book_var( st.key, "page_2" ), strokes_encode( st.blank_next.strokes ) )
	GlobalsSetValue( book_var( st.key, "page_2_inks" ), strokes_encode_inks( st.blank_next.strokes ) )
end

function S.save_seal( st, i )
	for _, field in ipairs( SEAL_FIELDS ) do
		local value = st.seals[i] and st.seals[i][field] or ""
		if field == "strokes" and st.seals[i] then value = st.seals[i].sheet ~= "" and "" or strokes_encode( value ) end
		if field == "inks" and st.seals[i] and st.seals[i].draft == "1" then value = strokes_encode_inks( st.seals[i].strokes ) end
		GlobalsSetValue( S.seal_var( st, i, field ), tostring( value ) )
	end
end

-- a pasted sheet's drawing is its grimoire page's
function S.load_seal_strokes( seal )
	local entry = seal.sheet ~= "" and GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[seal.sheet]
	if entry then
		seal.strokes = S.wiki_page_strokes( entry )
	else
		seal.strokes = strokes_apply_inks( strokes_decode( seal.strokes ), seal.inks )
	end
end

-- The book 'key' as the run has it; loaded once
function S.load( key )
	if shelf[key] then return shelf[key] end
	local st = { key = key, def = BOOKS[key], look = BOOK_LOOKS[key], seals = {} }
	st.blank = { strokes = strokes_apply_inks( strokes_decode( GlobalsGetValue( book_var( key, "page" ), "" ) ), GlobalsGetValue( book_var( key, "page_inks" ), "" ) ) }
	-- Older saves have no failure flag; a closed ring left on the blank page was a failed attempt.
	st.blank.failed = #st.blank.strokes > 0 and ( GlobalsGetValue( book_var( key, "page_failed" ), "" ) == "1" or seal_ring_closed( st.blank.strokes ) )
	st.blank.point_count = 0
	for _, stroke in ipairs( st.blank.strokes ) do st.blank.point_count = st.blank.point_count + #stroke end
	st.blank_next = { strokes = strokes_apply_inks( strokes_decode( GlobalsGetValue( book_var( key, "page_2" ), "" ) ), GlobalsGetValue( book_var( key, "page_2_inks" ), "" ) ), point_count = 0, failed = false }
	for _, stroke in ipairs( st.blank_next.strokes ) do st.blank_next.point_count = st.blank_next.point_count + #stroke end
	st.blank_next.failed = st.blank_next.point_count > 0 and seal_ring_closed( st.blank_next.strokes )
	for i = 1, tonumber( GlobalsGetValue( book_var( key, "seals" ), "0" ) ) or 0 do
		local seal = {}
		for _, field in ipairs( SEAL_FIELDS ) do seal[field] = GlobalsGetValue( S.seal_var( st, i, field ), "" ) end
		S.load_seal_strokes( seal )
		if seal.draft == "1" then
			seal.point_count = 0
			for _, stroke in ipairs( seal.strokes ) do seal.point_count = seal.point_count + #stroke end
			seal.failed = seal_ring_closed( seal.strokes )
		end
		st.seals[i] = seal
	end
	-- Unfinished pages saved with the run become a pair of drafts, leaving the next pair ready to draw on.
	if #st.blank.strokes > 0 or #st.blank_next.strokes > 0 then
		local i = #st.seals + 1
		for j, page in ipairs( { st.blank, st.blank_next } ) do
			page.draft, page.sheet = "1", ""
			st.seals[i + j - 1] = page
			S.save_seal( st, i + j - 1 )
		end
		GlobalsSetValue( book_var( key, "seals" ), tostring( i + 1 ) )
		local edited = #st.blank.strokes > 0 and i or i + 1
		st.blank = { strokes = {}, point_count = 0, failed = false }
		st.blank_next = { strokes = {}, point_count = 0, failed = false }
		GlobalsSetValue( book_var( key, "page" ), "" )
		GlobalsSetValue( book_var( key, "page_inks" ), "" )
		GlobalsSetValue( book_var( key, "page_failed" ), "" )
		GlobalsSetValue( book_var( key, "page_2" ), "" )
		GlobalsSetValue( book_var( key, "page_2_inks" ), "" )
		st.edit, st.edit_face = st.seals[edited], st.def.intro + edited
	else
		st.edit, st.edit_face = st.blank, st.def.intro + #st.seals + 1
	end
	st.active = tonumber( GlobalsGetValue( book_var( key, "active" ), "0" ) ) or 0
	st.active_wiki = GlobalsGetValue( book_var( key, "active_wiki" ), "" )
	st.spread = tonumber( GlobalsGetValue( book_var( key, "spread" ), "1" ) ) or 1
	st.own_spread, st.wiki_spread = st.spread, 1
	shelf[key] = st
	return st
end
