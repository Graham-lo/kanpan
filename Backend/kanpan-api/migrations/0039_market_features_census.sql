-- no-transaction
-- 找相似索引（src/market_index.rs `census`）数「每只品种每个周期每段已有几个窗口」用的覆盖索引（2026-09-30 压测 C 路）。
-- 原来这条 GROUP BY 只能走并行顺序扫描把 68 万行、660 MB 的表（带 HNSW 向量列）整张读一遍，一次 5–7 秒；
-- 等值列在前、品种与起点在后、窗口长度放在 INCLUDE 里，整条查询只读这条索引（Index Only Scan），不回表。
CREATE INDEX CONCURRENTLY IF NOT EXISTS market_features_census
 ON market_features(market,timeframe,source,render_version,model_id,symbol,start_at) INCLUDE (bars_count);
