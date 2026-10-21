-- Taking back what was done to a page (notebook.lua): before each line drawn, each erasing, each marking and Clear, the
-- page's lines as they were are kept - the last ones, while the game runs (not with the run's save). Undo (the button
-- under Mark, Ctrl+Z) puts them back: notebook.lua chooses the page on view changed last; a seal that awoke from that
-- change opens again as a draft with it.
--   BookUndo.remember( page )  before 'page' changes
--   BookUndo.take( page )      its lines as they were before its last change, taken off its list (nil: none)
--   BookUndo.last( page )      when it changed last (0: nothing to take back) ...
--   BookUndo.now()             ... on the same clock: when a seal awoke

BookUndo = {}
local U = BookUndo

local STEPS = 40 -- changes kept a page
local clock = 0  -- counts the changes on every page, to tell which page changed last

function U.now()
	clock = clock + 1
	return clock
end

-- The lines are copies holding the same points (a stroke's ink and mark kept as they are now); the points erased since are
-- whole again when they are put back
function U.remember( page )
	local list = page.undo or {}
	page.undo = list
	local lines = {}
	for i, stroke in ipairs( page.strokes ) do
		local line = { ink = stroke.ink, mark = stroke.mark }
		for k, p in ipairs( stroke ) do line[k] = p end
		lines[i] = line
	end
	list[#list + 1] = { strokes = lines, at = U.now() }
	if #list > STEPS then table.remove( list, 1 ) end
end

function U.last( page )
	local list = page.undo
	return list and #list > 0 and list[#list].at or 0
end

function U.take( page )
	local last = page.undo and table.remove( page.undo )
	if not last then return nil end
	for _, stroke in ipairs( last.strokes ) do
		for _, p in ipairs( stroke ) do p.erased = nil end
	end
	return last.strokes
end
