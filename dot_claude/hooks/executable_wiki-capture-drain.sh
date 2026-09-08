#!/usr/bin/env bash
# SessionStart: キューを引き取り、捕捉をバックグラウンドで起動する。
#
# このセッションは以後も生き続けるので、ここで起動した子プロセスは
# 生き残れる。SessionEnd では成立しない。
set -euo pipefail
source "$HOME/.claude/hooks/wiki-capture-lib.sh"
wiki_capture_guard

cat >/dev/null   # stdin を読み切ってからバックグラウンドに回す

[ -s "$QUEUE" ] || exit 0

# 取り出しと同時に空にする。以後の enqueue と衝突しない。
work="$QUEUE.$$"
mv "$QUEUE" "$work" 2>/dev/null || exit 0
mkdir -p "$DONE_DIR"

seen=""
while IFS=$'\t' read -r wiki transcript; do
  [ -n "${wiki:-}" ] && [ -n "${transcript:-}" ] || continue
  [ -f "$transcript" ] || continue

  key=$(wiki_done_key "$transcript")
  [ -f "$DONE_DIR/$key" ] && continue
  case " $seen " in *" $key "*) continue ;; esac
  seen="$seen $key"

  # herdr の環境変数を落とす。継承したままだと、捕捉用の headless セッションが
  # 親ペインの agent 状態を上書きしてしまう。herdr 側の hook は自分で
  # HERDR_PANE_ID を見て抜けるので、こちらが消せば触れられない。
  nohup env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SOCKET_PATH \
    WIKI_CAPTURE=1 \
    "$HOME/.claude/hooks/wiki-capture.sh" "$wiki" "$transcript" "$key" \
    >/dev/null 2>&1 &
  disown 2>/dev/null || true
done <"$work"

rm -f "$work"
