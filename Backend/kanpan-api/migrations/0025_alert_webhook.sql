-- 从图上加提醒：物化表补三列（Webhook、Webhook 文案、备注）。
--
-- - webhook：提醒响了往这个 http(s) 地址 POST 一份 JSON；空就不发。
-- - webhook_text：POST body 里 `text` 的模板（{品种}{价格}… 占位符）；空用默认模板。
-- - note：用户写的备注，APNs 正文和 Webhook 里都会带上。
--
-- 三列都是可空列、都带 IF NOT EXISTS：只动系统表、不重写数据、不排队
-- （README「加列只能是可空列」那一条），ops/install.py 每次部署都跑一遍 migrate 也无妨。
ALTER TABLE alert_watches ADD COLUMN IF NOT EXISTS webhook text;
ALTER TABLE alert_watches ADD COLUMN IF NOT EXISTS webhook_text text;
ALTER TABLE alert_watches ADD COLUMN IF NOT EXISTS note text;
