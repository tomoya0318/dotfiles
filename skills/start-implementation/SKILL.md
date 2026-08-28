---
name: start-implementation
description: Starts an implementation with an investigation and a user-approved plan. Adversarial plan and implementation reviews run only when the user asks for them.
disable-model-invocation: true
argument-hint: /start-implementation <description>
---

# 実装を開始する

`tmp/NNNN_<name>/` に `plan.md` を作り、調査、承認、実装を分離して進める。
計画検証と実装検証は既定では行わない。

## 前提

リポジトリ直下の `.claude/impl-workflow.md` を読む。
存在しなければ `/setup-impl-workflow` の実行を促し、設定が確定するまで実装しない。
作業ディレクトリは設定の上書きがなければ `tmp/` とする。

## 計画の単位

1つの plan は、独立して撤回できる1つの要件を扱う。
「これとあれを別々に revert できるか」で判定し、できるなら作業を分ける。
例外は、一方が他方の前提で、分けると片方が動かせない場合だけ。

`実装手順` が上限を超えるのも同じ信号として扱う。
要件が大きすぎるか方針が回りくどいので、分けられるなら分け、分けられないなら方針を見直す。

件数や差分の量では分けない。文言をまとめれば潜れるため。

## 計画の構成

`plan.md` は `概要`、`要件`、`方針`、`実装手順`、`リスク` の5節にする。節を増やさない。

`概要` は、何を作るか、何を変えるか、スコープ、非スコープを書く。

`要件` は、満たすべき状態を1件1見出しで書き、見出しに要件そのものを書く。
本文には、なぜ要るかと、満たされたかを後から判定する方法を2〜4行で書く。
AI が単独で決めてよいことは `要件` に書かない。

`方針` は、外すと要件を満たさなくなる実装方針だけを1件1見出しで書き、見出しに結論を書く。
本文には理由を3〜5行で書き、採らなかった案があれば1行で添える。
設定や言語仕様から導かれる表現方法は書かない。実装時に分かる。
該当が無ければ空でよい。

`実装手順` は、要件ごとに見出しを立て、その下へ1要件につき3〜5行で書く。
フェーズに分けない。現状の作り、検証方法、触らないものは書かない。
承認の対象にせず、実装検証でも参照しない。実現性を承認前に検査するために書く。

`リスク` は、確かめていない事実と、起きた場合の影響と、確度を1件2〜3行で書く。

## 書き方

日本語で書く。一文ごとに改行し、段落は空行で区切る。

短く、要点だけを書く。前置きと但し書きに文字数を使わない。
検討の経緯は書かず、結論と理由だけを残す。判断軸を本文に別立てしない。
同じことを複数の節へ重複させない。

確かめていないことは、確かめていないまま書く。推量を断定に変えない。
「重要なのは」「〜において」「多角的に」のような、論点を増やさない言い回しを使わない。

## 規模の判定

対象が2ファイル以内で、調査が数回の grep で済むなら、手順2・7 の委譲を飛ばす。
main が自分で調べて `plan.md` を書いて実装する。

サブエージェントは、広い範囲にまたがる調査と、範囲が重ならない単位へ分けられる実装にだけ使う。
main が数回の操作で終わる作業を委譲しない。台数分のコストと時間がそのまま乗る。

## 検証の実行

計画検証と実装検証は、ユーザーが明示的に求めたときだけ行う。
求められていなければ飛ばし、実行するかどうかを訊かない。提案もしない。

`review.md` は作業ディレクトリを作る時点では作らない。
`init-work-dir.sh` が返す `review_file` は書き込み先のパスであって、存在は保証しない。
ファイルは検証を走らせた codex が作り、自分で表を書く。main は転記しない。

検証も codex を `workspace-write` で走らせる。`review.md` を書かせるためである。
プロンプトで編集先を `review.md` と `--result-file` に限り、run の後に main が `git status` を見て、
それ以外が変わっていないことを確かめる。プロンプトの禁止だけに委ねない。

指摘の正本は `review.md` である。`--result-file` は決着判定に使う別のファイルで、
`review.md` へ何をどれだけ書いたかを短く報告させる。
`review.md` を `--result-file` に指定しない。追記する run で先頭から消える。

モデルと effort は `spawn-codex-tab.sh` の既定と引数で決める。`~/.codex/config.toml` の既定に任せない。
任せると、設定を変えたときに検証の強度が黙って変わる。

effort は実装検証だけ差分量で変える。計画検証は `xhigh` にする。

| `git diff --shortstat` | effort |
|---|---|
| 3ファイル以内かつ200行未満 | `high` |
| 200〜600行 | `xhigh` |
| 600行超 | `xhigh`。加えて要件単位で run を分ける |

600行を超えるときに effort をこれ以上上げても、1つの run では後半が雑になる。
run を分け、各 run に担当する `要件` を明示する。`review.md` へは追記させる。

## 手順

1. 作業名は英語のハイフン区切りで渡す。ユーザーが説明的な日本語・文章の名前を指定した場合は、main が先に変換する。
   `init-work-dir.sh "<作業名>" "<base-dir>"` を実行し、JSON の作業パスを読む。
2. Plan エージェントに調査を委譲する。`Edit` と `Write` を持たないが `Bash` は持つので、状態を変える操作の禁止は明示する。
   推測で確認していない事実を埋めさせない。
   返させるのは、触る対象の責務とデータフローと不変条件、実装に不可欠なファイル3〜5個、人間の判断が要る点、確かめられなかったことの4つとする。
   `plan.md` の節や段取りは書かせない。plan を書くのは常に main である。
3. main が調査結果から `plan.md` を書く。
   `要件` が独立して撤回できる単位に分かれていなければ、ここで作業を分ける。
4. ユーザーが計画検証を求めた場合のみ、[plan-review-prompt.md](references/plan-review-prompt.md) の入力プレースホルダー（`<work-dir>`、`<result-file>`）を具体的な値で置換し、`<work>/plan-review-prompt.md` へ書き出して fresh な codex に渡す。

   ```
   scripts/spawn-codex-tab.sh --name review-plan --role review \
     --cwd <repo-root> --effort xhigh \
     --prompt-file <work>/plan-review-prompt.md \
     --result-file <work>/plan-review-result.md --no-wait
   ```

   herdr の tab が1枚立ち、そこで codex が動く。
   起動と待ちと status の扱いは [run-in-tab.md](references/run-in-tab.md) に従う。
5. 手順4を行った場合は、指摘を計画へ反映し、`review.md` の「計画検証」の表の `対応` 列を埋める。
   `要件` が増えたなら、分割をもう一度判定する。
6. `plan.md` のパスをユーザーへ伝え、`要件` と `方針` の見出しを列挙して承認を求める。
   承認を得るまでコードを変更しない。
7. 承認後に実装する。
   規模が大きく、範囲が重ならない単位へ分けられるなら codex へ委譲する。分けた単位は並行させてよい。
   委譲プロンプトは [impl-delegation-prompt.md](references/impl-delegation-prompt.md) を骨組みにし、調査で分かった現状の作りをそこへ書く。`<work-dir>`、`<repo-root>`、`<result-file>` を具体的な値に置き換える。`plan.md` には書かない。
   書き出した `<work>/impl-prompt-<name>.md` を渡す。

   ```
   scripts/spawn-codex-tab.sh --name impl-<name> --role impl \
     --cwd <repo-root> --effort <effort> \
     --prompt-file <work>/impl-prompt-<name>.md \
     --result-file <work>/impl-result-<name>.md --no-wait
   ```

   herdr の tab が1枚立ち、そこで codex が動く。ユーザーが進行を見られ、その場で介入できる。
   引数と戻り値と落とし穴は [run-in-tab.md](references/run-in-tab.md) にある。読むのは status で迷ったときでよい。

   1本でも `--no-wait` で起動し、`scripts/wait-codex-tabs.sh` で待つ。
   Bash ツールは10分で切れるので、`--timeout 540` を返るまで呼び直す。待ちの間はトークンを消費しない。

   effort は `xhigh` を既定にする。方針が確定していて機械的な作業なら `high` にする。

   `needs-user` が返ったら、`issue` の論点をユーザーへ提示して回答を得る。
   main が代わりに判断しない。回答は `scripts/resume-codex-tab.sh` で止まっている tab へ届ける。
   `no-result` と `pane-gone` は tab を開いて原因を読み、ユーザーへ伝える。

   codex CLI が無い環境では fresh な subagent に委譲する。
   `要件` と `方針` から外れるときは訊く。それ以外の細部は実装が決めてよい。
   設定の DoD コマンドを変更範囲に応じて main が実行する。
   tab は決着しても閉じない。コミットまで通ってからまとめて閉じる。
8. ユーザーが実装検証を求めた場合のみ、[impl-review-prompt.md](references/impl-review-prompt.md) の入力プレースホルダー（`<work-dir>`、`<result-file>`）を具体的な値に置換し、`<work>/impl-review-prompt.md` へ書き出して実装者とは別の fresh な codex に渡す。

   ```
   scripts/spawn-codex-tab.sh --name review-<name> --role review \
     --cwd <repo-root> --effort <effort> \
     --prompt-file <work>/impl-review-prompt.md \
     --result-file <work>/impl-review-result.md --no-wait
   ```

   待ち方と status の扱いは手順7と同じである。
   指摘をどう直すかはユーザーが判断し、承認された指摘だけを実装側へ修正させる。

## コミット

コミットは1つにする。plan が単位そのものなので切り分けない。

本文には `plan.md` の `概要`、`要件`、`方針`、`リスク` をそのまま入れる。要約しない。
`実装手順` は入れない。差分が示すうえに、承認も検証もしていないためである。

コード側で `要件` と食い違う箇所があれば、コミット前にユーザーへ伝える。
`plan.md` を後から書き換えて辻褄を合わせない。

## ADR

撤回しにくく長期的な影響を持つ実装方針だけ、`adr-writing` で ADR に残す。簡単には書かない。
プロジェクトの正本に書かれる判断は ADR にしない。正本が二重化する。
ADR ディレクトリは最初の ADR を書くときに作る。

## バイアス分離

検証を行うときは、実装したインスタンスと別の fresh な codex に依頼する。
検証者には指摘だけをさせ、手を動かさせない。
検証者は、コミットメッセージ、計画、実装側の主張を信用せず、コード、差分、実行結果の現物で確認する。

main はこの検証と重ねて自分で差分を読み直さない。
main が行うのは DoD コマンドの実行と、指摘のユーザーへの提示である。
