-- 实时活动（Live Activity）挂在已有的推送 token 行上，不新开一张表。
--
-- 一枚 liveActivity 推送 token 说的就是「这台设备上正在跑的那一个活动」，
-- 0014 的 (user_id,device_id,kind) 本来就是它的身份，activity_id 也已经在表上了。
-- 缺的只有两件事，这一条就补这两件：
--
-- - alert_id：这个活动盯的是哪一条提醒。没有它，提醒响了就不知道该结束谁——
--   同一个人同时可能有好几条提醒，推错一个活动等于在锁屏上报一条假消息。
--   它引用 alert_watches(user_id,alert_id)，但**不加外键**：那张物化表会随着用户删提醒
--   整行消失，而「提醒没了」正是这里要读出来的状态（评估器据此结束活动、清这一行），
--   外键会把它变成级联删除，活动就静悄悄地留在锁屏上冻着。
-- - started_at：活动是什么时候开始的。八小时上限从这里算。不给 DEFAULT now()：
--   migrations/README.md 说得清楚，DEFAULT <函数> 会重写整张表；应用层写入即可，
--   旧行读的时候退回 updated_at。
--
-- 两条都是可空列、都带 IF NOT EXISTS：ops/install.py 每次部署都会跑一遍 migrate，
-- 而且加可空列只动系统表、不重写数据、不排队（README「加列只能是可空列」那一条）。
ALTER TABLE device_push_tokens ADD COLUMN IF NOT EXISTS alert_id text;
ALTER TABLE device_push_tokens ADD COLUMN IF NOT EXISTS started_at timestamptz;
