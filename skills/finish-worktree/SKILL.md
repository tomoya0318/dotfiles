---
name: finish-worktree
description: Saves implementation tmp artifacts to the main repository and removes a completed herdr worktree.
disable-model-invocation: true
argument-hint: /finish-worktree [work-slug]
---

# worktree を終了する

先に `/commit` と push を済ませる。
未コミットまたは未プッシュの変更があれば中止する。
worktree 内で main 側のルートを `git worktree list --porcelain` から特定し、`save-worktree-tmp.sh` で tmp を持ち帰る。
その後、main 側へ移動して `herdr worktree remove --workspace <id>` を実行する。
マージまたは PR の状態を確認し、保存先と削除結果を報告する。
