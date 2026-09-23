//! 连接池那层数据库死线的回归。
//!
//! 这一条是拿线上换来的：`after_connect` 里原本用 `sqlx::query` 一口气发三个 `SET`，
//! 扩展协议不许一条语句里放多个命令，于是**每一条连接都建不起来**——服务起得来，
//! 却一个请求都接不了。所以这里不去断言「代码长什么样」，而是真的建一次池、
//! 在真连接上把三个设置读回来。
use sqlx::Row;

fn url()->String {std::env::var("KANPAN_TEST_DATABASE_URL").expect("Run ops/test.py; an isolated database is required")}

#[tokio::test]
async fn serve_connections_carry_the_database_deadlines() {
 let pool=kanpan_api::pool_options(true).connect(&url()).await.expect("after_connect must not fail the connection");
 let row=sqlx::query("SELECT current_setting('statement_timeout') AS s,current_setting('lock_timeout') AS l,current_setting('idle_in_transaction_session_timeout') AS i")
  .fetch_one(&pool).await.unwrap();
 assert_eq!(row.get::<String,_>("s"),"20s");
 assert_eq!(row.get::<String,_>("l"),"5s");
 assert_eq!(row.get::<String,_>("i"),"30s");
}

/// worker 与 migrate 走的是这一档：长查询和建索引不该被二十秒打断。
#[tokio::test]
async fn worker_connections_keep_the_server_defaults() {
 let pool=kanpan_api::pool_options(false).connect(&url()).await.unwrap();
 let value:String=sqlx::query_scalar("SELECT current_setting('statement_timeout')").fetch_one(&pool).await.unwrap();
 assert_ne!(value,"20s");
 // 发呆的死线例外：worker 的事务不许停在半路攥着锁（审查 A6）。
 let idle:String=sqlx::query_scalar("SELECT current_setting('idle_in_transaction_session_timeout')").fetch_one(&pool).await.unwrap();
 assert_eq!(idle,"1min");
}

/// pgvector 0.8 的 `hnsw.iterative_scan` 默认是 `off`：HNSW 先按 ef_search 取回固定的
/// 一批候选，**然后**才拿 WHERE 里的 market/timeframe/source 去过滤，被过滤掉的不会补。
/// 实测要一百行只回六行——不是「没有更像的了」，是被截断了。
///
/// 这两条对 serve 和 worker 都要挂（找相似图形的那条近邻查询跑在 worker 里），而且和上面
/// 三条死线一样必须**一条语句一个 SET**。所以这里也是真的建一次池、把值读回来。
#[tokio::test]
async fn every_connection_lets_the_vector_index_keep_scanning() {
 for deadlines in [true,false] {
  let pool=kanpan_api::pool_options(deadlines).connect(&url()).await.expect("after_connect must not fail the connection");
  let row=sqlx::query("SELECT current_setting('hnsw.iterative_scan') AS s,current_setting('hnsw.max_scan_tuples') AS m").fetch_one(&pool).await.unwrap();
  assert_eq!(row.get::<String,_>("s"),"strict_order");
  assert_eq!(row.get::<String,_>("m"),"20000");
 }
}
