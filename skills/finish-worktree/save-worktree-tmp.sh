#!/bin/bash
set -euo pipefail
WORK_NAME="${1:-}"; WORKTREE_DIR="${2:-}"; ORIGINAL_DIR="${3:-}"
[[ -n "$WORK_NAME" && -n "$WORKTREE_DIR" && -n "$ORIGINAL_DIR" ]] || { echo "Usage: $(basename "$0") <work-name> <worktree-dir> <original-dir>" >&2; exit 1; }
WORKTREE_TOP=$(git -C "$WORKTREE_DIR" rev-parse --show-toplevel 2>/dev/null || true); [[ -n "$WORKTREE_TOP" ]] && WORKTREE_DIR="$WORKTREE_TOP"
SRC="$WORKTREE_DIR/tmp"; DEST="$ORIGINAL_DIR/tmp"; [[ -d "$SRC" ]] || { echo "worktree に tmp がありません: $SRC" >&2; exit 1; }; mkdir -p "$DEST"
max=0
for d in "$DEST"/[0-9][0-9][0-9][0-9]_*/; do [[ -d "$d" ]] || continue; n=$(basename "$d"|grep -oE '^[0-9]+'||echo 0); n=$((10#$n)); ((n>max))&&max=$n; done
next=$((max+1)); slug=$(printf '%s' "$WORK_NAME"|tr '[:upper:]' '[:lower:]'|tr ' ' '-'|tr -cd '[:alnum:]-_'); saved=()
shopt -s nullglob dotglob
for item in "$SRC"/*; do base=$(basename "$item"); if [[ -d "$item" && "$base" =~ ^[0-9]{4}_ ]]; then name=$(printf '%04d_%s' "$next" "${base#????_}"); mv "$item" "$DEST/$name"; saved+=("$DEST/$name"); next=$((next+1)); fi; done
left=(); for item in "$SRC"/*; do [[ -e "$item" ]] && left+=("$item"); done
if ((${#left[@]})); then name=$(printf '%04d_%s' "$next" "$slug"); mkdir -p "$DEST/$name"; for item in "${left[@]}"; do mv "$item" "$DEST/$name/"; done; saved+=("$DEST/$name"); fi
printf '{"saved_dirs":['; sep=; for item in "${saved[@]}"; do printf '%s"%s"' "$sep" "$item"; sep=,; done; printf ']}\n'
