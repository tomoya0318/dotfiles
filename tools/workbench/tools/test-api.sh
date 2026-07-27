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
PLAN="$SESSION/plan.md"
PLAN_STATE="$REVIEW/plan.json"
PLAN_APPROVED="$REVIEW/plan-approved"
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

plan_post() {
  curl -sS -X POST -H 'content-type: application/json' -d "$1" \
    "$BASE/api/sessions/$SESSION_ID/plan/state"
}

plan_status() {
  curl -sS -o /dev/null -w '%{http_code}' -X POST \
    -H 'content-type: application/json' -d "$2" \
    "$BASE/api/sessions/$SESSION_ID/plan/$1"
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
cat > "$PLAN" <<'EOF'
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
check 'session に4文書の存在を返す' 'true true true false' \
  "$(printf '%s' "$SESSIONS" | jq -r '.repositories[0].branches[0].sessions[0].documents | "\(.plan) \(.review) \(.report) \(.thread)"')"
check 'session に絶対 workDir を返す' "$(realpath "$SESSION")" \
  "$(printf '%s' "$SESSIONS" | jq -r '.repositories[0].branches[0].sessions[0].workDir')"
SESSION_META="$(curl -sS "$BASE/api/sessions/$SESSION_ID")"
check 'session メタ API が名前を返す' '0001_x' \
  "$(printf '%s' "$SESSION_META" | jq -r .name)"
check 'session メタ API が文書の存在を返す' 'true true true false' \
  "$(printf '%s' "$SESSION_META" | jq -r \
    '.documents | "\(.plan) \(.review) \(.report) \(.thread)"')"
check 'resolve が workDir から session ID を返す' "$SESSION_ID" \
  "$(curl -sS -G --data-urlencode "workDir=$SESSION" "$BASE/api/resolve" | jq -r .id)"

echo
echo "report"
check 'GET report が ref を返す' 'test-ref' \
  "$(curl -sS "$BASE/api/sessions/$SESSION_ID/report" | jq -r .ref)"

echo
echo "plan の解析"
cat > "$PLAN" <<'EOF'
# test plan

## 概要

概要の導入。

### 子見出し

子の本文。

```markdown
## フェンス内の判断
```

~~~text
## フェンス内の方針
~~~

- ```markdown
  ## フェンス内のリスト項目
  ```

<!--
## コメント内の判断
-->

## 方針

HTML コメント開始は `<!--` です。

### 独自の子

継承する本文。

### 判断

#### 内側

上書きする本文。

## 判断__TRAILING__

末尾空白。

##　判断

全角空白。

## 判断 ##

閉じ ATX。

##	判断

タブ区切り。

## メモ

標準外。

## ﾘｽｸ

<!-- テンプレートの説明だけ -->
EOF
sed 's/## 判断__TRAILING__$/## 判断 /' "$PLAN" > "$WORK/plan-with-trailing-space.md"
mv "$WORK/plan-with-trailing-space.md" "$PLAN"
PLAN_RESPONSE="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan")"
check 'plan がバイト列 SHA-256 を返す' \
  "$(shasum -a 256 "$PLAN" | awk '{print $1}')" \
  "$(printf '%s' "$PLAN_RESPONSE" | jq -r .hash)"
check '標準節名から level を引く' 'focus decision' \
  "$(printf '%s' "$PLAN_RESPONSE" | jq -r \
    '([.nodes[] | select(.title=="概要" and .kind=="section")][0].level)
     + " "
     + ([.nodes[] | select(.title=="判断" and .parent=="@doc")][0].level)')"
check '標準外の節名は focus になる' 'focus' \
  "$(printf '%s' "$PLAN_RESPONSE" | jq -r \
    '.nodes[] | select(.title=="メモ") | .level')"
check '標準外の子見出しは祖先の level を継承する' 'focus' \
  "$(printf '%s' "$PLAN_RESPONSE" | jq -r \
    '.nodes[] | select(.title=="独自の子") | .level')"
check '深い標準節名が祖先の level を上書きする' 'decision' \
  "$(printf '%s' "$PLAN_RESPONSE" | jq -r \
    '.nodes[] | select(.title=="内側") | .level')"
check '節名の空白と閉じ ATX の表記ゆれを正規化する' '4 4' \
  "$(printf '%s' "$PLAN_RESPONSE" | jq -r \
    '[.nodes[] | select(.title=="判断" and .parent=="@doc")]
     | "\(length) \([.[] | select(.level=="decision")]|length)"')"
check '節名を NFKC 正規化して level を引く' 'focus' \
  "$(printf '%s' "$PLAN_RESPONSE" | jq -r \
    '.nodes[] | select(.title=="ﾘｽｸ") | .level')"
check '最初の子見出し前の地の文が葉になる' '1 focus' \
  "$(printf '%s' "$PLAN_RESPONSE" | jq -r \
    '[.nodes[] | select(.title=="概要" and .kind=="preamble" and .leaf)]
     | "\(length) \(.[0].level)"')"
check 'コードフェンス内の見出しを検出しない' '0' \
  "$(printf '%s' "$PLAN_RESPONSE" | jq -r \
    '[.nodes[] | select(.title|startswith("フェンス内"))] | length')"
check 'HTML コメント内の見出しを検出しない' '0' \
  "$(printf '%s' "$PLAN_RESPONSE" | jq -r \
    '[.nodes[] | select(.title|startswith("コメント内"))] | length')"
check 'コードスパン内の HTML コメント開始記号で後続見出しを隠さない' '1' \
  "$(printf '%s' "$PLAN_RESPONSE" | jq -r \
    '[.nodes[] | select(.title=="独自の子")] | length')"
EMPTY_LEAF_ID="$(printf '%s' "$PLAN_RESPONSE" | jq -r \
  '.nodes[] | select(.title=="ﾘｽｸ") | .id')"
check 'HTML コメントだけの葉はレビュー対象にしない' 'false 400' \
  "$(printf '%s' "$PLAN_RESPONSE" | jq -r \
    '.nodes[] | select(.title=="ﾘｽｸ") | .leaf') \
$(plan_status state "$(jq -cn --arg node "$EMPTY_LEAF_ID" \
  '{revision:0,op:"confirm",nodeId:$node}')")"
check '標準外の節名を警告する' '1' \
  "$(printf '%s' "$PLAN_RESPONSE" | jq -r \
    '[.warnings[] | select(contains("メモ"))] | length')"

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
echo "plan state の op"
rm -f "$PLAN_STATE" "$PLAN_APPROVED"
cat > "$PLAN" <<'EOF'
# state plan

## 概要

### Alpha

alpha body

### Beta

beta body

## 判断

### Choice

choice body
EOF
PLAN_RESPONSE="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan")"
ALPHA_ID="$(printf '%s' "$PLAN_RESPONSE" | jq -r '.nodes[] | select(.title=="Alpha") | .id')"
BETA_ID="$(printf '%s' "$PLAN_RESPONSE" | jq -r '.nodes[] | select(.title=="Beta") | .id')"
check 'plan state は revision 0 で始まる' '0' \
  "$(printf '%s' "$PLAN_RESPONSE" | jq -r .revision)"

STATE_RESPONSE="$(plan_post "$(jq -cn --arg node "$ALPHA_ID" \
  '{revision:0,op:"confirm",nodeId:$node}')")"
check 'confirm が confirmations 単一配列へ入る' '1 false' \
  "$(printf '%s' "$STATE_RESPONSE" | jq -r \
    '"\(.confirmations|length) \(has("accepts"))"')"
check '古い revision の POST は 409' '409' \
  "$(plan_status state "$(jq -cn --arg node "$BETA_ID" \
    '{revision:0,op:"confirm",nodeId:$node}')")"

STATE_RESPONSE="$(plan_post "$(jq -cn --arg node "$ALPHA_ID" \
  '{revision:1,op:"add",comment:{anchor:{kind:"plan",nodeId:$node},
    label:"fix",turns:[{by:"you",body:"直してください"}],state:"open"}}')")"
check 'add がコメントを追加する' 'c1 2' \
  "$(printf '%s' "$STATE_RESPONSE" | jq -r \
    '"\(.comments[-1].id) \(.revision)"')"
check 'add が対象ノードの confirmation を落とす' '0' \
  "$(printf '%s' "$STATE_RESPONSE" | jq -r \
    --arg node "$ALPHA_ID" '[.confirmations[] | select(.nodeId==$node)] | length')"
check '存在しない nodeId を拒否する' '400' \
  "$(plan_status state \
    '{"revision":2,"op":"confirm","nodeId":"not-a-node"}')"

STATE_RESPONSE="$(plan_post \
  '{"revision":2,"op":"reply","id":"c1","turn":{"by":"claude","body":"修正しました"}}')"
check 'reply が AI 発言を追加して answered にする' '2 answered 3' \
  "$(printf '%s' "$STATE_RESPONSE" | jq -r \
    '. as $state | .comments[] | select(.id=="c1")
     | "\(.turns|length) \(.state) \($state.revision)"')"
check 'AI 発言を含むコメントは remove を拒否する' '409' \
  "$(plan_status state '{"revision":3,"op":"remove","id":"c1"}')"

STATE_RESPONSE="$(plan_post '{"revision":3,"op":"resolve","id":"c1"}')"
check 'resolve がコメントを解決する' 'resolved 4' \
  "$(printf '%s' "$STATE_RESPONSE" | jq -r \
    '. as $state | .comments[] | select(.id=="c1")
     | "\(.state) \($state.revision)"')"
STATE_RESPONSE="$(plan_post "$(jq -cn --arg node "$BETA_ID" \
  '{revision:4,op:"confirm",nodeId:$node}')")"
STATE_RESPONSE="$(plan_post "$(jq -cn --arg node "$BETA_ID" \
  '{revision:5,op:"unconfirm",nodeId:$node}')")"
check 'unconfirm が対象の confirmation を外す' '0 6' \
  "$(printf '%s' "$STATE_RESPONSE" | jq -r --arg node "$BETA_ID" \
    '"\([.confirmations[] | select(.nodeId==$node)]|length) \(.revision)"')"

STATE_RESPONSE="$(plan_post "$(jq -cn --arg node "$BETA_ID" \
  '{revision:6,op:"add",comment:{anchor:{kind:"plan",nodeId:$node},
    label:"note",turns:[{by:"you",body:"メモ"}],state:"open"}}')")"
STATE_RESPONSE="$(plan_post '{"revision":7,"op":"remove","id":"c2"}')"
check '人間だけのコメントは remove できる' '0 8' \
  "$(printf '%s' "$STATE_RESPONSE" | jq -r \
    '"\([.comments[] | select(.id=="c2")]|length) \(.revision)"')"

STATE_RESPONSE="$(plan_post "$(jq -cn --arg node "$BETA_ID" \
  '{revision:8,op:"confirm",nodeId:$node}')")"
check 'op ごとに revision が増える' '9' \
  "$(printf '%s' "$STATE_RESPONSE" | jq -r .revision)"

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

jq --arg node "$ALPHA_ID" '
  del(.revision)
  | .nodes += [.nodes[1], {"id":"broken"}]
  | .comments += [{
      "id":"c99",
      "anchor":{"kind":"plan","nodeId":$node},
      "label":"fix",
      "turns":[
        {"by":"you","body":"正しい人間の発言"},
        {"by":"claude","body":"正しい AI の返答"},
        {"by":"you","body":"AI が人間を騙る発言"}
      ],
      "state":"open"
    }]
  | .confirmations += [{
      "nodeId":$node,
      "hash":"broken",
      "at":"2026-01-01T00:00:00.000Z"
    }]
' "$PLAN_STATE" > "$WORK/broken-plan.json"
mv "$WORK/broken-plan.json" "$PLAN_STATE"
BROKEN_PLAN="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan/state")"
check 'revision 欠落だけを 0 に補正する' '0' \
  "$(printf '%s' "$BROKEN_PLAN" | jq -r .revision)"
check '壊れたノードと重複 ID だけを落とす' '0 0' \
  "$(printf '%s' "$BROKEN_PLAN" | jq -r \
    '[.nodes[].id] as $ids
     | "\(($ids|length)-($ids|unique|length)) \([.nodes[] | select(.id=="broken")]|length)"')"
check '人間を騙る AI 発言だけを落とす' '2 1' \
  "$(printf '%s' "$BROKEN_PLAN" | jq -r \
    '.comments[] | select(.id=="c99")
     | "\(.turns|length) \([.turns[] | select(.by=="you")]|length)"')"
check '正常なコメントと確認を巻き添えにしない' '1 1' \
  "$(printf '%s' "$BROKEN_PLAN" | jq -r --arg node "$BETA_ID" \
    '"\([.comments[] | select(.id=="c1")]|length) \([.confirmations[] | select(.nodeId==$node)]|length)"')"
check '除外した要素を warnings に載せる' '3' \
  "$(printf '%s' "$BROKEN_PLAN" | jq -r \
    '[.warnings[] | select(
      contains("revision")
      or contains("重複したノード")
      or contains("不正な発言")
    )] | length')"

jq '.revision = 9007199254740992' "$PLAN_STATE" > "$WORK/unsafe-revision.json"
mv "$WORK/unsafe-revision.json" "$PLAN_STATE"
UNSAFE_REVISION="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan/state")"
check '安全な整数でない revision を補正する' '0 1' \
  "$(printf '%s' "$UNSAFE_REVISION" | jq -r \
    '"\(.revision) \([.warnings[] | select(contains("revision"))]|length)"')"
check '安全な整数でない revision の POST を拒否する' '400' \
  "$(plan_status state "$(jq -cn --arg node "$ALPHA_ID" \
    '{revision:9007199254740992,op:"confirm",nodeId:$node}')")"

jq '.revision = 9007199254740991' "$PLAN_STATE" > "$WORK/exhausted-revision.json"
mv "$WORK/exhausted-revision.json" "$PLAN_STATE"
check '上限 revision の POST は状態を変えず 409' '409 9007199254740991' \
  "$(plan_status state "$(jq -cn --arg node "$ALPHA_ID" \
    '{revision:9007199254740991,op:"confirm",nodeId:$node}')") \
$(jq -r .revision "$PLAN_STATE")"

jq '
  (.nodes[] | select(.id=="@doc") | .hash) = "broken"
  | .nodes += [{
      "id":"n999999999999999999999",
      "parent":"@doc",
      "index":999,
      "hash":"000000000000",
      "level":"focus",
      "leaf":true
    }]
' \
  "$PLAN_STATE" > "$WORK/broken-doc-node.json"
mv "$WORK/broken-doc-node.json" "$PLAN_STATE"
sed 's/alpha body/alpha changed body/' "$PLAN" > "$WORK/changed-plan.md"
cat >> "$WORK/changed-plan.md" <<'EOF'

## リスク

new risk
EOF
mv "$WORK/changed-plan.md" "$PLAN"
BROKEN_DOC="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan")"
check '壊れた @doc だけを落として子ノード ID を位置照合で保つ' "$ALPHA_ID" \
  "$(printf '%s' "$BROKEN_DOC" | jq -r \
    '.nodes[] | select(.title=="Alpha") | .id')"
check '巨大な既存 ID の後も数字だけの連番 ID を割り当てる' 'true' \
  "$(printf '%s' "$BROKEN_DOC" | jq -r \
    '.nodes[] | select(.title=="リスク") | .id
     | (length > 20 and test("^n[0-9]+$"))')"

mv "$REPORT" "$REPORT.bak"
check 'report が無いと 404' '404' \
  "$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/sessions/$SESSION_ID/report")"
mv "$REPORT.bak" "$REPORT"

echo
echo "plan ノードの再照合"
rm -f "$PLAN_STATE" "$PLAN_APPROVED"
cat > "$PLAN" <<'EOF'
# matching

## 概要

### Alpha

alpha stable body

### Beta

beta stable body

### Deleted

deleted stable body

### Depth

depth stable body
EOF
MATCHING="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan")"
ALPHA_ID="$(printf '%s' "$MATCHING" | jq -r '.nodes[] | select(.title=="Alpha") | .id')"
BETA_ID="$(printf '%s' "$MATCHING" | jq -r '.nodes[] | select(.title=="Beta") | .id')"
DELETED_ID="$(printf '%s' "$MATCHING" | jq -r '.nodes[] | select(.title=="Deleted") | .id')"
DEPTH_ID="$(printf '%s' "$MATCHING" | jq -r '.nodes[] | select(.title=="Depth") | .id')"

plan_post "$(jq -cn --arg node "$ALPHA_ID" \
  '{revision:0,op:"add",comment:{anchor:{kind:"plan",nodeId:$node},
    label:"note",turns:[{by:"you",body:"alpha comment"}],state:"open"}}')" >/dev/null
plan_post "$(jq -cn --arg node "$DELETED_ID" \
  '{revision:1,op:"add",comment:{anchor:{kind:"plan",nodeId:$node},
    label:"note",turns:[{by:"you",body:"deleted comment"}],state:"open"}}')" >/dev/null
plan_post "$(jq -cn --arg node "$ALPHA_ID" \
  '{revision:2,op:"confirm",nodeId:$node}')" >/dev/null
plan_post "$(jq -cn --arg node "$BETA_ID" \
  '{revision:3,op:"confirm",nodeId:$node}')" >/dev/null
plan_post "$(jq -cn --arg node "$DELETED_ID" \
  '{revision:4,op:"confirm",nodeId:$node}')" >/dev/null
plan_post "$(jq -cn --arg node "$DEPTH_ID" \
  '{revision:5,op:"confirm",nodeId:$node}')" >/dev/null

cat > "$PLAN" <<'EOF'
# matching

## 概要

### Alpha renamed

alpha stable body

### Beta

beta stable body

### Deleted

deleted stable body

### Depth

depth stable body
EOF
MATCHING="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan")"
check '見出しの書き換えで ID を保つ' "$ALPHA_ID" \
  "$(printf '%s' "$MATCHING" | jq -r \
    '.nodes[] | select(.title=="Alpha renamed") | .id')"

cat > "$PLAN" <<'EOF'
# matching

## 概要

### Inserted

inserted body

### Alpha renamed

alpha stable body

### Beta

beta stable body

### Deleted

deleted stable body

### Depth

depth stable body
EOF
MATCHING="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan")"
check 'ノード挿入後も既存 ID を保つ' "$ALPHA_ID $BETA_ID" \
  "$(printf '%s' "$MATCHING" | jq -r \
    '[.nodes[] | select(.title=="Alpha renamed" or .title=="Beta") | .id] | join(" ")')"

cat > "$PLAN" <<'EOF'
# matching

## 概要

### Beta

beta stable body

### Inserted

inserted body

### Alpha renamed

alpha stable body

### Deleted

deleted stable body

### Depth

depth stable body
EOF
MATCHING="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan")"
check '節の並べ替え後も内容ハッシュで ID を保つ' "$BETA_ID $ALPHA_ID" \
  "$(printf '%s' "$MATCHING" | jq -r \
    '[.nodes[] | select(.title=="Beta" or .title=="Alpha renamed") | .id] | join(" ")')"

cat > "$PLAN" <<'EOF'
# matching

## 概要

### Beta

beta stable body

### Inserted

inserted body

### Alpha renamed

alpha stable body

### Depth

depth stable body
EOF
MATCHING="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan")"
MATCHING_STATE="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan/state")"
check '削除した節は現在の木から外れる' '0' \
  "$(printf '%s' "$MATCHING" | jq -r --arg id "$DELETED_ID" \
    '[.nodes[] | select(.id==$id)] | length')"
check 'コメント付きの削除ノードは迷子として保持する' '1 1' \
  "$(printf '%s' "$MATCHING_STATE" | jq -r --arg id "$DELETED_ID" \
    '"\([.nodes[] | select(.id==$id)]|length) \([.comments[] | select(.anchor.nodeId==$id)]|length)"')"

cat > "$PLAN" <<'EOF'
# matching

## 概要

### Beta

beta stable body

### Inserted

inserted body

### Alpha renamed

alpha stable body

## Depth

depth stable body
EOF
MATCHING="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan")"
check '見出しの深さ変更でも内容ハッシュで ID を保つ' "$DEPTH_ID" \
  "$(printf '%s' "$MATCHING" | jq -r \
    '.nodes[] | select(.title=="Depth") | .id')"
check '再照合は confirmations と comments を書き換えない' '4 2' \
  "$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan/state" \
    | jq -r '"\(.confirmations|length) \(.comments|length)"')"

STATE_RESPONSE="$(plan_post "$(jq -cn --arg node "$ALPHA_ID" \
  '{revision:6,op:"confirm",nodeId:$node}')")"
cat > "$PLAN" <<'EOF'
# matching

## 概要

### Beta

beta stable body

### Inserted

inserted body

### Alpha renamed

alpha rewritten body

## Depth

depth stable body
EOF
MATCHING="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan")"
check '本文変更でも位置照合で ID とコメントを保つ' "$ALPHA_ID 1" \
  "$(printf '%s' "$MATCHING" | jq -r --arg id "$ALPHA_ID" \
    '"\(.nodes[] | select(.title=="Alpha renamed") | .id) \([.comments[] | select(.anchor.nodeId==$id)]|length)"')"
check '本文変更は対象の confirmation だけを無効にする' '0 1' \
  "$(printf '%s' "$MATCHING" | jq -r --arg alpha "$ALPHA_ID" --arg beta "$BETA_ID" \
    '[.confirmations[]] as $confirmations
     | [.nodes[] | select(.id==$alpha)][0] as $alphaNode
     | [.nodes[] | select(.id==$beta)][0] as $betaNode
     | "\([$confirmations[] | select(.nodeId==$alpha and .hash==$alphaNode.hash)]|length) \([$confirmations[] | select(.nodeId==$beta and .hash==$betaNode.hash)]|length)"')"

rm -f "$PLAN_STATE" "$PLAN_APPROVED"
cat > "$PLAN" <<'EOF'
# ambiguity

## 概要

### Stable

stable body

## 方針

### Target

same quote
EOF
AMBIGUITY="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan")"
TARGET_ID="$(printf '%s' "$AMBIGUITY" | jq -r '.nodes[] | select(.title=="Target") | .id')"
plan_post "$(jq -cn --arg node "$TARGET_ID" \
  '{revision:0,op:"add",comment:{anchor:{kind:"plan",nodeId:$node},
    label:"note",turns:[{by:"you",body:"keep orphan"}],state:"open"}}')" >/dev/null
cat > "$PLAN" <<'EOF'
# ambiguity

## 方針

### Candidate one

same quote

### Candidate two

same quote

## 概要

### Stable

stable body
EOF
AMBIGUITY="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan")"
AMBIGUITY_STATE="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan/state")"
check '同じ quote が複数なら古い ID を採用しない' '0 2' \
  "$(printf '%s' "$AMBIGUITY" | jq -r --arg id "$TARGET_ID" \
    '"\([.nodes[] | select(.id==$id)]|length) \([.nodes[] | select(.quote=="same quote")]|length)"')"
check '曖昧な quote のコメントは迷子として保持する' '1 1' \
  "$(printf '%s' "$AMBIGUITY_STATE" | jq -r --arg id "$TARGET_ID" \
    '"\([.nodes[] | select(.id==$id)]|length) \([.comments[] | select(.anchor.nodeId==$id)]|length)"')"

echo
echo "plan の承認"
rm -f "$PLAN_STATE" "$PLAN_APPROVED"
cat > "$PLAN" <<'EOF'
# detail only

## 現状の作り

detail body
EOF
DETAIL_PLAN="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan")"
DETAIL_HASH="$(printf '%s' "$DETAIL_PLAN" | jq -r .hash)"
check 'focus の葉が0件でも文書確認なしでは承認できない' '409' \
  "$(plan_status approve "$(jq -cn --arg hash "$DETAIL_HASH" '{hash:$hash}')")"
plan_post '{"revision":0,"op":"confirm","nodeId":"@doc"}' >/dev/null
DETAIL_APPROVAL="$(curl -sS -X POST -H 'content-type: application/json' \
  -d "$(jq -cn --arg hash "$DETAIL_HASH" '{hash:$hash}')" \
  "$BASE/api/sessions/$SESSION_ID/plan/approve")"
check '文書全体の明示確認で空集合を防いだまま承認できる' 'true' \
  "$(printf '%s' "$DETAIL_APPROVAL" | jq -r '.approval.nonce | length > 0')"
curl -sS -X POST -H 'content-type: application/json' -d '{}' \
  "$BASE/api/sessions/$SESSION_ID/plan/approve/reset" >/dev/null

rm -f "$PLAN_STATE" "$PLAN_APPROVED"
cat > "$PLAN" <<'EOF'
# approval

## 概要

focus body

## 判断

decision body

## 現状の作り

detail body
EOF
APPROVAL_PLAN="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan")"
APPROVAL_HASH="$(printf '%s' "$APPROVAL_PLAN" | jq -r .hash)"
FOCUS_ID="$(printf '%s' "$APPROVAL_PLAN" | jq -r \
  '.nodes[] | select(.title=="概要") | .id')"
DECISION_ID="$(printf '%s' "$APPROVAL_PLAN" | jq -r \
  '.nodes[] | select(.title=="判断") | .id')"
DETAIL_ID="$(printf '%s' "$APPROVAL_PLAN" | jq -r \
  '.nodes[] | select(.title=="現状の作り") | .id')"
check '古い plan hash の approve は 409' '409' \
  "$(plan_status approve '{"hash":"old-hash"}')"

plan_post '{"revision":0,"op":"confirm","nodeId":"@doc"}' >/dev/null
check 'focus と decision の確認不足をサーバでも拒否する' '409' \
  "$(plan_status approve "$(jq -cn --arg hash "$APPROVAL_HASH" '{hash:$hash}')")"
plan_post "$(jq -cn --arg node "$FOCUS_ID" \
  '{revision:1,op:"confirm",nodeId:$node}')" >/dev/null
plan_post "$(jq -cn --arg node "$DECISION_ID" \
  '{revision:2,op:"confirm",nodeId:$node}')" >/dev/null
plan_post "$(jq -cn --arg node "$DECISION_ID" \
  '{revision:3,op:"add",comment:{anchor:{kind:"plan",nodeId:$node},
    label:"question",turns:[{by:"you",body:"質問"}],state:"open"}}')" >/dev/null
plan_post "$(jq -cn --arg node "$DECISION_ID" \
  '{revision:4,op:"confirm",nodeId:$node}')" >/dev/null
check '未解決のブロッキングコメントをサーバでも拒否する' '409' \
  "$(plan_status approve "$(jq -cn --arg hash "$APPROVAL_HASH" '{hash:$hash}')")"
plan_post '{"revision":5,"op":"resolve","id":"c1"}' >/dev/null

APPROVAL_ONE="$(curl -sS -X POST -H 'content-type: application/json' \
  -d "$(jq -cn --arg hash "$APPROVAL_HASH" '{hash:$hash}')" \
  "$BASE/api/sessions/$SESSION_ID/plan/approve")"
NONCE_ONE="$(printf '%s' "$APPROVAL_ONE" | jq -r .approval.nonce)"
check '正しい hash と有効条件でセンチネルを作る' 'yes true 6' \
  "$([ -f "$PLAN_APPROVED" ] && printf 'yes ' || printf 'no '; \
     jq -r '"\(.nonce != "") \(.stateRevision)"' "$PLAN_APPROVED")"
check '承認済みで未消費の再 approve は 409' '409' \
  "$(plan_status approve "$(jq -cn --arg hash "$APPROVAL_HASH" '{hash:$hash}')")"

STATE_RESPONSE="$(plan_post "$(jq -cn --arg node "$DETAIL_ID" \
  '{revision:6,op:"add",comment:{anchor:{kind:"plan",nodeId:$node},
    label:"note",turns:[{by:"you",body:"nonblocking"}],state:"open"}}')")"
check '承認後の状態変更が approval とセンチネルを消す' 'true no' \
  "$(printf '%s' "$STATE_RESPONSE" | jq -r '.approval == null') \
$([ -f "$PLAN_APPROVED" ] && echo yes || echo no)"

APPROVAL_TWO="$(curl -sS -X POST -H 'content-type: application/json' \
  -d "$(jq -cn --arg hash "$APPROVAL_HASH" '{hash:$hash}')" \
  "$BASE/api/sessions/$SESSION_ID/plan/approve")"
NONCE_TWO="$(printf '%s' "$APPROVAL_TWO" | jq -r .approval.nonce)"
check '承認を状態 revision と nonce に紐づける' '7 true' \
  "$(printf '%s' "$APPROVAL_TWO" | jq -r --arg old "$NONCE_ONE" \
    '"\(.approval.stateRevision) \(.approval.nonce != $old)"')"
check '古い nonce の consume は 409' '409' \
  "$(plan_status approve/consume \
    "$(jq -cn --arg nonce "$NONCE_ONE" '{nonce:$nonce}')")"
CONSUMED="$(curl -sS -X POST -H 'content-type: application/json' \
  -d "$(jq -cn --arg nonce "$NONCE_TWO" '{nonce:$nonce}')" \
  "$BASE/api/sessions/$SESSION_ID/plan/approve/consume")"
check '一致する nonce を消費済みにしてセンチネルを消す' 'true no' \
  "$(printf '%s' "$CONSUMED" | jq -r '.approval.consumedAt | length > 0') \
$([ -f "$PLAN_APPROVED" ] && echo yes || echo no)"

APPROVAL_THREE="$(curl -sS -X POST -H 'content-type: application/json' \
  -d "$(jq -cn --arg hash "$APPROVAL_HASH" '{hash:$hash}')" \
  "$BASE/api/sessions/$SESSION_ID/plan/approve")"
check '消費済みの後は新しい nonce で再承認できる' 'true' \
  "$(printf '%s' "$APPROVAL_THREE" | jq -r --arg old "$NONCE_TWO" \
    '.approval.nonce != $old')"
RESET="$(curl -sS -X POST -H 'content-type: application/json' -d '{}' \
  "$BASE/api/sessions/$SESSION_ID/plan/approve/reset")"
check 'reset が approval とセンチネルを両方消す' 'true no' \
  "$(printf '%s' "$RESET" | jq -r '.approval == null') \
$([ -f "$PLAN_APPROVED" ] && echo yes || echo no)"

jq '.approval = {"nonce":7}' "$PLAN_STATE" > "$WORK/broken-approval.json"
mv "$WORK/broken-approval.json" "$PLAN_STATE"
printf 'stale\n' > "$PLAN_APPROVED"
BROKEN_APPROVAL="$(curl -sS "$BASE/api/sessions/$SESSION_ID/plan/state")"
check '壊れた approval は正常要素を保ったまま除外する' 'true 1' \
  "$(printf '%s' "$BROKEN_APPROVAL" | jq -r \
    '"\(.approval == null) \([.warnings[] | select(contains("壊れた承認"))]|length)"')"
check '壊れた approval のセンチネルを残さない' 'no' \
  "$([ -f "$PLAN_APPROVED" ] && echo yes || echo no)"

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

printf '# outside plan\n' > "$WORK/outside-plan.md"
mv "$PLAN" "$PLAN.real"
ln -s "$WORK/outside-plan.md" "$PLAN"
check 'workDir 外の plan.md symlink は 403' '403' \
  "$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/sessions/$SESSION_ID/plan")"
rm "$PLAN"
mv "$PLAN.real" "$PLAN"

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
mv "$PLAN_ONLY/plan.md" "$PLAN_ONLY/plan.md.bak"
check 'plan が無いセッションは 404' '404' \
  "$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/sessions/$PLAN_ONLY_ID/plan")"
mv "$PLAN_ONLY/plan.md.bak" "$PLAN_ONLY/plan.md"

echo
echo "----------------------------------------"
printf 'ok %d / fail %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
