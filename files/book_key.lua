-- The configurable key used to open or close a book. Values are Noita keycodes (data/scripts/debug/keycodes.lua).
-- settings.lua keeps its own copy of KEY_NAMES (it can't load this file); change both together.
BOOK_OPEN_KEY_SETTING = "witch_notebook.open_key"
local DEFAULT_OPEN_KEY = 5 -- B
local KEY_NAMES = {}
for code = 4, 29 do KEY_NAMES[code] = string.char( string.byte( "A" ) + code - 4 ) end
for code = 30, 38 do KEY_NAMES[code] = tostring( code - 29 ) end
KEY_NAMES[39] = "0"
local OTHER_KEYS = {
	[40] = "Enter", [42] = "Backspace", [43] = "Tab", [44] = "Space",
	[45] = "-", [46] = "=", [47] = "[", [48] = "]", [49] = "Backslash",
	[51] = ";", [52] = "'", [53] = "`", [54] = ",", [55] = ".", [56] = "/",
	[57] = "Caps Lock", [70] = "Print Screen", [71] = "Scroll Lock", [72] = "Pause",
	[73] = "Insert", [74] = "Home", [75] = "Page Up", [76] = "Delete", [77] = "End",
	[78] = "Page Down", [79] = "Right", [80] = "Left", [81] = "Down", [82] = "Up",
	[83] = "Num Lock", [84] = "Numpad /", [85] = "Numpad *", [86] = "Numpad -",
	[87] = "Numpad +", [88] = "Numpad Enter", [98] = "Numpad 0", [99] = "Numpad .",
}
for code = 58, 69 do KEY_NAMES[code] = "F" .. ( code - 57 ) end
for code = 89, 97 do KEY_NAMES[code] = "Numpad " .. ( code - 88 ) end
for code, name in pairs( OTHER_KEYS ) do KEY_NAMES[code] = name end

local function key_setting( id, default )
	local code = tonumber( ModSettingGet( "witch_notebook." .. id ) )
	return code and KEY_NAMES[code] and code or default
end

function book_open_key()
	return key_setting( "open_key", DEFAULT_OPEN_KEY )
end

-- the keys that turn the pages back and on (the arrows always turn them too)
function book_turn_keys()
	return key_setting( "turn_back_key", 4 ), key_setting( "turn_on_key", 7 ) -- A, D
end

-- RMB with a book in hand opens it (on unless the setting is switched off)
function book_open_rmb()
	return ModSettingGet( "witch_notebook.open_rmb" ) ~= false
end

function book_open_key_name( code )
	return KEY_NAMES[code or book_open_key()] or KEY_NAMES[DEFAULT_OPEN_KEY]
end

function book_key_name( code )
	return KEY_NAMES[code] or "?"
end

function book_open_key_hint()
	return "[" .. book_open_key_name() .. "]"
end

-- "RMB in hand or [B]", or just "[B]" with RMB switched off
function book_open_hint()
	return ( book_open_rmb() and "RMB in hand or " or "" ) .. book_open_key_hint()
end
