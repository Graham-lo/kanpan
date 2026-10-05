-- no-transaction
-- 订单流历史读法（src/orderflow_history/store.rs `range_sql`）读一只 base 一天里结束的单：0044 的
-- (base,end_ms,first_seen_ms) 把要哪几行判准了，但每行都要回表，而一只 base 的单和别的四百来只交错着
-- 散在堆里（一页 21 行里这只的只有 1–2 行）——线上 ETH / LTC 一天 2–3 万行要冷读一两万页，
-- 2026-10-06 慢查询 11 条 1.1–3.5 秒，都是手机看图时按 24 小时一窗取。
-- 把读出去的列都挂进索引（INCLUDE）：同一只 base 的单在索引里挨着，仅索引扫描读连续的叶子页，不回表。
-- 表只有插入和每小时的清理，可见性图由 0050 调快的 autovacuum 保持新鲜。替代 0044 的那条（见 0049）。
CREATE INDEX CONCURRENTLY IF NOT EXISTS orderflow_orders_end_covering ON orderflow_orders(base,end_ms,first_seen_ms) INCLUDE (venue_id,exchange,product,side,bucket,price,status,initial_notional,notional,filled_notional,threshold,vanished_notional,step,seen_ms);
