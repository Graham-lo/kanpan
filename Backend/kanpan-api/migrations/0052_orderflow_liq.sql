-- 主力订单流 · 爆仓（强平）分钟聚合（2026-10-08，网页版底部「大单」抽屉里的爆仓一块）。
--
-- serve 常驻跟踪的每只 base，每分钟一行：币安（U 本位 + 币本位 `!forceOrder@arr`）与 OKX（`liquidation-orders`
-- 永续 + 交割）推来的强平单，多头被平 / 空头被平各自的美元名义之和、笔数，以及这一分钟最大的一笔
-- （名义、价格、哪一边 0 多头被平 / 1 空头被平、哪家 0 币安 / 1 OKX）。这一分钟没有强平就没有行。
-- 币安没有强平历史接口、推送是每个品种每秒最多一条的抽样，所以历史只从接入这天起攒，且币安那份是下限。
-- 同一分钟再写（迟到的、停机交出的半分钟、重启后接着的另半分钟）金额与笔数加到原来那行上、最大一笔取大（见 liq.rs `insert`）。
-- 读的时候 `GET /v1/market/orderflow/liq`。保留 3 天，每小时和订单流的滚动清理一起逐只 base 按主键删（liq.rs `purge`）。
-- 公开行情，不挂 RLS；install.py 的 GRANT … ON ALL TABLES 给运行角色读写。
CREATE TABLE orderflow_liq (
 base text NOT NULL,
 minute_ms bigint NOT NULL,
 long_usd double precision NOT NULL,
 short_usd double precision NOT NULL,
 n integer NOT NULL,
 max_usd double precision NOT NULL,
 max_price double precision NOT NULL,
 max_side smallint NOT NULL,
 max_ex smallint NOT NULL,
 PRIMARY KEY(base,minute_ms)
);
