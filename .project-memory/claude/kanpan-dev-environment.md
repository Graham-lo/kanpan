---
name: kanpan-dev-environment
description: 看盘项目的 iOS 开发环境已装好（Xcode 26.6 / iOS 26.5 运行时 / 八台模拟器），以及 simctl 和构建入口的几个坑
metadata:
  node_type: memory
  pinned: false
---

# 看盘：开发环境已就绪，以及几个踩过的坑

用户要求「直接帮我弄好开发环境」，环境已于本机装完并验证通过，后续会话**不要再从头装一遍，也不要再问用户装没装**，直接在 `/Users/mdd/zhk/kanpan/` 里干活即可。

## 已就位的东西

- Xcode 26.6（`/Applications/Xcode.app`，`xcode-select -p` 已指向它）、Swift 6.3.3、iOS SDK 26.5。
- 模拟器运行时 `com.apple.CoreSimulator.SimRuntime.iOS-26-5`。
- 任务书 A0.2 要求的八台模拟器已创建且**名字唯一**：iPhone SE (3rd generation)、iPhone 13 mini、iPhone 15、iPhone 16 Pro、iPhone Air、iPhone 16 Plus、iPhone 17 Pro Max、iPad mini (A17 Pro)。
- 仓库根有 `Makefile` 作为统一入口（`doctor` / `core-test` / `data-test` / `strict` / `build` / `snap` / `screenshots` / `devices` / `shutdown` / `clean`），工程是手写生成的 `Kanpan/Kanpan.xcodeproj` + 根目录 `Kanpan.xcworkspace`，本地 SPM 包通过 `XCLocalSwiftPackageReference` 引入。

## 坑一：`simctl runtime delete` 不带 `--keep-asset` 会连累别的运行时

运行时列表里可能出现多个条目指向**同一份底层磁盘镜像**（其中一个标成 `Duplicate of ...` / `Unusable`）。我曾直接 `xcrun simctl runtime delete <id>` 删掉那个坏条目，结果把共享的 dmg 一起删了，剩下那条 `Ready` 的运行时变成空壳，`simctl create` 直接报 `Invalid runtime`，只能重新下 8.5 GB。**删运行时条目一律加 `--keep-asset`**，确认没有别的条目引用了再单独清资产。

## 坑二：boot 完不等于能用

`xcrun simctl bootstatus -b` 返回只说明内核起来了，SpringBoard 和显示表面还可能没就绪。这时候 `simctl io ... screenshot` 会报 `NSPOSIXErrorDomain code=60: Timeout waiting for screen surfaces`，`simctl install` / `launch` 会报 `SimError code=405: Unable to lookup in current state`。光轮询 `state` 等到 `Booted` 是不够的。正确做法是**对 install / launch / screenshot 这几条统统加重试**（`Tools/snap.sh` 里的 `retry` 就是干这个的，每 2 秒重试、最多 30 次）。

## 坑三：Xcode 会偷偷加自己的默认模拟器

装完 Xcode 或跑过一次 GUI 后，它会自动创建一批同名默认设备，导致 `-destination name=...` 出现歧义、构建失败。发现重名时按 udid 去重即可（`make devices` 走的 `Tools/ensure-devices.sh` 只补缺的，不负责去重）。

## 部署与签名（已和用户确认过的结论）

免费 Apple ID 用 Personal Team 就能把 app 装到自己手机上，功能和体验与付费签名一致，唯一区别是证书 7 天过期、要重连电脑重签。要 TestFlight / 上架才需要 Apple Developer Program（¥688/年）。任务书 §12.1 规定 **M4 起每个里程碑必须在真机上验**，模拟器只做机型矩阵和截图。
