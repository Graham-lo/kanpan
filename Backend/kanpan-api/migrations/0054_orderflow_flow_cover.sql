-- no-transaction
-- 大单 / 小单分钟成交（flow.rs `read`）的覆盖索引（2026-10-08）：原来按主键 (base, minute_ms) 找到行还要逐行回表取四个数，
-- 冷页随机读一条 1.0–1.5 秒（线上慢语句）。四个数放进 INCLUDE，整条查询只读这条索引（Index Only Scan）；
-- 可见性图跟得上靠 0055 把这张表的 autovacuum 调勤。
CREATE INDEX CONCURRENTLY IF NOT EXISTS orderflow_flow_cover ON orderflow_flow(base,minute_ms) INCLUDE (big_buy,big_sell,small_buy,small_sell);
