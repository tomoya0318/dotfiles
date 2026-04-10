#!/bin/bash

# 【重要】Hookから実行されてもHomebrewのコマンドを使えるようにPATHを通す
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd')
project=$(basename "$cwd")
hook_event=$(echo "$input" | jq -r '.hook_event_name')

case "$hook_event" in
  "Notification")
    message="許可待ち"
    ;;
  "Stop")
    message="タスク完了"
    ;;
  *)
    exit 0
    ;;
esac

terminal-notifier -title "Claude Code" -subtitle "$project" -message "$message" -sound "Ping"
