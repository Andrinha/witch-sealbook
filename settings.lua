dofile( "data/scripts/lib/mod_settings.lua" )
dofile_once( "mods/witch_notebook/files/book_key.lua" )

-- The mod's settings (Options > Mod settings). Read in the game with ModSettingGet( "witch_notebook.<id>" ).
local mod_id = "witch_notebook"
mod_settings_version = 1
local choosing_open_key = false

local function open_key_setting_ui( mod_id, gui, in_main_menu, im_id, setting )
	local id = mod_setting_get_id( mod_id, setting )
	local code = tonumber( ModSettingGetNextValue( id ) ) or setting.value_default
	local label = choosing_open_key and "Press a key (Esc to cancel)" or ( setting.ui_name .. ": " .. book_open_key_name( code ) )
	local clicked, right_clicked = GuiButton( gui, im_id, mod_setting_group_x_offset, 0, label )
	if right_clicked then
		choosing_open_key = false
		ModSettingSetNextValue( id, setting.value_default, false )
	elseif choosing_open_key then
		if InputIsKeyJustDown( 41 ) then -- Escape cancels binding
			choosing_open_key = false
		else
			for key in pairs( book_open_key_options() ) do
				if InputIsKeyJustDown( key ) then
					ModSettingSetNextValue( id, key, false )
					choosing_open_key = false
					break
				end
			end
		end
	elseif clicked then
		choosing_open_key = true
	end
	mod_setting_tooltip( mod_id, gui, in_main_menu, setting )
end

mod_settings = {
	{
		id = "performance_profiler",
		ui_name = "Performance profiler",
		ui_description = "Show frame-time peaks and spell costs on screen; print a report every 5 seconds.\nUse this to investigate stutters. Profiling adds some overhead; disable after measuring.",
		value_default = false,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "open_key",
		ui_name = "Open / close book",
		ui_description = "Click, then press a key. Right-click to reset to B. Esc cancels. A/D and arrows turn pages unless assigned to open the book.",
		value_default = 5,
		scope = MOD_SETTING_SCOPE_RUNTIME,
		ui_fn = open_key_setting_ui,
	},
	{
		id = "full_grimoire",
		ui_name = "Whole grimoire unlocked",
		ui_description = "All the seals are in the books at once and can be cast from them - for testing.\nWithout it seals are learned from sheets found in the world and bought in the Holy Mountains.",
		value_default = false,
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
