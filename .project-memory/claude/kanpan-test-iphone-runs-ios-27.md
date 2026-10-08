# kanpan-test-iphone-runs-ios-27

**项目约定**：看盘的验收 iPhone 2026-09-18 起跑 iOS 27，而本机 Xcode 只有 iOS 26.5 SDK 与模拟器，所以模拟器全绿不等于真机能启动，真机启动必须单独验

2026-09-22 排查「app 点开就闪退」时，我一开始拿 iOS 26.5 模拟器复现，发现不崩，差点判成环境问题。
用户当场补了一句：「**真机是 iOS 27 系统**」。这条信息是整个诊断的转折点。

## 事实

- 用户用来验收看盘的那台 iPhone 16 Pro（设备 UDID `00008140-00010C902690801C`）**2026-09-18 中午 OTA 升到了
  iOS 27.0（build 24A437）**。
- 本机 Xcode 是 26.6，`xcrun --sdk iphoneos --show-sdk-version` 给的是 **26.5**，
  `xcrun simctl list runtimes` 里**只有 iOS 26.5 一个运行时**。
- 也就是说：**没有任何模拟器能模拟用户真机上跑的那个系统**。iOS 27 的 Swift 运行时与
  iOS 26.5 的行为并不等价。

## 因此的做法

- **模拟器全绿不等于真机没事。** 那次的 bug 正是只在 iOS 27 上发作：`MainScreen` 的视图类型
  嵌套了约 141 层，iOS 27 的运行时按 mangled name 实例化元数据时递归超过主线程 1MB 栈，
  启动即 `EXC_BAD_ACCESS` / `Thread stack size exceeded`；同一份代码在 iOS 26.5 模拟器上
  启动正常。单测和 UI 用例一条都没红。
- 所以凡是用户看得见的改动，**收尾必须真的在那台 iPhone 上启动一次并确认进程持续存活**，
  不能拿模拟器跑通当验收完成。这条和 kanpan-verify-by-running-the-app、
  kanpan-acceptance-means-reproducing-the-symptom-is-gone 是一致的，这次给出了硬理由。

## 顺带记下的取证手法

真机崩溃报告可以不开 Xcode 界面直接拉下来（libimobiledevice 够不到 iOS 17+ 的 RSD 服务，
`idevice_id -l` 是空的，别走那条路）：

```
xcrun devicectl device copy from --device <UDID> \
  --domain-type systemCrashLogs --source . --destination <dir>
```

拉下来的 `Kanpan-YYYY-MM-DD-HHMMSS.ips` 第一行是元信息、第二行起才是 JSON，
用 `tail -n +2 | python3 -c "import json,sys; d=json.load(sys.stdin); ..."` 解，
`d['exception']`、`d['threads'][d['faultingThread']]['frames']` 配 `d['usedImages']` 就能还原符号化调用栈。

判「有没有崩」要看**有没有新的 .ips**，不要只看进程表：**手机锁屏时用
`devicectl device process launch` 起 app，进程表里查不到它，但这不是崩溃**——
我就因此误报过一次。先用 `xcrun devicectl device info lockState --device <UDID>` 确认
`passcodeRequired` 才下结论。
