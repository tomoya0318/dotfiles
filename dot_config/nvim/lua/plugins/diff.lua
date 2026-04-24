return {
  -- 差分レビュー (git diff を nvim 内で確認)
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
