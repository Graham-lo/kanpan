-- 主力订单流的服务端历史（2026-09-24）。
--
-- kanpan-api 的 serve 进程常驻跟踪 BTC / ETH / SOL（以及最近有人看过的其它币，最多 20 只）
-- 的各家各产品挂单簿，按和手机上 OrderFlowModel 同一套规则判出「大单」，一单一行写在这里。
-- 手机打开一只品种时先拉最近 24 小时，往左拖再一天一天补，最多 30 天。
--
-- 公开行情数据，没有主人：和 daily_close 一样不挂 RLS；ops/install.py 迁移之后给运行角色
-- 授予全表的增删改查（跟踪器要 upsert、结束时更新、滚动清理要删）。
--
-- 主键 = 哪本簿、哪一侧、哪个桶、哪一刻出现：同一个桶先后出现的两单是两行。
-- `step` 记跟踪时的步长（步长换了桶号就对不上）；`seen_ms` 是挂着的单最后一次看到的时刻，
-- 进程重启读回时据此判断缺席是不是超过了两分钟。
-- 两张都是新表，同一事务里建的索引不会锁旧表。
CREATE TABLE orderflow_orders (
 base text NOT NULL,
 venue_id text NOT NULL,
 exchange text NOT NULL,
 product text NOT NULL,
 side text NOT NULL,
 bucket bigint NOT NULL,
 price double precision NOT NULL,
 first_seen_ms bigint NOT NULL,
 end_ms bigint,
 status text NOT NULL,
 initial_notional double precision NOT NULL,
 notional double precision NOT NULL,
 filled_notional double precision NOT NULL,
 threshold double precision NOT NULL,
 vanished_notional double precision,
 step double precision NOT NULL,
 seen_ms bigint NOT NULL,
 PRIMARY KEY(base,venue_id,side,bucket,first_seen_ms)
);
-- 读：一只 base 在一段时间里出现过的（first_seen ≤ to 且 end ≥ from）。
CREATE INDEX IF NOT EXISTS orderflow_orders_first_seen ON orderflow_orders(base,first_seen_ms);
-- 滚动清理按结束时刻删；读回挂着的单走 end_ms IS NULL。
CREATE INDEX IF NOT EXISTS orderflow_orders_end ON orderflow_orders(base,end_ms);

-- 跟踪过哪些 base：从什么时候开始有历史（`since_ms`，只写一次）、最近一次有人要（`requested_ms`）。
-- 进程重启时据此把最近 24 小时有人看过的 base 接着跟起来。
CREATE TABLE orderflow_bases (
 base text PRIMARY KEY,
 since_ms bigint NOT NULL,
 requested_ms bigint NOT NULL
);
