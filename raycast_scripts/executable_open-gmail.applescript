#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Gmail
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ✉️
# @raycast.packageName Chrome Tabs

property targetURL : "mail.google.com"
property fullURL : "https://mail.google.com/"

tell application "Google Chrome"
	activate
	set found to false

	repeat with w in windows
		set i to 1
		repeat with t in tabs of w
			if URL of t contains targetURL then
				set active tab index of w to i
				set index of w to 1
				set found to true
				return
			end if
			set i to i + 1
		end repeat
	end repeat

	if not found then
		open location fullURL
	end if
end tell
