-- A drawing as the books keep it: strokes { { x = , y = }, ..., ink = key (ink.lua INKS), mark (seal.lua) }, and the
-- text they are saved as - on a book's pages (book_store.lua), for the book in hand to light up in the air (cast.lua)
-- and in the records of recognized drawings (notebook.lua).

-- strokes <-> "x,y x,y|x,y ..."
function strokes_encode( list )
	local parts = {}
	for _, stroke in ipairs( list ) do
		local pts = {}
		for _, p in ipairs( stroke ) do pts[#pts + 1] = string.format( "%.1f,%.1f", p.x, p.y ) end
		parts[#parts + 1] = table.concat( pts, " " )
	end
	return table.concat( parts, "|" )
end

function strokes_decode( text )
	local list = {}
	for part in ( text or "" ):gmatch( "[^|]+" ) do
		local stroke = {}
		for x, y in part:gmatch( "([-%d.]+),([-%d.]+)" ) do stroke[#stroke + 1] = { x = tonumber( x ), y = tonumber( y ) } end
		if #stroke > 0 then list[#list + 1] = stroke end
	end
	return list
end

-- the strokes' inks <-> "ink,blood,ink"; one key alone is the ink of every stroke
function strokes_encode_inks( list )
	local keys, same = {}, true
	for i, stroke in ipairs( list ) do
		keys[i] = stroke.ink or "ink"
		if keys[i] ~= keys[1] then same = false end
	end
	if #keys == 0 or ( same and keys[1] == "ink" ) then return "" end
	return same and keys[1] or table.concat( keys, "," )
end

function strokes_apply_inks( list, text )
	local keys = {}
	for key in ( text or "" ):gmatch( "[^,]+" ) do keys[#keys + 1] = key end
	for i, stroke in ipairs( list ) do
		local key = keys[i] or ( #keys == 1 and keys[1] ) or "ink"
		stroke.ink = INK_BY_KEY[key] and key or "ink"
	end
	return list
end

-- the strokes marked as symbols (seal.lua: stroke.mark = { kind, key }, one table for all the strokes of one symbol) <->
-- "sign:light@1,2;sigil:fire@3": each mark with the strokes it holds
function strokes_encode_marks( list )
	local marks, of = {}, {}
	for i, stroke in ipairs( list ) do
		local mark = stroke.mark
		if mark then
			if not of[mark] then
				of[mark] = { mark.kind .. ":" .. mark.key }
				marks[#marks + 1] = of[mark]
			end
			table.insert( of[mark], i )
		end
	end
	local parts = {}
	for k, ids in ipairs( marks ) do parts[k] = table.remove( ids, 1 ) .. "@" .. table.concat( ids, "," ) end
	return table.concat( parts, ";" )
end

function strokes_apply_marks( list, text )
	for item in ( text or "" ):gmatch( "[^;]+" ) do
		local kind, key, ids = item:match( "^(%a+):([%w_]+)@([%d,]+)$" )
		if kind then
			local mark = { kind = kind, key = key }
			for i in ids:gmatch( "%d+" ) do
				local stroke = list[tonumber( i )]
				if stroke then stroke.mark = mark end
			end
		end
	end
	return list
end

-- A seal's page keeps a lighter copy of the strokes: 2x2 ink dots 1.5 apart still make a solid line
function strokes_thin( list, step )
	local out = {}
	local min = ( step or 1.5 ) ^ 2
	for _, stroke in ipairs( list ) do
		local kept = { stroke[1], ink = stroke.ink, mark = stroke.mark }
		for k = 2, #stroke do
			local p, last = stroke[k], kept[#kept]
			if k == #stroke or ( p.x - last.x ) ^ 2 + ( p.y - last.y ) ^ 2 >= min then kept[#kept + 1] = p end
		end
		out[#out + 1] = kept
	end
	return out
end

-- A line of points 'step' apart along it: the grimoire keeps its points about 2 apart, too far for 2x2 ink dots to make
-- a solid line
function strokes_even( list, step )
	local out = {}
	for _, stroke in ipairs( list ) do
		local line = { stroke[1], ink = stroke.ink, mark = stroke.mark }
		for k = 2, #stroke do
			local a, b = stroke[k - 1], stroke[k]
			local n = math.max( 1, math.ceil( math.sqrt( ( b.x - a.x ) ^ 2 + ( b.y - a.y ) ^ 2 ) / step ) )
			for i = 1, n do line[#line + 1] = { x = a.x + ( b.x - a.x ) * i / n, y = a.y + ( b.y - a.y ) * i / n } end
		end
		out[#out + 1] = line
	end
	return out
end
