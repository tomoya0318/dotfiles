#!/bin/sh
# ~/.claude.json は Claude Code のランタイム状態ファイルで、セッション状態や
# 履歴が同居しているため chezmoi がファイルごと管理するには向かない。
# ここでは chezmoi apply のたびに「必要なキーだけ」を冪等に強制する。
#   autoUpdates            : バックグラウンド自動更新を有効に保つ
#   mcpServers.semble.alwaysLoad : semble のツールスキーマを常駐させる
set -eu
f="$HOME/.claude.json"
[ -f "$f" ] || exit 0
command -v jq >/dev/null 2>&1 || { echo "chezmoi: jq がないので ~/.claude.json をスキップ" >&2; exit 0; }
tmp="$(mktemp "${TMPDIR:-/tmp}/claude-json.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
jq '
  .autoUpdates = true
  | if (.mcpServers.semble) then .mcpServers.semble.alwaysLoad = true else . end
' "$f" > "$tmp"
if ! cmp -s "$f" "$tmp"; then
  cat "$tmp" > "$f"
  echo "chezmoi: ~/.claude.json の autoUpdates / semble.alwaysLoad を更新した"
fi
