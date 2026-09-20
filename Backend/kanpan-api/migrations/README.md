# 迁移怎么写

## 前提：vector 扩展要超级用户先建

`0001_accounts.sql` 的第一句是 `CREATE EXTENSION IF NOT EXISTS vector`。pgvector
（这里是 0.8.2）**不是 trusted 扩展**，建它必须是超级用户——所以「拿一个非特权角色跑
迁移」在这条链的第一句就会失败，后面九条根本轮不到。

线上那台是用容器的 `POSTGRES_USER=kanpan_admin`（超级用户）跑 migrate 的，全新安装
自然走得通。`ops/install.py` 在 migrate 之前会只读地确认一次：扩展已经在、或者迁移角色
是超级用户，两者都不成立就直接报错说明，而不是让人去猜第一句为什么失败。

换到别的库上跑之前，先手工执行一次：

```sql
CREATE EXTENSION vector;
```

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
- **删索引一律 `DROP INDEX CONCURRENTLY IF EXISTS`。** 普通的 `DROP INDEX` 要拿表上的
  `ACCESS EXCLUSIVE`：它先排在当前的长查询后面，而它排队的时候，后面**所有**读写
  都堵在它后面。`0012` 删 `sync_objects_prefix` 走的就是 CONCURRENTLY。
- **`-- no-transaction` 的文件里只许放一条语句。** 这一条不写下来一定会踩：sqlx 即使
  在 no-transaction 模式下，也是把整份文件当**一条简单查询**发给 Postgres 的，而
  Postgres 对「一条简单查询里有多个命令」会自己包一个隐式事务——于是 CONCURRENTLY
  照样报 `cannot run inside a transaction block`，而且报得莫名其妙。
  这就是建索引与删索引被拆成 `0011`、`0012` 两个文件的原因。
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

## 为什么非 CONCURRENTLY 不可：两边的超时是不对称的

在真库上量过一次，结论比「建索引慢」严重得多：

- **migrate 那条连接没有 `lock_timeout`**（`src/lib.rs` 的 `pool_options(false)`：
  worker 和 migrate 都不挂死线，因为它们本来就该跑很久）。所以一条普通的
  `CREATE INDEX` / `ALTER TABLE` 在拿不到 `ACCESS EXCLUSIVE` 时会**一直等下去**。
- **但 serve 那条连接有 `lock_timeout='5s'`。** 迁移在锁队列里排着的时候，排在它
  后面的读写一样拿不到锁，5 秒一到就是
  `canceling statement due to lock timeout` → `src/error.rs` 的
  `From<sqlx::Error>` 把它折成 503 `temporarily_unavailable`。

也就是说：**迁移自己一声不吭地等，用户那边先开始报 503。** 一条锁着的迁移不会把自己
拖死，它拖死的是所有正在用 app 的人，而且升级日志上什么都看不出来。
这就是 0011 起把 CONCURRENTLY 写成硬规矩的原因，也是上面那道长事务检查的原因。

## 已有的两条结论

- **复盘列表的游标索引不需要新迁移。** D.4 提到 `src/review.rs` 的列表查询（owner 等值
  + `(submitted,id)` 游标 + `ORDER BY submitted DESC,id DESC LIMIT 51`）在 0007 里没有
  对应索引。它**在 0003 里**：`CREATE INDEX review_records_page ON
  review_records(user_id,submitted DESC,id DESC)`——前导等值列加上完全一致的排序，
  正是这条查询要的形状。`q`／`todo` 那些表达式过滤仍然是过滤，不指望索引。
- **0007 的 `sync_objects_prefix` 是一条死索引，0012 里删掉了。** 它用的
  `text_pattern_ops` 按字节序比较，而库是 `en_US.utf8`、`src/sync.rs` 的 bootstrap 又要
  `ORDER BY id LIMIT 101`（默认排序规则），两者对不上，规划器永远走主键、把前缀条件
  降级成 Filter。实测 `Rows Removed by Filter: 200`，索引一次都没被用过。

## 0011 / 0012 / 0013 上线怎么排

sqlx 按编号顺序一条一条跑，`ops/install.py` 的 `migrate` 那一步就把三条都带上了，
不用额外做什么。三条**都不需要停 worker、也不需要停 serve**：

- **0011（`-- no-transaction`）**：`CREATE INDEX CONCURRENTLY review_searches_due`。
  不挡读写。代价是它要等「自己开始之前就已经在跑的事务」全部结束——所以 install.py
  会先把超过 60 秒的长事务打印出来并中止（见上一节）。
- **0012（`-- no-transaction`）**：`DROP INDEX CONCURRENTLY sync_objects_prefix`。
  同样不挡读写，而且幂等。
- **0013**：两条 `UPDATE account_sessions`，走事务、行级锁，表只有活跃会话那么几行。
  它只改还记着 `'phone'` 的行，所以重跑没有第二次效果。

**CONCURRENTLY 中途失败了怎么办。** 不在事务里的迁移失败**不会回滚**：
`CREATE INDEX CONCURRENTLY` 会在库里留下一个 `INVALID` 的索引——规划器不会用它，
但每次写入仍旧要维护它。而 sqlx 的 `_sqlx_migrations` 只记「整个文件成功了」，
所以这一条不会被记成已应用，下一次 migrate 会**从头重跑这个文件**。重跑前先清干净：

```sql
-- 有哪些半成品索引
SELECT c.relname FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid WHERE NOT i.indisvalid;
-- 清掉再重来（这一句本身也是 CONCURRENTLY，不挡线上）
DROP INDEX CONCURRENTLY IF EXISTS review_searches_due;
```

清完再跑一次 `python3 ops/install.py` 即可。0011 的 `IF NOT EXISTS` 与 0012 的
`IF EXISTS` 就是为了让这种重跑安全——新加 CONCURRENTLY 迁移时把它们带上。
