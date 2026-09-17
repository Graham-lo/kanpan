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

## 六、未做 / 边界

- **没有下载 iOS 18 模拟器运行时**，按用户口径，18 这一侧只有静态核查；实测全在 26.5 上。
- **没有做 iPad 宽屏分栏**，按「不破」的口径，这不在这一轮范围里。
- 全量 13 台矩阵（`Tools/ui-test.sh`）**押后**：另外两个窗口的改动此刻还在工作树里没落提交，
  现在跑出来的红绿归谁说不清。等它们落地后再跑一遍。

## 七、真机（iPhone 16 Pro / iOS 26.6.1）

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
