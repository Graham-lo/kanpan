//! Public market metadata: coin supply (for total market cap) and open interest.
//!
//! Nothing here is personal, so these two routes carry no authentication and no
//! database. The supply table is a few hundred rows refreshed once a day, and
//! this host's runtime role neither owns tables nor bypasses RLS, so a public
//! market table would have to be created and granted by the admin role for no
//! gain: a process cache is the right size for it.
//!
//! The Binance marketing endpoints are the ones its own website calls; they are
//! undocumented and may change without warning, so every parser skips the rows
//! and the fields it cannot read instead of failing the whole table.
use crate::{AppState,envelope,error::{ApiError,Result}};
use axum::{Router,Json,extract::Query,routing::get,http::StatusCode};
use serde::Deserialize;
use serde_json::{Value,json};
use std::collections::HashMap;
use std::sync::{Arc,OnceLock,atomic::{AtomicBool,Ordering}};
use std::time::{Duration,Instant};

const APEX:&str="https://www.binance.com/bapi/apex/v1/public/apex/marketing/symbol/list";
const PRODUCTS:&str="https://www.binance.com/bapi/asset/v2/public/asset-service/product/get-products";
const COINGECKO:&str="https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=250&page=";
const COINGECKO_PAGES:u32=4;
// The futures REST paths are reached through `www.binance.com`, not
// `fapi.binance.com`: both market VPS sit in the United States, where
// `fapi.binance.com` and `dapi.binance.com` answer 451 ("restricted
// location"), while the same paths served off the website host answer 200
// with production data. Measured 2026-09-18 on both nodes.
const BINANCE_OI:&str="https://www.binance.com/fapi/v1/openInterest?symbol=";
const BINANCE_PRICES:&str="https://www.binance.com/fapi/v1/ticker/price";
const OKX_OI:&str="https://www.okx.com/api/v5/public/open-interest?instType=SWAP";
// Binance's own contract list, read for one field: `underlyingType`. A third of
// the perpetuals are not coins at all (equities, ETFs, metals, indices), and a
// ticker like NVDA or META also names an unrelated altcoin, so without this the
// supply table answers a stock with a coin's supply.
const EXCHANGE_INFO:&str="https://www.binance.com/fapi/v1/exchangeInfo";
// Where a listed company's market capitalisation comes from. stockanalysis.com
// is the one free source that answers for every venue these contracts track —
// New York, Hong Kong, Seoul, Shanghai — through one page shape, and answers it
// from the United States, where Yahoo's endpoints return 429 to everyone.
// `<path>/__data.json` is the data payload of the page a browser would render.
//
// Nasdaq's own screener was tried first and dropped: it prices a depositary
// share as if the ratio were a round one, which put SK hynix 44% above its real
// capitalisation, and it does not cover Hong Kong, Korea or Shanghai at all.
const STOCKANALYSIS:&str="https://stockanalysis.com/";
/// Hong Kong, Korean and Shanghai pages report a capitalisation in their own
/// market's currency; these rates bring it back to dollars.
const FX:&str="https://open.er-api.com/v6/latest/USD";
/// stockanalysis.com is asked once per equity contract, a couple of hundred
/// requests a day; this keeps them from arriving as a burst.
const LISTING_GAP:Duration=Duration::from_millis(200);

/// Supply moves in months, not seconds; one fetch a day is generous.
const SUPPLY_TTL:Duration=Duration::from_secs(24*60*60);
/// Open interest and price only need to be fresher than a glance at the header.
const LIVE_TTL:Duration=Duration::from_secs(15);
/// The quote assets a perpetual symbol can end with, longest spelling first.
const QUOTES:[&str;7]=["FDUSD","BUSD","TUSD","USDT","USDC","USDD","USD"];

pub fn routes()->Router<AppState> {
 Router::new().route("/v1/market/meta",get(meta))
 .route("/v1/market/open-interest",get(open_interest))
}

#[derive(Clone,Copy,Debug,Default,PartialEq)]
pub struct Meta {pub total_supply:Option<f64>,pub circulating_supply:Option<f64>,pub max_supply:Option<f64>,pub rank:Option<i64>}
impl Meta {
 fn empty(&self)->bool {self.total_supply.is_none()&&self.circulating_supply.is_none()&&self.max_supply.is_none()&&self.rank.is_none()}
 /// A `1000PEPE` contract is a bundle of 1000 coins, so its price is 1000x the
 /// coin's. For `supply x price` to stay equal to the coin's real market cap,
 /// the supply published under that symbol must be DIVIDED by the multiplier.
 /// Rank belongs to the coin and is not scaled.
 pub fn scaled(self,multiplier:f64)->Self {
  if !(multiplier.is_finite()&&multiplier>0.0) {return self}
  let by=|v:Option<f64>|v.map(|x|x/multiplier);
  Self{total_supply:by(self.total_supply),circulating_supply:by(self.circulating_supply),max_supply:by(self.max_supply),rank:self.rank}
 }
 pub fn value(&self)->Value {
  let mut out=serde_json::Map::new();
  if let Some(v)=self.total_supply {out.insert("totalSupply".into(),json!(v));}
  if let Some(v)=self.circulating_supply {out.insert("circulatingSupply".into(),json!(v));}
  if let Some(v)=self.max_supply {out.insert("maxSupply".into(),json!(v));}
  if let Some(v)=self.rank {out.insert("rank".into(),json!(v));}
  Value::Object(out)
 }
}
/// Keyed by base asset (`BTC`), never by contract symbol.
pub type SupplyTable=HashMap<String,Meta>;

/// What a contract's underlying really is, taken from Binance's own
/// `underlyingType`. A third of the perpetuals are not coins: US stocks, Hong
/// Kong, Korean and Shanghai listings, ETFs, metals, the BTCDOM index and
/// pre-IPO names all trade here, and a ticker like NVDA or COIN also names an
/// unrelated altcoin.
///
/// The two equity arms differ in one thing only: where the page lives. A US
/// ticker is its own address on stockanalysis.com (`stocks/NVDA`), while
/// everything else has to be named in `LISTINGS` — `SKHYNIX` is not a ticker
/// anywhere, and `stocks/SKHYNIX` would either miss or, worse, answer with some
/// unrelated American company. Guessing is not merely useless: `stocks/ANTH`
/// resolves to AN2 Therapeutics, nothing to do with Anthropic. The pre-IPO
/// names sit on the named arm too, under `private/<slug>`.
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Kind {Crypto,TickerEquity,NamedEquity,Other}
impl Kind {
 pub fn equity(self)->bool {matches!(self,Kind::TickerEquity|Kind::NamedEquity)}
}

/// One row of Binance's contract list, reduced to what the supply table needs.
#[derive(Clone,Debug,PartialEq)]
pub struct Contract {pub symbol:String,pub base:String,pub kind:Kind}

/// Everything a `/v1/market/meta` answer is built from, refreshed as one unit.
#[derive(Default)]
pub struct Market {
 /// Coin supply, keyed by base asset (`BTC`).
 pub coins:SupplyTable,
 /// Contract symbol (`AAPLUSDT`) -> the number its price is multiplied by to
 /// get the listed company's market capitalisation. See [`multiplier`]: it is
 /// deliberately not a share count.
 pub equities:HashMap<String,f64>,
 /// Contract symbol (`AAPLUSDT`) -> what it tracks.
 pub kinds:HashMap<String,Kind>,
}
impl Market {
 /// An unlisted symbol is read as a coin, which is what every OKX-only
 /// perpetual is; Binance lists no equity we would then get wrong.
 pub fn kind(&self,symbol:&str)->Kind {self.kinds.get(&plain(symbol)).copied().unwrap_or(Kind::Crypto)}
 /// The supply to publish for a contract symbol, or nothing.
 pub fn meta(&self,symbol:&str)->Option<Meta> {
  match self.kind(symbol) {
   Kind::Crypto=>lookup(&self.coins,symbol),
   // A stock whose capitalisation we could not resolve stays blank. Falling
   // back to the coin table here is exactly the bug this split exists to
   // prevent: NVDAUSDT would report the market cap of an altcoin that happens
   // to be called NVDA. ETFs, metals, indices and pre-IPO names have no
   // capitalisation at all, and blank is the honest answer for them too.
   Kind::TickerEquity|Kind::NamedEquity=>self.equities.get(&plain(symbol))
    .map(|k|Meta{total_supply:Some(*k),..Meta::default()}),
   Kind::Other=>None,
  }
 }
}

// ------------------------------------------------------------------- listings

/// Where a contract's underlying is really listed, for every contract whose
/// base asset is not simply a US ticker.
///
/// Binance names these in plain words (`SKHYNIX`, `TENCENT`) or by Hong Kong
/// board lot code (`HK0700`), and lists several the same company twice: `HK0700`
/// is Tencent quoted in Hong Kong dollars, `TENCENT` the same company quoted in
/// dollars per ordinary share. Both are pinned to the one listing, and
/// [`multiplier`] absorbs the difference in quote currency.
const LISTINGS:[(&str,&str);26]=[
 // 香港
 ("HK0700","quote/hkg/0700"),("TENCENT","quote/hkg/0700"),
 ("HK1810","quote/hkg/1810"),("HK0625","quote/hkg/0625"),("HK0992","quote/hkg/0992"),
 ("MEITUAN","quote/hkg/3690"),("KUAISHOU","quote/hkg/1024"),("POPMART","quote/hkg/9992"),
 ("BYD","quote/hkg/1211"),("MINIMAX","quote/hkg/0100"),("GIGADEV","quote/hkg/3986"),
 ("ZHONGJI","quote/hkg/3308"),("ZHIPU","quote/hkg/2513"),
 // 韩国
 ("SKHYNIX","quote/krx/000660"),("SAMSUNG","quote/krx/005930"),("HYUNDAI","quote/krx/005380"),
 ("SAMSUNGEM","quote/krx/009150"),("HANMI","quote/krx/042700"),
 ("LGELECTRONICS","quote/krx/066570"),("NAVER","quote/krx/035420"),
 // 上海
 ("CXMT","quote/sha/688825"),("UNITREE","quote/sha/688836"),
 // 未上市：估值页在 private/<slug> 下，用二级市场的「Implied Valuation」。
 ("ANTHROPIC","private/anthropic"),("OPENAI","private/openai"),
 // 美国，但合约名不是那个代码：伯克希尔 B 股写作 BRK.B，Quantinuum 的 QNT
 // 在币安被改名成 QNTX，因为 QNT 已经是一个币。
 ("BRKB","stocks/BRK.B"),("QNTX","stocks/QNT"),
];
/// The page to read for a contract, or nothing when we have no listing for it.
///
/// A foreign name we have never mapped stays blank on purpose: guessing
/// `stocks/<name>` is how a Korean contract ends up reporting an American
/// company's market cap.
pub fn listing(kind:Kind,base:&str)->Option<String> {
 if let Some((_,path))=LISTINGS.iter().find(|(name,_)|*name==base) {return Some((*path).to_owned())}
 let plain_ticker=!base.is_empty()&&base.chars().all(|c|c.is_ascii_alphanumeric());
 (kind==Kind::TickerEquity&&plain_ticker).then(||format!("stocks/{base}"))
}
/// The currency a listing's page reports its market capitalisation in.
pub fn listing_currency(path:&str)->&'static str {
 match path.split('/').nth(1).unwrap_or("") {
  "hkg"=>"HKD","krx"=>"KRW","sha"|"she"=>"CNY","tpe"=>"TWD",_=>"USD",
 }
}
/// What the header multiplies the price on screen by.
///
/// Deliberately not a share count. The same company trades here under
/// contracts quoted three different ways — in Hong Kong dollars (`HK0700`), in
/// dollars per ordinary share (`TENCENT`), and in dollars per depositary share
/// standing for some fraction of one (`SKHY`) — and a share count is only
/// right for the last of those if you also know the ratio, which is where the
/// Nasdaq screener went wrong by 44% on SK hynix. Dividing the company's real
/// capitalisation by the contract's own price folds quote currency, depositary
/// ratio and dual-class structure away at once, and what is left still tracks
/// the price tick by tick.
pub fn multiplier(cap_local:f64,rate:f64,price:f64)->Option<f64> {
 if !(cap_local>0.0&&rate>0.0&&price>0.0) {return None}
 let k=cap_local/rate/price;
 k.is_finite().then_some(k).filter(|x|*x>0.0)
}

// ---------------------------------------------------------------- symbol names

/// The symbol with its venue suffixes removed: `BTC-USDT-SWAP` -> `BTCUSDT`.
fn plain(symbol:&str)->String {
 let clean:String=symbol.to_ascii_uppercase().chars().filter(char::is_ascii_alphanumeric).collect();
 let clean=clean.strip_suffix("SWAP").filter(|r|!r.is_empty()).unwrap_or(&clean).to_owned();
 clean.strip_suffix("PERP").filter(|r|!r.is_empty()).unwrap_or(&clean).to_owned()
}
/// Strips the quote asset from a contract symbol: `BTC-USDT-SWAP` -> `BTC`.
/// A symbol with no recognised quote is returned whole, so a client asking for
/// a bare base still resolves. Where a pair is ambiguous (`USDTUSD` is USDT
/// against USD, not USD against TUSD) only [`base_candidates`] gets it right,
/// by asking the table which reading it knows.
pub fn strip_quote(symbol:&str)->String {
 let clean=plain(symbol);
 for quote in QUOTES {if let Some(rest)=clean.strip_suffix(quote) {if !rest.is_empty() {return rest.to_owned()}}}
 clean
}
/// Splits a bundle multiplier off a base asset: `1000PEPE` -> (`PEPE`, 1000).
/// `1INCH` is a coin and not a bundle, so only a run of three or more digits
/// counts, plus the older `1M`/`1K` spelling of the same thing.
pub fn strip_multiplier(base:&str)->(&str,f64) {
 let digits=base.chars().take_while(char::is_ascii_digit).count();
 if digits>=3 {
  if let Ok(multiplier)=base[..digits].parse::<f64>() {
   let rest=&base[digits..];
   if multiplier>=1000.0 && rest.len()>=2 {return (rest,multiplier)}
  }
 }
 for (prefix,multiplier) in [("1M",1e6),("1K",1e3)] {
  if let Some(rest)=base.strip_prefix(prefix) {
   if rest.len()>=3 && rest.starts_with(|c:char|c.is_ascii_alphabetic()) {return (rest,multiplier)}
  }
 }
 (base,1.0)
}
/// Every base a contract symbol could name, best reading first, each with the
/// multiplier its supply must be divided by.
///
/// Un-multiplied names come first on purpose: Binance's own table lists
/// `1000SATS` as an asset whose supply is *already* divided by 1000, so when it
/// knows the bundle we must take its figure rather than divide a second time.
/// Only a bundle it has never heard of (`1000PEPE`) falls through to the coin.
pub fn base_candidates(symbol:&str)->Vec<(String,f64)> {
 let clean=plain(symbol);
 let mut names=vec![clean.clone()];
 for quote in QUOTES {
  if let Some(rest)=clean.strip_suffix(quote) {if !rest.is_empty()&&!names.iter().any(|n|n==rest) {names.push(rest.to_owned())}}
 }
 let mut out:Vec<(String,f64)>=names.iter().map(|n|(n.clone(),1.0)).collect();
 for name in &names {
  let (base,multiplier)=strip_multiplier(name);
  if multiplier!=1.0 {out.push((base.to_owned(),multiplier))}
 }
 out
}
/// Resolves a contract symbol against the supply table, taking the first
/// reading the table actually knows. That is also what settles an ambiguous
/// pair: `USDTUSD` could be read as USD/TUSD, but only USDT is a listed asset.
pub fn lookup(table:&SupplyTable,symbol:&str)->Option<Meta> {
 base_candidates(symbol).into_iter().find_map(|(base,multiplier)|table.get(&base).map(|meta|meta.scaled(multiplier)))
}
/// `BTCUSDT` -> `BTC-USDT-SWAP`; an instrument id passed in as-is stays intact.
pub fn okx_instrument(symbol:&str)->String {
 let up=symbol.to_ascii_uppercase();
 if up.contains('-') {return if up.ends_with("-SWAP"){up}else{format!("{up}-SWAP")}}
 let clean:String=up.chars().filter(char::is_ascii_alphanumeric).collect();
 for quote in QUOTES {
  if let Some(rest)=clean.strip_suffix(quote) {if !rest.is_empty() {return format!("{rest}-{quote}-SWAP")}}
 }
 format!("{clean}-USDT-SWAP")
}

// -------------------------------------------------------------------- parsing

fn num(v:&Value)->Option<f64> {
 match v {Value::Number(n)=>n.as_f64(),Value::String(s)=>s.trim().parse().ok(),_=>None}.filter(|x:&f64|x.is_finite())
}
/// Upstreams spell "unknown" as 0 (or a negative), notably `maxSupply`.
fn positive(v:&Value)->Option<f64> {num(v).filter(|x|*x>0.0)}
fn rank_of(v:&Value)->Option<i64> {
 match v {Value::Number(n)=>n.as_i64(),Value::String(s)=>s.trim().parse().ok(),_=>None}.filter(|r|*r>0)
}
/// Finds the row array whichever envelope the upstream wraps it in this week.
fn rows(body:&Value)->&[Value] {
 for candidate in [body,&body["data"],&body["data"]["list"],&body["data"]["rows"],&body["result"]] {
  if let Some(array)=candidate.as_array() {if !array.is_empty() {return array}}
 }
 &[]
}
/// Fills only the fields the table is still missing, so earlier (better) sources win.
fn fill(table:&mut SupplyTable,base:&str,meta:Meta) {
 if base.is_empty()||meta.empty() {return}
 let slot=table.entry(base.to_owned()).or_default();
 slot.total_supply=slot.total_supply.or(meta.total_supply);
 slot.circulating_supply=slot.circulating_supply.or(meta.circulating_supply);
 slot.max_supply=slot.max_supply.or(meta.max_supply);
 slot.rank=slot.rank.or(meta.rank);
}
/// Binance apex marketing list: `symbol` is a spot pair such as `BTCUSDT` and
/// `baseAsset` names its coin outright, which is the only way to read a pair
/// like `USDTUSD` correctly.
pub fn parse_apex(body:&Value,table:&mut SupplyTable) {
 for row in rows(body) {
  let base=match (row["baseAsset"].as_str(),row["symbol"].as_str()) {
   (Some(base),_)=>base.to_ascii_uppercase(),
   (None,Some(symbol))=>strip_quote(symbol),
   (None,None)=>continue,
  };
  let meta=Meta{total_supply:positive(&row["totalSupply"]),circulating_supply:positive(&row["circulatingSupply"]),max_supply:positive(&row["maxSupply"]),rank:rank_of(&row["rank"])};
  fill(table,&base,meta);
 }
}
/// Binance product list: `b` is the base asset, `cs` its circulating supply.
pub fn parse_products(body:&Value,table:&mut SupplyTable) {
 for row in rows(body) {
  let Some(base)=row["b"].as_str() else {continue};
  fill(table,&base.to_ascii_uppercase(),Meta{circulating_supply:positive(&row["cs"]),..Meta::default()});
 }
}
/// CoinGecko markets page, used only for coins Binance never listed on spot.
pub fn parse_coingecko(body:&Value,table:&mut SupplyTable) {
 for row in rows(body) {
  let Some(symbol)=row["symbol"].as_str() else {continue};
  let meta=Meta{total_supply:positive(&row["total_supply"]),circulating_supply:positive(&row["circulating_supply"]),max_supply:positive(&row["max_supply"]),rank:rank_of(&row["market_cap_rank"])};
  fill(table,&symbol.to_ascii_uppercase(),meta);
 }
}
/// A capitalisation as these pages print it: `"1,271.87T"`, `"$4.90T"`, or a
/// bare number. Only positive amounts count; anything else is unknown.
pub fn money(v:&Value)->Option<f64> {
 let text=match v {
  Value::String(s)=>s.trim().trim_start_matches('$').replace(',',""),
  other=>return positive(other),
 };
 let (digits,scale)=match text.chars().last() {
  Some('T')=>(&text[..text.len()-1],1e12),
  Some('B')=>(&text[..text.len()-1],1e9),
  Some('M')=>(&text[..text.len()-1],1e6),
  Some('K')=>(&text[..text.len()-1],1e3),
  _=>(&text[..],1.0),
 };
 digits.parse::<f64>().ok().map(|x|x*scale).filter(|x:&f64|x.is_finite()&&*x>0.0)
}
/// stockanalysis.com ships a page's data the way SvelteKit serialises it: a
/// flat array whose first element is an index map, so `data[0]["marketCap"]` is
/// not the number but where to find it.
///
/// An ETF page has no `marketCap` at all — it reports assets under management,
/// which is not a capitalisation and must not be shown as one — so a page we
/// cannot read a capitalisation out of is simply left blank.
pub fn parse_stockanalysis_cap(body:&Value)->Option<f64> {
 for node in body["nodes"].as_array()? {
  let Some(data)=node["data"].as_array() else {continue};
  let Some(head)=data.first().and_then(Value::as_object) else {continue};
  let Some(index)=head.get("marketCap").and_then(Value::as_u64) else {continue};
  if let Some(cap)=data.get(index as usize).and_then(money) {return Some(cap)}
 }
 parse_private_valuation(body)
}
/// A company that has not listed has no market capitalisation, so its page
/// carries a stat list instead of a `marketCap` field. Two entries there could
/// stand in: `Valuation`, the post-money figure of the last funding round, and
/// `Implied Valuation`, what the secondary market is paying right now. The
/// implied one is preferred because it moves with the same trading the
/// perpetual tracks; the round figure is months stale by construction and only
/// used when no implied one is published.
fn parse_private_valuation(body:&Value)->Option<f64> {
 let mut fallback=None;
 for node in body["nodes"].as_array()? {
  let Some(data)=node["data"].as_array() else {continue};
  let Some(head)=data.first().and_then(Value::as_object) else {continue};
  let Some(index)=head.get("statsLeft").and_then(Value::as_u64) else {continue};
  let Some(stats)=data.get(index as usize).and_then(Value::as_array) else {continue};
  for entry in stats {
   let Some(row)=entry.as_u64().and_then(|i|data.get(i as usize)).and_then(Value::as_object) else {continue};
   let label=row.get("label").and_then(Value::as_u64).and_then(|i|data.get(i as usize)).and_then(Value::as_str);
   let value=row.get("value").and_then(Value::as_u64).and_then(|i|data.get(i as usize)).and_then(money);
   match (label,value) {
    (Some("Implied Valuation"),Some(cap))=>return Some(cap),
    (Some("Valuation"),Some(cap))=>fallback=fallback.or(Some(cap)),
    _=>{}
   }
  }
 }
 fallback
}
/// `{"result":"success","base_code":"USD","rates":{"HKD":7.844,...}}` — units of
/// the listed currency per dollar.
pub fn parse_fx(body:&Value)->HashMap<String,f64> {
 let mut out=HashMap::from([("USD".to_owned(),1.0)]);
 if let Some(rates)=body["rates"].as_object() {
  for (code,value) in rates {
   if let Some(rate)=positive(value) {out.insert(code.to_ascii_uppercase(),rate);}
  }
 }
 out
}
/// Binance `exchangeInfo` -> what each contract is and what it is written on.
/// The base asset is taken from the row rather than sliced off the symbol:
/// Binance quotes in USDT, USDC, USD1, U and BTC, so `SPCXUSD1` reads as SPCX
/// only because the row says so. A symbol with no `underlyingType` counts as a
/// coin, which is what everything here was before Binance listed anything else.
pub fn parse_exchange_info(body:&Value)->Vec<Contract> {
 let mut out=Vec::new();
 for row in rows(&body["symbols"]) {
  let Some(symbol)=row["symbol"].as_str() else {continue};
  let kind=match row["underlyingType"].as_str() {
   None|Some("COIN")=>Kind::Crypto,
   Some("EQUITY")=>Kind::TickerEquity,
   Some("HK_EQUITY")|Some("KR_EQUITY")|Some("CN_EQUITY")|Some("PREMARKET")=>Kind::NamedEquity,
   // Metals, oil and the BTCDOM index: no company, so no capitalisation.
   Some(_)=>Kind::Other,
  };
  let base=match row["baseAsset"].as_str() {
   Some(base)=>base.to_ascii_uppercase(),
   None=>strip_quote(symbol),
  };
  out.push(Contract{symbol:plain(symbol),base,kind});
 }
 out
}
/// Contract symbol -> kind, which is all the served table needs to keep.
pub fn kinds_of(contracts:&[Contract])->HashMap<String,Kind> {
 contracts.iter().map(|c|(c.symbol.clone(),c.kind)).collect()
}

/// Only the symbols asked for, and only the ones we actually know: a base we
/// cannot resolve is absent from `data` rather than present and null.
pub fn meta_payload(market:&Market,symbols:Option<&str>)->Value {
 let mut out=serde_json::Map::new();
 match symbols {
  Some(list)=>for name in list.split(',').map(str::trim).filter(|s|!s.is_empty()).take(1000) {
   let key=name.to_ascii_uppercase();
   if out.contains_key(&key) {continue}
   if let Some(meta)=market.meta(&key) {out.insert(key,meta.value());}
  },
  // The unfiltered form lists coins only: the share table holds every stock
  // Nasdaq quotes, thousands of which Binance never made a contract for.
  None=>for (base,meta) in &market.coins {
   let symbol=format!("{base}USDT");
   if market.kind(&symbol)==Kind::Crypto {out.insert(symbol,meta.value());}
  },
 }
 Value::Object(out)
}

#[derive(Clone,Copy,Debug,PartialEq)]
pub struct OpenInterest {pub open_interest:f64,pub value:Option<f64>,pub time:i64}
/// `{"symbol":"BTCUSDT","openInterest":"108431.724","time":1789661435379}`.
/// The amount is coin-denominated and Binance does not send a notional.
pub fn parse_binance_oi(body:&Value)->Option<OpenInterest> {
 Some(OpenInterest{open_interest:num(&body["openInterest"])?,value:None,time:body["time"].as_i64().unwrap_or(0)})
}
/// `/fapi/v1/ticker/price` -> `{"BTCUSDT":64123.4,...}`.
pub fn parse_binance_prices(body:&Value)->HashMap<String,f64> {
 let mut out=HashMap::new();
 for row in rows(body) {
  if let (Some(symbol),Some(price))=(row["symbol"].as_str(),positive(&row["price"])) {out.insert(symbol.to_ascii_uppercase(),price);}
 }
 out
}
/// OKX sends every swap at once: `oiCcy` is coin-denominated, `oiUsd` notional.
pub fn parse_okx_oi(body:&Value)->HashMap<String,OpenInterest> {
 let mut out=HashMap::new();
 for row in rows(body) {
  let Some(instrument)=row["instId"].as_str() else {continue};
  let Some(amount)=num(&row["oiCcy"]).or_else(||num(&row["oi"])) else {continue};
  let time=row["ts"].as_str().and_then(|t|t.parse().ok()).or_else(||row["ts"].as_i64()).unwrap_or(0);
  out.insert(instrument.to_ascii_uppercase(),OpenInterest{open_interest:amount,value:num(&row["oiUsd"]),time});
 }
 out
}
fn oi_payload(symbol:&str,oi:&OpenInterest)->Value {
 let mut out=serde_json::Map::new();
 out.insert("symbol".into(),json!(symbol));
 out.insert("openInterest".into(),json!(oi.open_interest));
 if let Some(value)=oi.value {out.insert("openInterestValue".into(),json!(value));}
 out.insert("time".into(),json!(oi.time));
 Value::Object(out)
}

// --------------------------------------------------------------------- caches

struct Cache<T> {slot:std::sync::RwLock<Option<(Instant,Arc<T>)>>}
impl<T> Cache<T> {
 fn new()->Self {Self{slot:std::sync::RwLock::new(None)}}
 fn read(&self)->Option<(Instant,Arc<T>)> {self.slot.read().unwrap_or_else(|e|e.into_inner()).clone()}
 fn fresh(&self,ttl:Duration)->Option<Arc<T>> {self.read().filter(|(at,_)|at.elapsed()<ttl).map(|(_,v)|v)}
 fn stale(&self)->Option<Arc<T>> {self.read().map(|(_,v)|v)}
 fn store(&self,value:T)->Arc<T> {
  let value=Arc::new(value);
  *self.slot.write().unwrap_or_else(|e|e.into_inner())=Some((Instant::now(),value.clone()));
  value
 }
}
/// Per-symbol slots for the one upstream that answers a single symbol at a time.
struct Recent<T> {slots:std::sync::Mutex<HashMap<String,(Instant,T)>>}
impl<T:Clone> Recent<T> {
 fn new()->Self {Self{slots:std::sync::Mutex::new(HashMap::new())}}
 fn get(&self,key:&str,ttl:Duration)->Option<T> {
  self.slots.lock().unwrap_or_else(|e|e.into_inner()).get(key).filter(|(at,_)|at.elapsed()<ttl).map(|(_,v)|v.clone())
 }
 fn put(&self,key:&str,value:T) {
  let mut slots=self.slots.lock().unwrap_or_else(|e|e.into_inner());
  if slots.len()>=512 {slots.clear()}
  slots.insert(key.to_owned(),(Instant::now(),value));
 }
}
fn supply_cache()->&'static Cache<Market> {static C:OnceLock<Cache<Market>>=OnceLock::new();C.get_or_init(Cache::new)}
fn price_cache()->&'static Cache<HashMap<String,f64>> {static C:OnceLock<Cache<HashMap<String,f64>>>=OnceLock::new();C.get_or_init(Cache::new)}
fn okx_cache()->&'static Cache<HashMap<String,OpenInterest>> {static C:OnceLock<Cache<HashMap<String,OpenInterest>>>=OnceLock::new();C.get_or_init(Cache::new)}
fn binance_oi_cache()->&'static Recent<OpenInterest> {static C:OnceLock<Recent<OpenInterest>>=OnceLock::new();C.get_or_init(Recent::new)}

// -------------------------------------------------------------------- fetching

fn upstream()->ApiError {ApiError(StatusCode::SERVICE_UNAVAILABLE,"market_upstream_unavailable")}
fn http()->&'static reqwest::Client {
 static HTTP:OnceLock<reqwest::Client>=OnceLock::new();
 HTTP.get_or_init(||reqwest::Client::builder().timeout(Duration::from_secs(20))
  // These are the endpoints binance.com itself calls; the default agent string
  // is the kind of thing such a front door refuses.
  .user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
  .build().expect("HTTP client"))
}
async fn get_json(url:&str)->Result<Value> {
 let response=http().get(url).send().await.map_err(|_|upstream())?.error_for_status().map_err(|_|upstream())?;
 response.json::<Value>().await.map_err(|_|upstream())
}
/// One equity contract's multiplier, or nothing when it has no listing we can
/// read. `Err` means the page could not be fetched at all, which is the only
/// case where the previous refresh's answer should be kept: a page that loads
/// and carries no capitalisation (every ETF) is genuinely blank.
async fn equity_multiplier(contract:&Contract,fx:&HashMap<String,f64>,prices:&HashMap<String,f64>)->Result<Option<f64>> {
 let Some(path)=listing(contract.kind,&contract.base) else {return Ok(None)};
 let Some(price)=prices.get(&contract.symbol).copied() else {return Ok(None)};
 let url=format!("{STOCKANALYSIS}{path}/__data.json");
 // The site occasionally answers a real listing with a challenge page instead
 // of JSON; one immediate retry is what separates "Visa is blank today" from
 // "Visa is blank for one refresh". Two failures in a row count as unreadable.
 let body=match get_json(&url).await {
  Ok(body)=>body,
  Err(_)=>{tokio::time::sleep(LISTING_GAP).await;get_json(&url).await?}
 };
 let Some(cap)=parse_stockanalysis_cap(&body) else {return Ok(None)};
 let rate=fx.get(listing_currency(&path)).copied().unwrap_or(0.0);
 Ok(multiplier(cap,rate,price))
}
/// Asks stockanalysis.com for every equity contract, one page at a time.
///
/// Anything unreadable falls back to what the last refresh knew rather than to
/// a guess: a blank cell beats another company's market cap. If the rates or
/// the price list are missing there is nothing to compute at all, so the whole
/// previous table is kept.
async fn refresh_equities(contracts:&[Contract],previous:Option<&HashMap<String,f64>>)->HashMap<String,f64> {
 let carried=||previous.cloned().unwrap_or_default();
 let wanted:Vec<&Contract>=contracts.iter().filter(|c|c.kind.equity()).collect();
 if wanted.is_empty() {return carried()}
 let fx=match get_json(FX).await {
  Ok(body)=>parse_fx(&body),
  Err(_)=>{tracing::warn!("Supply: exchange rates unavailable");return carried()}
 };
 let prices=match get_json(BINANCE_PRICES).await {
  Ok(body)=>parse_binance_prices(&body),
  Err(_)=>{tracing::warn!("Supply: contract prices unavailable");return carried()}
 };
 let mut out=HashMap::new();
 let mut kept=0usize;
 for contract in wanted {
  match equity_multiplier(contract,&fx,&prices).await {
   Ok(Some(k))=>{out.insert(contract.symbol.clone(),k);},
   Ok(None)=>{}
   Err(_)=>{
    if let Some(k)=previous.and_then(|p|p.get(&contract.symbol)) {out.insert(contract.symbol.clone(),*k);kept+=1;}
   }
  }
  tokio::time::sleep(LISTING_GAP).await;
 }
 if kept>0 {tracing::warn!("Supply: {kept} equity pages unreadable, kept the previous figures")}
 out
}
/// Rebuilds the whole table. Apex is the main coin source, the product list
/// fills circulating supply, CoinGecko covers coins Binance never listed,
/// `exchangeInfo` says which contract is which, and stockanalysis.com prices
/// the companies behind the equity contracts. Any single upstream may fail
/// without losing the others.
pub async fn refresh_supply()->Result<Arc<Market>> {
 let previous=supply_cache().stale();
 let mut coins=SupplyTable::new();
 match get_json(APEX).await {Ok(body)=>parse_apex(&body,&mut coins),Err(_)=>tracing::warn!("Supply: apex list unavailable")}
 match get_json(PRODUCTS).await {Ok(body)=>parse_products(&body,&mut coins),Err(_)=>tracing::warn!("Supply: product list unavailable")}
 for page in 1..=COINGECKO_PAGES {
  match get_json(&format!("{COINGECKO}{page}")).await {
   Ok(body)=>parse_coingecko(&body,&mut coins),
   // CoinGecko rate-limits anonymous callers; one refused page ends the sweep.
   Err(_)=>{tracing::warn!("Supply: CoinGecko page {page} unavailable");break}
  }
  tokio::time::sleep(Duration::from_millis(1200)).await;
 }
 let contracts=match get_json(EXCHANGE_INFO).await {
  Ok(body)=>parse_exchange_info(&body),
  Err(_)=>{tracing::warn!("Supply: exchangeInfo unavailable");Vec::new()}
 };
 let (kinds,equities)=if contracts.is_empty() {
  // Without the contract list every stock would read as a coin, so the old
  // classification stands until Binance answers again.
  let old=previous.as_ref();
  (old.map(|m|m.kinds.clone()).unwrap_or_default(),old.map(|m|m.equities.clone()).unwrap_or_default())
 } else {
  (kinds_of(&contracts),refresh_equities(&contracts,previous.as_ref().map(|m|&m.equities)).await)
 };
 if coins.is_empty() {return Err(upstream())}
 tracing::info!("Supply table refreshed: {} coins, {} equities priced, {} contracts classified",coins.len(),equities.len(),kinds.len());
 Ok(supply_cache().store(Market{coins,equities,kinds}))
}
async fn supply_table()->Result<Arc<Market>> {
 if let Some(table)=supply_cache().fresh(SUPPLY_TTL) {return Ok(table)}
 if let Some(table)=supply_cache().stale() {
  // A day-old table is still a correct answer; refresh behind the request
  // rather than making someone wait several seconds on upstreams.
  if !refreshing().swap(true,Ordering::SeqCst) {
   tokio::spawn(async {let _=refresh_supply().await;refreshing().store(false,Ordering::SeqCst);});
  }
  return Ok(table);
 }
 refresh_supply().await
}
fn refreshing()->&'static AtomicBool {static R:AtomicBool=AtomicBool::new(false);&R}
/// Keeps the table warm from boot so no request ever pays for the cold fetch.
pub fn spawn_refresh() {
 tokio::spawn(async {
  loop {
   let wait=if refresh_supply().await.is_ok() {SUPPLY_TTL} else {Duration::from_secs(600)};
   tokio::time::sleep(wait).await;
  }
 });
}
async fn binance_price(symbol:&str)->Option<f64> {
 let prices=match price_cache().fresh(LIVE_TTL) {
  Some(prices)=>prices,
  None=>match get_json(BINANCE_PRICES).await {
   Ok(body)=>price_cache().store(parse_binance_prices(&body)),
   // Without a price the notional is simply absent; the amount still stands.
   Err(_)=>price_cache().stale()?,
  }
 };
 prices.get(symbol).copied()
}
async fn binance_open_interest(symbol:&str)->Result<OpenInterest> {
 let mut oi=match binance_oi_cache().get(symbol,LIVE_TTL) {
  Some(oi)=>oi,
  None=>{
   let body=get_json(&format!("{BINANCE_OI}{symbol}")).await?;
   let oi=parse_binance_oi(&body).ok_or_else(||ApiError(StatusCode::SERVICE_UNAVAILABLE,"invalid_market_response"))?;
   binance_oi_cache().put(symbol,oi);oi
  }
 };
 oi.value=binance_price(symbol).await.map(|price|oi.open_interest*price);
 Ok(oi)
}
async fn okx_open_interest(symbol:&str)->Result<OpenInterest> {
 let table=match okx_cache().fresh(LIVE_TTL) {
  Some(table)=>table,
  None=>match get_json(OKX_OI).await {Ok(body)=>okx_cache().store(parse_okx_oi(&body)),Err(e)=>okx_cache().stale().ok_or(e)?}
 };
 table.get(&okx_instrument(symbol)).copied().ok_or_else(ApiError::missing)
}

// ------------------------------------------------------------------- handlers

#[derive(Deserialize,Default)] #[serde(deny_unknown_fields)] struct MetaQuery {symbols:Option<String>}
async fn meta(Query(q):Query<MetaQuery>)->Result<Json<Value>> {
 if q.symbols.as_ref().is_some_and(|s|s.len()>16*1024) {return Err(ApiError::bad("invalid_symbols"))}
 let table=supply_table().await?;
 Ok(envelope(meta_payload(&table,q.symbols.as_deref())))
}
#[derive(Deserialize)] #[serde(deny_unknown_fields)] struct OiQuery {symbol:String,source:Option<String>}
async fn open_interest(Query(q):Query<OiQuery>)->Result<Json<Value>> {
 let symbol:String=q.symbol.to_ascii_uppercase();
 if symbol.is_empty()||symbol.len()>32||!symbol.chars().all(|c|c.is_ascii_alphanumeric()||c=='-') {return Err(ApiError::bad("invalid_symbol"))}
 let oi=match q.source.as_deref().unwrap_or("binance") {
  "binance"=>{
   let plain:String=symbol.chars().filter(char::is_ascii_alphanumeric).collect();
   binance_open_interest(&plain).await?
  },
  "okx"=>okx_open_interest(&symbol).await?,
  _=>return Err(ApiError::bad("invalid_source")),
 };
 Ok(envelope(oi_payload(&symbol,&oi)))
}

#[cfg(test)]
mod tests {
 use super::*;

 fn table(pairs:&[(&str,Meta)])->SupplyTable {pairs.iter().map(|(k,v)|((*k).to_owned(),*v)).collect()}
 fn supply(total:f64)->Meta {Meta{total_supply:Some(total),circulating_supply:Some(total),max_supply:None,rank:None}}
 fn market(coins:SupplyTable)->Market {Market{coins,..Market::default()}}

 #[test]
 fn apex_rows_parse_and_an_absent_cap_means_unknown() {
  let body=json!({"code":"000000","success":true,"data":[
   {"symbol":"BTCUSDT","baseAsset":"BTC","quoteAsset":"USDT","circulatingSupply":19_800_000.0,"totalSupply":19_800_000.0,"maxSupply":21_000_000.0,"rank":1},
   {"symbol":"ETHUSDT","baseAsset":"ETH","quoteAsset":"USDT","circulatingSupply":"120500000","totalSupply":"120500000","maxSupply":null,"rank":"2"}]});
  let mut t=SupplyTable::new();parse_apex(&body,&mut t);
  assert_eq!(t["BTC"],Meta{total_supply:Some(19_800_000.0),circulating_supply:Some(19_800_000.0),max_supply:Some(21_000_000.0),rank:Some(1)});
  assert_eq!(t["ETH"].max_supply,None);
  assert_eq!(t["ETH"].rank,Some(2));
 }
 #[test]
 fn an_ambiguous_pair_is_read_by_its_declared_base() {
  // USDTUSD is USDT against USD; read off the suffix alone it looks like USD
  // against TUSD, which would file the supply of Tether under the wrong name.
  let body=json!({"data":[{"symbol":"USDTUSD","baseAsset":"USDT","quoteAsset":"USD","circulatingSupply":183_442_587_855.0_f64,"totalSupply":183_442_587_855.0_f64}]});
  let mut t=SupplyTable::new();parse_apex(&body,&mut t);
  assert!(t.contains_key("USDT")&&!t.contains_key("USD"));
  assert!(lookup(&t,"USDTUSD").is_some(),"and the same pair resolves back out");
 }
 #[test]
 fn a_quote_that_is_a_prefix_of_the_base_still_resolves() {
  let t=table(&[("ETH",supply(120_500_000.0))]);
  assert!(lookup(&t,"ETHFDUSD").is_some());
  assert!(lookup(&t,"ETHUSDC").is_some());
 }
 #[test]
 fn a_broken_row_does_not_break_the_table() {
  let body=json!({"data":[{"nonsense":true},{"symbol":"BTCUSDT","baseAsset":"BTC","totalSupply":"n/a"},{"symbol":"SOLUSDT","baseAsset":"SOL","totalSupply":600_000_000.0}]});
  let mut t=SupplyTable::new();parse_apex(&body,&mut t);
  assert_eq!(t.len(),1);
  assert_eq!(t["SOL"].total_supply,Some(600_000_000.0));
 }
 #[test]
 fn products_only_fill_what_apex_left_empty() {
  let body=json!({"data":[{"s":"BTCUSDT","b":"BTC","q":"USDT","cs":19_900_000.0},{"s":"HYPEUSDT","b":"HYPE","q":"USDT","cs":333_000_000.0}]});
  let mut t=table(&[("BTC",Meta{total_supply:Some(21_000_000.0),..Meta::default()})]);
  parse_products(&body,&mut t);
  assert_eq!(t["BTC"].total_supply,Some(21_000_000.0));
  assert_eq!(t["BTC"].circulating_supply,Some(19_900_000.0));
  assert_eq!(t["HYPE"].circulating_supply,Some(333_000_000.0));
 }
 #[test]
 fn coingecko_fills_the_gap_binance_never_listed() {
  let body=json!([{"symbol":"xmr","total_supply":18_400_000.0,"circulating_supply":18_400_000.0,"max_supply":null,"market_cap_rank":42}]);
  let mut t=SupplyTable::new();parse_coingecko(&body,&mut t);
  assert_eq!(t["XMR"].total_supply,Some(18_400_000.0));
  assert_eq!(t["XMR"].max_supply,None);
  assert_eq!(t["XMR"].rank,Some(42));
 }
 #[test]
 fn quote_assets_come_off_the_symbol() {
  assert_eq!(strip_quote("BTCUSDT"),"BTC");
  assert_eq!(strip_quote("ETHFDUSD"),"ETH");
  assert_eq!(strip_quote("BTC-USDT-SWAP"),"BTC");
  assert_eq!(strip_quote("USDCUSDT"),"USDC");
  assert_eq!(strip_quote("BTC"),"BTC");
 }
 #[test]
 fn only_bundles_lose_their_prefix() {
  assert_eq!(strip_multiplier("1000PEPE"),("PEPE",1000.0));
  assert_eq!(strip_multiplier("1000000MOG"),("MOG",1e6));
  assert_eq!(strip_multiplier("1MBABYDOGE"),("BABYDOGE",1e6));
  assert_eq!(strip_multiplier("1INCH"),("1INCH",1.0));
  assert_eq!(strip_multiplier("BTC"),("BTC",1.0));
 }
 #[test]
 fn a_bundle_keeps_the_coins_market_cap() {
  // One 1000PEPE contract is 1000 PEPE, so it trades at 1000x the coin price.
  // Dividing the supply is the only direction that leaves the cap unchanged.
  let coin_supply=420_690_000_000.0_f64;let coin_price=0.000_012_f64;
  let t=table(&[("PEPE",supply(coin_supply))]);
  let meta=lookup(&t,"1000PEPEUSDT").expect("bundle resolves to its coin");
  assert_eq!(meta.total_supply,Some(coin_supply/1000.0));
  let bundle_cap=meta.total_supply.unwrap()*(coin_price*1000.0);
  assert!((bundle_cap-coin_supply*coin_price).abs()<1e-6,"{bundle_cap}");
 }
 #[test]
 fn a_bundle_binance_itself_lists_is_not_divided_again() {
  // Binance files 1000SATS as its own asset with the supply already divided:
  // 2.1e15 satoshis become 2.1e12 bundles. Dividing that a second time would
  // report a market cap a thousandth of the real one.
  let coin_supply=2_100_000_000_000_000.0_f64;
  let t=table(&[("1000SATS",supply(coin_supply/1000.0)),("SATS",supply(coin_supply))]);
  assert_eq!(lookup(&t,"1000SATSUSDT").unwrap().total_supply,Some(coin_supply/1000.0));
 }
 #[test]
 fn symbols_filter_omits_what_we_cannot_resolve() {
  let t=market(table(&[("BTC",supply(19_800_000.0)),("ETH",supply(120_500_000.0))]));
  let payload=meta_payload(&t,Some("BTCUSDT, ethusdt ,HYPEUSDT,,BTCUSDT"));
  let map=payload.as_object().unwrap();
  assert_eq!(map.len(),2);
  assert!(map.contains_key("BTCUSDT")&&map.contains_key("ETHUSDT"));
  assert!(!map.contains_key("HYPEUSDT"),"an unknown base must be absent, not null");
  assert_eq!(map["BTCUSDT"]["totalSupply"],json!(19_800_000.0));
 }
 #[test]
 fn omitting_symbols_returns_the_whole_table() {
  let t=market(table(&[("BTC",supply(19_800_000.0))]));
  let payload=meta_payload(&t,None);
  assert_eq!(payload.as_object().unwrap().len(),1);
  assert!(payload["BTCUSDT"]["circulatingSupply"].is_number());
 }
 #[test]
 fn missing_fields_are_dropped_rather_than_nulled() {
  let value=Meta{total_supply:Some(1.0),..Meta::default()}.value();
  assert_eq!(value,json!({"totalSupply":1.0}));
 }
 #[test]
 fn binance_open_interest_parses_its_coin_amount() {
  let body=json!({"symbol":"BTCUSDT","openInterest":"108431.724","time":1_789_661_435_379_i64});
  let oi=parse_binance_oi(&body).unwrap();
  assert_eq!(oi.open_interest,108_431.724);
  assert_eq!(oi.time,1_789_661_435_379);
  assert_eq!(oi.value,None,"Binance sends no notional; the server multiplies");
  assert!(parse_binance_oi(&json!({"symbol":"BTCUSDT"})).is_none());
 }
 #[test]
 fn prices_turn_the_amount_into_a_notional() {
  let prices=parse_binance_prices(&json!([{"symbol":"BTCUSDT","price":"76700.0"},{"symbol":"ETHUSDT","price":"0"}]));
  assert_eq!(prices.len(),1);
  let oi=parse_binance_oi(&json!({"symbol":"BTCUSDT","openInterest":"100","time":1})).unwrap();
  assert_eq!(oi.open_interest*prices["BTCUSDT"],7_670_000.0);
 }
 #[test]
 fn okx_swaps_parse_with_their_own_notional() {
  let body=json!({"code":"0","data":[{"instId":"BTC-USDT-SWAP","oi":"1084317","oiCcy":"10843.17","oiUsd":"832000000","ts":"1789661435379"}]});
  let table=parse_okx_oi(&body);
  let oi=table["BTC-USDT-SWAP"];
  assert_eq!(oi.open_interest,10_843.17);
  assert_eq!(oi.value,Some(832_000_000.0));
  assert_eq!(oi.time,1_789_661_435_379);
 }
 #[test]
 fn okx_instrument_ids_are_built_from_the_plain_symbol() {
  assert_eq!(okx_instrument("BTCUSDT"),"BTC-USDT-SWAP");
  assert_eq!(okx_instrument("btc-usdt-swap"),"BTC-USDT-SWAP");
  assert_eq!(okx_instrument("PEPE-USDT"),"PEPE-USDT-SWAP");
 }
 #[test]
 fn oi_payload_drops_an_unknown_notional() {
  let out=oi_payload("BTCUSDT",&OpenInterest{open_interest:1.5,value:None,time:7});
  assert_eq!(out,json!({"symbol":"BTCUSDT","openInterest":1.5,"time":7}));
 }
 #[test]
 fn a_stock_is_never_answered_out_of_the_coin_table() {
  // NVDA and META are both a listed company and an unrelated altcoin. Before
  // the contract list was consulted, NVDAUSDT reported the altcoin's supply,
  // which put a 15-million-dollar market cap on Nvidia.
  let mut m=market(table(&[("NVDA",supply(91_937.5)),("BTC",supply(19_800_000.0))]));
  m.equities=[("NVDAUSDT".to_owned(),24_100_000_000.0)].into_iter().collect();
  m.kinds=[("NVDAUSDT",Kind::TickerEquity),("BTCUSDT",Kind::Crypto),("XAUUSDT",Kind::Other)]
   .iter().map(|(k,v)|((*k).to_owned(),*v)).collect();
  assert_eq!(m.meta("NVDAUSDT").unwrap().total_supply,Some(24_100_000_000.0));
  assert_eq!(m.meta("BTCUSDT").unwrap().total_supply,Some(19_800_000.0));
  assert_eq!(m.meta("XAUUSDT"),None,"gold has no market cap to report");
 }
 #[test]
 fn an_equity_we_could_not_price_stays_blank() {
  // ETFs (SPY holds shares, it does not issue a capitalisation) and companies
  // that are not listed anywhere yet. Blank is the answer; the coin table must
  // not be consulted, however well the ticker matches a coin.
  let mut m=market(table(&[("SPY",supply(1_000_000.0))]));
  m.kinds=[("SPYUSDT".to_owned(),Kind::TickerEquity)].into_iter().collect();
  assert_eq!(m.meta("SPYUSDT"),None);
  assert!(meta_payload(&m,Some("SPYUSDT")).as_object().unwrap().is_empty());
 }
 #[test]
 fn an_unlisted_symbol_is_still_read_as_a_coin() {
  // OKX lists perpetuals Binance never did; those have no classification and
  // must keep resolving the way they always have.
  let m=market(table(&[("PEPE",supply(420_690_000_000.0))]));
  assert!(m.meta("PEPE-USDT-SWAP").is_some());
  assert!(m.meta("1000PEPEUSDT").is_some());
 }
 #[test]
 fn a_capitalisation_reads_in_every_spelling_these_pages_use() {
  assert_eq!(money(&json!("$4.90T")),Some(4.90e12));
  assert_eq!(money(&json!("1,271.87T")),Some(1_271.87e12));
  assert_eq!(money(&json!("929.61B")),Some(929.61e9));
  assert_eq!(money(&json!("470.40M")),Some(470.40e6));
  assert_eq!(money(&json!(5_270_429_000_000.0_f64)),Some(5_270_429_000_000.0));
  assert_eq!(money(&json!("n/a")),None);
  assert_eq!(money(&json!("0")),None,"zero is how these pages spell unknown");
 }
 #[test]
 fn the_listing_page_hides_its_numbers_behind_an_index() {
  // SvelteKit serialises the page as a flat array whose head is an index map:
  // `marketCap` is 3, and element 3 is the string. Reading `data[0]` as the
  // value itself is how this parser gets silently wrong.
  let body=json!({"type":"data","nodes":[
   {"type":"data","data":[{"other":1},"ignored"]},
   {"type":"data","data":[{"marketCap":3,"sharesOut":4,"info":1},{"name":2},"SK hynix","1,271.87T","728.87M"]}]});
  assert_eq!(parse_stockanalysis_cap(&body),Some(1_271.87e12));
 }
 #[test]
 fn an_etf_page_carries_no_capitalisation() {
  // It reports assets under management instead, which is not a market cap and
  // must never be published as one.
  let body=json!({"nodes":[{"data":[{"aum":1,"nav":2},"$475.29B","716.47"]}]});
  assert_eq!(parse_stockanalysis_cap(&body),None);
 }
 #[test]
 fn an_unlisted_company_is_valued_off_its_stat_list() {
  // `private/<slug>` has no `marketCap`; the figure sits in `statsLeft`, and
  // the implied one wins because it moves with the trading the perpetual
  // tracks, while the round figure is stale the day it is published.
  let body=json!({"nodes":[{"data":[
   {"statsLeft":1},[2,5],
   {"label":3,"value":4},"Valuation","$965B",
   {"label":6,"value":7},"Implied Valuation","$880.67B"]}]});
  assert_eq!(parse_stockanalysis_cap(&body),Some(880.67e9));
  let round_only=json!({"nodes":[{"data":[
   {"statsLeft":1},[2],
   {"label":3,"value":4},"Valuation","$965B"]}]});
  assert_eq!(parse_stockanalysis_cap(&round_only),Some(965e9));
 }
 #[test]
 fn rates_come_out_of_the_fx_feed_with_the_dollar_itself() {
  let fx=parse_fx(&json!({"result":"success","base_code":"USD","rates":{"HKD":7.844,"KRW":1369.81,"CNY":0}}));
  assert_eq!(fx["USD"],1.0);
  assert_eq!(fx["HKD"],7.844);
  assert!(!fx.contains_key("CNY"),"a zero rate is not a rate");
 }
 #[test]
 fn a_foreign_name_is_only_ever_read_off_its_own_listing() {
  assert_eq!(listing(Kind::TickerEquity,"AAPL").as_deref(),Some("stocks/AAPL"));
  assert_eq!(listing(Kind::TickerEquity,"BRKB").as_deref(),Some("stocks/BRK.B"));
  // QNT is a coin, so Binance calls Quantinuum QNTX; the listing is still QNT.
  assert_eq!(listing(Kind::TickerEquity,"QNTX").as_deref(),Some("stocks/QNT"));
  assert_eq!(listing(Kind::NamedEquity,"SKHYNIX").as_deref(),Some("quote/krx/000660"));
  assert_eq!(listing(Kind::NamedEquity,"HK0700").as_deref(),Some("quote/hkg/0700"));
  assert_eq!(listing(Kind::NamedEquity,"ZHIPU").as_deref(),Some("quote/hkg/2513"));
  assert_eq!(listing(Kind::NamedEquity,"OPENAI").as_deref(),Some("private/openai"));
  // Never guessed: `stocks/ANTH` is AN2 Therapeutics, a 192M biotech, and
  // publishing that as Anthropic's market cap is worse than publishing nothing.
  assert_eq!(listing(Kind::NamedEquity,"MOONSHOT"),None);
  assert_eq!(listing(Kind::Other,"XAU"),None);
 }
 #[test]
 fn a_listings_currency_follows_its_exchange() {
  assert_eq!(listing_currency("quote/hkg/0700"),"HKD");
  assert_eq!(listing_currency("quote/krx/000660"),"KRW");
  assert_eq!(listing_currency("quote/sha/688825"),"CNY");
  assert_eq!(listing_currency("stocks/BRK.B"),"USD");
  assert_eq!(listing_currency("private/openai"),"USD");
 }
 #[test]
 fn two_contracts_on_one_company_report_the_same_market_cap() {
  // Binance quotes Tencent twice: HK0700USDT in Hong Kong dollars (426.00) and
  // TENCENTUSDT in dollars per ordinary share (54.90). Both must read 488B.
  let cap=3.83e12;let hkd=7.844;
  let by_lot=multiplier(cap,hkd,426.0).unwrap()*426.0;
  let by_name=multiplier(cap,hkd,54.90).unwrap()*54.90;
  assert!((by_lot-by_name).abs()<1.0);
  assert!((by_lot-488.3e9).abs()<0.2e9,"{by_lot}");
 }
 #[test]
 fn a_depositary_share_needs_no_ratio() {
  // SKHY is one ADS for roughly 0.14 of an SK hynix share. Nasdaq assumed a
  // round tenth and published 1.34T, 44% over the company's real 929B; taking
  // the capitalisation from the listing and dividing by the contract's own
  // price never has to know the ratio at all.
  let k=multiplier(929.61e9,1.0,183.79).unwrap();
  assert!((k*183.79-929.61e9).abs()<1.0);
 }
 #[test]
 fn an_unpriced_or_unrated_listing_yields_nothing() {
  assert_eq!(multiplier(929.61e9,0.0,183.79),None,"a missing rate is not one");
  assert_eq!(multiplier(929.61e9,1.0,0.0),None);
  assert_eq!(multiplier(0.0,1.0,183.79),None);
 }
 #[test]
 fn the_contract_list_says_what_each_symbol_tracks_and_writes_on() {
  let body=json!({"symbols":[
   {"symbol":"BTCUSDT","baseAsset":"BTC","underlyingType":"COIN"},
   {"symbol":"NVDAUSDT","baseAsset":"NVDA","underlyingType":"EQUITY"},
   {"symbol":"TENCENTUSDT","baseAsset":"TENCENT","underlyingType":"HK_EQUITY"},
   {"symbol":"SKHYNIXUSDT","baseAsset":"SKHYNIX","underlyingType":"KR_EQUITY"},
   {"symbol":"CXMTUSDT","baseAsset":"CXMT","underlyingType":"CN_EQUITY"},
   {"symbol":"SPCXUSD1","baseAsset":"SPCX","underlyingType":"EQUITY"},
   {"symbol":"XAUUSDT","baseAsset":"XAU","underlyingType":"COMMODITY"},
   {"symbol":"BTCDOMUSDT","baseAsset":"BTCDOM","underlyingType":"INDEX"},
   {"symbol":"OPENAIUSDT","baseAsset":"OPENAI","underlyingType":"PREMARKET"},
   {"symbol":"LEGACYUSDT","baseAsset":"LEGACY"}]});
  let contracts=parse_exchange_info(&body);
  let by:HashMap<&str,&Contract>=contracts.iter().map(|c|(c.symbol.as_str(),c)).collect();
  assert_eq!(by["BTCUSDT"].kind,Kind::Crypto);
  assert_eq!(by["NVDAUSDT"].kind,Kind::TickerEquity);
  assert_eq!(by["TENCENTUSDT"].kind,Kind::NamedEquity);
  assert_eq!(by["SKHYNIXUSDT"].kind,Kind::NamedEquity);
  assert_eq!(by["CXMTUSDT"].kind,Kind::NamedEquity);
  assert_eq!(by["XAUUSDT"].kind,Kind::Other);
  assert_eq!(by["BTCDOMUSDT"].kind,Kind::Other);
  assert_eq!(by["OPENAIUSDT"].kind,Kind::NamedEquity,"pre-IPO names are read off their private page");
  assert_eq!(by["LEGACYUSDT"].kind,Kind::Crypto,"no field means a coin");
  // USD1 is a quote asset too, so the base has to come off the row, not off
  // the end of the symbol.
  assert_eq!(by["SPCXUSD1"].base,"SPCX");
  assert_eq!(kinds_of(&contracts)["NVDAUSDT"],Kind::TickerEquity);
 }
 #[test]
 fn a_cached_value_expires_but_stays_readable() {
  let cache=Cache::new();
  cache.store(market(table(&[("BTC",supply(19_800_000.0))])));
  assert!(cache.fresh(Duration::from_secs(60)).is_some());
  std::thread::sleep(Duration::from_millis(20));
  assert!(cache.fresh(Duration::from_millis(5)).is_none(),"a lapsed entry is not fresh");
  assert!(cache.stale().is_some(),"but it is still there to serve while refreshing");
 }
 #[test]
 fn per_symbol_slots_expire_too() {
  let recent=Recent::new();
  recent.put("BTCUSDT",OpenInterest{open_interest:1.0,value:None,time:0});
  assert!(recent.get("BTCUSDT",Duration::from_secs(60)).is_some());
  assert!(recent.get("ETHUSDT",Duration::from_secs(60)).is_none());
  std::thread::sleep(Duration::from_millis(20));
  assert!(recent.get("BTCUSDT",Duration::from_millis(5)).is_none());
 }
}
