-- no-transaction
-- 订单流历史读法（src/orderflow_history/store.rs `range_sql`）第二路「窗口终点时还挂着、之后才结束」的单：
-- end_ms > 终点 AND first_seen_ms <= 终点。原来只有 (base,end_ms) 与 (base,first_seen_ms) 两条单列范围索引，
-- 规划器选了后者——first_seen_ms <= 终点就是这只 base 三天里的全部单，逐行回表再按 end_ms 滤掉，
-- 终点是「此刻」时一行都不剩：线上 ETH 一次回表 5.3 万行、4.8 秒（2026-10-05 慢查询 28 条）。
-- 把 first_seen_ms 接在 end_ms 后面：两个条件都在索引里判（end_ms 定范围、first_seen_ms 在索引项上滤），
-- 只有真要回的行才回表。第一路（end_ms 落在窗口里）与清理（end_ms < 截止）用它的前缀，所以替代 0024 的 orderflow_orders_end。
CREATE INDEX CONCURRENTLY IF NOT EXISTS orderflow_orders_end_first_seen ON orderflow_orders(base,end_ms,first_seen_ms);
