# kanpan-order-status-words-unified-no-colloquial

**工作习惯 / 用户纠正**：看盘大单 / 挂单的状态词 2026-10-08 起三端统一走 terms.json：挂单中 / 成交中 X% / 已成交 / 成交 X% · 撤单 Y% / 已撤单 / 已失联 / 已结束；「挂着」「在场」「已挂」「已撤销」这类口语或含糊词不许再出现

用户 2026-10-08 原话：「挂着一律改为挂单中不要用口语化词语，统一管理，这点之前做过」「成交中，已成交，撤单等一目了然的词语……按照实际情况展示不同的词语」「一律使用订单的状态，让用户知道怎么回事」。

**Why:** 界面上的状态要让用户一眼知道这张单现在怎么了；「挂着 / 在场」是口语、含糊，而且三端各写各的会漂。用词单一来源的规矩之前就定过（见 `kanpan-indicator-names-params-single-source`、`kanpan-ui-labels-are-chinese`）。

**How to apply:** 状态词只在 `KanpanCore/Sources/KanpanCore/Terms/terms.json` 的 `statusLive / statusFilling / statusFilled / statusPartFilled / statusCancelled / statusLost / statusEnded / held` 这几项，iOS 用 `BigTradeTerm`、网页用 `BT`；界面代码不再写状态字面量。TermsTests 的口语禁词表已含「挂着 / 在场 / 已挂 / 已撤销 / 后撤」，新增文案先过它。以后任何新状态（提醒、同步等）同样按「实际状态 + 一目了然的词」来，不写比喻。
