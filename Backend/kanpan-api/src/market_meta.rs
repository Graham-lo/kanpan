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
// Nasdaq's screener, the table its own market-activity pages are drawn from:
// one request lists every US-listed stock with its last sale and market cap.
const NASDAQ:&str="https://api.nasdaq.com/api/screener/stocks?tableonly=true&limit=10000&offset=0&download=true";

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
/// `underlyingType`. Only `Crypto` may be answered out of the coin table and
/// only `Equity` out of the share table; everything else — metals, oil, the
/// BTCDOM index, pre-IPO names, Hong Kong and Korean listings — has no figure
/// we can publish, and an absent value is the correct answer for it.
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Kind {Crypto,Equity,Other}

/// Everything a `/v1/market/meta` answer is built from, refreshed as one unit.
#[derive(Default)]
pub struct Market {
 /// Coin supply, keyed by base asset (`BTC`).
 pub coins:SupplyTable,
 /// Shares outstanding, keyed by ticker (`AAPL`). Shares rather than a market
 /// cap because the header multiplies by the price on screen: the perpetual's
 /// price, which is the one the user is actually looking at.
 pub shares:SupplyTable,
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
   // A stock we have no share count for stays blank. Falling back to the coin
   // table here is exactly the bug this split exists to prevent: NVDAUSDT
   // would report the market cap of an altcoin that happens to be called NVDA.
   Kind::Equity=>self.shares.get(&strip_quote(symbol)).copied(),
   Kind::Other=>None,
  }
 }
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
/// Nasdaq prints money as `$336.04` and `4,904,279,326,830`.
fn money(v:&Value)->Option<f64> {
 let text=match v {
  Value::String(s)=>s.trim().trim_start_matches('$').replace(',',""),
  other=>return num(other),
 };
 text.parse::<f64>().ok().filter(|x:&f64|x.is_finite())
}
/// The screener answers `{"data":{"rows":[...]}}` when downloading the whole
/// table and `{"data":{"table":{"rows":[...]}}}` when paging it.
fn nasdaq_rows(body:&Value)->&[Value] {
 for candidate in [&body["data"]["rows"],&body["data"]["table"]["rows"]] {
  if let Some(array)=candidate.as_array() {if !array.is_empty() {return array}}
 }
 &[]
}
/// Nasdaq screener rows -> shares outstanding, which is `marketCap / lastSale`.
/// A ticker is keyed by its letters alone, so Berkshire's `BRK/B` answers the
/// `BRKB` contract. Rows with no market cap (most ETFs, which hold assets
/// rather than issue shares) are skipped rather than published as zero.
pub fn parse_nasdaq(body:&Value,table:&mut SupplyTable) {
 for row in nasdaq_rows(body) {
  let Some(symbol)=row["symbol"].as_str() else {continue};
  let ticker:String=symbol.to_ascii_uppercase().chars().filter(char::is_ascii_alphanumeric).collect();
  let (Some(cap),Some(price))=(money(&row["marketCap"]),money(&row["lastsale"])) else {continue};
  if !(cap>0.0&&price>0.0) {continue}
  let shares=cap/price;
  fill(table,&ticker,Meta{total_supply:Some(shares),circulating_supply:Some(shares),..Meta::default()});
 }
}
/// Binance `exchangeInfo` -> what each contract tracks. A symbol whose
/// `underlyingType` is missing counts as a coin, which is what it was before
/// Binance started listing anything else.
pub fn parse_exchange_info(body:&Value)->HashMap<String,Kind> {
 let mut out=HashMap::new();
 for row in rows(&body["symbols"]) {
  let Some(symbol)=row["symbol"].as_str() else {continue};
  let kind=match row["underlyingType"].as_str() {
   None|Some("COIN")=>Kind::Crypto,
   // Only US listings: the share table is a US screener, and a Hong Kong or
   // Korean name could otherwise collide with an American ticker.
   Some("EQUITY")=>Kind::Equity,
   Some(_)=>Kind::Other,
  };
  out.insert(plain(symbol),kind);
 }
 out
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
/// Rebuilds the whole table. Apex is the main coin source, the product list
/// fills circulating supply, CoinGecko covers coins Binance never listed, the
/// Nasdaq screener covers the stocks, and `exchangeInfo` says which contract is
/// which. Any single upstream may fail without losing the others; the two that
/// decide a stock's answer keep their previous content rather than fall back to
/// the coin table, because a blank cell beats another asset's market cap.
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
 let mut shares=SupplyTable::new();
 match get_json(NASDAQ).await {Ok(body)=>parse_nasdaq(&body,&mut shares),Err(_)=>tracing::warn!("Supply: Nasdaq screener unavailable")}
 if shares.is_empty() {if let Some(old)=&previous {shares=old.shares.clone()}}
 let mut kinds=match get_json(EXCHANGE_INFO).await {
  Ok(body)=>parse_exchange_info(&body),
  Err(_)=>{tracing::warn!("Supply: exchangeInfo unavailable");HashMap::new()}
 };
 if kinds.is_empty() {if let Some(old)=&previous {kinds=old.kinds.clone()}}
 if coins.is_empty() {return Err(upstream())}
 tracing::info!("Supply table refreshed: {} coins, {} stocks, {} contracts classified",coins.len(),shares.len(),kinds.len());
 Ok(supply_cache().store(Market{coins,shares,kinds}))
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
  m.shares=table(&[("NVDA",supply(24_100_000_000.0))]);
  m.kinds=[("NVDAUSDT",Kind::Equity),("BTCUSDT",Kind::Crypto),("XAUUSDT",Kind::Other)]
   .iter().map(|(k,v)|((*k).to_owned(),*v)).collect();
  assert_eq!(m.meta("NVDAUSDT").unwrap().total_supply,Some(24_100_000_000.0));
  assert_eq!(m.meta("BTCUSDT").unwrap().total_supply,Some(19_800_000.0));
  assert_eq!(m.meta("XAUUSDT"),None,"gold has no market cap to report");
 }
 #[test]
 fn a_stock_with_no_share_count_stays_blank() {
  // Hong Kong and Korean names, ETFs and pre-IPO tickers are absent from the
  // US screener. Blank is the answer; the coin table must not be consulted.
  let mut m=market(table(&[("SPY",supply(1_000_000.0))]));
  m.kinds=[("SPYUSDT".to_owned(),Kind::Equity)].into_iter().collect();
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
 fn the_screener_gives_shares_outstanding_not_a_market_cap() {
  // Storing shares is what keeps the header honest: it multiplies by the price
  // on screen, so the cap follows the perpetual rather than yesterday's close.
  let body=json!({"data":{"rows":[
   {"symbol":"NVDA","lastsale":"$218.69","marketCap":"5,270,429,000,000"},
   {"symbol":"BRK/B","lastsale":"$509.91","marketCap":"1125020231187.00"},
   {"symbol":"SPY","lastsale":"$700.00","marketCap":"0.00"},
   {"symbol":"BROKEN","lastsale":"n/a","marketCap":"1"}]}});
  let mut t=SupplyTable::new();parse_nasdaq(&body,&mut t);
  assert_eq!(t.len(),2,"a zero cap and an unreadable price are both skipped");
  let shares=t["NVDA"].total_supply.unwrap();
  assert!((shares*218.69-5_270_429_000_000.0).abs()<1.0,"{shares}");
  assert!(t.contains_key("BRKB"),"BRK/B answers the BRKB contract");
 }
 #[test]
 fn the_contract_list_says_what_each_symbol_tracks() {
  let body=json!({"symbols":[
   {"symbol":"BTCUSDT","underlyingType":"COIN"},
   {"symbol":"NVDAUSDT","underlyingType":"EQUITY"},
   {"symbol":"TENCENTUSDT","underlyingType":"HK_EQUITY"},
   {"symbol":"XAUUSDT","underlyingType":"COMMODITY"},
   {"symbol":"BTCDOMUSDT","underlyingType":"INDEX"},
   {"symbol":"LEGACYUSDT"}]});
  let kinds=parse_exchange_info(&body);
  assert_eq!(kinds["BTCUSDT"],Kind::Crypto);
  assert_eq!(kinds["NVDAUSDT"],Kind::Equity);
  // A Hong Kong ticker could collide with an American one in the US screener.
  assert_eq!(kinds["TENCENTUSDT"],Kind::Other);
  assert_eq!(kinds["XAUUSDT"],Kind::Other);
  assert_eq!(kinds["BTCDOMUSDT"],Kind::Other);
  assert_eq!(kinds["LEGACYUSDT"],Kind::Crypto,"no field means a coin");
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
