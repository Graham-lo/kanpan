# 看盘轻量行情网关

两台已部署的公开行情入口：

- 主节点：`kanpan.107-174-172-10.sslip.io`
- 备用节点：`kanpan.96-44-162-222.sslip.io:8443`（该机443已有业务，保留原服务）

只处理公开行情，不接收交易/API密钥/账户数据，不代理REST。客户端优先使用当前有效线路；新连接比较用户地址、官方和两台网关的首条有效行情。健康连接持续使用，不因小幅延迟变化切换；断线、有效行情超时或网络接口变化后重选。败选连接立即关闭，首帧不会丢失。REST继续由客户端访问，两台美国节点的REST均实测451。

## 共享实时订阅

`/market/stream?streams=…`由独立aiohttp服务处理：每节点只有一条固定币安上游WS，所有客户端的同名频道合并订阅，最后一个订阅者离开才退订；无客户端时释放上游。保留双向SUBSCRIBE/UNSUBSCRIBE语义。每个慢客户端只留每频道最新一条待发真实帧，不落盘，不向新客户端重播旧报价。共享上游不等于下行免费：客户端数量增加仍消耗出站带宽和连接资源。

允许ticker、markPrice@1s和图表支持的kline周期；不允许用户指定上游URL、交易或账户API。每连接最多64频道、每来源最多160不同频道、每节点最多512频道。订阅消息有大小和速率限制；单来源握手、并发与总键数有界；慢发送超时断开，避免阻塞其他客户端。Caddy覆盖客户端来源头，公网自行填写同名头不能伪造来源。

当前匿名应用用可信连接IP隔离滥用，不宣称能识别独立自然人。共享NAT也共享来源配额。正常自选与主图每App通常两条连接；上限针对异常占用。应用层限制不替代运营商对大规模网络攻击的防护。

## 宿主资源预算

只读检查主机分别为7核/约8GB和3核/约4GB，部署时空闲内存约5.1GB/3.2GB、负载较低。先采用保守预算：主节点128连接、1.5MB/s应用出站；备用64连接、0.75MB/s。它们是上线保护参数，**不是压测得出的最大承载人数或供应商带宽保证**。

每5秒采样宿主CPU、可用内存、服务RSS、默认出口发送速度。压力升高时逐步减少新连接及发送预算，回落时缓慢恢复，避免抖动。整个服务由systemd限制256MB内存、50%单核CPU、64任务；历史服务独立受限。预算在`/etc/kanpan-gateway/limits.env`配置，不影响同机其他应用。公开HTTP健康接口只返回必要服务状态。

## 历史OI

- `/oi/v1/metrics/BTCUSDT/2021-12-01.json`：归档日切片，真实 `[毫秒时间戳,持仓量]`。
- `/oi/v1/metrics/BTCUSDT/range?interval=4h&from=1638316800000&to=1638403199999`：按14种图表周期取桶末值，周/月/年用UTC日历，1m/3m保留源5m粒度。
- `/chart-gateway/health`：历史服务状态。
- `/chart-gateway/stream-health`：实时服务连接/频道/预算状态。健康HTTP本身不证明行情可用。

历史日切片缓存最多200MB、8个全局下载任务、64个待处理键；同日请求合并。范围最多4并发，每请求2个读取任务；每来源2并发和请求速率限制，HTTP工作线程最多16，读超时5秒。缓存按最近使用淘汰，失败/404不永久缓存。手机只收周期聚合结果；主节点失败顺序转备用，不同时在两台重复生成相同历史范围；全部网关失败才走原有官方归档回退。近期REST及实时WS不交给历史聚合服务。

## 运行、验证与回滚

Python3.11+，独立venv，`pip install -r requirements.txt`；aiohttp固定3.14.3。本地运行 `python -m unittest discover -s Backend/kanpan-gateway`。19项测试含100个本地客户端复用一条假上游、来源限额、异常控制帧隔离、慢客户端释放、OI周期与缓存。100客户端测试只证明共享/隔离功能，不是生产容量承诺。

源码部署在`/opt/kanpan-gateway`，`kanpan-gateway.service`监听127.0.0.1:8792，`kanpan-stream-hub.service`监听127.0.0.1:8793；DynamicUser、NoNewPrivileges、ProtectSystem=strict、ProtectHome、PrivateTmp。历史缓存位于`/var/cache/kanpan-gateway`，可清理重建。

仅在项目独立Caddy站点导入`Caddy.routes`，其它主机规则保留。两台现有Caddy均admin off，配置备份并validate成功后各短重启一次激活；未升级Caddy或更改管理接口。后续Python更新只重启项目服务。恢复`/etc/caddy/Caddyfile.backup-before-shared-<部署时间>`并validate/激活可回滚路由；主节点旧源码另备份在`/var/backups/kanpan-gateway`。未修改Mac网络代理规则。

两台VPS的19项测试均通过；公网各2个客户端实收BTC、健康统计2客户端/1频道，断开后0客户端且上游关闭。2021年OI的4h返回6点、1d返回1点，两台一致。原始可公开结果见`docs/acceptance/AICoin-base/foundation/dual-gateway-live.json`。

Git只包含公开服务地址、实现及验证记录，不包含SSH配置、登录端口、私钥、密码或令牌。VPS是受信行情中转；WSS/HTTPS正常校验证书，不等于交易所对报价做端到端签名。
