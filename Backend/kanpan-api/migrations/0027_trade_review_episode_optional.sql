-- 交易复盘（`record.kind = 'trade'`，docs/交易复盘-协议-2026-09-27.md）不参与观点复盘的分组：
-- 它没有「同一段行情里的几条观点」这回事，也没有 episode 可挂。episode_id 放开成可空，
-- 交易复盘写 NULL；外键是默认的 MATCH SIMPLE，NULL 不参与检查，观点复盘照旧必须挂一个。
--
-- DROP NOT NULL 只改目录、不扫表不重写（加 NOT NULL 才要扫），锁拿一下就放。
ALTER TABLE review_records ALTER COLUMN episode_id DROP NOT NULL;
