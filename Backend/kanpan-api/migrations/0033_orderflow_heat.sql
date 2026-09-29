-- 主力订单流 · 深度热力快照（2026-09-29，网页版大屏的深度热力图）。
--
-- serve 常驻跟踪的每只 base，每 5 秒把三家 × 各产品的簿在中间价 ±5% 以内按这只的步长分桶，
-- 同一交易所同一产品的几本簿（交割有好几期）合成一行；名义不到该产品门槛 5% 的桶不写，空的不写。
-- 读的时候（`GET /v1/market/orderflow/heat`）再把三家合起来、按客户端的步长与时间桶合并。
--
-- 一行是一只 base 在一家一个产品上一个 5 秒快照的整条带子，桶放在数组里，不是一桶一行：
-- 线上 578 本簿一桶一行的话每 5 秒几万行、一天上亿行，行头（24 字节）加主键索引就吃掉一大半预算；
-- 放数组每个桶只占 12 字节（桶号偏移 int4 + 买卖两个 real）。
--   price_lo       带子里最小的桶号（桶号 = floor(价格 / step)）
--   price_bucket   各桶桶号 − price_lo
--   bid_notional / ask_notional   各桶买 / 卖两侧美元名义（不到门槛 5% 的那一侧记 0）
-- 保留 3 天，每小时和订单流的滚动清理一起逐只 base 按主键删（见 heat.rs `purge`），另有体积闸门。
-- 公开行情，不挂 RLS；install.py 的 GRANT … ON ALL TABLES 给运行角色读写。
CREATE TABLE orderflow_heat (
 base text NOT NULL,
 exchange text NOT NULL,
 product text NOT NULL,
 bucket_ms bigint NOT NULL,
 step double precision NOT NULL,
 price_lo bigint NOT NULL,
 price_bucket integer[] NOT NULL,
 bid_notional real[] NOT NULL,
 ask_notional real[] NOT NULL,
 PRIMARY KEY(base,bucket_ms,exchange,product)
);
-- 一行几百到几 KB：不让 2 KB 以上的行去试压缩 / 挪进 TOAST（浮点压不动，白费 CPU），8 KB 以内原样放在页里。
ALTER TABLE orderflow_heat SET (toast_tuple_target=8160);
