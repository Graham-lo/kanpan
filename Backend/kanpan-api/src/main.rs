use kanpan_api::{AppState,crypto::Secrets,supervise::{Life,Supervisor}};
use std::{sync::Arc,net::SocketAddr};
#[tokio::main]
async fn main()->anyhow::Result<()> {
 tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::from_default_env()).init();
 let command=std::env::args().nth(1).unwrap_or_else(||"serve".into());
 // The market fallback host runs `metrics`: open interest only, no accounts and
 // so no database. Answered before the pool, or it would demand a connection
 // string it has no reason to hold.
 if command=="metrics" {
  let supervisor=Supervisor::new();
  supervisor.watch("oi-warm",Life::Once,kanpan_api::oi_archive::spawn_warm());
  let address:SocketAddr=std::env::var("KANPAN_BIND").unwrap_or_else(|_|"127.0.0.1:8794".into()).parse()?;
  let listener=tokio::net::TcpListener::bind(address).await?;
  let (stop,cause)=supervisor.shutdown();
  axum::serve(listener,kanpan_api::metrics_router()).with_graceful_shutdown(stop).await?;
  return kanpan_api::supervise::outcome(&cause);
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
 if command=="reset-password" {
  let name=std::env::args().nth(2).ok_or_else(||anyhow::anyhow!("Usage: kanpan-api reset-password <username>"))?;
  match kanpan_api::auth::reset_password(&s,&name).await {
   Ok(fresh)=>{println!("{fresh}");return Ok(())}
   Err(e)=>anyhow::bail!("reset-password failed: {}",e.1),
  }
 }
 if command=="worker" {
  let market=Arc::new(kanpan_api::review_market::provider(s.pool.clone())?);
  // 每个循环各自一条任务、各自被看着：任何一条 panic 或者退出了，进程以非零码退出，
  // 交给 systemd 拉起。原来它们 `join!` 在一起，一条 panic 掉整个 worker 还活着、
  // 那一摊活却再也没人干（见 `kanpan_api::supervise`）。
  let supervisor=Supervisor::new();
  {
   let (s,market)=(s.clone(),market.clone());
   supervisor.spawn("review",Life::Forever,async move {loop {
    if let Err(e)=kanpan_api::review_worker::run_one(&s,&*market).await {tracing::warn!("Review work will retry ({e:?})");}
    tokio::time::sleep(std::time::Duration::from_secs(2)).await;
   }});
  }
  // Chart search is the one job a person actively waits on, and this host is
  // shared by fewer than ten of them: poll every second, not every two.
  {
   let (s,market)=(s.clone(),market.clone());
   supervisor.spawn("search",Life::Forever,async move {loop {
    if let Err(e)=kanpan_api::search::run_one(&s,&*market).await {tracing::warn!("Search work will retry ({e:?})");}
    tokio::time::sleep(std::time::Duration::from_secs(1)).await;
   }});
  }
  {
   let s=s.clone();
   supervisor.spawn("cleanup",Life::Forever,async move {loop {
    // 单步失败在 cleanup 里面各自记、接着做；这里只剩「整轮都开不了头」。
    if let Err(e)=kanpan_api::maintenance::cleanup(&s).await {tracing::warn!("Cleanup will retry ({e:?})");}
    tokio::time::sleep(std::time::Duration::from_secs(3600)).await;
   }});
  }
  // 提醒的评估器。APNs 密钥缺席时 `from_env` 只写一行 warn 并返回 None——评估照常跑、
  // 触发状态照常写回同步日志，少的只是最后那一下推送。密钥是用户要去开发者后台下载的
  // 东西，提醒的其余部分不该等它。币安、Coinbase 各一条常驻评估循环，各自被看着。
  let apns=kanpan_api::apns::Apns::from_env().map(Arc::new);
  supervisor.spawn("alerts",Life::Forever,kanpan_api::alerts::run(s.clone(),apns.clone()));
  supervisor.spawn("alerts-coinbase",Life::Forever,kanpan_api::alerts::run_coinbase(s.clone(),apns));
  tokio::select! {
   e=supervisor.failure()=>return Err(e),
   _=tokio::signal::ctrl_c()=>{}
  }
  return Ok(());

 }
 anyhow::ensure!(command=="serve","Use serve, metrics, worker, migrate or reset-password <username>");
 // 三条后台任务都被看着：常驻的两条返回或 panic、预热那条 panic，都让进程以非零码
 // 退出（先给在途请求 `supervise::DRAIN` 收尾），交给 systemd 拉起。
 let supervisor=Supervisor::new();
 // Public supply data has no owner and no database; warm it before the first request.
 supervisor.watch("market-meta",Life::Forever,kanpan_api::market_meta::spawn_refresh());
 // Daily closes are history, not a cache: the sweep and the route share this
 // process so the answer served is the one the sweep just refreshed.
 supervisor.watch("daily-close",Life::Forever,kanpan_api::sector_history::spawn_daily(s.pool.clone()));
 // 主力订单流的历史：常驻跟踪各家挂单簿、判出来的大单写进库，同一进程回 `/v1/market/orderflow/history`。
 supervisor.watch("orderflow-history",Life::Forever,kanpan_api::orderflow_history::spawn(s.pool.clone()));
 // The open interest archive keeps its own disk cache; index it before the
 // first chart asks rather than inside that request. It finishes by design.
 supervisor.watch("oi-warm",Life::Once,kanpan_api::oi_archive::spawn_warm());
 let address:SocketAddr=std::env::var("KANPAN_BIND").unwrap_or_else(|_|"127.0.0.1:8794".into()).parse()?;
 let listener=tokio::net::TcpListener::bind(address).await?;
 let (stop,cause)=supervisor.shutdown();
 axum::serve(listener,kanpan_api::router(s).into_make_service_with_connect_info::<SocketAddr>()).with_graceful_shutdown(stop).await?;
 kanpan_api::supervise::outcome(&cause)
}
