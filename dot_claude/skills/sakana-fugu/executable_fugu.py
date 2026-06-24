#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "openai>=1.66",
#     "python-dotenv>=1.0",
# ]
# ///
"""
Sakana Fugu client (OpenAI-compatible Responses API).

uv の PEP723 インラインメタデータで依存を隔離環境に自動解決して実行する。
グローバル python を汚さない。

API キーは ~/dev/.env の SAKANA_API_KEY から読む（環境変数があればそちらを優先）。

使い方:
    # プロンプトは stdin / 位置引数 / --prompt-file のいずれか
    echo "TLS の仕組みを簡潔に説明して" | uv run ~/.claude/skills/sakana-fugu/fugu.py
    uv run ~/.claude/skills/sakana-fugu/fugu.py --model fugu-ultra "難しい設計問題..."
    uv run ~/.claude/skills/sakana-fugu/fugu.py --prompt-file /path/to/prompt.txt --web-search

出力:
    stdout: response.output_text のみ（クリーン。パイプ/キャプチャ向け）
    stderr: 診断（使用モデル・所要時間・進捗）
"""

import argparse
import os
import sys
import time

BASE_URL = "https://api.sakana.ai/v1"
ENV_PATH = os.path.expanduser("~/dev/.env")
VALID_MODELS = ("fugu", "fugu-ultra", "fugu-ultra-20260615")


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def load_api_key() -> str:
    # 環境変数が既にあればそれを使う。なければ ~/dev/.env を読む。
    key = os.getenv("SAKANA_API_KEY")
    if not key:
        try:
            from dotenv import load_dotenv

            load_dotenv(ENV_PATH)
        except Exception:
            pass
        key = os.getenv("SAKANA_API_KEY")
    if not key:
        eprint(
            f"[fugu] SAKANA_API_KEY が見つかりません。\n"
            f"        {ENV_PATH} に `SAKANA_API_KEY=sk-...` を設定するか、\n"
            f"        環境変数 SAKANA_API_KEY を export してください。"
        )
        sys.exit(2)
    return key


def read_prompt(args) -> str:
    # 優先順位: --prompt-file > 位置引数 > stdin
    if args.prompt_file:
        with open(os.path.expanduser(args.prompt_file), "r", encoding="utf-8") as f:
            return f.read().strip()
    if args.prompt:
        return args.prompt.strip()
    if not sys.stdin.isatty():
        data = sys.stdin.read().strip()
        if data:
            return data
    eprint("[fugu] プロンプトが空です。位置引数 / --prompt-file / stdin のいずれかで渡してください。")
    sys.exit(2)


def ask(prompt: str, model: str, web_search: bool, effort: str | None, timeout: float) -> str:
    from openai import OpenAI

    client = OpenAI(api_key=load_api_key(), base_url=BASE_URL)

    kwargs: dict = {"model": model, "input": prompt, "timeout": timeout}
    if web_search:
        kwargs["tools"] = [{"type": "web_search"}]
    if effort:
        kwargs["effort"] = effort

    response = client.responses.create(**kwargs)
    return response.output_text


def main() -> int:
    parser = argparse.ArgumentParser(description="Sakana Fugu CLI (Responses API)")
    parser.add_argument("prompt", nargs="?", default=None, help="プロンプト（省略時は stdin）")
    parser.add_argument(
        "-m", "--model", default="fugu", choices=VALID_MODELS,
        help="モデル（既定: fugu）。重いタスクは fugu-ultra。",
    )
    parser.add_argument("--prompt-file", default=None, help="プロンプトをファイルから読む")
    parser.add_argument("--web-search", action="store_true", help="built-in web search を有効化")
    parser.add_argument(
        "--effort", default=None, choices=["high", "xhigh"],
        help="推論強度（fugu 向け。公式記載の high/xhigh）",
    )
    parser.add_argument(
        "--timeout", type=float, default=300.0,
        help="タイムアウト秒（既定: 300。fugu-ultra は長くかかる場合あり）",
    )
    args = parser.parse_args()

    prompt = read_prompt(args)

    eprint(f"[fugu] model={args.model} web_search={args.web_search} "
           f"effort={args.effort or '-'} timeout={args.timeout:.0f}s")
    eprint(f"[fugu] sending {len(prompt)} chars, waiting for response...")

    start = time.monotonic()
    try:
        text = ask(prompt, args.model, args.web_search, args.effort, args.timeout)
    except Exception as e:
        eprint(f"[fugu] ERROR: {type(e).__name__}: {e}")
        return 1
    elapsed = time.monotonic() - start

    eprint(f"[fugu] done in {elapsed:.1f}s ({len(text)} chars)")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
