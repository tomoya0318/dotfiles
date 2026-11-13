<!-- SEMBLE_START -->
## Semble Code Search

A `semble` MCP server is available with two tools:
- `mcp__semble__search` — search the codebase with a natural-language or code query.
- `mcp__semble__find_related` — find code similar to a specific file and line.

Use `mcp__semble__search` to find where something is implemented — instead of using Grep or Glob to discover files. After semble returns the file and line, navigate there directly and read that file. Do not grep for the same content again.

Pass `--content docs` to search documentation and prose, `--content config` for config files, or `--content all` to search code, docs, and config together.

For CLI fallback or sub-agents without MCP access, use:

```bash
semble search "authentication flow" ./my-project --max-snippet-lines 10
semble search "deployment guide" ./my-project --content docs
semble search "database host port" ./my-project --content config
semble find-related src/auth.py 42 ./my-project
semble search "save model to disk" ./my-project --top-k 10
```

The index is built on first run and cached automatically. If `semble` is not on `$PATH`, use `uvx --from "semble[mcp]" semble`.

### Workflow

1. Call `mcp__semble__search` with a query describing what the code does or its name. The tool returns results with 10 lines of context each (function/class signature + first body lines, enough to confirm the location).
2. Navigate directly to the top result's file and line. Read only the function or class at that location.
3. Make the edit. Do not re-search or grep for the same content.
4. Use `--content docs` for documentation, `--content config` for config files, or `--content all` for everything.
5. Optionally use `mcp__semble__find_related` with `file_path` and `line` to discover similar code elsewhere.
6. Use Grep only when you need every occurrence of a literal string across the whole repo (e.g., all callers of a renamed function).
<!-- SEMBLE_END -->

<!-- T3_CODE_FORK_START -->
## T3 Code の fork

T3 Code で「forkして」と頼まれたら、会話スレッドの分岐を意味する。`delegate_task`、subagent、`t3_thread_launch`、`create_threads` で代用しない。

- 現在のスレッドは T3 の `t3_thread_transfer` を `action: "fork"` で呼んで分岐する。分岐点の指定がなければ `sourcePoint` を省き、既定の最新の安定した時点を使う。
- fork 先を作っただけでは作業を始めない。fork 先で作業を続ける依頼もあるときに限り、その依頼を fork 先へ送る。
- fork 機能が使えないときは subagent で代用せず、使えないことを伝える。
- fork 先をユーザーに伝えるときは、T3 が返した thread link をそのまま示す。
<!-- T3_CODE_FORK_END -->
