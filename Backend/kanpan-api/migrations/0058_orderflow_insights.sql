-- 盘口洞察只保存真实大额成交的分钟 × 簿 × 价桶聚合，不从旧分钟总额或全量足迹估算价位。
-- payload 包含各簿独立价桶、真实首末成交时刻、覆盖起点与短期重放去重指纹。
-- 与 minutes.rs 共用批写、3 天滚动和足迹磁盘预算；没有永久逐笔表。
CREATE TABLE IF NOT EXISTS orderflow_insights (
 base text NOT NULL,
 minute_ms bigint NOT NULL,
 payload jsonb NOT NULL,
 PRIMARY KEY(base,minute_ms)
);
ALTER TABLE orderflow_insights SET (autovacuum_vacuum_insert_scale_factor=0.05);
