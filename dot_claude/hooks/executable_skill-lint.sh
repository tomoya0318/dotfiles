#!/usr/bin/env bash
# skill を編集した直後だけ skill-lint を走らせる。
# 定期実行しないのは、警報ラインが「今まさに足そうとしている」瞬間にしか意味を持たないため。
set -uo pipefail

payload="$(cat)"
path="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get("tool_input", {}).get("file_path", "") or "")
')"

case "$path" in
  */skills/*.md) ;;
  *) exit 0 ;;
esac

lint="$HOME/.claude/hooks/skill-lint.py"
[ -f "$lint" ] || exit 0

out="$(python3 "$lint" "$path" 2>&1)" && exit 0

printf 'skill-lint:\n%s\n' "$out" >&2
exit 2
