-- 足迹图与秒线的历史（2026-10-07，网页版足迹图 / 秒级 K 线补历史）。两张表都是一只 base 一分钟一行，内容打包成一段字节。
--
-- orderflow_footprint：serve 常驻跟踪的每只 base（和 orderflow_flow 同一批），三家现货与永续的逐笔成交（不含交割）
-- 按交易所给的成交时刻分到那一分钟、按价位桶分开记主动买 / 主动卖美元额。`step` 是这一分钟的桶宽（每个币的价，
-- 价 × 0.0002 取到 1/2/5×10ⁿ、不小于跳价）；`levels` 是第一个桶号（i64 小端）+ 每档（桶号差 uvarint、买 f32、卖 f32），
-- 桶号 × step = 桶的下沿。读的时候 `GET /v1/market/orderflow/footprint`（footprint.rs）。
--
-- klines_seconds：同一批 base 里币安 U 本位永续的逐笔，每秒一根开高低收、成交量与主动买量（币安挂牌的价与张数）。
-- `symbol`、`tick` 照币安合约表；`bars` 是有成交的秒（u64 位图）+ 第一根开盘格数（i64）+ 每根（开 − 上一根收 zigzag、
-- 高 − 开、开 − 低、收 − 低 uvarint、量 f32、主动买量 f32），价 = 格数 × tick。读的时候 `GET /v1/market/klines/seconds`（seconds.rs）。
--
-- 同一分钟再写（停机交出的半分钟、重启后的另半分钟）在服务里读出来合并再写回（minutes.rs `write`）。
-- 保留 3 天，每小时和订单流的滚动清理一起逐只 base 按主键删；表文件超过各自的预算（storage_budget.rs：足迹 2 GiB、秒线 1 GiB）
-- 再从最旧的往后删到线下 10%。公开行情，不挂 RLS；install.py 的 GRANT … ON ALL TABLES 给运行角色读写。
CREATE TABLE IF NOT EXISTS orderflow_footprint (
 base text NOT NULL,
 minute_ms bigint NOT NULL,
 step double precision NOT NULL,
 levels bytea NOT NULL,
 PRIMARY KEY(base,minute_ms)
);
CREATE TABLE IF NOT EXISTS klines_seconds (
 base text NOT NULL,
 minute_ms bigint NOT NULL,
 symbol text NOT NULL,
 tick double precision NOT NULL,
 bars bytea NOT NULL,
 PRIMARY KEY(base,minute_ms)
);
-- 只插为主（合并写回很少）：插入触发的 vacuum 早一点跑，可见性图跟得上，按主键删的清理也快些。
ALTER TABLE orderflow_footprint SET (autovacuum_vacuum_insert_scale_factor=0.05);
ALTER TABLE klines_seconds SET (autovacuum_vacuum_insert_scale_factor=0.05);
