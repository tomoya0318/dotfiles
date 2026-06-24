-- 日本語文章校正 textlint を nvim に統合（VSCode の textlint 設定の移植）。
-- 対象プロジェクトは textlint をローカル install（paper/node_modules）し、
-- 設定 .textlintrc を paper/ サブディレクトリに置いている（latex2e プラグインで
-- .tex を直接校正・preset-ja-technical-writing / preset-ja-spacing / prh）。
-- よって:
--   - linter はそのローカル bin を使う（global textlint だとルール群が無い）
--   - .textlintrc のあるディレクトリ(paper/)を cwd にして起動する。サブディレクトリの
--     設定/プラグインは既定 cwd だと解決できないため、LazyVim 既定の linters_by_ft
--     経由ではなく、root を cwd として渡す専用 autocmd で起動する。
return {
  "mfussenegger/nvim-lint",
  opts = function(_, opts)
    local lint = require("lint")
    local uv = vim.uv or vim.loop

    -- .textlintrc を持つディレクトリ（= ローカル node_modules もある場所）を上方向に探索
    local function textlint_root(buf)
      return vim.fs.root(buf or 0, {
        ".textlintrc",
        ".textlintrc.json",
        ".textlintrc.js",
        ".textlintrc.yml",
        ".textlintrc.yaml",
      })
    end

    -- カスタム textlint linter（ローカル install + stdin + JSON 出力をパース）
    lint.linters.textlint = {
      cmd = function()
        local root = textlint_root(0) or vim.fn.getcwd()
        local bin = root .. "/node_modules/.bin/textlint"
        return uv.fs_stat(bin) and bin or "textlint"
      end,
      stdin = true,
      args = {
        "--format",
        "json",
        "--stdin",
        "--stdin-filename",
        -- バッファのパス（拡張子で latex2e プラグイン選択・設定解決に使われる）
        function()
          return vim.api.nvim_buf_get_name(0)
        end,
      },
      stream = "stdout",
      ignore_exitcode = true, -- 指摘ありで exit 1 を返すため無視
      parser = function(output, _bufnr)
        local diagnostics = {}
        if not output or output == "" then
          return diagnostics
        end
        local ok, decoded = pcall(vim.json.decode, output)
        if not ok or type(decoded) ~= "table" then
          return diagnostics
        end
        local sev = vim.diagnostic.severity
        for _, file in ipairs(decoded) do
          for _, m in ipairs(file.messages or {}) do
            local s = (m.loc and m.loc.start) or { line = m.line, column = m.column }
            local e = (m.loc and m.loc["end"]) or s
            table.insert(diagnostics, {
              lnum = math.max((s.line or 1) - 1, 0),
              col = math.max((s.column or 1) - 1, 0),
              end_lnum = math.max((e.line or s.line or 1) - 1, 0),
              end_col = math.max((e.column or s.column or 1) - 1, 0),
              severity = (m.severity == 2) and sev.ERROR or sev.WARN,
              source = "textlint",
              code = m.ruleId,
              message = m.message,
            })
          end
        end
        return diagnostics
      end,
    }

    -- 専用トリガ: .textlintrc が見つかったバッファだけ、その root を cwd にして lint。
    -- 読込/保存/挿入抜けで走る（保存時のみより重くしたいなら InsertLeave を外す）。
    local group = vim.api.nvim_create_augroup("textlint_run", { clear = true })
    vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
      group = group,
      pattern = { "*.tex", "*.md", "*.markdown", "*.txt" },
      callback = function(ev)
        local root = textlint_root(ev.buf)
        if root then
          lint.try_lint("textlint", { cwd = root })
        end
      end,
    })

    -- 保存 → textlint --fix（VSCode の autoFixOnSave 相当を手動コマンド化）
    vim.api.nvim_create_user_command("TextlintFix", function()
      local file = vim.api.nvim_buf_get_name(0)
      local root = textlint_root(0)
      if file == "" or not root then
        vim.notify("textlint: .textlintrc が見つからないか無名バッファです", vim.log.levels.WARN)
        return
      end
      vim.cmd("silent write")
      vim.system({ root .. "/node_modules/.bin/textlint", "--fix", file }, { cwd = root }, function()
        vim.schedule(function()
          vim.cmd("checktime") -- 外部修正を autoread で取り込む
        end)
      end)
    end, { desc = "textlint --fix（現在ファイル）" })

    return opts
  end,
}
