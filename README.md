# 看盘 · Kanpan（产品名 Hntcoin）

Swift 原生 iOS 行情、自选与复盘应用。SwiftUI 页面 + UIKit/CoreGraphics 自绘图表，零第三方依赖，不提供交易下单。数据来自币安 USDT 永续公开接口，币安不能完整使用时整套切换 OKX（不混源）。

> 本文描述 2026-09-17 的现状。`docs/` 里更早的方案、任务书、交接文档是历史材料，与本文冲突时以本文和当前源码为准。

## 现在长什么样

- **皮肤**：「青苔·冷」（默认）、「陶土·暖」与「经典」三套，各有浅色 / 深色，跟随系统或手动指定。经典是青苔换了一张 AICoin 的白底，文字与强调色和青苔相同，让图里图外同一张纸。这张白底是**纯白 `#FFFFFF`**，不是带蓝的 `#F7F9FF`——真机逐像素量过 AICoin 的行情页，标题、价格行、周期行、主图副图全是纯白，安卓包里的 `sh_base_view_bg` 与 `ui_kline_menu_bg_color` 也都是 `#ffffff`；再往下一层的自选页底取中性灰 `#F7F8FA`（`sh_base_page_bg`），深色是 `#0D111C` / `#090C14`。K 线的颜色只有一套：浅色下三套皮肤的涨跌色、蜡烛、均线、副图指标线和顶栏价格红绿全是 AICoin iPhone 端的实测值（蜡烛 `#36B257` / `#E64552`、MA 黄 / 紫 / 绿 / 珊瑚、副图槽位 `#2FD2B2 #FFB400 #E849B9 …`），皮肤只管图外；深色 AICoin 没在真机量过，经典深色取安卓包常量，青苔 / 陶土深色暂留各自那组（`ThemeSkin` / `ThemeChoice`，色值种子在 `KanpanCore/Sources/KanpanCore/Style/Palette.swift`）。早期的靛色、纸色、暖暗配色已经不存在。
- **底栏**：复盘｜指标｜自选｜设置（`Kanpan/Kanpan/Main/BottomBar.swift`）。没有「横屏」和「风格」格子：横屏只是画线的工作台，点「画线」进横屏、画完自动转回；K 线只保留 AICoin 一套造型（`CandleStyle.all == [aicoin]`），没有风格选择入口。
- **行情页**：顶栏是品种徽章 + 品种名（点开半屏快捷自选与搜索）+ 连接状态点 + 自选星；价格行是 22pt 中等字重的最新价加涨跌幅填色药丸，下面一行成交额 / 振幅小字，不显示 24h 高低。周期条 14 档（1m…1y，不含 3d）。
- **自选页**（「琉璃」版，`Kanpan/Kanpan/Symbols/FavoritesView.swift`）：浅色是光斑底、深色是素底（2026-09-17 用户看真机说深色的两团光晕影响视觉，去掉了），列表行直接长在底上（同日用户选了「融合」，不再垫玻璃纸），衬线标题旁一枚正放的数量印章，涨跌比例条；每行有品种徽章、价格与涨跌药丸（迷你走势图默认关闭，可在「…」里打开）；分类文件夹、排序（含涨跌幅口径）收进排序弹层；长按排序、滑动 / 批量删除、加号选品。冷启动有收藏就进自选页，否则进 BTC。
- **品种徽章**：一个品种一个记号（`CoinBadge` / `CoinBadgeBrands`），配色跟皮肤走。
- **图表**：AICoin 手感复刻（`docs/AICoin-K线复刻规格.md`）。主图 MA(10,30,120,256) / EMA，副图默认 MACD + RSI，可选 VOL、OI、KDJ 等；固定框双指缩放、历史焦点缩放、手动 Y、末根贴右缘、越界阻尼。十种画线工具，画线与图表共用坐标。
- **复盘**（`KanpanReview` + `Kanpan/Kanpan/ReviewIntegration`）：记一笔、列表 / 待办 / 统计、详情、逐根重温、私有 OHLC 找相似；记录固定所属行情源。
- **账号**（`KanpanAccount`）：用户名 + 密码注册登录，Keychain 会话，设备管理、改密、注销；个人数据按账号目录隔离，云端同步以待发队列为准。没有邮箱注册。
- **行情线路**：设置里两档，出厂默认「直连」（只走币安自己的域名，探不通就提示重试、不切 OKX），「网关」只走两台 VPS 网关取 OKX 行情；选了哪条就走哪条，没有自动切换。选择存在 `Prefs.routePolicy`，登录随账号同步、未登录记在本机。多品种启动快照与预热让冷启动和切换不等网络。

## 代码与文档

| 位置 | 内容 |
| --- | --- |
| `Kanpan/Kanpan/` | App 页面：`Main`（顶栏、底栏、主屏）、`Symbols`（自选与选品）、`Panels`、`Settings`、`Drawing`、`Account`、`ReviewIntegration` |
| `Kanpan/Symbols`、`Kanpan/Settings` | `KanpanSymbols`、`KanpanSettings` 两个本地包及其单测 |
| `Kanpan/KanpanUITests/` | XCUITest；用例按 accessibilityIdentifier 找控件（`favorites.*`、`top.*`、`bottom.*`） |
| `KanpanCore/` | 坐标、布局、指标、画线、皮肤色板等纯 Swift 算法 |
| `KanpanChart/` | 自绘图表与 UIKit 手势 |
| `KanpanNetwork/` | 网络层：HTTP / WS 最小接口、币安 REST / WS 客户端与限流、行情线路（直连 / 网关）、网关竞速与冷却；`KanpanNetworkTestSupport` 是两个包共用的测试假件 |
| `KanpanData/` | 行情 feed、目录、历史 OI、快照与缓存（网络请求全部经 `KanpanNetwork`，并把它整包转出给 app） |
| `KanpanAccount/`、`KanpanReview/` | 账号同步与复盘模块 |
| [Backend/kanpan-gateway](Backend/kanpan-gateway/README.md) | 两台 VPS 行情网关（线上服务，只做只读探测） |
| [Backend/kanpan-api](Backend/kanpan-api/README.md) | Rust 个人后端：账号、同步、复盘索引 |
| `prototype/` | HTML 原型；见 [prototype/README.md](prototype/README.md) |
| `docs/` | 方案与验收记录；[docs/账号复盘-实施进度.md](docs/账号复盘-实施进度.md) 是账号 / 复盘 / 行情线路的最新状态，`docs/acceptance/` 是各里程碑的验收证据 |
| `AGENTS.md`、`.project-memory/` | 给任何模型窗口的项目约定与跨窗口记忆 |

历史文档的读法：`docs/实施任务书.md` 是 2026-09-14 的原始任务书，其中默认风格、指标、底栏布局都已被后续决定覆盖；`KANPAN-HANDOFF-2026-09-14.md` 是 Codex 接手当天的快照，仅供追溯。

## 构建与验证

Swift 6、部署目标 iOS 17+，真机验证目标是 iOS 26。打开 `Kanpan/Kanpan.xcodeproj`（或根目录 `Kanpan.xcworkspace`）选 `Kanpan` scheme。

```sh
swift test --package-path KanpanCore
swift test --package-path KanpanNetwork
swift test --package-path KanpanData
swift test --package-path Kanpan/Symbols
make strict
xcodebuild -project Kanpan/Kanpan.xcodeproj -scheme Kanpan -destination 'id=<真机 UDID>' -derivedDataPath /tmp/kanpan-dd build-for-testing
```

验证约定：改动只跑受影响的一两条真机 UI 用例（`-only-testing:` 加超时），不整套回归；纯视觉改动不需要 UI 测试，真机看一眼即可。安装到手机用 `xcrun devicectl device install app`。

App 端无第三方依赖；网关是 Python + aiohttp，个人后端是 Rust。自选、分组、画线、设置持久化；K 线只有有界的内存缓存与启动快照。仓库不包含 VPS 登录配置、私钥、密码或令牌。
