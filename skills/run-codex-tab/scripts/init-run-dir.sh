#!/usr/bin/env bash
# Codex run 用の tmp/NNNN_<name>/ を作り、絶対パスを返す。
set -euo pipefail

RUN_NAME="${1:-}"
BASE_DIR="${2:-$(pwd)/tmp}"

[[ -n "$RUN_NAME" ]] || { echo "run name is required" >&2; exit 1; }
mkdir -p "$BASE_DIR"
BASE_DIR="$(cd "$BASE_DIR" && pwd)"

SAFE_NAME="$(printf '%s' "$RUN_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | tr ' ' '-' \
  | tr -cd '[:alnum:]-_')"
[[ -n "$SAFE_NAME" ]] || SAFE_NAME=run

MAX_NUM=0
for dir in "$BASE_DIR"/[0-9][0-9][0-9][0-9]_*/; do
  [[ -d "$dir" ]] || continue
  basename_dir="$(basename "$dir")"
  [[ "$basename_dir" =~ ^([0-9]{4})_ ]] || continue
  num=$((10#${BASH_REMATCH[1]}))
  if (( num > MAX_NUM )); then
    MAX_NUM="$num"
  fi
done

NEXT_NUM=$((MAX_NUM + 1))
while :; do
  RUN_DIR="$BASE_DIR/$(printf '%04d' "$NEXT_NUM")_${SAFE_NAME}"
  if mkdir "$RUN_DIR" 2>/dev/null; then
    break
  fi
  NEXT_NUM=$((NEXT_NUM + 1))
done

printf '%s\n' "$RUN_DIR"
