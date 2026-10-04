-- Runs a seal's lasting magic every frame (see lib.lua): the entity's kind names the file with its modes
dofile_once( "mods/witch_notebook/files/effects/lib.lua" )
dofile_once( "mods/witch_notebook/files/effects/profiler.lua" )

local e = GetUpdatedEntityID()
local profile = EffectProfiler.begin_update()
local started = profile and profile:begin()
local p = effect_params( e )
if profile then profile:finish( "params", started ) end
started = profile and profile:begin()
if not EFFECT_MODES[p.kind or ""] then dofile_once( EFFECTS .. ( p.kind or "none" ) .. ".lua" ) end
if profile then profile:finish( "load", started ) end
local modes = EFFECT_MODES[p.kind or ""]
local run = modes and modes[p.mode or ""]
if not run then
	EntityKill( e )
	EffectProfiler.end_update( profile )
	return
end
if ( p.born or 0 ) == 0 then
	p.born = GameGetFrameNum()
	effect_set( e, "born", p.born )
end
local x, y = EntityGetTransform( e )
run( e, p, effect_age( p ), x, y, profile )
started = profile and profile:begin()
if p.reveal == 1 and EntityGetIsAlive( e ) then effect_light_visibility( e, p ) end
if profile then profile:finish( "light", started ) end
-- the Sign of Mimicry: magic that takes hold of a place drifts after the caster's cursor
if p.mimic == 1 and p.kind == "zone" and EntityGetIsAlive( e ) then
	local owner = effect_owner( p )
	local controls = owner and EntityGetFirstComponent( owner, "ControlsComponent" )
	if controls then
		local mx, my = ComponentGetValue2( controls, "mMousePosition" )
		EntitySetTransform( e, x + ( mx - x ) * 0.04, y + ( my - y ) * 0.04 )
	end
end
EffectProfiler.end_update( profile )
