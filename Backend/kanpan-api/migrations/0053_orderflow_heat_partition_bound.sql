-- 深度热力原始快照 orderflow_heat 改按 6 小时分区（2026-10-08）的第一步：给现在这张表加一道「bucket_ms < T」的边界约束。
-- 原来每分钟按行删过期快照、超预算时再按 6 小时一截按行删，十几 GB 的表上删除与随后的 VACUUM 跟读、并段抢磁盘
-- （线上一小时二十多条 1–2 秒的慢语句）。分区之后过期与超预算都是整张分区 DROP，不再按行删。
--
-- T 是此刻至少 1 小时之后的第一个 6 小时整点（UTC）。这一句 NOT VALID：只拿一瞬间的锁、不扫表，旧二进制照常写入
-- （新写入的行本来就都在 T 之前）。0056 验证它（扫一遍旧表、不挡读写），0057 把旧表整个挂成 [MINVALUE, T) 那一个分区——
-- 有这道验证过的约束，ATTACH 不再扫表；T 起的快照写进新的 6 小时分区。三步要在 T 之前跑完（install.py 一口气跑完，几分钟）；
-- 万一中途停下、又过了 T，旧二进制写 T 以后的快照会被这道约束挡掉：先 `ALTER TABLE orderflow_heat DROP CONSTRAINT orderflow_heat_legacy_bound` 再重来。
SET LOCAL lock_timeout='10s';
DO $$
DECLARE
 block constant bigint:=21600000;
 now_ms constant bigint:=(extract(epoch FROM clock_timestamp())*1000)::bigint;
 t constant bigint:=((now_ms+3600000)/block+1)*block;
BEGIN
 EXECUTE format('ALTER TABLE orderflow_heat ADD CONSTRAINT orderflow_heat_legacy_bound CHECK (bucket_ms < %s) NOT VALID',t);
END $$;
