use crate::AppState;
use lettre::{AsyncSmtpTransport,AsyncTransport,Message,Tokio1Executor,transport::smtp::authentication::Credentials};
use sqlx::Row;
use uuid::Uuid;
use std::time::Duration;

#[derive(Debug, PartialEq)]
enum MailSecurity { ImplicitTls, StartTls }

fn mail_security(port: &str) -> anyhow::Result<MailSecurity> {
 match port {
  "465" => Ok(MailSecurity::ImplicitTls),
  "587" => Ok(MailSecurity::StartTls),
  _ => anyhow::bail!("KANPAN_SMTP_PORT must be 465 (TLS) or 587 (required STARTTLS)"),
 }
}

pub struct Mailer {transport:AsyncSmtpTransport<Tokio1Executor>,from:String}
impl Mailer {
 pub fn from_env()->anyhow::Result<Option<Self>> {
  let Ok(host)=std::env::var("KANPAN_SMTP_HOST") else{return Ok(None)};
  let security=mail_security(&std::env::var("KANPAN_SMTP_PORT").unwrap_or_else(|_|"465".into()))?;
  let builder=match security {
   MailSecurity::ImplicitTls=>AsyncSmtpTransport::<Tokio1Executor>::relay(&host)?,
   MailSecurity::StartTls=>AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(&host)?,
  };
  let from=std::env::var("KANPAN_MAIL_FROM")?;
  let _:lettre::message::Mailbox=from.parse()?;
  let transport=builder.timeout(Some(Duration::from_secs(20)))
   .credentials(Credentials::new(std::env::var("KANPAN_SMTP_USER")?,std::env::var("KANPAN_SMTP_PASSWORD")?)).build();
  Ok(Some(Self{transport,from}))
 }
 pub async fn deliver_one(&self,s:&AppState)->anyhow::Result<bool> {
  let mut tx=s.pool.begin().await?;
  let row=sqlx::query("SELECT id,payload_sealed FROM account_mail WHERE sent_at IS NULL AND attempts<5 AND next_attempt<=now() AND created_at>now()-interval '10 minutes' ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1").fetch_optional(&mut *tx).await?;
  let Some(row)=row else {return Ok(false)};
  let id:Uuid=row.get("id");let data=s.secrets.open(&row.get::<String,_>("payload_sealed")).map_err(|_|anyhow::anyhow!("Cannot decrypt queued mail"))?;
  let body:serde_json::Value=serde_json::from_slice(&data)?;
  let email=body["email"].as_str().ok_or_else(||anyhow::anyhow!("Invalid mail recipient"))?;
  let text=if body["existing"]==true {"此邮箱已有账号，请直接登录；忘记密码可在登录页找回。".to_owned()}
   else {format!("你的看盘验证码：{}\n10 分钟内有效。若非本人操作，请忽略此邮件。",body["code"].as_str().unwrap_or_default())};
  let message=Message::builder().from(self.from.parse()?).to(email.parse()?).subject("看盘验证码").body(text)?;
  if self.transport.send(message).await.is_ok() {
   sqlx::query("UPDATE account_mail SET sent_at=now(),payload_sealed='' WHERE id=$1").bind(id).execute(&mut *tx).await?;
  }else{sqlx::query("UPDATE account_mail SET attempts=attempts+1,next_attempt=now()+interval '30 seconds' WHERE id=$1").bind(id).execute(&mut *tx).await?;}
  tx.commit().await?;Ok(true)
 }
}

#[cfg(test)]
mod tests {
 use super::*;
 #[test]
 fn smtp_requires_encryption() {
  assert_eq!(mail_security("465").unwrap(),MailSecurity::ImplicitTls);
  assert_eq!(mail_security("587").unwrap(),MailSecurity::StartTls);
  for port in ["25","0","5870",""] { assert!(mail_security(port).is_err()); }
 }
}
