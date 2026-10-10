//! 自选层（2026-10-10，原型 §11「登录用户自选由服务端自动补跟」）：近 7 天登录过的人，每人自选前 30 只，
//! 合在一起按「几个人自选了它」排、最多 [`CAP`] 只，交给 [`super::Registry::apply`] 的 `Layer::Favorite`。
//!
//! 只读同步里已有的 `favorites` 集合（不加同步字段）；7 天没登录的人自动不算，他的自选在下一轮自然释放。
//! 和固定层同一档卸层、不被「腾地方」踢掉；名单每 10 分钟重算一次。
use crate::sync;
use serde_json::Value;
use sqlx::PgPool;
use std::collections::{HashMap,HashSet};
use uuid::Uuid;

pub const EVERY_MS:i64=10*60_000;
/// 每人算前几只（按自选里的顺序）。
pub const PER_USER:usize=30;
/// 合起来最多跟几只。
pub const CAP:usize=60;

/// 一条自选 → 订单流的 base：币安 `1000PEPEUSDT` → `PEPE`，Coinbase / OKX `BTC-USD(-…)` → `BTC`，
/// Bybit `XUSDT`，Hyperliquid `kPEPE`；美元指数这类不在订单流里的为 None。
pub fn base_of(venue:&str,symbol:&str)->Option<String> {
 let listed=match venue {
  "binance"|"bybit"=>symbol.strip_suffix("USDT").or_else(||symbol.strip_suffix("USDC"))?,
  "coinbase"|"okx"=>symbol.split('-').next()?,
  "hyperliquid"=>symbol.strip_prefix('k').filter(|r|r.bytes().next().is_some_and(|b|b.is_ascii_uppercase())).unwrap_or(symbol),
  _=>return None,
 };
 let (_,base)=crate::orderflow_instruments::scale_of(listed);
 crate::orderflow_instruments::valid_base(base).then(||base.to_string())
}

/// 一个人的自选 → 他的前 [`PER_USER`] 只 base（按 `order`，同序按 id；重复的只算一次）。
pub fn of_person(objects:&[sync::Object])->Vec<String> {
 let mut rows:Vec<(f64,&str,String)>=objects.iter().filter_map(|o| {
  let symbol=o.body.get("symbol")?.as_str()?;
  let venue=o.body.get("venue").and_then(Value::as_str).unwrap_or(crate::instruments::DEFAULT_VENUE);
  let order=o.body.get("order").and_then(Value::as_f64).unwrap_or(f64::MAX);
  Some((order,o.id.as_str(),base_of(venue,symbol)?))
 }).collect();
 rows.sort_by(|a,b|a.0.total_cmp(&b.0).then_with(||a.1.cmp(b.1)));
 let mut seen=HashSet::new();
 rows.into_iter().map(|r|r.2).filter(|b|seen.insert(b.clone())).take(PER_USER).collect()
}

/// 各人的名单合起来：按人数降序、同数按名字，最多 [`CAP`] 只。
pub fn pick(people:&[Vec<String>])->Vec<String> {
 let mut count:HashMap<&str,usize>=HashMap::new();
 for p in people {for b in p {*count.entry(b.as_str()).or_default()+=1;}}
 let mut all:Vec<(&str,usize)>=count.into_iter().collect();
 all.sort_by(|a,b|b.1.cmp(&a.1).then_with(||a.0.cmp(b.0)));
 all.into_iter().take(CAP).map(|(b,_)|b.to_string()).collect()
}

/// 近 7 天登录过（会话没撤、7 天内用过）的人的自选合起来的名单。
pub async fn bases(pool:&PgPool)->anyhow::Result<Vec<String>> {
 let owners:Vec<Uuid>=sqlx::query_scalar(
  "SELECT DISTINCT s.user_id FROM account_sessions s JOIN account_users u ON u.id=s.user_id \
   WHERE u.disabled_at IS NULL AND s.revoked_at IS NULL AND s.seen_at>now()-interval '7 days'")
  .fetch_all(pool).await?;
 let mut people=Vec::with_capacity(owners.len());
 for owner in owners {
  // 同 `AppState::personal`：带上本人身份读他自己的同步对象。
  let mut tx=pool.begin().await?;
  sqlx::query("SELECT set_config('kanpan.user_id',$1,true)").bind(owner.to_string()).execute(&mut *tx).await?;
  let objects=match sync::live_objects(&mut tx,owner,sync::FAVORITES).await {
   Ok(o)=>o,
   Err(e)=>{tracing::warn!("Orderflow history: favorites of one account unreadable: {e:?}");continue},
  };
  tx.commit().await?;
  people.push(of_person(&objects));
 }
 Ok(pick(&people))
}

#[cfg(test)]
mod tests {
 use super::*;

 #[test]
 fn bases_from_each_venue() {
  assert_eq!(base_of("binance","1000PEPEUSDT").as_deref(),Some("PEPE"));
  assert_eq!(base_of("binance","AXSUSDT").as_deref(),Some("AXS"));
  assert_eq!(base_of("coinbase","ZEC-USD").as_deref(),Some("ZEC"));
  assert_eq!(base_of("okx","BTC-USDT-SWAP").as_deref(),Some("BTC"));
  assert_eq!(base_of("hyperliquid","kPEPE").as_deref(),Some("PEPE"));
  assert_eq!(base_of("macro","DXY"),None);
  assert_eq!(base_of("binance","BTCUSD_PERP"),None);
 }

 #[test]
 fn a_person_counts_their_first_thirty_in_order() {
  let fav=|id:&str,venue:&str,symbol:&str,order:f64|sync::Object{collection:"favorites".into(),id:id.into(),
   body:[("symbol".to_string(),serde_json::json!(symbol)),("venue".to_string(),serde_json::json!(venue)),("order".to_string(),serde_json::json!(order))].into_iter().collect(),
   fields:Default::default(),revision:1,deleted:false,generation:1};
  let mut objects=vec![fav("a","binance","ETHUSDT",2.0),fav("b","coinbase","BTC-USD",1.0),fav("c","binance","BTCUSDT",3.0),fav("d","macro","DXY",0.0)];
  assert_eq!(of_person(&objects),vec!["BTC","ETH"]);
  objects.extend((0..40).map(|i|fav(&format!("z{i}"),"binance",&format!("C{i:02}USDT"),10.0+f64::from(i))));
  let mine=of_person(&objects);
  assert_eq!(mine.len(),PER_USER);
  assert_eq!(mine[2],"C00");
 }

 #[test]
 fn union_ranks_by_people_and_caps() {
  let a:Vec<String>=["AXS","BTC"].iter().map(|s|s.to_string()).collect();
  let b:Vec<String>=["BTC","ZEC"].iter().map(|s|s.to_string()).collect();
  assert_eq!(pick(&[a,b]),vec!["BTC","AXS","ZEC"]);
  let many:Vec<Vec<String>>=vec![(0..100).map(|i|format!("C{i:03}")).collect()];
  assert_eq!(pick(&many).len(),CAP);
 }
}
