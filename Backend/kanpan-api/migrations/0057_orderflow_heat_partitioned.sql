-- 深度热力分区的第三步（见 0053）：orderflow_heat 换成按 bucket_ms 的 RANGE 分区表，一张分区 6 小时（UTC 0 / 6 / 12 / 18 点起），
-- 名字 orderflow_heat_pYYYYMMDD_HH。原来那张表改名 orderflow_heat_legacy，整个挂成 [MINVALUE, T) 那一张分区
-- （T 取自 0053 那道已经验证过的约束，ATTACH 不扫表）；列、主键与原来一模一样，读写的 SQL 一句不用改。
--
-- 整个文件一个事务：改名、建父表、建 T 起的两张分区、挂旧表一起提交，旧二进制的写入要么落在旧表、要么落在新父表下已有的分区，
-- 不会撞上「父表下没有分区」。锁：旧表与新父表的 ACCESS EXCLUSIVE 只在这个事务里拿一瞬间（不扫表），等不到 10 秒就整个回滚。
--
-- 之后服务每分钟预建「此刻 + 下一张」分区、整张 DROP 过期的与超预算的（heat.rs `purge`）。服务跑在非属主的 kanpan_app 上，
-- 建 / 删分区要父表属主，所以包成两个 SECURITY DEFINER 函数：名字、边界都在函数里校验，只能建 6 小时对齐的
-- orderflow_heat_p… 分区、只能删 orderflow_heat 名下的分区；DROP 要拿父表的 ACCESS EXCLUSIVE，锁等不到 2 秒就放弃、下一分钟再来。
SET LOCAL lock_timeout='10s';

ALTER TABLE orderflow_heat RENAME TO orderflow_heat_legacy;
ALTER INDEX orderflow_heat_pkey RENAME TO orderflow_heat_legacy_pkey;

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
) PARTITION BY RANGE (bucket_ms);

-- 建一张 [lo, lo + 6 小时) 的分区：已经有了回 false。和原表一样 toast_tuple_target=8160（一行几 KB 的数组尽量留在堆里）。
CREATE FUNCTION orderflow_heat_ensure(name text,lo bigint,hi bigint) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp SET lock_timeout='2s' AS $$
BEGIN
 IF name IS NULL OR name !~ '^orderflow_heat_p[0-9]{8}_[0-9]{2}$' OR lo IS NULL OR lo%21600000<>0 OR hi IS DISTINCT FROM lo+21600000 THEN
  RAISE EXCEPTION 'orderflow_heat_ensure: bad partition % [%, %)',name,lo,hi;
 END IF;
 PERFORM pg_advisory_xact_lock(hashtext('orderflow_heat_ensure'));
 IF to_regclass(name) IS NOT NULL THEN RETURN false; END IF;
 EXECUTE format('CREATE TABLE %I (LIKE orderflow_heat) WITH (toast_tuple_target=8160)',name);
 EXECUTE format('ALTER TABLE %I ADD PRIMARY KEY (base,bucket_ms,exchange,product)',name);
 EXECUTE format('ALTER TABLE orderflow_heat ATTACH PARTITION %I FOR VALUES FROM (%s) TO (%s)',name,lo,hi);
 RETURN true;
END $$;

-- 新父表随即授给运行期角色：install.py 在 migrate 之后才 GRANT … ON ALL TABLES，这一瞬间旧二进制还在写，别让它报没有权限。
-- 经父表读写不查分区自己的权限，所以之后建的分区不用再授。本机测试库里没有这个角色就跳过（测试夹具自己授）。
DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='kanpan_app') THEN
  GRANT SELECT,INSERT,UPDATE,DELETE ON orderflow_heat TO kanpan_app;
 END IF;
END $$;

-- 删 orderflow_heat 名下的一张分区：不是它的分区回 false。
CREATE FUNCTION orderflow_heat_drop(name text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp SET lock_timeout='2s' AS $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_inherits i JOIN pg_class c ON c.oid=i.inhrelid
  WHERE i.inhparent='public.orderflow_heat'::regclass AND c.relname=name AND c.relnamespace='public'::regnamespace) THEN
  RETURN false;
 END IF;
 EXECUTE format('DROP TABLE public.%I',name);
 RETURN true;
END $$;

DO $$
DECLARE
 block constant bigint:=21600000;
 checked boolean;
 def text;
 t bigint;
BEGIN
 SELECT convalidated,pg_get_constraintdef(oid) INTO checked,def FROM pg_constraint
  WHERE conrelid='orderflow_heat_legacy'::regclass AND conname='orderflow_heat_legacy_bound';
 t:=substring(def FROM '<\s*''?(-?[0-9]+)')::bigint;
 IF checked IS NOT TRUE OR t IS NULL OR t%block<>0 THEN
  RAISE EXCEPTION 'orderflow_heat_legacy_bound is missing or unchecked (%): run 0053 and 0056 first',def;
 END IF;
 FOR k IN 0..1 LOOP
  PERFORM orderflow_heat_ensure('orderflow_heat_p'||to_char(to_timestamp((t+k*block)/1000) AT TIME ZONE 'UTC','YYYYMMDD_HH24'),t+k*block,t+(k+1)*block);
 END LOOP;
 EXECUTE format('ALTER TABLE orderflow_heat ATTACH PARTITION orderflow_heat_legacy FOR VALUES FROM (MINVALUE) TO (%s)',t);
END $$;
