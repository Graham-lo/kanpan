# kanpan-web-drawings-tv-style-full-settings

**项目约定**：电脑网页画线 2026-10-08 起照 TradingView 全可自定义（四页设置弹窗），成交量分布无边框实线、青粉配色；只限 PC 端、只管画线不管指标

2026-10-08 用户拿 TradingView FRVP 截图要求：成交量分布配色照 TV（区外青绿 / 粉红，价值区更亮，VAH/VAL 浅粉，POC 默认关），框住的边缘不画实线；每条画线都能像 TV 那样逐项自定义（输入 / 样式 / 文本 / 坐标 / 可见范围 + 模板），其它 40 种画线同样。

范围用户明确选了：**只改电脑网页端**、**只管画线、不碰指标**、默认配色照截图青粉（不跟皮肤涨跌色）。

**Why:** 用户看 TV 的观感与可调程度更好；这在电脑网页上推翻了 09-28 收设置项 F 组（画线样式表收线型 / 填充 / 坐标）的做法，`kanpan-minimal-settings-surface` 在 PC 画线上让位。
「不画框住的实线」只针对成交量分布（TV 的直方图框只铺 #26C6DA@5% 底、无描边）；其它画线照 TV 各自出厂默认（矩形在 TV 里就有边框）。TV 出厂值可从 cn.tradingview.com 图表页的 webpack 模块里扒（匿名能开图、画 FRVP 要登录）：`webpackChunktradingview.push` 拿 require，色板在模块 788453 的 colors。

**How to apply:** iOS / 手机网页不跟着加弹窗，除非用户再说；新细项样式放画线的 `style` 字段走契约同步，iOS 只原样透传。指标设置不要顺手改成 TV 式。
