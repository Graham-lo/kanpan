-- orderflow_flow 每分钟按 (base, minute_ms) upsert、每小时删 3 天以前的：缺省要攒到 20% 的死元组才 VACUUM，
-- 这期间改过的页不在可见性图里，0054 的仅索引扫描对它们仍要回表。降到 2%。只改存储参数：拿 SHARE UPDATE EXCLUSIVE，不挡读写。
ALTER TABLE orderflow_flow SET (autovacuum_vacuum_scale_factor=0.02);
