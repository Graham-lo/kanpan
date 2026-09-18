---
name: kanpan-project-location-and-spec
description: 看盘 iOS 项目的真实代码目录和任务书位置，回答前必须先读任务书
metadata:
  node_type: memory
  pinned: false
  originSessionId: 6c4bd828-d529-42c8-8a4e-430ebcd5a1a8
  modified: 2026-09-14T07:22:39.082Z
---

# 看盘（kanpan）项目：先读任务书再回答

> **历史快照（2026-09-14 导入，2026-09-18 标注）。** 只有「真正的仓库在 `/Users/mdd/zhk/kanpan/`、
> 这是个原生 iOS app 不是网页/脚本」这两点还成立。其余都被后续决定覆盖了：**最低系统已是
> iOS 18.0 不是 iOS 17+**；产品名是 Hkline；app 早已不止「品种、周期、K 线、指标」四件事
> （自选分类、板块气泡、画线、复盘、账号都在里面）；`docs/实施任务书.md` 的默认风格、指标与
> 底栏布局也全被覆盖，**不要再「先读任务书」**。现行入口是 `AGENTS.md` → `README.md` →
> `../PROJECT.md`。原文保留在下面只为看当时的上下文。

用户在被问到「看盘」项目的任何问题时，期望我**先去读项目里的实施任务书**，而不是凭一般常识泛泛而谈。他曾直接纠正我：「目前就是做的app啊，你看任务书」——当时我没有查找任务书，就按「看盘系统一般是网页/脚本」给了通用回答，方向完全跑偏。

## 关键路径

- **会话的工作目录 `/Users/mdd/kanpan` 是空的**，不是真正的工程目录。真正的代码仓库在 **`/Users/mdd/zhk/kanpan/`**（独立 git 仓库）。
- 任务书：`/Users/mdd/zhk/kanpan/docs/实施任务书.md`（约 935 行，含全部架构、算法、验收标准）。桌面上 `/Users/mdd/Desktop/看盘-iOS-任务书/` 有同一份的分发包副本。
- 定版原型（只读，不要改）：`/Users/mdd/zhk/kanpan/prototype/` 和 `/Users/mdd/zhk/kanpan-design/`。任务书明确规定「原型即规格」，冲突时以原型为准。

## 项目是什么

一个**原生 iOS app**（Swift 6 / iOS 17+ / SwiftUI 外壳 + UIKit 自绘图表 / 零第三方依赖），做币安 USDT 本位合约的实时看盘，只有品种、周期、K 线、指标四件事。不是网页、不是脚本、不是通用行情系统。

因此凡是涉及这个项目的技术问题，默认语境是 iOS 原生开发、Xcode、模拟器与真机验收，而不是 Web 或后端。
