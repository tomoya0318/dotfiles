#!/bin/bash
set -euo pipefail
WORK_NAME="${1:-}"; BASE_DIR="${2:-$(pwd)/tmp}"
[[ -n "$WORK_NAME" ]] || { echo "作業名を指定してください" >&2; exit 1; }
mkdir -p "$BASE_DIR"
MAX_NUM=0
for dir in "$BASE_DIR"/[0-9][0-9][0-9][0-9]_*/; do
  [[ -d "$dir" ]] || continue
  num=$(basename "$dir" | grep -oE '^[0-9]+' || echo 0); num=$((10#$num)); ((num > MAX_NUM)) && MAX_NUM=$num
done
NEXT_NUM=$(printf '%04d' $((MAX_NUM + 1)))
SAFE_NAME=$(printf '%s' "$WORK_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-_')
[[ -n "$SAFE_NAME" ]] || SAFE_NAME=work
WORK_DIR="$BASE_DIR/${NEXT_NUM}_${SAFE_NAME}"; mkdir "$WORK_DIR"; TODAY=$(date +%Y-%m-%d)
{
  printf '# 実装計画: %s\n\n作成日: %s\n' "$WORK_NAME" "$TODAY"
  cat <<'EOF'

## 概要
<!-- 何を作る/変えるか。スコープと非スコープ。 -->

## 対象コードの理解
<!-- 責務・データフロー・不変条件を自分の言葉で。未解明は推測で埋めない。 -->

## 未決事項
<!-- ユーザー判断が要るもの。選択肢とトレードオフを添える。 -->

## 方針と代替案
<!-- 採った方針と、検討して捨てた案を同じ判断基準で比較。 -->

## 実装手順
<!-- フェーズと具体的なタスク。 -->

## リスクと懸念
EOF
} > "$WORK_DIR/plan.md"
{
  printf '# 検証記録: %s\n\n作成日: %s\n' "$WORK_NAME" "$TODAY"
  cat <<'EOF'

## 計画検証
<!-- 指摘表: # | 指摘 | 確信度 | 対応（計画へ反映 / スキップ＋理由） -->

## 実装検証
<!-- 指摘表: # | 指摘 | 確信度 | 対応 -->
EOF
} > "$WORK_DIR/review.md"
printf '{"work_dir":"%s","plan_file":"%s/plan.md","review_file":"%s/review.md","sequence_number":"%s","work_name":"%s"}\n' "$WORK_DIR" "$WORK_DIR" "$WORK_DIR" "$NEXT_NUM" "$SAFE_NAME"

register_workbench_root() {
  local home_dir="${HOME:-}"
  [ -n "$home_dir" ] || return 0
  local register_root="$home_dir/dev/workbench/tools/register-root.sh"
  [ -x "$register_root" ] || return 0

  local git_common_dir=""
  if git_common_dir="$(git -C "$BASE_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    && [ -n "$git_common_dir" ]; then
    "$register_root" "$(dirname "$git_common_dir")" >/dev/null 2>&1 || true
  fi
}
register_workbench_root >/dev/null 2>&1 || true
