pub mod auth;
pub mod crypto;
pub mod error;
pub mod sync;
pub mod sync_validation;
pub mod instruments;
pub mod http;
pub mod review;
pub mod review_worker;
pub mod search;
pub mod binance_gate;
pub mod market_meta;
pub mod market_depth;
pub mod orderflow_instruments;
pub mod orderflow_history;
pub mod market_relay;
pub mod venues;
pub mod sector_history;
pub mod oi_archive;
pub mod maintenance;
pub mod alerts;
pub mod apns;
pub mod live_activity;
pub mod share;
pub mod watch_move;
pub mod export;
pub mod legal;
pub mod supervise;
use axum::{Router,Json,routing::get,extract::DefaultBodyLimit};
use std::time::Duration;
use serde_json::{Value,json};
use sqlx::{PgPool,Postgres,Transaction};
use std::sync::Arc;
use uuid::Uuid;
use error::Result;

#[derive(Clone)]
pub struct AppState {
 pub pool: PgPool,
 pub secrets: Arc<crypto::Secrets>,
 pub dummy_hash: Arc<String>,
}
impl AppState {
 pub async fn personal(&self, owner: Uuid) -> Result<Transaction<'_,Postgres>> {
  let mut tx=self.pool.begin().await?;
  let active:Option<Uuid>=sqlx::query_scalar("SELECT id FROM account_users WHERE id=$1 AND disabled_at IS NULL FOR SHARE").bind(owner).fetch_optional(&mut *tx).await?;
  if active.is_none() {return Err(error::ApiError::unauthorized())}
  sqlx::query("SELECT set_config('kanpan.user_id',$1,true)").bind(owner.to_string()).execute(&mut *tx).await?;
  Ok(tx)
 }
}
pub fn envelope(value: Value) -> Json<Value> { Json(json!({"data":value})) }
/// worker / migrate 连接的事务内发呆上限，见 `pool_options`。
pub const WORKER_IDLE_IN_TRANSACTION:&str="SET idle_in_transaction_session_timeout='60s'";
/// 建连接池。`deadlines` 为真时给每条新连接挂上数据库自己的那层死线。
///
/// 三层截止里的最后一层：请求体有 512 KiB 上限、请求有 30 秒超时，但那两层只管到
/// Rust 这边——超时之后把 future 丢掉，Postgres 那条语句仍在服务器上跑。池子只有八条
/// 连接，一条锁等、一条全表扫就能把三个人一起卡住，所以在连接上直接挂死线：
/// 语句 20 秒、锁等 5 秒、事务里发呆 30 秒。都比上面那层 30 秒短，报错才落在业务这边。
///
/// 只有 `serve` 该挂。worker 与 migrate 都是独立进程、独立连接池，占不到 API 那八条连接：
/// worker 的板块历史、OI 归档、日线收盘、复盘计算本来就是长查询加批量写，migrate 建索引
/// 改表也会跑很久、要排队等锁——给它们挂二十秒只会让任务和升级半路断在中间。
///
/// 三条 `SET` 必须**一条一条**发。塞进同一个 `sqlx::query` 里会被 Postgres 顶回来
/// （扩展协议不许一条语句里放多个命令：`cannot insert multiple commands into a prepared
/// statement`），而 `after_connect` 一报错就是**每一条连接都建不起来**——服务起得来，
/// 却一个请求都接不了。`sqlx::raw_sql` 能一次发三条，但它在 `after_connect` 这个
/// 高阶闭包里过不了 `Executor` 的生命周期，所以这里就按三条发。
///
/// worker 与 migrate 只挂一条「事务里发呆 60 秒」（审查 A6），理由见函数体里的注释。
pub fn pool_options(deadlines: bool) -> sqlx::postgres::PgPoolOptions {
 sqlx::postgres::PgPoolOptions::new().max_connections(8).after_connect(move|conn,_|Box::pin(async move {
  if deadlines {
   for sql in ["SET statement_timeout='20s'","SET lock_timeout='5s'","SET idle_in_transaction_session_timeout='30s'"] {
    sqlx::query(sql).execute(&mut *conn).await?;
   }
  } else {
   // worker 与 migrate 不设语句和锁的死线，但**发呆**的死线要有（审查 A6）：一个在事务里
   // 停住不动的连接（任务卡在某个 await 上、忘了 commit）会一直攥着它拿到的行锁和同步闸，
   // API 那边同一个人的推送就一直排在它后面。worker 的每个事务都是在出站之前就提交的
   // （review_worker、search、alerts::record_fired），正常路径上从不在事务里等网络；
   // 60 秒给得很宽。migrate 的语句一条接一条发，也不会在事务里发呆。
   sqlx::query(WORKER_IDLE_IN_TRANSACTION).execute(&mut *conn).await?;
  }
  // 这两条对 serve 和 worker 都要挂：找相似图形的近邻查询跑在 worker 里。
  //
  // pgvector 0.8 的 hnsw.iterative_scan 默认是 off：HNSW 只按 ef_search 取回固定的一批
  // 候选，**然后**才拿 WHERE 里的 market/timeframe/source 去过滤。过滤掉的不会补，于是
  // 要一百行只回六行——不是"没有更像的了"，是被截断了。strict_order 让它在不够的时候
  // 继续往下迭代，而且仍旧严格按距离递增吐行（relaxed_order 快一点，但吐出来的顺序不是
  // 严格递增的，我们外层还要按 distance 定序，不能要）。
  // max_scan_tuples 是配套的刹车：过滤条件筛得太狠时，迭代会一直往下走，这里封顶。
  for sql in ["SET hnsw.iterative_scan='strict_order'","SET hnsw.max_scan_tuples='20000'"] {
   sqlx::query(sql).execute(&mut *conn).await?;
  }
  Ok(())
 }))
}
/// The market fallback host answers open interest and nothing else. It keeps no
/// accounts, so it gets no database — which is why these routes are split out
/// rather than served by `router` with a pool nobody would query.
pub fn metrics_router() -> Router {
 Router::new().route("/health",get(||async{envelope(json!({"ok":true}))}))
  .merge(oi_archive::routes()).merge(venues::routes())
}
pub fn router(s: AppState) -> Router {
 Router::new().route("/health",get(||async{envelope(json!({"ok":true}))}))
  .merge(auth::routes()).merge(export::routes()).merge(legal::routes()).merge(sync::routes()).merge(alerts::routes()).merge(live_activity::routes()).merge(share::routes()).merge(review::routes()).merge(search::routes()).merge(market_meta::routes()).merge(market_depth::routes()).merge(orderflow_instruments::routes()).merge(orderflow_history::routes()).merge(market_relay::routes()).merge(sector_history::routes()).merge(oi_archive::routes()).merge(venues::routes())
  .layer(DefaultBodyLimit::max(512*1024))
  // 在超时那层里面：排队等名额的时间也算进三十秒。
  .layer(axum::middleware::from_fn(session_slots))
  // 一个请求最多占住一条连接三十秒。池子只有八条连接，一个卡死的查询就能把
  // 剩下的人一起挡在门外；超时之后连接回池，客户端本来也早就重试了。
  .layer(tower_http::timeout::TimeoutLayer::with_status_code(axum::http::StatusCode::REQUEST_TIMEOUT,Duration::from_secs(30)))
  .with_state(s)
}

/// 同一把登录令牌（一台设备的一个会话）同时最多有几个请求在处理。
pub const SESSION_SLOTS:usize=3;
type Slots=std::sync::Mutex<std::collections::HashMap<u64,Arc<tokio::sync::Semaphore>>>;
static SESSION_GATES:std::sync::LazyLock<(std::collections::hash_map::RandomState,Slots)>=std::sync::LazyLock::new(Default::default);
/// 一个人不能把连接池一个人占满。
///
/// 池子八条连接给所有人共用，而几乎每条带登录的路都要在事务里拿**这个人自己的**锁
/// （同步 / 复盘 / 分享各一把 advisory 锁，还有账号行、同步对象行的行锁；worker 记已触发
/// 提醒时也拿同步那一把）。那把锁一旦被慢事务攥着，这个人同时发来的每个请求都会
/// 先拿一条连接、再在锁上干等到锁等上限（5 秒）——他发十六个，八条连接就全被他占着等，
/// 其他人一个都进不来。压测：锁住一个账号、他同时发 16 个请求，其他人的 80 个请求从
/// 0.2 秒拖到 9.8 秒。
///
/// 所以按令牌限并发：同一把 Bearer 令牌同时最多 [`SESSION_SLOTS`] 个请求往下走，多出来的
/// 在进程里排队，**不占连接**。按令牌而不是按账号，是因为这里还没查库、不知道是谁；
/// 一个账号每类设备只准一台在线，实际就是一两台设备。令牌只取哈希当键，内存里不留原文。
/// 伪造的令牌只限得住它自己。名额在处理函数返回答复头时就还——流式的答复体慢慢发，
/// 不占名额（那段时间也不占连接）。
async fn session_slots(req:axum::extract::Request,next:axum::middleware::Next)->axum::response::Response {
 use std::hash::BuildHasher;
 let Some(token)=req.headers().get("authorization").and_then(|h|h.to_str().ok()).and_then(|v|v.strip_prefix("Bearer ")) else {return next.run(req).await};
 let (hasher,gates)=&*SESSION_GATES;let key=hasher.hash_one(token);
 let gate=gates.lock().unwrap_or_else(|e|e.into_inner()).entry(key).or_insert_with(||Arc::new(tokio::sync::Semaphore::new(SESSION_SLOTS))).clone();
 let lease=SessionLease{key,gate};
 let _slot=lease.gate.acquire().await.expect("Session gate is never closed");
 next.run(req).await
}
/// 请求结束（包括超时那层把它半路丢掉）时，没人再用这把令牌的闸就从表里拿掉：
/// 表的大小跟着在途的令牌数走，不随时间长。
struct SessionLease {key:u64,gate:Arc<tokio::sync::Semaphore>}
impl Drop for SessionLease {
 fn drop(&mut self) {
  let mut map=SESSION_GATES.1.lock().unwrap_or_else(|e|e.into_inner());
  // 表里一份、这里一份：别的请求都已经不拿着它了（拿的时候也要先过这把锁）。
  if Arc::strong_count(&self.gate)==2 {map.remove(&self.key);}
 }
}
#[cfg(test)]
mod session_slots_tests {
 use super::*;
 use axum::{body::Body,http::Request,routing::get};
 use std::sync::atomic::{AtomicUsize,Ordering};
 use tower::ServiceExt;
 fn gate_open(token:&str)->bool {use std::hash::BuildHasher;let (h,g)=&*SESSION_GATES;g.lock().unwrap().contains_key(&h.hash_one(token))}
 /// 同一把令牌同时来 12 个请求：同时在处理的不超过名额，全部做完后闸从表里拿掉；
 /// 另一把令牌不受它排队的影响。
 #[tokio::test(flavor="multi_thread",worker_threads=4)]
 async fn one_token_is_held_to_its_slots_and_its_gate_is_released() {
  static NOW:AtomicUsize=AtomicUsize::new(0);static PEAK:AtomicUsize=AtomicUsize::new(0);
  let app:Router=Router::new().route("/slow",get(||async {let n=NOW.fetch_add(1,Ordering::SeqCst)+1;PEAK.fetch_max(n,Ordering::SeqCst);tokio::time::sleep(Duration::from_millis(100)).await;NOW.fetch_sub(1,Ordering::SeqCst);"ok"}))
   .route("/fast",get(||async {"ok"})).layer(axum::middleware::from_fn(session_slots));
  let token="slots-test-token-a";
  let mut set=tokio::task::JoinSet::new();
  for _ in 0..12 {let app=app.clone();set.spawn(async move {app.oneshot(Request::get("/slow").header("authorization",format!("Bearer {token}")).body(Body::empty()).unwrap()).await.unwrap().status()});}
  tokio::time::sleep(Duration::from_millis(30)).await;
  let t=std::time::Instant::now();
  let other=app.clone().oneshot(Request::get("/fast").header("authorization","Bearer slots-test-token-b").body(Body::empty()).unwrap()).await.unwrap();
  assert_eq!(other.status(),200);assert!(t.elapsed()<Duration::from_millis(50),"another token waited {:?}",t.elapsed());
  while let Some(r)=set.join_next().await {assert_eq!(r.unwrap(),200);}
  assert_eq!(PEAK.load(Ordering::SeqCst),SESSION_SLOTS);
  assert!(!gate_open(token),"a finished token left its gate behind");
 }
 /// 超时那层把排队中、处理中的请求半路丢掉，闸同样要还、要从表里拿掉。
 #[tokio::test]
 async fn a_request_dropped_mid_flight_releases_its_gate() {
  let app:Router=Router::new().route("/hang",get(||async {std::future::pending::<()>().await;"never"})).layer(axum::middleware::from_fn(session_slots))
   .layer(tower_http::timeout::TimeoutLayer::with_status_code(axum::http::StatusCode::REQUEST_TIMEOUT,Duration::from_millis(50)));
  let token="slots-test-token-c";
  let mut set=tokio::task::JoinSet::new();
  for _ in 0..6 {let app=app.clone();set.spawn(async move {app.oneshot(Request::get("/hang").header("authorization",format!("Bearer {token}")).body(Body::empty()).unwrap()).await.unwrap().status()});}
  while let Some(r)=set.join_next().await {assert_eq!(r.unwrap(),408);}
  assert!(!gate_open(token),"timed-out requests left the gate behind");
  // 名额也都还回来了：再来一个照样能进（仍然挂住、再超时，而不是排不上队）。
  let st=app.oneshot(Request::get("/hang").header("authorization",format!("Bearer {token}")).body(Body::empty()).unwrap()).await.unwrap().status();
  assert_eq!(st,408);assert!(!gate_open(token));
 }
}

pub mod review_domain;
pub mod review_market;

#[cfg(test)]
mod migrations {
 /// 0001–0010 已经在线上跑过，sqlx 校验校验和，一个字都不能改；这条只管 0011 起的
 /// 新迁移。规矩写在 `migrations/README.md`：建索引一律 CONCURRENTLY（因此整个文件不能
 /// 在事务里，首行必须是 `-- no-transaction`），加列一律可空或者带常量默认值。
 #[test] fn migrations_after_0010_are_lock_free() {
  let dir=std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("migrations");
  let mut names:Vec<_>=std::fs::read_dir(&dir).expect("migrations directory").map(|e|e.expect("directory entry").file_name().to_string_lossy().into_owned()).collect();
  names.sort();
  for name in names {
   let Some(number)=name.split('_').next().and_then(|v|v.parse::<u32>().ok()) else {continue};
   if number<=10 || !name.ends_with(".sql") {continue}
   let sql=std::fs::read_to_string(dir.join(&name)).expect("readable migration");
   if let Err(problem)=check(&name,&sql) {panic!("{problem}")}
  }
 }

 /// 已经上线、校验和钉死了的例外。0023 把 NOT VALID 与 VALIDATE 放在了同一个事务里：
 /// ADD CONSTRAINT 拿的 ACCESS EXCLUSIVE 要到提交才放，VALIDATE 的整表扫描就是在这把锁
 /// 底下做的，NOT VALID 一点没省下来。那张表只有每人几行推送令牌，扫一遍是毫秒级，
 /// 而改文件会让 sqlx 在每台已经跑过它的库上拒绝启动，所以留着、只在这里记一笔。
 const APPLIED_EXCEPTIONS:&[&str]=&["0023_review_due_push_token.sql"];

 /// 一份 0011 起的迁移守不守规矩。不守就说出哪条、为什么。
 fn check(name:&str,sql:&str)->Result<(),String> {
  // 注释里写着「CREATE INDEX」不算语句。空白一律压成一个空格，大小写不论——
  // `CREATE\n  UNIQUE INDEX` 和 `create unique index` 是同一句话。
  let body=sql.lines().filter(|l|!l.trim_start().starts_with("--")).collect::<Vec<_>>().join("\n").to_lowercase();
  let body=body.split_whitespace().collect::<Vec<_>>().join(" ").replace(" (","(");
  let statements:Vec<&str>=body.split(';').map(str::trim).filter(|s|!s.is_empty()).collect();
  // 同一事务刚创建的表上建索引不会锁旧表；已有表仍必须 CONCURRENTLY。
  let fresh_tables:Vec<&str>=body.split("create table ").skip(1).filter_map(|v|{
   let v=v.strip_prefix("if not exists ").unwrap_or(v);
   v.split([' ','(']).next().filter(|t|!t.is_empty())
  }).collect();
  for statement in &statements {
   for (verb,rest) in index_clauses(statement) {
    let on_fresh=verb=="create" && fresh_tables.iter().any(|table|statement.contains(&format!(" on {table}(")));
    if !rest.starts_with("concurrently ") && !on_fresh {
     return Err(if verb=="create" {format!("{name}：建索引要 CONCURRENTLY，否则升级时整张表的写都在排队")}
      else {format!("{name}：删索引也要 CONCURRENTLY，普通 DROP INDEX 要拿表上的 ACCESS EXCLUSIVE")});
    }
   }
  }
  let concurrent=statements.iter().any(|s|index_clauses(s).iter().any(|(_,rest)|rest.starts_with("concurrently ")));
  if concurrent && sql.lines().next().map(str::trim)!=Some("-- no-transaction") {
   return Err(format!("{name}：CONCURRENTLY 不能在事务里跑，首行必须是 -- no-transaction"));
  }
  // 不在事务里的那种迁移，一个文件只许放一条语句。sqlx 仍旧是把整份文件当**一条**
  // 简单查询发过去，而 Postgres 对「一条简单查询里有多个命令」会自己包一个隐式事务
  // ——于是 CONCURRENTLY 照样会报 cannot run inside a transaction block。
  if sql.starts_with("-- no-transaction") && statements.len()!=1 {
   return Err(format!("{name}：不在事务里的迁移一个文件只能放一条语句（多条会被 Postgres 包进隐式事务）"));
  }
  for statement in &statements {
   for column in added_columns(statement) {
    if column.contains("not null") && !column.contains("default ") {
     return Err(format!("{name}：加 NOT NULL 列要带常量默认值，否则旧行会把迁移顶回来"));
    }
    if let Some(default)=column.split("default ").nth(1) && is_function_call(default) {
     return Err(format!("{name}：加列的默认值要是常量，函数默认值（clock_timestamp()、gen_random_uuid() 之类）会让整张表按行重写、全程锁表"));
    }
   }
  }
  // 同一个事务里先 NOT VALID 再 VALIDATE，等于没有 NOT VALID：前一句拿的 ACCESS EXCLUSIVE
  // 要到提交才放，整表扫描还是在它底下做。VALIDATE 要单独一个文件。
  if body.contains(" not valid") && body.contains("validate constraint") && !APPLIED_EXCEPTIONS.contains(&name) {
   return Err(format!("{name}：NOT VALID 和 VALIDATE CONSTRAINT 在同一个事务里，扫描照样在 ACCESS EXCLUSIVE 底下做；VALIDATE 挪到下一份迁移"));
  }
  Ok(())
 }

 /// 一条语句里的每处 `create [unique] index …` / `drop index …`，连同它后面的正文。
 /// DO 块里 EXECUTE 的动态 SQL 也算——它们一样拿锁。
 fn index_clauses(statement:&str)->Vec<(&'static str,&str)> {
  let mut found=Vec::new();
  for (verb,pattern) in [("create","create index "),("create","create unique index "),("drop","drop index ")] {
   let mut from=0;
   while let Some(at)=statement[from..].find(pattern) {
    let start=from+at+pattern.len();
    found.push((verb,&statement[start..]));
    from=start;
   }
  }
  found
 }

 /// ALTER TABLE 里每一个加列动作的列定义。`ADD COLUMN` 的 COLUMN 可以省，
 /// 一条 ALTER TABLE 也可以用逗号挂好几个动作。
 fn added_columns(statement:&str)->Vec<String> {
  let Some(actions)=statement.strip_prefix("alter table ") else {return Vec::new()};
  let actions=actions.strip_prefix("if exists ").unwrap_or(actions);
  let actions=actions.strip_prefix("only ").unwrap_or(actions);
  // 跳过表名。
  let Some((_,actions))=actions.split_once(' ') else {return Vec::new()};
  let mut pieces=Vec::new();let mut depth=0i32;let mut quoted=false;let mut piece=String::new();
  for c in actions.chars() {
   match c {
    '\''=>quoted^=true,
    '(' if !quoted=>depth+=1,
    ')' if !quoted=>depth-=1,
    ',' if !quoted && depth==0=>{pieces.push(std::mem::take(&mut piece));continue}
    _=>{}
   }
   piece.push(c);
  }
  pieces.push(piece);
  pieces.into_iter().filter_map(|piece|{
   let rest=piece.trim().strip_prefix("add ")?;
   let rest=rest.strip_prefix("column ").unwrap_or(rest);
   let first=rest.split([' ','(']).next().unwrap_or_default();
   if ["constraint","primary","unique","foreign","check","exclude"].contains(&first) {return None}
   Some(rest.to_owned())
  }).collect()
 }

 /// 默认值是不是一个函数调用（`now()`、`gen_random_uuid()`）。字面量、`'[]'::jsonb`、
 /// 括起来的常量表达式都不是。
 fn is_function_call(default:&str)->bool {
  let name:String=default.chars().take_while(|c|c.is_ascii_alphanumeric()||*c=='_'||*c=='.').collect();
  !name.is_empty() && !name.chars().next().is_some_and(|c|c.is_ascii_digit()) && default[name.len()..].starts_with('(')
 }

 #[test] fn the_guard_catches_what_the_rules_forbid() {
  let bad=[
   ("unique index","CREATE UNIQUE INDEX shares_one ON shares(to_user);"),
   ("line-broken index","CREATE\n  INDEX shares_two\n ON shares(to_user);"),
   ("plain drop","DROP INDEX shares_inbox;"),
   ("concurrently inside a transaction","CREATE INDEX CONCURRENTLY shares_three ON shares(to_user);"),
   ("two statements without a transaction","-- no-transaction\nCREATE INDEX CONCURRENTLY a ON shares(x);\nCREATE INDEX CONCURRENTLY b ON shares(y);"),
   ("not null without default","ALTER TABLE shares ADD COLUMN pinned boolean NOT NULL;"),
   ("not null without the COLUMN keyword","ALTER TABLE shares ADD pinned boolean NOT NULL;"),
   ("second action of one alter","ALTER TABLE shares ADD COLUMN a text, ADD COLUMN b text NOT NULL;"),
   ("function default","ALTER TABLE shares ADD COLUMN token uuid NOT NULL DEFAULT gen_random_uuid();"),
   ("validate in the same transaction","ALTER TABLE shares ADD CONSTRAINT c CHECK (x>0) NOT VALID;\nALTER TABLE shares VALIDATE CONSTRAINT c;"),
  ];
  for (why,sql) in bad {assert!(check("9999_bad.sql",sql).is_err(),"{why} 应该被拦下");}
  let good=[
   ("concurrent index alone","-- no-transaction\nCREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS a ON shares(x);"),
   ("index on a table made in the same file","CREATE TABLE IF NOT EXISTS fresh (x int);\nCREATE INDEX IF NOT EXISTS fresh_x ON fresh (x);"),
   ("nullable column","ALTER TABLE shares ADD COLUMN IF NOT EXISTS note text;"),
   ("constant default","ALTER TABLE shares ADD COLUMN IF NOT EXISTS venue text NOT NULL DEFAULT 'binance';"),
   ("cast constant default","ALTER TABLE shares ADD COLUMN lines jsonb NOT NULL DEFAULT '[]'::jsonb;"),
   ("constraint is not a column","ALTER TABLE shares ADD CONSTRAINT c CHECK (x IN ('a','b')) NOT VALID;"),
   ("index named in a comment","-- CREATE INDEX x ON shares(y)\nALTER TABLE shares ADD COLUMN note text;"),
  ];
  for (why,sql) in good {assert_eq!(check("9999_good.sql",sql),Ok(()),"{why} 不该被拦");}
 }
}

#[cfg(test)]
mod install_script {
 const INSTALL:&str=include_str!("../ops/install.py");

 /// 角色已经在的时候 CREATE ROLE 那句什么都不做；口令必须无条件按 service.env 对齐，
 /// 否则卷在、env 新生成（或从别处恢复）时服务每次连库都认证失败。
 #[test] fn the_app_role_password_follows_service_env_every_run() {
  assert!(INSTALL.lines().any(|l|l.starts_with("sql(f\"ALTER ROLE kanpan_app ")&&l.contains("PASSWORD '{password}'")),
   "install.py 要在顶层无条件 ALTER ROLE kanpan_app PASSWORD");
 }

 /// 升级时服务在跑，`enable --now` 不会重启它们；migrate 之后跑着的必须换成新二进制。
 #[test] fn running_services_are_restarted_after_migrate() {
  let migrate=INSTALL.find("kanpan-api','migrate'").expect("migrate step");
  let restart=INSTALL.find("'try-restart','kanpan-api','kanpan-worker'").expect("try-restart step");
  let reload=INSTALL.find("'daemon-reload'").expect("daemon-reload step");
  assert!(migrate<reload && reload<restart,"顺序要是 migrate → daemon-reload → try-restart");
 }

 /// 备份是 docker exec 进容器 pg_dump；开机补跑时 docker 必须已经起来。
 #[test] fn the_backup_waits_for_docker() {
  let unit=INSTALL.split("kanpan-backup.service').write_text(").nth(1).expect("backup unit");
  let unit=&unit[..unit.find("[Service]").expect("service section")];
  assert!(unit.contains("After=docker.service")&&unit.contains("Requires=docker.service"));
 }
}
