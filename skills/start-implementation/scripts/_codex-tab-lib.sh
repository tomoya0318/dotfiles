# spawn / wait / resume が共有する関数。単体では実行しない。

# codex の起動フラグ。read-only では書き込み系の緩和を渡さない。
codex_flags() {
  local model="$1" sandbox="$2" effort="$3" cwd="$4"
  printf -- '-m %q --sandbox %q -c model_reasoning_effort=%q -C %q' "$model" "$sandbox" "$effort" "$cwd"
  if [[ "$sandbox" == "workspace-write" ]]; then
    # 子 codex を起動して上位モデルへ相談するために両方要る。片方だけでは app-server が初期化できない。
    printf -- ' --add-dir %q -c sandbox_workspace_write.network_access=true' "$HOME/.codex"
  fi
}

pane_state() {
  # pane が無いと herdr は RC=1 を返す。pipefail と併用すると `|| echo missing` が
  # python の出力に重なって2行になるので、herdr の失敗はここで握り潰しておく。
  local raw
  raw="$(herdr pane get "$1" 2>/dev/null || true)"
  printf '%s' "$raw" | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["result"]["pane"].get("agent_status") or "unknown")
except Exception: print("missing")' 2>/dev/null || printf 'missing\n'
}

classify_result() {
  local f="$1"
  [[ -f "$f" ]] || { echo "no-result"; return; }
  if grep -q '^NEEDS_USER_DECISION:' "$f" 2>/dev/null; then echo "needs-user"; return; fi
  echo "completed"
}

issue_line() {
  { grep -m1 '^NEEDS_USER_DECISION:' "$1" 2>/dev/null || true; } \
    | sed 's/^NEEDS_USER_DECISION:[[:space:]]*//' | head -c 300
}

# pane を1枚ずつ見て、結果ファイルが現れるか pane が落ち着くまで待つ。
# 状態だけに頼らない。done のまま idle へ落ちない run があり、idle だけを待つと返らないため。
# 起動直後にも idle が一瞬出るので、最初の GRACE 秒は状態を判定に使わない。
# echo する値: completed | needs-user | no-result | pane-gone | timeout
wait_one() {
  local pane="$1" result="$2" timeout="$3" grace="${4:-20}"
  local start now st
  start=$(date +%s)
  while :; do
    [[ -f "$result" ]] && { classify_result "$result"; return; }
    now=$(date +%s)
    (( now - start >= timeout )) && { echo timeout; return; }
    st="$(pane_state "$pane")"
    [[ "$st" == missing ]] && { echo pane-gone; return; }
    if (( now - start >= grace )) && [[ "$st" == done || "$st" == idle ]]; then
      # 落ち着いた直後に書き出される場合があるので一拍おいてから確定させる。
      sleep 3
      classify_result "$result"; return
    fi
    sleep 2
  done
}

report_meta() {
  local pane="$1" role="$2" status="$3" result="$4" parent="$5" issue="${6:-}"
  # 値は 64 文字ほどで切られるので、絶対パスではなく作業ディレクトリ名とファイル名だけ載せる。
  local short="$(basename "$(dirname "$result")")/$(basename "$result")"
  # トークンキーは ^[A-Za-z0-9_-]{1,32}$ のみ。ドットは invalid_metadata_token になる。
  herdr pane report-metadata "$pane" --source codex-run \
    --token "codex_role=$role" --token "codex_status=$status" \
    --token "codex_result=$short" --token "codex_parent=$parent" \
    ${issue:+--token "codex_issue=$issue"} >/dev/null 2>&1 || true
}

emit_json() {
  python3 -c 'import json,sys; print(json.dumps(dict(zip(sys.argv[1::2], sys.argv[2::2])), ensure_ascii=False))' "$@"
}
