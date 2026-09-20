# Hkline（看盘 / Kanpan）跨窗口项目记忆

更新：2026-09-21（第 6 节是最新一轮；1–5 节是 09-18/19/20 的快照）。给任何新开的模型窗口恢复上下文用。用户当前指示优先；下面是整理时的快照，接手前用 `git log`、`git status` 和源码核对。

## 1. 身份与分工

- 产品 Hkline（桌面显示名即 Hkline，2026-09-18 定；旧名已停用，活文档里不要再写），工程名 Kanpan。仓库 `/Users/mdd/zhk/kanpan`，远程 `https://github.com/Graham-lo/kanpan`，分支 `main`，2026-09-18 HEAD `3b9fb44`。
- Swift 6、最低系统 iOS 18.0（2026-09-18 从 17.0 抬上来，app 与各 SPM 包同步）、真机验证 iOS 26；SwiftUI + UIKit/CoreGraphics 自绘图表；零第三方依赖；不做交易。
- 代码由 Claude 窗口实现，视觉 / 交互原型定稿后可派 Opus 5（high）子代理写、主窗口验收、装真机、push。Codex 已不参与；`HISTORY-2026-09-15-codex.md` 与根目录 `KANPAN-HANDOFF-2026-09-14.md` 是历史。
- 常常有第二个窗口在同一工作树改交互逻辑。只动自己范围内的文件，不提交别人的改动。

## 2. 当前界面（2026-09-18）

- 皮肤：青苔·冷（默认）/ 陶土·暖 / 经典（2026-09-17 用户点名加的：青苔的文字 / 强调色原样、底换成 AICoin 白）。**经典的白是纯白 `#FFFFFF`，不是 `#F7F9FF`**——后者是安卓包的 `sh_base_bg_color`，K 线页不用它，写成那支蓝白会让纯白画布在页面上显成一块更亮的补丁；真机实测 AICoin 行情页从标题到副图全是 `#FFFFFF`，自选页那一层用中性灰 `#F7F8FA`，深色 `#0D111C` / `#090C14`。**分割线同理别拿错令牌**：图内结构线用 `ui_kline_divider_color` = `#F2F4F7`（夜 `#191C21`，`Palette.dayCanvas.axis` / `nightCanvas.axis`），周期条上下用 `ui_kline_indicator_bar_divider_color` = `#EAEAEA`（夜 `#20232E`，`classicSeed.line`）；原先拿的 `sh_base_divider_dim_fill_color` = `#DEE1E5` 是通用列表分割线，离纯白的亮度差是 `#F2F4F7` 的七倍，整屏 8 条把纯白页面切成了格子，用户读成「更刺眼」。**K 线色只有 AICoin 一套、以后不再另起**（2026-09-17 用户定）：浅色三套皮肤的涨跌色、MA 线色 `palette` 和副图线色 `sub` 都是 AICoin iPhone 端实测值（`Palette.aicoinDayUp/Down/MA`、`aicoinSlots`：蜡烛 `#36B257` / `#E64552`，副图槽位序 `#2FD2B2 #FFB400 #E849B9 #1478C8 …`）；深色 AICoin 没在真机量过，经典深色用安卓包常量，青苔 / 陶土深色暂留自己那组，各有浅深两版，`ThemeSkin` + `ThemeChoice`；种子色在 `KanpanCore/Sources/KanpanCore/Style/Palette.swift`。
- 底栏是常驻标签栏「画线 · 图表 · 自选 · 板块分类 · 设置」五格等宽（`Kanpan/Kanpan/Main/TabBar.swift`，`BottomBar.swift` 已废）。每格各是一整页，切到哪一页它都还在；「画线」那一格是动作不是去处（点它把当前这张图横过来画）。复盘挪进行情页顶栏那颗带角标的按钮，指标并进「图表设置」面板，无横屏格、无风格格。**第五格「板块分类」2026-09-18 晚落地**（`Kanpan/Kanpan/Sector/`，口径在 `KanpanCore/Sources/KanpanCore/Sector/`）：加密／美股是那一页顶上的硬切换，不再开第六格。**板块强弱甲版 2026-09-18 晚已推送并装真机（`a4f4132`）**：口径只有中位数（无口径选项），每板块另算广度（跑赢全场等权池的成员占比）与「领涨」成员（跑赢且进全场前 10%），有行情成员不足 3 个的板块只进「全部板块」；同币多计价对去重（USDT > USDC > FDUSD > BUSD > USD1 > TUSD）；球半径分母 = 全场 |涨跌幅| 最大值（下限 0.01，差不到 20% 沿用上次）。**乙版 2026-09-18 深夜也已落地**：手机端 `648b7bd`（`Sector/SectorHistoryFeed.swift` 拉 `/v1/market/sector-history`，`SectorPage` 顶上「今日 / 5 日」两颗 chip，只有服务端给得出 5 日时才出现；5 日 = 100·(最新价 / 5 个自然日前收盘 − 1)，成员按窗口内有收盘的集合算，覆盖率不足 80% 的板块不进 5 日；当前市场没有可上场的 5 日板块时静默回到今日，偏好保留），服务端 `4f660b1` + `5f24167`（`Backend/kanpan-api/src/sector_history.rs`：`daily_close` 表、每日 00:10 UTC 增量采集只补缺昨天收盘的合约，`TRADIFI_PERPETUAL` 已一并采，主节点已部署并只读验证过，公网路由给 757 个品种；备用节点无库不跑，手机端按 `hosts.oiProxies` 顺序逐台试、全失败时静默）。方案见 `docs/板块强弱-实施方案-2026-09-18.md`。页面上不出现任何后台维护字段（更新时间 / 数据截至 / 覆盖率等）。
- **行情页返回与原路回去（2026-09-18 夜，`0376ec2`）**：顶栏最左一颗「返回」（`Main/TopBar.swift`，id `top.back`），只在从自选行、板块品种列表、或在非图表页点「画线」进到图表时出现，点底栏任一格即清掉，回去落回进来那一层（`MainScreen.chartOrigin`；板块页的层级路由 `SectorRoute` 由 `MainScreen` 持有，切页不再丢）。「全部板块」页头是 返回 · 全部板块 · 加密/美股 胶囊（`SectorMarketSwitch` 与球场顶栏共用），无「N 个」，在清单里换市场仍留在清单。气泡尺子按 `SectorLayout.referenceCount = 13` 颗参考球算，不随上场颗数膨胀。同类断头路一并补掉：搜索 → 全量选择器返回时回到搜索页并保留关键词，复盘「退出」回到进来的那条记录或搜索页，自选排序方式与金额档持久化（`favorites.sort` 等）。
- 行情页顶栏：品种徽章 + 品种名 + 复盘（带待办角标）+ 放大镜（搜索）；连接状态点与顶栏自选星 2026-09-18 一起撤掉（状态点是后台字段，星和行上的星重复且贴着品种名易误触）；最新价 22pt medium + 涨跌药丸 11.5pt，下一行成交额 / 振幅；不显示 24h 高低（`Main/TopBar.swift`）。**品种名只是标签，点上去什么都不弹**（2026-09-18 用户点名去掉那个半屏快捷选择框，`FavoritesQuickPicker` 已删除）；换品种两条路：顶栏放大镜进搜索页、底栏「自选」进分类自选页。
- 行情页头部四格：持仓量 / 成交额 / 市值 / 费率，只有这四个，数额统一 K/M/B/T。市值 = 总市值 = 总供应量 × 现价；持仓量与市值都由 VPS 的 `kanpan-api` 提供。**非币合约（美股 / 港韩 A 股 / ETF / 商品 / 指数 / 未上市）的市值口径与数据来源见 `docs/市值口径与数据来源-2026-09-18.md`**，服务端存的是「市值 ÷ 合约价」的乘数而不是股数，认不出的一律留空。
- 品种搜索：先最匹配、同档按 24h 成交额降序（`KanpanSymbols/SymbolQuery.swift`、`SymbolSections.swift`）。
- 自选页「琉璃」版（`Symbols/FavoritesView.swift`，提交 `a2cbb0d`，`fda4e1c` 起去掉玻璃纸改为融合）：浅色光斑底（底部叠同色渐变保可读）、深色素底不画光斑（2026-09-17 用户要求去掉）、行直接长在底上只留发丝线、衬线标题 22pt 与正放的数量印章、涨跌比例条、品种徽章 33pt、价格 15.5pt、涨跌药丸；迷你走势图默认关闭，「…」菜单里 `favorites.sparkline` 可打开（本机 AppStorage）；排序与涨跌幅口径在 `favorites.sort` 弹层里；没有领涨 / 领跌行。
- 品种徽章一品种一记号（`Main/CoinBadge.swift`、`CoinBadgeBrands.swift`），配色随皮肤。
- K 线只有 AICoin 一套造型（`CandleStyle.all == [aicoin]`），主图 MA(10,30,120,256)，副图默认 MACD + RSI；14 档周期，不含 3d；横屏仅画线用，画线时主副图指标不画。
- 图上不浮任何控件（`kanpan-no-floating-controls-over-chart`）：早先那颗可拖动的「记」按钮已经没有了，
  记一笔走行情页顶栏那颗带角标的复盘按钮，工具一律放在图外的周期条 / 底栏 / 横屏工具栏上。

## 3. 行情、账号、复盘（技术结论，沿用 09-15/16 的验证）

- 线路：设置里「行情线路」两档，**出厂默认直连，没有自动切换**（2026-09-17 定）。直连 = 只走币安自己的域名（REST + WS），探不通照实说「点此重试」，绝不切 OKX；网关 = 只走两台 VPS 网关（主 `kanpan.107-174-172-10.sslip.io`，备 `kanpan.96-44-162-222.sslip.io:8443`）供 OKX 行情，两台之间竞速、失败的歇 10 秒（听 `Retry-After`）。选择存在 `Prefs.routePolicy`，字段归类 `deviceOnly`（2026-09-19 按第二轮 B7 改：不再随账号同步，新客户端不上传、云端旧值不覆盖本机、迁移保住当前选择；服务端为兼容老客户端仍认这个键，`wireOnlyKeys` 里有说明）；`PrefsStore` 把它镜像到 `MarketRoutePolicyStore`（`UserDefaults` 键 `market.routePolicy`，测试档案下用 `kanpan.tests.*` 套件），`RoutedMarketFeed` 听通知立刻换线（REST 与已连的 WS 一起）。旧的 `market-source.json`、`MarketRecoverySchedule`、直连冷却/对冲都已删除。
- 网络层单独成包 `KanpanNetwork`（2026-09-17）：HTTP / WS 接口、币安 REST / WS 客户端、限流、线路策略与网关竞速都在这里，`KanpanData` 依赖并 `@_exported` 转出，app 与 pbxproj 不用改。改线路逻辑只碰这一包；`make network-test`。`BinanceREST.upstream` 不传 policy 就读用户当前线路，OI / 目录 / 报价簿客户端都跟设置走。网络这块之前做过速度优化，改完必须拿真机实测对比、不许变慢。
- 冷启动 / 切换靠多品种快照、后台加深、自选预热做到不等网络；登录用户的自选表要等账号恢复后再判首屏（09-16 修过「冷启动进行情页」「自选一行行慢慢加载」）。
- 账号：用户名 + 密码，Keychain 会话，设备管理、改密、注销；服务端 `Backend/kanpan-api`（Rust，主 VPS `/opt/kanpan-api`，API 8794，PostgreSQL loopback 55434，RLS 隔离，同机每日备份 30 天）。邮箱注册停掉了。**离机备份（2026-09-19，审查 A-08）**：主 VPS `kanpan-offsite-push.timer` 每天 00:20 CST 把最新 dump + `/etc/kanpan-api/{service,database}.env` rsync 到备用 VPS `trade-vps-old:/var/backups/kanpan-offsite/<UTC 时间戳>/`（sshd 在 **33333** 端口，密钥 `/root/.ssh/kanpan-offsite`，authorized_keys 限 `from=107.174.172.10` 且无 pty/转发，留 30 份）；Mac 上 launchd `com.mdd.kanpan.offsite-pull` 每天 01:00 拉到 `~/kanpan-backups/<时间戳>/`（日志 `pull.log`，留 30 份）。安装步骤与恢复演练见 `Backend/kanpan-api/ops/OFFSITE.md`。
- **每类设备只许一台在线（2026-09-19 用户定，已上线）**：手机 / 平板 / 电脑各一类，同类第二台登录把前一台顶掉，iPhone + iPad + Mac 可同时在线。服务端迁移 `0010_device_kind.sql`（`account_sessions.device_kind` 默认 phone、`revoked_reason`、部分索引），`Device.kind` 可选（缺省 phone，老包不用改），`new_session` 撤同用户同类或同 `device_id` 的活会话并记 `replaced`；被顶的会话之后无论 refresh 还是带 access 的任何请求都回 `401 {"error":{"code":"session_replaced","deviceKind":"phone"}}`（先过设备绑定再说这句），refresh 改口类别回 `400 invalid_device`，`/v1/auth/devices` 每条带 `kind`。客户端 `DeviceKind.current` 在壳层判（`isiOSAppOnMac`/`.mac` → desktop，`.pad` → tablet，其余 phone；旧存档没 kind 按 phone，不按机型重推），`AccountError.sessionReplaced` 走独立路径：清 refresh 令牌、身份留着（`SavedAccount.replacedBy`）、进入需重登状态，失效横幅与登录页错误位显示「这个账号在另一台手机/平板/电脑上登录了」，本地资料照常；设备列表副标题「手机 · 本机」。测试：`tests/auth_security.rs` 4 条、`KanpanAccount DeviceKindTests` 7 条、`KanpanUITests/AccountSessionReplacedUITests`（模拟器对线上端到端）。
- 账号安全与并发生命周期第三轮（2026-09-19，GPT Pro 报告 `docs/看盘-账号安全与并发生命周期-GPT-Pro-报告-2026-09-19.md`，基线 `be32841`）：本地已改、已推送、后端已部署到主 VPS 并只读验证、Release 真机包已装。服务端：opaque 令牌不变，新增 `POST /v1/auth/session/revoke`（refresh + 设备鉴权、不轮换、幂等 200，客户端退登冷启动路径用它）；`refresh` 按会话 30 次/60 秒限速、request_id 重放不限时（密封响应留 24 小时）；`wrong_password` 与 `authentication_failed` 分开；限速的 `client_ip` 只有 peer 是回环时才信 X-Forwarded-For 最后一段；整站 `TimeoutLayer` 30 秒；`serve` 进程的每条 DB 连接 `SET statement_timeout 20s / lock_timeout 5s / idle_in_transaction_session_timeout 30s`（worker / migrate 不设）；迁移 0009 删掉邮箱挑战与邮件表，`mail.rs` 与 lettre 已删。客户端：`AccountClient` 只在 refresh 401 时抛 `reauthenticationRequired`，`signOut()` 先清内存再后台撤销（三次），`AccountFeature.logout()` 顺序 signOut → 清 `kanpan.scorebook` Keychain → 清状态 → 访客档案；`AccountView` 有「登录已过期」块与重新登录；所有 `KANPAN_TEST_*` 钩子包在 `#if DEBUG`；推送批次按 384 KiB 切、413 减半。并发：`RoutedMarketFeed.activate` / `MarketFeed` / `WSClient` 用代际号丢弃过期发布，`RootTeardown` 在视图 deinit 时收尾，`MarketModel` 弱引用泵 + deinit 停，`QuoteBook.shutdown()`，`ChartView` 的 drawing link 显式拆。新增测试：`Backend tests/auth_security.rs`、`tests/pool_deadlines.rs`、`KanpanAccount SessionLifecycleTests / PushBatchSizeTests`、`KanpanData FeedLifecycleTests`、`KanpanNetwork GatewayRaceCancelTests / WSRunGenerationTests`、`KanpanChart ChartLifecycleTests`、`Kanpan/KanpanTests`（`make main-ios-test`，符号链接到 `Kanpan/Kanpan/Main`）。**A-06 补齐（2026-09-19 晚）**：`RefreshCoordinator`（进程级按 vault 槽登记的 actor，单飞 + 代际，领跑者进 `performRefresh` 先重读 vault 防拿到作废令牌，`invalidate()` 供登录/退登整槽作废）；`AccountClient.Options` 域名白名单（`allowedHosts`/`allowedPorts`，`allowAnyHostForTests` 只在 DEBUG）；`SavedAccount.origin` 记签发主机，来源不符的存档当没有会话；`isSafe(path:)` 循环 percent-decode 后查 `..`/`.`/空段/`://`/`\`/控制字符（Foundation 自己就会把 `%2e%2e` 解成 `..`）。`ClientHardeningTests` 5 条。BT-09（消费者被闸门按住不丢结构性事件）、BT-11（后台 24.9 s 复用连接 / 25.1 s 重连补缺）已按报告原样落到 `KanpanData FeedLifecycleTests`，夹具 `ManualPacer` + `ReplayStep.hold`。
- 性能与本地／云端冲突第二轮（2026-09-19，GPT Pro 报告 `docs/看盘-性能与本地云端冲突-GPT-Pro-报告-2026-09-19.md`，基线 `76e658d`，14 项）：A1 冷缓存元数据 `b42b921`（整表快照落 CacheDirectory，启动先用快照答、冷请求共享一次刷新）；A3 OI 近期缺失 `a69d50f`（未结算日 404 只记 10 分钟，结算后才永久）；A4 单根 K 线增量种子 `1fd6225`（起点 0、极短序列退全量）；B3 空标注文字 `400551e`（客户端总写 `text`、服务端 null 折成 ""、字节上限 4096）+ `c8b7dbd`（只替自己认识的字段说话，陌生键原样带回）；A2 / B1 / B2 / B4 / B5 / B6 `be11ad6`（整档写合并成一个待写槽；删/撤销成批认依赖、409 同轮 rollback→refetch→realign；draws.json 改为存档先落＋启动前向对账；applyPending 准备→落盘→发布三段；ACK 不再抬未发送 patch 的 base；ApplyGate 让合并后补推真的发生）；B8 `290433f`（settings 字段契约由 PrefsFieldPlan 生成、两边 include 对账）+ 本轮补上 `drawingKinds` / `indicatorIDs`（含主副分界）两份词表，Rust `KINDS` / `OVERLAY_INDICATORS` / `SUB_INDICATORS` 改切片并读契约对账。B7 已改（见上「线路」条，`RoutePolicyStaysHomeTests`）。A5 已改：先量后改，`IndicatorEngine.updateTail` 先放开 `values` 再就地改 `states`（字典下标 `_modify`）、枚举负载绑定后 `self = .moved` 放引用，末根更新从每次整列 COW 复制（N=10000 时 1.2 MB、0.058 ms）变成 0 次复制、0.0043 ms 且不随 N 增长，Debug 下同样成立（`PerfBenchmarkTailOwnershipTests`）。A6 已改 `7e16a60`：`ChartRenderer.recalc` 只在 `sameGeometryInputs` 为假时换 `GeometryCache`，十字线移动 100 次 geometry/layout/priceRange/hiddenMask 重建 100 → 0；十字线回调从每次两遍收成一遍；主屏十字线读数下沉到 `CrosshairReadout`（`@Observable`），只有 OHLC 标签和让位修饰器观察它（`CrosshairWorkTests`，`ChartWorkCounter` 仅 DEBUG）。服务端三项随第三轮一起部署到主 VPS。
- 交易所协议与品种目录第四轮（2026-09-20，GPT Pro 报告 `docs/看盘-交易所协议与品种目录-GPT-Pro-报告-2026-09-19.md`，基线 `a15980c`，A-01…A-07 / B-01…B-09 全改，报告里的 A-T / B-T 用例按原编号落到各包测试）。**网关↔客户端限流契约**（`Backend/kanpan-gateway/market_rest.py`、`okx_hub.py`、`server.py`，两台 VPS 都已部署并只读验证）：上游 429 / 418 / 403 与 OKX 业务码 50011 / 50013 / 50026 一律回 HTTP 429 + 整数 `Retry-After` + `{"error":"upstream_rate_limited","source":"okx","code":429,"retryAfter":N,"upstreamStatus":"429|418|403|…"}`（缺省 429→10 s、418→120 s、403→60 s）；上游 451 回 `{"error":"upstream_blocked"}` 且网关自己冷却 60 s；忙回 `{"error":"busy"}`；不可用回 503 `market unavailable`；网关健康路径是 `/chart-gateway/health`。新端点 `GET /market/v1/tickers?source=okx` 一次给全市场 24h 行情（467 行，`{"source":"okx","symbol":"","ticker":[…]}`），板块页走网关时靠它一次拿齐；`instruments` 带 `underlyingType: "COIN"`、`underlyingSubType: []`，OKX `state` 映射到 TRADING / PENDING_TRADING / BREAK。**OKX 永续没有计价币成交额**（`volCcy24h` 是币量），所以网关线路的 `quoteVolume` 永远是空串，板块副文案在缺成交额时整句去掉「· 成交额」（`sectorVolumeClause`），数值格显示「—」，头部保持 `--`；不要拿币量冒充成交额。**客户端网络层**（`KanpanNetwork`）：`BinanceError` 带 `retryAfter` / `reason`（http / rateLimited / ipBanned / blocked / geoBlocked）/ `proxied`，`stopsRetrying` 含 418 封禁与 451；`RateLimiter` 记 `bannedUntil`、`X-MBX-USED-WEIGHT-1M` 只升不降、`openInterestHist` 单独配额 1000/5 min、`apply(rules:)` 按交易所公布上限打 87.5% 折；`Backoff` ±20% 抖动；`MarketSource.gatewayLimited` 按主机记冷却并保留上游类别；`RoutedMarketFeed.skippable` 不跳限流 / 地域封禁 / 408。WS 三层看门狗：10 s 探活、30 s 传输静默、15 s 数据缺口（探活缺口 7.5 s）。**品种目录与状态**（`KanpanData` / `KanpanCore`）：`SymbolStatus` 四值 tradable / pending / halted / delisted；目录里没有的品种是 unknown（灰占位，不删自选），没加载完不算灰；`QuoteSnapshot` 的 NaN 落盘成 null；`SectorAggregate.volumeSum` 是可选值，缺就缺。`SectorFeed.retry()` 先等线路冷却清零再重启，首屏加载期间不闪空态（`attempted` + `showsEmptyState`）；板块页窗口 chip 由 `SectorWindowChoice` 统一取名；复盘各处的价格/时间文案统一走 `KanpanCore.ReviewLabels`（带价格精度与时区）。**Rust `kanpan-api`**（主 VPS 已部署，备份 `backup-20260920-round4`）：新 `binance_gate.rs` 统一上游限流闸门（418 / 429 听 Retry-After、451 冷却），`market_meta.rs` / `sector_history.rs` / `oi_archive.rs` / `review_market.rs` 都从它过；`ops/backup.sh`、`OFFSITE.md` 同步更新。新测试壳 `Kanpan/Sector/`（`make sector-test`，符号链接到 `Kanpan/Kanpan/Sector`）；`make test` 现在包含 `main-ios-test`。UI 验收用例 `KanpanUITests/SectorRouteUITests`（网关沙盒 + 币安 REST 断开，断言板块页真的从 OKX 一次拿到全市场行情）。网关 92 条（VPS Python 3.11）、Rust 105 条、网络 88、数据 175、核心 288、品种 113、板块 29。
- 收尾轮第五轮（2026-09-20，GPT Pro 报告 `docs/看盘-收尾轮-图表交互画线-复盘-界面与合规-GPT-Pro-报告-2026-09-20.md`，基线 `8733e3f`，A-01…A-09 / B-01…B-08 / C-01…C-08 / D-01 与 A.5 / B.5 / C.10 / D.2 用例全改；报告里 GPT Pro 做不到的测试实跑、迁移实跑、模拟器复现都补齐了）。**画线 A 节**：捏合结束不再当成拖拽（`cameFromPinch`）、`settleGeometry` 用 defer 保证落地、拖画线时轴随手指实时算（`applyDrag(to:axes:)`）、放大镜松手即收、切周期用 `switchInterval(spacing:anchorRight:)` 保住右锚；`DrawGeometry` 标签排布（`placeDrawingLabels`）与命中把手优先，`hitHandlePt=9.5 / selectedHandlePt=22`；`DrawArchive.bucketChanged` 只在桶真变时重载。**复盘 B 节**服务端（主 VPS 已部署，备份 `backup-20260920-round5`，迁移 0011 `review_searches_due` CONCURRENTLY、0012 删 `sync_objects_prefix`、0013 回填 `device_kind`；`ops/install.py` 迁移前查长事务 / vector 扩展 / 重复行）：零观察不判错（`Verdict`）、按域错误码、战绩改「已确认锚定 episode 的相对规则」分组（`comparableGroups` / `comparableProof` / `comparableGrouping`）、`Payload/Params/Route` 提取器回 JSON 错误、搜索 `hnsw.iterative_scan=strict_order` + 内层 ORDER BY distance LIMIT 300；`ops/test.py` 跑 `--workspace` 并断言 BYPASSRLS。客户端：`ReviewSyncVerdict` 三分（transient / conflict / rejected，永久冲突隔离不堵队列）、列表按 id 合并不丢本地新记录、回放按品种自己的小数位与 tickSize、回放推进保住缩放（`ReviewReplayViewport.next`）、`ReviewStore` 按 usedAt 淘汰、战绩用服务端相对口径分组；`ReviewContractReconciliationTests` 直接读 `native_review.rs` / `interval.rs` 对账。**界面与合规 C 节**：板块空快照不退栈（`SectorDrillDecision`）；app 目录里 Release 可达的测试后门清零并由 `ReleaseHookScanTests` 机械守着（含 ChartView / DrawStore / ReviewRangeOverlay 三处）、`ReleaseTestRosterTests` 守 Release 测试名册；`PrivacyInfo` 补 DeviceID；iPad 用例不许假绿；Makefile `test` 并入 account / review，另有 `test-release` 家族（`ENABLE_TESTABILITY=YES`）；账号 presenter 唯一（`AccountPresenter(account: asPage ? nil : account)`）；指标参数边打字边保存按 `clamp` 落值；自选切页回来按品种代号锚点滚回（残差约一行半，`.scrollPosition(id:)` 在 List 上实测无效已写进注释）；顺手修了 `SymbolPickerModel.setCatalog` 目录晚到时补分类。已知未收的观察（画线）：单锚点工具一次点击可能生成两条；竖屏点中已有画线会被拽进横屏工作台。Rust 175 条、Symbols 122、Sector 35、Account 60（Debug/Release）、main-ios-release 18、模拟器 UI 用例 15 条全绿；`FavoritesGroupSyncUITests` 本来就红（真后端双设备同步等不到）。
- 部署后端的两条教训（2026-09-19）：`ops/install.py` 只跑迁移、**不会重启已在跑的服务**，装完必须 `systemctl restart kanpan-api kanpan-worker` 再看 `ExecMainStartTimestamp`；sqlx 的 `after_connect` 里一条 `sqlx::query` 只能放一条语句（多条 SET 会报 `cannot insert multiple commands into a prepared statement` 把整个服务打死），凡是改连接池的都要在本机真的 `serve` 起来 curl 过 `/health` 再部署。部署前的二进制备份在 `/opt/kanpan-api/backup-<日期>-<时分秒>/kanpan-api.bin`，回滚就是拷回去重启。
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

## 6. 2026-09-20/21 提醒与体验细节轮

方案 `docs/提醒与体验细节-实施方案-2026-09-20.md`（含第 10 节从 GPT 功能规划里采纳的几项）。
多个 Opus 子代理并行实现、收尾窗口统一验收提交。**状态：本地已改、已推送；服务端已部署到主 VPS
并只读验证；真机包这一轮没打（用户不在机器旁）。**

### 提醒（Alerts）是一个独立模块

- **纯逻辑** `KanpanCore/Sources/KanpanCore/Alerts/`：`Alert` 模型、`AlertGeometry`
  （把一条画线摊平成若干条价格折线）、`AlertEvaluator`（触碰判定）。单测在 `core-test`。
- **客户端模块** `Kanpan/Kanpan/Alerts/`：`AlertStore` / `AlertArchive`（存档与对账）、
  `AlertWatcher`（前台用现有行情流本地评估）、`AlertPrompt`（画完一条线之后在**图外**那一行弹的
  小确认卡，六秒不理等于「只画线」；它在场时图区就矮一整行，所以按 `mainH` 的比例点画布的
  UI 用例要先 `dismissAlertPrompt()` 再量高度）、`AlertListPage`（设置面板里「提醒」那一行进）、
  `AlertNotifications`、`PushRegistration`、`ReviewDueNotifications`（复盘待办到点，纯本地通知）。
  测试壳 `Kanpan/Alerts/`（符号链接，`make alerts-test`）。
- **图表只暴露两样**：`ChartHost.onDrawingCommitted(Drawing, symbol)` 和
  `alertedDrawingIDs`（线右端画一枚小铃铛）。提醒的规矩一个字都不进 `KanpanChart`。
- **服务端** `Backend/kanpan-api/src/alerts.rs`（几何 + 物化表 + 评估器 + `POST /v1/devices/push-token`）
  与 `src/apns.rs`（APNs HTTP/2 token 认证），迁移 `0014_alerts.sql`。评估器跑在 `kanpan-worker`：
  订阅币安 1m K 线，触发时**在同一个事务里**把物化表置 `fired` 并以服务端身份往该用户的同步日志
  写一条 `alerts` op，客户端下次拉取自然收到，然后才推送。服务端只认
  `[{points:[{t,p}],extendLeft,extendRight}]` 这一种形状——**加一把新画线工具不用动服务端**。
- **APNs 没有密钥也要能跑**：`KANPAN_APNS_KEY_PATH` / `KANPAN_APNS_KEY_ID` / `KANPAN_APNS_TEAM_ID` /
  `KANPAN_APNS_TOPIC` / `KANPAN_APNS_ENV` 全走 `/etc/kanpan-api/service.env`；**任一缺席时
  `Apns::from_env()` 只写一行 info 并返回 `None`**——服务照常起、评估照常跑、`fired` 照常写回同步，
  少的只是最后那一下横幅。线上现在就是这个样子（没有开发者会员，工程里也没有推送 capability，
  `didRegisterForRemoteNotifications` 永远不会响，`OrientationBridge` 里那两条留着是为了开通那天不用改码）。

### 同步集合与深链

- **同步集合现在是六个**：`settings` / `drawingPreferences` / `drawings` / `favorites` / `groups` /
  **`alerts`**（`Backend/kanpan-api/src/sync.rs` 的 `COLLECTIONS`，值规则在 `sync_validation.rs`）。
  客户端那一侧是 `PersonalSyncCodec`。加字段仍走 `AGENTS.md` 里「加 / 删一个同步字段」那条路。
  `Prefs.favoriteSorts` 这一轮多了 `alert`（自选页排序「离提醒线最近」），服务端白名单已同步。
- **深链只有一处解析**：`Kanpan/Kanpan/Main/DeepLink.swift`，scheme `hkline://`（登记在
  `Kanpan/Config/Info.plist` 的 `CFBundleURLTypes`），形态 `symbol/<SYM>?interval=`、
  `drawing/<SYM>/<id>`、`alerts`、`review/<id>`、`search`、`share/<id>`，以及等价的
  `https://kanpan.107-174-172-10.sslip.io/s/<id>`。桌面快捷入口、通知点击、共享链接全从这一个口进来，
  由 `MainScreen` 一处消费。测试壳 `Kanpan/DeepLink/`（`make deeplink-test`）。
  **UI 用例进不去系统通知中心**，所以测试档案下多认一条启动环境 `KANPAN_TEST_DEEPLINK`
  （配合 `KANPAN_TEST_PROFILE=1`，`#if DEBUG`）把一条链接直接喂给路由。同一套路还有一条
  `KANPAN_TEST_ALERT_FIRED=<代号>`（`AlertStore.testSeed`，`#if DEBUG`）：跑用例的是另一个进程，
  塞不进 app 的沙盒，所以「服务端判到价、同步换下来的那一条已触发提醒」由它在开局种进空存档。

### 界面这一轮定下来的几件

- **行情页头部六格**：仓 / 额 · 市值 / 费率 · 结算 / 振幅（`Main/HeaderStats.swift`）。「结算」是
  费率的下一次结算倒计时（`MarkPriceTick.nextFundingTime`），单位用中文「时 / 分」，不足一分钟写
  「即将结算」，拿不到时刻就一个字不写。头部为此高一行，图表让出那几十 pt——头部的字一个都不缩、不截。
- **周期条最多六档，出厂就放满**（`Prefs.maxQuick = 6`，原来是 10；`Interval.quick =
  5m 30m 1h 4h 1d 1w`，2026-09-21 从五档改成六档）。那条「排不下就横向滚动、右边渐隐」的退路
  删掉了：能滚就意味着有钉住的档位藏在屏幕外。各档**等宽平分**铺满周期区（iPad 上单格封顶 76pt），
  `PrefsCodec.factoryQuicks` 记着历代出厂行，没动过常用行的老档案会继承新的出厂值。
- **周期条读成「一行文字 + 一个高亮」**（`Main/IntervalBar.swift`）。没选中的档是**纯文字**、不带底；
  当前档是一颗**贴着字**的琥珀软胶囊（按字宽量出来，封顶 `单格宽 - 4`，所以既不会拉成整格、也够不着
  隔壁那一档的字）；当前档没被钉住时那颗胶囊改画虚线边。行尾「更多 ˅」「图表」同样是纯文字动作，
  只有网格开着时「更多」才亮一颗胶囊；两者之间隔一条 1×14pt 的细线。点击热区照旧是整格 × 44pt。
- **行尾那颗动作不再占固定槽位**。原来「最新」/「返回刚才」/ 空三种状态垫一颗影子药丸钉成一样宽，
  为的是药丸进出时周期不跳位；出厂放满六档之后那个空槽读起来就是条上凭空少一块。现在**不在场即零宽**，
  在场时淡入，周期区跟着 `.easeOut(0.18)` 重新铺满。于是「周期一个点都不许动」这条只对**十字线开关**
  还成立（那几颗在图外的另一行上），`IntervalSlotUITests` 里「最新 / 返回刚才」改成断言
  **六档一颗不少、互不重叠、都在条里，且那颗动作自己点得着**。
- **价格轴按内容定宽**：轴宽 = 这一屏最宽的那条刻度 + 两侧各 `AICoinBehavior.axisLabelPadding`(4pt)，
  量宽时先把数字一律换成 `0`（等宽数字，所以最新价每跳一下轴都不动，只有真的多一位才走一个字符的台阶）。
  原来是「50pt 起跳、不够按 8pt 一档往上加」。胶囊几何统一走 `ChartRenderer.axisChip`。
- **画线时两根轴钉住**（`ChartRenderer.pinnedPriceRange` + `ChartView.beginAxisFreeze`）：手指按着一个
  目标的那两秒里新 K 线到货、行情走出新高都不许让线跟着跑。**撤销栈搬到 `DrawingController` 上按品种存**
  （`histories`），图被重建（切页、进出横屏工作台）之后撤销仍然可用。
- **连续扫图与「看细节」**（方案 §10.1）：从自选分类 / 板块品种列表进图表时冻结那份名单
  （`Main/ScanList.swift`，纯逻辑在 `Kanpan/Scan/`，`make scan-test`），在**顶栏价格区**左右横滑切上一只 /
  下一只（画布与周期条上不加手势）；十字线选中一根 K 线后，头部十字线动作那一行出现「看细节」，
  进下一档小周期并把视野铺成那一根覆盖的区间，切回大周期时从按品种的视野栈里恢复（`Main/DetailZoom.swift`）。
  十字线那一行现在是「‹ 上一根 / 下一根 ›（2026-09-21 箭头改成左右对称）/ 按此价画线 / 看细节」。
- **搜索与入口**：`SymbolAliases`（中文名 + 拼音全拼 + 首字母，`CFStringTransform` 运行时生成，
  不引第三方）、`ClipboardSymbol`（剪贴板里的 `SOLUSDT` / `$SOL` / 中文名，同一段只提示一次）、
  `HomeShortcuts`（桌面长按图标 = 最近看过的 3 个 + 搜索）、`DefaultFavorites` / `DefaultFavoritesSeeder`
  （第一次装、没账号没自选时种 BTC/ETH/SOL + 当天成交额前 5 的币，种过记本机标记，删了不再回来）。
- **分享图片与复盘截图**：`Main/ChartSnapshotRenderer.swift` 离屏渲染当前图（画线、指标、皮肤底色都带着），
  「图表设置 → 这张图 → 分享图片」走系统分享面板；「记一笔」时自动用同一套截一张附在记录上，
  服务端 `POST/GET /v1/native-review/records/{id}/shot`（迁移 `0015_review_shots.sql`），
  `/v1/capabilities` 的 `screenshots` 2026-09-21 起为 `true`。
- **长按预览卡** `Symbols/SymbolPreviewCard.swift`：自选页与板块品种列表共用，卡只读、动作在旁边的菜单里
  （打开 / **调整顺序** / 移到分类 / 取消自选）。自选页那份多一项「调整顺序」是因为长按只有一个：
  这张卡挂上 `contextMenu` 之后，`List` 自带的「普通状态长按整行直接拖动排序」起不来了
  （同一个手势两件事），排序没有丢——它退到长按弹出来的第一屏上，点一下进批量编辑，
  那儿的长按仍旧是拖动。用例 `ChartFoundationUITests.testFavoritesLongPressPreviewThenReorder`
  （原 `testFavoritesDirectRowReorder`）走的就是这条新路。
- 其余体验打磨：自选删除给「撤销」、手指按在表上时冻结排序（只冻顺序，价格照刷）、回到自选页滚回原来那一行、
  行尾按钮 44pt 命中区、「返回刚才」只活一分钟、**四处纯成功提示删掉**（「密码已修改」「账号已注销」
  「已登录」「已清缓存」——只报成功、没有下一步可做的提示对用户没有用；带「撤销」的保留）。

### 部署这一轮踩到的坑

- **rsync 到 VPS 之后必须先 `touch src/*.rs` 再 `cargo build --release`。** 否则 rsync 保留下来的
  mtime 早于机器上那份旧二进制，cargo 认为没有变化、**直接跳过编译**，`systemctl restart` 装回去的
  还是旧包——看起来一切正常，新端点却 404。这一条和 09-19 那两条（`ops/install.py` 不重启服务、
  `after_connect` 里一条 query 只能放一条语句）是同一类账。
- 本轮部署前的二进制备份在主 VPS `/opt/kanpan-api/backup-20260921-0031/`，回滚就是拷回去重启。

### 临时验收材料（不入库）

各子代理这一轮的模拟器截图分别在 `/tmp/kanpan-p1`、`p2`、`p3`、`p4`、`s`、`b`、`a`、`c`，
只是过程材料，重启 Mac 就没了，不要当作长期证据引用。
