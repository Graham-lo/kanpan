//! PostgreSQL serializes the shared outbound IP/product budget across API and workers.
use crate::error::{Error, Result, RetryDirective};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
#[derive(Clone)]
pub struct ProviderBudget {
    pool: PgPool,
    egress: String,
    limit: i32,
}
impl ProviderBudget {
    pub fn new(pool: PgPool) -> anyhow::Result<Self> {
        // 默认 1200：币安 fapi 每个 IP 每分钟 2400，留一半给同机别的模块（板块历史、
        // 市场元数据走的是同一个出口，`observe` 记的也是整个 IP 的已用权重）。原来是 600，
        // 一次「找相似」要取 300 个候选、约 300 权重，同一分钟里连着找两次就被自家账本
        // 拦下（P3.8 实测 1d 那次 12 个候选因此没比上）。
        let limit = std::env::var("KANPAN_BINANCE_WEIGHT_PER_MINUTE")
            .map(|v| v.parse())
            .unwrap_or(Ok(1200))?;
        anyhow::ensure!(
            (20..=2400).contains(&limit),
            "invalid Binance weight budget"
        );
        Ok(Self {
            pool,
            egress: std::env::var("KANPAN_EGRESS_ID")
                .unwrap_or_else(|_| "default-egress".into()),
            limit,
        })
    }
    pub async fn reserve(&self, market: &str, weight: i32) -> Result<()> {
        if weight <= 0 {
            return Err(Error::bad("invalid_provider_weight"));
        }
        if weight > self.limit {
            return Err(Error::deferred(
                "capability_configuration_required",
                RetryDirective::AwaitCapability,
            ));
        }
        let mut tx = self.pool.begin().await?;
        sqlx::query(
            "INSERT INTO provider_budgets(egress_id,market) VALUES($1,$2) ON CONFLICT DO NOTHING",
        )
        .bind(&self.egress)
        .bind(market)
        .execute(&mut *tx)
        .await?;
        let row=sqlx::query("SELECT window_start,used,greatest(blocked_until,'epoch'::timestamptz) AS blocked_until,now() AS at FROM provider_budgets WHERE egress_id=$1 AND market=$2 FOR UPDATE").bind(&self.egress).bind(market).fetch_one(&mut *tx).await?;
        let now: DateTime<Utc> = row.get("at");
        // 列默认值是 '-infinity'（从没冷却过）；chrono 解不了无穷，sqlx 会直接 panic 把 worker 带走，
        // 所以在 SQL 里先夹到 epoch，语义不变（「早于现在」= 没在冷却）。
        let blocked: DateTime<Utc> = row.get("blocked_until");
        let start: DateTime<Utc> = row.get("window_start");
        if blocked > now {
            return Err(Error::deferred(
                "provider_cooling_down",
                RetryDirective::At(blocked),
            ));
        }
        let current = now.timestamp().div_euclid(60) == start.timestamp().div_euclid(60);
        if current && row.get::<i32, _>("used") + weight > self.limit {
            return Err(Error::deferred(
                "provider_budget_exhausted",
                RetryDirective::At(start + chrono::Duration::minutes(1)),
            ));
        }
        sqlx::query("UPDATE provider_budgets SET used=CASE WHEN window_start=date_trunc('minute',now()) THEN used+$3 ELSE $3 END,window_start=date_trunc('minute',now()) WHERE egress_id=$1 AND market=$2").bind(&self.egress).bind(market).bind(weight).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(())
    }
    pub async fn observe(
        &self,
        market: &str,
        used: Option<i32>,
        cooldown: Option<u32>,
    ) -> Result<()> {
        sqlx::query("UPDATE provider_budgets SET used=CASE WHEN window_start=date_trunc('minute',now()) THEN greatest(used,COALESCE($3,0)) ELSE COALESCE($3,0) END,window_start=date_trunc('minute',now()),blocked_until=CASE WHEN $4::int IS NULL THEN blocked_until ELSE greatest(blocked_until,now()+make_interval(secs=>$4)) END WHERE egress_id=$1 AND market=$2").bind(&self.egress).bind(market).bind(used).bind(cooldown.map(|s|s as i32)).execute(&self.pool).await?;
        Ok(())
    }
}
