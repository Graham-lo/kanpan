# 迁移怎么写

## 0001–0010 一个字都不能改

这十条已经在线上那台跑过了。sqlx 记的是每条迁移的**校验和**，改动任何一个字符——
包括补一个注释、改一个大小写——都会让下一次 `kanpan-api migrate` 直接报
`migration was previously applied but has been modified` 并停在那里，服务起不来。
写错了就再加一条新的迁移去纠正，不要回头改旧的。

## 0011 起：新迁移必须是无锁的

审查（2026-09-20 第五轮 D-01）指出现有迁移里的 `CREATE INDEX` 与 `ALTER TABLE`
会拿表锁：建索引要扫全表，扫的这段时间里所有写这张表的请求都在排队。眼下只有几个
用户、表也小，所以不是发布阻断；但库只会越来越大，规矩从 0011 开始立下：

- **建索引一律 `CREATE INDEX CONCURRENTLY IF NOT EXISTS`。** 它不挡写。
  代价是它**不能在事务里跑**，所以这样的迁移**第一行必须是** `-- no-transaction`
  ——sqlx 认这条魔法注释，看到它就不把整个文件包进 `BEGIN/COMMIT`。
  没有这一行的 `CREATE INDEX CONCURRENTLY` 会在运行时报
  `CREATE INDEX CONCURRENTLY cannot run inside a transaction block`。
  另外：一条不在事务里的迁移**中途失败不会回滚**，Postgres 会留下一个 `INVALID`
  的索引。重跑前先 `DROP INDEX IF EXISTS`，或者靠 `IF NOT EXISTS` 加手工清理。
- **加列只能是可空列，或者带常量默认值的列。** PostgreSQL 11 起
  `ADD COLUMN ... NOT NULL DEFAULT <常量>` 不重写表，是安全的；
  `NOT NULL` 而没有默认值会被现有行顶回来，`DEFAULT <函数>`（比如 `now()`）
  则会重写整张表。0010 的 `device_kind NOT NULL DEFAULT 'phone'` 就是正例。
- **改列类型、加 `CHECK`、加外键、`DROP COLUMN` 都要单独想一遍。**
  `ADD CONSTRAINT ... NOT VALID` 加完再 `VALIDATE CONSTRAINT` 是两步走的常见做法。
- 一条迁移只做一件事；回滚靠备份加一条新迁移，不是 down 脚本（这里没有 down 脚本）。

`cargo test migrations_after_0010_are_lock_free`（在 `src/lib.rs`）会扫编号 ≥ 0011
的文件，替你把前两条挡住。

## 升级前先看有没有长事务

`CREATE INDEX CONCURRENTLY` 不挡写，但它**要等自己开始之前就已经在跑的事务全部结束**
才算完；一个忘了提交的 `psql` 窗口就能把它挂在那儿。所以 `ops/install.py` 在跑
migrate 之前会只读地查一次 `pg_stat_activity`，把开了超过 60 秒的事务打印出来并
**中止安装**；确认这些事务无害、要带着它们继续，就用 `python3 ops/install.py --force`。

## 复盘列表的那条游标索引不需要新迁移

D.4 提到 `src/review.rs` 的列表查询（owner 等值 + `(submitted,id)` 游标 +
`ORDER BY submitted DESC,id DESC LIMIT 51`）在 0007 里没有对应索引。它**在 0003 里**：
`CREATE INDEX review_records_page ON review_records(user_id,submitted DESC,id DESC)`
——前导等值列加上完全一致的排序，正是这条查询要的形状。所以本轮没有新增 0011；
`q`／`todo` 那些表达式过滤仍然是过滤，不指望索引。
