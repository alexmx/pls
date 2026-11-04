-- @quick.description: Switch the system appearance between dark and light
-- @quick.param mode: enum(dark|light|toggle) = toggle -- Desired appearance
-- @quick.example: it's too bright
-- @quick.example: turn on dark mode

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
