# kanpan-bigtrade-page-takes-all-venues-no-descriptions

**项目约定**：看盘「大单与爆仓」页（iOS 弹层 / 手机网页弹层 / PC 抽屉）要接入全部交易所的数据（2026-10-08 起含 Bybit、Hyperliquid），页上解释性描述一律删掉只留数据

2026-10-08 用户交代：另一个窗口做的「大单与爆仓」独立页面（iOS `BigTradeSheet`、手机网页 `bigTradeSheet.ts`、PC `drawerView.ts` 抽屉）快完成了，新接的交易所（Bybit、Hyperliquid）的簿 / 逐笔 / 爆仓数据「后面是要接入进去的，别忘了」；并且「该页面一些无关的描述直接去掉即可」。

**Why:** 用户不关心哪家交易所，大单页是按桶汇总的统一展示，少一家就少一块量；页上的解释文案是干扰（见 `kanpan-ui-no-lecturing`）。

**How to apply:** 以后再接任何交易所（见 `kanpan-multi-exchange-is-in-scope`），接完必须顺手把大单页三端的分项 / 汇总 / 爆仓「哪家」映射补上并截图核对；大单页只放数据与短标签，不写「这是什么 / 怎么看」的句子。
