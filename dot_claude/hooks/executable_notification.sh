#!/bin/bash

# 【重要】Hookから実行されてもHomebrewのコマンドを使えるようにPATHを通す
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# 入力の取得
input=$(cat)

# デバッグ用: もしまた失敗したら、下の行のコメントアウトを外してログを確認してみてください
# echo "$(date): $input" >> ~/.claude/notify_debug.log

cwd=$(echo "$input" | jq -r '.cwd')
project=$(basename "$cwd")
notification_type=$(echo "$input" | jq -r '.notification_type')

# 通知内容の判定
case "$notification_type" in
  "permission_prompt")
    message="許可待ち"
    ;;
  "idle_prompt")
    message="入力待ち"
    ;;
  "stop")
    message="タスク完了"
    ;;
  *)
    message="通知"
    ;;
esac

# macOS通知を実行
terminal-notifier -title "Claude Code" -subtitle "$project" -message "$message" -sound "Ping"
