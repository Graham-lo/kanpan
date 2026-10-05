-- 两句都只改存储参数：拿 SHARE UPDATE EXCLUSIVE，不挡读写（只和 VACUUM / DDL 互斥，正在跑的 autovacuum 会让路）。
-- orderflow_orders 只有插入和每小时的清理：缺省 autovacuum 要攒到表的 20%（三十多万行）新插入才来一次，
-- 这期间新页不在可见性图里，0048 的仅索引扫描对它们仍要回表。降到 1%（约一万六千行，线上约一小时）。
ALTER TABLE orderflow_orders SET (autovacuum_vacuum_insert_scale_factor=0.01);
-- orderflow_heat 每分钟删一分钟的快照（约 5.6 千行，见 0047）：缺省要攒到 20%（约 480 万死元组、十几个小时）
-- 才回收，空间迟迟留不给新插入、索引里死项也越积越多。降到 5%（约 120 万，四个来小时一次）。
ALTER TABLE orderflow_heat SET (autovacuum_vacuum_scale_factor=0.05);
-- market_features（找相似的窗口库）：census 走 market_features_census 的仅索引扫描（0039），但缺省要攒到 20%
-- （十几万行新窗口）才 VACUUM 一次，这期间新页不在可见性图里——线上 1h 那一条数 39 万项要回表 5 万次。降到 2%。
ALTER TABLE market_features SET (autovacuum_vacuum_insert_scale_factor=0.02);
