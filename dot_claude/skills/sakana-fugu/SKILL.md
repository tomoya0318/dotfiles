---
name: sakana-fugu
description: Send a prompt to Sakana Fugu (fugu / fugu-ultra) via its OpenAI-compatible Responses API and return the answer. Use when the user wants to delegate a question, research, summary, brainstorm, or implementation task to Sakana Fugu, or explicitly mentions Fugu / Sakana / fugu-ultra. The user may name a model explicitly; if omitted, auto-select by task weight (fugu for light/fast, fugu-ultra for hard/multi-step).
---

# Sakana Fugu

Sakana Fugu（`fugu` / `fugu-ultra`）に OpenAI 互換 Responses API でプロンプトを送り、回答を受け取るためのスキル。汎用の問い合わせ（調査・要約・設計相談・実装委譲など）に使う。

## 前提
- API キー: `~/dev/.env` に `SAKANA_API_KEY=sk-...`（chezmoi 管理外の秘密ファイル）
- `uv` がインストール済み。依存（openai / python-dotenv）は PEP723 で隔離環境に自動解決される（初回のみ取得・キャッシュ）。
- スクリプト: `~/.claude/skills/sakana-fugu/fugu.py`

## モデル選択（重要）
ユーザがモデルを明示したら**必ずそれに従う**。明示が無ければ、こちらでタスクの重さを判定して自動選択する:

- `fugu`（既定・高速・低コスト）: 単純な Q&A、短い要約、軽い調査、定型的なコード、事実確認、1ファイル規模の作業
- `fugu-ultra`（高品質・低速・高コスト）: 多段推論、難問、深い調査や設計、大規模リファクタ、数学・証明、ユーザが「重要 / 難しい / しっかり」と示したもの

迷ったら `fugu` から始める。品質や難度が強調されている / 失敗コストが高いと判断したら `fugu-ultra`。

## 実行方法
プロンプトは **stdin 経由が基本**（長文・多行・シェルエスケープに強い）。一時ファイルに書いてからパイプする:

```bash
# 1. プロンプトを scratchpad 等の一時ファイルに書く
# 2. パイプで渡す
uv run ~/.claude/skills/sakana-fugu/fugu.py --model fugu < /path/to/prompt.txt
```

短い1行プロンプトなら位置引数でも可:

```bash
uv run ~/.claude/skills/sakana-fugu/fugu.py --model fugu-ultra "プロンプト本文"
```

### オプション
- `-m, --model {fugu,fugu-ultra,fugu-ultra-20260615}`: モデル（既定 `fugu`）
- `--web-search`: built-in web search を有効化（最新情報・URL 調査が必要なとき）
- `--effort {high,xhigh}`: 推論強度（`fugu` 向けの公式パラメータ）
- `--timeout SEC`: タイムアウト秒（既定 300）。`fugu-ultra` の重いタスクは長くなるので必要なら増やす
- `--prompt-file PATH`: ファイルからプロンプトを読む（stdin の代わり）

### 出力の扱い
- **stdout** = 回答本文のみ。そのままユーザに提示、または後続処理にパイプ/キャプチャできる
- **stderr** = 診断ログ（使用モデル・所要時間など）。回答とは混ざらない

回答を整形してユーザに返すときは stdout のみを使う。

## 注意
- `fugu-ultra` は数分かかることがある。タイムアウトしたら `--timeout` を増やして再実行する。
- API キーが無い場合は終了コード 2 でエラーになる。`~/dev/.env` の `SAKANA_API_KEY` を確認する。
- `fugu` 自体が内部で複数 LLM をオーケストレーションするモデルなので、プロンプトは「やってほしいこと」を素直に1本のテキストで渡せばよい。
