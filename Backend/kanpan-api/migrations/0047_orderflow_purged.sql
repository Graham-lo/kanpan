-- 热力历史（orderflow_heat）清理删到哪了：src/orderflow_history/heat.rs `purge` / `purged` / `set_purged`。
-- 原来每小时一次、逐只 base 不设下限地删 `bucket_ms < 此刻 − 3 天`：索引从每只 base 最旧的一头走起，
-- 前几次删掉、还没被 VACUUM 收走的死索引项每一条都要回表确认（位图扫描不给死项打标记，下次照走），
-- 2026-10-06 线上一次清理 2–27 条 1–2.3 秒的慢语句、离上次 VACUUM 越久越多。
-- 改成每分钟只删 [上次删到的时刻, 此刻 − 3 天) 这一截，下沿记在这里，重启接着用。
CREATE TABLE IF NOT EXISTS orderflow_purged (
 target text PRIMARY KEY,
 before_ms bigint NOT NULL
);
-- 老版本每小时清理一次、每次都删到「此刻 − 3 天」：部署时最近一次清理不早于 70 分钟以前，
-- 从这里接着删不会漏下没删的。新库没有热力数据，起点无所谓。
INSERT INTO orderflow_purged(target,before_ms)
 VALUES('heat',(extract(epoch FROM now())*1000)::bigint-3*86400000-70*60000)
 ON CONFLICT(target) DO NOTHING;
