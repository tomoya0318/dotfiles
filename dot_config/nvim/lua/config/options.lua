vim.opt.clipboard = "unnamedplus"
vim.g.python3_host_prog = vim.fn.expand("~/.local/share/nvim/venv_tools/bin/python")
vim.o.exrc = true
vim.opt.spelllang = { "en", "cjk" }
-- LSP Server to use for Python.
-- Set to "basedpyright" to use basedpyright instead of pyright.
vim.g.lazyvim_python_lsp = "pyright"
-- Set to "ruff_lsp" to use the old LSP implementation version.
vim.g.lazyvim_python_ruff = "ruff"

-- Tabをスペースに置換する
vim.opt.expandtab = true
-- 基本のインデント幅を2にする
vim.opt.tabstop = 2 -- 画面上でタブ文字が占める幅
vim.opt.shiftwidth = 2 -- 自動インデントや">"コマンドで動く幅
vim.opt.softtabstop = 2 -- Tabキーを押した時に挿入されるスペースの量
-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
