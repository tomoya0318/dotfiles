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

-- ── カレントディレクトリ(cwd)が外部操作で消えたときの自動復旧 ─────────────────
-- nvim が cwd を置いているディレクトリを、別プロセスが「消して作り直す / 別ブランチへ
-- 切替えて消す / finish-worktree で worktree を remove する」等で消すと、同名で作り
-- 直しても inode が変わり、元の cwd ハンドルが無効化される。すると vim.uv.cwd() が
-- nil を返し、次のように軒並み壊れる:
--   - oil の描画が mini.icons → vim.filetype.match → vim.fs.abspath(assert(uv.cwd()))
--     で "vim/fs:837: assertion failed!" を吐く
--   - snacks の files/grep は fd/rg を cwd 基準で走らせるため
--     "Could not retrieve current directory" で空振りする
-- これは worktree 運用に限らず git switch / git clean -fd / rm して作り直し等でも起きる。
-- 対策: 生きている cwd とその git メインワークツリーを控えておき、cwd が死んだら
-- 「main(控え) → 最寄り生存祖先 → HOME」の順で退避し、消えた cwd 配下を指す
-- 孤児バッファ（実ファイル無し・未保存以外）を片付ける。
local last_cwd -- 最後に生きていた cwd（死んだパスの起点・祖先辿りに使う）
local main_worktree -- last_cwd の git メインワークツリー（git worktree list の先頭）

-- 生きているうちに cwd とメインワークツリーを控える（git 呼び出しは非同期で UI を止めない）
local function remember_cwd()
  local cwd = vim.uv.cwd()
  if not cwd then
    return
  end
  last_cwd = cwd
  -- git でなければ nil に戻す（前の repo の値を残さない）
  vim.system({ "git", "-C", cwd, "worktree", "list", "--porcelain" }, { text = true }, function(out)
    main_worktree = out.code == 0 and out.stdout:match("^worktree (.-)\n") or nil
  end)
end

local function isdir(p)
  return p ~= nil and p ~= "" and vim.fn.isdirectory(p) == 1
end

-- 消えた cwd(dead) 配下を指す通常ファイルバッファを片付ける。
-- 未保存(modified)は触らず、名前だけ集めて返す（呼び出し側で通知する）。
local function wipe_orphan_buffers(dead)
  local prefix = dead:gsub("/*$", "") .. "/" -- 末尾 / で wt が wt2 等に誤マッチしないようにする
  local kept = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then -- 通常ファイルのみ(oil/term/help を除外)
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and vim.startswith(name, prefix) and not vim.uv.fs_stat(name) then
        if vim.bo[buf].modified then
          kept[#kept + 1] = vim.fn.fnamemodify(name, ":t")
        else
          pcall(vim.api.nvim_buf_delete, buf, { force = true }) -- 表示中でも代替バッファに差し替わる
        end
      end
    end
  end
  return kept
end

local function recover_dead_cwd()
  if vim.uv.cwd() ~= nil then
    return -- 生きていれば何もしない（コストは uv.cwd() 1回だけ）
  end
  local dead = last_cwd

  -- 退避先: main(控え) → 死んだ cwd の最寄り生存祖先 → HOME
  local target
  if isdir(main_worktree) then
    target = main_worktree
  else
    local dir = dead and vim.fs.dirname(dead) or nil
    while dir and dir ~= "" do
      if isdir(dir) then
        target = dir
        break
      end
      local parent = vim.fs.dirname(dir)
      if parent == dir then
        break
      end
      dir = parent
    end
  end
  target = target or vim.fn.expand("~")

  pcall(vim.cmd.cd, vim.fn.fnameescape(target)) -- ここで crash 源(無効 cwd)が解消する

  vim.schedule(function()
    local kept = dead and wipe_orphan_buffers(dead) or {}
    vim.notify("cwd が消えていたため " .. target .. " へ移動しました", vim.log.levels.WARN, { title = "cwd recover" })
    if #kept > 0 then
      vim.notify(
        "保存先が消えています（未保存のため保持）: " .. table.concat(kept, ", "),
        vim.log.levels.WARN,
        { title = "cwd recover" }
      )
    end
  end)
end

local recover_group = vim.api.nvim_create_augroup("recover_dead_cwd", { clear = true })
-- 控え: 実際に cwd が変わったとき(<leader>gw の :cd 等)＋起動時
vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
  group = recover_group,
  callback = remember_cwd,
})
-- 復旧: 別アプリから戻った瞬間(FocusGained)・nvim 内操作(BufEnter)・小休止(CursorHold)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  group = recover_group,
  callback = recover_dead_cwd,
})
