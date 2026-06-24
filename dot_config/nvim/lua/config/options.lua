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
-- nowrap 時の横スクロールを滑らかにする。
-- 既定の sidescroll=0 はカーソルが画面端に来るたびに画面が半分ジャンプし
-- 「ガクガク」する。markdown の広い表(描画中は nowrap)やコードの長い行で効く。
vim.opt.sidescroll = 1 -- 1 列ずつ滑らかにスクロール
vim.opt.sidescrolloff = 4 -- カーソルの左右に最低 4 列の文脈を残す
vim.opt.listchars:append({ extends = "›", precedes = "‹" }) -- 画面外に続きがある印

-- マウスホイール(トラックパッド)スクロールを無効化する。
-- 目的: markview の高速スクロール時の描画崩れを避け、移動を j/k・<C-d>/<C-u> 等の
--       離散移動に統一する。mouse=a は維持なのでクリック/選択は使える。
-- 方式: ScrollWheel を各モードで <Nop> する代わりに、公式の mousescroll で
--       「スクロール量 0」にする（:help mousescroll「a count of 0」で無効化と明記）。
--       全モード一括・1行で済み、修飾キー付きホイールも漏れなく無効化できる。
vim.opt.mousescroll = "ver:0,hor:0"

-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
