use kanpan_api::{AppState,crypto::Secrets};
use std::{sync::Arc,net::SocketAddr};
#[tokio::main]
async fn main()->anyhow::Result<()> {
 tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::from_default_env()).init();
 let command=std::env::args().nth(1).unwrap_or_else(||"serve".into());
 // The market fallback host runs `metrics`: open interest only, no accounts and
 // so no database. Answered before the pool, or it would demand a connection
 // string it has no reason to hold.
 if command=="metrics" {
  kanpan_api::oi_archive::spawn_warm();
  let address:SocketAddr=std::env::var("KANPAN_BIND").unwrap_or_else(|_|"127.0.0.1:8794".into()).parse()?;
  let listener=tokio::net::TcpListener::bind(address).await?;
  axum::serve(listener,kanpan_api::metrics_router()).with_graceful_shutdown(async{let _=tokio::signal::ctrl_c().await;}).await?;
  return Ok(());
 }
 let pool=kanpan_api::pool_options(command=="serve").connect(&std::env::var("KANPAN_DATABASE_URL")?).await?;
 if command=="migrate" {sqlx::migrate!().run(&pool).await?;return Ok(())}
 let privileged:bool=sqlx::query_scalar("SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user").fetch_one(&pool).await?;
 anyhow::ensure!(!privileged,"Runtime role must not be superuser or BYPASSRLS");
 let pepper=std::env::var("KANPAN_PASSWORD_PEPPER")?.into_bytes();anyhow::ensure!(pepper.len()>=32,"Pepper must contain at least 32 bytes");
 let key=hex::decode(std::env::var("KANPAN_ENCRYPTION_KEY")?)?;
 let encryption:[u8;32]=key.try_into().map_err(|_|anyhow::anyhow!("Encryption key must be 32 bytes"))?;
 let secrets=Arc::new(Secrets{pepper,encryption});
 let dummy_hash=Arc::new(secrets.hash_password(&kanpan_api::crypto::random_token()).map_err(|_|anyhow::anyhow!("Password hashing unavailable"))?);
 let s=AppState{pool,secrets,dummy_hash};
 if command=="worker" {
  let market=scorebook_market::adapters::binance::Binance::new(s.pool.clone())?;
  let review_loop=async {loop {
   if kanpan_api::review_worker::run_one(&s,&market).await.is_err(){tracing::warn!("Review work will retry");}
   tokio::time::sleep(std::time::Duration::from_secs(2)).await;
  }};
  // Chart search is the one job a person actively waits on, and this host is
  // shared by fewer than ten of them: poll every second, not every two.
  let search_loop=async {loop {
   if kanpan_api::search::run_one(&s,&market).await.is_err(){tracing::warn!("Search work will retry");}
   tokio::time::sleep(std::time::Duration::from_secs(1)).await;
  }};
  let cleanup_loop=async {loop {
   if kanpan_api::maintenance::cleanup(&s).await.is_err(){tracing::warn!("Cleanup will retry");}
   tokio::time::sleep(std::time::Duration::from_secs(3600)).await;
  }};
  // 提醒的评估器。APNs 密钥缺席时 `from_env` 只写一行 warn 并返回 None——评估照常跑、
  // 触发状态照常写回同步日志，少的只是最后那一下推送。密钥是用户要去开发者后台下载的
  // 东西，提醒的其余部分不该等它。
  let alert_loop=kanpan_api::alerts::run(s.clone(),kanpan_api::apns::Apns::from_env());
  tokio::select! {
   _=async {tokio::join!(review_loop,search_loop,cleanup_loop,alert_loop);} => {},
   _=tokio::signal::ctrl_c()=>{}
  }
  return Ok(());

 }
 anyhow::ensure!(command=="serve","Use serve, metrics, worker or migrate");
 // Public supply data has no owner and no database; warm it before the first request.
 kanpan_api::market_meta::spawn_refresh();
 // Daily closes are history, not a cache: the sweep and the route share this
 // process so the answer served is the one the sweep just refreshed.
 kanpan_api::sector_history::spawn_daily(s.pool.clone());
 // The open interest archive keeps its own disk cache; index it before the
 // first chart asks rather than inside that request.
 kanpan_api::oi_archive::spawn_warm();
 let address:SocketAddr=std::env::var("KANPAN_BIND").unwrap_or_else(|_|"127.0.0.1:8794".into()).parse()?;
 let listener=tokio::net::TcpListener::bind(address).await?;
 axum::serve(listener,kanpan_api::router(s).into_make_service_with_connect_info::<SocketAddr>()).with_graceful_shutdown(async{let _=tokio::signal::ctrl_c().await;}).await?;
 Ok(())
}
