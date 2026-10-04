-- LuaComponent of the witch's books (books.lua; entities/spellbook.xml, palm_quire.xml, great_tome.xml), runs every
-- frame while a book is held: a left click casts the seal on its active page (see cast.lua).
-- Spiraling Flame then follows held Fire in effects/flame.lua until release.
dofile_once( "mods/witch_notebook/files/dictionary.lua" )
dofile_once( "mods/witch_notebook/files/cast.lua" )

local item = GetUpdatedEntityID()
local holder = EntityGetRootEntity( item )
if holder == item then return end
-- disabled while the book is open, so drawing doesn't cast
local controls = EntityGetFirstComponent( holder, "ControlsComponent" )
if not controls then return end
local frame = GameGetFrameNum()
if ComponentGetValue2( controls, "mButtonFrameFire" ) == frame then
	spellbook_use( item, holder, controls, frame )
end
