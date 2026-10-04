"""What the offline tests stand on: the mod's Lua run in LuaJIT (pip install lupa) with the Noita API stubbed.

Three grounds, from the lightest:
    load_reader()    what reads a drawing (templates, dictionary, recognizer, seal), nothing of the game
    load_mod()       the books as init.lua loads them, over stubs that record what the gui and the globals are asked
                     (STUBS); load_cast() - casting alone, over stubs that record what is made (CAST_STUBS)
    world_runtime()  a small fake world that runs (WORLD): entities with components, a caster, enemies, ground,
                     frames; the mod's files loaded as the game resolves them

The lists of the mod's files below are the only ones the tests and the tools keep: a file added to the mod is added here.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

from lupa import luajit21

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.normpath(os.path.join(HERE, ".."))
DATA = os.path.normpath(os.path.join(MOD, "..", "reference", "noita_data"))
sys.path.insert(0, os.path.join(MOD, "tools"))
import noita_components as NC  # noqa: E402

# what reads a drawing and makes its spell
SEAL_FILES = ["files/seal.lua", "files/seal_canon.lua", "files/seal_spell.lua"]
READER_FILES = ["files/templates.lua", "files/dictionary.lua", "files/recognizer.lua"] + SEAL_FILES
GRIMOIRE_FILE = "files/grimoire.lua"
# the books, in init.lua's order
MOD_FILES = ["files/templates.lua", "files/dictionary.lua", "files/sigils.lua", "files/recognizer.lua"] + SEAL_FILES + [
             "files/books.lua", "files/cast.lua", "files/ink.lua", "files/sheets.lua", "files/book_gfx.lua", "files/book_draw.lua", "files/page_turn.lua",
             "files/awaken.lua", "files/strokes.lua", "files/book_store.lua", "files/book_mouse.lua", "files/book_pages.lua",
             "files/quire_strap.lua", "files/quire_strap_world.lua", "files/spell_notes.lua", "files/test_book.lua", "files/notebook.lua"]
# the world's magic: what casts a page
WORLD_FILES = ["files/templates.lua", "files/dictionary.lua", "files/sigils.lua", "files/recognizer.lua",
               GRIMOIRE_FILE] + SEAL_FILES + ["files/cast.lua"]


def real_path(path):
    """the file a game path ("mods/witch_notebook/...", "data/...") stands for, or None"""
    path = path.replace("\\", "/")
    if path.startswith("mods/witch_notebook/"):
        return os.path.join(MOD, path[len("mods/witch_notebook/"):])
    if path.startswith("data/"):
        return os.path.join(DATA, path)
    return None


def read_game_file(path):
    real = real_path(path)
    return open(real, encoding="utf-8").read() if real and os.path.exists(real) else None


def read_mod_file(f):
    return open(os.path.join(MOD, f), encoding="utf-8").read()


# dofile_once of the mod's and the game's files, as the game resolves them
DOFILE = r'''
local done = {}
function dofile_once( path )
    if done[path] ~= nil then return end
    local text = py_read( path )
    if not text then error( "no such file: " .. path ) end
    done[path] = true
    assert( loadstring( text, path ) )()
end
function dofile( path ) return assert( loadstring( py_read( path ), path ) )() end
'''


def bare_runtime():
    """LuaJIT with dofile and dofile_once, nothing else"""
    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().py_read = read_game_file
    lua.execute(DOFILE)
    return lua


def load_reader(grimoire=True):
    """what reads a drawing; 'grimoire': with the wiki's seals to know it by"""
    lua = bare_runtime()
    lua.execute("function color_abgr_merge( r, g, b, a ) return 0 end function GameGetFrameNum() return 0 end")
    # the grimoire before the seal's files, as init.lua has it
    files = [f for f in READER_FILES if f not in SEAL_FILES] + ([GRIMOIRE_FILE] if grimoire else []) + SEAL_FILES
    for f in files:
        lua.execute(f'dofile_once( "mods/witch_notebook/{f}" )')
    return lua


# ---- the books: stubs that record ----

STUBS = r'''
function color_abgr_merge(r, g, b, a)
    return bit.bor(bit.band(r, 255), bit.lshift(bit.band(g, 255), 8), bit.lshift(bit.band(b, 255), 16), bit.lshift(bit.band(a, 255), 24))
end
images, names, settings, globals, loaded, added = {}, {}, {}, {}, {}, {}
local nid = 0
function ModImageMakeEditable(f, w, h) nid = nid + 1; images[nid] = {w = w, h = h, px = {}}; names[f] = nid; return nid, w, h end
function ModImageIdFromFilename(f) return names[f] or 0 end
function ModImageSetPixel(id, x, y, c)
    local im = images[id]
    assert(x >= 0 and y >= 0 and x < im.w and y < im.h, "pixel out of range " .. x .. "," .. y)
    im.px[y * im.w + x] = c
end
function ModImageGetPixel(id, x, y) local im = images[id]; return im and im.px[y * im.w + x] or 0 end
function ModSettingGet(k) return settings[k] end
function ModSettingSet(k, v) settings[k] = v end
function GlobalsGetValue(k, default) return globals[k] or default end
function GlobalsSetValue(k, v) globals[k] = v end

-- display like an ultrawide monitor: gui 853.5x360, mouse in internal resolution 1707x720
SW, SH = 853.5, 360
mouse = {0, 0}; left_down = false; left_just_down = false; right_down = false; right_just_down = false; key_b = false; pressed = {}
function InputGetMousePosOnScreen() return mouse[1] * 2, mouse[2] * 2 end
function InputIsMouseButtonDown(b) return (b == 1 and left_down) or (b == 2 and right_down) end
function InputIsMouseButtonJustDown(b) return (b == 2 and right_just_down) or (b == 1 and left_just_down) end
function InputIsKeyJustDown(k) return (k == 5 and key_b) or pressed[k] == true end
function GuiCreate() return {} end
function GuiStartFrame() end
function GuiGetScreenDimensions() return SW, SH end
function GuiText() end
function GuiImage() end
function GuiZSetForNextWidget() end
function GuiColorSetForNextWidget() end
function GuiGetTextDimensions(g, t) return #t * 4, 8 end
buttons = {} -- ids of the buttons clicked this frame
function GuiButton(g, id) return buttons[id] == true end
function GuiImageButton() return false end
function GuiGetPreviousWidgetInfo() return false, false, false, 0, 0, 0, 0 end
function EntityGetWithTag() return {1} end
book_owner = 1 -- the root of the spellbook's entity: the player (1) while it is in the inventory
function EntityGetRootEntity(e) return book_owner end
component_values = {}
function ComponentSetValue2(c, f, v) component_values[f] = v; if f == "enabled" then controls_enabled = v end end

-- player 1 -> inventory_quick 2 -> flask 3 holding the cells of witch inks in 'flask'
MATERIAL_IDS = { witch_ink = 42, witch_ink_blood = 43, witch_ink_azure = 44, witch_ink_clear = 45, witch_ink_gold = 46,
    witch_ink_oil = 47, witch_ink_swift = 48 }
flask = { witch_ink = 1000 }
function EntityGetAllChildren(e) if e == 1 then return {2} elseif e == 2 then return {3} end end
function EntityGetName(e) return e == 2 and "inventory_quick" or "" end
function EntityGetFirstComponentIncludingDisabled(e, name)
    if name == "MaterialInventoryComponent" then return e == 3 and 30 or nil end
    return 7
end
function EntityGetFirstComponent(e, name) return nil end -- (the witch's speed for the quire's strap: none)
function CellFactory_GetType(m) return MATERIAL_IDS[m] or 0 end
function ComponentGetValue2(c, f)
    if c == 30 and f == "count_per_material_type" then
        local t = {}
        for m, n in pairs(flask) do t[MATERIAL_IDS[m] + 1] = n end
        return t
    end
    if type(c) == "string" and c:sub(1, 5) == "book:" then return f == "name" and "witch_book" or c:sub(6) end
end
function AddMaterialInventoryMaterial(e, m, n) assert(MATERIAL_IDS[m], m); flask[m] = n end
function RemoveMaterialInventoryMaterial(e, m) if m then flask[m] = 0 else flask = {} end end
virtual = {}
function ModTextFileSetContent(f, c) virtual[f] = c end
function ModTextFileGetContent(f) return virtual[f] or py_read(f) end
function GameIsInventoryOpen() return false end
function EntityGetTransform() return 0, 0 end
function EntityLoad(f, x, y) loaded[#loaded + 1] = f; return 100 + #loaded end
run_flags = {}
function GameHasFlagRun(f) return run_flags[f] == true end
function GameAddFlagRun(f) run_flags[f] = true end
function EntityAddComponent2(e, t, v) added[#added + 1] = {entity = e, type = t, values = v}; return 50 + #added end
function RemoveFlagPersistent() end
function EntityRefreshSprite() end
function GamePickUpInventoryItem() end
function GameGetFrameNum() return 1 end
function print() end
-- the books: every book entity is the Spellbook unless a test says otherwise (book_keys[entity] = "quire")
book_keys = {}
function EntityGetComponentIncludingDisabled(e, t)
    if t == "VariableStorageComponent" and book_keys[e] then return { "book:" .. book_keys[e] } end
    return {}
end
function EntityHasTag() return false end
printed_important = {}
function GamePrintImportant(a, b) printed_important[#printed_important + 1] = a .. " | " .. (b or "") end
'''

# a tiny entity world for casting sheets (cast.lua): projectiles with components holding values
CAST_STUBS = r'''
entities, comps, shots, killed, printed = {}, {}, {}, {}, {}
local next_id = 1000
local function new_comp(e, t, values)
    next_id = next_id + 1
    comps[next_id] = { entity = e, type = t, values = values }
    entities[e] = entities[e] or {}
    table.insert(entities[e], next_id)
    return next_id
end
function EntityLoad(file, x, y)
    next_id = next_id + 1; local e = next_id
    entities[e] = {}
    new_comp(e, "ProjectileComponent", { damage = 1, lifetime = 100, knockback_force = 0, explosion_radius = 10 })
    new_comp(e, "VelocityComponent", { mVelocity = {100, 0}, gravity_y = 400, gravity_x = 0, air_friction = 0 })
    shots[#shots + 1] = { entity = e, file = file, x = x, y = y }
    return e
end
function GameShootProjectile(shooter, x, y, tx, ty, e)
    local d = math.sqrt((tx - x) ^ 2 + (ty - y) ^ 2)
    for _, c in ipairs(entities[e]) do
        if comps[c].type == "VelocityComponent" then comps[c].values.mVelocity = { (tx - x) / d * 100, (ty - y) / d * 100 } end
    end
end
function EntityGetFirstComponentIncludingDisabled(e, t)
    for _, c in ipairs(entities[e] or {}) do if comps[c].type == t then return c end end
end
function EntityGetComponentIncludingDisabled(e, t)
    local out = {}
    for _, c in ipairs(entities[e] or {}) do if comps[c].type == t then out[#out + 1] = c end end
    return out
end
function ComponentGetValue2(c, f)
    local v = comps[c].values[f]
    if type(v) == "table" then return v[1], v[2] end
    return v
end
function ComponentSetValue2(c, f, a, b)
    if b ~= nil then comps[c].values[f] = { a, b } else comps[c].values[f] = a end
end
function ComponentObjectGetValue2(c, o, f) return comps[c].values[f] end
function ComponentObjectSetValue2(c, o, f, v) comps[c].values[f] = v end
function EntityGetTransform(e) return 0, 0 end
function EntityKill(e) killed[#killed + 1] = e end
function GamePrint(t) printed[#printed + 1] = t end
function SetRandomSeed(a, b) math.randomseed(a * 7919 + b) end
function Random(a, b) return math.random(a, b) end
function EntityAddComponent2(e, t, values)
    local v = {}
    for k, x in pairs(values or {}) do v[k] = x end
    return new_comp(e, t, v)
end
globals = {}
function GlobalsGetValue(k, default) return globals[k] or default end
-- the spellbook with 'spell' on its active page
function make_book(spell, key)
    next_id = next_id + 1; local e = next_id
    entities[e] = {}
    new_comp(e, "VariableStorageComponent", { name = "witch_notebook_next_cast", value_int = 0 })
    if key and key ~= "book" then new_comp(e, "VariableStorageComponent", { name = "witch_book", value_string = key }) end
    globals[book_var(key or "book", "active_spell")] = spell
    return e
end
-- what casting touches besides projectiles: the seal flaring up in the air, the wave of dispersion
function EntityCreateNew(name) next_id = next_id + 1; local e = next_id; entities[e] = {}; return e end
function EntitySetTransform() end
function GameCreateCosmeticParticle() end
function GameCreateParticle() end
function GamePlaySound() end
function GlobalsSetValue(k, v) globals[k] = v end
function EntityGetFirstComponent(e, t) return EntityGetFirstComponentIncludingDisabled(e, t) end
function EntityGetComponent(e, t) local l = EntityGetComponentIncludingDisabled(e, t) if #l == 0 then return nil end return l end
function Raytrace() return false end
function EntityGetInRadiusWithTag() return {} end -- no creatures here: Detection finds no one
RaytraceSurfaces, RaytracePlatforms = Raytrace, Raytrace
function GamePrintImportant() end
function EntityGetIsAlive(e) return entities[e] ~= nil end
function make_controls(ax, ay, mx, my)
    next_id = next_id + 1; local e = next_id
    entities[e] = {}
    return new_comp(e, "ControlsComponent", { mAimingVectorNormalized = {ax, ay}, mMousePosition = {mx, my} }), e
end
'''


def load_mod():
    lua = bare_runtime()
    lua.execute(STUBS)
    for f in MOD_FILES:
        lua.execute(read_mod_file(f))
    lua.execute("sigils_create_images() book_gfx_create()")
    return lua


def load_cast():
    lua = bare_runtime()
    lua.execute(CAST_STUBS)
    for f in ["files/dictionary.lua", "files/cast.lua"]:
        lua.execute(read_mod_file(f))
    return lua


# ---- a fake world that runs ----

def materials():
    names = set()
    for f in (os.path.join(DATA, "data", "materials.xml"), os.path.join(MOD, "files", "materials.xml")):
        for m in re.finditer(r'<CellData(?:Child)?\s[^>]*?name="([^"]+)"', open(f, encoding="utf-8", errors="replace").read(), re.S):
            names.add(m.group(1))
    return names


MATERIALS = materials()
FIELDS = NC.known_components()


def parse_entity(text):
    """-> (tags, [(type, attrs)]) of an entity file's text, its Base files merged in"""
    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        return "", []
    comps = []

    def walk(node):
        for child in node:
            if child.tag == "Base":
                f = real_path(child.attrib.get("file", ""))
                if f and os.path.exists(f):
                    _, base = parse_entity(open(f, encoding="utf-8", errors="replace").read())
                    comps.extend(base)
                walk(child)
            elif child.tag.endswith("Component"):
                attrs = dict(child.attrib)
                for sub in child:
                    for a, v in sub.attrib.items():
                        attrs[sub.tag + "." + a] = v
                comps.append((child.tag, attrs))
    walk(root)
    return root.attrib.get("tags", ""), comps


WORLD = r'''
W = { entities = {}, comps = {}, next_id = 1, next_comp = 1, frame = 1000, globals = {}, errors = {}, made = {},
	added = {}, particles = 0, prints = {}, current = 0, vfiles = {} }
GROUND = 10

local function err( msg ) W.errors[#W.errors + 1] = msg end
function note_error( msg ) err( msg ) end

-- files
local cache = {}
function map_path( path ) return py_path( path ) end
function do_file( path )
	local chunk = cache[path]
	if not chunk then
		local real = map_path( path )
		if not real or not py_exists( real ) then error( "no such file: " .. path ) end
		chunk = assert( loadfile( real ) )
		cache[path] = chunk
	end
	return chunk()
end
local once = {}
function dofile_once( path )
	if once[path] == nil then once[path] = { do_file( path ) } end
	return unpack( once[path] )
end
function dofile( path ) return do_file( path ) end
function ModTextFileGetContent( path )
	if W.vfiles[path] then return W.vfiles[path] end
	return py_read( map_path( path ) )
end
function ModTextFileSetContent( path, text ) W.vfiles[path] = text end
function ModImageMakeEditable( path, w, h ) W.vfiles[path] = "image"; return 1, w, h end
function ModImageSetPixel() end
function file_exists( path )
	if W.vfiles[path] then return true end
	local real = map_path( path )
	return real ~= nil and py_exists( real )
end

-- Model the engine's texture cache for both transient and pooled gas sprites.
local sprite_files = {}
local function check_sprite( file )
	if not sprite_files[file] then
		if not file_exists( file ) then err( "sprite: no such file " .. file )
		else sprite_files[file] = true end
	end
end

-- entities
function EntityCreateNew( name )
	local id = W.next_id
	W.next_id = id + 1
	W.entities[id] = { id = id, name = name or "", tags = {}, comps = {}, children = {}, parent = 0, x = 0, y = 0, alive = true, file = "" }
	return id
end
local function ent( id ) return W.entities[id] end
function EntityGetIsAlive( id ) return ent( id ) ~= nil and ent( id ).alive end
function EntitySetTransform( id, x, y, r, sx, sy )
	local e = ent( id )
	if not e then return err( "EntitySetTransform on a missing entity" ) end
	e.x, e.y = x, y or 0
	e.sx, e.sy = sx or 1, sy or 1 -- left out, the scale goes back to 1 as in the game
	if x ~= x or ( y or 0 ) ~= ( y or 0 ) then err( "EntitySetTransform NaN" ) end
end
EntityApplyTransform = EntitySetTransform
function EntityGetTransform( id )
	local e = ent( id )
	if not e then return 0, 0, 0, 1, 1 end
	return e.x, e.y, 0, e.sx or 1, e.sy or 1
end
function EntityGetName( id ) return ent( id ) and ent( id ).name or "" end
function EntitySetName( id, n ) if ent( id ) then ent( id ).name = n end end
function EntityGetFilename( id ) return ent( id ) and ent( id ).file or "" end
function EntityAddTag( id, t ) if ent( id ) then ent( id ).tags[t] = true end end
function EntityRemoveTag( id, t ) if ent( id ) then ent( id ).tags[t] = nil end end
function EntityHasTag( id, t ) return ent( id ) ~= nil and ent( id ).tags[t] == true end
function EntityGetTags( id )
	local e = ent( id )
	if not e then return nil end
	local out = {}
	for t in pairs( e.tags ) do out[#out + 1] = t end
	return table.concat( out, "," )
end
function EntityAddChild( parent, child )
	if not ent( parent ) or not ent( child ) then return err( "EntityAddChild on a missing entity" ) end
	table.insert( ent( parent ).children, child )
	ent( child ).parent = parent
end
function EntityGetAllChildren( id )
	local e = ent( id )
	if not e then return nil end
	local out = {}
	for _, c in ipairs( e.children ) do if EntityGetIsAlive( c ) then out[#out + 1] = c end end
	return out
end
function EntityGetParent( id ) return ent( id ) and ent( id ).parent or 0 end
function EntityGetRootEntity( id )
	local e = ent( id )
	while e and e.parent ~= 0 and ent( e.parent ) do e = ent( e.parent ) end
	return e and e.id or id
end
function EntityRemoveFromParent( id ) if ent( id ) then ent( id ).parent = 0 end end
function EntityRefreshSprite( id, cid )
	local c = W.comps[cid]
	if not c or c.entity ~= id or c.type ~= "SpriteComponent" then err( "EntityRefreshSprite on a missing sprite" ) end
end

local function run_removed( id )
	for _, cid in ipairs( ent( id ).comps ) do
		local c = W.comps[cid]
		if c and c.type == "LuaComponent" and c.values.execute_on_removed then run_script( id, c.values.script_source_file ) end
	end
end
function EntityKill( id )
	local e = ent( id )
	if not e or not e.alive then return end
	e.alive = false
	run_removed( id )
	for _, c in ipairs( e.children ) do EntityKill( c ) end
end

function EntityAddComponent2( id, kind, values )
	if not ent( id ) then return err( "EntityAddComponent2 on a missing entity (" .. kind .. ")" ) end
	local cid = W.next_comp
	W.next_comp = cid + 1
	local v = {}
	for k, x in pairs( values or {} ) do v[k] = x end
	if kind == "SpriteComponent" and v.image_file and ( v._tags or "" ):find( "witch_fluid_fire_", 1, true ) then
		check_sprite( v.image_file )
	end
	W.comps[cid] = { type = kind, entity = id, values = v, enabled = true }
	table.insert( ent( id ).comps, cid )
	W.added[#W.added + 1] = { kind, values or {} }
	return cid
end
function EntityAddComponent( id, kind, values ) return EntityAddComponent2( id, kind, values ) end
function EntityRemoveComponent( id, cid )
	local e = ent( id )
	if not e then return end
	for i, c in ipairs( e.comps ) do if c == cid then table.remove( e.comps, i ) break end end
	W.comps[cid] = nil
end
local function comps_of( id, kind, disabled, tag )
	local e = ent( id )
	if not e then return nil end
	local out = {}
	for _, cid in ipairs( e.comps ) do
		local c = W.comps[cid]
		if c and c.type == kind and ( disabled or c.enabled )
			and ( not tag or tag == "" or ( "," .. ( c.values._tags or "" ) .. "," ):find( "," .. tag .. ",", 1, true ) ) then
			out[#out + 1] = cid
		end
	end
	if #out == 0 then return nil end
	return out
end
function EntityGetComponent( id, kind, tag ) return comps_of( id, kind, false, tag ) end
function EntityGetComponentIncludingDisabled( id, kind, tag ) return comps_of( id, kind, true, tag ) end
function EntityGetFirstComponent( id, kind, tag ) local l = comps_of( id, kind, false, tag ) return l and l[1] end
function EntityGetFirstComponentIncludingDisabled( id, kind, tag ) local l = comps_of( id, kind, true, tag ) return l and l[1] end
function EntitySetComponentIsEnabled( id, cid, on ) if W.comps[cid] then W.comps[cid].enabled = on end end
function ComponentGetIsEnabled( cid ) return W.comps[cid] ~= nil and W.comps[cid].enabled end

DEFAULTS = { mVelocity = { 0, 0 }, mMousePosition = { 150, -20 }, mAimingVectorNormalized = { 1, 0 }, name = "", value_string = "",
	value_float = 0, value_int = 0, value_bool = false, herd_id = 1, fly_time_max = 3, mFlyingTimeLeft = 3, pixel_gravity = 350,
	hp = 4, max_hp = 4, lifetime = 60, mWhoShot = 0, count_per_material_type = {}, special_scale_x = 1, special_scale_y = 1,
	aabb_min_x = -3, aabb_max_x = 3, aabb_min_y = -10, aabb_max_y = 2, mana = 10, mana_max = 100, damage = 0, frames = 60,
	gravity_y = 0, gravity_x = 0, air_friction = 0, knockback_force = 0, circle_radius = 10, mActiveItem = 0,
	damage_game_effect_entities = "", on_death_emit_particle_count = 10 }
local function unpack_value( v )
	if type( v ) == "table" and ( v[1] ~= nil and #v <= 4 ) and type( v[1] ) == "number" and v.__list == nil then return unpack( v ) end
	return v
end
function ComponentGetValue2( cid, field )
	local c = W.comps[cid]
	if not c then err( "ComponentGetValue2 on a missing component: " .. tostring( field ) ); return nil end
	local v = c.values[field]
	if v == nil then v = DEFAULTS[field] end
	if v == nil then
		if field:match( "^mButtonDown" ) or field:match( "^is_" ) then return false end
		return 0
	end
	if field == "count_per_material_type" then return v end
	return unpack_value( v )
end
function ComponentSetValue2( cid, field, a, b, ... )
	local c = W.comps[cid]
	if not c then return err( "ComponentSetValue2 on a missing component: " .. tostring( field ) ) end
	if a == nil then err( "ComponentSetValue2 " .. c.type .. "." .. field .. " = nil" ) end
	if type( a ) == "number" and a ~= a then err( "ComponentSetValue2 " .. c.type .. "." .. field .. " = NaN" ) end
	if c.type == "SpriteComponent" and field == "image_file" and ( c.values._tags or "" ):find( "witch_fluid_fire_", 1, true ) then
		check_sprite( a )
	end
	if b ~= nil then c.values[field] = { a, b, ... } else c.values[field] = a end
end
function ComponentObjectGetValue2( cid, object, field ) local c = W.comps[cid] return c and c.values[object .. "." .. field] or 0 end
function ComponentObjectSetValue2( cid, object, field, v ) local c = W.comps[cid] if c then c.values[object .. "." .. field] = v end end
function ComponentGetValue( cid, field ) return tostring( ComponentGetValue2( cid, field ) ) end
function ComponentSetValue( cid, field, v ) ComponentSetValue2( cid, field, v ) end

function EntityLoad( file, x, y )
	if not file_exists( file ) then err( "EntityLoad: no such file " .. tostring( file ) ) end
	local id = EntityCreateNew( "" )
	local e = ent( id )
	e.x, e.y, e.file = x or 0, y or 0, file
	local tags, comps = py_entity( W.vfiles[file] or py_read( map_path( file ) ) or "" )
	for t in tostring( tags ):gmatch( "[^,]+" ) do e.tags[t] = true end
	for i = 1, #comps do
		local kind, attrs = comps[i][1], comps[i][2]
		local values = {}
		for k, v in pairs( attrs ) do
			local n = tonumber( v )
			if n ~= nil then values[k] = n elseif v == "true" then values[k] = true else values[k] = v end
		end
		if kind == "LuaComponent" and ( values.execute_on_removed == 1 ) then values.execute_on_removed = true end
		local cid = EntityAddComponent2( id, kind, values )
	end
	W.made[#W.made + 1] = file
	return id
end

-- the world
function in_radius( x, y, r, tag )
	local out = {}
	for id, e in pairs( W.entities ) do
		if e.alive and ( tag == nil or e.tags[tag] ) and ( e.x - x ) ^ 2 + ( e.y - y ) ^ 2 <= r * r then out[#out + 1] = id end
	end
	table.sort( out )
	return out
end
function EntityGetInRadiusWithTag( x, y, r, tag ) return in_radius( x, y, r, tag ) end
function EntityGetInRadius( x, y, r ) return in_radius( x, y, r, nil ) end
function EntityGetWithTag( tag ) return in_radius( 0, 0, 1e9, tag ) end
function EntityGetClosestWithTag( x, y, tag ) local l = in_radius( x, y, 1e9, tag ) return l[1] or 0 end
function EntityGetWithName( name ) for id, e in pairs( W.entities ) do if e.alive and e.name == name then return id end end return 0 end
local function ground_hit( x1, y1, x2, y2 )
	if ( y1 - GROUND ) * ( y2 - GROUND ) <= 0 and y1 ~= y2 then
		local t = ( GROUND - y1 ) / ( y2 - y1 )
		return true, x1 + ( x2 - x1 ) * t, GROUND
	end
	return false, x2, y2
end
Raytrace = ground_hit
RaytraceSurfaces = ground_hit
RaytracePlatforms = ground_hit
RaytraceSurfacesAndLiquiform = ground_hit
function DoesWorldExistAt() return true end

-- the game
function GameGetFrameNum() return W.frame end
function GamePrint( t ) W.prints[#W.prints + 1] = t end
function GamePrintImportant( a, b ) W.prints[#W.prints + 1] = a end
function GamePlaySound( bank, event ) if not file_exists( bank:gsub( "%.snd$", ".bank" ) ) then end end
function GameEntityPlaySound() end
local function check_material( name, where )
	if type( name ) ~= "string" or not py_material( name ) then err( where .. ": unknown material " .. tostring( name ) ) end
end
function GameCreateParticle( m, x, y, n, vx, vy, just_visual )
	check_material( m, "GameCreateParticle" )
	W.particles = W.particles + 1
end
function GameCreateCosmeticParticle( m, x, y, n, vx, vy, color, lmin, lmax, force, front, collide, randomize, gx, gy )
	check_material( m, "GameCreateCosmeticParticle" )
	if x ~= x or y ~= y then err( "cosmetic particle at NaN" ) end
	if type( color ) ~= "number" then err( "cosmetic particle color is " .. type( color ) ) end
	W.particles = W.particles + 1
end
function GameCreateSpriteForXFrames( file )
	check_sprite( file )
end
function GameShootProjectile( shooter, x, y, tx, ty, proj )
	local p = EntityGetFirstComponent( proj, "ProjectileComponent" )
	if p then ComponentSetValue2( p, "mWhoShot", shooter ) end
	local v = EntityGetFirstComponent( proj, "VelocityComponent" )
	local dx, dy = tx - x, ty - y
	local d = math.max( 1, math.sqrt( dx * dx + dy * dy ) )
	local speed = p and ( W.comps[p].values.speed_min or 100 ) or 100
	if v then ComponentSetValue2( v, "mVelocity", dx / d * speed, dy / d * speed ) end
end
function LoadGameEffectEntityTo( target, file )
	if not file_exists( file ) then err( "LoadGameEffectEntityTo: no such file " .. file ) end
	local id = EntityLoad( file, 0, 0 )
	EntityAddChild( target, id )
	return id
end
function GetGameEffectLoadTo( target, name ) return 0, 0 end
function GameGetGameEffect( target, name ) return 0 end
function GameGetGameEffectCount() return 0 end
function EntityRemoveStainStatusEffect( id, name ) if type( name ) ~= "string" then err( "EntityRemoveStainStatusEffect: bad name" ) end end
function EntityRemoveIngestionStatusEffect() end
function EntityInflictDamage( id, amount, kind, desc, ragdoll, ix, iy, who, x, y, knock )
	if type( amount ) ~= "number" or amount ~= amount then err( "EntityInflictDamage: bad amount" ) end
	if type( kind ) ~= "string" or not kind:match( "^DAMAGE_" ) then err( "EntityInflictDamage: bad type " .. tostring( kind ) ) end
	W.damage = ( W.damage or 0 ) + amount
end
function GameRegenItemActionsInPlayer() end
function GameGetAllInventoryItems( id ) return INVENTORY or {} end
function GameDropAllItems() end
function EntityConvertToMaterial( id, m ) check_material( m, "EntityConvertToMaterial" ) end
function GameSetCameraFree() end
function GameSetCameraPos() end
function GameGetCameraPos() return 0, 0 end
function GameScreenshake() end
function CellFactory_GetType( m ) check_material( m, "CellFactory_GetType" ) return 3 end
function CellFactory_GetName( id ) return "water" end
function AddMaterialInventoryMaterial( id, m, n ) check_material( m, "AddMaterialInventoryMaterial" ) end
function RemoveMaterialInventoryMaterial() end
function GetMaterialInventoryMainMaterial() return 3 end
function GlobalsGetValue( k, d ) local v = W.globals[k] if v == nil then return d or "" end return v end
function GlobalsSetValue( k, v ) if type( v ) ~= "string" then err( "GlobalsSetValue " .. k .. ": not a string" ) end W.globals[k] = v end
local seed = 1
function SetRandomSeed( a, b ) seed = math.floor( math.abs( a * 7 + b * 13 ) ) % 2147483647 + 1 end
function Random( a, b )
	seed = ( seed * 16807 ) % 2147483647
	local t = seed / 2147483647
	if a == nil then return t end
	if b == nil then return math.floor( t * a + 0.5 ) end
	if b < a then err( "Random(" .. a .. ", " .. b .. ")" ) end
	return math.floor( a + t * ( b - a ) + 0.5 )
end
function Randomf( a, b ) local t = Random() if a == nil then return t end if b == nil then return t * a end return a + t * ( b - a ) end
function PhysicsSetStatic( id, static ) if ent( id ) then ent( id ).static = static end end
function PhysicsApplyForceOnArea( fn, ignore, x0, y0, x1, y1 )
	local bx, by = ( x0 + x1 ) / 2, ( y0 + y1 ) / 2
	local rx, ry, fx, fy, fa = fn( 99999, 1.5, bx, by, 0, 0, 0 )
	if type( fx ) ~= "number" or type( fy ) ~= "number" then err( "PhysicsApplyForceOnArea: the function returned no force" ) end
end
function StringToHerdId( name ) return 5 end
function HerdIdToString( id ) return "player" end
function GameTextGetTranslatedOrNot( t ) return t end
function GameTextGet( t ) return t end
W.flags = {}
function GameAddFlagRun( f ) W.flags[f] = true end
function GameHasFlagRun( f ) return W.flags[f] == true end
function ModSettingGet() return nil end
function GetUpdatedEntityID() return W.current end
function GetUpdatedComponentID() return 0 end
function print_error( t ) err( t ) end

function run_script( id, path )
	if type( path ) ~= "string" then return end
	if not path:match( "^mods/witch_notebook/" ) then return end
	local was = W.current
	W.current = id
	local ok, e = xpcall( function() do_file( path ) end, debug.traceback )
	W.current = was
	if not ok then err( path .. ": " .. tostring( e ) ) end
end

-- creatures fall and stand on the ground, projectiles fly
local function physics()
	for id, e in pairs( W.entities ) do
		if e.alive then
			local cd = EntityGetFirstComponent( id, "CharacterDataComponent" )
			local vel = EntityGetFirstComponent( id, "VelocityComponent" )
			if cd then
				local vx, vy = ComponentGetValue2( cd, "mVelocity" )
				vy = vy + 350 / 60
				e.x, e.y = e.x + vx / 60, e.y + vy / 60
				if e.y > GROUND - 4 then e.y, vy = GROUND - 4, 0 end
				ComponentSetValue2( cd, "mVelocity", vx * 0.9, vy )
			elseif vel then
				local vx, vy = ComponentGetValue2( vel, "mVelocity" )
				e.x, e.y = e.x + vx / 60, e.y + vy / 60
			end
		end
	end
end

function simulate( frames )
	for f = 1, frames do
		W.frame = W.frame + 1
		physics()
		local ids = {}
		for id, e in pairs( W.entities ) do if e.alive then ids[#ids + 1] = id end end
		table.sort( ids )
		for _, id in ipairs( ids ) do
			local e = W.entities[id]
			local list = {}
			for _, cid in ipairs( e.comps ) do list[#list + 1] = cid end
			for _, cid in ipairs( list ) do
				local c = W.comps[cid]
				if c and c.enabled and e.alive then
					if c.type == "LuaComponent" then
						local n = c.values.execute_every_n_frame or 1
						if n > 0 and W.frame % n == 0 and not c.values.execute_on_removed then run_script( id, c.values.script_source_file ) end
					elseif c.type == "LifetimeComponent" then
						c.values.lifetime = ( c.values.lifetime or 0 ) - 1
						if c.values.lifetime <= 0 then EntityKill( id ) end
					elseif c.type == "ProjectileComponent" then
						local lt = c.values.lifetime or 60
						if lt > 0 then
							c.values.lifetime = lt - 1
							if lt - 1 <= 0 then EntityKill( id ) end
						end
					end
				end
			end
		end
	end
end

-- a small world: the caster on flat ground, three enemies, things to find
function make_world()
	W.entities, W.comps = {}, {}
	W.next_id = 1
	local player = EntityCreateNew( "player" )
	EntitySetTransform( player, 0, GROUND - 4 )
	for _, t in ipairs( { "player_unit", "mortal", "hittable" } ) do EntityAddTag( player, t ) end
	EntityAddComponent2( player, "ControlsComponent", { mMousePosition = { 150, -20 }, mAimingVectorNormalized = { 0.99, -0.13 } } )
	EntityAddComponent2( player, "CharacterDataComponent", {} )
	EntityAddComponent2( player, "CharacterPlatformingComponent", {} )
	EntityAddComponent2( player, "DamageModelComponent", {} )
	EntityAddComponent2( player, "GenomeDataComponent", {} )
	EntityAddComponent2( player, "HitboxComponent", {} )
	local flask = EntityCreateNew( "flask" )
	EntityAddTag( flask, "potion" )
	EntityAddComponent2( flask, "MaterialInventoryComponent", { count_per_material_type = { [4] = 500 } } )
	EntityAddChild( player, flask )
	local empty = EntityCreateNew( "empty flask" )
	EntityAddTag( empty, "potion" )
	EntityAddComponent2( empty, "MaterialInventoryComponent", {} )
	EntityAddChild( player, empty )
	local wand = EntityCreateNew( "wand" )
	EntityAddTag( wand, "wand" )
	EntityAddComponent2( wand, "AbilityComponent", {} )
	EntityAddChild( player, wand )
	INVENTORY = { flask, empty, wand }
	EntityAddComponent2( player, "Inventory2Component", { mActiveItem = flask } )
	ENEMIES = {}
	for i, pos in ipairs( { { 120, GROUND - 4 }, { 150, -20 }, { 40, GROUND - 4 } } ) do
		local e = EntityCreateNew( "$animal_zombie" )
		EntitySetTransform( e, pos[1], pos[2] )
		for _, t in ipairs( { "enemy", "mortal", "hittable", "homing_target" } ) do EntityAddTag( e, t ) end
		EntityAddComponent2( e, "CharacterDataComponent", {} )
		EntityAddComponent2( e, "DamageModelComponent", { hp = 2, max_hp = 2 } )
		EntityAddComponent2( e, "GenomeDataComponent", { herd_id = 2 } )
		EntityAddComponent2( e, "HitboxComponent", {} )
		EntityAddComponent2( e, "AnimalAIComponent", {} )
		EntityAddComponent2( e, "SpriteComponent", {} )
		ENEMIES[i] = e
	end
	local chest = EntityCreateNew( "chest" )
	EntitySetTransform( chest, 200, GROUND - 3 )
	EntityAddTag( chest, "chest" )
	EntityAddTag( chest, "item_pickup" )
	local gold = EntityCreateNew( "gold" )
	EntitySetTransform( gold, 170, GROUND - 2 )
	EntityAddTag( gold, "gold_nugget" )
	EntityAddComponent2( gold, "VelocityComponent", {} )
	local shot = EntityCreateNew( "enemy projectile" )
	EntitySetTransform( shot, 12, GROUND - 8 )
	EntityAddTag( shot, "projectile" )
	EntityAddComponent2( shot, "ProjectileComponent", { mWhoShot = ENEMIES[1], lifetime = 500 } )
	EntityAddComponent2( shot, "VelocityComponent", { mVelocity = { -60, 0 } } )
	PLAYER = player
	return player
end
'''


def bare_world(files=WORLD_FILES):
    """the fake world's Lua (WORLD) with the mod's files loaded; make_world() puts the caster and the rest in it"""
    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.py_path = real_path
    g.py_exists = lambda p: p is not None and os.path.exists(p)
    g.py_read = lambda p: open(p, encoding="utf-8", errors="replace").read() if p and os.path.exists(p) else None
    g.py_material = lambda m: m in MATERIALS

    def entity(text):
        tags, comps = parse_entity(text or "")
        return tags, lua.table_from([lua.table_from([kind, lua.table_from(attrs)]) for kind, attrs in comps])

    g.py_entity = entity
    lua.execute(WORLD)
    for f in files:
        lua.execute(f'dofile_once( "mods/witch_notebook/{f}" )')
    return lua


def world_runtime():
    """the world made, its ground far below; W.hits and W.real_fire record the damage dealt and the real fire made"""
    lua = bare_world()
    lua.execute("make_world(); GROUND = 10000; W.hits = {}; W.real_fire = 0; W.max_particles = 0")
    lua.execute('''
        local damage = EntityInflictDamage
        function EntityInflictDamage(id, amount, kind, desc, ragdoll, ix, iy, who, x, y, knock)
            W.hits[#W.hits + 1] = {id = id, who = who, kind = kind, amount = amount, frame = W.frame}
            damage(id, amount, kind, desc, ragdoll, ix, iy, who, x, y, knock)
        end
        local particle = GameCreateParticle
        function GameCreateParticle(m, x, y, n, vx, vy, visual)
            if m == "fire" and not visual then W.real_fire = W.real_fire + n end
            particle(m, x, y, n, vx, vy, visual)
        end
    ''')
    return lua


def cast_page(lua, key, tx=200, ty=-40, legacy=False):
    lua.globals().TEST_KEY = key
    lua.globals().TEST_TX, lua.globals().TEST_TY = tx, ty
    lua.globals().TEST_LEGACY = legacy
    return lua.execute('''
        local data = seal_page_data({named = TEST_KEY, precision = 1, stability = 1})
        if TEST_LEGACY then data = data:gsub(";manifest=[%w_]+", "") end
        return cast_spell(PLAYER, parse_spell_data(data), 0, -40, 1, 0, TEST_TX, TEST_TY, W.frame, nil)[1]
    ''')


def freeze_enemies(lua, positions):
    for i, (x, y) in enumerate(positions, 1):
        lua.globals().ENEMY_I, lua.globals().ENEMY_X, lua.globals().ENEMY_Y = i, x, y
        lua.execute('''
            local id = ENEMIES[ENEMY_I]
            EntitySetTransform(id, ENEMY_X, ENEMY_Y)
            EntityRemoveComponent(id, EntityGetFirstComponent(id, "CharacterDataComponent"))
        ''')


def wall(lua, at=80):
    lua.globals().WALL_X = at
    lua.execute('''
        function RaytraceSurfaces(x1, y1, x2, y2)
            if (x1 - WALL_X) * (x2 - WALL_X) <= 0 and x1 ~= x2 then
                local t = (WALL_X - x1) / (x2 - x1)
                return true, WALL_X, y1 + (y2 - y1) * t
            end
            return false, x2, y2
        end
        RaytraceSurfacesAndLiquiform = RaytraceSurfaces
    ''')
