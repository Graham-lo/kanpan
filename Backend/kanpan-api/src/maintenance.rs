use crate::{AppState,error::Result};
use uuid::Uuid;
pub async fn cleanup(s:&AppState)->Result<()> {
 for sql in [
 "DELETE FROM account_mail WHERE created_at<now()-interval '1 day'",
 "UPDATE account_tokens SET response_sealed=NULL WHERE used_at<now()-interval '60 seconds' AND response_sealed IS NOT NULL",
 "UPDATE account_challenges SET response_sealed=NULL WHERE response_at<now()-interval '60 seconds' AND response_sealed IS NOT NULL",
 "DELETE FROM account_challenges WHERE expires_at<now()-interval '1 day'",
 "DELETE FROM account_sessions WHERE expires_at<now()-interval '1 day' OR revoked_at<now()-interval '31 days'",
 "DELETE FROM account_tokens WHERE kind='access' AND expires_at<now()-interval '1 hour'",
 "DELETE FROM account_limits WHERE window_start<now()-interval '1 day' AND (locked_until IS NULL OR locked_until<now())"
 ] {sqlx::query(sql).execute(&s.pool).await?;}
 let mut after:Option<Uuid>=None;
 loop {
  let owners:Vec<Uuid>=sqlx::query_scalar("SELECT id FROM account_users WHERE disabled_at IS NULL AND ($1::uuid IS NULL OR id>$1) ORDER BY id LIMIT 100").bind(after).fetch_all(&s.pool).await?;
  if owners.is_empty(){break}
  for owner in &owners {
   let mut tx=match s.personal(*owner).await {Ok(tx)=>tx,Err(_)=>continue};
   sqlx::query("DELETE FROM sync_snapshots WHERE user_id=$1 AND created_at<now()-interval '30 days'").bind(owner).execute(&mut *tx).await?;
   sqlx::query("DELETE FROM review_searches WHERE user_id=$1 AND expires_at<now()").bind(owner).execute(&mut *tx).await?;
   tx.commit().await?;
  }
  after=owners.last().copied();
 }
 Ok(())
}
