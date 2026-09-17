use kanpan_api::{AppState,crypto::Secrets,mail::Mailer};
use sqlx::postgres::PgPoolOptions;
use std::{sync::Arc,net::SocketAddr};
#[tokio::main]
async fn main()->anyhow::Result<()> {
 tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::from_default_env()).init();
 let command=std::env::args().nth(1).unwrap_or_else(||"serve".into());
 let pool=PgPoolOptions::new().max_connections(8).connect(&std::env::var("KANPAN_DATABASE_URL")?).await?;
 if command=="migrate" {sqlx::migrate!().run(&pool).await?;return Ok(())}
 let privileged:bool=sqlx::query_scalar("SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user").fetch_one(&pool).await?;
 anyhow::ensure!(!privileged,"Runtime role must not be superuser or BYPASSRLS");
 let pepper=std::env::var("KANPAN_PASSWORD_PEPPER")?.into_bytes();anyhow::ensure!(pepper.len()>=32,"Pepper must contain at least 32 bytes");
 let key=hex::decode(std::env::var("KANPAN_ENCRYPTION_KEY")?)?;
 let encryption:[u8;32]=key.try_into().map_err(|_|anyhow::anyhow!("Encryption key must be 32 bytes"))?;
 let secrets=Arc::new(Secrets{pepper,encryption});
 let dummy_hash=Arc::new(secrets.hash_password(&kanpan_api::crypto::random_token()).map_err(|_|anyhow::anyhow!("Password hashing unavailable"))?);
 let mail=Mailer::from_env()?;
 let s=AppState{pool,secrets,dummy_hash,mail_enabled:mail.is_some()};
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
  let mail_loop=async {loop {
   if let Some(ref mail)=mail {if mail.deliver_one(&s).await.is_err(){tracing::warn!("Email delivery will retry");}}
   tokio::time::sleep(std::time::Duration::from_secs(2)).await;
  }};
  let cleanup_loop=async {loop {
   if kanpan_api::maintenance::cleanup(&s).await.is_err(){tracing::warn!("Cleanup will retry");}
   tokio::time::sleep(std::time::Duration::from_secs(3600)).await;
  }};
  tokio::select! {
   _=async {tokio::join!(review_loop,search_loop,mail_loop,cleanup_loop);} => {},
   _=tokio::signal::ctrl_c()=>{}
  }
  return Ok(());

 }
 anyhow::ensure!(command=="serve","Use serve, worker or migrate");
 // Public supply data has no owner and no database; warm it before the first request.
 kanpan_api::market_meta::spawn_refresh();
 let address:SocketAddr=std::env::var("KANPAN_BIND").unwrap_or_else(|_|"127.0.0.1:8794".into()).parse()?;
 let listener=tokio::net::TcpListener::bind(address).await?;
 axum::serve(listener,kanpan_api::router(s).into_make_service_with_connect_info::<SocketAddr>()).with_graceful_shutdown(async{let _=tokio::signal::ctrl_c().await;}).await?;
 Ok(())
}
