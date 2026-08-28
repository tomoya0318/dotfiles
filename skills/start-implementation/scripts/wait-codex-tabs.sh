#!/bin/bash
# 起動済みの codex tab を1枚以上まとめて待ち、最初に決着したものを返す。
# --no-wait で起動した並行 run を待つために使う。Bash ツールの10分上限に合わせて
# --timeout を短めに刻み、timeout が返ったら同じ引数で呼び直す。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_codex-tab-lib.sh"

PANES=(); RESULTS=(); TIMEOUT=540

die() { emit_json status wait-failed error "$1"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    # --target <pane_id>=<result_file> を run の数だけ並べる。
    # pane_id 自体が w11:p1G のようにコロンを含むので、区切りは = にする。
    --target) PANES+=("${2%%=*}"); RESULTS+=("${2#*=}"); shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) die "unknown option: $1" ;;
  esac
done

(( ${#PANES[@]} > 0 )) || die "--target is required"

START=$(date +%s)
while :; do
  for i in "${!PANES[@]}"; do
    pane="${PANES[$i]}"; result="${RESULTS[$i]}"
    if [[ -f "$result" ]]; then
      st="$(classify_result "$result")"
      emit_json pane_id "$pane" status "$st" result_file "$result" issue "$(issue_line "$result")"
      exit 0
    fi
    state="$(pane_state "$pane")"
    if [[ "$state" == missing ]]; then
      emit_json pane_id "$pane" status pane-gone result_file "$result" issue ""
      exit 0
    fi
  done
  (( $(date +%s) - START >= TIMEOUT )) && { emit_json status timeout issue "no run settled yet"; exit 0; }
  sleep 3
done
