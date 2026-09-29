-- 主力订单流 · 大单与散户的分钟成交（2026-09-29，网页版副图「大单与散户累计量差」的历史）。
--
-- serve 常驻跟踪的每只 base，每分钟一行：三家全部簿的逐笔成交里，一笔 ≥ 大单线（订单流门槛的 1/50）的
-- 主动买 / 主动卖美元额，与一笔 < 1 万美元（散户）的主动买 / 主动卖美元额。这一分钟没有成交就没有行。
-- 同一分钟再写（停机交出的半分钟、重启后接着的另半分钟）加到原来那行上（见 flow.rs `insert`）。
-- 读的时候 `GET /v1/market/orderflow/flow`。保留 3 天，每小时和订单流的滚动清理一起逐只 base 按主键删（flow.rs `purge`）。
-- 公开行情，不挂 RLS；install.py 的 GRANT … ON ALL TABLES 给运行角色读写。
CREATE TABLE orderflow_flow (
 base text NOT NULL,
 minute_ms bigint NOT NULL,
 big_buy double precision NOT NULL,
 big_sell double precision NOT NULL,
 small_buy double precision NOT NULL,
 small_sell double precision NOT NULL,
 PRIMARY KEY(base,minute_ms)
);
