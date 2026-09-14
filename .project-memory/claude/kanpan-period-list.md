---
name: kanpan-period-list
description: 「看盘」iOS app 的周期档位：日线以上只给周、月、年，不要 3 天
metadata:
  pinned: false
---

2026-09-14，用户为「看盘」（独立的原生 iOS 看盘 app）定下周期档位的规矩：**大于 1d 的周期只给「周、月、年」三档**。原型和早期任务书里有的 `3d`（3 天）要去掉，换成 `1y`（1 年）。

所以完整的 14 档是：1m 3m 5m 15m 30m 1h 2h 4h 6h 12h 1d 1w 1M 1y，默认 1h，常用一行仍是 1m 5m 15m 1h 4h 1d。

实现上要注意币安 `fapi/v1/klines` 原生支持 `3d 1w 1M`，但**没有 `1y`**（传 `1y` 返回 `-1120 Invalid interval`），所以年线必须在客户端按自然年把 1M（或 1d）聚合出来；1w / 1M / 1y 的步长都不是定值，`BarSeries` 要走真实 `openTime` 数组而不是固定 step。
