#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Google Calendar
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📅
# @raycast.packageName Chrome Tabs


# 1. 探すURLの一部（この文字が含まれるタブを探します）
property targetURL : "calendar.google.com"

# 2. 見つからない時に開くURL（新規タブで開く用）
property fullURL : "https://calendar.google.com/"


tell application "Google Chrome"
	activate
	set found to false

	-- 全ウィンドウの全タブをチェック
	repeat with w in windows
		set i to 1
		repeat with t in tabs of w
			if URL of t contains targetURL then
				-- 見つかったらそのタブを表示
				set active tab index of w to i
				set index of w to 1
				set found to true
				return
			end if
			set i to i + 1
		end repeat
	end repeat

	-- 見つからなければ新規作成
	if not found then
		open location fullURL
	end if
end tell
