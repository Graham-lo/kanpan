-- 深度热力分区的第二步（见 0053）：验证 orderflow_heat_legacy_bound。VALIDATE 只拿 SHARE UPDATE EXCLUSIVE，
-- 扫描期间旧二进制照常读、写、删；线上约 19 GB 要扫几分钟。不设语句死线。
SET LOCAL statement_timeout=0;
ALTER TABLE orderflow_heat VALIDATE CONSTRAINT orderflow_heat_legacy_bound;
