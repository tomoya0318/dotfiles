-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- lazygit を Space g g で開く（snacks 経由。LazyVim 既定では extra 扱いのため明示）
-- worktree 運用対応:
--   - oil バッファは擬似パス(oil://)になるので、表示中の実ディレクトリを基点にする
--   - そこから git ルート(worktree 含む)を解決し、lazygit をそのルートで起動する
--     （MB-scanner/ のような非git親で開いても、今見ている worktree で開く）
--   - git 管理外なら lazygit の「新規リポジトリ作成?」暴発を防ぐため通知して中断する
--   - worktree 間の切替は lazygit の Worktrees パネル(Space)で行う
vim.keymap.set("n", "<leader>gg", function()
  local base
  if vim.bo.filetype == "oil" then
    local ok, oil = pcall(require, "oil")
    base = ok and oil.get_current_dir() or nil
  else
    local name = vim.api.nvim_buf_get_name(0)
    base = name ~= "" and vim.fs.dirname(name) or nil
  end

  local root = Snacks.git.get_root(base)
  if not root then
    Snacks.notify.warn("git リポジトリ外です（worktree の中で開いてください）", { title = "lazygit" })
    return
  end

  Snacks.lazygit({ cwd = root })
end, { desc = "Lazygit" })

-- Space g w : git worktree を選んで nvim の作業ディレクトリ(cwd)を切り替える
-- MB-scanner/ のように同一リポジトリの worktree 複製が並ぶ構成で、
-- nvim のスコープを単一 worktree に絞るための切替。切替後はファジーファインダーや
-- lazygit がその worktree にスコープされる（同名ファイルの重複が消える）。
vim.keymap.set("n", "<leader>gw", function()
  -- 現在のバッファ/oil から git ルートを解決し、その配下の worktree を列挙する
  local base
  if vim.bo.filetype == "oil" then
    local ok, oil = pcall(require, "oil")
    base = ok and oil.get_current_dir() or nil
  else
    local name = vim.api.nvim_buf_get_name(0)
    base = name ~= "" and vim.fs.dirname(name) or nil
  end
  base = base or (vim.uv or vim.loop).cwd()

  local out = vim.system({ "git", "-C", base, "worktree", "list", "--porcelain" }, { text = true }):wait()
  if out.code ~= 0 then
    Snacks.notify.warn("worktree を列挙できません（git リポジトリ内で実行してください）", { title = "worktree" })
    return
  end

  -- porcelain（空行区切りのレコード）をパース
  local items, cur = {}, {}
  for _, line in ipairs(vim.split(out.stdout, "\n", { plain = true })) do
    if line:match("^worktree ") then
      cur = { dir = line:sub(10) }
    elseif line:match("^branch ") then
      cur.branch = line:gsub("^branch refs/heads/", "")
    elseif line:match("^detached") then
      cur.branch = "(detached)"
    elseif line:match("^bare") then
      cur.branch = "(bare)"
    elseif line == "" and cur.dir then
      items[#items + 1], cur = cur, {}
    end
  end
  if cur.dir then items[#items + 1] = cur end

  local current = vim.fs.normalize((vim.uv or vim.loop).cwd())
  vim.ui.select(items, {
    prompt = "Switch worktree",
    format_item = function(it)
      local mark = vim.fs.normalize(it.dir) == current and "● " or "  "
      return string.format("%s%-44s %s", mark, vim.fn.fnamemodify(it.dir, ":t"), it.branch or "")
    end,
  }, function(choice)
    if not choice then
      return
    end
    vim.cmd.cd(vim.fn.fnameescape(choice.dir))
    -- cwd を変えるだけではカレントバッファが旧 worktree を指したままになり、
    -- LazyVim の root 検出(snacks picker)や oil が旧 worktree をスコープする。
    -- 無名バッファにすることで root 検出が cwd(=新 worktree)にフォールバックする。
    vim.cmd.enew()
    Snacks.notify.info("cwd → " .. choice.dir, { title = "worktree" })
  end)
end, { desc = "Switch git worktree" })
