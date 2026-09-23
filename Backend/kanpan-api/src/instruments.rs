//! 品种命名的三张小表：计价资产、周期、永续合约判定。**每张在 Rust 这边只此一份**。
//!
//! 审查（2026-09-24 §2）点过名：这三样以前各抄了三份，而且抄得不一样——
//! `market_meta` 的后缀表没有 `USD1`，`SPCXUSD1` 就拆不出 `SPCX`；`watch_move` 的只有四项，
//! `ETHFDUSD`、`XTUSD` 的通知标题就成了整串代号；周期表 `share` 一份 14 项、`sync_validation`
//! 一份 16 项，只有前者有测试对着客户端；永续判定 `sector_history` 认 `TRADIFI_PERPETUAL`、
//! `oi_archive` 不认，同一只美股永续板块历史里有、持仓量预热里没有。
//!
//! Swift 那边各自的副本由客户端那条线去收；这里的每张表都在注释里写明了它对着客户端的哪一处。

use serde_json::Value;

/// 看盘自己交易、同步、分享时认的计价资产——币安 U 本位上真的挂着的那几种。
///
/// 对着客户端 `SectorQuotePreference.quoteAssets`（KanpanCore/Sector/SectorAggregate.swift），
/// 顺序也照抄（它按这个顺序挑同一个 base 的「首选」合约）。`sync_validation` 用它判
/// 「这个代号是不是币安 U 本位的合约」，所以**只放真的会出现在币安合约代号结尾的**：
/// 往这里加一项就等于放宽同步与分享的校验。
pub const QUOTE_ASSETS:[&str;6]=["USDT","USDC","FDUSD","BUSD","USD1","TUSD"];

/// 从一个代号上剥计价资产时认的全部后缀，**长的、更具体的在前**。
///
/// 比 [`QUOTE_ASSETS`] 多两项：`USDD` 与裸 `USD`。它们不是币安 U 本位的计价资产，但供应量表、
/// 别家交易所的代号会带着它们。顺序是正确性的一部分：
/// `FDUSD`、`BUSD`、`TUSD` 都以 `USD` 结尾，必须排在 `USD` 前面，否则 `ETHFDUSD`
/// 会被剥成 `ETHFD`。`suffixes_are_ordered_longest_first` 钉着这一条。
pub const QUOTE_SUFFIXES:[&str;8]=["FDUSD","BUSD","TUSD","USDT","USDC","USDD","USD1","USD"];

/// 一个代号的 base：`BTCUSDT` → `BTC`、`SPCXUSD1` → `SPCX`、`BTC-USD`（Coinbase 现货）→ `BTC`。
///
/// 认不出计价资产、或者剥完什么都不剩（`USDT` 本身）就原样返回——宁可显示整串代号，
/// 也不猜。和客户端 `SymbolInfo.placeholder` 同一口径。
pub fn base(symbol:&str)->&str {
 // 带分隔符的（Coinbase 现货 `BTC-USD`）：横杠前面就是 base。
 // 横杠前面是空的（`-USD`）就是坏代号，原样返回，不再往下剥。
 if let Some((base,_))=symbol.split_once('-') {return if base.is_empty() {symbol} else {base}}
 for quote in QUOTE_SUFFIXES {
  if let Some(base)=symbol.strip_suffix(quote).filter(|b|!b.is_empty()) {return base}
 }
 symbol
}

/// 客户端周期条上能选到的全部周期，顺序照抄 `Interval`（KanpanCore/Sources/KanpanCore/Model/Interval.swift）。
///
/// 分享（`share.rs`）只收这一张：发出去的图必须是对方周期条上点得到的。
/// `intervals_match_native` 逐项对着 Swift 源文件比。
pub const INTERVALS:[&str;14]=["1m","3m","5m","15m","30m","1h","2h","4h","6h","12h","1d","1w","1M","1y"];

/// 客户端以前提供过、现在周期条上已经没有的周期。
///
/// 同步（`settings.interval` / `quickIntervals`）还得收它们：老存档、老客户端里可能还记着
/// `8h` / `3d`，而同步的值规则一旦拒收，整条操作 400，后面排队的设置全堵在它后面
/// （`sync.rs` 顶部那段 a161bb0 的教训）。分享不收——新发出去的图不该落在对方选不到的周期上。
pub const LEGACY_INTERVALS:[&str;2]=["8h","3d"];

/// 是客户端现在能选到的周期。
pub fn is_interval(value:&str)->bool {INTERVALS.contains(&value)}
/// 同步里可以出现的周期：现行的，加上以前提供过的。
pub fn is_synced_interval(value:&str)->bool {is_interval(value)||LEGACY_INTERVALS.contains(&value)}

/// 币安 `exchangeInfo` 里算「永续」的 `contractType`。
///
/// 美股、ETF、贵金属这些 TradFi 合约写的是 `TRADIFI_PERPETUAL`，它们正是手机上「美股」
/// 那一栏的全部内容——只认 `PERPETUAL` 的话那一栏永远没有历史（`sector_history` 以前踩过）。
pub const PERPETUAL_TYPES:[&str;2]=["PERPETUAL","TRADIFI_PERPETUAL"];

/// `exchangeInfo` 的一行是不是一个**正在交易的永续合约**。
///
/// 季度合约会到期，它的历史属于一个会消失的合约；`SETTLING`、`PENDING_TRADING`、`BREAK`
/// 的合约没有活价格。两类都不值得为它发请求。板块历史与持仓量预热都用这一个判定。
pub fn is_live_perpetual(row:&Value)->bool {
 row["contractType"].as_str().is_some_and(|kind|PERPETUAL_TYPES.contains(&kind))
  &&row["status"].as_str()==Some("TRADING")
}

#[cfg(test)]
mod tests {
 use super::*;
 use serde_json::json;

 /// 剥后缀按顺序试，所以一个后缀若以另一个结尾，它必须排在前面。
 #[test] fn suffixes_are_ordered_longest_first() {
  for (i,long) in QUOTE_SUFFIXES.iter().enumerate() {
   for short in &QUOTE_SUFFIXES[..i] {
    assert!(!long.ends_with(short)||long==short,"{long} 以 {short} 结尾，必须排在它前面");
   }
  }
  for quote in QUOTE_ASSETS {assert!(QUOTE_SUFFIXES.contains(&quote),"{quote} 是计价资产，剥后缀时也得认得");}
 }
 /// 审查点名的那几只：USD1 结尾、FDUSD / TUSD 结尾，以前各有一份表拆不出来。
 #[test] fn every_quote_comes_off() {
  for (symbol,want) in [("BTCUSDT","BTC"),("ETHUSDC","ETH"),("SPCXUSD1","SPCX"),("ETHFDUSD","ETH"),
   ("XTUSD","X"),("BNBBUSD","BNB"),("1000PEPEUSDT","1000PEPE"),("BTC-USD","BTC")] {
   assert_eq!(base(symbol),want,"{symbol}");
  }
  // 剥完什么都不剩、或者根本认不出计价资产：原样返回，不猜。
  assert_eq!(base("USDT"),"USDT");
  assert_eq!(base("-USD"),"-USD");
  assert_eq!(base("BTC"),"BTC");
  // 两个后缀叠在一起时按表序取第一个：`USDTUSD` 读成 `USD` + `TUSD`，和客户端
  // `SymbolInfo.placeholder` 一样。币安没有这种合约，这里钉住的是两端一致，不是哪个更对。
  assert_eq!(base("USDTUSD"),"USD");
 }
 /// 客户端周期条就是这张表：逐项、按顺序对着 Swift 源文件。
 #[test] fn intervals_match_native() {
  let source=include_str!("../../../KanpanCore/Sources/KanpanCore/Model/Interval.swift");
  // 只认 `case m1 = "1m", …` 这几行的原始值（显示名那几行是 `case .m1: "1 分钟"`）。
  let cases:String=source.lines().filter(|l|l.trim_start().starts_with("case ")&&l.contains(" = \"")).collect::<Vec<_>>().join("\n");
  let values:Vec<_>=cases.split('"').enumerate().filter_map(|(i,s)|(i%2==1).then_some(s)).collect();
  assert_eq!(values,INTERVALS);
 }
 /// 复盘那边的 `Interval` 是「币安 klines 能给的周期」，是另一件事；但客户端能选的周期
 /// 除了年线（复盘自己按日线聚合）都得是币安给得出的，否则那一档画不出图。
 #[test] fn every_interval_but_the_year_is_a_binance_interval() {
  use scorebook_core::domain::interval::Interval;
  for value in INTERVALS.iter().chain(LEGACY_INTERVALS.iter()).filter(|v|**v!="1y") {
   assert!(Interval::exact(value).is_ok(),"{value} 不是币安 klines 的周期");
  }
  assert!(LEGACY_INTERVALS.iter().all(|v|!is_interval(v)&&is_synced_interval(v)));
  assert!(!is_synced_interval("7h"));
 }
 #[test] fn only_trading_perpetuals_count() {
  assert!(is_live_perpetual(&json!({"symbol":"BTCUSDT","contractType":"PERPETUAL","status":"TRADING"})));
  assert!(is_live_perpetual(&json!({"symbol":"NVDAUSDT","contractType":"TRADIFI_PERPETUAL","status":"TRADING"})));
  assert!(!is_live_perpetual(&json!({"symbol":"XAUTUSDT","contractType":"TRADIFI_PERPETUAL","status":"BREAK"})));
  assert!(!is_live_perpetual(&json!({"symbol":"BTCUSDT_250926","contractType":"CURRENT_QUARTER","status":"TRADING"})));
  assert!(!is_live_perpetual(&json!({"symbol":"NEWUSDT","contractType":"PERPETUAL","status":"PENDING_TRADING"})));
  assert!(!is_live_perpetual(&json!({"symbol":"X"})));
 }
}
