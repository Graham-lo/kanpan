-- 主力订单流 · 深度热力的预聚合（2026-09-30，网页版深度压测 C 路「热力冷读慢」的根因修复）。
--
-- 原来一次读几小时到三天，要从 `orderflow_heat`（每 5 秒一只 base 九条带子）里按主键点查几百个快照，
-- 这些行散在十几 GB 的表里，冷页随机读，2 并发 p95 就到 3 秒。现在后台每 30 秒把刚收完的时间段并成段：
--   30 秒一段    ← 原始快照（三家各产品相加，同一价格桶各快照相加）
--   150 秒一段   ← 30 秒段相加
--   900 秒一段   ← 150 秒段相加
-- 每段一行（一只 base、一个步长），存各价格桶的买 / 卖名义「总和」与这一段有几个快照（samples）；
-- 读的时候总和相加、快照数相加再相除，和原来「格里各快照取平均、某快照没有这个桶按 0 算」同一个口径（见 heat.rs）。
-- 读法：时间格是哪一段整数倍就读那一段，段没盖到的头尾再用细一级的段、最后用原始快照补。
--   price_lo       这一段里最小的桶号（桶号 = floor(价格 / step)）
--   price_bucket   各桶桶号 − price_lo
--   bid_notional / ask_notional   各桶买 / 卖名义在这一段各快照上的总和
-- 按段宽分区：三档各是一张堆表，900 秒那张很小、常驻缓存，读三天也只碰几百页。
-- 保留与清理跟原始快照一起（heat.rs `purge`）。公开行情，不挂 RLS；install.py 的 GRANT … ON ALL TABLES 给运行角色读写。
CREATE TABLE orderflow_heat_rollup (
 base text NOT NULL,
 width_ms bigint NOT NULL,
 bucket_ms bigint NOT NULL,
 step double precision NOT NULL,
 samples integer NOT NULL,
 price_lo bigint NOT NULL,
 price_bucket integer[] NOT NULL,
 bid_notional real[] NOT NULL,
 ask_notional real[] NOT NULL,
 PRIMARY KEY(base,width_ms,bucket_ms,step)
) PARTITION BY LIST (width_ms);
CREATE TABLE orderflow_heat_rollup_30s PARTITION OF orderflow_heat_rollup FOR VALUES IN (30000);
CREATE TABLE orderflow_heat_rollup_150s PARTITION OF orderflow_heat_rollup FOR VALUES IN (150000);
CREATE TABLE orderflow_heat_rollup_900s PARTITION OF orderflow_heat_rollup FOR VALUES IN (900000);
-- 后台并段按时间段取细一级的段、清理按时间删：不带 base 的时间范围。
CREATE INDEX orderflow_heat_rollup_period ON orderflow_heat_rollup(width_ms,bucket_ms);
-- 一行一两 KB 到几 KB，浮点压不动：8 KB 以内原样放在页里。
ALTER TABLE orderflow_heat_rollup_30s SET (toast_tuple_target=8160);
ALTER TABLE orderflow_heat_rollup_150s SET (toast_tuple_target=8160);
ALTER TABLE orderflow_heat_rollup_900s SET (toast_tuple_target=8160);
