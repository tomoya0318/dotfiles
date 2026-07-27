# Plan 描画の安全性確認

## 概要

[危険なリンク](javascript:alert('plan-link')) はリンクにしない。

![外部画像](https://example.invalid/workbench-plan-image.png)

段落の前は残す。<script>globalThis.planScriptExecuted = true</script>段落の後も残す。

| 種類 | 内容 |
|---|---|
| HTML を含むセル | セルの前 <strong>この HTML は捨てる</strong> セルの後 |
| 通常のセル | **Markdown の強調は残す** |

## 判断

### 安全性確認にだけ使う

このファイルは専用の一時セッションへコピーし、実際の計画を上書きしない。
