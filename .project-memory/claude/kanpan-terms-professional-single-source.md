# kanpan-terms-professional-single-source

**工作习惯 / 用户纠正**：看盘文案用专业看盘用语（不口语、不解释、不啰嗦），三端用词只存一份 KanpanCore/Terms/terms.json，iOS 读 BigTradeTerm、网页读 src/terms.ts

看盘界面文案一律用专业看盘软件的用语：短、无歧义、不口语化、不写解释句。用户 2026-10-08 原话「有些用词不太合适，比如空爆，多头被打得更狠，这不是寻常聊天，这是专业的看盘软件」「用词最好都统一起来，不要到处散落，三端最好通用，统一维护」「当然我说的是专业的用词」。

已定的对照（大单与爆仓）：多单爆仓 / 空单爆仓（不写多爆、空爆、多头被平）；净买入 / 净卖出；大单买入 / 大单卖出；逐根（不写每根）；买墙 / 卖墙；今日最大单笔；数据停于 hh:mm；1 小时 / 今日 / 24 小时；聚焦某根时标题只写时间（不写「该根」）；不写「还在走」「上拉看…」「改 ›」这类口语提示。

**Why:** 口语和解释句显得不专业，还容易产生歧义；三端各写一套会漂移。
**How to apply:** 新文案先进 `KanpanCore/Sources/KanpanCore/Terms/terms.json`（Swift 侧同步 `Terms.swift` 的 case，TermsTests 守着键齐全与禁用词表），代码里不写字面文案。其他功能的文案也按这个口径收，参照指标名的做法 `kanpan-indicator-names-params-single-source`、`kanpan-ui-no-lecturing`、`kanpan-ui-labels-are-chinese`。
