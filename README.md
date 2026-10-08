# 看盘 · Kanpan（产品名 Hkline）

Swift 原生 iOS 行情、自选与复盘应用，另有同一套账号与数据的电脑网页 `/web/` 与手机网页 `/web/m/`（`Web/`，Vite + TypeScript，2026-09-29 起）。SwiftUI 页面 + UIKit/CoreGraphics 自绘图表，app 端零第三方依赖，不提供交易下单。行情品种来自三家：币安 USDT 永续（默认，板块页只认它）、Coinbase 美元现货（2026-09-23 起）、美元指数 DXY（服务端自采，2026-10-05 起）；主力订单流另聚合币安 / OKX / Coinbase / Bybit / Hyperliquid 五家的挂单与成交。设置里的「行情线路」两档由用户自己选：直连只走币安自己的域名；网关只走新加坡那一台 VPS（`kanpan.43-160-232-253.sslip.io`）——iOS 的 K 线 / 报价 / 推送在网关线路下由 OKX 供数（服务端替身，`BinanceProvider.upstream(for:)`），网页版的网关线路则经新加坡透传币安本家的 REST 与推送；两条之间没有自动切换，也不混源。

> 更新于 2026-10-08。使用方式见[使用手册](docs/使用手册-2026-09-21.md)，现行规格见[文档索引](docs/README.md)，逐日进展见 `.project-memory/PROJECT.md`。[不做清单](docs/不做清单.md)是唯一排除口径，[交接书](docs/待办交接-Codex-2026-09-22.md)是唯一书面工作来源（P0～P4 已全部完成，之后的活由用户当场指派）；其它文档不产生任务。

## 现在长什么样

- **皮肤**：「青苔·冷」（默认）、「陶土·暖」与「经典」三套，各有浅色 / 深色，跟随系统或手动指定。经典是青苔换了一张 AICoin 的白底，文字与强调色和青苔相同，让图里图外同一张纸。这张白底是**纯白 `#FFFFFF`**，不是带蓝的 `#F7F9FF`——真机逐像素量过 AICoin 的行情页，标题、价格行、周期行、主图副图全是纯白，安卓包里的 `sh_base_view_bg` 与 `ui_kline_menu_bg_color` 也都是 `#ffffff`；再往下一层的自选页底取中性灰 `#F7F8FA`（`sh_base_page_bg`），深色是 `#0D111C` / `#090C14`。图里图外的分隔线取 K 线页自己的那两支——图内结构线（主图 / 时间轴 / 各副图之间、右轴竖线）`ui_kline_divider_color` = `#F2F4F7`，周期条上下 `ui_kline_indicator_bar_divider_color` = `#EAEAEA`，不是通用列表的 `sh_base_divider_dim_fill_color` = `#DEE1E5`（后者离纯白的亮度差是前者的七倍，整屏 8 条会把一块连续的白切成格子）。K 线的颜色只有一套：浅色下三套皮肤的涨跌色、蜡烛、均线、副图指标线和顶栏价格红绿全是 AICoin iPhone 端的实测值（蜡烛 `#36B257` / `#E64552`、MA 黄 / 紫 / 绿 / 珊瑚、副图槽位 `#2FD2B2 #FFB400 #E849B9 …`），皮肤只管图外；深色 AICoin 没在真机量过，经典深色取安卓包常量，青苔 / 陶土深色暂留各自那组（`ThemeSkin` / `ThemeChoice`，色值种子在 `KanpanPresentation/Sources/KanpanPresentation/Palette.swift`）。**涨跌色出厂一律绿涨红跌**（2026-10-03 起三端同口径，老用户迁一次，开关保留）。2026-10-08 起琉璃材质（光斑底、玻璃卡、1/3pt 细线）抽成 `DesignSystem/LiuliMaterial.swift` 铺到全 app；画线默认笔色跟皮肤强调色。早期的靛色、纸色、暖暗配色已经不存在。
- **底栏**：常驻标签栏「图表 · 自选 · 板块分类 · 我的」四格等宽（2026-09-27 从五格收成四格；`Kanpan/Kanpan/Main/TabBar.swift`；旧的 `BottomBar.swift` 已删）。底栏没有自己的底，页面的材料从它身后穿过去，选中态是页面同款的釉面记号。「我的」（`Kanpan/Kanpan/Me/MePage.swift`）收拢账号、复盘本、全部预警、朋友与收件箱、交易所账户、设置六块，复盘待判定角标挂在「我的」记号右上。周期条行尾三件「更多˅ · 分析 · 图表设置」（2026-09-28）；「分析」一张面板四节「画线 · 主力订单流 · 指标 · 对比」，2026-10-08 起按使用频率排位（出厂序即此，用过的按次数前移，同步字段 `analysisUsage`）；「画线」是画线节里的「开始画线」——点它把当前这张图横过来画，画完自动转回，同节还有「隐藏画线」开关（2026-10-06，提醒不随画线隐藏 / 删除而丢）；没有「横屏」和「风格」格子，K 线只保留 AICoin 一套造型（`CandleStyle` 只剩实心 / 空心阳线与网格两个开关）。图表设置只剩「这张图 · K 线 · 显示〔盘口〕 · 价格轴」（2026-09-28 收设置项后）。
- **行情页**：顶栏左侧品种徽章 + 品种名（从自选 / 板块进来时最左多一颗返回键），右上三颗圆片「提醒铃 · ⋯ · 搜索」（`Main/TopBar.swift`，2026-10-08；铃带当前品种未触发提醒数角标，点开「提醒」表〔列表 | 日志〕；「⋯」是系统菜单「添加对比 · 记一笔 · 分享」；10-05 那版五颗圆片与更早的复盘按钮都已收掉）。品种名只是标签，点上去什么都不弹；换品种两条路：放大镜进搜索页、底栏「自选」进分类自选页。价格块为 22pt 中等字重最新价，正下方 13pt 的涨跌额与涨跌幅小字（无底色、无箭头），右侧固定六格统计（两列三行：仓 / 额 · 市值 / 费率 · 结算 / 振幅，2026-09-21 定，`Main/HeaderStats.swift`；品种一格都给不出时整块不摆，如美元指数），头部动态字体封顶 `.large`，价格位数统一取报价步长推导的 `SymbolInfo.priceDecimals`；数额统一 K/M/B/T，市值是总市值（总供应量 × 现价，口径见 `docs/市值口径与数据来源-2026-09-18.md`）。周期条常用行六档等宽铺满（出厂 `5m 30m 1h 4h 1d 1w`，`Prefs.maxQuick = 6`），全部 14 档（1m…1y，不含 3d）在行尾「更多 ˅」里钉住 / 取消；十字线读数 2026-10-08 起挪到周期条那一行。价格区左右横滑是连续扫图（切上一只 / 下一只，名单来自进来时那份列表）。图上每根 K 线最多一枚透明「大单与爆仓」气泡（三端同口径，2026-10-08，`KanpanChart/BigTradeSigns.swift`），点开「大单与爆仓」弹层（`OrderFlow/BigTradeSheet.swift`）；K 线收盘倒计时 2026-10-03 起不再展示。
- **自选页**（「琉璃」版，`Kanpan/Kanpan/Symbols/FavoritesView.swift`）：浅色是光斑底、深色是素底，列表行直接长在底上（2026-09-17 用户选了「融合」），衬线标题旁一枚正放的数量印章，涨跌比例条；每行有品种徽章、24 小时走势线（2026-10-08 起出厂开，全局开关「我的 › 设置 › 通用」首行 `Prefs.favoritesTrend`，随账号同步）、价格与涨跌药丸；分类是固定枚举（加密 / 美股 / Coinbase 现货 / 指数…），长按一行出只读预览卡（打开 / 调整顺序 / 移到分类 / 取消自选），拖动排序退到卡上那条「调整顺序」里；滑动 / 批量删除后给「撤销」，加号选品。2026-09-28 收设置项后自选表永远按自选顺序，排序弹层与迷你走势开关都已收掉。冷启动有收藏就进自选页，否则进 BTC。
- **品种徽章**：一个品种一个记号（`CoinBadge` / `Resources/CoinBadgeBrands.json`），配色跟皮肤走。
- **板块分类**（`Kanpan/Kanpan/Sector/`，口径在 `KanpanCore/Sources/KanpanCore/Sector/`）：底栏第四格，2026-09-18 落地。一张板块列表（按当前窗口涨跌幅排，行上是板块名、品种数、跑赢大盘数、「领涨 X」、成交额；页头「今日 / 5 日」窗口切换，5 日只在服务端给得出时出现），点进去是该板块的品种列表（照抄自选页的列表，按当前窗口涨跌幅降序），加密 / 美股是这一页顶上的硬切换（美股 2026-10-08 起 23 格）。2026-09-24 起气泡场整套删除（用户：「不再展示气泡，一律用页面即可」），`prototype/板块气泡-釉珠-2026-09-18.html` 只是历史。
- **图表**：AICoin 手感复刻（[现行规格](docs/AICoin-K线复刻规格.md)）。主图 7 种：MA（10/30/120/256）/ EMA / BOLL / VWAP / 超级趋势 / 抛物线 / 主力订单流；副图 10 种：成交量 · 累计量差 · MACD · RSI · KDJ · 动向指标 · 持仓量 · 多空比 · 买卖比 · 基差，同时最多三个，出厂成交量 + 持仓量 + MACD（随机强弱、真实波幅的算法留着但不在面板里；指标名与出厂参数三端只有一份 `KanpanCore/Sources/KanpanCore/Indicator/indicators.json`）。直连支持外部统计副图，网关显示中文空态；「盘口」默认关，打开后显示上卖五、下买五的固定十行盘口梯；固定框双指缩放、历史焦点缩放、手动 Y、末根贴右缘、越界阻尼。画线契约 41 种（`Drawing.Kind`，老存档与云端都要认），**手机画线面板只摆 12 把**（`Drawing.Kind.palette`，2026-09-22 用户砍的，见[不做清单](docs/不做清单.md)；射线 / 直线 / 箭头等在样式表「换一种画法」里换，区间并进「测量」，标签 / 旗标并进「标注」），电脑网页工具栏按 TradingView 九组摆全 41 种；画线与图表共用坐标。「对比」最多叠 3 只，百分比坐标，入口在「分析」面板与顶栏「⋯」两处。
- **提醒**（`KanpanCore/Alerts` + `Kanpan/Kanpan/Alerts`，2026-09-20 起）：独立模块，不是画线的属性。价格提醒从图上起手：点图出十字线 → 周期条那一行「创建提醒」→ 创建页（价格预填、条件「价格达到 / 收盘穿过」、可选网络回调地址）；画线提醒在选中栏的胶囊一点就开；另有条件提醒（费率 / 持仓量 / 均线穿越 / 大单墙，只在登录且币安 U 本位时出现）、复盘到点、自选五分钟波动（幅度按每只近一天波动自动定）。**只响一次、响完即删**；画线隐藏或删除都不影响提醒，线不可见时图上按提醒自己的几何画一条琥珀虚线 + 铃铛。总表「全部预警」在「我的」里，顶栏铃开当前品种置顶的列表与触发日志（`GET /v1/alerts/log`，留 30 天）。前台本地评估（`AlertEngine` 把行情流折成 1 分钟桶喂 `AlertEvaluator`，和服务端同一套规则），后台由 `kanpan-api worker` 评估并把 `fired` 写回同步；两边靠 `status == .active` 这道闸去重。**没有 APNs 密钥时一切照跑，只是不弹锁屏横幅——app 开着时靠浮条 + 震动 + 通知中心那一条**。提醒铃声四档随账号同步。
- **复盘**（`KanpanReview` + `Kanpan/Kanpan/ReviewIntegration`）：记一笔（取景区间 = 图上看得见的那一段）、列表 / 待办 / 统计、详情、逐根重温、私有 OHLC 找相似、交易回放；入口在「我的 › 复盘本」与顶栏「⋯ › 记一笔」；记录固定所属行情源。只读交易所 API 接入与自动复盘见 `docs/交易复盘-协议-2026-09-27.md`。
- **账号**（`KanpanAccount`）：用户名 + 密码注册登录，Keychain 会话，设备管理、改密、注销、导出；个人数据按账号目录隔离，云端同步以待发队列为准，登录了就一直同步（「自动同步」开关 2026-09-28 收掉）；同一类设备（手机 / 平板 / 电脑）只许一台在线。没有邮箱注册。
- **行情线路**：设置里两档，出厂默认「网关」（2026-10-08 起，和网页版一致，国内不开代理也能用）：iOS 在网关线路下 K 线 / 报价 / 推送只走新加坡网关的 OKX 替身（`/market/v1/*?source=okx`、`/market/okx/stream`，直连才有的外部统计副图显示中文空态）；网页版在网关线路下经新加坡透传币安本家（`/v1/market/raw/*?source=binance` + `/market/stream` 共享上游）。「直连」只走币安自己的域名（探不通就提示重试、不切 OKX；国内要开代理）；选了哪条就走哪条，没有自动切换。老档里的直连升级时迁成网关一次（`PrefsCodec` 第 5 版），之后自己切回直连就留住。选择存在 `Prefs.routePolicy`，只记在本机这台设备上，不随账号同步（2026-09-19 按审查 B7 改）。线路只管币安主行情；kanpan-api（账号、同步、订单流中继、深度快照、Coinbase / 美元指数透传、板块历史）在任何线路下都只打新加坡那台。多品种启动快照与预热让冷启动和切换不等网络。

## 代码与文档

| 位置 | 内容 |
| --- | --- |
| `Kanpan/Kanpan/` | App 页面：`Main`（顶栏、标签栏、主屏）、`Symbols`（自选与选品）、`Sector`（板块分类）、`Me`（我的）、`Panels`（分析 / 图表设置）、`Settings`、`Drawing`、`Alerts`、`Compare`、`OrderFlow`（主力订单流、大单与爆仓）、`Exchange`（只读交易所账户）、`Share`（发给朋友）、`Account`、`ReviewIntegration`、`Habits`（按习惯自动调整）、`Glossary`（术语问号）、`DesignSystem`（琉璃材质）、`Diagnostics`、`Widget`、`App` |
| `Kanpan/KanpanTests/` | app 侧逻辑单测（`@testable import Kanpan`，按页面分组：`make app-logic-test` / `main-ios-test` 等） |
| `Kanpan/KanpanShared/`、`Kanpan/KanpanWidget/` | app 与小组件扩展共用的源文件（锁屏实时活动的属性、小组件快照的读写）与小组件扩展 |
| `Kanpan/KanpanUITests/` | XCUITest；用例按 accessibilityIdentifier 找控件（`favorites.*`、`top.*`、`bottom.*`） |
| `KanpanCore/` | 坐标、布局、指标、画线、提醒、订单流等纯 Swift 模型与算法（不含皮肤与界面文案） |
| `KanpanPresentation/` | 三套皮肤的配色种子与图表用色表（`Palette`）、设置里的档位名 |
| `KanpanChart/` | 自绘图表与 UIKit 手势 |
| `KanpanNetwork/` | 网络层：HTTP / WS 最小接口、`Provider/`（`MarketProvider` 抽象与 `VenueRegistry`）、`Binance/` `Coinbase/` `Macro/` 三家行情、`OKX/` `Bybit/` `Hyperliquid/` 订单流、行情线路（`Route/`）；`KanpanNetworkTestSupport` 是共用的测试假件。接新交易所照 `docs/多交易所-接入指南.md`，守卫 `Tools/check-venue-isolation.sh` |
| `KanpanData/` | 行情 feed、目录、历史 OI、快照与缓存（网络请求全部经 `KanpanNetwork`，用到网络层名字的文件自己 `import KanpanNetwork`） |
| `KanpanAccount/`、`KanpanReview/` | 账号同步与复盘模块 |
| [Web/](Web/README.md) | 电脑网页 `/web/` 与手机网页 `/web/m/`（`Web/src/m/`）：Vite + TypeScript，不用 UI 框架；`make web-*` 目标 |
| [Backend/kanpan-api](Backend/kanpan-api/README.md) | Rust 个人后端：账号、同步、提醒评估（`kanpan-api worker` 子命令）、复盘索引、订单流聚合与热力、爆仓分钟聚合、交易所透传（`src/venues/`）、隐私政策与条款（`src/legal.rs`） |
| [Backend/kanpan-gateway](Backend/kanpan-gateway/README.md) | Python aiohttp 行情网关（`/market/v1/*` 历史 K 线、`/market/stream` 共享上游）；线上服务，只做只读探测 |
| `Evidence/` | 取证宿主 app（`KanpanEvidenceHost`，`make evidence` 渲染像素基线） |
| `Tools/`、`scripts/` | 构建 / 测试 / 截图脚本（`Tools/ui-test.sh` 等）与机器资源看门狗 `scripts/machine-guard.sh`（重活一律经它或 `make`） |
| `prototype/` | HTML 原型；见 [prototype/README.md](prototype/README.md) |
| `docs/` | [现行规格索引](docs/README.md)、[唯一工作清单](docs/待办交接-Codex-2026-09-22.md)和 `acceptance/` 验收证据；旧方案只在 Git 历史中追溯 |
| `AGENTS.md`、`.project-memory/` | 给任何模型窗口的项目约定与跨窗口记忆 |

现行事实以源码、验收记录和 `.project-memory/PROJECT.md` 的日期与基线核对。

## 构建与验证

Swift 6、部署目标 iOS 26.0（app 与各 SPM 包同步，2026-09-21 从 18.0 抬上来；iOS 27 也在支持范围内，26 以下不再维护），真机验证目标是 iOS 26，模拟器只维护 iPhone 16 Pro 与 iPhone 17 Pro Max 两台。打开 `Kanpan/Kanpan.xcodeproj`（或根目录 `Kanpan.xcworkspace`）选 `Kanpan` scheme。

```sh
make core-test network-test data-test presentation-test   # 各 SPM 包 swift test（经 machine-guard 排队）
make app-logic-test                                        # app 侧逻辑单测 + 交易所隔离守卫
make strict                                                # 警告即错误的构建
make sync-contract                                         # 改了同步字段 / 画线种类 / 指标后重生契约并跑后端测试
make web-test web-build                                    # 网页版
```

重活（xcodebuild、swift test、cargo）一律经 `make` 目标或 `scripts/machine-guard.sh run`，不要在会话里裸跑，机器资源纪律见 `AGENTS.md`。验证约定：当前任务全部用模拟器，受影响 UI 用例带超时执行，截图进入阶段报告；完整两机型矩阵在交接书 P4 执行。真机安装、账号登录和密钥配置属于第 3 节外部条件，不做、不等。服务端功能改动须备份、部署并只读验证，流程见 `.project-memory/PROJECT.md`（新加坡机上没装 cargo，二进制在 Mac 上 `cargo zigbuild` 交叉编译后拷过去）。

App 端无第三方依赖；网关是 Python + aiohttp，个人后端是 Rust，网页是 Vite + TypeScript。自选、分组、画线、提醒、设置持久化；K 线只有有界的内存缓存与启动快照。仓库不包含 VPS 登录配置、私钥、密码或令牌——服务端密钥只在线上 `/etc/kanpan-api/` 里，运维文档里只写主机名、端口与路径。
