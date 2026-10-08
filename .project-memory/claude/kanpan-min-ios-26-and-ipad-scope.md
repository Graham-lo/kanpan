# kanpan-min-ios-26-and-ipad-scope

**项目约定**：看盘 iOS app 兼容 iPhone 16 Pro、iPhone 17 Pro Max，2026-10-03 起加上 iPhone 15 Pro Max；系统 iOS 26.6 以上 + iOS 27；手机网页版要适配 iPhone 15 Pro Max 与华为 nova 16（鸿蒙 7 自带浏览器）；其余机型不兼容，除非用户指定；iPad 只求「不破」

# 看盘的兼容范围：两台机器 + iOS 26.6 以上 / iOS 27

## 2026-10-03 加机型：iPhone 15 Pro Max，以及手机网页版的华为 nova 16

用户发来一张华为 nova 16（型号 EMA-AL00U，HarmonyOS 7.0）的「关于本机」截图，说：
「网页版适配一下这个机型以及 15pm，15pm 还要适配 ios app」。所以在下面两台的基础上：

- **iOS app 加 iPhone 15 Pro Max**（430×932 pt，灵动岛）。验收与截图按三台来，模拟器多维护
  一台 15 Pro Max；一个窗口同一时刻仍只开一台。
- **手机网页版（/web/m/）要适配 iPhone 15 Pro Max 的 Safari 和 nova 16 的鸿蒙自带浏览器**。
  鸿蒙 7 不是安卓：浏览器内核是 ArkWeb（Chromium 系），UA 形如 `(Phone; OpenHarmony …) … ArkWeb … Mobile`，
  任何按 Android / iPhone 判断设备的 UA 逻辑都要把它当手机。


## 2026-09-23 定稿：只做 iPhone 16 Pro 与 iPhone 17 Pro Max

先前的演变：09-18 最低系统提到 iOS 18；09-21 用户说「后续不再维护 iOS 26 以下的系统，
这次测试也只修复 26 系统以上的包括 27」，兼容矩阵还是 13 台机型；09-23 中午机器被
多台模拟器和并行构建拖垮之后，用户先缩到四台（16 Pro / 16 Pro Max / 17 Pro / 17 Pro Max），
随即又缩了一次，原话是：

> 「机器再去掉几个，只维护 16 Pro 和 17 Pro Max，如果后续有新的需求再说。
> 以后也只做这两台机器的兼容，以及 iOS 26.6 以上和 iOS 27 兼容，其余一律不再兼容，除非特别指定。」

所以现在的规矩：

- **机型只有两台：iPhone 16 Pro、iPhone 17 Pro Max。** 兼容矩阵、截图证据、UI 测试、
  验收都只跑这两台；模拟器也只保留这两台（`Tools/ensure-devices.sh`、`Makefile` 的
  `DEVICES`、`Tools/ui-test.sh` 的列表都只有这两个名字）。不要再建 16 Pro Max、17 Pro、
  iPhone 15/16 Plus/17/17e/Air 或任何 iPad 模拟器，除非用户点名。
- **系统只有 iOS 26.6 及以上和 iOS 27。** 26.0–26.5 也不再算兼容范围；本机模拟器运行时
  目前是 26.5，它只是「能跑」的替身，出现只在 26.5 上才有的现象不修。真机是 iOS 27。
- **其余一律不兼容，除非用户特别指定。** 别的机型或系统上的 bug 不修、不建矩阵、
  不在报告里写成有保留；用户指定了再加回去。
- 为老系统写的 `@available` / `#available` 分支与降级代码都可以清掉，新代码直接用
  iOS 26 才有的 API。

这条也是 kanpan-watch-machine-resources 的一部分：机型砍到两台的直接原因是模拟器把
16 GB 的机器压垮，不是产品上不想支持别的手机。

## iPad 仍然只求「不破」（这一条没变）

工程的 `TARGETED_DEVICE_FAMILY` 是 "1,2"，app 能装进 iPad，但整套界面是照 iPhone
宽度画的。用户选的是「每一页在 iPad 全部宽度下不错位、不拉伸、可用」这一档，不是重新
设计分栏布局，也不是取消 iPad 支持。09-23 起 iPad 也不在兼容矩阵里、不建 iPad 模拟器；
只有用户点名某个 iPad 问题时才修，修的也只是写死的宽度、弹层形态、横屏与安全区这类
让页面读不通的地方（现行做法是给满屏单列页封 `readableColumn(560)` 的内容列）。
