# kanpan-indicator-names-params-single-source

**项目约定**：看盘指标名称与出厂参数三端（iOS / 手机网页 / 电脑网页）只存一份 JSON，改名改默认只动这一处；RSI 出厂 14，MACD 保持 10/30/9

2026-10-08 用户要求：指标名称三端一致，「后续只需要改一处」；参数也「各个端尽量统一，不要各处另起一套」。
做法：`KanpanCore/Sources/KanpanCore/Indicator/indicators.json`（按 iOS rawValue 键，name + params），
iOS 作包资源运行时读，手机网页与电脑网页 import 同一个文件（vite server.fs.allow 放行）。

同日参数决定：只把 RSI 出厂改成 14（单线，可自己加线）；MACD 10/30/9、MA 10/30/120/256、
EMA 12/144/169/200 是用户自己 AICoin 里的设置（refs/aicoin/USER-CHART-PROFILE.json），不改。

**Why:** 以前 iOS、手机网页、电脑各写一张名字表和默认参数表，09 月出过电脑 12/26/9 与手机 10/30/9 读数对不上。
**How to apply:** 改指标名称或出厂参数只改这份 JSON；看到哪一端又写了字面量名字/默认参数，收回到它。相关 `kanpan-ui-labels-are-chinese`。
