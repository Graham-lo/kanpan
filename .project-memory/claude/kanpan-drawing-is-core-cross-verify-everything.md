# kanpan-drawing-is-core-cross-verify-everything

**工作习惯 / 用户纠正**：看盘里画线是重点功能：性能压测、指标、布局等任何验收都要带着画线交叉验证，并有一套独立抽出来的画线验证套件

看盘（iOS 与网页版）里画线是用户眼中的重点功能。用户 2026-10-07 明说：「无论是性能还是其他，都要交叉画线验证，这是重点功能，最好抽出来」。

**Why:** 之前的压测 / 回归把画线当成一个段落（draw500、regress draw），指标、布局、性能改动时没有把画线叠进去一起测，画线 bug 容易在别的改动里被带坏而不被发现。

**How to apply:**
- 每一轮验收（性能、指标、布局、皮肤、同步……）都要在「图上有画线」的状态下再跑一遍，核对画线的命中 / 拖动 / 选中 / 撤销 / 隐藏 / 跨品种 / 同步没坏。
- 画线验证抽成独立套件（网页版 `Web/scripts/draw-cross.mjs` 一类），场景 × 画线交叉矩阵，能单独一条命令跑完，收尾报告里单列一节。
- 相关：`kanpan-full-regression-after-feature-batch`、`kanpan-acceptance-means-reproducing-the-symptom-is-gone`、`kanpan-verify-by-running-the-app`。
