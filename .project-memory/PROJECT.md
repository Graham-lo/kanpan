# Hntcoin（看盘 / Kanpan）跨窗口项目记忆

更新：2026-09-17。给任何新开的模型窗口恢复上下文用。用户当前指示优先；下面是整理时的快照，接手前用 `git log`、`git status` 和源码核对。

## 1. 身份与分工

- 产品 Hntcoin，工程名 Kanpan。仓库 `/Users/mdd/zhk/kanpan`，远程 `https://github.com/Graham-lo/kanpan`，分支 `main`，2026-09-17 HEAD `a2cbb0d`。
- Swift 6、目标 iOS 17+、真机验证 iOS 26；SwiftUI + UIKit/CoreGraphics 自绘图表；零第三方依赖；不做交易。
- 代码由 Claude 窗口实现，视觉 / 交互原型定稿后可派 Opus 5（high）子代理写、主窗口验收、装真机、push。Codex 已不参与；`HISTORY-2026-09-15-codex.md` 与根目录 `KANPAN-HANDOFF-2026-09-14.md` 是历史。
- 常常有第二个窗口在同一工作树改交互逻辑。只动自己范围内的文件，不提交别人的改动。

## 2. 当前界面（2026-09-17）

- 皮肤：青苔·冷（默认）/ 陶土·暖，各有浅深两版，`ThemeSkin` + `ThemeChoice`；种子色在 `KanpanCore/Sources/KanpanCore/Style/Palette.swift`。
- 底栏「复盘｜指标｜自选｜设置」（`Kanpan/Kanpan/Main/BottomBar.swift`）。无横屏格、无风格格。
- 行情页顶栏：品种徽章 + 品种名（点开半屏快捷自选 / 搜索）+ 状态点 + 自选星；最新价 22pt medium + 涨跌药丸 11.5pt，下一行成交额 / 振幅；不显示 24h 高低（`Main/TopBar.swift`）。
- 自选页「琉璃」版（`Symbols/FavoritesView.swift`，提交 `a2cbb0d`）：光斑底、玻璃纸、衬线标题 22pt 与正放的数量印章、涨跌比例条、品种徽章 33pt、价格 15.5pt、涨跌药丸；迷你走势图默认关闭，「…」菜单里 `favorites.sparkline` 可打开（本机 AppStorage）；排序与涨跌幅口径在 `favorites.sort` 弹层里；没有领涨 / 领跌行。
- 品种徽章一品种一记号（`Main/CoinBadge.swift`、`CoinBadgeBrands.swift`），配色随皮肤。
- K 线只有 AICoin 一套造型（`CandleStyle.all == [aicoin]`），主图 MA(10,30,120,256)，副图默认 MACD + RSI；14 档周期，不含 3d；横屏仅画线用，画线时主副图指标不画。
- 「记」按钮可拖动、限主图内、记住位置。

## 3. 行情、账号、复盘（技术结论，沿用 09-15/16 的验证）

- 线路：官方直连、用户线路、两台 VPS 网关（主 `kanpan.107-174-172-10.sslip.io`，备 `kanpan.96-44-162-222.sslip.io:8443`）自动选路并落盘 `market-source.json`。Binance 不能完整使用时历史、补页、WS 整套切 OKX，不混源；后台首次 5 分钟、最长 15 分钟低频确认恢复后切回。取消请求与单次超时不惩罚线路。
- 冷启动 / 切换靠多品种快照、后台加深、自选预热做到不等网络；登录用户的自选表要等账号恢复后再判首屏（09-16 修过「冷启动进行情页」「自选一行行慢慢加载」）。
- 账号：用户名 + 密码，Keychain 会话，设备管理、改密、注销；服务端 `Backend/kanpan-api`（Rust，主 VPS `/opt/kanpan-api`，API 8794，PostgreSQL loopback 55434，RLS 隔离，同机每日备份 30 天）。邮箱注册停掉了。
- 复盘：`KanpanReview` 接现有图表，记一笔 / 列表 / 待办 / 统计 / 详情 / 逐根重温 / 私有 OHLC 找相似；记录固定行情源；公开相似索引只是首批种子。
- 网关：`Backend/kanpan-gateway`，`/opt/kanpan-gateway`，REST 8792、共享 WS 8793，服务 `kanpan-gateway`、`kanpan-stream-hub`。线上服务，只读探测，不改 Caddyfile。
- 原型静态托管：主 VPS `/var/www/kanpan/ui/`（`ssh orderflow-vps`，`install -o caddy -g caddy -m 644`），浏览器地址 `https://kanpan.107-174-172-10.sslip.io/ui/`。

## 4. 用户稳定偏好

- 极致好看优先，不要工程风 / 后台风；元素尺寸克制，大字号与粗字重会被判「廉价」；装饰元素正放不倾斜；整屏是一块连续材料，不要硬拼接。
- 配色只在青苔 / 陶土两套里做，不自创第三套；图表底座不是设计对象。
- 合并入口不能丢功能；发现残留问题直接修不请示；面板选完即收起。
- 界面不出现「行情实时」之类状态字段，不堆解释文案，能自动做的不弹窗。
- 验证只跑受影响的一两条真机 UI 用例并开超时；视觉改动真机看一眼即可。真机 iPhone 16 Pro 常连在 Mac 上。
- 手机可能经 Mac 的 Surge 网关上网，不改 Mac 网络配置。

## 5. 未完成范围（沿用 `docs/账号复盘-实施进度.md`）

- 复盘：框选贴边自动滚动、精确时间编辑、痕迹点进详情、保存案例管理 UI、规则版本查看、截图补录、旧资料归属导入。
- OKX 持仓量副图未接；精确 trade_touch 证据不足时保持待核验。
- 跨设备并发与同步冲突、全部复盘手机交互的端到端真机回归；其他机型与旧系统兼容按用户顺序另做。
- 2026-09-17 交互整套重排原型（`docs/交互审计与新原型方案-2026-09-17.md`）正在分页落地，另一窗口在改。
