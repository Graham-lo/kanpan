# Hntcoin 品牌素材

桌面图标是用 CoreGraphics 直接画出来的，没有位图源文件，改设计就改对应的生成脚本：

```
swift icon-generator-v5.swift <输出目录>     # 当前这版（纯形状 P/Q/R/S）+ contact-sheet-5.png
swift flatten.swift <源图> <目标图>          # 去掉 alpha 通道，iOS 图标不允许透明
```

当前采用 **Q 叠**（`icon-Q-overlap-1024.png`：墨色底上一个米白圆角方和一个黄铜圆相叠，
交叠处压暗做出前后关系）。纯形状构图，不含字母、行情元素，也不承载寓意。
已展平后放在 `Kanpan/Kanpan/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`。

同一版的备选在同目录：
- `icon-P-fold-1024.png` 折（一道斜折面，明暗两块）
- `icon-R-arc-1024.png` 弧（一条粗黄铜弧）
- `icon-S-orb-1024.png` 丘（一个软球）

再上一版是带字母 H 的安静稿（L/M/N/O，见 `icon-generator-v4.swift`），需要字母时可回取。

换一版只需 `swift flatten.swift icon-X-....png ../../Kanpan/Kanpan/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`，
文件名不变，asset catalog 不用改。

早几轮的稿子（E 金币 H、F 霓虹、G 金币行情、H 极光、I 液态铬、J 宝石、K 环）和它们的
生成脚本 `icon-generator.swift` / `icon-generator-v3.swift` 一并留着，方便回头对照。

改完可以不跑构建就校验目录是否合法：

```
xcrun actool <路径>/Assets.xcassets --compile $(mktemp -d) --platform iphoneos \
  --minimum-deployment-target 17.0 --app-icon AppIcon \
  --output-partial-info-plist /tmp/partial.plist --target-device iphone --target-device ipad
```

桌面名字在 `Kanpan/Kanpan.xcodeproj/project.pbxproj` 的
`INFOPLIST_KEY_CFBundleDisplayName`（Debug/Release 各一处），现为 `Hntcoin`。
Target、bundle id、scheme、Makefile 里的 `Kanpan` 标识符没有动。
