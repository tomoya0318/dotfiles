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
HOST="127.0.0.1"
BASE="http://$HOST:$PORT"
WORK="$(mktemp -d)"
STATE="$WORK/state"
REPO="$WORK/repo"
SESSION="$REPO/tmp/0001_x"
REVIEW="$SESSION/review"
REPORT="$REVIEW/report.json"
THREAD="$REVIEW/thread.json"
SERVER_PID=""
SESSION_ID=""
SERVER_MODE="tcp"
IPC_DIR="$WORK/api-ipc"

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

api_curl() {
  local method="GET" body="" content_type="" url="" query=""
  local output_body=true write_format="" fail_on_error=false head_only=false force_get=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -X)
        method="$2"
        shift 2
        ;;
      -H)
        content_type="${2#*: }"
        shift 2
        ;;
      -d|--data|--data-raw)
        body="$2"
        [ "$force_get" = true ] || method="POST"
        shift 2
        ;;
      -G)
        method="GET"
        force_get=true
        shift
        ;;
      --data-urlencode)
        local key="${2%%=*}" value="${2#*=}" encoded
        encoded="$(jq -rn --arg value "$value" '$value|@uri')"
        query="${query:+$query&}$key=$encoded"
        shift 2
        ;;
      -o)
        [ "$2" = "/dev/null" ] && output_body=false
        shift 2
        ;;
      -w)
        write_format="$2"
        shift 2
        ;;
      -*)
        [[ "$1" == *I* ]] && {
          method="HEAD"
          head_only=true
        }
        [[ "$1" == *f* ]] && fail_on_error=true
        shift
        ;;
      *)
        url="$1"
        shift
        ;;
    esac
  done

  local path="${url#"$BASE"}" request response status request_id
  local request_file response_file
  [ -n "$query" ] && path="$path?$query"
  request_file="$(mktemp "$IPC_DIR/requests/request.XXXXXX")"
  request_id="$(basename "$request_file")"
  response_file="$IPC_DIR/responses/$request_id.json"
  request="$(jq -cn \
    --arg requestId "$request_id" \
    --arg method "$method" \
    --arg path "$path" \
    --arg body "$body" \
    --arg contentType "$content_type" \
    '{
      requestId:$requestId,
      method:$method,
      path:$path,
      body:$body,
      headers:(if $contentType=="" then {} else {"content-type":$contentType} end)
    }')"
  printf '%s\n' "$request" > "$request_file"
  mv "$request_file" "$request_file.json"
  for _ in $(seq 1 1000); do
    [ -f "$response_file" ] && break
    sleep 0.01
  done
  response="$(cat "$response_file")"
  rm "$response_file"
  status="$(printf '%s' "$response" | jq -r .status)"
  if [ "$fail_on_error" = true ] && [ "$status" -ge 400 ]; then
    return 22
  fi
  if [ "$head_only" = true ]; then
    printf '%s' "$response" | jq -r \
      '.headers | to_entries[] | "\(.key): \(.value)\r"'
  elif [ "$output_body" = true ]; then
    printf '%s' "$response" | jq -rj .body
  fi
  [ "$write_format" = "%{http_code}" ] && printf '%s' "$status"
}

curl() {
  if [ "$SERVER_MODE" = "in-process" ]; then
    api_curl "$@"
  else
    command curl "$@"
  fi
}

mkdir -p "$STATE" "$REVIEW"
git init -q "$REPO"
printf '["%s"]\n' "$REPO" > "$STATE/roots.json"
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

if ! node -e "
  const server = require('node:net').createServer();
  server.once('error', () => process.exit(1));
  server.listen(0, '$HOST', () => server.close());
" 2>/dev/null; then
  SERVER_MODE="in-process"
fi

if [ "$SERVER_MODE" = "tcp" ]; then
  # 別のサーバへの誤接続を避けるため、起動前にポートの空きを確かめる。
  if (exec 3<>"/dev/tcp/$HOST/$PORT") 2>/dev/null; then
    exec 3>&-
    echo "ポート $PORT は既に使われている。引数で別のポートを指定すること。" >&2
    exit 1
  fi
fi

echo "起動中 (port $PORT)..."
if [ "$SERVER_MODE" = "tcp" ]; then
  WORKBENCH_STATE_DIR="$STATE" \
  WORKBENCH_CACHE_DIR="$WORK/.vite" \
    pnpm --dir "$APP_DIR" exec vite --host "$HOST" --port "$PORT" --strictPort >"$WORK/server.log" 2>&1 &
  SERVER_PID=$!
else
  mkdir -p "$IPC_DIR/requests" "$IPC_DIR/responses"
  WORKBENCH_STATE_DIR="$STATE" \
  WORKBENCH_CACHE_DIR="$WORK/.vite" \
    node "$APP_DIR/server/testApiHarness.mjs" "$APP_DIR" "$IPC_DIR" \
      > /dev/null 2>"$WORK/server.log" &
  SERVER_PID=$!
  for _ in $(seq 1 1000); do
    [ -f "$IPC_DIR/ready" ] && break
    sleep 0.01
  done
fi

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
check 'session に3文書の存在を返す' 'true true false' \
  "$(printf '%s' "$SESSIONS" | jq -r '.repositories[0].branches[0].sessions[0].documents | "\(.review) \(.report) \(.thread)"')"
check 'session に絶対 workDir を返す' "$(realpath "$SESSION")" \
  "$(printf '%s' "$SESSIONS" | jq -r '.repositories[0].branches[0].sessions[0].workDir')"
SESSION_META="$(curl -sS "$BASE/api/sessions/$SESSION_ID")"
check 'session メタ API が名前を返す' '0001_x' \
  "$(printf '%s' "$SESSION_META" | jq -r .name)"
check 'session メタ API が文書の存在を返す' 'true true false' \
  "$(printf '%s' "$SESSION_META" | jq -r \
    '.documents | "\(.review) \(.report) \(.thread)"')"
check 'resolve が workDir から session ID を返す' "$SESSION_ID" \
  "$(curl -sS -G --data-urlencode "workDir=$SESSION" "$BASE/api/resolve" | jq -r .id)"

echo
echo "report"
check 'GET report が ref を返す' 'test-ref' \
  "$(curl -sS "$BASE/api/sessions/$SESSION_ID/report" | jq -r .ref)"

echo
echo "gen.py の指摘メタデータ"
GEN_REPO="$WORK/gen-repo"
GEN_REVIEW="$WORK/gen-review"
mkdir -p "$GEN_REPO" "$GEN_REVIEW"
git init -q "$GEN_REPO"
printf 'base\n' > "$GEN_REPO/a.txt"
git -C "$GEN_REPO" add a.txt
git -C "$GEN_REPO" -c user.name=test -c user.email=test@example.com \
  -c commit.gpgsign=false commit -qm base
printf 'changed\n' > "$GEN_REPO/a.txt"
cat > "$GEN_REVIEW/findings.json" <<'EOF'
{"findings":[{"hunk":"h001","line":"changed","classification":"欠陥","confidence":"高","body":"要件を満たさない"}]}
EOF
python3 "$APP_DIR/tools/gen.py" "$GEN_REPO" HEAD --uncommitted \
  --findings "$GEN_REVIEW/findings.json" --thread "$GEN_REVIEW/thread.json" \
  -o "$GEN_REVIEW/report.json" >/dev/null
check 'gen.py が classification を thread.json に保存する' '欠陥' \
  "$(jq -r '.comments[0].classification' "$GEN_REVIEW/thread.json")"
check 'gen.py が classification を report.json に含める' '欠陥' \
  "$(jq -r '.thread.comments[0].classification' "$GEN_REVIEW/report.json")"
cat > "$GEN_REVIEW/findings-old.json" <<'EOF'
{"findings":[{"hunk":"h001","line":"changed","body":"旧形式の指摘"}]}
EOF
python3 "$APP_DIR/tools/gen.py" "$GEN_REPO" HEAD --uncommitted \
  --findings "$GEN_REVIEW/findings-old.json" --thread "$GEN_REVIEW/thread-old.json" \
  -o "$GEN_REVIEW/report-old.json" >/dev/null
check 'classification がない旧 findings は thread.json で省略される' 'false' \
  "$(jq '.comments[0] | has("classification")' "$GEN_REVIEW/thread-old.json")"
check 'classification がない旧 findings は report.json で省略される' 'false' \
  "$(jq '.thread.comments[0] | has("classification")' "$GEN_REVIEW/report-old.json")"

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
echo "review ディレクトリが無いセッション"
BARE="$REPO/tmp/0002_bare"
mkdir -p "$BARE"
cat > "$BARE/review.md" <<'EOF'
# bare review
EOF
UPDATED_SESSIONS="$(curl -sS "$BASE/api/sessions")"
BARE_ID="$(printf '%s' "$UPDATED_SESSIONS" \
  | jq -r '.repositories[0].branches[0].sessions[] | select(.name=="0002_bare") | .id')"
check 'git TTL 内でも新しい session を即時に発見する' '2' \
  "$(printf '%s' "$UPDATED_SESSIONS" | jq -r '.repositories[0].branches[0].sessions | length')"
check 'review ディレクトリが無い report は 404' '404' \
  "$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/sessions/$BARE_ID/report")"
check 'review ディレクトリが無い thread は空スレッド' '0 0' \
  "$(curl -sS "$BASE/api/sessions/$BARE_ID/thread" | jq -r '"\(.comments|length) \(.checks|length)"')"
curl -sS -X POST "$BASE/api/sessions/$BARE_ID/handoff" >/dev/null
check 'handoff が review ディレクトリを作る' 'yes' \
  "$([ -f "$BARE/review/handoff" ] && echo yes || echo no)"

echo
echo "----------------------------------------"
printf 'ok %d / fail %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
