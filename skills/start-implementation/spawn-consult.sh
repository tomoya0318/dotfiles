#!/bin/bash
# エージェントをペインの直接コマンドにせず send-text で投入する
# （起動失敗時にエラーがペインへ残り、プロンプトから再実行できる）。
set -euo pipefail
command -v herdr >/dev/null 2>&1 || { echo "Error: herdr が見つかりません" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq が見つかりません" >&2; exit 1; }
WORK_DIR="${1:-}"; MODE="${2:-confirm}"
[[ -n "$WORK_DIR" ]] || { echo "Usage: spawn-consult.sh <work-dir> [confirm|qa]" >&2; exit 1; }
[[ -n "${HERDR_ENV:-}" ]] || { echo "Error: herdr 環境で実行してください（HERDR_ENV が未設定）" >&2; exit 1; }
REPO=$(pwd)
# main と同系のエージェントを起動する（herdr が報告する現在ペインの agent を引き継ぐ）
AGENT=$(herdr pane current 2>/dev/null | jq -r '.result.pane.agent // empty')
if [[ -z "$AGENT" ]] || ! command -v "$AGENT" >/dev/null 2>&1; then
  echo "Warning: current pane agent is unavailable; falling back to claude" >&2
  AGENT=claude
fi
INVOKE="/consult-session $WORK_DIR $MODE"
INVOKE_Q="${INVOKE//\'/\'\\\'\'}"
PANE_ID=$(herdr pane split --direction right --focus --cwd "$REPO" | jq -r '.result.pane.pane_id')
[[ -n "$PANE_ID" ]] || { echo "Error: herdr pane split が pane_id を返しませんでした" >&2; exit 1; }
herdr pane send-text "$PANE_ID" "$AGENT '$INVOKE_Q'"
herdr pane send-keys "$PANE_ID" enter
echo "分割ペイン ($PANE_ID) で $AGENT の consult-session を起動しました。結論は $WORK_DIR/consult-*.md に書かれます。"
