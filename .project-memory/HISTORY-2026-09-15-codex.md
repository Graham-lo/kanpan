# Hntcoin（看盘 / Kanpan）历史记忆：2026-09-15 至 09-16（原 CODEX.md）

> **历史文件。** 这是 2026-09-15 为 Codex 窗口整理、并在 09-16 追加过的快照。Codex 已退出本项目；其中「图表风格入口为经典/圆角/空心/轮廓」「Opus 原型由 Codex 落地」等说法已失效。现行约定见 `PROJECT.md`，行情线路与账号的技术结论仍可参考。
>
> **产品名现为 Hkline**（2026-09-18 起；深链 scheme 就是 `hkline://`，见 `Kanpan/Kanpan/Main/DeepLink.swift`）。本文通篇保留当时「Hntcoin」的叫法，不逐句改。工程名仍是 Kanpan。

## 1. 项目身份与入口

- 产品正式名称 **Hntcoin**，代码工程仍叫 Kanpan；实际仓库 `/Users/mdd/zhk/kanpan`，远程 `https://github.com/Graham-lo/kanpan`，当前分支 `main`。
- `/Users/mdd/kanpan` 是旧路径，本次核查为空。相关 Codex 任务的 cwd 可能显示 `/Users/mdd/zjh-codex-p3`，不代表看盘代码在那里。
- 原生 SwiftUI 页面 + UIKit/CoreGraphics 自绘图表，Swift 6、工程目标 iOS 17+，用户当前重点是 **iOS 26 真机**。不依赖第三方图表库，不提供交易下单。
- `Kanpan/Kanpan`：App 页面、设置、自选、账号及复盘适配；`KanpanCore`：模型/坐标/指标/画线算法；`KanpanChart`：图表绘制与手势；`KanpanData`：行情与选路；`KanpanAccount`、`KanpanReview`：账号与复盘模块；`Backend/kanpan-gateway`：行情网关；`Backend/kanpan-api`：个人 API/worker。
- 既有 Scorebook 是另一个应用/服务，仅复用冻结的算法与适配器；本项目不要改动或重启它，也不要套用炸金花部署规则。

## 2. 用户稳定偏好

- **现有看盘已较完善，接入账号和复盘即可，不另起一套。** 复盘保存市场、品种、周期、时间范围、判断/规则/结果等定位信息，打开时沿用当前图表按需取行情。
- 正常看盘的速度和手感优先：能正常用的线路直接用；取消旧请求、切品种/周期不应造成全局网络失败或卡顿。不要让自动化测试持续占用用户正在操作的手机。
- 新增与此前半成品一起完成后统一真机测试，重点 iOS 26；其他机型和旧系统兼容后续单独推进。保留失败记录，不将编译/模拟器成功包装成全部真机通过。
- 文案简短，普通界面不展示服务地址、Token、数据库或实现过程。常规设置立即生效；多项编辑的参数/颜色明确取消与保存。
- 个人配置、自选、分组、画线、草稿不能丢；跨账号隔离，跨设备自动同步以云端个人数据为主，手机保留必要轻量副本和可靠待发队列。
- K 线按视野加载，有限内存缓存和必要小型启动快照，不按品种×周期无限累积永久行情库。不要为了省缓存牺牲出图体验。
- AICoin 是手感参考，真实 iOS 行为、Android 源码证据和设计推断分开说明，不声称完整 1:1 复刻已验收。
- 双指缩放时主图框及纵向映射要稳定，避免每帧极值重算导致上下跳。默认副图历史约定为 MACD/RSI、主图 MA；升级不能为了改变默认值覆盖已有个性化设置。
- 周期共14档：1m、3m、5m、15m、30m、1h、2h、4h、6h、12h、1d、1w、1M、1y；不提供3d。周/月/年按日历，不能固定分钟数推算。

## 3. 最新界面决定

> **这一节已整节被推翻（2026-09-22 标注），只当史料看，别照它做。** 下面记的是 2026-09-15/16 的界面。现行是常驻标签栏五格「画线 · 图表 · 自选 · 板块分类 · 设置」（不是「复盘｜指标｜自选｜设置」四格），K 线只保留 AICoin 那一套风格（没有经典/圆角/空心/轮廓四选），也没有可单指拖动的「记」按钮。现状见 `PROJECT.md` 与 `docs/使用手册-2026-09-21.md`。

- 底栏 **复盘｜指标｜自选｜设置**，已由 `BottomBar.swift` 核对。旧方案的「指标｜自选｜复盘｜设置」已失效。
- 「图表」在周期行，风格并入其中，新选择仅显示经典/圆角/空心/轮廓，旧风格配置保留兼容。
- 随系统自动旋转、尊重旋转锁；不再靠单独横屏按钮。
- **「记」可单指拖动、松手保存、重启恢复位置，活动范围限主图，避开副图和价格轴。** 轻点记一笔；拖按钮不能带着图一起移动。用户已在新手机确认可以拖动。
- 画线/框选模式互斥。未进入框选时覆盖层不能截走正常拖图。面板外首击仅关闭，再次点击恢复图表正常交互。

## 4. 行情：最重要的历史纠正

### 起因与最终决定

本任务最初确认：朋友无币安直连时只有最新 K 线和价格更新。旧网关只转发币安 WS 与历史 OI；首屏历史/翻页仍直连 REST，因此实时通而历史不通。两台美国 VPS 曾实测币安 REST 返回451，但 WS及归档可用；这不等于 VPS 无法取任何历史数据。

该问题已通知任务「完善K线画线功能」并被纳入实现。随后用户在该任务明确授权 **Binance 不可完整使用时整套切换 OKX**，不混源；恢复后自动切回 Binance。用户原话核心是「哪套完整用哪套」。因此早期“只能找 Binance 历史来源”的建议已被新决定覆盖。

### 现行规则与实现状态

- 按完整行情源切换：历史、补页、断线补缺、WS 使用同一交易所。复盘记录固定原市场身份，后续日常线路切换不能改写旧记录的来源。
- 默认正常 Binance 直接加载，不在每次进图前额外串行验证 REST/WS。只在确实不可完整使用时兜底；币安 WS 单独可用不能算图表功能可用。
- 成功切换落盘到 `market-source.json`；重启、切品种、换周期沿用，不重走失败流程。
- OKX 使用期间后台恢复检测首次5分钟，失败延长到最多15分钟；页面切换不重置期限。真实网络恢复可提前一次，60秒内抖动不重复触发。正常恢复须连续两次通过历史 REST 和有效 WS 帧，第二次确认间隔10秒；全程不阻塞当前图表。
- 首次切换提示「检测到当前链路不可用，正在切换智能链路」，历史和WS实际就绪后短暂提示「已切换成功」。不反复展示“历史数据未加载”；两套都不可用才给重试提示。
- 已修过关键回归：切品种/周期取消旧请求产生 `URLError.cancelled (-999)` 被误判网络失败，曾让其他品种也进入失败冷却。取消不能惩罚线路；单次普通超时也不能全局禁用正常直连。
- 源码入口：`KanpanData/Sources/KanpanData/Feed/RoutedMarketFeed.swift`、`MarketRecoverySchedule.swift`、`MarketSource.swift`，及 `Backend/kanpan-gateway`。
- 最新实施记录称两台 VPS 已部署 OKX REST 与共享WS；真实 OKX 300根首屏、1500根历史补页、实时与线路重启恢复已通过；Data90项及模拟器行情流程已通过。**完整新增提示和全部复盘真机回归仍未完成**，不能泛称所有场景都验收了。
- OKX 持仓量副图尚未接入；不应跨交易所拿 OI 或精确触价证据补数。无对应品种的能力边界须核对，不能声称 Binance TradFi 全目录都可由 OKX 替代。

### 2026-09-15 网络与 K 线加载修复（本地工作树）

- `MarketFeed.fillOnce` 现在先请求并发布最新 K 线，再并行等待快照缺口 `startTime=末根` 的回补；缺口失败只保留最新序列并提示重试，不把实时 WS 一起置为离线。ticker 校准失败也只记日志，不使已加载历史失效。
- `MarketRESTTransport` 对直连超时/网关错误进入有限冷却（普通网络错误30秒、403/451 60秒、418/429 15秒），取消请求不污染线路；成功网关会在当前进程优先复用。`BinanceREST` 的 K 线权重按 limit 分档，终态 418/429 也会留下限流罚停。
- 看盘顶栏 QuoteBook 与图表统一使用当前 `MarketSource` 和 `SourceSocketFactory`，避免图表走兜底而自选报价仍直连；WS 控制帧只有发送成功才更新已同步集合，失败会保留差异重试。
- 新增/更新测试覆盖：首屏最新优先与缺口回补、ticker 失败隔离、直连超时冷却/网关复用、K 线实际权重、终态限流罚停。`KanpanData` 本地 `swift test` 于 2026-09-15 22:25 通过 **94 tests / 12 suites**。
- 本地 `xcodebuild build` 和 `build-for-testing` 均成功。iPhone 16 Pro（iOS 26.6.1）在最终代码上重新运行 `testLiveMarketUpdatesWithinSeconds` 通过，12.691s，约 1.2 / 2.2 / 3.2 / 4.1 / 5.2 秒的连续采样值发生变化；结果包 `/tmp/kanpan-device-live-final2-20260915.xcresult`。同机历史拖动/缩放/手动 Y 用例已执行到全部动作并产出附件，但 XCTest 最终因 **signal kill** 失败，不能计为真机通过；冷启动全流程同样仍需单独排查测试进程退出原因。
- 当前只完成本地代码和真机开发签名验证，**未提交、未推送、未重新部署 VPS/网关、未完成 TestFlight 发布**。工作树仍包含原有界面/画线/测试及 DerivedData 变更，接手者不得清理或覆盖无关修改。

## 5. 账号、同步、复盘

- 用户最新拍板 **用户名 + 密码直接注册/登录，邮箱先不搞**。旧邮箱验证码、Proton/Brevo/SMTP 方案已暂停，不再当当前阻塞项。不要将任何历史聊天凭证写入记忆。
- 实施记录：会话与Keychain、设备管理、改密/注销、字段同步、持久待发队列、账号目录隔离已接入；服务端强制 PostgreSQL RLS，运行角色不拥有表且无绕过权限。
- 私人内容保存后即时响应，后台同步；未上传内容不可被可重建缓存淘汰。不要用整份本机 Prefs 上传，把网络配置/视野/回放游标一起带到云端。
- 画线删除须保留墓碑，普通并发修改不能复活；明确撤销产生恢复操作。旧“每品种超过50条裁剪丢弃”不能作为云同步规则沿用；性能限制不能静默删除用户内容。
- 原生复盘已接记一笔、列表/待办/统计、详情、逐根重温、私有OHLC找相似；服务端保存定位和规则，不下载全量K线历史。相似度不是胜率。
- 模块已有实现与部署不代表完整交互完成；见第8节待办。

## 6. 画线与图表已交付范围

- 10工具：趋势线、水平线、射线、水平射线、直线、垂直线、矩形、平行通道、斐波那契回撤、价时测量。
- 分类与收藏、弱磁吸、连续画线、样式/颜色/线宽/虚实/填充、锁定/隐藏/复制/单根删除、管理列表、撤销重做、坐标/回撤比例编辑。
- 单根删线立即执行且能撤销，清空单独确认；未完成对象先撤回锚点。存档兼容与损坏保护，重启恢复对象和偏好。
- 图表与画线共用时间价格坐标；画线不撑大自动Y。已选端点44pt触达，弱磁吸按屏幕距离；拖动只更新预览、抬手落盘。
- MA/EMA 每个输出独立改色，取消不提交、保存同步曲线与图例、重启保留。
- 真机证据见 `docs/acceptance/drawing-v2/DEVICE.md`；其“复盘暂缓”等当时状态已被后续实施覆盖。高级工具如文字、箭头、扩展、多空仓位、波浪等未在10工具交付范围。

## 7. 部署、代码与手机快照

- 主行情节点 `kanpan.107-174-172-10.sslip.io`；备用 `kanpan.96-44-162-222.sslip.io:8443`。保留同机其他业务，尤其备用节点443。
- 行情服务：`/opt/kanpan-gateway`，历史/REST服务8792、共享WS8793；服务名 `kanpan-gateway`、`kanpan-stream-hub`。具体路由以当前 Caddy.routes 为准，旧 README 可能未覆盖后续 OKX。
- 个人后端实施记录：主VPS `/opt/kanpan-api`，API8794、独立 PostgreSQL loopback55434；`kanpan-api`、`kanpan-worker`、`kanpan-backup.timer`。每日数据库备份30天是**同机备份**，不声称已有异地灾备。
- 2026-09-15 19:32本次现场核对：本地HEAD与 `git ls-remote origin refs/heads/main` 均为 **9b19133a722547827ff48c25ad58cd8abcabd879**。此前提交 `b71bd9c` 是画线/账号复盘/持久选路，`22c3927` 是Hntcoin名称图标，`9b19133` 是底栏与可拖动记按钮等。
- **工作树不干净**：还有图表/画线/页面源码、UI测试及大量 DerivedData 变更。不能说当前全部修改已推送；本轮只核对Git，没有提交或清理他人改动。
- 来源任务报告：iPhone16 Pro/iOS26.6.1已有画线颜色等真机验证；新 iPhone17 Pro Max/iOS26.7已安装最新版且用户确认能使用及拖动「记」。旧手机到新手机迁移5个数据文件并回读一致，含23自选/3分组和配置草稿；这是设备文件迁移证据，**不是跨设备云同步完整验收**。不记录设备UDID。
- 当前安装为开发签名版本，原任务说明运行需开发者模式；TestFlight只是后续分发建议，未在本次证据中完成。
- Mac 是手机可能使用的 Surge 网关；用户强调真实流量会从 Mac 路由出去。不要仅凭“手机没开代理App”推断它直连失败。已有实机 Binance HTTP200/198ms记录；测试源、网络出口和日期都要区分。

## 8. 明确待办与验收边界

以下来自 `docs/账号复盘-实施进度.md`，尚未有后续完成证据：

1. 框选贴边自动滚动、精确时间编辑、点痕迹进详情的完整流程。
2. 保存案例管理UI、规则版本和完整修订查看、截图补录、旧个人资料有归属导入。
3. 公开历史相似索引已完成首批导入：主节点 2677 个已发布窗口，OKX USDⓈ-M、10 个主流 USDT 永续、最近 180 天、1h，使用 `candle-geometry-v2`；这是可用种子，不代表全市场、全周期覆盖。查询按行情源隔离，未用 Binance 数据冒充 OKX。
4. OKX OI未接；精确trade_touch证据不足保持待核验，不用普通OHLC或Binance数据冒充。
5. 跨设备并发、同步冲突、全部复盘手机交互最终端到端回归，及新增行情提示完整真机回归。
6. 其余机型和旧版系统兼容按用户顺序后续处理；已安装与可打开不等于完整兼容验收。

## 9. 记忆来源与接手顺序

先看用户当前请求，再读本文件和 `docs/账号复盘-实施进度.md`；修改前核对实际源码、工作树及执行中的任务。新结果应更新本记忆的日期/来源，而不是简单叠加互相矛盾的结论。

- 主实施任务 **完善K线画线功能**：`01a0a345-0f14-7e83-b895-169ecb421b83`，host `local`。需追溯新指示时用 `read_thread`；本次整理时最新已读轮次completed、任务notLoaded，不能仍称它一直运行中。不要因记忆含待办就自动唤醒。
- 本次原始核查与通知任务：`01a0a3e6-fafa-70d0-bbcf-e737f80bf3a7`。
- 状态：`docs/账号复盘-实施进度.md`；后端：`Backend/kanpan-api/README.md`；图表：`docs/acceptance/AICoin-base/foundation/IMPLEMENTATION.md`、`docs/acceptance/护眼配色与数据完整性.md`；画线：`docs/acceptance/drawing-v2/README.md`和`DEVICE.md`。
- `docs/账号同步与复盘-最终落地方案.md`是设计来源，标题“最终”不代表当前状态；其中邮箱注册、旧底栏顺序、尚未部署叙述已过时。未在新记录中确认的设计条款只能当目标。
- `KANPAN-HANDOFF-2026-09-14.md`、早期实施任务书和 `.project-memory/claude/*.md`保留历史，不用它们否定后续已实现工作；旧“VPS不参与App”“没有K线兜底”“复盘暂停”“默认升级清空偏好”等说法需按本文件纠正。Claude旧多代理偏好不构成当前启用代理的指令。

本记忆由当前任务读取实施任务最新用户指示/结果、项目文档、相关源码以及Git核对后归纳；本轮已重跑本地数据测试、App 编译和 iPhone 16 Pro 实时/历史交互用例，未重部署服务器或发布分发包。只保存必要项目上下文，不复制聊天全文或任何秘密。

### 2026-09-15 22:39 接手复核

- 用户要求接手「排查币安历史K线加载失败」并让原任务整理后停止；该任务已核对为 `idle/completed`，未再继续修改。
- 本轮重新验证：`KanpanData` `swift test` 通过 **94 tests / 12 suites**；网关 `test_market_rest.py` 与 `test_server.py` 共 **14 项**通过；`xcodebuild` iOS Simulator Debug 构建成功。
- `KANPAN_LIVE_ROUTING=1 swift test --filter LiveRoutingTests` 通过：OKX 300 根首屏、1500 根前翻、实时推送、来源落盘与重启恢复；主/备用公网 `/market/v1/klines?source=okx` 均 HTTP 200。
- 本轮仍未重新部署 VPS、提交/推送 Git 或做新的真机回归；所有现有工作树改动（含界面/画线等）均保留。

### 2026-09-15 23:21 提交与网关部署

- 提交 `702831b`（`Fix resilient historical market data routing`）已推送至 `origin/main`。
- 主节点 `orderflow-vps` 与备用节点 `trade-vps-old` 均已在同步前备份 `/opt/kanpan-gateway` 相关文件，备份目录分别为 `/var/backups/kanpan-gateway/20260915T152019Z` 与 `/var/backups/kanpan-gateway/20260915T152018Z`。
- 两台 VPS 已同步网关目录并重启 `kanpan-gateway.service`、`kanpan-stream-hub.service`；两台远端各运行网关完整 **26 项测试通过**，服务状态均为 `active`。
- 两台本机回环健康检查，以及公网主/备 HTTPS 健康接口和 `source=okx` BTCUSDT 1m K 线接口均返回正常；未重载 Caddy（路由未改变），未影响同机其他业务。

### 2026-09-15 23:58 自选分类列表 OKX ticker 修复

- 本次用户明确确认修改范围是“自选 → 分类 → 品种列表”，不是改 K 线展示逻辑本身。后端 `OKXHub` 现在接受客户端已有的 `symbol@ticker` 与 `symbol@kline_*` 频道，并分别映射到 OKX public `tickers` 与 business `candle*` 上游，再统一转成客户端现有报文格式；这样自选列表和 K 线继续共用同一来源路由。
- `MarketModel` 初始化时立即读取已保存的 `MarketSource`，让分类目录 REST 与行情源一致；`MainScreen.boot()` 先完成目录/源配置，再展示自选列表，避免冷启动先用默认 Binance 发起一次失败目录请求。
- 新增 `Backend/kanpan-gateway/test_okx_hub.py` 覆盖频道校验、OKX 参数映射、ticker 标准化和脏数据过滤。`KanpanData` 仍为 94 tests / 12 suites 通过，iOS Simulator 构建成功。
- 本地 `okx_hub.py` 语法检查通过；备用节点网关完整 30 项测试通过，主节点核心测试 18 项通过。两台 VPS 的 `kanpan-stream-hub.service` 均为 `active`、`NRestarts=0`，部署文件校验和与本地一致；主/备公网混合订阅已验证同时返回 OKX ticker 与 1m K 线。
- 本次未重新做真机 App 安装/回归，也未发布 TestFlight；只能确认源码已构建、网关已部署，不能表述为手机端完整验收。
- 关联源码已提交为 `af16deaf28ac726b425f8520235a0302c19c0c84`（`Fix OKX favorites ticker routing`）并推送到 `origin/main`。工作树中其余画线、样式、UI 测试和 DerivedData 改动未纳入本提交。

### 2026-09-16 00:16 直连环境与备用选路修复

- 当前本机无代理直连实测 Binance REST `/fapi/v1/time` HTTP 200、Binance WebSocket `fstream.binance.com` 成功收到 ticker/K 线，命令行首帧约 4ms；因此新安装或没有持久化 OKX 偏好的 App 会优先使用 Binance。OKX REST 也正常。
- 两台 VPS 直连 Binance 返回 HTTP 451，而直连 OKX 返回 HTTP 200；主/备网关的 `source=binance` 因此返回 503，`source=okx` 正常。VPS 不能作为 Binance 的有效代理，但可承载 OKX 备用源。
- 修复 `MarketRESTTransport`：网关候选并行请求，返回第一个通过来源/品种/周期校验的结果；品种表和 ticker 网关请求超时上限收紧到 5 秒，历史 K 线保留较长超时；获胜网关短期优先，失败路径进入短暂冷却。
- 修复 `URLSessionSocketFactory`：WebSocket URLSession 请求增加 6 秒建连/升级超时，避免直连黑洞拖住备用选路。
- `KanpanData` `swift test` 通过 **95 tests / 12 suites**，App Simulator build 通过；新增并行网关竞速测试。尚未重新部署这轮 Swift 变化，待提交后按既有流程发布 App 源码，不涉及 VPS Python 文件。
- 本轮客户端改动已提交为 `123c6d54fa89668ab37a77edaf0765543baf6feb`（`Avoid blocking fallback route selection`）并推送到 `origin/main`；尚未安装到真机或发布 TestFlight。

### 2026-09-16 01:08 冷启动行情延迟优化

- 提交 `09f8e4c39e5455b9cdbd91eb2a37f0a7b4c6195f`（`Optimize fallback market startup latency`）已推送到 `origin/main`。客户端直连失败判定上限收紧到3秒；Binance/OKX REST与WS健康探测并行；已收到完整Binance历史失败时直接激活OKX，不重复做一次等待型探测；新选线路离线时立即触发重选，不等待20秒监控周期；OKX首屏网关历史请求上限收紧到8秒。
- 网关首屏 OKX 最新窗口改用 `market/candles?limit=300` 单请求，历史分页仍用 `history-candles`，保持来源、周期、连续性校验不变；OKX共享WS首次订阅的防抖从300ms降到30ms，连续切换仍保留300ms合并。
- 两台行情VPS已部署该提交涉及的网关文件，部署前保留 `/var/backups/kanpan-gateway/20260915T170221Z`；主备 `kanpan-gateway` 与 `kanpan-stream-hub` 均 `active`、`NRestarts=0`，远端文件SHA一致，市场REST单测7项通过。主备公网OKX 300根首屏冷请求约1.44秒，后续约0.7–1.0秒。
- iPhone 16 Pro模拟器冷启动实测：正常Binance清数据 `app.launch` 到图表与live约5.569秒；无源记录且Binance REST故障，切OKX后页面4.525秒、OKX来源5.569秒、WS live 6.615秒、300根条件7.673秒，测试通过。正常Binance第一次测试受模拟器UI会话偶发超时，清理App数据重跑通过；日志中的直连Binance REST约0.53秒、WS随后成功。
- 当前Binance直连实测REST time约0.50秒、300根K线约0.63秒，正常App冷启动约5.57秒；该路径已无额外串行探测或重复首屏请求，剩余主要是App冷启动/图表首帧和交易所WS建连，暂不为追求毫秒数并行请求OKX以免破坏“手机直连Binance优先”。本轮未完成真机/TestFlight回归。

### 2026-09-16 02:45 后台恢复与冷启动：不再清价

- 本轮由 Claude 直接改代码（用户明确说「你直接帮我一次性弄好」，越过了「只给方案 + 由 Codex 写代码」的常规分工）。未提交、未推送、未动 VPS 网关。
- 根因不在 iOS 后台刷新也不在快照，而是 `QuoteBook` 自己把价格抹了：进后台清一次、状态非 live 清一次、重连再清一次，所以回前台必定是空列表，只能等一整轮 WS 重连 + REST 补价。
- 改法：
  - `QuoteBook` 三处清价全部去掉，只有换交易所才清。断线/后台只清 `latestReceived`（跨连接不能延用的顺序状态）与实时指示灯，显示值留着——`FavoritesView` 顶部那颗灯本来就只认 5 秒内的更新，旧值不会被当成实时价。
  - 补价门槛从「有没有值」改成「值够不够新」（`receivedAt` + 20 秒），否则留着旧值会把 REST 补价全挡掉。
  - 新增 `KanpanData/Store/QuoteSnapshot`（`Paths.quotes`，最多 256 条），冷启动第一帧直接铺上次看到的报价。
  - 新增 `RESTClient.tickers24h()`（权重 40，不重试）与 `Endpoints.tickers24h()`：待补行 ≥ 8 时一次换回整屏，失败则 120 秒内退回逐个请求。`MarketRESTTransport` 增加守卫，不带 symbol 的 ticker 一律不转发给网关（网关只代理单品种，转过去的载荷无从校验）。
  - `MarketFeed.backgroundGraceMs` 5 秒 → 25 秒，`enterForeground` 先把内存里的序列重新发一遍再补齐；`QuoteBook` 同样有 25 秒宽限才真拆连接；新增 `BackgroundGrace`（`beginBackgroundTask`，27 秒自解）让这段宽限真的拿到运行时间。
  - 新增 `LaunchPrewarm`：`KanpanApp.init()` 里发一笔 `/fapi/v1/ping`，界面还没起来时就把 TLS 连接握进 `URLSession.shared` 连接池。只热身 REST 直连域名，不碰网关。
- 验证：`KanpanData` **100 tests / 13 suites** 通过（新增 `QuoteSnapshotTests` 5 项），`KanpanCore` **209 tests / 33 suites** 通过；模拟器与真机（iPhone 16 Pro，iOS 26.6.1）均构建成功，已安装到真机。
- 未完成：模拟器 UI 交互验收。Claude Code 的 iOS Simulator 工具报 `xcode-select` 未选中（`xcode-select -p` 实际正常），computer-use 授权被拒，所以「回前台立刻有价 / 冷启动列表不空」只有单测与构建证据，没有跑通界面回归。真机上的实际体验待用户或下一轮确认。

### 2026-09-16 换品种/换周期秒开：多品种快照、对冲选路、后台加深、自选预热

- 仍由 Claude 直接改代码（用户「都要」「你可以根据具体情况大胆使用」）。未提交、未推送、未动 VPS 网关。
- 前提变更：用户说明实际用户只有 3 位朋友、上限 10 人，并把手机资源上限放宽到「存储 + 内存不超过 2 G」。据此**作废**任务书里 A6.11 的「行情缓存恒 < 1 MB」与 P9.4 的「常驻 < 80 MB / 沙盒 < 1 MB」，改成各自封顶的新数值（已同步改 `docs/实施任务书.md`）。
- 改法：
  - 新增 `KanpanData/Store/SeriesStore`：启动快照从「磁盘上唯一一份 `last.kbar`」改成按 (品种, 周期) 一对一个文件，放在 `Caches/kanpan/series/`，上限 **400 对 / 64 MB**，按最近使用淘汰。文件名用枚举 case 名而不是 `rawValue`——`1m` 和 `1M` 只差大小写，iOS 文件系统默认大小写不敏感会撞名；读回时再校验品种与周期，撞了也只是未命中。`Paths.snapshot` 退化成只用于清理旧文件。
  - `Snapshot.maxBars` 600 → **1500**（`maxBytes` 60 KB → 150 KB），`BarCache.defaultLimitBytes` 40 MB → **160 MB**。内存没有再往上抬：前台占得越多退后台越早被 jetsam 杀，而被杀正是「切回来要重新加载」的根因。
  - `MarketFeed.switchTo` 的快照打底不再限于冷启动，改成每次换品种/换周期都查；新增 `seedUsable`（`maxSeedGapBars = 3000`）挡住旧到 `contiguousTail` 补不回来的快照。
  - 两段式首屏：`firstScreenLimit = 300` 的小页与完整深度并行发，谁先回谁先画（`applyFirstScreen` 只在图还空着时落地）。注意 app 侧 `RoutedMarketFeed` 本来就用 `initialLimit: 300`，所以这条实际只在默认 1500 的场景生效。
  - 新增「后台加深」：首屏落地 1.2 秒后自动 `loadMore(quiet:)` 一页到 `deepenTarget = 1800` 根，把「拖到左边缘现拉」的等待挪到用户还在看第一屏时做掉。失败不报错。
  - 对冲选路：`MarketRESTTransport.get` 原来是串行——直连干等满 `directAttemptTimeout = 3s` 才开网关竞速。改成直连发出后 `hedgeDelay = 0.7s` 没回音就并行叫网关，谁先回用谁。不设次数配额（延迟本身就是闸门；直连健康时那一发根本不会发出去）。网关赢时**不**给直连记 300 秒长冷却（只说明它慢，不说明它坏）；直连自己跑完并报错的仍照记 30 秒；取消（换品种）一律不记账。
  - 自选预热 `RoutedMarketFeed.prefetch`：冷启动第一屏是自选页，趁用户在看报价，把前 8 个品种当前周期的 300 根拉回来直接写进 `SeriesStore`（不进 `BarCache`），点进去命中磁盘。一个失败就整批停手。
  - `LaunchPrewarm` 同时热身推送域名（HEAD `/`），不只 REST。
  - `QuoteBook` 增加 30 秒节流的定时落盘 `notePersist()`：原来只有退后台/拆连接才写，被 jetsam 杀是没有通知的，那一次的报价会全丢。
- 验证：`KanpanData` **109 tests / 15 suites** 通过（新增 `SeriesStoreTests` 7 项、`TwoStageFetchTests` 2 项；`FeedReplayTests` 三条快照用例改到 `series/`；`DataIntegrityTests.returningToSameSelectionCannotReviveOldRequest` 把 `initialLimit` 压到 300 以免两段式打乱按下标放行的顺序），`KanpanCore` **209 tests / 33 suites** 通过，模拟器 `xcodebuild` BUILD SUCCEEDED。
- 未完成：真机安装与界面验收（模拟器 MCP 仍报 `xcode-select` 未选中，需用户执行 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`）。

### 2026-09-16 按实际机型重调容量 + 换周期预热 + MACD 精度

- 仍由 Claude 直接改代码（用户「如果还有更好的方案或者更适合的方案你可以直接改，如果没有了测试通过后直接提交代码到远程」）。未动 VPS 网关。
- 前提再变更：用户说明主力机型是 **8～12 G 内存、256 G 存储、当前空余约 160 G**，让我自行调整。结论是「花磁盘、不花内存」——磁盘这一侧几乎无约束，内存那一侧受 jetsam 约束（前台占得越多，退后台越早被杀，而被杀正是「切回来要重新加载」的根因）。
- 改法：
  - `SeriesStore` 上限 400 对 / 64 MB → **2000 对 / 512 MB**。2000 对的含义是「你翻过的全都留着」，淘汰基本不会被触发。
  - `Snapshot.maxBars` 1500 → **3000**（`maxBytes` 150 KB → 300 KB）。这是**必须**的：`MarketFeed.deepenTarget = 1800`，1500 的上限会把后台加深出来的那一段在写盘时截掉，下次冷启动白干。已在 `MarketFeed` 里把「`deepenTarget` ≤ `Snapshot.maxBars`」写成注释不变式。
  - `BarCache.defaultLimitBytes` 维持 **160 MB**，注释里写明了为什么不跟着往上抬。
  - 新增 `SeriesStore.pruneEverySeconds = 60` 节流（`PruneClock`，`prune(force:)` 留给测试）。目录能放到 2000 份之后，每次写盘都全目录扫一遍 + 取每份大小就不便宜了，而预热是一口气写十几二十份的。
  - 预热扩写：`prefetchLimit` 8 → **20**；`prefetch` 增加 `intervals:` 参数，除了自选品种的当前周期，还热**当前品种的其他常用周期**（`Prefs.quickIntervals`，由 `MainScreen.boot` 传入）。
  - 新增「换品种后自动热其他周期」：`RoutedMarketFeed` 记住上一次传进来的 `warmIntervals`，`switchTo(coldStart:)` 结束时延迟 **2500 ms** 给新品种的其余常用周期各拉一份（延迟是为了让首屏和 1.2 秒的后台加深先跑完）。它占**独立的 task 槽**（`warmTask`），不会把还在跑的自选预热掐掉；两个槽都在 `stop()` 里取消。
  - 修 `ChartRenderer+Sub` 的 MACD 图例精度：DIF/DEA/M 都是价差，量级跟着价格走，原来按固定 2 位小数印，在 0.0033 量级的品种上全是 `0.00`。改成跟着 `state.decimals`。
- 文档：`docs/实施任务书.md` A2.4 / A6.11 / P9.4 的数值同步到新上限（≤ 3000 根、≤ 300 KB/份、全目录 ≤ 2000 份 / 512 MB，沙盒 `du` < 540 MB）。
- 验证：`KanpanData` **109 tests / 15 suites**、`KanpanCore` **209 tests / 33 suites** 通过；模拟器与真机 `xcodebuild` 均 BUILD SUCCEEDED。模拟器（iPhone 16 Pro / iOS 26.5）走了完整交互验收：冷启动直接落在自选分类页且报价是实时的；清空 `series/` 后冷启动即生成 7 份预热快照（2 个自选当前周期 + BTC 其余 5 档常用周期）；点 0G 秒出整图；2.5 秒后磁盘上出现 `0GUSDT@{m1,m5,m15,h4,d1}`，且 `0GUSDT@h1` 已加深到 1800 根（72039 B = 39 B 头 + 1800×40）；点 15m 立刻切换，主图/VOL/持仓量/MACD 全在，MACD 读数为 `DIF -0.0007993 DEA -0.0003856 M -0.0008273`。
- 备注：等距周期的快照没有 openTime 列，**一根 40 字节不是 48**；按 48 估算会误判「加深没生效」。
- 本轮连同前两轮（后台恢复不清价、多品种快照/对冲选路/后台加深/预热）一起提交为 `201749f`（`让冷启动与切换不再等网络：多品种快照、后台加深、预热`），已推送到 `origin/main`，并已安装到真机 iPhone 16 Pro。同时把 `.project-memory/claude/kanpan-no-persistent-kline-storage.md` 更新到新的存储口径（原文写的「磁盘只留一份几十 KB 的 last.kbar」已作废）。工作树里与本任务无关的未提交内容（`AGENTS.md`、`docs/acceptance/drawing-v2/`、`docs/brand/`、账号系统与复盘交接文档）一律没动。

### 2026-09-16 公开相似索引首批部署

- 主节点 `orderflow-vps` 的 `kanpan-postgres` 原有 `market_features` 计数为 0；已新增 `0006_public_history_ann.sql`，加入公开窗口唯一身份约束和 HNSW cosine ANN 索引。
- 新增 `Backend/kanpan-api/src/bin/import_public_history.rs`：`KANPAN_INDEX_SOURCE=binance` 时读取官方 Binance REST，`okx` 时读取本机 OKX 行情网关，验证连续 K 线后使用冻结的 `candle-geometry-v2`/`ohlc-geometry-resample64-v2` 生成窗口，按 `(market,symbol,timeframe,start,end,model,render,source)` 幂等写入。
- 首批已发布 **5354** 个窗口：Binance 2677 + OKX 2677；两套均为 USDⓈ-M、BTC/ETH/SOL/XRP/BNB/DOGE/ADA/LINK/AVAX/SUI 十个 USDT 永续、最近180天、1h。`/v1/capabilities` 已返回 `indexedWindows:5354`；主节点 API/worker 重启后均 active，ANN 邻近查询与 64 根 OKX 网关回取均通过。
- 因两台 VPS 直连 Binance REST 仍为 HTTP 451，Binance 批次由当前 Mac 可用的官方 REST 读取后经 SSH 隧道写入主库；查询端已按 `source` 与请求行情源隔离，未混源。该批是可用种子，不代表全市场、全周期覆盖。
- 本轮后端 `ops/test.py` 通过：7 项单元测试 + 1 项真实 PostgreSQL 账号隔离集成测试。工作树里其他用户已有未提交改动仍保留。

### 2026-09-16 冷启动「自选一个个慢慢加载」的真因与修复

- 用户反馈：「自选列表我划掉后台冷启动还是一样啊，一个个慢慢加载这个功能是不是没做好」，随后要求「多加几个品种测试一下」。我上一轮报的「冷启动直接落在自选分类页且报价是实时的」**是错的**——那次截图在启动约 8 秒之后，整个骨架填充过程一帧都没看到。这一轮把自选加到 15 个品种，用「terminate → sleep 2 → launch + 紧循环截图 6 秒」的方式逐帧抓，才看见真相。
- 两个独立成因，都已修：
  1. **`QuoteBook.updateStreams()` 把刚恢复出来的快照裁掉了。** 冷启动顺序是 `restoreQuotes()` 先把上次的 15 行摆好，宿主随后才 `setFavorites`。中间这一小段里 `wanted` 只有图上那一个品种，`raw` 被裁到只剩 1 行，`onScopeChange` 还顺手通知 picker 把其余的丢掉——15 行里 14 行当场作废，只能一个个重新从网络拉回来。修法：新增 `favoritesKnown`，自选表到齐之前只准往 `wanted` 里加、不准拿它去裁（`wanted.formUnion(raw.keys)`）；同时 `MainScreen.boot()` 里把 `quotes.setFavorites` 排到 `setChartSymbol` 前面。
  2. **落盘的 30 秒节流会漏掉刚加的自选。** 星标一个新品种后 30 秒内把 app 划掉，那一行根本没进 `quotes.json`。修法：`notePersist()` 里若 `raw` 出现 `persistedSymbols` 之外的品种就绕过节流立刻写；`restoreQuotes`/`persistQuotes` 各自维护 `persistedSymbols`，避免恢复后又原样回写一遍。
- 另两处配套：
  - `MarketModel.start(snapshot:)` 开头**同步**从 `SeriesStore` 读一份 `series`。原来要等 `feed`（actor）跨执行器跳一次才回得来，冷启动那一跳就是半秒空图。
  - `SymbolPickerModel.setLoader` 在 `catalog` 仍为空时自己补一趟加载。自选页现在从第一帧就在，它的 `appear()` 可能比宿主接线还早跑一步。
- **首屏盖层不能用 `fullScreenCover`。** 先试过「`showFavorites` 初值为 true」和「在 `disablesAnimations` 的事务里置位」，动画能关掉，但 UIKit 的 present 流程注定要先让宿主自己画一帧——抓帧稳定看到 0.57 s 有一张行情页闪过。最终改成 `MainScreen.launchFavorites`：用 `@State launchCover = MainScreen.startsOnFavorites`（静态只读一次 `SymbolPrefsStore().load().favorites`）配一个普通 `.overlay`，和宿主在同一帧布局。`favoritesPage(onClose:)` 抽出来给两条路共用；`picker.onPick` 与 `AppAccountBridge.onSwitch` 里都补了 `launchCover = false`，`renderingActive` 和 `quotes.setVisible` 也都算上它。用户一旦离开这一层就永久落下，之后进自选仍走原来的 `fullScreenCover`，两条路不会同时在。
- 模拟器（iPhone 16 Pro / iOS 26.5，15 个自选）逐帧结果：0.00 s 启动动画 → 0.27/0.46 s 启动屏 → **0.64 s 自选页，15 行全部带值** → 0.85 s 之后不再变化。对照修复前的回归版是 0.72 s 出灰骨架、一行行填到 3.65 s 才齐。交互复验：从首屏盖层点 BTC 能正常落下并出整图（主图/VOL/持仓量/MACD 一屏内），底栏「自选」再进走的是 `fullScreenCover`，表头仍是「涨 0 跌 15」。
- 验证：`KanpanData` **109 tests / 15 suites**、`KanpanCore` **209 tests / 33 suites** 通过；模拟器与真机 `xcodebuild` 均 BUILD SUCCEEDED；真机 iPhone 16 Pro 已安装最新包。
**真机 UI 用例（2026-09-16 03:47–03:53）**：四次尝试全部倒在同一个地方——
`KanpanUITests-Runner` 起来打印 `Running tests...`，18.07 秒后固定收到
`Connection peer refused channel request for "dtxproxy:XCTestDriverInterface:XCTestManager_IDEInterface"`
→ `Exiting due to IDE disconnection`，xcodebuild 报 `runner exited with code 74 before establishing connection`。
第一次是手机锁屏（`Unlock iPhone to Continue`），之后三次日志里再没有锁屏字样，18.07 秒这个固定值
也说明不是网络抖动，是 XCTest 的 bootstrap 握手在无线通道上握不上。
排除项：删掉设备上的 `com.mdd.kanpan.KanpanUITests.xctrunner` 重装无效；
`devicectl device install app` + `process launch` 一次成功，说明通道本身是通的、设备是健康的；
同样这三条用例在模拟器（iPhone 16 Pro）上全绿（8.2 s / 9.5 s / 9.5 s）。
`devicectl device info details` 里 `transportType: localNetwork`——手机只有无线配对。
结论：这是 XCTest 走无线通道的老毛病，和本次改动无关，插上 USB 线后重跑即可。

**真机用例已补跑（USB，2026-09-16 03:55）**：插上 USB 后 `devicectl device info details` 的 `transportType` 从 `localNetwork` 变成 `wired`，同一条命令一次通过——`testFavoriteStarToggles` 8.035 s、`testSearchEntryOpensSymbolPage` 8.856 s、`testSymbolButtonOpensQuickSheet` 8.991 s，`** TEST SUCCEEDED **`。这反过来坐实了上面那条：无线配对下 XCTest 的调试通道握不上，和代码无关。
**以后真机跑 UI 用例先确认 `transportType: wired`。**

代码已推到 `origin/main`（`cd9b32d`）。

**仍未做**：真机上的逐帧冷启动实测。真机没有可用的截图通道——`devicectl` 没有 screenshot 子命令，`idevicescreenshot` 在 USB 下能看到设备但报 `Could not start screenshotr service: Invalid service`（iOS 17+ 的个性化 DDI 由 CoreDevice 挂载，libimobiledevice 够不着），UI 测试里又因为 `KANPAN_TEST_PROFILE=1` 关掉了 `LaunchPrewarm`、把 `SymbolPrefsStore` 换成内存实现，`startsOnFavorites` 恒为 false，测不到首屏盖层。逐帧结论目前只有模拟器那一份。
- 工作树里与本任务无关的未提交内容（`AGENTS.md`、`docs/acceptance/drawing-v2/`、`docs/brand/`、账号系统与复盘交接文档、后端 `search.rs` 与 `import_public_history.rs`）一律没动。

## 2026-09-16 04:x — 冷启动自选的第二轮：网络这一头（`1ba2a1b`，已推）

上一轮把「一行行慢慢加载」修掉之后，用户在真机上仍觉得「4 个品种也要等一下」，问是不是网络。
量了一下，是网络，而且是自己给自己加的：

- 币安单品种 `fapi/v1/ticker/24hr?symbol=X` 回包 **~375 B**；`?symbols=[...]` 在合约那边**被忽略**，
  返回整个市场 **285,252 B / 0.62 s**。而币安走 HTTP/2，几十条单品种请求在同一条连接上多路复用，
  实测 8 条并行 0.664 s，本来就只花一个往返。
- `QuoteBook.batchThreshold` 原来是 8，于是冷启动一屏自选（恢复出来的行都不算「新鲜」，
  `receivedAt` 没落盘）必然触发全市场那一发 —— 把 8 KB 换成 285 KB。**这就是那段等待。**

改动（全部在 `1ba2a1b`）：
- `QuoteBook.batchThreshold` 8 → 48；`quoteConcurrency` 4 → 24；`historyConcurrency` 2 → 8。
- `RoutedMarketFeed.prefetch` 的 K 线预热 `delayMs` 0 → 1200：每份 300 根几十 KB，让位给那一屏几百字节的报价。
- `SymbolPickerModel` 加 `index: [String: SymbolInfo]` + `info(for:)` + `reindex()`（在 `init` 与 `setCatalog` 调用；
  **不要用 `didSet`**，`@Observable` 会改写存储属性）。`FavoritesView` 4 处、`FavoritesQuickPicker` 1 处
  的 `catalog.first { $0.symbol == ... }` 全部换掉——那是每秒几万次主线程字符串比较。
- `historyCapacity` 8 → 40。

验证：模拟器逐帧 0.64 s 全满（改前 0.69 s）；`nettop` 冷启动累计 bytes_in 30 KB → 78 KB，285 KB 那发消失；
`KanpanData` 109 tests / 15 suites 全过；真机 USB `MainScreenUITests` 三条 24.96 s 全过。

**刻意没做**：展开行的 1m 分钟线落盘缓存。它只喂展开的详情面板，`historyChange` 本来就拒收超过 60 s 的旧数据。

**试过又撤掉**：把系统启动屏（那 0.2–0.5 s 空白）的底色改成 app 背景色。这版 Xcode 只认
`INFOPLIST_KEY_UILaunchScreen_Generation`，`INFOPLIST_KEY_UILaunchScreen_BackgroundColor` 写进 pbxproj 后
`-showBuildSettings` 能看到，但生成的 `Info.plist` 里 `UILaunchScreen` 仍是空 dict（全 Xcode 里搜 `INFOPLIST_KEY_UI*`
只有 `UILaunchScreen_Generation` 和 `UILaunchStoryboardName`）。要改就得引 storyboard 并动 pbxproj 的资源阶段，
收益（浅色白对白、深色纯黑对 #161A3F）不值，已把键和 `LaunchBackground.colorset` 撤干净。

**用户问「冷启动第一页不应该是自选列表吗」**：是，而且现在就是——`MainScreen.launchFavorites` 那个 `overlay`
保证第一帧就是自选页，逐帧 0.19/0.45 s 是系统启动屏、0.64 s 自选页全满，中间没有行情页。
退后台再进来停在原页也是对的（`launchCover` 一旦离开就永久落下）。最新包已装到真机。

## 2026-09-16 04:4x — 上面那条结论对模拟器成立、对真机不成立：登录态这一层

用户连着三条：「我现在划掉了后台冷启动是进入行情页面，不是自选的分类页面」「你是不是没打包最新
代码更新到手机上」「登录了账号也不能这样吧」。包是新的，是真有 bug——而且模拟器永远看不到，
因为模拟器上**没登录**。

`AppAccountBridge.init` 结尾同步跑了一次 `try prepare(nil)()`，先把**访客**那份档案挂上；
真正属于账号的那份要等 `Task { await account.restore() }` 异步读回来。真机上：
`accounts/local/8f5843d2-…/symbols.json` 自选 **0** 个，`accounts/u-4ada33ff-…/symbols.json` 自选 **22** 个。
而 `MainScreen.boot()` 里 `wireAccount()` 排在最前面，于是 boot 后面每一行看到的自选表都是空的：

1. `prepare(_:)` 返回的 apply 闭包里 `onSwitch()` 在 `symbols.useStorage` **之前**调用。
   `onSwitch` 原来无条件 `launchCover = false`——恢复登录态走的是和用户主动换号同一条路，
   于是首屏盖层被当场掀掉，第一眼就是行情页。**这就是「冷启动进行情页」。**
2. `quotes.setFavorites([])` 把 `favoritesKnown` 置真，`updateStreams()` 里那条保护
   `if !favoritesKnown { wanted.formUnion(raw.keys) }` 随即失效，`configure` 刚从
   `quotes.json` 恢复出来的十几行被裁到只剩图上那一个品种。
3. `quotes.setVisible(true)` 和 `market.prefetchFavorites(...)` 整个 `if` 块被跳过。

也就是说 `1ba2a1b` 那一轮的优化在**登录用户身上一条都没生效**——用户反复说的「手机上还是一行行
慢慢加载」是真的，不是错觉。真机 `Library/Caches/kanpan/quotes.json` 当时只剩 15 行（账号自选 22 个）。

改法（`MainScreen.swift` + `SymbolPickerModel.swift`）：
- `didRestoreAccount`：`onSwitch` 的**第一次**是冷启动恢复，不掀盖层；之后才当换号看。
- `awaitingAccount` + `coveringLaunch`：等账号回来的这一小段里不能把「自选是空的」当真，
  否则盖层先让位给行情页、账号回来再翻回去，闪一下。
- 账号那份表回来之后按真表**重判**首屏（`didLeaveLaunch` 保证不会把已经在看图的用户拽回自选页）。
  `launchCover` 的初值是拿默认档案猜的，登录用户的表不在那儿，猜不准。
- `boot()` 里空表**不交**给 `QuoteBook`；`settleFavorites(_:)` / `primeFavorites(_:)` 跟着表本身走，
  由 `onChange(of: picker.prefs.favorites)` 和 `onSwitch` 的延迟任务触发。
- `picker.resetSelectedGroup()`：冷启动回到第一个分类（用户：「它还是记录了我上一次退出正在看的分页」）。
  只改内存、不落盘不同步——分组选中在同一次使用里仍然记得住。

另外用户报「涨跌幅每次都是最慢出来的」。非 24 小时口径（上海 0 点 / UTC 0 点）的涨跌幅要自己拿
边界那根 1h K 线的开盘价算，一个品种一发请求、并发写死 4，二十几个自选要排六轮往返。加了
`BaselineSnapshot`（`Paths.opens`）把这批开盘价按边界落盘，冷启动读回来就能第一帧算出涨跌幅；
`baselineConcurrency` 4 → 16。**但这位用户的 `changeBasis` 是 `rolling24h`**（真机 plist 实测），
走的不是这条路——他那边涨跌幅慢的根因是上面第 2 条把快照裁掉了。这段优化是给另外两种口径的。
