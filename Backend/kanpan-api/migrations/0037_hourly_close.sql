-- 全部 U 本位永续的小时收盘（2026-09-30，src/hourly_close.rs，路由 GET /v1/market/hourly-closes）。
-- 公开行情、不分账号，所以不挂 RLS；保留 8 天、由写它的那个任务滚动删。主键就是读的那条路：
-- `symbol = ANY(...) AND hour_ms BETWEEN ...`，也是「每只最新一小时」那条 GROUP BY 走的索引。
CREATE TABLE IF NOT EXISTS hourly_close(
 symbol text NOT NULL,
 hour_ms bigint NOT NULL,
 close double precision NOT NULL,
 PRIMARY KEY(symbol,hour_ms)
);
