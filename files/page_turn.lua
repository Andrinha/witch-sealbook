-- A sheet of a book turning over (notebook.lua draws the books). The sheet is cut into strips across the way it turns
-- (book_gfx.lua), and it is a curve: every bit of the paper makes the same turn, but the nearer the hinge, the later -
-- so the sheet lifts at its free edge, arches over and rolls down onto the other side, bending like paper. The strips
-- are drawn along the curve with perspective (raised paper is bigger) and light (turned away from the light - darker);
-- where the paper leans over, its other side shows. The page's content is drawn through a surface that bends with the
-- paper, like book_draw.lua's flat one.
-- A book's sheets turn over its spine, sideways; the Palm Quire's leaves flip up over the hinge at their top ('vertical').
-- Positions run 'along' from the hinge towards the page lying on the front side (the right page, the quire's pad) and
-- 'across' from the page's edge along the hinge. The view (notebook.lua): def (the book), size, vertical, gap (from the
-- hinge to a page), strips, strip (a strip's width), hinge (its screen x, or y when vertical), across0 (the pages' top,
-- or left side when vertical).

PageTurn = {}
local T = PageTurn
local D = BookDraw

T.LAG = 0.36          -- how far behind its free edge the paper near the hinge turns (a share of the turn)
T.PERSPECTIVE = 0.1   -- how much bigger the lifted paper looks
local CURL_DOT_STEP = 0.8 -- the pen's dots on a turning page, a little fewer

-- the screen point 'a' along the axis from the hinge and 'c' across it
local function screen( view, a, c )
	if view.vertical then return view.across0 + c, view.hinge + a end
	return view.hinge + a, view.across0 + c
end
T.screen = screen

-- The paper's angle at 'u' along it from the hinge (0 .. gap + size) at 't' of the turn: 0 - lying on the front side,
-- pi - lying on the back side (the left page, the quire's lid)
local function sheet_angle( view, t, u, forward )
	local lag = T.LAG * ( 1 - ( u / ( view.gap + view.size ) ) ^ 0.8 )
	local k = math.max( 0, math.min( 1, ( t - lag ) / ( 1 - T.LAG ) ) )
	local a = math.pi * k * k * ( 3 - 2 * k )
	return forward and a or math.pi - a
end

-- The turning sheet's shape at 't': for each strip's edge its offset along the axis from the hinge and its height over
-- the book, and each strip's angle
function T.shape( view, t, forward )
	local n, w, g = view.strips, view.strip, view.gap
	local as, zs, angles = {}, {}, {}
	local a, z = 0, 0
	-- along the fold into the hinge first, then strip by strip, two steps each
	for step = 0, 3 do
		local ang = sheet_angle( view, t, g * ( step + 0.5 ) / 4, forward )
		a, z = a + math.cos( ang ) * g / 4, z + math.sin( ang ) * g / 4
	end
	as[0], zs[0] = a, z
	for i = 0, n - 1 do
		for half = 0, 1 do
			local ang = sheet_angle( view, t, g + w * ( i + ( half + 0.5 ) / 2 ), forward )
			a, z = a + math.cos( ang ) * w / 2, z + math.sin( ang ) * w / 2
		end
		as[i + 1], zs[i + 1] = a, z
		angles[i] = sheet_angle( view, t, g + w * ( i + 0.5 ), forward )
	end
	return as, zs, angles
end

-- The share of the turn at which the free edge is 'a' from the hinge (a page's corner held with the mouse)
local edge_tables = {}
function T.turn_at( view, a, forward )
	local key = view.def.key .. ( forward and ":on" or ":back" )
	local tab = edge_tables[key]
	if not tab then
		tab = {}
		for k = 0, 64 do tab[k] = ( T.shape( view, k / 64, forward ) )[view.strips] end
		edge_tables[key] = tab
	end
	-- every bit of the paper turns one way, so the edge does too
	local sign = forward and -1 or 1
	if ( a - tab[0] ) * sign <= 0 then return 0 end
	for k = 1, 64 do
		if ( a - tab[k] ) * sign <= 0 then return ( k - 1 + ( a - tab[k - 1] ) / ( tab[k] - tab[k - 1] ) ) / 64 end
	end
	return 1
end

-- A sheet turning over: its shape at this frame - for each strip its place along the axis, height and angle, how it is
-- lit and how near it is. The higher the paper, the nearer: sheets turning together cover one another as they should;
-- sheets lying on each other keep the book's order: on the front side the sheets further on lie under, on the back side
-- over ('rank': 0 - the first sheet). f: { from, to, frame, lift } - the spreads it turns between; 'frames': the whole
-- turn.
function T.geometry( view, f, rank, frames )
	local t = math.max( 0, math.min( 1, f.frame / frames ) )
	local forward = f.to > f.from
	local as, zs, angles = T.shape( view, t, forward )
	local n, size = view.strips, view.size
	-- a sheet held by its corner follows the mouse across the axis: the paper shifts, the more the nearer the free edge,
	-- so the sheet skews as if turned by its corner (not while it lies flat at either end of the turn)
	local shift = {}
	local lift = ( f.lift or 0 ) * math.min( 1, 4 * t, 4 * ( 1 - t ) )
	for j = 0, n do shift[j] = lift * ( ( view.gap + view.strip * j ) / ( view.gap + size ) ) ^ 1.3 end
	-- light from above and a little from the back side: a face turned up is bright, one turned away darker
	local light, z, lo, hi = {}, {}, {}, {}
	for i = 0, n - 1 do
		local a = angles[i]
		local up = math.cos( a ) > 0 and ( math.cos( a ) + 0.3 * math.sin( a ) ) or ( -math.cos( a ) - 0.3 * math.sin( a ) )
		-- lying flat (either face up) it is as bright as a page lying still: no jump as it starts or ends its turn
		light[i] = math.min( 1, 0.6 + 0.4 * math.max( 0, up ) )
		z[i] = 14 - 0.01 * ( zs[i] + zs[i + 1] ) + ( math.cos( a ) > 0 and 1 or -1 ) * rank * 0.001
		lo[i], hi[i] = math.min( as[i], as[i + 1] ), math.max( as[i], as[i + 1] )
	end
	-- what is drawn on the paper lies over its strip and the strips beside it: a dot or a letter reaches over a strip's
	-- edge, and a neighbour lifted higher would cut it off
	local zc = {}
	for i = 0, n - 1 do zc[i] = math.min( z[i], z[i - 1] or z[i], z[i + 1] or z[i] ) - 0.0002 end
	local a0, a1 = math.huge, -math.huge
	for i = 0, n do a0, a1 = math.min( a0, as[i] ), math.max( a1, as[i] ) end
	return { f = f, t = t, forward = forward, as = as, zs = zs, angles = angles, light = light, z = z, lo = lo, hi = hi,
		a0 = a0, a1 = a1, hidden = {}, shift = shift, zc = zc, lifted = math.abs( lift ) > 0.5 }
end

-- The strips another sheet covers whole, nearer than them: nothing on them shows (the paper is one piece from the hinge
-- to its edge, so a sheet covers all of its span)
function T.hide_covered( view, shapes )
	-- A round leaf has transparent corners. Its span along the turn cannot tell which parts of another leaf it covers.
	if view.def.round then return end
	for _, a in ipairs( shapes ) do
		for i = 0, view.strips - 1 do
			for _, b in ipairs( shapes ) do
				if b ~= a and not b.lifted and a.lo[i] >= b.a0 and a.hi[i] <= b.a1 then
					local nearer = true
					for j = 0, view.strips - 1 do
						if b.hi[j] > a.lo[i] and b.lo[j] < a.hi[i] and b.z[j] >= a.z[i] then nearer = false break end
					end
					if nearer then a.hidden[i] = true break end
				end
			end
		end
	end
end

-- the sheets lying still enough to hide the pages under them: their spans on the screen, along the axis (BookDraw.covered)
function T.covered( view, shapes )
	-- The same one-dimensional span would hide ink on the flat leaf where the curled round leaf is transparent.
	-- Draw the ink and let the opaque pixels of the turning leaf cover it at their proper depth.
	if view.def.round then return nil end
	local spans = {}
	for _, shape in ipairs( shapes ) do
		if not shape.lifted then spans[#spans + 1] = { view.hinge + shape.a0, view.hinge + shape.a1 } end
	end
	return { vertical = view.vertical, spans = spans }
end

---- a side of the turning sheet as a surface ----

local Curl = {}
Curl.__index = Curl

-- A face of the turning sheet: a point of the page is where the bent paper carries it, seen only while that bit of the
-- paper shows this face ('front': the face that shows while the paper lies on the front side)
function T.surface( view, shape, front )
	return setmetatable( { view = view, shape = shape, front = front, step = CURL_DOT_STEP, size = view.size }, Curl )
end
-- a point of the page: how far from the hinge along the paper, and where across it
function Curl:uv( px, py )
	local along, across = px, py
	if self.view.vertical then along, across = py, px end
	return self.front and along or self.size - along, across
end
-- the strip under a point of the page, and where in it (0..1)
function Curl:locate( px, py )
	local f = self:uv( px, py ) / self.view.strip
	local i = math.max( 0, math.min( self.view.strips - 1, math.floor( f ) ) )
	return i, f - i
end
function Curl:seen( i )
	if self.shape.hidden[i] then return false end -- under another sheet
	local cos = math.cos( self.shape.angles[i] )
	return ( self.front and cos > 0.02 ) or ( not self.front and cos < -0.02 )
end
-- where a point of the page is on the screen, and its scale there; the paper held by its corner is shifted across
function Curl:map( px, py )
	local _, v = self:uv( px, py )
	local i, f = self:locate( px, py )
	local sh, size = self.shape, self.size
	local a = sh.as[i] + ( sh.as[i + 1] - sh.as[i] ) * f
	local z = sh.zs[i] + ( sh.zs[i + 1] - sh.zs[i] ) * f
	local k = 1 + T.PERSPECTIVE * z / size
	local shift = sh.shift[i] + ( sh.shift[i + 1] - sh.shift[i] ) * f
	local x, y = screen( self.view, a, size / 2 + ( v - size / 2 ) * k + shift )
	return x, y, k, i
end
function Curl:z( i ) return self.shape.z[i] end
-- the depth of what is drawn on the paper over strips i0..i1
function Curl:zc( i0, i1 )
	local z = math.huge
	for i = math.min( i0, i1 or i0 ), math.max( i0, i1 or i0 ) do z = math.min( z, self.shape.zc[i] ) end
	return z
end
function Curl:shade( color, i )
	local k = self.shape.light[i]
	color = color or { 1, 1, 1 }
	return { color[1] * k, color[2] * k, color[3] * k }
end
function Curl:dot( px, py, color, alpha )
	local i = self:locate( px, py )
	if not self:seen( i ) then return end
	local x, y = self:map( px, py )
	local c = self:shade( color, i )
	GuiZSetForNextWidget( D.gui(), self:zc( i ) )
	GuiColorSetForNextWidget( D.gui(), c[1], c[2], c[3], alpha or 1 )
	-- the pen's dot at its own size, as on a flat page: scaled by a hair its texels no longer fall on the screen's pixels
	local w = self.pen or 1
	GuiImage( D.gui(), D.next_id(), x - w, y - w, NOTEBOOK_BRUSH_IMAGE, alpha or 1, w / NOTEBOOK_BRUSH_RES )
end

-- the size of an image a page carries
local function image_size( file )
	local columns = NOTEBOOK_COLUMNS[file]
	if columns then return columns.w, columns.h end
	if file:find( "digit_", 1, true ) then return BOOK_DIGIT_W, BOOK_DIGIT_H end
	return 16, 16
end

-- the part of an image between two points of the page, squeezed with the paper under them
function Curl:put( px0, py0, px1, py1, file, w, h, color, alpha, behind )
	local i0, i1 = self:locate( px0, py0 ), self:locate( px1, py1 )
	local seen = self:seen( i0 ) and self:seen( i1 )
	if not ( seen or behind ) then return end
	local x0, y0, _, i = self:map( px0, py0 )
	local x1, y1 = self:map( px1, py1 )
	local c = self:shade( color, i )
	GuiZSetForNextWidget( D.gui(), seen and self:zc( i0, i1 ) or math.max( self:z( i0 ), self:z( i1 ) ) + 0.0005 )
	GuiColorSetForNextWidget( D.gui(), c[1], c[2], c[3], alpha or 1 )
	GuiImage( D.gui(), D.next_id(), math.min( x0, x1 ), math.min( y0, y1 ), file, alpha or 1, math.abs( x1 - x0 ) / w,
		math.abs( y1 - y0 ) / h )
end

-- An image on the page, squeezed with the paper: on a sheet turning sideways one cut into columns (image_cut_columns)
-- bends with it, a column at a time. 'behind': also where the paper shows its other face - behind the paper there,
-- showing only past its edge (the ribbon).
function Curl:image( px, py, file, z, color, alpha, sx, sy, behind )
	sx = sx or 1
	sy = sy or sx
	local w, h = image_size( file )
	local columns = not self.view.vertical and NOTEBOOK_COLUMNS[file]
	if not columns then
		return self:put( px, py, px + w * sx, py + h * sy, file, w, h, color, alpha, behind )
	end
	for column = 0, w - 1 do
		local cx = px + column * sx
		self:put( cx, py, cx + sx, py + h * sy, columns[column], 1, h, color, alpha, behind )
	end
end

-- text bends with the paper letter by letter (book_gfx.lua BOOK_GLYPHS); a letter shows while its paper faces this way
function Curl:text( px, py, str, color, z, scale )
	scale = scale or 1
	local x = px
	for ch in str:gmatch( D.UTF8_CHAR ) do
		local glyph = BOOK_GLYPHS[D.code_point( ch )]
		if glyph and glyph.file then
			local gx, gy = x + glyph.ox * scale, py + glyph.oy * scale
			local i0, i1 = self:locate( gx, gy ), self:locate( gx + glyph.w * scale, gy + glyph.h * scale )
			if self:seen( i0 ) and self:seen( i1 ) then
				local x0, y0, _, i = self:map( gx, gy )
				local x1, y1 = self:map( gx + glyph.w * scale, gy + glyph.h * scale )
				local c = self:shade( color or { 1, 1, 1 }, i )
				GuiZSetForNextWidget( D.gui(), self:zc( i0, i1 ) - 0.0001 )
				GuiColorSetForNextWidget( D.gui(), c[1], c[2], c[3], 1 )
				GuiImage( D.gui(), D.next_id(), math.min( x0, x1 ), math.min( y0, y1 ), glyph.file, 1, math.abs( x1 - x0 ) / glyph.w,
					math.abs( y1 - y0 ) / glyph.h )
			end
		end
		x = x + ( glyph and glyph.width or BOOK_WORD_SPACE ) * scale
	end
	return x - px
end

---- drawing a turning sheet ----

-- The quire's leaves are round, and so are their shadows: drawn row by row, each row cut to the leaf it falls on
-- ('side': 1 - the pad, -1 - the lid): the span across it, cut along its pixels; nil off it
local function leaf_span( view, side, a )
	-- the leaf's pixels in this row, as book_gfx.lua paints it: those within c + 0.5 of its middle
	local size = view.size
	local y = side > 0 and a - view.gap or a + view.gap + size
	if y < 0 or y >= size then return nil end
	local c = ( size - 1 ) / 2
	local w2 = ( c + 0.5 ) ^ 2 - ( y - c ) ^ 2
	if w2 < 0 then return nil end
	local w = math.sqrt( w2 )
	local k0, k1 = math.ceil( c - w ), math.floor( c + w ) + 1
	if k1 <= k0 then return nil end
	return k0, k1
end

-- a row of shadow across the screen from 'c0' to 'c1' (across the axis), one pixel along it at 'a'
local function shadow_row( view, a, c0, c1, alpha, z )
	c0, c1 = math.max( c0, 0 ), math.min( c1, view.size )
	if c1 - c0 < 0.5 or alpha <= 0.01 then return end
	local x, y = screen( view, a, c0 )
	D.rect( x, y, c1 - c0, 1, D.SHADE_COLOR, z, alpha )
end

-- A row of a soft shadow: solid over 'i0'..'i1' across, fading out to 'o0' and 'o1', cut to 'k0'..'k1' (the leaf beneath)
local function soft_row( view, a, o0, i0, i1, o1, k0, k1, alpha, z )
	if alpha <= 0.01 then return end
	-- the solid middle and the ramps meet on whole pixels: no pixel left between them
	i0, i1 = math.floor( i0 + 0.5 ), math.floor( i1 + 0.5 )
	if i1 < i0 then i0, i1 = math.floor( ( i0 + i1 ) / 2 ), math.floor( ( i0 + i1 ) / 2 ) end
	shadow_row( view, a, math.max( i0, k0 ), math.min( i1, k1 ), alpha, z )
	-- a ramp from 'from' (solid) to 'to' (clear): whole, as an image; cut by the leaf's rim, in steps
	local function ramp( from, to, file )
		local lo, hi = math.min( from, to ), math.max( from, to )
		local w = hi - lo
		if w < 0.25 then return end
		if lo >= k0 and hi <= k1 then
			local x, y = screen( view, a, lo )
			D.image( x, y, file, z, D.SHADE_COLOR, alpha, w / 16, 1 )
			return
		end
		for p = math.max( math.floor( lo ), k0 ), math.min( math.ceil( hi ), k1 ) - 1 do
			local t = math.max( 0, 1 - math.abs( p + 0.5 - from ) / w )
			shadow_row( view, a, p, p + 1, alpha * t * t, z )
		end
	end
	ramp( i0, o0, BOOK_SHADE_R_IMAGE )
	ramp( i1, o1, BOOK_SHADE_IMAGE )
end

-- the shadow of a turning round leaf on the leaves beneath it. Each bit of the leaf casts its shadow further on the higher it is, towards the side the leaf leans to; the shadow
-- is the oval round all that (a bent leaf's own outline would fold over itself into straight edges), soft all round.
-- Under the leaf it is hidden, beside it it shows.
local function round_shadows( view, shape, lift )
	local n, r = view.strips, view.size / 2
	local lean = math.cos( shape.angles[n - 1] )
	local fade = math.min( 1, math.abs( lean ) / 0.5 )
	fade = fade * fade * ( 3 - 2 * fade )
	local dir = lean > 0 and 1 or -1
	local alpha = ( dir > 0 and 0.35 or 0.25 ) * lift * fade -- the lid stands up to the light: fainter on it
	local a0, a1, k = math.huge, -math.huge, 1
	local cast = dir > 0 and 1 or 0.6 -- on the lid the shadow falls nearer the leaf
	for i = 0, n do
		local sa = shape.as[i] + dir * cast * math.min( 26, 5 + shape.zs[i] * 0.22 ) * math.min( 1, lift * 3 )
		a0, a1 = math.min( a0, sa ), math.max( a1, sa )
		k = math.max( k, 1 + T.PERSPECTIVE * shape.zs[i] / view.size )
	end
	local reach = math.min( 26, 5 + shape.zs[n] * 0.22 ) * math.min( 1, lift * 3 )
	local soft = math.max( 3, reach ) -- the soft rim round the shadow: the higher the leaf, the wider
	-- the soft rim spreads out past the leaf's own size, as a blurred shadow does, rather than eating into it
	local spread = soft
	a0, a1 = a0 - spread, a1 + spread
	-- its far end stays on the leaf it falls on: the shadow shrinks there rather than being cut off by the leaf's rim
	local rim = view.gap + view.size
	if dir > 0 then a1 = math.min( a1, rim ) else a0 = math.max( a0, -rim ) end
	local c, ea, eb = ( a0 + a1 ) / 2, ( a1 - a0 ) / 2, r * k + spread
	if alpha > 0.01 and ea >= 1 + spread then
		local hinge_end = math.abs( a0 ) < math.abs( a1 ) and a0 or a1
		for a = math.floor( a0 ), math.ceil( a1 ) do
			local u = ( a + 0.5 - c ) / ea
			local k0, k1 = leaf_span( view, a >= 0 and 1 or -1, a )
			if k0 and math.abs( u ) < 1 then
				-- solid over an oval 'soft' in from the outline, fading out over the same rim all round: at the ends
				-- as at the sides (past the solid oval a row is fainter, with a flat top rather than a ridge)
				local outer = eb * math.sqrt( 1 - u * u )
				local d = math.abs( a + 0.5 - c )
				local ia, ib = math.max( 0.01, ea - soft ), math.max( 0, eb - soft )
				local peak = math.min( 1, ( ea - d ) / soft )
				peak = peak * peak * ( 3 - 2 * peak ) -- smooth into the solid middle: no edge where the fading starts
				local inner = math.max( ib * math.sqrt( math.max( 0, 1 - ( d / ia ) ^ 2 ) ), outer - soft, outer * 0.3 )
				local m = r + shape.shift[n] * math.abs( a - hinge_end ) / ( 2 * ea )
				soft_row( view, a, m - outer, m - inner, m + inner, m + outer, k0, k1, alpha * peak, 15 )
			end
		end
	end
end

-- A sheet turning over: it bends strip by strip, shaded by how it faces the light; its two faces are the two pages it
-- carries - 'faces': { { face, front, kind }, ... }, draw_face( s, face, seen ) draws what is on one onto its surface
-- ('seen': some of it shows) - and it casts a soft shadow ahead of its free edge
function T.draw_sheet( view, shape, faces, draw_face )
	local size, n = view.size, view.strips
	local as, zs, light = shape.as, shape.zs, shape.light
	for _, face in ipairs( faces ) do
		local s = T.surface( view, shape, face.front )
		local seen = false
		for i = 0, n - 1 do
			if s:seen( i ) then
				seen = true
				local a0, a1 = as[i], as[i + 1]
				local k = 1 + T.PERSPECTIVE * ( zs[i] + zs[i + 1] ) / 2 / size
				local strip = face.front and i or n - 1 - i
				local c = light[i]
				-- a hair longer than the strip, so no gaps show between strips
				local x, y = screen( view, math.min( a0, a1 ) - 0.15, size / 2 * ( 1 - k ) + ( shape.shift[i] + shape.shift[i + 1] ) / 2 )
				local along = ( math.abs( a1 - a0 ) + 0.3 ) / view.strip
				GuiZSetForNextWidget( D.gui(), s:z( i ) )
				-- shaded paper a little warmer; lit fully, its own colour
				GuiColorSetForNextWidget( D.gui(), c, c, c * ( 0.97 + 0.03 * c ), 1 )
				GuiImage( D.gui(), D.next_id(), x, y, book_turn_strip_image( view.def, face.kind, strip, face.front ), 1, view.vertical and k or along,
					view.vertical and along or k )
			end
		end
		draw_face( s, face.face, seen )
	end
	-- the shadow ahead of the free edge, on the page beneath; the higher the edge, the longer and softer. It falls on the
	-- side the paper leans to, fading out as the paper stands up, and only on the pages (the sheet may be shifted across
	-- with its corner held).
	local edge = as[n]
	local lift = math.sin( math.pi * shape.t )
	if view.def.round then return round_shadows( view, shape, lift ) end
	local reach = math.min( 26, 5 + zs[n] * 0.22 ) * math.min( 1, lift * 3 )
	local lean = math.cos( shape.angles[n - 1] )
	local fade = math.min( 1, math.abs( lean ) / 0.5 )
	fade = fade * fade * ( 3 - 2 * fade )
	local shift = shape.shift[n]
	local length = lean > 0 and math.min( reach, view.gap + size - edge ) or -math.min( reach, edge + view.gap + size )
	local x, y = screen( view, edge, math.max( 0, shift ) )
	D.shadow( x, y, length, size - math.abs( shift ), 0.35 * lift * fade, 15, true, view.vertical )
	-- the open book darkens a little under the lifted paper
	local fx, fy = screen( view, view.gap, 0 )
	D.shadow( fx, fy, 30 * lift, size, 0.18 * lift, 16, false, view.vertical )
	local bx, by = screen( view, -view.gap, 0 )
	D.shadow( bx, by, -30 * lift, size, 0.18 * lift, 16, false, view.vertical )
end
