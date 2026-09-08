#!/usr/bin/env bash
# SessionEnd: 捕捉の対象をキューへ 1 行足すだけ。即座に返る。
#
# ここで捕捉そのものを走らせない。SessionEnd で起動した子プロセスは
# 終了しつつあるセッションと一緒に殺されうるため、長い処理を置けない。
# 実際の捕捉は次回の SessionStart が拾う。
set -euo pipefail
source "$HOME/.claude/hooks/wiki-capture-lib.sh"
wiki_capture_guard

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

[ -n "$cwd" ] && [ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

wiki=$(wiki_resolve "$cwd") || exit 0

mkdir -p "$STATE_DIR"
printf '%s\t%s\n' "$wiki" "$transcript" >>"$QUEUE"
