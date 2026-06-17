return {
  "stevearc/oil.nvim",
  opts = {
    -- 外部（Claude Code など別プロセス）でのファイル追加・削除を監視し、
    -- oil バッファを自動で更新する（手動 <C-l> リフレッシュ不要にする）
    watch_for_changes = true,
    view_options = {
      -- 隠しファイル（ドットファイル）もデフォルトで表示する。
      -- 全表示 ⇔ 非表示 は標準キーマップ "g." でトグルできる。
      show_hidden = true,
      -- VSCode の files.exclude / Zed の file_scan_exclusions 相当:
      -- ここに挙げたものは常に非表示（g. でも出さない）
      is_always_hidden = function(name, _)
        local always_hidden = {
          -- 汎用
          [".git"] = true,
          [".DS_Store"] = true,
          -- JS / TS / フロントエンド
          ["node_modules"] = true,
          [".next"] = true, -- Next.js のビルドキャッシュ
          [".nuxt"] = true, -- Nuxt のビルドキャッシュ
          [".turbo"] = true, -- Turborepo のキャッシュ
          -- Python
          [".venv"] = true, -- 仮想環境
          ["venv"] = true,
          ["__pycache__"] = true, -- バイトコードキャッシュ
          [".mypy_cache"] = true,
          [".pytest_cache"] = true,
          [".ruff_cache"] = true,
        }
        if always_hidden[name] then
          return true
        end
        -- 末尾一致で隠すもの（*.pyc, *.egg-info など名前が可変なもの）
        if name:match("%.pyc$") or name:match("%.egg%-info$") then
          return true
        end
        return false
      end,
    },
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
      -- "gY" を押すと、cwd からの相対パスをクリップボードにコピーする
      ["gY"] = {
        callback = function()
          local oil = require("oil")
          local entry = oil.get_cursor_entry()
          local dir = oil.get_current_dir()

          if not entry or not dir then
            return
          end

          local full_path = dir .. entry.name
          -- cwd からの相対パスに変換（cwd 外なら絶対パスのまま）
          local rel_path = vim.fn.fnamemodify(full_path, ":.")

          vim.fn.setreg("+", rel_path)
          vim.notify("Copied: " .. rel_path)
        end,
        desc = "Copy cursor entry relative path",
        mode = "n",
      },
    },
  },
  dependencies = { "nvim-tree/nvim-web-devicons" },
  keys = {
    { "<leader>f-", "<cmd>Oil<cr>", desc = "Open parent directory with Oil" },
  },
}
