# 看盘 / Hkline：Codex 跨窗口入口

同步日期：2026-10-09（Asia/Shanghai）。这是恢复上下文的索引；用户当前指示优先，状态须核对 Git、源码与验收记录。

- 实际仓库 `/Users/mdd/zhk/kanpan`，远程 `Graham-lo/kanpan`。不要使用旧目录 `/Users/mdd/kanpan`，也不要与炸金花项目混淆。
- 先读 `AGENTS.md`，现状以 `.project-memory/PROJECT.md` 最新节为准；Claude 本机记忆索引在 `/Users/mdd/.claude/projects/-Users-mdd-zhk-kanpan/memory/MEMORY.md`。旧记忆中关于美国主机、OKX 替身、五格底栏、八台模拟器的描述已被新决定覆盖，不能直接套用。
- 新加坡 VPS `43.160.232.253`，SSH 别名 `kanpan-sg`，登录用户 `ubuntu`（sudo）；唯一公开入口 `https://kanpan.43-160-232-253.sslip.io`。API、worker、Postgres、Python 网关、stream hub、电脑与手机网页都在此机。美国节点已停用客户端入口；不添加自动切换、跳板或备用线路。
- 后端 `/opt/kanpan-api`，Python 网关 `/opt/kanpan-gateway`，网页 `/var/www/kanpan/web`。本机用 `cargo zigbuild --release --target x86_64-unknown-linux-gnu.2.35` 构建 Linux 二进制，重活必须经 `scripts/machine-guard.sh run` 或 Makefile。
- 用户本次授权同步 Claude 记忆并部署最新代码。Claude 分支 `claude/funny-turing-qp668m` 的 20 个提交截至 `69b840ce`；已快进合入并推送 main，后端、网关、电脑与手机网页均已部署新加坡，发布与验证结果见 PROJECT.md §72；随后新增历史大单开关、更新新加坡并安装真机 Release 的结果见 §73；电脑入口位置见 §74，三端自选 / 搜索名称见 §75，订单流点击互斥、手机大单页整页字体与最新手机安装见 §76。部署前查明线上 186 个后端文件与旧 main `c43ae419` 逐一相符，无新增数据库迁移。
- 最新行情规则：交易所各自独立，OKX 不再替代币安；品种身份为 venue/market/symbol，主力订单流仍跨交易所聚合。网关线路经新加坡访问选定交易所，线路手动选、不混源。HL 费率按每小时原值显示，整点结算，倒计时过点按一小时滚。
- 发布顺序：main 推送 → kanpan-api → Python 网关 → 移除 Caddy `/market/okx/stream` → 网页。先备份二进制、源码、网关、Caddy 路由及网页，再校验散列；`ops/install.py` 自带一次重启，不再重复重启后端。旧版 iOS 网关档依赖已退役 OKX 接口，需要更新 App；10-09 17:29 已给连接的 iPhone 16 Pro 安装最新 Release（功能提交 4c76872d，包含订单流点击修复与整页字体统一），本轮自动启动因锁屏被系统拒绝；界面测试在模拟器通过。不要把一次服务器发布自动视为所有手机都已更新。
- 两个尚未拍板的问题只是上下文，不自动实施：PEPE 搜索组序的 PC / 手机匹配差异；Coinbase 订单流 level2 在网关档仍直连。
- 不保存凭证；不修改 Mac 网络配置；不压测线上服务器；不覆盖别的窗口未提交改动。

- 10-09 用户决定：「分析 → 主力订单流 → 历史大单」默认关闭，`orderFlowHistory=false` 随账号同步；只画 live，成交完 / 撤单 / 失联结束隐藏，部分成交仍 live 的保留。沿用生命周期，先过滤再合墙，不删除历史。三端已实现、已推送、已部署；证据见 PROJECT.md §73。

- 10-09 电脑网页：右侧「主力订单流」的「图上订单流」下一行直达「历史大单」，指标弹窗也保留同一偏好入口；自选只写 BTCUSDT 这类品种 + 实际计价币，不写交易所与永续。两项已推送、已部署、线上验证，见 PROJECT.md §74（覆盖 §71 对电脑自选缩写的旧要求）。
- 10-09 三端自选与搜索：iOS / 手机网页 / 电脑网页统一连写 BTCUSDT / BTCUSDC / BTCUSD，不带行内交易所、斜线、永续 / 现货；搜索交易所只在组头显示，第二行保留已有中文别名。行情页与板块列表保持原样，完整品种身份未改。网页已上线，最新 iOS 包已安装；测试与证据见 PROJECT.md §75，覆盖 §71 对这些列表行带缩写的旧要求。

- 10-09 手机订单流点击与整页排版：金额签按屏上最终矩形命中整组墙，点签优先；点气泡定位带 bigTrade 来源，不再同时弹挂单卡，手动移动恢复悬停。iOS / 手机网页大单页全部复用现有字阶，标题与主金额 17 semibold；已推送、网页已上线、17:29 最新 Release 已装手机（启动被锁屏拒绝），详见 PROJECT.md §76。
