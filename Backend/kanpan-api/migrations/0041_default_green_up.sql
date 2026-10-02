-- 2026-10-03 用户：「现在一律默认绿涨红跌」。出厂默认从红涨改成绿涨，老用户也一次性迁过去。
--
-- 涨跌色（settings:chart 里的 `redUp`）是随账号同步的字段。客户端各自把本机那份迁一次
-- （iOS PrefsCodec v4、手机网页 / PC 网页的一次性标记），但云端存着的 `true` 不改的话，
-- 设备下次拉取会把它当成「别的设备改的」照样盖回红涨——等于没改。还没升级的 app
-- 也只认云端这一份，所以云端这边也要翻一次。
--
-- 怎么翻：和 `sync::apply_server_op` 走同一个形状——值、字段戳、对象修订号、变更日志
-- 四样一起动，设备读到的就是一条普通的服务端改动。字段戳的 deviceId 是全零（服务端
-- 自己，不是哪台真设备），时间戳取迁移这一刻：之后用户在任何一端自己切回红涨，
-- 那一下的时间更晚，按字段的 LWW 照样赢。
--
-- 只翻一次：这条迁移只会在每个库上跑一次（sqlx 记着），之后用户自己选的红涨不会再被动。
-- 只锁这几行（每人一条设置对象），不碰表结构，不违反 0011 起的无锁规矩。
WITH flipped AS (
  UPDATE sync_objects SET
    body = jsonb_set(body, '{redUp}', 'false'::jsonb),
    fields = jsonb_set(fields, '{redUp}', jsonb_build_object(
      'revision', revision + 1,
      'timestamp', (extract(epoch FROM clock_timestamp()) * 1000)::bigint,
      'logical', 0,
      'deviceId', '00000000-0000-0000-0000-000000000000',
      'operationId', gen_random_uuid()::text)),
    revision = revision + 1,
    changed_at = now()
  WHERE collection = 'settings' AND id = 'chart' AND NOT deleted
    AND jsonb_typeof(body) = 'object' AND jsonb_typeof(fields) = 'object'
    AND body->'redUp' IS DISTINCT FROM 'false'::jsonb
  RETURNING user_id, collection, id, revision, deleted
)
INSERT INTO sync_changes(user_id, collection, object_id, revision, deleted)
SELECT user_id, collection, id, revision, deleted FROM flipped;
