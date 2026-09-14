---
name: kanpan-default-subplots
description: 「看盘」这个 iOS 看盘 app 的副图默认挂 MACD 和 RSI，不是成交量
metadata:
  node_type: memory
  pinned: false
  originSessionId: b7df3459-eec1-43f9-9318-99ece4bc748a
  modified: 2026-09-14T06:10:35.494Z
---

2026-09-14，用户为「看盘」（独立的原生 iOS 看盘 app，只有品种／周期／K 线／指标）定下一条默认值：**副图默认使用 MACD 和 RSI 两个指标**。在此之前原型的副图默认是成交量（VOL），用户看过之后明确要求改掉。

这条要一直带到 Swift 实现里：`KanpanCore` 和图表视图的初始副图列表应当是 `["MACD", "RSI"]`，主图叠加维持 MA。用户仍然可以在指标面板里增删副图，默认值只是开箱状态。

注意这和 Trader Foresight（原 Scorebook）那条「任何图表指标都必须有开关且默认不显示」是两个产品的两套规矩，不要互相套用：Trader Foresight 的图是记录用的，默认干净；看盘是自用盯盘工具，用户要一打开就有这两个副图。

另外，改动这类默认值时要同时把本地存档的键名往上跳一版（原型里是 `kanpan.v1` → `kanpan.v2`），否则用户手机上的旧存档会把新默认值盖回去，他会以为改动没生效。
