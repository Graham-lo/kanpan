# iOS 27 真机启动闪退（2026-09-22）

## 现象

iPhone 16 Pro / iOS 27.0 (24A437)，UDID `00008140-00010C902690801C`，开发者模式已开。
Release 包装上去后**点开必闪退**，连续复现 9 次，全部在启动画面之后立刻退回桌面。
九份崩溃报告签名一模一样：`EXC_BAD_ACCESS (SIGSEGV)` / `Thread stack size exceeded` /
`KERN_PROTECTION_FAILURE`，出事的是主线程（faultingThread 0）。
原始报告见本目录 `crash-before.ips`。

栈顶是 Swift 运行时的类型元数据解码在自我递归：

```
swift::SubstGenericParametersFromMetadata::buildDescriptorPath
swift::Demangle::TypeDecoder<...>::decodeMangledType
swift::Demangle::TypeDecoder<...>::decodeGenericArgs
swift_getTypeByMangledName
swift_getTypeByMangledNameInContext2
Kanpan __swift_instantiateConcreteTypeFromMangledNameV2
closure #4 in closure #1 in MainScreen.header.getter
MainScreen.header.getter → chartPage → portraitBody → basePresentation
→ presentation → lifecycleContent → indicatorObservedContent → observedContent
→ marketContent → MainScreen.body.getter
SwiftUI ViewBodyAccessor.updateBody → AttributeGraph → _UIHostingView.layoutSubviews
```

排除项：拿干净的 `origin/main`（`7157341`）重新打 Release 包同样必崩，所以**不是当时工作树里
未提交的改动引起的**；签名、描述文件、开发者模式都正常，**不是签名问题**；
iOS 26.5 模拟器完全不崩，所以它是 iOS 27 运行时才暴露出来的。

## 根因一句话

`MainScreen.body` 是一棵约 141 层的嵌套泛型 `ModifiedContent<...>` 具体类型，
iOS 27 运行时按 mangled name 实例化这个类型时递归深度超过了主线程 1MB 栈，栈溢出。

## 改了什么

纯结构整改，**行为零变化、视觉零变化**，只动两个文件。

| 位置 | 改动 |
|---|---|
| `Kanpan/Kanpan/Main/MainScreen.swift:1-40` | 新增文件头警告注释，写清嵌套层数天花板，并留下 `Thread stack size exceeded` / `decodeMangledType` 两个关键词，防止以后有人把 `.onChange` 重新堆回主链 |
| `Kanpan/Kanpan/Main/MainScreen.swift:364` | `lifecycleContent` 精简为 `.onAppear` / `.task` / `.task(id: beating)` / `.modifier(observers)` 四层 |
| `Kanpan/Kanpan/Main/MainScreen.swift:389` | 新增 `observers` 计算属性：在 **`MainScreen.body` 里**算好全部 26 个被观察值，连同 33 个动作闭包传给 `MainScreenObservers` |
| `Kanpan/Kanpan/Main/MainScreen.swift` | 删除 `indicatorObservedContent` / `observedContent` / `marketContent` 三个中间层，`body` 里 9 个 `.onChange` 一并收走 |
| `Kanpan/Kanpan/Main/MainScreen.swift:877 / 1063 / 1156 / 1162` | `header` / `chart` / `reviewHeader` / `captureCard` 改成只负责转发参数的薄壳 |
| `Kanpan/Kanpan/Main/MainScreenParts.swift`（新建，484 行） | `MainScreenObservers`（ViewModifier，31 个观察者）、`MainHeaderView`、`MainChartView`、`ChartHistoryRetry`、`ChartLoadingBadge`、`ReplayHeaderView`、`ReviewCaptureLayer` |

为什么这样就能断开嵌套：**只有非泛型 `View` struct 的 `body` 和自定义 `ViewModifier` 的
`body(content:)` 会开一个新的类型根**（后者的 `Content` 是 `_ViewModifier_Content<Self>`，
不含宿主类型）。计算属性 `some View` 和泛型包装都不会重置深度。

保行为的两条硬规矩，代码注释里也写了：

1. **`onChange(of:)` 的 `of:` 表达式一律在 `MainScreen.body` 里求值再传进去。** 依赖记在谁的
   body 上是按求值位置算的；要是图省事在子视图里读 `picker.prefs.favorites`，宿主就不再订阅它，
   由它算出来的 `listVisible` 会永远停在旧值。
2. **动作闭包一律接收新值作参数**，不从捕获的 `self` 里读，否则拿到的是变更前的旧值。

`MainScreenObservers.body` 拆成 `lifecycleSection` / `displaySection` / `marketSection` /
`panelSection` 四段嵌套调用，是因为 31 个 `onChange` 串成一条表达式会让类型检查器超时
（`unable to type-check this expression in reasonable time`），修饰符顺序原样保留。

## 层数 141 → ≈38

「顶层修饰符数」按任务书给的口径（主链上每个属性自己那一段的修饰符个数）：

| 属性 | before | after | 说明 |
|---|---|---|---|
| basePresentation | 8 | 8 | 未动 |
| presentation | 4 | 4 | 未动 |
| lifecycleContent | 5 | 4 | 观察者收进 `.modifier(observers)` 一层 |
| indicatorObservedContent | 4 | 0 | 删除 |
| observedContent | 8 | 0 | 删除 |
| marketContent | 14 | 0 | 删除 |
| body | 25 | 17 | 9 个 `.onChange` 移走 |
| portraitBody | 3 | 3 | 未动 |
| chartPage | 29 | 2 | `chart` / `reviewHeader` / `captureCard` 各自成了新类型根 |
| header | 41 | 0 | 整段进 `MainHeaderView`（它自己的 body 是新类型根） |
| **合计** | **141** | **≈38** | |

复核口径：另用一个只数「链式修饰符调用」的脚本对同一批属性做了 before/after 对照，
得 **121 → 43**（该脚本在 presentation=4、lifecycleContent=5、indicatorObservedContent=4、
observedContent=8、marketContent=14 这五项上与任务书给的数字完全一致，差异只出在
`header` / `chartPage` 这类把子属性内联进去算的项上）。两个口径的结论一致：主链深度砍掉了约七成，
剩余层数在 40 以内。

## 真机存活证据

完整原始记录见 `after-device-survival.txt`。要点：

```
$ make install-release        → ** BUILD SUCCEEDED **  /  App installed:
$ xcrun devicectl device process launch --device 00008140-00010C902690801C \
      --terminate-existing com.mdd.kanpan
  Launched application with com.mdd.kanpan bundle identifier.

[17:57:29] 3225  .../Kanpan.app/Kanpan
[17:57:40] 3225  .../Kanpan.app/Kanpan
[17:57:51] 3225  .../Kanpan.app/Kanpan
[17:58:01] 3225  .../Kanpan.app/Kanpan
[17:58:12] 3225  .../Kanpan.app/Kanpan     ← 同一个 PID 连续存活 52 秒
```

前一轮（17:55:55 启动）同样以 PID 3224 在 T+8s / T+18s / T+33s 三次点名都在。
17:59 重新拉设备崩溃报告，最后一份 Kanpan 崩溃仍是修复前的 `Kanpan-2026-09-22-173643.ips`，
修复后的两次启动**没有产生任何新的 ips**。

没有 `after.png`：这台手机只经 CoreDevice 无线连接，本机 devicectl 的 `device` 子命令里
没有 `screenshot`，libimobiledevice 也够不到 iOS 17+ 的 RSD 服务（`idevice_id -l` 为空、
`Could not start screenshotr service: Invalid service`）。按任务书允许的兜底方案，改用上面
这份 30 秒以上进程存活的文字记录。

## 其它验证

- `make build`（iPhone 16 Pro 模拟器）→ `** BUILD SUCCEEDED **`
- `make install-release`（真机 Release）→ `** BUILD SUCCEEDED **` + `App installed:`
- 受影响的模拟器 UI 用例：`KanpanUITests/MainScreenUITests` + `KanpanUITests/ScanAndDetailZoomUITests`
  （头部六格统计、品种名不可点、顶栏只有搜索、周期条、各面板开合、点图关面板、画线进出、
  横屏画线隐藏指标、回到最新、扫图横滑、细看缩放），见 `ui-test.log`
