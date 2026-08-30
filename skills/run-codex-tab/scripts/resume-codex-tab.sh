#!/bin/bash
# NEEDS_USER_DECISION で止まっている tab にユーザーの回答を届けて再開する。
# TUI の入力欄に文字が残っていると送信内容が連結されて壊れるので、空であることを先に確かめる。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_codex-tab-lib.sh"

PANE=""; ANSWER_FILE=""; RESULT_FILE=""; TIMEOUT=1800; ROLE="impl"

die() { emit_json status resume-failed error "$1"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pane) PANE="$2"; shift 2 ;;
    --answer-file) ANSWER_FILE="$2"; shift 2 ;;
    --result-file) RESULT_FILE="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "$PANE" ]] || die "--pane is required"
[[ -n "$ANSWER_FILE" && -f "$ANSWER_FILE" ]] || die "--answer-file must be an existing file"
[[ -n "$RESULT_FILE" ]] || die "--result-file is required"
[[ "$(pane_state "$PANE")" != missing ]] || die "pane is gone; the codex session was closed"

# 入力欄の状態を見る。プレースホルダが出ていれば空。
# クリア用のキーは送らない。ctrl+c は codex ごと終了させる。
SCREEN="$(herdr pane read "$PANE" --source visible --lines 5 2>/dev/null || true)"
if ! printf '%s' "$SCREEN" | grep -q 'Ask Codex to do anything'; then
  emit_json pane_id "$PANE" status dirty-input \
    issue "input box is not empty; clear it in the tab before resuming"
  exit 0
fi

rm -f "$RESULT_FILE"
herdr agent send "$PANE" "$(cat "$ANSWER_FILE")" >/dev/null 2>&1 || die "herdr agent send failed"
sleep 1
herdr pane send-keys "$PANE" Enter >/dev/null 2>&1 || die "herdr pane send-keys failed"

STATUS="$(wait_one "$PANE" "$RESULT_FILE" "$TIMEOUT")"
ISSUE="$(issue_line "$RESULT_FILE")"
report_meta "$PANE" "$ROLE" "$STATUS" "$RESULT_FILE" "${HERDR_PANE_ID:-}" "$ISSUE"
emit_json pane_id "$PANE" status "$STATUS" result_file "$RESULT_FILE" issue "$ISSUE"
