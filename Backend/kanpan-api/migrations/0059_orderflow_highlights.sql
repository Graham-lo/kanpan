-- 要点引擎（手机首页「异动」与行情页「盘口要点」，2026-10-10）的落盘：一只 base 一行。
--
-- payload：账本（8 bps 一格的墙 / 吃单 / 爆仓 / 触及）、30 天分位样本、小时线（带净主动）、持仓小时序列，
-- 以及「账本记到哪一刻」（重启后从这里用库里的足迹 / 爆仓分钟 / 大单补到新一任开始收之前）。
-- 每只每 30 分钟覆盖写一次；7 天没更新的行删掉（highlights/mod.rs `Job::Purge`）。体积算在足迹那条磁盘预算头上。
-- 公开行情，不挂 RLS；install.py 的 GRANT … ON ALL TABLES 给运行角色读写。
CREATE TABLE IF NOT EXISTS orderflow_highlights (
 base text PRIMARY KEY,
 updated_ms bigint NOT NULL,
 payload jsonb NOT NULL
);
