-- The wiki's seals (grimoire.lua): a drawing close enough to one of them is that seal. Loaded after seal.lua, which
-- reads the drawing (its ring, its symbols); seal_spell.lua makes the spell of what is found here.
--   seal_canonical( seal )  -> the wiki's seal the whole drawing looks like: key, distance, distance to the next
--   seal_name( seal )       -> the wiki's seal a read drawing is: by its shape and by its symbols
--   whole_alike / whole_sure( distance, second ) -> a drawing is a page known only as a whole / a page of signs
--   seal_middle( strokes, entry ) -> the page of a seal that takes any sigil in its middle

local find_ring, bbox, recognize_symbol, clamp = SealRead.find_ring, SealRead.bbox, SealRead.recognize_symbol, SealRead.clamp
local STRONG_SIGIL = SealRead.STRONG_SIGIL

local CANON_MATCH = 0.105    -- mean distance (share of the radius) under which a seal is the wiki's seal
-- A seal the book reads only as a whole (seal_name) must be very close in shape ...
local CANON_WHOLE = 0.058  -- mean distance (share of the radius)
local CANON_APART = 0.9    -- ... and at most this share of the distance to the next closest seal

-- The whole drawing, the ring's own strokes left out, in the ring's units (the center at 0, 0, the radius 1), two
-- ways: a few points evenly along its lines - as if all the lines were one, so a seal drawn in more strokes or fewer
-- gives the same points - and its lines as close points in a grid, to find the nearest bit of line to any point. Every
-- point knows which way its line runs there: a line crossing another isn't the same line.
-- Two drawings are compared both ways: how far, on average, the points of each are from the lines of the other.
local CANON_SAMPLES = 128   -- points taken along a seal's lines
local CANON_DENSE = 0.03    -- the lines kept as points this close (share of the radius)
local CANON_CELL = 0.15     -- grid cells: a point farther than this from the other drawing's lines counts as this far
local CANON_TURN = 0.1      -- a line turned by a radian away counts as this much farther
local CANON_REACH = 4       -- which way a line runs: from the point this many points back to this many on

local function seal_lines( strokes, ring, skip )
	local lines, total = {}, 0
	for i, stroke in ipairs( strokes ) do
		if not ( skip and skip[i] ) and #stroke > 0 then
			local xs, ys, len = {}, {}, 0
			for k, p in ipairs( stroke ) do
				xs[k], ys[k] = ( p.x - ring.x ) / ring.r, ( p.y - ring.y ) / ring.r
				if k > 1 then len = len + math.sqrt( ( xs[k] - xs[k - 1] ) ^ 2 + ( ys[k] - ys[k - 1] ) ^ 2 ) end
			end
			-- which way the line runs at each point, over a few points (a shaking hand turns single steps every way)
			local dirs = {}
			for k = 1, #xs do
				local a, b = math.max( 1, k - CANON_REACH ), math.min( #xs, k + CANON_REACH )
				dirs[k] = math.atan2( ys[b] - ys[a], xs[b] - xs[a] )
			end
			lines[#lines + 1] = { xs = xs, ys = ys, dirs = dirs, len = len }
			total = total + len
		end
	end
	return lines, total
end

-- points 'step' apart along the lines, the remainder carried from one line to the next; a line shorter than half a step
-- (a dot, a tick) is a point of its own, running every way (dir = nil)
local function sample_lines( lines, step )
	local xs, ys, dirs = {}, {}, {}
	local carry = 0
	for _, l in ipairs( lines ) do
		if l.len < step * 0.5 then
			local n = #xs + 1
			xs[n], ys[n], dirs[n] = l.xs[1], l.ys[1], false
		else
			for k = 2, #l.xs do
				local ax, ay, bx, by = l.xs[k - 1], l.ys[k - 1], l.xs[k], l.ys[k]
				local d = math.sqrt( ( bx - ax ) ^ 2 + ( by - ay ) ^ 2 )
				local t = step - carry
				while t <= d do
					local n = #xs + 1
					xs[n], ys[n], dirs[n] = ax + ( bx - ax ) * t / d, ay + ( by - ay ) * t / d, l.dirs[k]
					t = t + step
				end
				carry = d - ( t - step )
			end
		end
	end
	return { xs = xs, ys = ys, dirs = dirs, n = #xs }
end

-- the lines as points in a grid of CANON_CELL cells: cells[ix][iy] = { x, y, dir, x, y, dir, ... } (dir false: a dot)
local function line_grid( lines )
	local cells = {}
	local function put( x, y, dir )
		local ix, iy = math.floor( x / CANON_CELL ), math.floor( y / CANON_CELL )
		local column = cells[ix]
		if not column then column = {}; cells[ix] = column end
		local cell = column[iy]
		if not cell then cell = {}; column[iy] = cell end
		cell[#cell + 1] = x
		cell[#cell + 1] = y
		cell[#cell + 1] = dir
	end
	for _, l in ipairs( lines ) do
		put( l.xs[1], l.ys[1], #l.xs > 1 and l.len >= CANON_DENSE and l.dirs[1] )
		for k = 2, #l.xs do
			local ax, ay, bx, by = l.xs[k - 1], l.ys[k - 1], l.xs[k], l.ys[k]
			local d = math.sqrt( ( bx - ax ) ^ 2 + ( by - ay ) ^ 2 )
			local n = math.max( 1, math.ceil( d / CANON_DENSE ) )
			for i = 1, n do put( ax + ( bx - ax ) * i / n, ay + ( by - ay ) * i / n, l.dirs[k] ) end
		end
	end
	return cells
end

-- how far two lines' ways are apart, 0 .. pi/2 (a line has no head and tail)
local function turn_apart( a, b )
	local d = math.abs( a - b ) % math.pi
	return d > math.pi / 2 and math.pi - d or d
end

-- the distance from x, y (a line running 'dir' there) to the nearest bit of line in the grid running much the same way,
-- at most CANON_CELL
local function nearest( cells, x, y, dir )
	local ix, iy = math.floor( x / CANON_CELL ), math.floor( y / CANON_CELL )
	local best = CANON_CELL * CANON_CELL
	for cx = ix - 1, ix + 1 do
		local column = cells[cx]
		if column then
			for cy = iy - 1, iy + 1 do
				local cell = column[cy]
				if cell then
					for k = 1, #cell, 3 do
						local dx, dy = x - cell[k], y - cell[k + 1]
						local d = dx * dx + dy * dy
						if d < best then
							local other = cell[k + 2]
							if dir and other then
								local turn = turn_apart( dir, other ) * CANON_TURN
								d = d + turn * turn
							end
							if d < best then best = d end
						end
					end
				end
			end
		end
	end
	return math.sqrt( best )
end

local function seal_cloud( strokes, ring, skip )
	local lines, total = seal_lines( strokes, ring, skip )
	if #lines == 0 then return nil end
	local samples = sample_lines( lines, math.max( total / CANON_SAMPLES, 0.02 ) )
	if samples.n == 0 then return nil end
	samples.cells = line_grid( lines )
	return samples
end

-- how far the points of a (turned by 'angle', 'scale' times bigger) are from the lines of b, on average; math.huge past
-- 'bound'
local function chamfer( a, b, angle, bound, scale )
	local cos, sin = math.cos( angle ) * ( scale or 1 ), math.sin( angle ) * ( scale or 1 )
	local sum, n, cells = 0, a.n, b.cells
	local limit = bound and bound * n
	for i = 1, n do
		local x, y, dir = a.xs[i], a.ys[i], a.dirs[i]
		sum = sum + nearest( cells, x * cos - y * sin, x * sin + y * cos, dir and dir + angle )
		if limit and sum > limit then return math.huge end
	end
	return sum / n
end

-- Two pages alike but for a part (Counterclock and Valance Leech Counterclock differ only in the middle): each one's
-- own part - its points farther than CANON_OWN from the other's lines - and the drawing has one of them, the other not
local CANON_OWN = 0.06
local CANON_OWN_APART = 0.6 -- the own part of one this much nearer to the drawing's lines than the other's
local own_parts = {}

local function own_part( a, b )
	local cached = own_parts[a.key .. "/" .. b.key]
	if cached then return cached end
	local part = { xs = {}, ys = {}, dirs = {}, n = 0 }
	for i = 1, a.cloud.n do
		local x, y, dir = a.cloud.xs[i], a.cloud.ys[i], a.cloud.dirs[i]
		if nearest( b.cloud.cells, x, y, dir ) >= CANON_OWN then
			local n = part.n + 1
			part.xs[n], part.ys[n], part.dirs[n], part.n = x, y, dir, n
		end
	end
	own_parts[a.key .. "/" .. b.key] = part
	return part
end

-- which of two found pages ({ entry, d, turn }) the drawing is by their own parts, or nil when it can't be told
local function twin_choice( mine, a, b )
	local own_a, own_b = own_part( a.entry, b.entry ), own_part( b.entry, a.entry )
	if own_a.n < 4 or own_b.n < 4 then return nil end
	local near_a = chamfer( own_a, mine, -a.turn[1], nil, 1 / a.turn[2] )
	local near_b = chamfer( own_b, mine, -b.turn[1], nil, 1 / b.turn[2] )
	if near_a <= CANON_OWN_APART * near_b then return a end
	if near_b <= CANON_OWN_APART * near_a then return b end
end

local grimoire_clouds
-- a copy is turned a little and drawn a little bigger or smaller than the wiki's page: try those, as drawn first
local CANON_TRIES = { { 0, 1 }, { 0.12, 1 }, { -0.12, 1 }, { 0, 0.94 }, { 0, 1.06 }, { 0.12, 0.94 }, { 0.12, 1.06 },
	{ -0.12, 0.94 }, { -0.12, 1.06 } }
-- the book reads a drawing twice (at a glance, then sign by sign): the answer for the last one drawn
local canon_last = setmetatable( {}, { __mode = "k" } )

local function point_count( strokes )
	local n = 0
	for _, stroke in ipairs( strokes ) do n = n + #stroke end
	return n
end

-- The wiki's seal this drawing is, if any: key, distance (share of the radius)
function seal_canonical( seal )
	if not GRIMOIRE or not seal or not seal.strokes then return nil end
	if not grimoire_clouds then
		grimoire_clouds = {}
		for _, entry in ipairs( GRIMOIRE ) do
			local strokes = grimoire_strokes( entry )
			local ring, parts = find_ring( strokes )
			if ring then
				-- pages that differ only in the sigil in their middle are one seal here: seal_middle tells them apart
				local name = entry.middle and "middle:" .. tostring( entry.manifest ) or entry.name
				grimoire_clouds[#grimoire_clouds + 1] = { key = entry.key, name = name, cloud = seal_cloud( strokes, ring, parts ) }
			end
		end
	end
	local points = point_count( seal.strokes )
	local known = canon_last[seal.strokes]
	if known and known.points == points then return known[1], known[2], known[3] end
	local ring, parts = find_ring( seal.strokes )
	if not ring then return nil end
	local mine = seal_cloud( seal.strokes, ring, parts )
	if not mine or mine.n < 4 then return nil end
	-- the closest seal, the closest other one and the one after (a seal drawn twice in the wiki is the same seal)
	local found = {}
	local best_d, best_name, best_d0, second_d
	for _, entry in ipairs( grimoire_clouds ) do
		local other = entry.cloud
		if other and other.n >= 4 then
			local d_entry, d0, turn
			local bound = second_d or CANON_MATCH * 1.6
			for i, try in ipairs( CANON_TRIES ) do
				local angle, scale = try[1], try[2]
				local d1 = chamfer( mine, other, angle, bound * 2, scale )
				local d = d1 < bound * 2 and ( d1 + chamfer( other, mine, -angle, bound * 2, 1 / scale ) ) / 2 or math.huge
				if d < ( d_entry or bound ) then d_entry, turn = d, try end
				-- far off as drawn, farther than the closest one is as drawn: a little turn or size won't bring it near
				-- (as drawn against as drawn: a copy turned a little is far from every page as drawn)
				if i == 1 then
					d0 = d
					if d > 1.5 * ( best_d0 or math.huge ) then break end
				end
			end
			if d_entry then
				found[#found + 1] = { entry = entry, d = d_entry, turn = turn }
				if not best_d or d_entry < best_d then
					if best_name ~= entry.name then second_d = best_d end
					best_d, best_name, best_d0 = d_entry, entry.name, d0
				elseif entry.name ~= best_name and ( not second_d or d_entry < second_d ) then
					second_d = d_entry
				end
			end
		end
	end
	table.sort( found, function( a, b ) return a.d < b.d end )
	local first, second, third
	for _, f in ipairs( found ) do
		if not first then first = f
		elseif not second then if f.entry.name ~= first.entry.name then second = f end
		elseif f.entry.name ~= first.entry.name and f.entry.name ~= second.entry.name then third = f; break end
	end
	-- two pages alike but for a part of them, too close to tell apart as a whole: the one whose own part the drawing has
	if first and second and first.d > CANON_APART * second.d then
		local own = twin_choice( mine, first, second )
		if own then
			if own == second then first = second end
			second = third
		end
	end
	local result = { nil, nil, nil, points = points }
	if first and first.d <= CANON_MATCH then result[1], result[2], result[3] = first.entry.key, first.d, second and second.d or CANON_MATCH * 1.6 end
	canon_last[seal.strokes] = result
	return result[1], result[2], result[3]
end

-- How precise a drawing of a wiki's seal is, from how far it is from the wiki's page: a faithful copy is a clean one
function seal_canon_precision( distance )
	return clamp( 1 - 0.6 * distance / CANON_MATCH, 0.4, 1 )
end

-- A drawing the book can't read sign by sign may still be one of the wiki's seals as a whole (grimoire.lua):
-- its key, or nil
function seal_named_fallback( strokes )
	return seal_canonical( { strokes = strokes } )
end

-- Which of the wiki's seals a drawing is. The whole drawing's shape (seal_canonical) can't tell apart simple seals
-- of the same layout - a sigil with four signs around it looks like many - so a seal the book reads symbol by symbol
-- is the wiki's seal only when its symbols are that seal's symbols (the same sigils, most of the same signs); a seal
-- the book reads only as a whole (traced from the wiki: grimoire's 'symbols' is empty) must be very close in shape,
-- and much closer to it than to any other.
local SIGNS_ALIKE = 0.6    -- share of the signs in common (of all the signs of both)
local CANON_CLOSE = 0.035  -- a drawing this close in shape ...
local CANON_CLOSE_APART = 0.75 -- ... and this much closer than to any other seal ...
local SYMBOLS_LOOSE = 0.5  -- ... needs only this share of the symbols in common
local CANON_CLEAR_APART = 0.5 -- ... and none at all this much closer: the wiki draws some sigils its own way (Everflow's
                              -- water reads as wind), and a copy reads as its picture does
-- A copy of a seal of signs whose signs don't read at all (one is ambiguous or tiny, a mark lies outside the ring) is
-- that seal when it is this close in shape and this much closer to it than to any other: a seal of the book's own
-- vocabulary comes no nearer to a wiki's page than about 0.036, and it reads anyway
local CANON_SURE = 0.045
local CANON_SURE_APART = 0.75

-- a reading's symbols as a signature: "sigil:fire=1,sign:column=4" (sorted)
function seal_symbols_key( symbols )
	local counts, keys = {}, {}
	for _, s in ipairs( symbols or {} ) do
		local k = s.kind .. ":" .. s.key
		if not counts[k] then keys[#keys + 1] = k end
		counts[k] = ( counts[k] or 0 ) + 1
	end
	table.sort( keys )
	local out = {}
	for i, k in ipairs( keys ) do out[i] = k .. "=" .. counts[k] end
	return table.concat( out, "," )
end

-- How alike a reading's symbols are to a signature: the share of symbols in common, and whether the sigils are the
-- same ones
local function symbols_share( signature, symbols )
	local want, have = {}, {}
	for k, n in signature:gmatch( "([%w_:]+)=(%d+)" ) do want[k] = tonumber( n ) end
	for k, n in seal_symbols_key( symbols ):gmatch( "([%w_:]+)=(%d+)" ) do have[k] = tonumber( n ) end
	local common, all, same_sigils = 0, 0, true
	for _, list in ipairs( { want, have } ) do
		for k in pairs( list ) do
			local a, b = want[k] or 0, have[k] or 0
			if k:sub( 1, 6 ) == "sigil:" and a ~= b then same_sigils = false end
			if list == want or not want[k] then
				common = common + math.min( a, b )
				all = all + math.max( a, b )
			end
		end
	end
	return all == 0 and 1 or common / all, same_sigils
end

local function symbols_alike( signature, symbols )
	local share, same_sigils = symbols_share( signature, symbols )
	return same_sigils and share >= SIGNS_ALIKE
end

function whole_alike( distance, second )
	return distance ~= nil and distance <= CANON_WHOLE and distance <= CANON_APART * ( second or math.huge )
end

function whole_sure( distance, second )
	return distance ~= nil and distance <= CANON_SURE and distance <= CANON_SURE_APART * ( second or math.huge )
end

-- Some of the wiki's whole seals take any sigil in their middle (grimoire.lua 'middle': Flowers of Light and Flowers
-- of Sand are one drawing round two sigils). The sigil drawn there: the lines that reach no farther from the
-- drawing's own middle than 'share' of the drawing's reach - a copy is never quite the page's size, nor quite in the
-- middle of its ring. Its key and how well it reads, or nil when it reads as no element's sigil.
local function middle_sigil( strokes, share )
	local ring, parts = find_ring( strokes )
	if not ring then return nil end
	local sx, sy, total = 0, 0, 0
	for i, stroke in ipairs( strokes ) do
		if not parts[i] then
			for k = 2, #stroke do
				local a, b = stroke[k - 1], stroke[k]
				local d = math.sqrt( ( b.x - a.x ) ^ 2 + ( b.y - a.y ) ^ 2 )
				sx, sy, total = sx + ( a.x + b.x ) / 2 * d, sy + ( a.y + b.y ) / 2 * d, total + d
			end
		end
	end
	if total == 0 then return nil end
	local cx, cy = sx / total, sy / total
	local far, reach = {}, 0
	for i, stroke in ipairs( strokes ) do
		if not parts[i] and #stroke > 0 then
			local m = 0
			for _, p in ipairs( stroke ) do m = math.max( m, ( p.x - cx ) ^ 2 + ( p.y - cy ) ^ 2 ) end
			far[i] = math.sqrt( m )
			reach = math.max( reach, far[i] )
		end
	end
	local content = {}
	for i, stroke in ipairs( strokes ) do
		if far[i] and far[i] <= share * reach then content[#content + 1] = stroke end
	end
	if #content == 0 then return nil end
	local symbol = recognize_symbol( content, bbox( content ), ring )
	local def = symbol and symbol.kind == "sigil" and DICTIONARY_SIGILS[symbol.key]
	-- a sigil that manifests in a way of its own is no element for the seal to take
	if def and def.element and not def.manifest then return symbol.key, symbol.score end
end

-- A drawing that is the page 'entry' as a whole, by the sigil in its middle: the page it is - the page of the same
-- manifest with that sigil - and, when no page has the sigil's element and the sigil is read well, the element.
-- With nothing in its middle that reads as an element's sigil it is the first of those pages (the wiki's own).
function seal_middle( strokes, entry )
	if not entry.middle then return entry end
	local sigil, score = middle_sigil( strokes, entry.middle_reach )
	local element = sigil and DICTIONARY_SIGILS[sigil].element
	local first
	for _, other in ipairs( GRIMOIRE ) do
		if other.middle and other.manifest == entry.manifest then
			first = first or other
			if DICTIONARY_SIGILS[other.middle].element == element then return other end
		end
	end
	if element and score >= STRONG_SIGIL then return first, element end
	return first
end

-- How far a drawing is in shape from one wiki's page (as seal_canonical measures it), or nil when it is far off
local function page_distance( seal, key )
	seal_canonical( seal ) -- builds the pages' clouds
	if not grimoire_clouds then return nil end
	local ring, parts = find_ring( seal.strokes or {} )
	if not ring then return nil end
	local mine = seal_cloud( seal.strokes, ring, parts )
	if not mine or mine.n < 4 then return nil end
	local best
	for _, entry in ipairs( grimoire_clouds ) do
		local other = entry.cloud
		if entry.key == key and other and other.n >= 4 then
			for _, try in ipairs( CANON_TRIES ) do
				local bound = CANON_MATCH * 2
				local d1 = chamfer( mine, other, try[1], bound, try[2] )
				if d1 < bound then
					local d = ( d1 + chamfer( other, mine, -try[1], bound, 1 / try[2] ) ) / 2
					if not best or d < best then best = d end
				end
			end
		end
	end
	return best
end

-- The one wiki's page whose symbols (as it reads, or as it is drawn of) are exactly a reading's, and how far the
-- drawing is from it in shape (nil: not measured), or nil: a seal of the page's symbols laid out its own way
-- (Pyreball's signs on the axes instead of the diagonals) is far from the page in shape, but no other page has
-- those symbols. A few symbols say little - a lone sword sigil is not yet Raincleaver, wind with a levitation sign
-- is not always Skysoaring - so such a seal must also look like its page (Skysoaring's big arrow over the sigil)
local SYMBOLS_PAGE_SIGNS = 3
local function sign_count( seal )
	local signs = 0
	for _, s in ipairs( seal.symbols or {} ) do
		if s.kind == "sign" then signs = signs + 1 end
	end
	return signs
end
local pages_by_symbols
local function symbols_page( seal )
	if not GRIMOIRE then return nil end
	if not pages_by_symbols then
		pages_by_symbols = {}
		for _, entry in ipairs( GRIMOIRE ) do
			for _, signature in ipairs( { entry.symbols or "", entry.recipe or "" } ) do
				if signature ~= "" then
					local list = pages_by_symbols[signature] or {}
					pages_by_symbols[signature] = list
					-- a seal drawn twice in the wiki is the same seal
					if not list[entry.name] then list[entry.name] = entry.key; list.count = ( list.count or 0 ) + 1 end
				end
			end
		end
	end
	local list = pages_by_symbols[seal_symbols_key( seal.symbols )]
	if not list or list.count ~= 1 then return nil end
	local key
	for name, k in pairs( list ) do
		if name ~= "count" then key = k end
	end
	if sign_count( seal ) >= SYMBOLS_PAGE_SIGNS then return key end
	-- a lone sigil is every plain seal of that sigil: it names the page only when drawn as the page is, not when it is
	-- merely nearer to it than to any other page
	local lone = #( seal.symbols or {} ) <= 1
	local distance = page_distance( seal, key )
	if distance and distance <= ( lone and CANON_WHOLE or CANON_MATCH ) then return key, distance end
	return nil
end

-- A copy of a whole seal drawn of the book's symbols (Flame Shot's ten Regions) whose shape is a hair nearer another
-- page (Petrification, as near as it): the page it is drawn like that has most of its symbols, the nearest of them
local function recipe_page( seal )
	if not GRIMOIRE or sign_count( seal ) < SYMBOLS_PAGE_SIGNS then return nil end
	local best, best_d
	for _, entry in ipairs( GRIMOIRE ) do
		if ( entry.symbols or "" ) == "" and ( entry.recipe or "" ) ~= "" and symbols_alike( entry.recipe, seal.symbols ) then
			local d = page_distance( seal, entry.key )
			if d and d <= CANON_MATCH and ( not best_d or d < best_d ) then best, best_d = entry.key, d end
		end
	end
	return best, best_d
end

-- The wiki's seal a read drawing is by its shape, and how far it is from it
local function seal_shape_name( seal )
	local key, distance, second = seal_canonical( seal )
	local entry = key and GRIMOIRE_BY_KEY and GRIMOIRE_BY_KEY[key]
	if not entry then return nil end
	if ( entry.symbols or "" ) ~= "" then
		-- the same symbols as the page reads as, or as the seal is drawn of
		if symbols_alike( entry.symbols, seal.symbols ) or symbols_alike( entry.recipe or "", seal.symbols ) then return key, distance end
		-- very close in shape, with most of the symbols (a sigil misread in a faithful drawing)
		local share = math.max( symbols_share( entry.symbols, seal.symbols ), ( symbols_share( entry.recipe or "", seal.symbols ) ) )
		if distance <= CANON_CLOSE and distance <= CANON_CLOSE_APART * second and share >= SYMBOLS_LOOSE then return key, distance end
		if distance <= CANON_CLOSE and distance <= CANON_CLEAR_APART * second then return key, distance end
		return nil
	end
	if whole_alike( distance, second ) then
		-- with a sigil in its middle that no page has, it is none of the wiki's seals: it is read sign by sign
		local page, element = seal_middle( seal.strokes, entry )
		if not element then return page.key, distance end
	end
	-- a whole seal drawn of the book's symbols (Flame Shot's ten Regions): a copy with a few of its signs more or fewer -
	-- hands don't count them - is still that seal when it looks like it and most of its symbols are the page's
	if ( entry.recipe or "" ) ~= "" and sign_count( seal ) >= SYMBOLS_PAGE_SIGNS and symbols_alike( entry.recipe, seal.symbols ) then
		return key, distance
	end
	return nil
end

-- The wiki's seal a read drawing is (its key) and how far it is from the page in shape (nil when it is that seal by
-- its symbols alone), or nil
function seal_name( seal )
	local key, distance = seal_shape_name( seal )
	if key then return key, distance end
	key, distance = symbols_page( seal )
	if key then return key, distance end
	return recipe_page( seal )
end
