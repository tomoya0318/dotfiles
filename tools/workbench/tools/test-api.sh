#!/bin/bash
# workbench の HTTP API の挙動を固定する。
#
# リファクタリングの前後で同じ結果になることを確認するために使う。
# 「あるべき姿」ではなく「現在そうなっている」を記録したものなので、
# 仕様を変えたときは意図的にこのスクリプトを書き換える。
#
# ws による外部変更の通知は curl では検証できないため対象外。
#
# 使い方: tools/test-api.sh [port]
set -uo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${1:-5199}"
BASE="http://localhost:$PORT"
WORK="$(mktemp -d)"
STATE="$WORK/state"
REPO="$WORK/repo"
SESSION="$REPO/tmp/0001_x"
REVIEW="$SESSION/review"
REPORT="$REVIEW/report.json"
THREAD="$REVIEW/thread.json"
SERVER_PID=""
SESSION_ID=""

pass=0
fail=0

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1))
    printf '  ok   %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$label" "$expected" "$actual"
  fi
}

post() {
  curl -sS -X POST -H 'content-type: application/json' -d "$1" \
    "$BASE/api/sessions/$SESSION_ID/thread"
}

# --- 準備 ---

mkdir -p "$STATE" "$REVIEW"
git init -q "$REPO"
printf '["%s"]\n' "$REPO" > "$STATE/roots.json"
cat > "$SESSION/plan.md" <<'EOF'
# test plan
EOF
cat > "$SESSION/review.md" <<'EOF'
# test review
EOF
cat > "$REPORT" <<EOF
{
  "ref": "test-ref",
  "subject": "test subject",
  "repo": "$REPO",
  "threadPath": "$THREAD",
  "stats": { "files": 1, "hunks": 1, "additions": 1, "deletions": 0, "coreCandidates": 1 },
  "files": [{ "id": "F0", "old": "a.txt", "new": "a.txt", "path": "a.txt", "diff": "", "hunks": ["h001"] }],
  "hunks": [{ "id": "h001", "file": "a.txt", "fileId": "F0", "index": 0, "kinds": [], "coreCandidate": true, "add": 1, "del": 0 }],
  "fileOps": [],
  "groups": []
}
EOF

# 先にポートの空きを確かめる。
# ここを飛ばすと、別の workbench が同じポートで動いていたときに
# --strictPort で vite が死んでも curl はそのサーバに通ってしまい、
# 以降の POST が実運用中の thread.json を書き換える。
if (exec 3<>"/dev/tcp/localhost/$PORT") 2>/dev/null; then
  exec 3>&-
  echo "ポート $PORT は既に使われている。引数で別のポートを指定すること。" >&2
  exit 1
fi

echo "起動中 (port $PORT)..."
WORKBENCH_STATE_DIR="$STATE" \
WORKBENCH_CACHE_DIR="$WORK/.vite" \
  pnpm --dir "$APP_DIR" exec vite --port "$PORT" --strictPort >"$WORK/server.log" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 60); do
  # 自分が起動したプロセスが生きていることを条件にする
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "サーバが起動に失敗した。ログ:" >&2
    cat "$WORK/server.log" >&2
    exit 1
  fi
  [ "$(curl -sf "$BASE/api/health" 2>/dev/null | jq -r .app 2>/dev/null)" = workbench ] && break
  sleep 0.5
done
if [ "$(curl -sf "$BASE/api/health" 2>/dev/null | jq -r .app 2>/dev/null)" != workbench ]; then
  echo "サーバが応答しなかった。ログ:" >&2
  cat "$WORK/server.log" >&2
  exit 1
fi

SESSIONS="$(curl -sS "$BASE/api/sessions")"
SESSION_ID="$(printf '%s' "$SESSIONS" | jq -r '.repositories[0].branches[0].sessions[0].id')"

echo
echo "health と sessions"
check 'GET /api/health がアプリ名を返す' 'workbench' \
  "$(curl -sS "$BASE/api/health" | jq -r .app)"
check 'repository → branch → session の階層を返す' 'repo 1 0001_x' \
  "$(printf '%s' "$SESSIONS" | jq -r '"\(.repositories[0].name) \(.repositories[0].branches|length) \(.repositories[0].branches[0].sessions[0].name)"')"
check 'session に4文書の存在を返す' 'true true true false' \
  "$(printf '%s' "$SESSIONS" | jq -r '.repositories[0].branches[0].sessions[0].documents | "\(.plan) \(.review) \(.report) \(.thread)"')"
check 'session に絶対 workDir を返す' "$(realpath "$SESSION")" \
  "$(printf '%s' "$SESSIONS" | jq -r '.repositories[0].branches[0].sessions[0].workDir')"
check 'resolve が workDir から session ID を返す' "$SESSION_ID" \
  "$(curl -sS -G --data-urlencode "workDir=$SESSION" "$BASE/api/resolve" | jq -r .id)"

echo
echo "report"
check 'GET report が ref を返す' 'test-ref' \
  "$(curl -sS "$BASE/api/sessions/$SESSION_ID/report" | jq -r .ref)"

echo
echo "thread の初期状態"
check 'thread が無いときは空スレッド' \
  '0 0' "$(curl -sS "$BASE/api/sessions/$SESSION_ID/thread" | jq -r '"\(.comments|length) \(.checks|length)"')"

echo
echo "add と nextId の採番"
check '1件目の id は c1' 'c1' \
  "$(post '{"op":"add","comment":{"hunk":"h001","side":"new","offset":0,"lineText":"foo","label":"fix","turns":[{"by":"you","body":"1件目"}],"state":"open"}}' \
     | jq -r '.comments[-1].id')"
check '2件目の id は c2' 'c2' \
  "$(post '{"op":"add","comment":{"hunk":"h001","side":"new","offset":1,"lineText":"bar","label":"note","turns":[{"by":"you","body":"2件目"}],"state":"open"}}' \
     | jq -r '.comments[-1].id')"
check 'ファイルにも2件書かれている' '2' "$(jq -r '.comments|length' "$THREAD")"

echo
echo "reply"
check 'reply で turns が増える' '2' \
  "$(post '{"op":"reply","id":"c1","turn":{"by":"claude","body":"直した"}}' \
     | jq -r '.comments[] | select(.id=="c1") | .turns | length')"
check 'reply すると state は open に戻る' 'open' \
  "$(jq -r '.comments[] | select(.id=="c1") | .state' "$THREAD")"

echo
echo "resolve"
check 'resolve で state が resolved' 'resolved' \
  "$(post '{"op":"resolve","id":"c2"}' | jq -r '.comments[] | select(.id=="c2") | .state')"

echo
echo "checks"
check 'checks が入る' 'g1 g2' \
  "$(post '{"op":"checks","checks":["g1","g2"]}' | jq -r '.checks | join(" ")')"
check 'checks は comments を壊さない' '2' "$(jq -r '.comments|length' "$THREAD")"

echo
echo "remove"
# c1 は claude のターンを含む。c2 は you のみ。
check 'AI のターンを含む c1 は消えない' 'c1' \
  "$(post '{"op":"remove","id":"c1"}' | jq -r '.comments[] | select(.id=="c1") | .id')"
check 'you だけの c2 は消える' '0' \
  "$(post '{"op":"remove","id":"c2"}' | jq -r '[.comments[] | select(.id=="c2")] | length')"
check '存在しない id を消しても壊れない' '1' \
  "$(post '{"op":"remove","id":"c99"}' | jq -r '.comments|length')"

echo
echo "未知の op"
check '未知の op は何もしない' '1' \
  "$(post '{"op":"nonexistent"}' | jq -r '.comments|length')"

echo
echo "handoff"
rm -f "$REVIEW/handoff"
curl -sS -X POST "$BASE/api/sessions/$SESSION_ID/handoff" >/dev/null
check 'handoff が review ディレクトリにできる' 'yes' \
  "$([ -f "$REVIEW/handoff" ] && echo yes || echo no)"

echo
echo "メソッドと 404"
check 'PUT thread は 405' '405' \
  "$(curl -sS -o /dev/null -w '%{http_code}' -X PUT "$BASE/api/sessions/$SESSION_ID/thread")"
check '未知の session ID は 404' '404' \
  "$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/sessions/unknown/report")"
check '未知の /api endpoint は 404' '404' \
  "$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/unknown")"
check '未知の /api endpoint は JSON' 'application/json' \
  "$(curl -sSI "$BASE/api/unknown" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type" { print $2 }')"

echo
echo "壊れた入力"
cp "$THREAD" "$WORK/thread.bak"
echo 'not json' > "$THREAD"
check '壊れた thread.json は空スレッド扱い' '0 0' \
  "$(curl -sS "$BASE/api/sessions/$SESSION_ID/thread" | jq -r '"\(.comments|length) \(.checks|length)"')"
cp "$WORK/thread.bak" "$THREAD"

mv "$REPORT" "$REPORT.bak"
check 'report が無いと 404' '404' \
  "$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/sessions/$SESSION_ID/report")"
mv "$REPORT.bak" "$REPORT"

echo
echo "realpath の封じ込め"
printf '{}\n' > "$WORK/outside.json"
mv "$REPORT" "$REPORT.real"
ln -s "$WORK/outside.json" "$REPORT"
check 'workDir 外の report symlink は 403' '403' \
  "$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/sessions/$SESSION_ID/report")"
rm "$REPORT"
mv "$REPORT.real" "$REPORT"

mv "$THREAD" "$THREAD.real"
ln -s "$WORK/outside.json" "$THREAD"
check 'workDir 外の thread symlink は 403' '403' \
  "$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/sessions/$SESSION_ID/thread")"
rm "$THREAD"
mv "$THREAD.real" "$THREAD"

rm -f "$REVIEW/handoff"
printf 'keep\n' > "$WORK/outside-handoff"
ln -s "$WORK/outside-handoff" "$REVIEW/handoff"
check 'workDir 外の handoff symlink は 403' '403' \
  "$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$BASE/api/sessions/$SESSION_ID/handoff")"
check 'workDir 外の handoff は変更されない' 'keep' "$(cat "$WORK/outside-handoff")"

echo
echo "計画段階のセッション"
PLAN_ONLY="$REPO/tmp/0002_plan-only"
mkdir -p "$PLAN_ONLY"
cat > "$PLAN_ONLY/plan.md" <<'EOF'
# plan only
EOF
UPDATED_SESSIONS="$(curl -sS "$BASE/api/sessions")"
PLAN_ONLY_ID="$(printf '%s' "$UPDATED_SESSIONS" \
  | jq -r '.repositories[0].branches[0].sessions[] | select(.name=="0002_plan-only") | .id')"
check 'git TTL 内でも新しい session を即時に発見する' '2' \
  "$(printf '%s' "$UPDATED_SESSIONS" | jq -r '.repositories[0].branches[0].sessions | length')"
check 'review ディレクトリが無い report は 404' '404' \
  "$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/sessions/$PLAN_ONLY_ID/report")"
check 'review ディレクトリが無い thread は空スレッド' '0 0' \
  "$(curl -sS "$BASE/api/sessions/$PLAN_ONLY_ID/thread" | jq -r '"\(.comments|length) \(.checks|length)"')"
curl -sS -X POST "$BASE/api/sessions/$PLAN_ONLY_ID/handoff" >/dev/null
check 'handoff が review ディレクトリを作る' 'yes' \
  "$([ -f "$PLAN_ONLY/review/handoff" ] && echo yes || echo no)"

echo
echo "----------------------------------------"
printf 'ok %d / fail %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
