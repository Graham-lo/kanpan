//! PostgreSQL serializes the shared outbound IP/product budget across API and workers.
//!
//! 一行账（每个出口 × 市场、每分钟一个窗口）记两个数（2026-09-30 压测 C 路）：
//!
//! * `used`：这个 IP 这一分钟用掉的权重估计——自己预留的加上，每次回答再和币安回头里的
//!   `x-mbx-used-weight-1m`（整个 IP 的，含同机 serve 进程的订单流快照、行情转发、元数据）取大；
//! * `reserved`：只算这个账本自己（worker 里的找相似、复盘判定、索引）这一分钟预留了多少。
//!
//! 预留要同时过两道：`reserved + w <= limit`（本类份额：找相似 1200，复盘判定与索引按
//! [`ProviderBudget::with_share`] 打折）与 `used + w <= ceiling`（整个 IP 的上限，默认 1800 / 2400）。
//! 原来只有一个数：`used` 取了整个 IP 的已用，又拿「留了一半给别的模块」的 1200 去比，同机别的模块
//! 那一半被扣了两遍——serve 重启时订单流快照通道一分钟 600、再加稳态两百来，worker 这边就只剩
//! 三四百，找相似（一次约 300）与复盘判定互相挤着排队（02:56 重启后十分钟账本 600–1 190）。
use crate::error::{Error, Result, RetryDirective};
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
#[derive(Clone)]
pub struct ProviderBudget {
    pool: PgPool,
    egress: String,
    /// 这个账本自己一分钟最多预留多少（本类份额）。
    limit: i32,
    /// 整个 IP 这一分钟的权重估计到多少就不再出站。
    ceiling: i32,
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
        // 整个 IP 的上限：币安 fapi 每 IP 每分钟 2400，留四分之一给同机 serve 进程在两次回答之间
        // 冒出来、这边还没看见的那部分（手机行情转发、订单流快照）。
        let ceiling = std::env::var("KANPAN_BINANCE_IP_WEIGHT_CEILING")
            .map(|v| v.parse())
            .unwrap_or(Ok(1800))?;
        anyhow::ensure!(
            (20..=2400).contains(&ceiling),
            "invalid Binance IP weight ceiling"
        );
        Ok(Self::fixed(
            pool,
            &std::env::var("KANPAN_EGRESS_ID").unwrap_or_else(|_| "default-egress".into()),
            limit,
            ceiling,
        ))
    }
    /// 不读环境变量、直接给定出口与两个上限。测试用，线上一律 [`ProviderBudget::new`]。
    #[doc(hidden)]
    pub fn fixed(pool: PgPool, egress: &str, limit: i32, ceiling: i32) -> Self {
        Self {
            pool,
            egress: egress.to_owned(),
            limit,
            ceiling,
        }
    }
    /// 本类只拿账本份额的 `percent`%：复盘判定与索引拿 75%，最上面那四分之一只有找相似能用——
    /// 人在屏幕前等的那一件，判定补跑再多也挤不掉它。IP 上限不打折。
    pub fn with_share(mut self, percent: i32) -> Self {
        self.limit = (self.limit * percent.clamp(1, 100) / 100).max(1);
        self
    }
    /// 本类每分钟最多预留多少。
    pub fn limit(&self) -> i32 {
        self.limit
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
        let row=sqlx::query("SELECT window_start,used,reserved,greatest(blocked_until,'epoch'::timestamptz) AS blocked_until,now() AS at FROM provider_budgets WHERE egress_id=$1 AND market=$2 FOR UPDATE").bind(&self.egress).bind(market).fetch_one(&mut *tx).await?;
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
        let (used, reserved) = if current {
            (row.get::<i32, _>("used"), row.get::<i32, _>("reserved"))
        } else {
            (0, 0)
        };
        if !admits(used, reserved, weight, self.limit, self.ceiling) {
            return Err(Error::deferred(
                "provider_budget_exhausted",
                RetryDirective::At(start + chrono::Duration::minutes(1)),
            ));
        }
        sqlx::query("UPDATE provider_budgets SET used=CASE WHEN window_start=date_trunc('minute',now()) THEN used+$3 ELSE $3 END,reserved=CASE WHEN window_start=date_trunc('minute',now()) THEN reserved+$3 ELSE $3 END,window_start=date_trunc('minute',now()) WHERE egress_id=$1 AND market=$2").bind(&self.egress).bind(market).bind(weight).execute(&mut *tx).await?;
        tx.commit().await?;
        Ok(())
    }
    pub async fn observe(
        &self,
        market: &str,
        used: Option<i32>,
        cooldown: Option<u32>,
    ) -> Result<()> {
        sqlx::query("UPDATE provider_budgets SET used=CASE WHEN window_start=date_trunc('minute',now()) THEN greatest(used,COALESCE($3,0)) ELSE COALESCE($3,0) END,reserved=CASE WHEN window_start=date_trunc('minute',now()) THEN reserved ELSE 0 END,window_start=date_trunc('minute',now()),blocked_until=CASE WHEN $4::int IS NULL THEN blocked_until ELSE greatest(blocked_until,now()+make_interval(secs=>$4)) END WHERE egress_id=$1 AND market=$2").bind(&self.egress).bind(market).bind(used).bind(cooldown.map(|s|s as i32)).execute(&self.pool).await?;
        Ok(())
    }
}

/// 这一分钟还能不能再预留 `weight`：本类份额与整个 IP 的上限都要过。
fn admits(used: i32, reserved: i32, weight: i32, limit: i32, ceiling: i32) -> bool {
    reserved + weight <= limit && used + weight <= ceiling
}

#[cfg(test)]
mod tests {
    use super::admits;

    /// serve 重启时订单流快照通道把 IP 推到 800：原来（一个数、上限 1200）找相似只剩 400，
    /// 判定再占 150 就连一次 300 的找相似都排不上；现在 IP 还远没到 1800，找相似照走。
    #[test]
    fn serve_traffic_is_no_longer_charged_twice() {
        assert!(admits(800 + 150, 150, 300, 1200, 1800));
        // 判定只拿 75%：自己预留到 900 就停，最上面 300 只留给找相似。
        assert!(admits(1000, 880, 20, 900, 1800));
        assert!(!admits(1000, 890, 20, 900, 1800));
        assert!(admits(1000, 890, 300, 1200, 1800));
        // 整个 IP 的上限谁都过不去。
        assert!(!admits(1790, 0, 20, 1200, 1800));
        assert!(admits(1780, 0, 20, 1200, 1800));
    }
}
