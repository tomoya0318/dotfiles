return {
  "stevearc/oil.nvim",
  opts = {
    keymaps = {
      -- "gy" を押すと、現在地のパスをクリップボードにコピーする
      ["gy"] = {
        callback = function()
          local oil = require("oil")
          local entry = oil.get_cursor_entry()
          local dir = oil.get_current_dir()

          if not entry or not dir then
            return
          end

          -- ファイル名とディレクトリを結合してフルパスを作成
          local full_path = dir .. entry.name

          -- クリップボードにセット
          vim.fn.setreg("+", full_path)
          vim.notify("Copied: " .. full_path)
        end,
        desc = "Copy cursor entry absolute path",
        mode = "n",
      },
    },
  },
  dependencies = { "nvim-tree/nvim-web-devicons" },
  keys = {
    { "<leader>f-", "<cmd>Oil<cr>", desc = "Open parent directory with Oil" },
  },
}
