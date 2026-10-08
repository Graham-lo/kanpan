//! 品种命名的三张小表：计价资产、周期、永续合约判定。**每张在 Rust 这边只此一份**。
//!
//! 审查（2026-09-24 §2）点过名：这三样以前各抄了三份，而且抄得不一样——
//! `market_meta` 的后缀表没有 `USD1`，`SPCXUSD1` 就拆不出 `SPCX`；`watch_move` 的只有四项，
//! `ETHFDUSD`、`XTUSD` 的通知标题就成了整串代号；周期表 `share` 一份 14 项、`sync_validation`
//! 一份 16 项，只有前者有测试对着客户端；永续判定 `sector_history` 认 `TRADIFI_PERPETUAL`、
//! `oi_archive` 不认，同一只美股永续板块历史里有、持仓量预热里没有。
//!
//! 两端对的是同一份手工维护的契约 `contract/instruments.json`：这里的每张表都由
//! `the_contract_file_is_what_both_sides_use` 逐项对着它比，客户端那一半是
//! `KanpanCore/Tests/KanpanCoreTests/InstrumentContractTests.swift`。

use serde_json::Value;

/// 裸代号（没带交易所前缀的老数据）归哪一家。对着客户端 `InstrumentID.defaultVenue` /
/// `defaultMarket` / `defaultMarketKey`（KanpanCore/Model/InstrumentID.swift）。
/// 服务端凡是「字段缺省按币安 U 本位」的地方都引用这里，不再各写一遍字面量。
pub const DEFAULT_VENUE:&str="binance";
pub const DEFAULT_MARKET:&str="usd_m";
pub const DEFAULT_MARKET_KEY:&str="binance/usd_m";

/// 看盘自己交易、同步、分享时认的计价资产——币安 U 本位上真的挂着的那几种。
///
/// 对着客户端 `QuoteAssets.tradable`（KanpanCore/Model/QuoteAssets.swift），
/// 顺序也照抄（板块页按这个顺序挑同一个 base 的「首选」合约）。`sync_validation` 用它判
/// 「这个代号是不是币安 U 本位的合约」，所以**只放真的会出现在币安合约代号结尾的**：
/// 往这里加一项就等于放宽同步与分享的校验。
pub const QUOTE_ASSETS:[&str;6]=["USDT","USDC","FDUSD","BUSD","USD1","TUSD"];

/// 从一个代号上剥计价资产时认的全部后缀，**长的、更具体的在前**。
///
/// 对着客户端 `QuoteAssets.suffixes`。比 [`QUOTE_ASSETS`] 多两项：`USDD` 与裸 `USD`。它们不是币安 U 本位的计价资产，但供应量表、
/// 别家交易所的代号会带着它们。顺序是正确性的一部分：
/// `FDUSD`、`BUSD`、`TUSD` 都以 `USD` 结尾，必须排在 `USD` 前面，否则 `ETHFDUSD`
/// 会被剥成 `ETHFD`。`suffixes_are_ordered_longest_first` 钉着这一条。
pub const QUOTE_SUFFIXES:[&str;8]=["FDUSD","BUSD","TUSD","USDT","USDC","USDD","USD1","USD"];

/// 币安合约代号（大写形式）里允许的一个字符：ASCII 大写、数字、下划线，或者**非 ASCII 的 Unicode 字母数字**——
/// 币安挂着「币安人生USDT」「龙虾USDT」这类中文底名的永续（2026-10-03 有五只），行情推送、REST、深度都照常给。
/// 同步层的 `sync_validation::binance_symbol` 早就这么认；行情这几条路（REST 透传、深度快照、订单流中继、
/// stream-hub）以前只认 ASCII，一只中文合约混进订阅就让**整条** WS 握手 400、整页行情断掉。
pub fn binance_symbol_char(c:char)->bool {c.is_ascii_uppercase()||c.is_ascii_digit()||c=='_'||(!c.is_ascii()&&c.is_alphanumeric())}
/// 小写形式（币安流名 `龙虾usdt@aggTrade`）：中文没有大小写，规则同上、只把 ASCII 大写换成小写。
pub fn binance_stream_symbol_char(c:char)->bool {c.is_ascii_lowercase()||c.is_ascii_digit()||c=='_'||(!c.is_ascii()&&c.is_alphanumeric())}

/// 拼进上游 URL 之前的百分号编码：非 ASCII（中文底名）和保留字符都编成 `%XX`。
/// `format!` 直接把「龙虾USDT」塞进 URL，`http::Uri` 解析不了，连接根本发不出去。
/// `@` 留着（币安流名 `sym@aggTrade` 本来就带它，查询串里合法）。
pub fn url_component(s:&str)->String {
 let mut out=String::with_capacity(s.len());
 for b in s.bytes() {
  if b.is_ascii_alphanumeric()||matches!(b,b'_'|b'-'|b'.'|b'~'|b'@') {out.push(b as char)} else {out.push_str(&format!("%{b:02X}"))}
 }
 out
}

/// `url_component` 的反方向：查询串里一个值的 `%XX` 还原成 UTF-8；编码坏了或不是 UTF-8 就是 `None`。
/// 自己读原始查询串的接口（`hourly-closes` 的 `symbols=`）要靠它认出浏览器编过的中文底名。
pub fn url_decode(s:&str)->Option<String> {
 let b=s.as_bytes();let mut out=Vec::with_capacity(b.len());let mut i=0;
 while i<b.len() {
  if b[i]==b'%' {
   let hex=std::str::from_utf8(b.get(i+1..i+3)?).ok()?;
   out.push(u8::from_str_radix(hex,16).ok()?);i+=3;
  } else {out.push(b[i]);i+=1}
 }
 String::from_utf8(out).ok()
}

/// 一个代号的 base：`BTCUSDT` → `BTC`、`SPCXUSD1` → `SPCX`、`BTC-USD`（Coinbase 现货）→ `BTC`。
///
/// 认不出计价资产、或者剥完什么都不剩（`USDT` 本身）就原样返回——宁可显示整串代号，
/// 也不猜。和客户端 `QuoteAssets.split`（`SymbolInfo.placeholder` 用它）同一口径，
/// 契约里的 `baseCases` 两端各跑一遍。
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
/// 对着客户端 `Interval.allCases`，两端都比 `contract/instruments.json` 的 `intervals`。
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
/// 对着客户端 `SymbolInfo.perpetualContractTypes`（品种表准入用它）。
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

 #[test]
 fn chinese_base_names_are_symbols_and_get_encoded() {
  assert!("龙虾USDT".chars().all(binance_symbol_char)&&"BTCUSD_PERP".chars().all(binance_symbol_char));
  assert!(!"btcusdt".chars().all(binance_symbol_char)&&!"龙虾/USDT".chars().all(binance_symbol_char)&&!"龙虾 USDT".chars().all(binance_symbol_char));
  assert!("龙虾usdt".chars().all(binance_stream_symbol_char)&&!"龙虾USDT".chars().all(binance_stream_symbol_char));
  assert_eq!(url_component("龙虾usdt@aggTrade"),"%E9%BE%99%E8%99%BEusdt@aggTrade");
  assert_eq!(url_component("BTCUSDT"),"BTCUSDT");
  assert_eq!(url_component("a/b&c=d"),"a%2Fb%26c%3Dd");
  assert_eq!(url_decode("%E9%BE%99%E8%99%BEUSDT").as_deref(),Some("龙虾USDT"));
  assert_eq!(url_decode(&url_component("币安人生USDT")).as_deref(),Some("币安人生USDT"));
  assert_eq!(url_decode("%E9%BE"),None,"半个字");
  assert_eq!(url_decode("%G1"),None);
 }

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
 /// 用例本身在契约里（`baseCases`），客户端 `QuoteAssets.split` 跑的是同一批：
 /// 剥完什么都不剩、认不出计价资产的原样返回；`USDTUSD` 按表序读成 `USD` + `TUSD`——
 /// 币安没有这种合约，钉住的是两端一致，不是哪个更对。
 #[test] fn every_quote_comes_off() {
  let cases=contract()["baseCases"].as_array().unwrap().clone();
  assert!(!cases.is_empty());
  for case in cases {
   let (symbol,want)=(case[0].as_str().unwrap(),case[1].as_str().unwrap());
   assert_eq!(base(symbol),want,"{symbol}");
  }
 }
 fn contract()->Value {serde_json::from_str(include_str!("../contract/instruments.json")).expect("instruments.json")}
 fn strings(value:&Value)->Vec<&str> {value.as_array().expect("数组").iter().map(|v|v.as_str().expect("字符串")).collect()}
 /// 两端对的是同一份契约：客户端 `InstrumentContractTests` 拿同一个文件比 Swift 那几张表。
 #[test] fn the_contract_file_is_what_both_sides_use() {
  let c=contract();
  assert_eq!(strings(&c["quoteAssets"]),QUOTE_ASSETS);
  assert_eq!(strings(&c["quoteSuffixes"]),QUOTE_SUFFIXES);
  assert_eq!(strings(&c["intervals"]),INTERVALS);
  assert_eq!(strings(&c["legacyIntervals"]),LEGACY_INTERVALS);
  assert_eq!(strings(&c["perpetualContractTypes"]),PERPETUAL_TYPES);
  assert_eq!(c["defaultMarket"]["venue"],DEFAULT_VENUE);
  assert_eq!(c["defaultMarket"]["market"],DEFAULT_MARKET);
  assert_eq!(c["defaultMarket"]["key"],DEFAULT_MARKET_KEY);
  assert_eq!(format!("{DEFAULT_VENUE}/{DEFAULT_MARKET}"),DEFAULT_MARKET_KEY);
  // 交易所清单：服务端注册表逐项、按顺序对上（客户端那一半由 `VenueRegistry` 对）。
  let venues:Vec<(String,String,bool)>=c["venues"].as_array().expect("contract has no venues").iter()
   .map(|v|(v["venue"].as_str().unwrap().to_owned(),v["market"].as_str().unwrap().to_owned(),v["review"].as_bool().unwrap())).collect();
  let ours:Vec<(String,String,bool)>=crate::venues::venues().iter().map(|v|(v.source().to_owned(),v.market().to_owned(),v.review())).collect();
  assert_eq!(venues,ours);
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
