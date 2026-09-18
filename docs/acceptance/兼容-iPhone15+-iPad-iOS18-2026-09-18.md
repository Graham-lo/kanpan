# 兼容一轮：iPhone 15 及以上 · 全 iPad 系列 · iOS 18 起

2026-09-18。用户定的三条口径：

1. **最低系统提到 iOS 18.0**，各 SPM 包同步，iOS 17 的兼容分支可以清掉。
2. **iPad 只做「不破」**——每一页在 iPad 全部宽度下不错位、不拉伸、可用。
   明确不做宽屏分栏／侧边并排，也明确不砍掉 iPad 支持。
3. **iOS 18 只做静态核查**，不下 18 的模拟器运行时；实测跑在本机装着的 iOS 26.5 上。

---

## 一、最低系统

| 位置 | 值 |
|---|---|
| Kanpan app target（Debug / Release） | `IPHONEOS_DEPLOYMENT_TARGET = 18.0` |
| Evidence 宿主（Debug / Release） | `18.0` |
| KanpanCore / Chart / Data / Network / Review / Account / Settings / Symbols / Diagnostics | `platforms: [.iOS(.v18), …]` |

全仓无 `17.0`、无 `.v17` 残留。落在 `a47f2d2`（app + 9 个包）与 `b952fee`
（Evidence 宿主——它链着已经提到 18 的 KanpanChart / KanpanCore，不跟着提会编不过）。

**静态核查结论**：源码里 `@available` / `#available` **一处都没有**。
（全仓 grep 到的 24 处全部落在各包 `.build/` 的生成测试壳里，与产品代码无关。）
也就是说不存在「iOS 17 走一条、18 走另一条」的分支，抬高下限不会让任何代码路径失活，
也没有留下死代码。构建侧：app 与测试包各编一遍，**0 error、0 deprecation 告警**。

## 二、iPad 静态核查

按「在 iPad 上会破」的几类成因逐条查：

| 查什么 | 结果 |
|---|---|
| `NavigationSplitView` / `navigationViewStyle` / `horizontalSizeClass` | 0 处——整套界面不按 size class 分叉，iPad 上就是 iPhone 那一套，不存在「宽屏分支没写好」 |
| 分享单／文档选择器（iPad 上不给 popover 源会**当场崩**） | `UIActivityViewController` / `ShareLink` / `UIDocumentPickerViewController` 全为 0 处，无此风险 |
| 承担版面的固定宽度（≥100pt） | 仅 `TopBar.swift:247` 的 `.frame(width: 184)`，是 2×2 仓/额/市值/费率格子的**防抖宽度**，真机上量定的，iPad 上照样不抖，保留 |
| 正文越过安全区 | 4 处 `ignoresSafeArea` 全是背景层（启动底色、极光背景、透明捕点层、横屏遮罩），**没有一处是内容** |
| 方向声明 | iPad 四向全开，iPhone 三向（不含倒置）——符合「横屏是画线工作台」的设定 |

## 三、iPad 实修

真正会「破」的是**铺满整屏的单列页**：它们的行是「左边一个名目、右边一个数」，
iPhone 上两端相距 350pt 左右扫得过来，13" iPad 横屏铺满就是 1300pt——
品种名钉在最左、价格钉在最右，中间一片空白，对不上号。这是**系统性缺陷**，不是个别页面手误。

修法是封顶而不是重排版，正好卡在「不破」这条线上：

```swift
func readableColumn(_ max: CGFloat = 560) -> some View {
  frame(maxWidth: max).frame(maxWidth: .infinity)
}
```

560pt 比最宽的 iPhone 再富余一点，所以 **iPhone 上这一层等于不存在**；页面底色仍铺在封顶外面，两侧不露白边。
`ReviewUI` 是独立的包、看不到 app 的扩展，所以那边留了同名的一份。

落到四张页（`87e7f56`）：搜索页、品种整页、复盘本、复盘记录详情。
**没有动自选分类页**——那是用户自己定稿的设计，且当时正被另一个窗口改着。

另有三处会拉伸/画错的，在 `a47f2d2` 里一并修了。

## 四、实测矩阵（iOS 26.5 运行时）

`IPadLayoutUITests` 是这道封顶的看门人：每台 iPad 上把三页走一遍，量关键控件宽度（上限 600pt =
560 封顶 + 舍入余量），顺手留截图。iPhone 上窗口本来就窄（402pt），这几条自己跳过。

| 机型 | 宽度 | 内容列封顶 | 横屏画线不画指标 | 「回到最新」 |
|---|---|---|---|---|
| iPhone 16 Pro | 402pt | 跳过（窄屏无意义） | 通过 | 通过 |
| iPad mini (A17 Pro) | 744pt | **通过** | 通过 | 通过 |
| iPad (A16) | 820pt | **通过** | 通过 | 通过 |
| iPad Air 11" (M4) | 820pt | **通过** | 通过 | 通过 |
| iPad Pro 11" (M5) | 834pt | **通过** | 通过 | 通过 |
| iPad Pro 13" (M5) | 1024pt | **通过** | 通过 | 通过 |

13" 上的截图（`iPad-搜索页`、`iPad-搜索页-有结果`、`iPad-复盘本`）目视确认：
内容列居中成一条，BTC 与 76613.80 挨在一起可读；复盘本的待办/记录/战绩分段控件不再摊成满屏。

**机型覆盖说明**：仓库的 13 台清单覆盖 iPhone 宽度 393 / 402 / 430 / 440pt 四档与全部四档 iPad。
iPhone 15 Plus、15 Pro Max、16、16e 与清单内机型同宽同 size class，不另跑。

## 五、顺手修掉的一颗雷

三台 iPad 第一轮各红一条，且都不是断言红，是 XCUI 当场抛
`Failed to get matching snapshot: No matches found`，位置在 `hittable()` 里的 `el.frame`。

`exists` 挡不住 `.frame`——答「在」之后、取 frame 之前的那一帧里按钮已经淡出去了。
这和那段注释里**已经挡住**的 `isHittable` 问题是同一回事，只是深了一层。
iPad 上更容易撞：图更宽、视野归位滑得更久。

改成从 `try? el.snapshot()` 这一张快照上读「在不在 / 有没有面积」——
这是这组接口里唯一会把「没这个元素」老实交成 Swift 错误的路径。改完三台重跑全过（`f26c7a6`）。

这是存量问题，不是这轮引入的；按项目规矩直接修了，没停下来请示。

## 六、全量矩阵翻出来的三条红（都已从根因修掉）

把 13 台矩阵真跑起来之后，iPhone 15 上红了三条。查到底之后分成两类：
**一条是 app 自己的缺陷**（首屏空图），**两条是用例的点法不对**（周期条药丸、自选拖动排序）。
app 那条补了会红的回归用例；用例那两条改的是用例，一行产品代码都没动。

**1. 周期条的药丸被 XCUI 判成「点不着」——是判定抖动，不是 app 的毛病（用例侧）**

现象是 `testLatestQuoteDoesNotRegressAcrossIntervals` 在点周期条时报
`Not hittable: Button, identifier: 'interval.chip.1m'` /
`Computed hit point {-1, -1} after scrolling to visible`，重试三次都一样。

**先走错了两轮，两轮都已经拆掉。** 从 xcresult 导出的无障碍层级里看到屏幕上有**两个**全屏
`Window`，第二个是键盘那层 `UITextEffectsWindow`，于是先按「关搜索页时留了一层透明窗口盖住
整个 app」去修：`f68b543` 把页面拆除推迟一个 runloop，没用；接着又写了个 `KeyboardExit`，
等 `keyboardDidHideNotification`（最多 450ms）再关页，重跑还是在同一处、同一个时间点红。
两处改动现在都已**回滚**（`f68b543` 整个 revert、`KeyboardExit` 及其四个调用点删除）——
它们既没修好问题，`KeyboardExit` 还会白白给关搜索页加上至多 450ms 的延迟。

**真正的证据是从 app 里取的。** 写了一个只在 DEBUG 下挂着的探针（`HitProbe`，取完证已删），
在卡住的那一刻遍历 `windowScene.windows`，对药丸中心那一点各做一次 `hitTest` 和
`accessibilityHitTest`。结果是：

- `#0 UIWindow` → `hitTest` 命中药丸自己的容器，`accessibilityHitTest` 落在它的无障碍节点上；
  这一对结果和界面正常时（尚未卡住）**完全一样**。
- `#1 UITextEffectsWindow` → `hitTest` 和 `accessibilityHitTest` **两个都返回 `nil`**。
  它透明、`hidden=false`、第一次用完键盘后就常驻应用整个生命周期，但它什么也不挡——
  真人的手指和 VoiceOver 的焦点从来没被它拦过。

另外两条对照也否掉了「键盘惹的祸」：`chip1m=false` 在**完全没走过搜索页**的步骤上也出现过；
通过和失败两次迭代的时间线几乎一模一样，不是「没等够」。

**根因在 XCUI 自己那一侧。** `IntervalBar` 的常用行是一个横向 `ScrollView`
（`interval.quick`），内容宽度 `max(可用宽, 自然宽)` 取的是可用宽——实测自然宽 245.3pt、
可用 263pt，**钉几档就铺满几档，从来不溢出**，所以它是一个*滚不动的滚动视图*。
`XCUIElement.tap()` 点滚动视图里的东西之前一定先做一次「滚到可见」，对滚不动的那种，
这一步算回来的命中点偶尔就是 `{-1, -1}`，XCUI 于是判它 not hittable、直接放弃。

**修法是改用例。** 新增 `XCUIApplication.tapIntervalChip(_:)`，按药丸中心的坐标点，
绕开可点性判定——和这条条上本来就在用的那几下 `swipe` 是同一个路子。
四处点药丸的地方（`ChartFoundationUITests` 三处、`MainScreenUITests` 一处）全部换过去；
`tapButton` 顺手加了一个可换的落手动作，好让「点完要等到选中」那套取证逻辑继续用。

**2. 首屏拉不到历史，图就永远钉死在「行情加载中」（`d79e0a5`）**

`testTradFiSearchAndMarketData` 的图一直空着。查下去是两条互相独立的原因叠在一起：

- `MarketFeed.writeSnapshotNow` 会把只有 1 根的序列落盘（快照 79B）。而
  `RoutedMarketFeed` 要收够 3 根才肯把这条线路的图交给界面——1 根的快照画不出第一帧，
  却把上一份能用的覆盖掉了。首屏 429 拉不到历史时正好撞上：序列里只剩 WS 推来的那一根，
  下次冷启动读回来还是一根，图就永远停在「行情加载中」。现在门槛对齐成 3 根（`snapshotFloor`），
  不到就宁可不存。
- `RoutedMarketFeed.forward` 在收到历史报错时会报一声 `.routing(.switching)`。
  可行情页收到 `.switching` 的第一件事就是 `historyError = nil`（`MarketModel.swift:268`），
  于是内部每重试一次就把「点此重试」那条横幅抹掉一次：巡检刚把它亮起来，下一发 429 回来又抹掉，
  用户最后看到的是一张空图加一句「行情加载中」，既没有错误也没有重试的路。
  历史没拉下来本来就不是换线路（线路是用户定的，这里从不换线），那一声本就不该报，去掉了。

两条都补进了 `KanpanData/Tests/KanpanDataTests/BlankChartTests.swift`，
各自把修复退回去验证过会红。

**3. 自选拖动排序抢不过整行那个按钮（`f182353`，用例侧）**

`testFavoritesBatchEditing` 的 0.6 秒长按在机器忙的时候会被 `favorites.open.BTCUSDT`
那个满宽按钮先认走。这一条是用例的问题不是 app 的问题——自选分类页是用户自己定稿的，
不动它——改成按满 1.2 秒、`.slow` 速度拖、松手前再按住 0.8 秒。
顺带修掉一个更隐蔽的错：基准 `before` 原先取在「等布局稳定」那段循环之前，量的是还没落位的坐标。

## 七、未做 / 边界

- **没有下载 iOS 18 模拟器运行时**，按用户口径，18 这一侧只有静态核查；实测全在 26.5 上。
- **没有做 iPad 宽屏分栏**，按「不破」的口径，这不在这一轮范围里。
- 全量 13 台矩阵（`Tools/ui-test.sh`）**押后**：另外两个窗口的改动此刻还在工作树里没落提交，
  现在跑出来的红绿归谁说不清。等它们落地后再跑一遍。

## 八、真机（iPhone 16 Pro / iOS 26.6.1）

**已完成**：按 iOS 18 下限编出的真机 Debug 包签名、安装都成功
（`Apple Development` + `iOS Team Provisioning Profile: com.mdd.kanpan`），
说明抬高下限没有影响真机侧的构建与分发。

**未完成**：三条受影响的 UI 用例没跑成。runner 两次都是
`Early unexpected exit … before establishing connection`，
直接 `devicectl process launch` 给出了根因——`BSErrorCodeDescription = Locked`，
**手机锁着屏**，锁屏状态下 app 起不来、XCUITest 的 runner 也连不上。

解锁后重跑即可，产物已经编好在 `dd-dev`：

```
xcodebuild test-without-building -workspace Kanpan.xcworkspace -scheme Kanpan \
  -destination "platform=iOS,id=02E38904-6C11-53D5-9114-2AB4D6E755DC" \
  -only-testing:KanpanUITests/IPadLayoutUITests \
  -only-testing:KanpanUITests/MainScreenUITests/testLandscapeDrawingHidesEveryIndicator \
  -only-testing:KanpanUITests/MainScreenUITests/testLatestButtonAppearsAfterLeavingLatest
```

（`IPadLayoutUITests` 在 iPhone 上会按设计跳过——402pt 的窗口谈不上封顶。）

截图存于 `docs/acceptance/兼容-2026-09-18/`。
