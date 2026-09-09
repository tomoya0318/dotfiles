#!/usr/bin/env bash
# llm-wiki への自動捕捉で共有する処理。
# enqueue / drain / capture の 3 スクリプトから source する。

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/llm-wiki"
QUEUE="$STATE_DIR/capture-queue.tsv"
DONE_DIR="$STATE_DIR/done"
REGISTRY="${XDG_CONFIG_HOME:-$HOME/.config}/llm-wiki/registry.toml"

# headless の claude を hook から呼ぶと、その子セッションが同じ hook を
# 登録して無限再帰する。捕捉中はこの変数を立て、全 hook の先頭で抜ける。
wiki_capture_guard() {
  [ -n "${WIKI_CAPTURE:-}" ] && exit 0
  return 0
}

wiki_expand() {
  case "$1" in
    "~"*) printf '%s' "$HOME${1#\~}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# 作業ディレクトリから捕捉先の Wiki を引く。
# 一致しなければ何も出力せず 1 を返す。捕捉しないことが既定である。
wiki_resolve() {
  local cwd="$1"
  [ -f "$REGISTRY" ] || return 1
  python3 - "$REGISTRY" "$cwd" <<'PY'
import os, re, sys, pathlib

registry, cwd = sys.argv[1], os.path.realpath(sys.argv[2])
text = pathlib.Path(registry).read_text()

entries, cur = [], None
for line in text.splitlines():
    line = line.split("#", 1)[0].strip()
    if line == "[[wiki]]":
        cur = {"path": None, "match": []}
        entries.append(cur)
    elif cur is not None and line.startswith("path"):
        cur["path"] = line.split("=", 1)[1].strip().strip('"')
    elif cur is not None and line.startswith("match"):
        cur["match"] = re.findall(r'"([^"]+)"', line)

def accept(entry):
    wiki = os.path.realpath(os.path.expanduser(entry["path"]))
    if os.path.isdir(os.path.join(wiki, "inbox")):
        print(wiki)
        sys.exit(0)

for e in entries:
    if not e["path"]:
        continue
    # match を書かないエントリは、すべてのセッションに一致する
    if not e["match"]:
        accept(e)
        continue
    for m in e["match"]:
        base = os.path.realpath(os.path.expanduser(m))
        if cwd == base or cwd.startswith(base.rstrip(os.sep) + os.sep):
            accept(e)
sys.exit(1)
PY
}

# transcript のパスとサイズで冪等キーを作る。
# セッションを再開して作業が増えればサイズが変わり、再度処理される。
wiki_done_key() {
  local transcript="$1" size
  size=$(wc -c <"$transcript" 2>/dev/null | tr -d ' ')
  printf '%s' "$(printf '%s:%s' "$transcript" "$size" | shasum -a 256 | cut -c1-32)"
}
