-- The run's clock: frames since the run began, going on across Save & Quit. GameGetFrameNum() starts from 0 again with
-- every session, so a frame number kept in the world - an effect's birth, the book's next cast, the Knights' next
-- coming - would lie far ahead after a game is loaded. Every Lua context reads the clock (run_frame) as a base kept in
-- the run's globals plus GameGetFrameNum(); init.lua moves the base on (run_clock_update) when it sees the frame count
-- start again, before the world's frame, so the effects updated in it read it right.

local BASE_VAR = "witch_notebook.clock_base" -- what run_frame adds to GameGetFrameNum()
local SEEN_VAR = "witch_notebook.clock_seen" -- the frame count when the clock was last looked after

local cached_at, cached_base -- the base read this frame: many effects read the clock every frame

function run_frame()
	local now = GameGetFrameNum()
	if now ~= cached_at then
		cached_at, cached_base = now, tonumber( GlobalsGetValue( BASE_VAR, "0" ) ) or 0
	end
	return cached_base + now
end

-- Every frame, before the world's (init.lua OnWorldPreUpdate), and as the witch comes into the world: a frame count
-- lower than the last one seen is a new session - the clock goes on from where the last one stopped, a frame on
function run_clock_update()
	local now = GameGetFrameNum()
	local seen = tonumber( GlobalsGetValue( SEEN_VAR, "0" ) ) or 0
	if now < seen then
		GlobalsSetValue( BASE_VAR, tostring( ( tonumber( GlobalsGetValue( BASE_VAR, "0" ) ) or 0 ) + seen + 1 - now ) )
		cached_at = nil
	end
	if now ~= seen then GlobalsSetValue( SEEN_VAR, tostring( now ) ) end
end
