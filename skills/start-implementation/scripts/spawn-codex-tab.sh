#!/usr/bin/env bash
# herdr の tab を1枚立て、そこで codex を対話モードで起動する。
# Claude からも codex からも同じ引数で呼べる。階層が何段でも同じ手順が使える。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_codex-tab-lib.sh"

NAME=""; CWD=""; PROMPT_FILE=""; RESULT_FILE=""
ROLE="impl"; MODEL="gpt-5.6-luna"; EFFORT="xhigh"; SANDBOX="workspace-write"
TIMEOUT=1800; WAIT_DONE=1; PARENT="${HERDR_PANE_ID:-}"

die() { emit_json status spawn-failed error "$1"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --result-file) RESULT_FILE="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --sandbox) SANDBOX="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --parent) PARENT="$2"; shift 2 ;;
    --no-wait) WAIT_DONE=0; shift ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "$NAME" ]] || die "--name is required"
[[ "$NAME" =~ ^[A-Za-z0-9_-]+$ ]] || die "--name must contain only ASCII letters, digits, hyphens, and underscores"
[[ -n "$CWD" && -d "$CWD" ]] || die "--cwd must be an existing directory"
[[ -n "$PROMPT_FILE" && -f "$PROMPT_FILE" ]] || die "--prompt-file must be an existing file"
[[ -n "$RESULT_FILE" ]] || die "--result-file is required"

rm -f "$RESULT_FILE"
RESULT_DIR="$(cd "$(dirname "$RESULT_FILE")" 2>/dev/null && pwd)" \
  || die "--result-file parent directory must exist"
CWD_REAL="$(cd "$CWD" 2>/dev/null && pwd)" \
  || die "--cwd must be an accessible directory"
FLAGS="$(codex_flags "$MODEL" "$SANDBOX" "$EFFORT" "$CWD")"
if [[ "$ROLE" == "consult" ]]; then
  # primary workspace は read-only のまま、結果ファイルの受け渡し先だけ書き込み可能にする。
  case "$CWD_REAL/" in
    "$RESULT_DIR/"*) die "consult result directory must be below or outside --cwd" ;;
  esac
  FLAGS+=" --add-dir $(printf '%q' "$RESULT_DIR")"
fi

# herdr の外（CI や素のターミナル）では非対話で同期実行する。tab は作れない。
if [[ "${HERDR_ENV:-}" != "1" || -z "${HERDR_PANE_ID:-}" ]]; then
  eval "codex exec $FLAGS -o ${RESULT_FILE@Q} < ${PROMPT_FILE@Q}" >/dev/null 2>&1 || true
  ST="$(classify_result "$RESULT_FILE")"
  emit_json pane_id "" tab_id "" status "$ST" result_file "$RESULT_FILE" issue "$(issue_line "$RESULT_FILE")"
  exit 0
fi

# 長いコマンドを pane へ打ち込むとクォートが壊れるので、起動用スクリプトを経由する。
WORK_DIR="$(cd "$(dirname "$RESULT_FILE")" && pwd)"
LAUNCHER="$WORK_DIR/.launch-${NAME}.sh"
{ echo '#!/bin/zsh'; echo "codex $FLAGS \"\$(cat ${PROMPT_FILE@Q})\""; } > "$LAUNCHER"

# --workspace と --cwd は省略できない。省くと別 workspace や既定の cwd に飛ぶ。
CREATED="$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --label "$NAME" --cwd "$CWD" --no-focus)" \
  || die "herdr tab create failed"
read -r PANE TAB <<<"$(printf '%s' "$CREATED" | python3 -c \
  'import json,sys; r=json.load(sys.stdin)["result"]; print(r["root_pane"]["pane_id"], r["tab"]["tab_id"])')"

herdr pane rename "$PANE" "$NAME" >/dev/null 2>&1 || true
report_meta "$PANE" "$ROLE" running "$RESULT_FILE" "$PARENT"
herdr pane run "$PANE" "zsh ${LAUNCHER@Q}" >/dev/null 2>&1 || die "herdr pane run failed"

if [[ "$WAIT_DONE" -eq 0 ]]; then
  emit_json pane_id "$PANE" tab_id "$TAB" status running result_file "$RESULT_FILE" issue ""
  exit 0
fi

STATUS="$(wait_one "$PANE" "$RESULT_FILE" "$TIMEOUT")"
ISSUE="$(issue_line "$RESULT_FILE")"
report_meta "$PANE" "$ROLE" "$STATUS" "$RESULT_FILE" "$PARENT" "$ISSUE"
emit_json pane_id "$PANE" tab_id "$TAB" status "$STATUS" result_file "$RESULT_FILE" issue "$ISSUE"
