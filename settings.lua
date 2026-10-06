dofile( "data/scripts/lib/mod_settings.lua" )

-- The mod's settings (Options > Mod settings). Read in the game with ModSettingGet( "witch_notebook.<id>" ).
-- This file can't load the mod's own files (a Workshop install has no mods/witch_notebook path here, so a missing
-- function hid every setting after the book key), hence the key names are kept here as well as in files/book_key.lua.
local mod_id = "witch_notebook"
mod_settings_version = 1
local choosing_key_id -- the key setting waiting for a key press

local KEY_NAMES = {}
for code = 4, 29 do KEY_NAMES[code] = string.char( string.byte( "A" ) + code - 4 ) end
for code = 30, 38 do KEY_NAMES[code] = tostring( code - 29 ) end
KEY_NAMES[39] = "0"
for code = 58, 69 do KEY_NAMES[code] = "F" .. ( code - 57 ) end
for code = 89, 97 do KEY_NAMES[code] = "Numpad " .. ( code - 88 ) end
for code, name in pairs( {
	[40] = "Enter", [42] = "Backspace", [43] = "Tab", [44] = "Space",
	[45] = "-", [46] = "=", [47] = "[", [48] = "]", [49] = "Backslash",
	[51] = ";", [52] = "'", [53] = "`", [54] = ",", [55] = ".", [56] = "/",
	[57] = "Caps Lock", [70] = "Print Screen", [71] = "Scroll Lock", [72] = "Pause",
	[73] = "Insert", [74] = "Home", [75] = "Page Up", [76] = "Delete", [77] = "End",
	[78] = "Page Down", [79] = "Right", [80] = "Left", [81] = "Down", [82] = "Up",
	[83] = "Num Lock", [84] = "Numpad /", [85] = "Numpad *", [86] = "Numpad -",
	[87] = "Numpad +", [88] = "Numpad Enter", [98] = "Numpad 0", [99] = "Numpad .",
} ) do KEY_NAMES[code] = name end

local function key_setting_ui( mod_id, gui, in_main_menu, im_id, setting )
	local id = mod_setting_get_id( mod_id, setting )
	local code = tonumber( ( ModSettingGetNextValue( id ) ) ) or setting.value_default
	local choosing = choosing_key_id == setting.id
	local label = choosing and "Press a key (Esc to cancel)"
		or ( setting.ui_name .. ": " .. ( KEY_NAMES[code] or KEY_NAMES[setting.value_default] ) )
	local clicked, right_clicked = GuiButton( gui, im_id, mod_setting_group_x_offset, 0, label )
	if right_clicked then
		choosing_key_id = nil
		ModSettingSetNextValue( id, setting.value_default, false )
	elseif choosing then
		if InputIsKeyJustDown( 41 ) then -- Escape cancels binding
			choosing_key_id = nil
		else
			for key in pairs( KEY_NAMES ) do
				if InputIsKeyJustDown( key ) then
					ModSettingSetNextValue( id, key, false )
					choosing_key_id = nil
					break
				end
			end
		end
	elseif clicked then
		choosing_key_id = setting.id
	end
	mod_setting_tooltip( mod_id, gui, in_main_menu, setting )
end

mod_settings = {
	{
		id = "open_key",
		ui_name = "Open / close book",
		ui_description = "Click, then press a key. Right-click to reset to B. Esc cancels.\nA key that opens the book does not turn pages.",
		value_default = 5,
		scope = MOD_SETTING_SCOPE_RUNTIME,
		ui_fn = key_setting_ui,
	},
	{
		id = "turn_back_key",
		ui_name = "Turn page back",
		ui_description = "Click, then press a key. Right-click to reset to A. Esc cancels.\nThe left arrow and the mouse wheel turn pages too.",
		value_default = 4,
		scope = MOD_SETTING_SCOPE_RUNTIME,
		ui_fn = key_setting_ui,
	},
	{
		id = "turn_on_key",
		ui_name = "Turn page on",
		ui_description = "Click, then press a key. Right-click to reset to D. Esc cancels.\nThe right arrow and the mouse wheel turn pages too.",
		value_default = 7,
		scope = MOD_SETTING_SCOPE_RUNTIME,
		ui_fn = key_setting_ui,
	},
	{
		id = "open_rmb",
		ui_name = "RMB opens the held book",
		ui_description = "Right mouse button opens the book in your hand. Turn off to open it only with the key above.\nInside the book RMB still erases.",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "grimoire_remembers",
		ui_name = "Grimoire remembers past runs",
		ui_description = "The seals learned in earlier runs stay in the grimoire, to study and redraw.\nTo cast one, it still has to be drawn on a page or found on a sheet again.",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		category_id = "testing",
		ui_name = "Testing and debugging",
		ui_description = "Options for developing and testing the mod.",
		foldable = true,
		_folded = true,
		settings = {
			{
				id = "performance_profiler",
				ui_name = "Performance profiler",
				ui_description = "Show frame-time peaks and spell costs on screen; print a report every 5 seconds.\nUse this to investigate stutters. Profiling adds some overhead; disable after measuring.",
				value_default = false,
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "full_grimoire",
				ui_name = "Whole grimoire unlocked",
				ui_description = "All the seals are in the books at once and can be cast from them - for testing.\nWithout it seals are learned from sheets found in the world and bought in the Holy Mountains.",
				value_default = false,
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "books_at_spawn",
				ui_name = "All the books at the start",
				ui_description = "The Palm Quire and the Great Tome lie beside the witch when a run starts - for testing.\nWithout it the quire is sold now and then in the Holy Mountains, and the first boss the witch kills\nleaves a Great Tome (the Holy Mountains from the fourth on sell one too, rarely).",
				value_default = false,
				scope = MOD_SETTING_SCOPE_NEW_GAME,
			},
			{
				id = "test_book_at_spawn",
				ui_name = "Spawn the Test Book",
				ui_description = "The Test Book (every sigil with every sign, drawn in advance) lies beside the witch when a run\nstarts - for testing.",
				value_default = false,
				scope = MOD_SETTING_SCOPE_NEW_GAME,
			},
		},
	},
}

function ModSettingsUpdate( init_scope )
	mod_settings_update( mod_id, mod_settings, init_scope )
end

function ModSettingsGuiCount()
	return mod_settings_gui_count( mod_id, mod_settings )
end

function ModSettingsGui( gui, in_main_menu )
	mod_settings_gui( mod_id, mod_settings, gui, in_main_menu )
end
