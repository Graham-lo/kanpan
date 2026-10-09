# 看盘 / Hkline：Codex 跨窗口入口

同步日期：2026-10-09（Asia/Shanghai）。这是恢复上下文的索引；用户当前指示优先，状态须核对 Git、源码与验收记录。

- 实际仓库 `/Users/mdd/zhk/kanpan`，远程 `Graham-lo/kanpan`。不要使用旧目录 `/Users/mdd/kanpan`，也不要与炸金花项目混淆。
- 先读 `AGENTS.md`，现状以 `.project-memory/PROJECT.md` 最新节为准；Claude 本机记忆索引在 `/Users/mdd/.claude/projects/-Users-mdd-zhk-kanpan/memory/MEMORY.md`。旧记忆中关于美国主机、OKX 替身、五格底栏、八台模拟器的描述已被新决定覆盖，不能直接套用。
- 新加坡 VPS `43.160.232.253`，SSH 别名 `kanpan-sg`，登录用户 `ubuntu`（sudo）；唯一公开入口 `https://kanpan.43-160-232-253.sslip.io`。API、worker、Postgres、Python 网关、stream hub、电脑与手机网页都在此机。美国节点已停用客户端入口；不添加自动切换、跳板或备用线路。
- 后端 `/opt/kanpan-api`，Python 网关 `/opt/kanpan-gateway`，网页 `/var/www/kanpan/web`。本机用 `cargo zigbuild --release --target x86_64-unknown-linux-gnu.2.35` 构建 Linux 二进制，重活必须经 `scripts/machine-guard.sh run` 或 Makefile。
- 用户本次授权同步 Claude 记忆并部署最新代码。Claude 分支 `claude/funny-turing-qp668m` 的 20 个提交截至 `69b840ce`；已快进合入并推送 main，后端、网关、电脑与手机网页均已部署新加坡，发布与验证结果见 PROJECT.md §72。部署前查明线上 186 个后端文件与旧 main `c43ae419` 逐一相符，无新增数据库迁移。
- 最新行情规则：交易所各自独立，OKX 不再替代币安；品种身份为 venue/market/symbol，主力订单流仍跨交易所聚合。网关线路经新加坡访问选定交易所，线路手动选、不混源。HL 费率按每小时原值显示，整点结算，倒计时过点按一小时滚。
- 发布顺序：main 推送 → kanpan-api → Python 网关 → 移除 Caddy `/market/okx/stream` → 网页。先备份二进制、源码、网关、Caddy 路由及网页，再校验散列；`ops/install.py` 自带一次重启，不再重复重启后端。旧版 iOS 网关档依赖已退役 OKX 接口，需要更新 App；服务器部署不等于已装真机包。
- 两个尚未拍板的问题只是上下文，不自动实施：PEPE 搜索组序的 PC / 手机匹配差异；Coinbase 订单流 level2 在网关档仍直连。
- 不保存凭证；不修改 Mac 网络配置；不压测线上服务器；不覆盖别的窗口未提交改动。
