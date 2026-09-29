-- 主力订单流：挂着的单搬出历史表（2026-09-29，订单簿压测第四轮）。
--
-- 原来挂着的单和结束的单同在 orderflow_orders 里，挂着的每分钟重写一次 seen_ms / 名义：
-- 线上 200 万行、387 MB 的堆里挂着的只占 0.2%，而且散在各处（一单一行、按出现时刻落在不同页上）。
-- 停机那一句「把所有挂着的行的 seen_ms 刷到最后一次看到」要碰约 2 600 页、其中 1 900 页是冷的随机读，
-- 1.5–2.5 秒（慢语句告警的根因）；平时每分钟的重写也在历史表里攒死元组、把主键索引撑到 290 MB。
--
-- 拆成两张表：orderflow_live 只放挂着的（几千行、常驻缓存，重写与停机刷新都在这张小表上），
-- orderflow_orders 只放结束的（只插不改、按结束时刻滚动删）。一单结束时从 orderflow_live 删、往
-- orderflow_orders 插，同一条语句里做（数据修改 CTE），不会两张都有或两张都没。
-- 读回、取历史、清理各自改到对应的表（见 store.rs）。
--
-- 同一事务里把现有挂着的行搬过去。旧进程在迁移与重启之间那十几秒还会往 orderflow_orders 写挂着的行，
-- 新进程读回（store::live）与每小时清理（store::purge）时会把它们搬过来。
CREATE TABLE orderflow_live (LIKE orderflow_orders INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
ALTER TABLE orderflow_live ADD PRIMARY KEY(base,venue_id,side,bucket,first_seen_ms);
WITH moved AS (DELETE FROM orderflow_orders WHERE end_ms IS NULL RETURNING *)
INSERT INTO orderflow_live SELECT * FROM moved;

-- 成交不能多过消失掉的量（第四轮残留 3）：老规则按首次名义判成交时留下的行，成交比后来记的消失量还大，
-- 手机上成交比例封顶 1 看不出来，库里却是对不上的两个数。读回时模型也会夹（model.rs `Live::restored`），
-- 这里把已经结束的一次改齐。挂着的行从 0031 起也写消失量（原来只在结束时写）。
UPDATE orderflow_orders SET filled_notional=vanished_notional WHERE vanished_notional IS NOT NULL AND filled_notional>vanished_notional;
