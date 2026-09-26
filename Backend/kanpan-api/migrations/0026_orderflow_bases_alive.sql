-- 订单流：每只 base 的跟踪器最后一次「活着并且写进库了」的时刻。
--
-- `since_ms` 原来只在第一次写入时记一次、之后永不更新：一只 base 跟过、停了两天、再有人要，
-- `trackedSinceMs` 还是两天前，手机往左补会把没在跟的那两天当成「没有大单」画出来。
-- 有了这一列，跟踪器起跟时发现上一段断了（最后一次活着距今超过十分钟）就把 since 重置到此刻；
-- 路由也按它判断这只此刻是不是接着在跟。
--
-- 可空列、IF NOT EXISTS：只动系统表、不重写数据（README「加列只能是可空列」）。
-- 老行为 NULL = 不知道上一段断没断，照旧用原来的 since（部署那一下不把正在跟的历史起点全部清成此刻）。
ALTER TABLE orderflow_bases ADD COLUMN IF NOT EXISTS alive_ms bigint;
