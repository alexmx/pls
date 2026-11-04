-- @pls.description: Switch the system appearance between dark and light
-- @pls.param mode: enum(dark|light|toggle) = toggle -- Desired appearance
-- @pls.example: it's too bright
-- @pls.example: turn on dark mode

on run argv
	set mode to item 1 of argv
	tell application "System Events"
		tell appearance preferences
			if mode is "toggle" then
				set dark mode to not dark mode
			else
				set dark mode to (mode is "dark")
			end if
		end tell
	end tell
end run
