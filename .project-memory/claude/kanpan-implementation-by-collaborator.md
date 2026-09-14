---
name: kanpan-implementation-by-collaborator
description: 「看盘」iOS app 的代码实现由用户的协作者负责，Claude 不要主动开发，只在用户下命令时才动手
metadata:
  node_type: memory
  pinned: false
  originSessionId: b7df3459-eec1-43f9-9318-99ece4bc748a
  modified: 2026-09-14T07:28:06.552Z
---

2026-09-14，用户在「看盘」这个原生 iOS 看盘 app 的仓库（https://github.com/Graham-lo/kanpan ，本机 `/Users/mdd/zhk/kanpan/`）里明确说：「你先别开发了，后续等我命令，是我协作者在开发」。

背景是仓库工作树里出现了一套约 3400 行、未纳入版本控制的 Swift 代码（`KanpanCore/` 和 `Tools/`），不是 Claude 写的。Claude 当时发现它的周期枚举还是旧的（带 `3d`、没有 `1y`），问要不要改并提交；用户先回了「是的，可以改成 1y」，紧接着又补了这条停工指令。后一条覆盖前一条：不要去改 `KanpanCore/`，也不要提交它，把 `1y` 的事留给协作者。

因此在「看盘」项目上的默认姿态是：**只在用户明确下命令时才动手写代码**。文档、任务书、原型、仓库维护这类事仍然可以按用户当次的要求做，但 Swift 实现本身属于协作者的地盘，不要并发修改、不要自作主张提交，也不要在新会话里「接着上次的实现继续」。这和之前 Scorebook 移交 Codex 时的约定是同一类：有另一个人在同一棵树上写代码时，并发改动会互相覆盖。
