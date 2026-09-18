# Hkline（看盘 / Kanpan）跨窗口项目记忆

更新：2026-09-18。给任何新开的模型窗口恢复上下文用。用户当前指示优先；下面是整理时的快照，接手前用 `git log`、`git status` 和源码核对。

## 1. 身份与分工

- 产品 Hkline（桌面显示名即 Hkline，2026-09-18 定；旧名已停用，活文档里不要再写），工程名 Kanpan。仓库 `/Users/mdd/zhk/kanpan`，远程 `https://github.com/Graham-lo/kanpan`，分支 `main`，2026-09-18 HEAD `3b9fb44`。
- Swift 6、最低系统 iOS 18.0（2026-09-18 从 17.0 抬上来，app 与各 SPM 包同步）、真机验证 iOS 26；SwiftUI + UIKit/CoreGraphics 自绘图表；零第三方依赖；不做交易。
- 代码由 Claude 窗口实现，视觉 / 交互原型定稿后可派 Opus 5（high）子代理写、主窗口验收、装真机、push。Codex 已不参与；`HISTORY-2026-09-15-codex.md` 与根目录 `KANPAN-HANDOFF-2026-09-14.md` 是历史。
- 常常有第二个窗口在同一工作树改交互逻辑。只动自己范围内的文件，不提交别人的改动。

## 2. 当前界面（2026-09-18）

- 皮肤：青苔·冷（默认）/ 陶土·暖 / 经典（2026-09-17 用户点名加的：青苔的文字 / 强调色原样、底换成 AICoin 白）。**经典的白是纯白 `#FFFFFF`，不是 `#F7F9FF`**——后者是安卓包的 `sh_base_bg_color`，K 线页不用它，写成那支蓝白会让纯白画布在页面上显成一块更亮的补丁；真机实测 AICoin 行情页从标题到副图全是 `#FFFFFF`，自选页那一层用中性灰 `#F7F8FA`，深色 `#0D111C` / `#090C14`。**分割线同理别拿错令牌**：图内结构线用 `ui_kline_divider_color` = `#F2F4F7`（夜 `#191C21`，`Palette.dayCanvas.axis` / `nightCanvas.axis`），周期条上下用 `ui_kline_indicator_bar_divider_color` = `#EAEAEA`（夜 `#20232E`，`classicSeed.line`）；原先拿的 `sh_base_divider_dim_fill_color` = `#DEE1E5` 是通用列表分割线，离纯白的亮度差是 `#F2F4F7` 的七倍，整屏 8 条把纯白页面切成了格子，用户读成「更刺眼」。**K 线色只有 AICoin 一套、以后不再另起**（2026-09-17 用户定）：浅色三套皮肤的涨跌色、MA 线色 `palette` 和副图线色 `sub` 都是 AICoin iPhone 端实测值（`Palette.aicoinDayUp/Down/MA`、`aicoinSlots`：蜡烛 `#36B257` / `#E64552`，副图槽位序 `#2FD2B2 #FFB400 #E849B9 #1478C8 …`）；深色 AICoin 没在真机量过，经典深色用安卓包常量，青苔 / 陶土深色暂留自己那组，各有浅深两版，`ThemeSkin` + `ThemeChoice`；种子色在 `KanpanCore/Sources/KanpanCore/Style/Palette.swift`。
- 底栏是常驻标签栏「画线 · 图表 · 自选 · 板块分类 · 设置」五格等宽（`Kanpan/Kanpan/Main/TabBar.swift`，`BottomBar.swift` 已废）。每格各是一整页，切到哪一页它都还在；「画线」那一格是动作不是去处（点它把当前这张图横过来画）。复盘挪进行情页顶栏那颗带角标的按钮，指标并进「图表设置」面板，无横屏格、无风格格。**第五格「板块分类」2026-09-18 晚落地**（`Kanpan/Kanpan/Sector/`，口径在 `KanpanCore/Sources/KanpanCore/Sector/`）：加密／美股是那一页顶上的硬切换，不再开第六格。
- 行情页顶栏：品种徽章 + 品种名 + 复盘（带待办角标）+ 放大镜（搜索）；连接状态点与顶栏自选星 2026-09-18 一起撤掉（状态点是后台字段，星和行上的星重复且贴着品种名易误触）；最新价 22pt medium + 涨跌药丸 11.5pt，下一行成交额 / 振幅；不显示 24h 高低（`Main/TopBar.swift`）。**品种名只是标签，点上去什么都不弹**（2026-09-18 用户点名去掉那个半屏快捷选择框，`FavoritesQuickPicker` 已删除）；换品种两条路：顶栏放大镜进搜索页、底栏「自选」进分类自选页。
- 行情页头部四格：持仓量 / 成交额 / 市值 / 费率，只有这四个，数额统一 K/M/B/T。市值 = 总市值 = 总供应量 × 现价；持仓量与市值都由 VPS 的 `kanpan-api` 提供。**非币合约（美股 / 港韩 A 股 / ETF / 商品 / 指数 / 未上市）的市值口径与数据来源见 `docs/市值口径与数据来源-2026-09-18.md`**，服务端存的是「市值 ÷ 合约价」的乘数而不是股数，认不出的一律留空。
- 品种搜索：先最匹配、同档按 24h 成交额降序（`KanpanSymbols/SymbolQuery.swift`、`SymbolSections.swift`）。
- 自选页「琉璃」版（`Symbols/FavoritesView.swift`，提交 `a2cbb0d`，`fda4e1c` 起去掉玻璃纸改为融合）：浅色光斑底（底部叠同色渐变保可读）、深色素底不画光斑（2026-09-17 用户要求去掉）、行直接长在底上只留发丝线、衬线标题 22pt 与正放的数量印章、涨跌比例条、品种徽章 33pt、价格 15.5pt、涨跌药丸；迷你走势图默认关闭，「…」菜单里 `favorites.sparkline` 可打开（本机 AppStorage）；排序与涨跌幅口径在 `favorites.sort` 弹层里；没有领涨 / 领跌行。
- 品种徽章一品种一记号（`Main/CoinBadge.swift`、`CoinBadgeBrands.swift`），配色随皮肤。
- K 线只有 AICoin 一套造型（`CandleStyle.all == [aicoin]`），主图 MA(10,30,120,256)，副图默认 MACD + RSI；14 档周期，不含 3d；横屏仅画线用，画线时主副图指标不画。
- 「记」按钮可拖动、限主图内、记住位置。

## 3. 行情、账号、复盘（技术结论，沿用 09-15/16 的验证）

- 线路：设置里「行情线路」两档，**出厂默认直连，没有自动切换**（2026-09-17 定）。直连 = 只走币安自己的域名（REST + WS），探不通照实说「点此重试」，绝不切 OKX；网关 = 只走两台 VPS 网关（主 `kanpan.107-174-172-10.sslip.io`，备 `kanpan.96-44-162-222.sslip.io:8443`）供 OKX 行情，两台之间竞速、失败的歇 10 秒（听 `Retry-After`）。选择存在 `Prefs.routePolicy`：登录了随账号同步（`PersonalSyncCodec.fields`），没登录记在本机访客档案；`PrefsStore` 把它镜像到 `MarketRoutePolicyStore`（`UserDefaults` 键 `market.routePolicy`，测试档案下用 `kanpan.tests.*` 套件），`RoutedMarketFeed` 听通知立刻换线（REST 与已连的 WS 一起）。旧的 `market-source.json`、`MarketRecoverySchedule`、直连冷却/对冲都已删除。
- 网络层单独成包 `KanpanNetwork`（2026-09-17）：HTTP / WS 接口、币安 REST / WS 客户端、限流、线路策略与网关竞速都在这里，`KanpanData` 依赖并 `@_exported` 转出，app 与 pbxproj 不用改。改线路逻辑只碰这一包；`make network-test`。`BinanceREST.upstream` 不传 policy 就读用户当前线路，OI / 目录 / 报价簿客户端都跟设置走。网络这块之前做过速度优化，改完必须拿真机实测对比、不许变慢。
- 冷启动 / 切换靠多品种快照、后台加深、自选预热做到不等网络；登录用户的自选表要等账号恢复后再判首屏（09-16 修过「冷启动进行情页」「自选一行行慢慢加载」）。
- 账号：用户名 + 密码，Keychain 会话，设备管理、改密、注销；服务端 `Backend/kanpan-api`（Rust，主 VPS `/opt/kanpan-api`，API 8794，PostgreSQL loopback 55434，RLS 隔离，同机每日备份 30 天）。邮箱注册停掉了。
- 复盘：`KanpanReview` 接现有图表，记一笔 / 列表 / 待办 / 统计 / 详情 / 逐根重温 / 私有 OHLC 找相似；记录固定行情源；公开相似索引只是首批种子。
- 网关：`Backend/kanpan-gateway`，`/opt/kanpan-gateway`，REST 8792、共享 WS 8793，服务 `kanpan-gateway`、`kanpan-stream-hub`。线上服务，只读探测，不改 Caddyfile。 2026-09-17 性能轮已按「备份 → 先备节点 → 只读验证 → 主节点」部署过一次（备份在 `/opt/kanpan-gateway/backup-20260917-*`，API 在 `/opt/kanpan-api/backup-20260917`）；Caddy `admin off`，改完要 `systemctl restart caddy`。Release 基准用各包 `PerfBenchmarkTests.swift`（`swift test -c release --filter PerfBenchmark`），验收报告见桌面 `看盘-性能优化-验收-2026-09-17.md`。
- 原型静态托管：主 VPS `/var/www/kanpan/ui/`（`ssh orderflow-vps`，`install -o caddy -g caddy -m 644`），浏览器地址 `https://kanpan.107-174-172-10.sslip.io/ui/`。

## 4. 用户稳定偏好

- 极致好看优先，不要工程风 / 后台风；元素尺寸克制，大字号与粗字重会被判「廉价」；装饰元素正放不倾斜；整屏是一块连续材料，不要硬拼接。
- 配色不自创色板：青苔 / 陶土两套是定版，第三套「经典」只是青苔换 AICoin 白底，是用户自己点名要的；K 线 / 涨跌 / 指标线色浅色下全皮肤统一用 AICoin 那套，不再另起；图表底座不是设计对象。
- 合并入口不能丢功能；发现残留问题直接修不请示；面板选完即收起。
- 界面不出现「行情实时」之类状态字段，不堆解释文案，能自动做的不弹窗。
- 验证只跑受影响的一两条真机 UI 用例并开超时；视觉改动真机看一眼即可。真机 iPhone 16 Pro 常连在 Mac 上。
- 手机可能经 Mac 的 Surge 网关上网，不改 Mac 网络配置。

## 5. 未完成范围（沿用 `docs/账号复盘-实施进度.md`）

- 复盘：框选贴边自动滚动、精确时间编辑、痕迹点进详情、保存案例管理 UI、规则版本查看、截图补录、旧资料归属导入。
- OKX 持仓量副图未接；精确 trade_touch 证据不足时保持待核验。
- 跨设备并发与同步冲突、全部复盘手机交互的端到端真机回归。
- 机型与系统兼容已做完一轮（2026-09-18，见 `docs/acceptance/兼容-iPhone15+-iPad-iOS18-2026-09-18.md`）：最低系统提到 iOS 18.0（各 SPM 包同步），iPad 按「不破」口径把满屏单列页封了 560pt 的内容列，全量 13 台 × 49 条矩阵已在 iOS 26.5 上跑完（基线 `9c3a79b`，日志在 `docs/acceptance/M8/ui-test/`），翻出来的十一条红全部从根因修掉——其中 iPad 侧四条：双指缩放的 pt 死区、指标编辑纸被键盘顶飞吃掉第一下、横屏出口在 iPad 上问错了问题、搜索结果那颗星的感应区在 iPad Pro 上被整行压过去（点星变成开图表）。按用户口径不下载 iOS 18 运行时、真机不再跑。
- 2026-09-17 交互整套重排原型（`docs/交互审计与新原型方案-2026-09-17.md`）正在分页落地，另一窗口在改。
