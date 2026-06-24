-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- PDF を nvim で開いたら外部 Skim に渡し、バッファにはバイナリを表示しない。
-- （ファイラ/picker からうっかり .pdf を開いても生バイナリが出ない。LaTeX の
--   プレビューは vimtex の view 経由で Skim が開くので、こちらは「直接開いた」場合の保険）
vim.api.nvim_create_autocmd("BufReadCmd", {
  group = vim.api.nvim_create_augroup("pdf_open_external", { clear = true }),
  pattern = "*.pdf",
  callback = function(ev)
    vim.fn.jobstart({ "open", "-a", "Skim", ev.file }, { detach = true })
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(ev.buf) then
        pcall(vim.api.nvim_buf_delete, ev.buf, { force = true })
      end
    end)
  end,
})
