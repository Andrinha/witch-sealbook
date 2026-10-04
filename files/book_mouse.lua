-- The mouse on the gui, for drawing in the books (notebook.lua).
-- InputGetMousePosOnScreen() returns the mouse in the game's internal resolution (config.xml
-- internal_size_w/h), whose height is 720 by default, also on ultrawide screens. Lua can't read the
-- internal resolution, so for non-default setups there is an optional calibration: the player clicks
-- two gui buttons, and the gui positions of the buttons are matched with the raw mouse positions.

BookMouse = {}
local M = BookMouse

local INTERNAL_HEIGHT = 720
local SETTING = "witch_notebook.mouse_calibration"
local BUTTON_TARGET, BUTTON_CANCEL = 900001, 900008 -- ids that stay the same every frame (notebook.lua BUTTON)
local MOUSE_LEFT, MOUSE_RIGHT = 1, 2
local calibration -- { sx, ox, sy, oy, sw, sh }: gui = raw * s + o, measured at gui size sw x sh
local clicks = {}
M.calibrating = false

local function load_calibration()
	local saved = ModSettingGet( SETTING )
	if type( saved ) ~= "string" then return nil end
	local v = {}
	for n in saved:gmatch( "[^,]+" ) do v[#v + 1] = tonumber( n ) end
	if #v ~= 6 then return nil end
	return { sx = v[1], ox = v[2], sy = v[3], oy = v[4], sw = v[5], sh = v[6] }
end

function M.start()
	M.calibrating, clicks = true, {}
end

-- given up (the book was closed)
function M.stop()
	M.calibrating, clicks = false, {}
end

-- both crosses clicked: true when they gave a calibration (clicks on one spot give none: it starts over)
local function finish( sw, sh )
	local a, b = clicks[1], clicks[2]
	clicks = {}
	if math.abs( b.raw_x - a.raw_x ) < 1 or math.abs( b.raw_y - a.raw_y ) < 1 then return false end
	local sx = ( b.gui_x - a.gui_x ) / ( b.raw_x - a.raw_x )
	local sy = ( b.gui_y - a.gui_y ) / ( b.raw_y - a.raw_y )
	M.calibrating = false
	calibration = { sx = sx, ox = a.gui_x - sx * a.raw_x, sy = sy, oy = a.gui_y - sy * a.raw_y, sw = sw, sh = sh }
	ModSettingSet( SETTING, table.concat( { calibration.sx, calibration.ox, calibration.sy, calibration.oy, sw, sh }, "," ) )
	return true
end

-- A frame of the calibration, instead of the book. Returns "done" when it is measured, "cancelled" when given up.
function M.calibrate( gui, sw, sh )
	local step = #clicks + 1
	local tx = step == 1 and sw * 0.2 or sw * 0.8
	local ty = step == 1 and sh * 0.25 or sh * 0.75

	local text = "Mouse calibration: click the cross (" .. step .. "/2)"
	local w = GuiGetTextDimensions( gui, text )
	GuiText( gui, ( sw - w ) / 2, sh * 0.5, text )
	-- clicked by mistake: the button (the game places its own buttons under the real cursor) or the right button leave it
	local cancel = "[Cancel - RMB]"
	GuiColorSetForNextWidget( gui, 0.7, 0.7, 0.7, 1 )
	if GuiButton( gui, BUTTON_CANCEL, ( sw - GuiGetTextDimensions( gui, cancel ) ) / 2, sh * 0.5 + 14, cancel )
		or InputIsMouseButtonJustDown( MOUSE_RIGHT ) then
		M.stop()
		return "cancelled"
	end

	local clicked = GuiImageButton( gui, BUTTON_TARGET, tx, ty, "", NOTEBOOK_TARGET_IMAGE )
	local _, _, _, x, y, width, height = GuiGetPreviousWidgetInfo( gui )
	if clicked then
		local raw_x, raw_y = InputGetMousePosOnScreen()
		clicks[step] = { raw_x = raw_x, raw_y = raw_y, gui_x = x + width / 2, gui_y = y + height / 2 }
		if step == 2 and finish( sw, sh ) then return "done" end
	end
end

-- the mouse in gui units, on a gui sw x sh
function M.position( sw, sh )
	calibration = calibration or load_calibration()
	local mx, my = InputGetMousePosOnScreen()
	if calibration and calibration.sw == sw and calibration.sh == sh then
		return mx * calibration.sx + calibration.ox, my * calibration.sy + calibration.oy
	end
	local scale = sh / INTERNAL_HEIGHT
	return mx * scale, my * scale
end
