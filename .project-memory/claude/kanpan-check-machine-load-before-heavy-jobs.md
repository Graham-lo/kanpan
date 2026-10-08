# kanpan-check-machine-load-before-heavy-jobs

**项目约定**：看盘里起 xcodebuild、模拟器、swift test 这类重活之前先看机器负载和已在跑的构建/模拟器数量，太多就排队等空出来再跑，不要硬挤上去让所有任务一起拖半天

2026-09-23 我在看盘里改完画线/指标/分享之后起了一个模拟器构建，当时另外几个窗口已经有
三四个 xcodebuild（build-for-testing、KanpanChart test）和模拟器在跑，10 核的机器负载
冲到 55–61。我那个构建跑了一个多小时还在编 app 模块，中途又叠了一个 `swift test`。
用户看到后说：「机器的负载已经严重超标，执行任务的时候应该看看机器资源使用情况，
如果进程模拟器太多了，就放队列中等待，否则一个任务执行半天」。

所以在这个项目里，起任何重活（`xcodebuild build / build-for-testing / test`、
`make install-release`、`swift test`、启动/克隆模拟器）之前：

- **先看资源**：`uptime` 看负载（机器 10 核），`ps` 数一下正在跑的 xcodebuild、
  swift-build、模拟器（`xcrun simctl list devices booted`）有几个。
- **超了就排队，不要硬挤**：负载明显高于核数、或已经有两三个构建/模拟器在跑时，
  不要再并上去。用一个后台脚本低频（几十秒一次）检查，等负载和构建数降下来再启动，
  启动后由后台任务的完成通知把我叫回来——这种「排队等资源」是用户要的，
  不属于 kanpan-no-idle-waiting-for-phone 里禁止的空等。
- **自己的重活也一次只跑一个**：别在构建没完时再叠 swift test、第二个构建或模拟器。
- 已经挤上去、拖得很慢的自己的任务，可以直接停掉再排队重跑（停进程是授权动作，
  见 kanpan-killing-processes-is-authorized）；别的窗口的进程不要动。

原因很直接：大家同时挤，每个任务都慢好几倍，结果比排队依次跑还晚。
