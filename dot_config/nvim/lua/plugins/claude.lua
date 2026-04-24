return {
  -- 1. 日本語入力の自動切り替え (im-select) - Mac のみ
  -- Linux (SSH 先の研究サーバ等) では IME 切替は client 側 (Mac) の責務なので無効化
  {
    "keaising/im-select.nvim",
    enabled = function() return vim.fn.has("mac") == 1 end,
    config = function()
      require("im_select").setup({
        -- Mac では macism (nixpkgs 版) を使う
        default_command = "macism",
        set_default_events = { "VimEnter", "FocusGained", "InsertLeave", "CmdlineLeave" },
        set_previous_events = { "InsertEnter" },
        async_switch_im = true,
      })
    end,
  },

  -- 2. Claude Code 用の隔離ターミナル (Toggleterm)
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    opts = {
      open_mapping = [[<c-\>]], -- Ctrl + \ で開閉
      direction = "float", -- 画面中央に浮く
      float_opts = { border = "curved" }, -- 角丸の枠
      start_in_insert = true, -- 開いたらすぐ入力モード
    },
  },

  -- 3. 差分レビュー用 (Diffview)
  {
    "sindrets/diffview.nvim",
    opts = {
      enhanced_diff_hl = true,
    },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Git Diff Review" },
      { "<leader>gx", "<cmd>DiffviewClose<cr>", desc = "Close Diff Review" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File History" },
    },
  },
}
