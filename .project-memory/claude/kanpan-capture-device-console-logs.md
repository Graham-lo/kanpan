# kanpan-capture-device-console-logs

**项目约定**：看盘抓真机日志时用后台任务写日志文件再轮询，不要用 timeout（macOS 没有），也不要让 --console 会话结束时把 app 带走

2026-09-18 在真机上验证行情推送时我需要抓 app 的诊断日志（看盘的 `FeedLog` 由环境变量
`KANPAN_LOG=1` 打开，推送域名体检由 `KANPAN_WS_SWEEP=1` 打开），路子是
`xcrun devicectl device process launch --console --environment ...`。踩了两个坑：

**一、macOS 没有 GNU 的 `timeout` 命令。** 我照惯性写了
`timeout 30 xcrun devicectl ...`，shell 直接报 `timeout: command not found`，
于是连着两轮抓取都静默地什么都没拿到，日志文件是空的而我以为是 app 没打日志。
正确做法是把启动命令丢进后台（Bash 工具的 `run_in_background`）并重定向到日志文件，
再用 Monitor 轮询到够用的行数为止，例如
`until [ "$(grep -c '有效首帧' live.log)" -ge 1 ]; do sleep 2; done`。

**二、`--console` 的会话一结束就会把手机上的 app 一起终止。** 抓完日志如果还要让
用户自己在手机上看界面，必须再用**不带 `--console`** 的
`launch --terminate-existing` 重新拉起一次，否则用户拿起手机会发现 app 已经退了。

所以固定顺序是：后台 `--console` 启动 → 轮询日志文件到拿够证据 → 结束后台任务 →
不带 `--console` 正常重启一次留在手机上。
