# 看盘 · Kanpan（产品名 Hkline）

Swift 原生 iOS 行情、自选与复盘应用。SwiftUI 页面 + UIKit/CoreGraphics 自绘图表，零第三方依赖，不提供交易下单。数据来自币安 USDT 永续公开接口；设置里的「行情线路」两档由用户自己选，直连只走币安、网关只走两台 VPS 的 OKX，两条之间没有自动切换，也不混源。

> 更新于2026-09-22。使用方式见[使用手册](docs/使用手册-2026-09-21.md)，现行规格见[文档索引](docs/README.md)。[不做清单](docs/不做清单.md)是唯一排除口径，[交接书](docs/待办交接-Codex-2026-09-22.md)是唯一工作来源；其它文档不产生任务。

## 现在长什么样

- **皮肤**：「青苔·冷」（默认）、「陶土·暖」与「经典」三套，各有浅色 / 深色，跟随系统或手动指定。经典是青苔换了一张 AICoin 的白底，文字与强调色和青苔相同，让图里图外同一张纸。这张白底是**纯白 `#FFFFFF`**，不是带蓝的 `#F7F9FF`——真机逐像素量过 AICoin 的行情页，标题、价格行、周期行、主图副图全是纯白，安卓包里的 `sh_base_view_bg` 与 `ui_kline_menu_bg_color` 也都是 `#ffffff`；再往下一层的自选页底取中性灰 `#F7F8FA`（`sh_base_page_bg`），深色是 `#0D111C` / `#090C14`。图里图外的分隔线取 K 线页自己的那两支——图内结构线（主图 / 时间轴 / 各副图之间、右轴竖线）`ui_kline_divider_color` = `#F2F4F7`，周期条上下 `ui_kline_indicator_bar_divider_color` = `#EAEAEA`，不是通用列表的 `sh_base_divider_dim_fill_color` = `#DEE1E5`（后者离纯白的亮度差是前者的七倍，整屏 8 条会把一块连续的白切成格子）。K 线的颜色只有一套：浅色下三套皮肤的涨跌色、蜡烛、均线、副图指标线和顶栏价格红绿全是 AICoin iPhone 端的实测值（蜡烛 `#36B257` / `#E64552`、MA 黄 / 紫 / 绿 / 珊瑚、副图槽位 `#2FD2B2 #FFB400 #E849B9 …`），皮肤只管图外；深色 AICoin 没在真机量过，经典深色取安卓包常量，青苔 / 陶土深色暂留各自那组（`ThemeSkin` / `ThemeChoice`，色值种子在 `KanpanCore/Sources/KanpanCore/Style/Palette.swift`）。早期的靛色、纸色、暖暗配色已经不存在。
- **底栏**：常驻标签栏「画线 · 图表 · 自选 · 板块分类 · 设置」五格等宽（`Kanpan/Kanpan/Main/TabBar.swift`；旧的 `BottomBar.swift` 已删）。底栏没有自己的底，页面的材料从它身后穿过去，选中态是页面同款的釉面记号。「画线」那一格是动作不是去处——点它把当前这张图横过来画，画完自动转回；没有「横屏」和「风格」格子，K 线只保留 AICoin 一套造型（`CandleStyle.all == [aicoin]`），指标并进「图表设置」面板，复盘挪到行情页顶栏那颗带角标的按钮。
- **行情页**：顶栏是品种徽章 + 品种名 + 复盘（带待办角标）+ 放大镜（`Main/TopBar.swift`）。品种名只是标签，点上去什么都不弹（2026-09-18 撤掉了那个半屏快捷选择层）；换品种两条路：放大镜进搜索页、底栏「自选」进分类自选页。连接状态点与顶栏那颗自选星同日撤掉——加自选统一在搜索页和自选页的行上做。价格块为22pt中等字重最新价，正下方13pt的涨跌额与涨跌幅小字（无底色、无箭头），右侧固定六格统计（两列三行：仓 / 额 · 市值 / 费率 · 结算 / 振幅，2026-09-21 定，`Main/HeaderStats.swift`），头部动态字体封顶 `.large`，价格位数统一取报价步长推导的 `SymbolInfo.priceDecimals`（闪迪 / 美光两位、BTC一位、1000SATS八位）；数额统一 K/M/B/T，市值是总市值（总供应量 × 现价，口径见 `docs/市值口径与数据来源-2026-09-18.md`）。周期条常用行六档等宽铺满（出厂 `5m 30m 1h 4h 1d 1w`，`Prefs.maxQuick = 6`），全部 14 档（1m…1y，不含 3d）在行尾「更多 ˅」里钉住 / 取消。价格区左右横滑是连续扫图（切上一只 / 下一只，名单来自进来时那份列表）。
- **自选页**（「琉璃」版，`Kanpan/Kanpan/Symbols/FavoritesView.swift`）：浅色是光斑底、深色是素底（2026-09-17 用户看真机说深色的两团光晕影响视觉，去掉了），列表行直接长在底上（同日用户选了「融合」，不再垫玻璃纸），衬线标题旁一枚正放的数量印章，涨跌比例条；每行有品种徽章、价格与涨跌药丸（迷你走势图默认关闭，可在「…」里打开）；分类文件夹、排序（含涨跌幅口径与 2026-09-21 新增的「离提醒线最近」）收进排序弹层；长按一行出只读预览卡（打开 / 调整顺序 / 移到分类 / 取消自选），拖动排序退到卡上那条「调整顺序」里；滑动 / 批量删除后给「撤销」，加号选品。冷启动有收藏就进自选页，否则进 BTC。
- **品种徽章**：一个品种一个记号（`CoinBadge` / `CoinBadgeBrands`），配色跟皮肤走。
- **板块分类**（`Kanpan/Kanpan/Sector/`，口径在 `KanpanCore/Sources/KanpanCore/Sector/`）：底栏第四格，2026-09-18 落地。只有一层气泡（板块），点进去是该板块的品种列表（照抄自选页的列表），加密 / 美股是这一页顶上的硬切换；气泡本体是定稿的「釉珠」，见 `prototype/板块气泡-釉珠-2026-09-18.html`。
- **图表**：AICoin 手感复刻（[现行规格](docs/AICoin-K线复刻规格.md)）。主图均线（10/30/120/256）/ 指数均线 / 布林带，副图出厂成交量 + 持仓量 + 平滑异同，同时最多三个；十种候选还包括相对强弱、随机指标、随机强弱、真实波幅、多空比、主动买卖比、基差。直连支持四种外部统计，网关显示中文空态；「盘口」默认关，打开后显示上卖五、下买五的固定十行盘口梯；固定框双指缩放、历史焦点缩放、手动 Y、末根贴右缘、越界阻尼。41 把画线工具（九组，按 TradingView 手机版对齐），画线与图表共用坐标。
- **提醒**（`KanpanCore/Alerts` + `Kanpan/Kanpan/Alerts`，2026-09-20/21）：独立模块，不是画线的属性。画完一条线之后头部价格行就地变成一张小确认卡（六秒不理等于只画线），判定两种「等它碰到」/「等它收盘穿过」，可开「再次提醒」；「设置 → 提醒」是列表。前台本地评估（`AlertEngine`：把行情流的成交价折成 1 分钟桶喂 `AlertEvaluator`，和服务端同一套规则；挂着提醒的品种会被钉进 `QuoteBook` 的订阅范围，跨品种也算），后台由 `kanpan-worker` 服务端评估并把 `fired` 写回同步；两边靠 `status == .active` 这道闸去重。**没有 APNs 密钥时一切照跑，只是不弹锁屏横幅——app 开着时靠浮条 + 震动 + 通知中心那一条**。
- **复盘**（`KanpanReview` + `Kanpan/Kanpan/ReviewIntegration`）：记一笔、列表 / 待办 / 统计、详情、逐根重温、私有 OHLC 找相似；记录固定所属行情源。
- **账号**（`KanpanAccount`）：用户名 + 密码注册登录，Keychain 会话，设备管理、改密、注销；个人数据按账号目录隔离，云端同步以待发队列为准。没有邮箱注册。
- **行情线路**：设置里两档，出厂默认「直连」（只走币安自己的域名，探不通就提示重试、不切 OKX），「网关」只走两台 VPS 网关取 OKX 行情；选了哪条就走哪条，没有自动切换。选择存在 `Prefs.routePolicy`，只记在本机这台设备上，不随账号同步（2026-09-19 按审查 B7 改）。多品种启动快照与预热让冷启动和切换不等网络。

## 代码与文档

| 位置 | 内容 |
| --- | --- |
| `Kanpan/Kanpan/` | App 页面：`Main`（顶栏、标签栏、主屏）、`Symbols`（自选与选品）、`Sector`（板块分类）、`Panels`、`Settings`、`Drawing`、`Account`、`ReviewIntegration` |
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
| `docs/` | [现行规格索引](docs/README.md)、[唯一工作清单](docs/待办交接-Codex-2026-09-22.md)和 `acceptance/` 验收证据；旧方案只在Git历史中追溯 |
| `AGENTS.md`、`.project-memory/` | 给任何模型窗口的项目约定与跨窗口记忆 |

现行事实以源码、验收记录和 `.project-memory/PROJECT.md` 的日期与基线核对。

## 构建与验证

Swift 6、部署目标 iOS 26.0（app 与各 SPM 包同步，2026-09-21 从 18.0 抬上来；iOS 27 也在支持范围内，26 以下不再维护），真机验证目标是 iOS 26。打开 `Kanpan/Kanpan.xcodeproj`（或根目录 `Kanpan.xcworkspace`）选 `Kanpan` scheme。

```sh
swift test --package-path KanpanCore
swift test --package-path KanpanNetwork
swift test --package-path KanpanData
swift test --package-path Kanpan/Symbols
make strict
xcodebuild -workspace Kanpan.xcworkspace -scheme Kanpan -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/kanpan-dd build
```

验证约定：当前任务全部用模拟器，受影响UI用例带超时执行，截图进入阶段报告；完整两机型（16 Pro / 17 Pro Max）矩阵在交接书P4执行。真机安装、账号登录和密钥配置属于第3节外部条件，不做、不等。服务端功能改动须备份、部署并只读验证，流程见 `.project-memory/PROJECT.md`。

App 端无第三方依赖；网关是 Python + aiohttp，个人后端是 Rust。自选、分组、画线、设置持久化；K 线只有有界的内存缓存与启动快照。仓库不包含 VPS 登录配置、私钥、密码或令牌。
