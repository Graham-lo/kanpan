---
name: keep-main-track-moving-with-subagents
description: 排查旁支问题时不要停掉主线开发，用 sub-agent 并行推进
metadata:
  node_type: memory
  pinned: true
  originSessionId: e9dbcbc0-29db-4fc1-9d26-863d0b737f12
  modified: 2026-09-14T09:05:29.692Z
---

# 旁支排查时用 sub-agent 并行推进主线

用户明确要求：当我陷进某个旁支问题（网络代理排查、环境配置、工具链调试之类）时，
**主开发进度不能停**——原话是「主开发进度也别停，开 sub 并行」。

做法：我自己继续盯旁支问题的同时，用 Agent 工具开一个或多个 subagent
接着往下做主线里程碑的实现工作。给 subagent 的任务要自包含（写清仓库路径、
任务书章节、只读区约束、构建命令），并且和我手上的改动在文件层面不重叠，
避免互相覆盖。

为什么：用户在意的是交付节奏。旁支排查往往要等网络、等界面、等用户点授权，
这些空档期如果什么都不干，整个里程碑就白白拖住了。

注意这条会和「默认不要动用 Agent 工具」的通用指引冲突——以用户这条要求为准。
