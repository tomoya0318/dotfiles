-- <leader>? を「日本語チートシート」のプレフィックスに上書き
-- （LazyVim 既定の <leader>? = Buffer Keymaps を無効化）
-- 分類ごとに別ファイルを表示: v=vim / f=ファイル / l=LazyVim / a=全部

-- 指定したファイル群を読み込んでフロート表示する関数を返す
local function open_cheat(names)
  return function()
    local dir = vim.fn.stdpath("config") .. "/cheatsheet-ja/"
    local lines = {}
    for _, name in ipairs(names) do
      local path = dir .. name .. ".txt"
      if vim.fn.filereadable(path) == 1 then
        vim.list_extend(lines, vim.fn.readfile(path))
        table.insert(lines, "")
      end
    end
    if #lines == 0 then
      vim.notify("cheatsheet not found in " .. dir, vim.log.levels.WARN)
      return
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"
    local width = math.min(82, vim.o.columns - 4)
    local height = math.min(#lines, vim.o.lines - 4)
    vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      style = "minimal",
      border = "rounded",
      title = " チートシート (q で閉じる) ",
      title_pos = "center",
    })
    for _, key in ipairs({ "q", "<esc>" }) do
      vim.keymap.set("n", key, "<cmd>close<cr>", { buffer = buf, nowait = true, silent = true })
    end
  end
end

return {
  "folke/which-key.nvim",
  -- <leader>? にグループ名を付ける（既存 spec を壊さず追記）
  opts = function(_, opts)
    opts.spec = opts.spec or {}
    table.insert(opts.spec, { "<leader>?", group = "チートシート" })
  end,
  keys = {
    { "<leader>?", false }, -- LazyVim 既定の <leader>? を無効化してプレフィックス化
    { "<leader>?a", open_cheat({ "vim", "files", "lazyvim", "lazygit" }), desc = "全部" },
    { "<leader>?v", open_cheat({ "vim" }), desc = "vim 標準" },
    { "<leader>?f", open_cheat({ "files" }), desc = "ファイル/タブ/分割" },
    { "<leader>?l", open_cheat({ "lazyvim" }), desc = "LazyVim (Space)" },
    { "<leader>?g", open_cheat({ "lazygit" }), desc = "lazygit" },
  },
}
