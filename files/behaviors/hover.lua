-- A sphere floating in place (cast.lua: levitation without columns, the Pyreball Seal): it hangs where it was cast,
-- bobbing gently.

local e = GetUpdatedEntityID()
local vel = EntityGetFirstComponent( e, "VelocityComponent" )
if not vel then return end
local vx, vy = ComponentGetValue2( vel, "mVelocity" )
ComponentSetValue2( vel, "mVelocity", vx * 0.8, math.sin( GameGetFrameNum() * 0.08 + e ) * 6 )
