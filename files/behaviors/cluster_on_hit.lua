-- Cluster (resonances.lua): where the swollen shot ends it bursts into "witch_cluster" fragments of its element, thrown
-- up and outwards - a splash's short, weak drops
dofile_once( "mods/witch_notebook/files/behaviors/hit_lib.lua" )

local e = GetUpdatedEntityID()
local n = math.floor( hit_var( e, "witch_cluster" ) or 0 )
local element = hit_var( e, "witch_cluster_element" ) or "light"
if n <= 0 or not DICTIONARY_LOOKS[element] then return end
local shooter = hit_shooter( e )
local x, y = EntityGetTransform( e )
y = y - 2
for i = 1, n do
	local a = -math.pi / 2 + ( ( i - 0.5 ) / n - 0.5 ) * math.rad( 200 ) + Random( -100, 100 ) / 100 * 0.15
	local piece = EntityLoad( carrier_file( element, "splash" ), x, y )
	GameShootProjectile( shooter, x, y, x + math.cos( a ) * 100, y + math.sin( a ) * 100, piece, true )
	local proj = EntityGetFirstComponent( piece, "ProjectileComponent" )
	if proj then ComponentSetValue2( proj, "lifetime", Random( 16, 28 ) ) end
end
fx_burst( x, y, effect_color( element, 0.7 ), 16, 60, 0.4 )
