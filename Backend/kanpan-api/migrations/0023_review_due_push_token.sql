-- 复盘到点的推送单独一类 token（第三批第 25 项：到点提醒只走一个通道）。
--
-- 以前复盘到点的 APNs 推给 kind='alerts' 的 token——每台开了通知权限的手机都注册了它，
-- 而手机上同时还排着一条到点就响的本地日历通知。今天没有 APNs 密钥所以没重，密钥一插上
-- 就是锁屏上同一件事两条。现在服务端只把复盘到点推给 kind='reviewDue' 的 token：只有
-- 选了「服务端推送」这条通道的客户端才注册它（那时它不再排本地通知），老客户端从来不注册，
-- 照旧只靠本地那一条。一台设备在哪条通道上，由它注册了哪一类 token 决定，重不了。
--
-- 放宽 CHECK 走两步（README：加 CHECK 要 NOT VALID 再 VALIDATE）：新约束是旧约束的超集，
-- 现有行全部满足；表是每人每设备几行的小表。
ALTER TABLE device_push_tokens DROP CONSTRAINT IF EXISTS device_push_tokens_kind_check,
 ADD CONSTRAINT device_push_tokens_kind_check CHECK (kind IN ('alerts','liveActivity','widget','reviewDue')) NOT VALID;
ALTER TABLE device_push_tokens VALIDATE CONSTRAINT device_push_tokens_kind_check;
