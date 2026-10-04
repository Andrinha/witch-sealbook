-- Optional instrumentation, using only the documented, Workshop-safe API.
-- Effect scripts share one VM; init.lua consumes the numeric frame row through
-- Globals because world callbacks run in a different Lua context.
EffectProfiler = {}
local P = EffectProfiler
P.payload_key, P.report_key = "witch_notebook.perf_frame", "witch_notebook.perf_report"
P.columns = { "lua", "params", "restore", "movement", "mask", "injection", "forces",
	"pressure", "velocity", "density", "emitters", "draw", "damage", "save", "light",
	"solver_ticks", "substeps", "rays", "pixels", "new_sources", "restores", "updates",
	"heap", "heap_drop", "snapshot_bytes", "load", "warmup", "starts", "reused_sources",
	"heap_available", "mask_rays", "injection_rays", "velocity_rays", "density_rays", "emitters_rays", "draw_rays" }
P.index = {}
for i, name in ipairs( P.columns ) do P.index[name] = i + 1 end

function P.enabled()
	local frame = GameGetFrameNum()
	if not P.next_check or frame >= P.next_check or frame < P.checked_frame then
		P.checked_frame, P.next_check = frame, frame + 30
		P.active = ModSettingGet( "witch_notebook.performance_profiler" ) == true
	end
	return P.active and type( GameGetRealWorldTimeSinceStarted ) == "function"
end

local function heap()
	return type( collectgarbage ) == "function" and collectgarbage( "count" ) or 0
end

local Token = {}
function Token:begin() return GameGetRealWorldTimeSinceStarted() end
function Token:count( name, amount )
	local i = P.index[name]
	if i then P.row[i] = P.row[i] + ( amount or 1 ) end
end
function Token:finish( name, started )
	self:count( name, math.max( 0, self:begin() - started ) * 1000 )
	if name ~= "lua" then
		local rays = P.row[P.index.rays]
		self:count( name .. "_rays", rays - ( self.rays or 0 ) )
		self.rays = rays
	end
end

function P.begin_update()
	if not P.enabled() then return nil end
	local frame = GameGetFrameNum()
	if frame ~= P.frame then
		P.frame, P.row = frame, P.row or {}
		P.row[1] = frame
		for i = 2, #P.columns + 1 do P.row[i] = 0 end
	end
	local token = P.token or setmetatable( {}, { __index = Token } )
	P.token = token
	token.started, token.heap = token:begin(), heap()
	token.rays = P.row[P.index.rays]
	return token
end

function P.end_update( token )
	if not token then return end
	token:finish( "lua", token.started )
	token:count( "updates", 1 )
	local used = heap()
	P.row[P.index.heap_available] = used > 0 and 1 or 0
	P.row[P.index.heap] = math.max( P.row[P.index.heap], used )
	token:count( "heap_drop", math.max( 0, token.heap - used ) )
	-- Export after each effect, so the world callback sees the complete frame.
	GlobalsSetValue( P.payload_key, table.concat( P.row, "," ) )
end

function P.pause()
	P.last_time, P.last_frame = nil, nil
end

local function metric( rows, field )
	local values, sum, max_value = {}, 0, 0
	for _, row in ipairs( rows ) do
		local value = row[field] or 0
		if field ~= "dt" or value > 0 then
			values[#values + 1], sum = value, sum + value
			max_value = math.max( max_value, value )
		end
	end
	table.sort( values )
	return sum / math.max( 1, #values ), values[math.max( 1, math.ceil( #values * 0.95 ) )] or 0, max_value
end

local function describe( row )
	local name, cost = "none", 0
	for i = P.index.params, P.index.light do
		if ( row[i] or 0 ) > cost then name, cost = P.columns[i - 1], row[i] end
	end
	for _, stage in ipairs( { "load", "warmup" } ) do
		if ( row[P.index[stage]] or 0 ) > cost then name, cost = stage, row[P.index[stage]] end
	end
	local memory = row[P.index.heap_available] == 1
		and string.format( "heap=%.0fKB drop=%.0fKB", row[P.index.heap], row[P.index.heap_drop] ) or "heap=n/a"
	return string.format( "f=%d frame=%.1fms Lua=%.1fms %s=%.1fms ticks=%d sub=%d rays=%d(m=%d,v=%d,d=%d) pixels=%d new=%d reuse=%d save=%.0fKB %s",
		row[1], row.dt or 0, row[P.index.lua] or 0, name, cost,
		row[P.index.solver_ticks] or 0, row[P.index.substeps] or 0,
		row[P.index.rays] or 0, row[P.index.mask_rays] or 0, row[P.index.velocity_rays] or 0, row[P.index.density_rays] or 0,
		row[P.index.pixels] or 0, row[P.index.new_sources] or 0, row[P.index.reused_sources] or 0,
		( row[P.index.snapshot_bytes] or 0 ) / 1024, memory )
end

function P.summary()
	local rows = P.samples or {}
	local avg, p95, peak = metric( rows, "dt" )
	local lua_avg, lua_p95, lua_peak = metric( rows, P.index.lua )
	local worst_frame, worst_lua
	for _, row in ipairs( rows ) do
		if not worst_frame or row.dt > worst_frame.dt then worst_frame = row end
		if not worst_lua or row[P.index.lua] > worst_lua[P.index.lua] then worst_lua = row end
	end
	local title = string.format( "Frames ms avg/p95/max: %.1f / %.1f / %.1f", avg, p95, peak )
	local effects = string.format( "Effects Lua ms avg/p95/max: %.1f / %.1f / %.1f", lua_avg, lua_p95, lua_peak )
	local lines = { title, effects,
		"Worst frame: " .. ( worst_frame and describe( worst_frame ) or "none" ),
		"Worst Lua: " .. ( worst_lua and describe( worst_lua ) or "none" ) }
	if worst_lua then
		local parts = { "Stages ms (worst Lua):" }
		for _, stage in ipairs( { "mask", "pressure", "velocity", "density", "draw", "save", "load", "warmup" } ) do
			parts[#parts + 1] = string.format( "%s=%.1f", stage, worst_lua[P.index[stage]] or 0 )
		end
		lines[#lines + 1] = table.concat( parts, " " )
	end
	if P.first_cast then lines[#lines + 1] = "First cast: " .. describe( P.first_cast ) end
	return lines
end

function P.world_update()
	if not P.enabled() then
		P.pause()
		P.samples, P.lines, P.first_cast, P.was_active = nil, nil, nil, false
		if P.gui then GuiDestroy( P.gui ); P.gui = nil end
		return
	end
	local frame, now = GameGetFrameNum(), GameGetRealWorldTimeSinceStarted()
	if not P.was_active or P.last_frame and frame < P.last_frame then
		P.samples, P.cursor, P.first_cast, P.was_active = {}, 0, nil, true
		P.next_summary, P.next_log = frame, frame + 300
		P.pause()
	end
	if frame == P.last_frame then return end
	P.cursor = P.cursor % 300 + 1
	local row = P.samples[P.cursor] or {}
	P.samples[P.cursor] = row
	for i = 1, #P.columns + 1 do row[i] = 0 end
	local text = GlobalsGetValue( P.payload_key, "" )
	local i = 0
	for value in text:gmatch( "([^,]+)" ) do
		i = i + 1
		if i > #P.columns + 1 then break end
		row[i] = tonumber( value ) or 0
	end
	if row[1] ~= frame then for j = 2, #P.columns + 1 do row[j] = 0 end end
	row[1] = frame
	row.dt = P.last_time and frame == P.last_frame + 1 and math.max( 0, now - P.last_time ) * 1000 or 0
	P.last_time, P.last_frame = now, frame
	if not P.first_cast and row[P.index.starts] > 0 then
		P.first_cast = { dt = row.dt }
		for j = 1, #P.columns + 1 do P.first_cast[j] = row[j] end
	end
	if frame >= P.next_summary then
		P.lines, P.next_summary = P.summary(), frame + 30
		GlobalsSetValue( P.report_key, table.concat( P.lines, "\n" ) )
	end
	if frame >= P.next_log then
		print( "[witch_notebook/perf] " .. table.concat( P.lines, "\n" ) )
		P.next_log = frame + 300
	end
	if type( GuiCreate ) == "function" then
		P.gui = P.gui or GuiCreate()
		GuiStartFrame( P.gui )
		local y = 60
		for _, text in ipairs( P.lines ) do
			local line = ""
			for word in text:gmatch( "%S+" ) do
				if #line + #word > 68 then
					GuiText( P.gui, 8, y, line ); y, line = y + 10, "  "
				end
				line = line .. ( #line > 0 and " " or "" ) .. word
			end
			GuiText( P.gui, 8, y, line ); y = y + 10
		end
	end
end
