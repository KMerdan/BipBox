-- ui_click.applescript — click a Bipbox UI element by its accessibility identifier.
--
-- Usage:  osascript scripts/automation/ui_click.applescript sidebar.inbox
--
-- Requires: the controlling app (Terminal/iTerm) must have Accessibility
-- permission (System Settings ▸ Privacy & Security ▸ Accessibility).
-- This drives the REAL rendered window via the macOS Accessibility API.

on run argv
	if (count of argv) < 1 then error "Pass an accessibility identifier, e.g. sidebar.inbox"
	set targetID to item 1 of argv
	tell application "Bipbox" to activate
	delay 0.3
	tell application "System Events"
		tell process "BipboxApp"
			set matches to (every UI element of entire contents of window 1 whose value of attribute "AXIdentifier" is targetID)
			if (count of matches) is 0 then error "No element with AXIdentifier '" & targetID & "'"
			perform action "AXPress" of (item 1 of matches)
			return "clicked " & targetID
		end tell
	end tell
end run
