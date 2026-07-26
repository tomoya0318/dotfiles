#!/bin/bash
set -u

command -v jq >/dev/null 2>&1 || exit 0

ROOT="${1:-}"
case "$ROOT" in
  /*) ;;
  *) exit 0 ;;
esac
[ -d "$ROOT" ] || exit 0

DEFAULT_STATE_DIR="${HOME:-}/.local/state/workbench"
STATE_DIR="${WORKBENCH_STATE_DIR:-$DEFAULT_STATE_DIR}"
[ -n "$STATE_DIR" ] || exit 0
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

ROOTS_FILE="$STATE_DIR/roots.json"
TMP_FILE="$(mktemp "$STATE_DIR/.roots.json.XXXXXX" 2>/dev/null)" || exit 0
cleanup() {
  rm -f "$TMP_FILE"
}
trap cleanup EXIT

if [ -f "$ROOTS_FILE" ] && jq -e 'type == "array"' "$ROOTS_FILE" >/dev/null 2>&1; then
  if jq -e --arg root "$ROOT" 'index($root) != null' "$ROOTS_FILE" >/dev/null 2>&1; then
    exit 0
  fi
  jq --arg root "$ROOT" '. + [$root]' "$ROOTS_FILE" > "$TMP_FILE" 2>/dev/null || exit 0
else
  jq -n --arg root "$ROOT" '[$root]' > "$TMP_FILE" 2>/dev/null || exit 0
fi

mv "$TMP_FILE" "$ROOTS_FILE" 2>/dev/null || exit 0
trap - EXIT
exit 0
