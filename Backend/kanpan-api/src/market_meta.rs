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
use crate::{AppState,binance_gate,envelope,error::{ApiError,Result}};
use axum::{Router,Json,extract::Query,routing::get,http::StatusCode};
use serde::{Deserialize,Serialize};
use serde_json::{Value,json};
use std::collections::{HashMap,HashSet};
use std::future::Future;
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::{Arc,OnceLock,atomic::{AtomicBool,Ordering}};
use std::time::{Duration,Instant,SystemTime};

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
/// Coinbase 现货整表，带价格；只用来核对 CoinGecko 撞上的身份（P4.8）。一次最多
/// 一千行，2026-09-23 整表 925 行。
const COINBASE_SPOT:&str="https://api.coinbase.com/api/v3/brokerage/market/products?product_type=SPOT&limit=1000";
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
pub(crate) const LIVE_TTL:Duration=Duration::from_secs(15);
/// The quote assets a perpetual symbol can end with, longest spelling first —
/// one table for the whole server, [`crate::instruments::QUOTE_SUFFIXES`].
/// It used to be a copy here without `USD1`, so `SPCXUSD1` never lost its quote.
pub(crate) use crate::instruments::QUOTE_SUFFIXES as QUOTES;

// 缓存可以一直留着当恢复材料，但**送出去**的数字有年龄上限：拿不到新数据时留空，
// 绝不把一个不知道多久以前的数字当现在的答案（B-03）。
/// 供应量与股票乘数最多带着七天的年龄出门。供应量按月变，七天内的偏差看不出来；
/// 再往上就说不准了——被摘牌、增发、拆股都会让它彻底失真，而那正是留空的场合。
/// 连续七天一次都没刷成功也意味着上游或出口坏了整整一周，那时候留空是实话。
pub const MAX_PUBLISH_AGE:Duration=Duration::from_secs(7*24*60*60);
/// 名义持仓量 = 张数 × 价格，价格超过五分钟就不再乘：那是「现在的持仓 × 半小时前
/// 的价格」，一个谁都对不上的数。超时就只给张数，不给 `value`（A-02）。
pub const OI_PRICE_MAX_AGE:Duration=Duration::from_secs(300);
/// 不带 `symbols` 时最多答多少个品种，跟 `symbols` 那一路同一个上限。
const PAYLOAD_LIMIT:usize=1000;

pub fn routes()->Router<AppState> {
 Router::new().route("/v1/market/meta",get(meta))
 .route("/v1/market/open-interest",get(open_interest))
}

// Serialize/Deserialize 是为了落盘快照（见 `Snapshot`），不是接口形状：
// 送给手机的 JSON 由 `Meta::value()` 拼，字段名不一样。
#[derive(Clone,Copy,Debug,Default,PartialEq,Serialize,Deserialize)]
#[serde(default)]
pub struct Meta {pub total_supply:Option<f64>,pub circulating_supply:Option<f64>,pub max_supply:Option<f64>,pub rank:Option<i64>,
 /// 这一行的身份是谁认的。**内部字段**：[`Meta::value`] 不会把它写进客户端看到的
 /// JSON，客户端也永远不会拿到「来源」这种字段。它存在只为一件事——`lookup` 要能
 /// 分辨「币安自己就把 `1000SATS` 当成一个资产」和「CoinGecko 上有个叫这名字的
 /// 东西」，这两者一个是证据、一个是巧合。落盘快照里带着它，否则重启之后每一行都
 /// 退化成「没人认领」，`1000SATS` 就会被当成有歧义而留空。
 pub family:Option<Family>,
 /// 这一行的上游在同一刻报的单价（美元）。**内部字段**，同 `family` 一样不进
 /// [`Meta::value`]。只有 CoinGecko 那一族填它：CoinGecko 是按代号撞上的弱证据，
 /// 同一个代号底下可能是另一个币（P4.8 普查：`1000000BOBUSDT` 撞上的是
 /// bob-build-on-bitcoin，单价差了五个数量级）。拿它跟合约价一比，身份对不对一眼就
 /// 看得出来，见 [`coingecko_verified`]。
 pub price:Option<f64>}
/// 一行供应量的身份是哪一族的口径认的。
///
/// 币安自己的两个表（apex / product）用的是同一套资产代号，所以它们是同一族，
/// 可以按代号相互补字段；CoinGecko 用的是自己的 `id`，跟币安的代号没有任何保证的
/// 对应关系，所以它自成一族，绝不跟币安那一族互相填字段（B-02）。
#[derive(Clone,Copy,Debug,PartialEq,Eq,Serialize,Deserialize)]
pub enum Family {Binance,CoinGecko}
impl Meta {
 fn empty(&self)->bool {self.total_supply.is_none()&&self.circulating_supply.is_none()&&self.max_supply.is_none()&&self.rank.is_none()}
 /// A `1000PEPE` contract is a bundle of 1000 coins, so its price is 1000x the
 /// coin's. For `supply x price` to stay equal to the coin's real market cap,
 /// the supply published under that symbol must be DIVIDED by the multiplier.
 /// Rank belongs to the coin and is not scaled.
 pub fn scaled(self,multiplier:f64)->Self {
  if !(multiplier.is_finite()&&multiplier>0.0) {return self}
  let by=|v:Option<f64>|v.map(|x|x/multiplier);
  // 单价反过来乘：一张 `1000PEPE` 值一千个 PEPE。这样查出来的 `price` 总是「一张合约
  // 该值多少」，可以直接跟合约价比。
  Self{total_supply:by(self.total_supply),circulating_supply:by(self.circulating_supply),max_supply:by(self.max_supply),rank:self.rank,family:self.family,
   price:self.price.map(|p|p*multiplier)}
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
///
/// `PreMarket` 和 `Unknown` 都是「不给市值」的档位，但理由不同：未上市的公司根本
/// 没有市值可言（二级市场的估值页已经不再公布，见 B-09），而 `Unknown` 是币安没说
/// 这个合约写在什么上面——没说就不猜，不给数（B-01）。
#[derive(Clone,Copy,Debug,PartialEq,Eq,Serialize,Deserialize)]
pub enum Kind {Crypto,TickerEquity,NamedEquity,PreMarket,Other,Unknown}
impl Kind {
 pub fn equity(self)->bool {matches!(self,Kind::TickerEquity|Kind::NamedEquity)}
 /// 这个分类在契约里的写法。客户端的品种目录用它对账（见 B-T11 的样本文件）。
 pub fn wire(self)->&'static str {
  match self {
   Kind::Crypto=>"crypto",Kind::TickerEquity=>"equityUS",Kind::NamedEquity=>"equityNamed",
   Kind::PreMarket=>"preMarket",Kind::Other=>"other",Kind::Unknown=>"unknown",
  }
 }
}

/// One row of Binance's contract list, reduced to what the supply table needs.
#[derive(Clone,Debug,PartialEq)]
pub struct Contract {pub symbol:String,pub base:String,pub kind:Kind}

/// 一个股票乘数，连着它是什么时候算出来的。
///
/// 时刻用 [`SystemTime`] 而不是 `Instant`：进程刚起来时 `Instant` 减不出开机之前的
/// 时刻，于是快照里那些「已经三天大」的乘数一重启就会被当成刚算的，七天上限也就
/// 白设了。
#[derive(Clone,Copy,Debug,PartialEq,Serialize,Deserialize)]
pub struct Priced {pub k:f64,pub at:SystemTime,
 /// 算这个 k 时用的合约价格。留着它是为了认出拆股：见 [`unit_changed`]。
 #[serde(default)] pub price:f64}

/// 合约的计价单位变了吗——拆股、合股、换股都长这个样子。
///
/// `k = 市值 / 价格`，所以 k 只在「价格还是同一个单位」的前提下有效。2 拆 1 之后股价
/// 腰斩、股数翻倍、市值不变，拿旧 k 乘新价格报出来的市值正好是真值的一半。七天的年龄
/// 上限拦不住这件事：它可能发生在 k 算出来的第二天（B-T09）。阈值取 1.5 倍：一只股票
/// 一天之内涨跌五成已经是极端事件，而最小的拆股就是 2 比 1；宁可多留空几只。
pub fn unit_changed(before:f64,now:f64)->bool {
 if !(before>0.0&&now>0.0) {return true}
 let ratio=now/before;
 !(0.667..=1.5).contains(&ratio)
}
/// Contract symbol (`AAPLUSDT`) -> the number its price is multiplied by to get
/// the listed company's market capitalisation, and when that number was taken.
pub type EquityTable=HashMap<String,Priced>;

/// 送出去的数字够不够新。`None`（不知道是什么时候的）一律算过期——不知道年龄的
/// 数字跟没有数字是一回事。落在未来的时刻不算过期：那是机器对时，不是数据变旧。
pub fn expired(at:Option<SystemTime>)->bool {
 match at {
  None=>true,
  Some(at)=>SystemTime::now().duration_since(at).is_ok_and(|age|age>MAX_PUBLISH_AGE),
 }
}

/// Everything a `/v1/market/meta` answer is built from, refreshed as one unit.
#[derive(Default)]
pub struct Market {
 /// Coin supply, keyed by base asset (`BTC`).
 pub coins:SupplyTable,
 /// 股票乘数，各自带着自己的时刻。
 pub equities:EquityTable,
 /// Contract symbol (`AAPLUSDT`) -> what it tracks.
 pub kinds:HashMap<String,Kind>,
 /// 币的那张表是什么时候抓下来的。`None` = 不知道，于是一个都不发布。
 pub coins_at:Option<SystemTime>,
 /// 供应量来自 CoinGecko、而且同一刻的单价跟这张合约（`1000PEPEUSDT`）或这个现货对
 /// （`TON-USD`）的价格对得上的那些。CoinGecko 那一族的数字只有在这里面才出门：
 /// 按代号撞上的可能是同名的另一个币，见 [`coingecko_verified`]。
 pub coingecko_verified:HashSet<String>,
}
impl Market {
 /// 刚抓下来的一张表。
 pub fn fresh(coins:SupplyTable,equities:EquityTable,kinds:HashMap<String,Kind>)->Self {
  Market{coins,equities,kinds,coins_at:Some(SystemTime::now()),coingecko_verified:HashSet::new()}
 }
 /// 同上，带着这一轮核对过身份的 CoinGecko 行。
 pub fn with_verified(mut self,verified:HashSet<String>)->Self {self.coingecko_verified=verified;self}
 /// CoinGecko 那一族的数字，只有这个合约或现货对核对过身份才放行。
 fn vouched(&self,key:&str,meta:Meta)->Option<Meta> {
  (meta.family!=Some(Family::CoinGecko)||self.coingecko_verified.contains(key)).then_some(meta)
 }
 /// 币安没说这个合约写在什么上面时是 [`Kind::Unknown`]，不是「币」。
 ///
 /// 以前这里兜底成 `Crypto`，理由是「OKX 独有的永续本来就都是币」。但兜底的代价
 /// 是反过来那一半：exchangeInfo 抓不到、或者币安新加了一类标的还没被认出来时，
 /// 每一只股票都会被当成同名的币去查供应量——NVDAUSDT 报出某个叫 NVDA 的山寨币的
 /// 市值，正是这么来的。查不到分类就不给市值：少一个数字，不给一个错数字（B-01）。
 pub fn kind(&self,symbol:&str)->Kind {self.kinds.get(&plain(symbol)).copied().unwrap_or(Kind::Unknown)}
 /// The supply to publish for a contract symbol, or nothing.
 pub fn meta(&self,symbol:&str)->Option<Meta> {
  match self.kind(symbol) {
   // 七天没刷成功的供应量不再出门：见 MAX_PUBLISH_AGE。
   Kind::Crypto=>(!expired(self.coins_at)).then(||lookup(&self.coins,symbol)).flatten().and_then(|meta|self.vouched(&plain(symbol),meta)),
   // A stock whose capitalisation we could not resolve stays blank. Falling
   // back to the coin table here is exactly the bug this split exists to
   // prevent: NVDAUSDT would report the market cap of an altcoin that happens
   // to be called NVDA. ETFs, metals, indices and pre-IPO names have no
   // capitalisation at all, and blank is the honest answer for them too.
   Kind::TickerEquity|Kind::NamedEquity=>self.equities.get(&plain(symbol))
    .filter(|priced|!expired(Some(priced.at)))
    .map(|priced|Meta{total_supply:Some(priced.k),..Meta::default()}),
   // 未上市（B-09）、金属与指数、以及币安没说过的东西：都没有可发布的市值。
   Kind::PreMarket|Kind::Other|Kind::Unknown=>None,
  }
 }
 /// 现货对（Coinbase 的 `BTC-USD`）的供应量：那一家现货只上币，所以直接按 base 查
 /// 币的供应量表，和币安合约同一张表、同一条「七天没刷新就不出门」。
 pub fn spot_meta(&self,pair:&str)->Option<Meta> {
  let base=pair.strip_suffix("-USD").filter(|b|!b.is_empty()&&!b.contains('-'))?;
  (!expired(self.coins_at)).then(||lookup(&self.coins,base)).flatten().and_then(|meta|self.vouched(pair,meta))
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
/// 第三列是这一页该有的公司名开头（大写、只留字母数字）。它是页面身份校验的第二条
/// 证据：光有代码相等已经很难认错人，但 stockanalysis 偶尔会把一个下市的代码指到
/// 别处，而名字对得上就基本排除了这种可能。见 [`page_is`]。
const LISTINGS:[(&str,&str,Option<&str>);24]=[
 // 香港
 ("HK0700","quote/hkg/0700",Some("TENCENT")),("TENCENT","quote/hkg/0700",Some("TENCENT")),
 ("HK1810","quote/hkg/1810",Some("XIAOMI")),("HK0625","quote/hkg/0625",Some("SHEIN")),
 ("HK0992","quote/hkg/0992",Some("LENOVO")),
 ("MEITUAN","quote/hkg/3690",Some("MEITUAN")),("KUAISHOU","quote/hkg/1024",Some("KUAISHOU")),
 ("POPMART","quote/hkg/9992",Some("POPMART")),
 ("BYD","quote/hkg/1211",Some("BYD")),("MINIMAX","quote/hkg/0100",Some("MINIMAX")),
 ("GIGADEV","quote/hkg/3986",Some("GIGADEVICE")),
 ("ZHONGJI","quote/hkg/3308",Some("ZHONGJI")),("ZHIPU","quote/hkg/2513",Some("ZAI")),
 // 韩国
 ("SKHYNIX","quote/krx/000660",Some("SKHYNIX")),("SAMSUNG","quote/krx/005930",Some("SAMSUNGELECTRONICS")),
 ("HYUNDAI","quote/krx/005380",Some("HYUNDAIMOTOR")),
 ("SAMSUNGEM","quote/krx/009150",Some("SAMSUNGELECTRO")),("HANMI","quote/krx/042700",Some("HANMISEMICONDUCTOR")),
 ("LGELECTRONICS","quote/krx/066570",Some("LGELECTRONICS")),("NAVER","quote/krx/035420",Some("NAVER")),
 // 上海
 ("CXMT","quote/sha/688825",Some("CXMT")),("UNITREE","quote/sha/688836",Some("YUSHU")),
 // 美国，但合约名不是那个代码：伯克希尔 B 股写作 BRK.B，Quantinuum 的 QNT
 // 在币安被改名成 QNTX，因为 QNT 已经是一个币。
 ("BRKB","stocks/BRK.B",Some("BERKSHIRE")),("QNTX","stocks/QNT",Some("QUANTINUUM")),
];
// ANTHROPIC / OPENAI 不在这张表里了：它们是未上市公司，没有市值。二级市场的
// 「Implied Valuation」既不是市值、也已经不在那两页上公布，拿它当市值发布是把一个
// 不同口径的数字冒充成市值（B-09）。PREMARKET 那一类合约同理，一律留空。
/// The page to read for a contract, or nothing when we have no listing for it.
///
/// A foreign name we have never mapped stays blank on purpose: guessing
/// `stocks/<name>` is how a Korean contract ends up reporting an American
/// company's market cap.
pub fn listing(kind:Kind,base:&str)->Option<String> {
 // 未上市与非公司标的没有可读的页面，连找都不找。
 if !kind.equity() {return None}
 if let Some((_,path,_))=LISTINGS.iter().find(|(name,_,_)|*name==base) {return Some((*path).to_owned())}
 let plain_ticker=!base.is_empty()&&base.chars().all(|c|c.is_ascii_alphanumeric());
 (kind==Kind::TickerEquity&&plain_ticker).then(||format!("stocks/{base}"))
}
/// 这一页该是谁：代码（路径最后一段）和可选的公司名开头。
pub fn expected_identity(base:&str,path:&str)->(String,Option<&'static str>) {
 let code=normalise(path.rsplit('/').next().unwrap_or(""));
 let keyword=LISTINGS.iter().find(|(name,listing,_)|*name==base&&*listing==path).and_then(|(_,_,word)|*word);
 (code,keyword)
}
/// 大写，只留字母数字：`BRK.B` -> `BRKB`，`000660` -> `000660`，`SK hynix` -> `SKHYNIX`。
pub fn normalise(text:&str)->String {
 text.to_ascii_uppercase().chars().filter(char::is_ascii_alphanumeric).collect()
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
/// against USD, not USD against TUSD) only [`lookup`] gets it right, by
/// asking the table which of the [`base_readings`] it knows.
pub fn strip_quote(symbol:&str)->String {
 let clean=plain(symbol);
 for quote in QUOTES {if let Some(rest)=clean.strip_suffix(quote)&& !rest.is_empty() {return rest.to_owned()}}
 clean
}
/// Splits a bundle multiplier off a base asset: `1000PEPE` -> (`PEPE`, 1000).
/// `1INCH` is a coin and not a bundle, so only a run of three or more digits
/// counts, plus the older `1M`/`1K` spelling of the same thing.
pub fn strip_multiplier(base:&str)->(&str,f64) {
 let digits=base.chars().take_while(char::is_ascii_digit).count();
 // 前缀必须是 10 的整数次幂、而且至少一千：币安的打包只有 1000 / 1000000 这两种
 // 写法。不卡这一条的话 `2024ABC` 这种名字会被当成「2024 个 ABC」，供应量凭空缩
 // 两千倍——它只是一个以年份开头的名字。剩下的部分还得以字母开头且不止一个字符，
 // 所以 `1000X`、`1INCH`、`123ABC` 都是名字本身。
 let power_of_ten=digits>=4&&base.starts_with('1')&&base[1..digits].bytes().all(|b|b==b'0');
 if power_of_ten
  && let Ok(multiplier)=base[..digits].parse::<f64>() {
   let rest=&base[digits..];
   if rest.len()>=2&&rest.starts_with(|c:char|c.is_ascii_alphabetic()) {return (rest,multiplier)}
  }
 for (prefix,multiplier) in [("1M",1e6),("1K",1e3)] {
  if let Some(rest)=base.strip_prefix(prefix)
   && rest.len()>=3 && rest.starts_with(|c:char|c.is_ascii_alphabetic()) {return (rest,multiplier)}
 }
 (base,1.0)
}
/// 一个合约符号能读成哪些资产名，最像的在前：整个符号，然后去掉计价资产之后的部分。
pub fn base_readings(symbol:&str)->Vec<String> {
 let clean=plain(symbol);
 let mut names=vec![clean.clone()];
 for quote in QUOTES {
  if let Some(rest)=clean.strip_suffix(quote)&& !rest.is_empty()&&!names.iter().any(|n|n==rest) {names.push(rest.to_owned())}
 }
 names
}
/// Resolves a contract symbol against the supply table.
///
/// 每一种读法都可能对上两行：名字原样那一行（`1000SATS`），和剥掉打包前缀之后那一行
/// （`SATS`，供应量要除以 1000）。谁说了算看身份（B-02）：
///
/// * 币安自己的表里就有这个名字 -> 它已经是按张算的了，原样拿走，绝不再除一次。
///   `1000SATS`、`1000CAT`、`1MBABYDOGE` 都是这种，币安给的供应量已经除过。
/// * 币安自己的表里有剥掉前缀后的资产 -> 这是「1000 个 PEPE」的证据，除以 1000。
///   它比「CoinGecko 上有个东西叫 1000PEPE」这种弱证据更可信。
/// * 两边都只有弱证据（CoinGecko 既有原名又有剥掉前缀的名字）-> 说不清是哪一个，
///   留空。绝不让市值排行榜替我们选一个。
///
/// 读法之间仍然是「第一个对得上的赢」，这也是歧义对的解法：`USDTUSD` 可以读成
/// USD/TUSD，但表里只有 USDT 这个资产。
pub fn lookup(table:&SupplyTable,symbol:&str)->Option<Meta> {
 let readings=base_readings(symbol);
 let binance=|meta:&&Meta|meta.family==Some(Family::Binance);
 // 币安那一族先把所有读法走一遍，然后才轮到弱证据。「第一个对得上的赢」只在同一族
 // 里成立：`AUSDT` 的第一种读法是整个符号，CoinGecko 上正好有个叫 AUSDT 的
 // alloy-tether；而币安自己的表里认的是第二种读法 `A`（Vaulta）。按读法顺序走的话
 // 弱证据先到先得，市值差了三十多倍（P4.8 普查）。
 for name in &readings {
  if let Some(meta)=table.get(name).filter(binance) {return Some(*meta)}
  let (stripped_name,multiplier)=strip_multiplier(name);
  if multiplier!=1.0 && let Some(meta)=table.get(stripped_name).filter(binance) {return Some(meta.scaled(multiplier))}
 }
 for name in readings {
  let original=table.get(&name);
  let (stripped_name,multiplier)=strip_multiplier(&name);
  let stripped=(multiplier!=1.0).then(||table.get(stripped_name)).flatten();
  match (original,stripped) {
   (Some(_),Some(_))=>return None,
   (Some(meta),None)=>return Some(*meta),
   (None,Some(meta))=>return Some(meta.scaled(multiplier)),
   (None,None)=>{}
  }
 }
 None
}

/// 哪些币合约、哪些现货对的 CoinGecko 身份经得起单价核对。
///
/// CoinGecko 那一族的身份是它自己的 `id`，跟币安、Coinbase 的代号只是碰巧同名（B-02）。
/// 同一刻 CoinGecko 报的单价（已按打包倍数折成一张合约的价）和交易所的价差出 1.5 倍
/// 以上，撞上的就不是这个币。2026-09-23 的普查（P4.8）里有四个这样的：
/// `1000000BOBUSDT` 撞上 bob-build-on-bitcoin，单价差五个数量级，市值报成 66 美元，
/// 真值八百多万；Coinbase 的 `TON-USD`、`UP-USD`、`INDEX-USD` 各撞上一个同名币。
/// 阈值跟股票拆股同一把尺（[`unit_changed`]）：同一刻两家报价差五成不可能是行情。
///
/// 交易所价拿不到、或 CoinGecko 那行没有单价：身份无从核对，不放行——认不出身份的
/// 数字不出门。币安那一族的行不需要这一关，它的代号就是身份。
pub fn coingecko_verified(coins:&SupplyTable,contracts:&[Contract],prices:&HashMap<String,f64>,spot:&HashMap<String,f64>)->HashSet<String> {
 let agrees=|meta:Meta,price:Option<&f64>|meta.family==Some(Family::CoinGecko)
  && matches!((meta.price,price),(Some(bundle),Some(&price)) if !unit_changed(bundle,price));
 let mut out=HashSet::new();
 for contract in contracts.iter().filter(|c|c.kind==Kind::Crypto) {
  if lookup(coins,&contract.symbol).is_some_and(|meta|agrees(meta,prices.get(&contract.symbol))) {out.insert(contract.symbol.clone());}
 }
 for (pair,price) in spot {
  let Some(base)=pair.strip_suffix("-USD").filter(|b|!b.is_empty()&&!b.contains('-')) else {continue};
  if lookup(coins,base).is_some_and(|meta|agrees(meta,Some(price))) {out.insert(pair.clone());}
 }
 out
}
/// Coinbase 现货整表（`/market/products?product_type=SPOT`）→ 在线的 USD 对的价格。
pub fn parse_coinbase_spot(body:&Value)->HashMap<String,f64> {
 let mut out=HashMap::new();
 for row in body["products"].as_array().map(Vec::as_slice).unwrap_or(&[]) {
  if row["quote_currency_id"].as_str()!=Some("USD")||row["status"].as_str()!=Some("online")||row["is_disabled"].as_bool()==Some(true) {continue}
  if let (Some(pair),Some(price))=(row["product_id"].as_str(),positive(&row["price"])) {out.insert(pair.to_ascii_uppercase(),price);}
 }
 out
}

// -------------------------------------------------------------------- parsing

pub(crate) fn num(v:&Value)->Option<f64> {
 match v {Value::Number(n)=>n.as_f64(),Value::String(s)=>s.trim().parse().ok(),_=>None}.filter(|x:&f64|x.is_finite())
}
/// Upstreams spell "unknown" as 0 (or a negative), notably `maxSupply`.
fn positive(v:&Value)->Option<f64> {num(v).filter(|x|*x>0.0)}
fn rank_of(v:&Value)->Option<i64> {
 match v {Value::Number(n)=>n.as_i64(),Value::String(s)=>s.trim().parse().ok(),_=>None}.filter(|r|*r>0)
}
/// Finds the row array whichever envelope the upstream wraps it in this week.
pub(crate) fn rows(body:&Value)->&[Value] {
 for candidate in [body,&body["data"],&body["data"]["list"],&body["data"]["rows"],&body["result"]] {
  if let Some(array)=candidate.as_array()&& !array.is_empty() {return array}
 }
 &[]
}
/// 一个上游说的一项资产：它在**那个上游自己的口径**里的身份、它挂的代号，和数字。
///
/// 身份和代号分开是这一层的全部意义（B-02）。币安的口径里资产代号就是身份，一个代号
/// 一个东西；CoinGecko 的口径里身份是 `id`（`pepe`、`pepe-2`、`wrapped-pepe`），代号
/// （`symbol`）可以有一大把重名的。只按代号合表，等于让「谁的市值大谁占住这个代号」
/// 替我们做判断——那正是要改掉的东西。
#[derive(Clone,Debug,PartialEq)]
pub struct Asset {pub id:String,pub ticker:String,pub meta:Meta}

/// 只补空字段，所以同一身份里先来的（更可信的）源赢。
fn merge_into(slot:&mut Meta,meta:&Meta) {
 slot.total_supply=slot.total_supply.or(meta.total_supply);
 slot.circulating_supply=slot.circulating_supply.or(meta.circulating_supply);
 slot.max_supply=slot.max_supply.or(meta.max_supply);
 slot.rank=slot.rank.or(meta.rank);
 slot.price=slot.price.or(meta.price);
}
/// 把一个源的资产按身份收拢，再按代号索引。
///
/// 返回值里的 `None` 是「这个代号在这个源里指向好几个不同的东西」——歧义。字段只在
/// 同一身份内部相互补，跨身份一个字段都不填。
pub fn by_identity(assets:&[Asset],family:Family)->HashMap<String,Option<Meta>> {
 let mut per_id:HashMap<&str,(String,Meta)>=HashMap::new();
 for asset in assets {
  if asset.id.is_empty()||asset.ticker.is_empty() {continue}
  let slot=per_id.entry(&asset.id).or_insert_with(||(asset.ticker.clone(),Meta{family:Some(family),..Meta::default()}));
  merge_into(&mut slot.1,&asset.meta);
 }
 let mut owner:HashMap<String,&str>=HashMap::new();
 let mut out:HashMap<String,Option<Meta>>=HashMap::new();
 for (id,(ticker,meta)) in &per_id {
  // 什么数字都没有的那一行不算一个候选：它既当不了答案，也没资格把唯一那个有数字
  // 的同名资产拖成「有歧义」。
  if meta.empty() {continue}
  match owner.get(ticker) {
   Some(other) if other!=id=>{out.insert(ticker.clone(),None);}
   Some(_)=>{}
   None=>{owner.insert(ticker.clone(),id);out.insert(ticker.clone(),Some(*meta));}
  }
 }
 out
}
/// 两族合成一张按代号索引的表。
///
/// 币安自己的表说了算：它认领的代号直接盖掉 CoinGecko 那一行，绝不互相补字段。
/// 币安那边有歧义（同一个代号指向两个资产）就把这个代号整个去掉——留空比挑一个强。
pub fn merge_assets(binance:&[Asset],coingecko:&[Asset])->SupplyTable {
 let mut out=SupplyTable::new();
 for (ticker,meta) in by_identity(coingecko,Family::CoinGecko) {
  if let Some(meta)=meta {out.insert(ticker,meta);}
 }
 for (ticker,meta) in by_identity(binance,Family::Binance) {
  match meta {Some(meta)=>{out.insert(ticker,meta);},None=>{out.remove(&ticker);}}
 }
 out
}
/// Binance apex marketing list: `symbol` is a spot pair such as `BTCUSDT` and
/// `baseAsset` names its coin outright, which is the only way to read a pair
/// like `USDTUSD` correctly. 币安自己的口径里，资产代号就是资产的身份。
///
/// 所以 `baseAsset` 缺位的那一行整行丢掉，绝不退回去切 `symbol` 的尾巴猜一个代号
/// （B-02）：`USDTUSD` 切出来的不是 USDT，而这一行还会盖上 `Family::Binance` 的戳，
/// 于是一个猜出来的身份能把 CoinGecko 那个正确的同名资产顶掉、甚至把它判成有歧义
/// 后整个删掉。认不出身份的数字不进表。
pub fn parse_apex(body:&Value)->Vec<Asset> {
 let mut out=Vec::new();
 for row in rows(body) {
  let Some(base)=row["baseAsset"].as_str() else {continue};
  let base=base.to_ascii_uppercase();
  let meta=Meta{total_supply:positive(&row["totalSupply"]),circulating_supply:positive(&row["circulatingSupply"]),max_supply:positive(&row["maxSupply"]),rank:rank_of(&row["rank"]),family:Some(Family::Binance),price:None};
  out.push(Asset{id:base.clone(),ticker:base,meta});
 }
 out
}
/// Binance product list: `b` is the base asset, `cs` its circulating supply.
/// 跟 apex 是同一套资产代号，所以同一个代号的两行会被合成一行。
pub fn parse_products(body:&Value)->Vec<Asset> {
 let mut out=Vec::new();
 for row in rows(body) {
  let Some(base)=row["b"].as_str() else {continue};
  let base=base.to_ascii_uppercase();
  let meta=Meta{circulating_supply:positive(&row["cs"]),family:Some(Family::Binance),..Meta::default()};
  out.push(Asset{id:base.clone(),ticker:base,meta});
 }
 out
}
/// CoinGecko markets page, used only for coins Binance never listed on spot.
/// 身份是 `id`，不是 `symbol`：几十个币都叫 `BTC`，只有 `id` 分得开。没有 `id` 的
/// 行整行丢掉——认不出身份的数字不能进表。
pub fn parse_coingecko(body:&Value)->Vec<Asset> {
 let mut out=Vec::new();
 for row in rows(body) {
  let (Some(id),Some(symbol))=(row["id"].as_str(),row["symbol"].as_str()) else {continue};
  let meta=Meta{total_supply:positive(&row["total_supply"]),circulating_supply:positive(&row["circulating_supply"]),max_supply:positive(&row["max_supply"]),rank:rank_of(&row["market_cap_rank"]),family:Some(Family::CoinGecko),price:positive(&row["current_price"])};
  out.push(Asset{id:id.to_ascii_lowercase(),ticker:symbol.to_ascii_uppercase(),meta});
 }
 out
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
 None
}
/// 页面上所有能当身份用的字符串：代码与公司名，规范化之后。
///
/// 这些字段藏在 `nodes[n].data[m]` 的**嵌套**对象里（`marketCap` 在另一个节点上），
/// 而且跟页面上的其它东西一样是索引：`{"symbol":7}` 指的是 `data[7]`。
pub fn page_identities(body:&Value)->Vec<String> {
 const KEYS:[&str;7]=["symbol","db_symbol","nameFull","name","titleName","ticker","exchange_symbol"];
 let mut out=Vec::new();
 let Some(nodes)=body["nodes"].as_array() else {return out};
 for node in nodes {
  let Some(data)=node["data"].as_array() else {continue};
  for cell in data {
   let Some(map)=cell.as_object() else {continue};
   for key in KEYS {
    let text=match map.get(key) {
     Some(Value::String(text))=>Some(text.as_str()),
     Some(Value::Number(n))=>n.as_u64().and_then(|i|data.get(i as usize)).and_then(Value::as_str),
     _=>None,
    };
    if let Some(text)=text {
     let clean=normalise(text);
     if !clean.is_empty()&&!out.contains(&clean) {out.push(clean)}
    }
   }
  }
 }
 out
}
/// 这一页真的是我们要的那家公司吗（B.3 / A.7）。
///
/// 市值本身读得出来还不够：`stocks/<代码>` 这条路是拼出来的，代码一改名、一下市，
/// 同一个地址就会答成另一家公司，而那个市值照样是个合法的数字——错得毫无破绽。所以
/// 每一页都要自证身份：代码对得上，或者公司名以我们登记的那个词开头。一条证据都举不
/// 出来（页面上根本没有身份字段，比如一张验证码页）时按「不是」处理，宁可留空。
pub fn page_is(body:&Value,code:&str,keyword:Option<&str>)->bool {
 let found=page_identities(body);
 if found.is_empty() {return false}
 let code=normalise(code);
 if !code.is_empty()&&found.contains(&code) {return true}
 match keyword {
  Some(word)=>{let word=normalise(word);!word.is_empty()&&found.iter().any(|text|text.starts_with(&word))}
  None=>false,
 }
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
/// only because the row says so.
///
/// 没有 `underlyingType` 的行是 [`Kind::Unknown`]，不是「币」。以前它算币，理由是
/// 「币安加这个字段之前这里全都是币」——但那是历史，不是证据。这个字段缺了只说明一件
/// 事：币安没告诉我们这个合约写在什么上面。猜成币的代价是把一只股票按同名山寨币的
/// 供应量算市值，而留空的代价只是少一个数字（B-01）。
pub fn parse_exchange_info(body:&Value)->Vec<Contract> {
 let mut out=Vec::new();
 for row in rows(&body["symbols"]) {
  let Some(symbol)=row["symbol"].as_str() else {continue};
  let kind=match row["underlyingType"].as_str().map(str::trim).filter(|text|!text.is_empty()) {
   Some("COIN")=>Kind::Crypto,
   Some("EQUITY")=>Kind::TickerEquity,
   Some("HK_EQUITY")|Some("KR_EQUITY")|Some("CN_EQUITY")=>Kind::NamedEquity,
   // 未上市：没有市值（B-09）。
   Some("PREMARKET")=>Kind::PreMarket,
   // Metals, oil and the BTCDOM index: no company, so no capitalisation.
   Some(_)=>Kind::Other,
   None=>Kind::Unknown,
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
  Some(list)=>for name in list.split(',').map(str::trim).filter(|s|!s.is_empty()).take(PAYLOAD_LIMIT) {
   let key=name.to_ascii_uppercase();
   if out.contains_key(&key) {continue}
   let meta=if key.contains('-') {market.spot_meta(&key)} else {market.meta(&key)};
   if let Some(meta)=meta {out.insert(key,meta.value());}
  },
  // The unfiltered form is the whole contract table: the equity rows are
  // already keyed by contract symbol, and a coin row is turned into a
  // `<base>USDT` symbol only when the contract of that name really is a coin
  // （`COINUSDT` 是 Coinbase，不是那个叫 COIN 的币）。每一行都走 `market.meta`，
  // 所以分类未知的、以及七天没刷新的，一样答不出来（B.9）。
  // 上限跟 `symbols` 那一路一样，先股票再币，好让几百只股票不被几千个币挤掉。
  None=>{
   let mut names:Vec<String>=market.equities.keys().cloned().collect();
   names.sort();
   let mut coins:Vec<String>=market.coins.keys().map(|base|format!("{base}USDT")).collect();
   coins.sort();
   names.extend(coins);
   for symbol in names.into_iter().take(PAYLOAD_LIMIT) {
    if out.contains_key(&symbol) {continue}
    if let Some(meta)=market.meta(&symbol) {out.insert(symbol,meta.value());}
   }
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
fn oi_payload(symbol:&str,oi:&OpenInterest)->Value {
 let mut out=serde_json::Map::new();
 out.insert("symbol".into(),json!(symbol));
 out.insert("openInterest".into(),json!(oi.open_interest));
 if let Some(value)=oi.value {out.insert("openInterestValue".into(),json!(value));}
 out.insert("time".into(),json!(oi.time));
 Value::Object(out)
}

// --------------------------------------------------------------------- caches

pub(crate) struct Cache<T> {slot:std::sync::RwLock<Option<(Instant,Arc<T>)>>}
impl<T> Cache<T> {
 pub(crate) fn new()->Self {Self{slot:std::sync::RwLock::new(None)}}
 fn read(&self)->Option<(Instant,Arc<T>)> {self.slot.read().unwrap_or_else(|e|e.into_inner()).clone()}
 pub(crate) fn fresh(&self,ttl:Duration)->Option<Arc<T>> {self.read().filter(|(at,_)|at.elapsed()<ttl).map(|(_,v)|v)}
 fn stale(&self)->Option<Arc<T>> {self.read().map(|(_,v)|v)}
 pub(crate) fn store(&self,value:T)->Arc<T> {self.store_at(value,Instant::now())}
 /// 存一份「一进来就算旧」的值，快照走这条路：它立刻能用来答请求，但仍然算
 /// 旧表，所以第一个请求照常把后台刷新踢起来，而不是拿着昨天的数字当新的用。
 fn store_stale(&self,value:T,age:Duration)->Arc<T> {
  // 机器刚开机不到 `age` 时减不出更早的时刻；那种情况下当成新表也无妨，
  // 启动预热本来就会立刻刷一次。
  self.store_at(value,Instant::now().checked_sub(age).unwrap_or_else(Instant::now))
 }
 fn store_at(&self,value:T,at:Instant)->Arc<T> {
  let value=Arc::new(value);
  *self.slot.write().unwrap_or_else(|e|e.into_inner())=Some((at,value.clone()));
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
fn price_cache()->&'static Cache<HashMap<String,f64>> {static C:OnceLock<Cache<HashMap<String,f64>>>=OnceLock::new();C.get_or_init(Cache::new)}
fn binance_oi_cache()->&'static Recent<OpenInterest> {static C:OnceLock<Recent<OpenInterest>>=OnceLock::new();C.get_or_init(Recent::new)}

// -------------------------------------------------------------------- fetching

fn upstream()->ApiError {ApiError(StatusCode::SERVICE_UNAVAILABLE,"market_upstream_unavailable")}
pub(crate) fn http()->&'static reqwest::Client {
 static HTTP:OnceLock<reqwest::Client>=OnceLock::new();
 HTTP.get_or_init(||reqwest::Client::builder().timeout(Duration::from_secs(20))
  // 单独的连接超时。只有整体超时的话，一个黑洞路由（SYN 出去没人回）会把这个请求
  // 按满 20 秒，而刷新是串着跑的：几百个页面各占 20 秒，一轮就再也跑不完。连上
  // 一个活着的主机从来不需要五秒。
  .connect_timeout(Duration::from_secs(5))
  // These are the endpoints binance.com itself calls; the default agent string
  // is the kind of thing such a front door refuses.
  .user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
  .build().expect("HTTP client"))
}
/// The contract list exactly as Binance publishes it, for callers that need
/// fields `parse_exchange_info` does not keep — `sector_history` reads
/// `contractType` and `status` from the same body rather than fetching it a
/// second time from a host of its own.
pub async fn exchange_info()->Result<Value> {get_json(EXCHANGE_INFO).await}
pub(crate) async fn get_json(url:&str)->Result<Value> {
 // 同一个出口被币安封着的时候连出站都不出：429 之后继续敲门换来的是 418，418 之后
 // 继续敲门换来的是几天（A-06）。这道闸门是进程级的，`sector_history` 和
 // `oi_archive` 的 exchangeInfo / ticker / klines 共用同一份截止时间。
 if binance_gate::covers(url)&&binance_gate::blocked() {return Err(upstream())}
 let response=http().get(url).send().await.map_err(|_|upstream())?;
 // 记闸门也要先问 covers：这个函数同时服务 CoinGecko、stockanalysis.com 和
 // open.er-api.com，而 CoinGecko 对匿名调用者是按分钟限速的。少了这道守卫，
 // CoinGecko 的一个 429 就会把币安的出口按停两分钟，连带 sector_history 与
 // oi_archive——那道闸门只该由 binance.com 自己按下（A-06）。
 if binance_gate::covers(url)&&binance_gate::note_reply(&response) {return Err(upstream())}
 let response=response.error_for_status().map_err(|_|upstream())?;
 response.json::<Value>().await.map_err(|_|upstream())
}
/// 一个股票合约这一轮该发布什么。
///
/// 三种结局分得很清楚，因为它们的正确处置完全不同（A.7）：
/// * `Value` 算出来了；
/// * `Blank` 这个合约确实没有可发布的市值——页面读到了但没有市值（每一只 ETF）、
///   或者页面根本不是这家公司（身份校验没过）。要把旧值清掉。
/// * `Carry` 这一轮问不出来——页面抓不到、汇率缺这个币种、价格表里没有这个合约。
///   留着上一轮的数字（还要过七天上限那一关），而不是当成「没有市值」。
enum Priceable {Value(f64),Blank,Carry}
async fn equity_price(source:&dyn Source,contract:&Contract,fx:&HashMap<String,f64>,prices:&HashMap<String,f64>)->Priceable {
 // 没有登记过页面的名字：不猜地址，这个合约就是没有市值。
 let Some(path)=listing(contract.kind,&contract.base) else {return Priceable::Blank};
 // 价格表 200 了但没有这个合约：这是表里缺一行，不是「这家公司没有市值」。
 let Some(price)=prices.get(&contract.symbol).copied() else {return Priceable::Carry};
 // 汇率缺这个币种就跳过它这一轮。绝不把缺失的汇率当成 1——那等于把 1369 韩元
 // 报成 1369 美元。
 let Some(rate)=fx.get(listing_currency(&path)).copied().filter(|rate|*rate>0.0) else {
  tracing::warn!("Supply: no rate for {}, {} carried this round",listing_currency(&path),contract.symbol);
  return Priceable::Carry;
 };
 let url=format!("{STOCKANALYSIS}{path}/__data.json");
 // The site occasionally answers a real listing with a challenge page instead
 // of JSON; one immediate retry is what separates "Visa is blank today" from
 // "Visa is blank for one refresh". Two failures in a row count as unreadable.
 let body=match source.json(&url).await {
  Ok(body)=>body,
  Err(_)=>{
   tokio::time::sleep(source.gap()).await;
   match source.json(&url).await {Ok(body)=>body,Err(_)=>return Priceable::Carry}
  }
 };
 let (code,keyword)=expected_identity(&contract.base,&path);
 if !page_is(&body,&code,keyword) {
  tracing::warn!("Supply: {} answered with another company's page; publishing nothing",path);
  return Priceable::Blank;
 }
 let Some(cap)=parse_stockanalysis_cap(&body) else {return Priceable::Blank};
 match multiplier(cap,rate,price) {Some(k)=>Priceable::Value(k),None=>Priceable::Blank}
}
/// Asks stockanalysis.com for every equity contract, one page at a time.
///
/// Anything unreadable falls back to what the last refresh knew rather than to
/// a guess: a blank cell beats another company's market cap. If the rates or
/// the price list are missing there is nothing to compute at all, so the whole
/// previous table is kept.
async fn refresh_equities(source:&dyn Source,contracts:&[Contract],previous:Option<&EquityTable>)->EquityTable {
 let carried=||previous.cloned().unwrap_or_default();
 let wanted:Vec<&Contract>=contracts.iter().filter(|c|c.kind.equity()).collect();
 if wanted.is_empty() {return carried()}
 let fx=match source.json(FX).await {
  Ok(body)=>parse_fx(&body),
  Err(_)=>{tracing::warn!("Supply: exchange rates unavailable");return carried()}
 };
 let prices=match source.json(BINANCE_PRICES).await {
  Ok(body)=>parse_binance_prices(&body),
  Err(_)=>{tracing::warn!("Supply: contract prices unavailable");return carried()}
 };
 // 价格表 200 了但一行都没有，跟抓不到是一回事：它算不出任何一个乘数，却会把整张
 // 旧表清空。这种空数组见过不止一次，不能当成「所有股票都没有市值了」。
 if prices.is_empty() {tracing::warn!("Supply: the price list came back empty");return carried()}
 let now=SystemTime::now();
 let mut out=EquityTable::new();
 let mut kept=0usize;
 for contract in wanted {
  match equity_price(source,contract,&fx,&prices).await {
   Priceable::Value(k)=>{out.insert(contract.symbol.clone(),Priced{k,at:now,price:prices.get(&contract.symbol).copied().unwrap_or(0.0)});},
   Priceable::Blank=>{}
   Priceable::Carry=>{
    // 带着上一次的时刻一起留着，所以它会继续变老，七天之后自己就不再发布了。
    // 但年龄不是唯一的判据：价格的单位一变（拆股），旧 k 当天就作废。
    if let Some(priced)=previous.and_then(|p|p.get(&contract.symbol)) {
     match prices.get(&contract.symbol) {
      Some(price) if unit_changed(priced.price,*price)=>{
       tracing::warn!("Supply: {} changed units since its multiplier was taken; dropping it",contract.symbol);
      }
      _=>{out.insert(contract.symbol.clone(),*priced);kept+=1;}
     }
    }
   }
  }
  tokio::time::sleep(source.gap()).await;
 }
 if kept>0 {tracing::warn!("Supply: {kept} equity contracts could not be recomputed, kept the previous figures")}
 out
}
// ------------------------------------------------------------ refresh 的调度

/// 抓上游这一步抽成一个 trait，是为了让刷新的调度能在不连外网的情况下跑起来。
/// 单飞、分两次发布、快照都是时序上的东西，原来只有真的打到币安才走得到，
/// 于是「预热还在抓全表时第一个请求到达」这类问题没有任何测试拦得住。
pub(crate) trait Source:Send+Sync {
 fn json<'a>(&'a self,url:&'a str)->Pin<Box<dyn Future<Output=Result<Value>>+Send+'a>>;
 /// 每抓完一个股票页面停多久。真上游要按 [`LISTING_GAP`] 限速，假上游不必。
 fn gap(&self)->Duration {LISTING_GAP}
}
struct Upstream;
impl Source for Upstream {
 fn json<'a>(&'a self,url:&'a str)->Pin<Box<dyn Future<Output=Result<Value>>+Send+'a>> {Box::pin(get_json(url))}
}

/// 落盘快照的版本号。表的结构变了就换这个数，旧文件会被当成「没有快照」。
// 3：多了 `coingecko_verified`（P4.8）。旧快照里的 CoinGecko 行没核对过身份。
const SNAPSHOT_VERSION:u32=3;
#[derive(Serialize,Deserialize)]
struct Snapshot {version:u32,coins:SupplyTable,equities:EquityTable,kinds:HashMap<String,Kind>,
 /// 核对过 CoinGecko 身份的合约与现货对，跟币表一起刷新、一起落盘。
 #[serde(default)] coingecko_verified:HashSet<String>,
 /// 币那张表是什么时候抓的。快照里必须带着它，否则重启就等于把所有年龄清零，
 /// 七天上限会被一次重启绕过去（B-03）。
 #[serde(default)] coins_at:Option<SystemTime>}

/// 快照落在服务自己的缓存目录里，跟 open interest 的日切片同在一个
/// `CacheDirectory=kanpan-api` 下（见 `ops/install.py`）。`KANPAN_MARKET_CACHE`
/// 可以指到别处，跟 `KANPAN_OI_CACHE` 一个写法。
fn snapshot_path()->Option<PathBuf> {
 let dir=PathBuf::from(std::env::var("KANPAN_MARKET_CACHE").unwrap_or_else(|_|"/var/cache/kanpan-api/market".into()));
 match std::fs::create_dir_all(&dir) {
  Ok(())=>Some(dir.join("supply.json")),
  // 没有快照只是每次重启多付一次冷抓，不是服务起不来的理由。
  Err(_)=>{tracing::warn!("Supply snapshot directory is unavailable; a restart will refetch the table");None}
 }
}

/// 全表刷新的调度，进程里只有这一份。
///
/// 启动预热、缓存过期后的后台刷新、以及缓存完全为空时的请求，走的都是同一条路：
/// `refreshing` 是刷新权，抢到的人去抓，抢不到的人在 `ready` 上等那一个任务把表
/// 发布出来。不这么做的话，进程刚起来时预热在抓全表、第一个请求也在抓全表，
/// 两边各把几百个上游页面抓一遍，谁都不会更快。
struct Supply {
 cache:Cache<Market>,
 source:Box<dyn Source>,
 /// 快照文件；`None` 表示不落盘（目录建不出来，或这是测试自己造的实例）。
 snapshot:Option<PathBuf>,
 refreshing:AtomicBool,
 ready:tokio::sync::Notify,
}
/// 刷新权的持有者。无论刷新是正常结束、出错、被取消还是 panic，它离开作用域时
/// 都会把权交回去并叫醒等待的人——少了这一下，一次 panic 就能让之后所有冷请求
/// 永远等在那儿。
struct Refreshing(&'static Supply);
impl Drop for Refreshing {
 fn drop(&mut self) {
  self.0.refreshing.store(false,Ordering::SeqCst);
  self.0.ready.notify_waiters();
 }
}
fn supply()->&'static Supply {
 static S:OnceLock<Supply>=OnceLock::new();
 S.get_or_init(||Supply::new(Box::new(Upstream),snapshot_path()))
}

impl Supply {
 fn new(source:Box<dyn Source>,snapshot:Option<PathBuf>)->Self {
  Supply{cache:Cache::new(),source,snapshot,refreshing:AtomicBool::new(false),ready:tokio::sync::Notify::new()}
 }
 /// 抢刷新权；抢不到就说明已经有一个刷新在跑。
 fn claim(&'static self)->Option<Refreshing> {
  // 不能写成 `then_some(Refreshing(self))`：那样守卫会先被造出来再丢掉，于是没抢到
  // 权的人反而把正在刷新的那个人的权交了回去，还顺手把等待的请求全叫醒——它们醒来时
  // 表还是空的，只能收到 503。
  if self.refreshing.swap(true,Ordering::SeqCst) {return None}
  Some(Refreshing(self))
 }
 /// 没人在刷就在后台起一个。请求不在这里等它跑完。
 fn kick(&'static self) {
  let Some(claim)=self.claim() else {return};
  tokio::spawn(async move {let _claim=claim;let _=self.refresh().await;});
 }
 /// 请求要的那张表。
 async fn table(&'static self)->Result<Arc<Market>> {
  if let Some(table)=self.cache.fresh(SUPPLY_TTL) {return Ok(table)}
  if let Some(table)=self.cache.stale() {
   // A day-old table is still a correct answer; refresh behind the request
   // rather than making someone wait several seconds on upstreams.
   self.kick();
   return Ok(table);
  }
  self.wait().await
 }
 /// 冷路径：进程里还没有任何表。
 ///
 /// 等的是「表可用了」，不是「整轮刷新跑完了」——股票页面还在一个一个抓的时候，
 /// 币的那一半早已发布过一次，请求就该在那时返回。抓表的活儿一律交给后台任务，
 /// 所以请求被取消也不会把刷新带走，一个卡住的股票页面也拖不住这里。
 async fn wait(&'static self)->Result<Arc<Market>> {
  // enable() 先把自己挂到通知上再看缓存：反过来的话，正好落在这两步之间的那次
  // 发布会被漏掉，于是白等到下一次通知。
  let waiting=self.ready.notified();
  tokio::pin!(waiting);
  waiting.as_mut().enable();
  if let Some(table)=self.cache.stale() {return Ok(table)}
  self.kick();
  waiting.await;
  self.cache.stale().ok_or_else(upstream)
 }
 /// 预热循环的一轮：自己刷，或者等已经在跑的那一个，绝不并排再抓一遍。
 async fn cycle(&'static self)->Result<Arc<Market>> {
  match self.claim() {
   Some(claim)=>{let _claim=claim;self.refresh().await}
   None=>self.wait().await,
  }
 }
 /// Rebuilds the whole table. Apex is the main coin source, the product list
 /// fills circulating supply, CoinGecko covers coins Binance never listed,
 /// `exchangeInfo` says which contract is which, and stockanalysis.com prices
 /// the companies behind the equity contracts. Any single upstream may fail
 /// without losing the others.
 async fn refresh(&'static self)->Result<Arc<Market>> {
  let previous=self.cache.stale();
  // 两族分开收，最后按身份合（B-02）。币安自己的两个表共用一套资产代号，所以它们
  // 进同一个篮子；CoinGecko 的 `id` 是另一套口径，单独一个篮子。
  let mut binance:Vec<Asset>=Vec::new();
  match self.source.json(APEX).await {Ok(body)=>binance.extend(parse_apex(&body)),Err(_)=>tracing::warn!("Supply: apex list unavailable")}
  match self.source.json(PRODUCTS).await {Ok(body)=>binance.extend(parse_products(&body)),Err(_)=>tracing::warn!("Supply: product list unavailable")}
  let mut coingecko:Vec<Asset>=Vec::new();
  for page in 1..=COINGECKO_PAGES {
   match self.source.json(&format!("{COINGECKO}{page}")).await {
    Ok(body)=>coingecko.extend(parse_coingecko(&body)),
    // CoinGecko rate-limits anonymous callers; one refused page ends the sweep.
    Err(_)=>{tracing::warn!("Supply: CoinGecko page {page} unavailable");break}
   }
   tokio::time::sleep(Duration::from_millis(1200)).await;
  }
  let coins=merge_assets(&binance,&coingecko);
  let contracts=match self.source.json(EXCHANGE_INFO).await {
   Ok(body)=>parse_exchange_info(&body),
   Err(_)=>{tracing::warn!("Supply: exchangeInfo unavailable");Vec::new()}
  };
  if coins.is_empty() {return Err(upstream())}
  let old=previous.as_ref();
  // Without the contract list every stock would read as a coin, so the old
  // classification stands until Binance answers again.
  let kinds=if contracts.is_empty() {old.map(|m|m.kinds.clone()).unwrap_or_default()} else {kinds_of(&contracts)};
  // 一个分类都没有（这一轮 exchangeInfo 没答，上一轮也没留下任何东西可继承）：这一轮
  // 什么都不发布，返回 Err 让预热循环 600 秒后再来。
  //
  // 从前这里照发一张「有币表、没分类」的表，理由是每个品种都读成 Unknown、于是一个
  // 市值都答不出来。但发布这件事本身有副作用：`coins_at` 写成此刻，`table()` 在
  // 接下来 24 小时里都认这张表新鲜，预热循环也因为这一轮「成功」把下一轮推到
  // SUPPLY_TTL 之后。冷启动时 exchangeInfo 失败一次，代价就是整整一天的空表。
  // 不发布的话缓存里仍然是空的，请求收到 503，十分钟后再试一次（B-01）。
  if kinds.is_empty() {
   tracing::warn!("Supply: no contract classification this round and none to carry over; publishing nothing and retrying in ten minutes");
   return Err(upstream());
  }
  let carried=old.map(|m|m.equities.clone()).unwrap_or_default();
  // 分两次发布：合约分类一到手，币的那一半就先交出去，不必等股票页面逐个抓完
  // ——那是上百次请求，每次之间还隔着 LISTING_GAP。此刻分类已经在表里，所以
  // 一只还没定价的股票答的是空，而不是同名币种的供应量；NVDAUSDT 报出某个
  // 叫 NVDA 的山寨币的市值，正是这个拆分存在的理由。
  // 币那一半发布之前先核对 CoinGecko 撞上的身份：币安合约价、Coinbase 现货价各一次
  // 请求。这一轮合约表没答时沿用上一轮核对过的；价格表没答时那一边一个都放行不了。
  let verified=if contracts.is_empty() {old.map(|m|m.coingecko_verified.clone()).unwrap_or_default()} else {
   let prices=match self.source.json(BINANCE_PRICES).await {
    Ok(body)=>parse_binance_prices(&body),
    Err(_)=>{tracing::warn!("Supply: contract prices unavailable; CoinGecko identities stay unverified");HashMap::new()}
   };
   let spot=match self.source.json(COINBASE_SPOT).await {
    Ok(body)=>parse_coinbase_spot(&body),
    Err(_)=>{tracing::warn!("Supply: Coinbase spot prices unavailable; CoinGecko identities of spot pairs stay unverified");HashMap::new()}
   };
   coingecko_verified(&coins,&contracts,&prices,&spot)
  };
  self.publish(Market::fresh(coins.clone(),carried.clone(),kinds.clone()).with_verified(verified.clone()));
  let equities=if contracts.is_empty() {carried} else {refresh_equities(self.source.as_ref(),&contracts,old.map(|m|&m.equities)).await};
  tracing::info!("Supply table refreshed: {} coins, {} equities priced, {} contracts classified",coins.len(),equities.len(),kinds.len());
  let table=self.publish(Market::fresh(coins,equities,kinds).with_verified(verified));
  // 只有这一轮真的问到了合约分类才留快照：存一份分不出股票和币的表，等于让
  // 下次启动从一张会报错数的表开始。
  if !contracts.is_empty() {self.save(table.clone()).await}
  Ok(table)
 }
 /// 把一张可用的表交出去，并叫醒所有在等冷启动的请求。
 fn publish(&self,market:Market)->Arc<Market> {
  let table=self.cache.store(market);
  self.ready.notify_waiters();
  table
 }
 /// 装入上一次完整刷新留下的表。
 ///
 /// 按「旧表」记进缓存：它立刻能答请求，同时第一个请求照常把后台刷新踢起来。
 /// 文件不在、读坏了、版本对不上，都只算「没有快照」——快照是省掉一次冷等待的
 /// 便利，不能变成服务起不来的理由。
 fn restore(&self)->bool {
  let Some(path)=self.snapshot.as_ref() else {return false};
  let Ok(raw)=std::fs::read(path) else {return false};
  let Ok(snapshot)=serde_json::from_slice::<Snapshot>(&raw) else {
   tracing::warn!("Supply snapshot is unreadable; the table will be refetched");
   return false;
  };
  // 分类为空的快照跟没有快照一样危险：那张表会把每只股票读成同名的币。
  if snapshot.version!=SNAPSHOT_VERSION||snapshot.coins.is_empty()||snapshot.kinds.is_empty() {return false}
  // 年龄跟着快照一起回来：重启不会让一张三天大的表变成「刚抓的」。快照里没写时刻
  // （不该发生）就当不知道年龄，于是币那一半一个都不发布，等这一轮刷新填上。
  let coins_at=snapshot.coins_at;
  if coins_at.is_none() {tracing::warn!("Supply snapshot carries no time; the coin half stays blank until the next refresh")}
  self.cache.store_stale(Market{coins:snapshot.coins,equities:snapshot.equities,kinds:snapshot.kinds,coins_at,coingecko_verified:snapshot.coingecko_verified},SUPPLY_TTL);
  true
 }
 /// 写快照。先写临时文件再改名：断电或被杀时留下的要么是上一份完整快照、要么
 /// 什么都没有，不会是半个文件——半个文件下次启动只会被当成读不出来，白存一场。
 async fn save(&self,table:Arc<Market>) {
  let Some(path)=self.snapshot.clone() else {return};
  let _=tokio::task::spawn_blocking(move||{
   let snapshot=Snapshot{version:SNAPSHOT_VERSION,coins:table.coins.clone(),equities:table.equities.clone(),kinds:table.kinds.clone(),coins_at:table.coins_at,coingecko_verified:table.coingecko_verified.clone()};
   let Ok(payload)=serde_json::to_vec(&snapshot) else {return};
   let temporary=path.with_extension(format!("tmp{}",std::process::id()));
   if std::fs::write(&temporary,&payload).is_err()||std::fs::rename(&temporary,&path).is_err() {
    let _=std::fs::remove_file(&temporary);
    tracing::warn!("Supply snapshot could not be written");
   }
  }).await;
 }
}

/// Keeps the table warm from boot so no request ever pays for the cold fetch.
pub fn spawn_refresh()->tokio::task::JoinHandle<()> {
 tokio::spawn(async {
  // 先把上一次的快照顶上：进程重启后的那几十秒里，请求答的是昨天那张表，
  // 而不是排在几百个上游页面后面等。
  if tokio::task::spawn_blocking(||supply().restore()).await.unwrap_or(false) {
   tracing::info!("Supply table restored from the last snapshot");
  }
  loop {
   let wait=if supply().cycle().await.is_ok() {SUPPLY_TTL} else {Duration::from_secs(600)};
   tokio::time::sleep(wait).await;
  }
 })
}
async fn binance_price(symbol:&str)->Option<f64> {
 let prices=match price_cache().fresh(LIVE_TTL) {
  Some(prices)=>prices,
  None=>match get_json(BINANCE_PRICES).await {
   Ok(body)=>price_cache().store(parse_binance_prices(&body)),
   // Without a price the notional is simply absent; the amount still stands.
   // 旧价格只在五分钟内还算价格：再往前的价格乘上现在的持仓量，算出来的是一个
   // 哪个时刻都不成立的名义金额，不如不给（A-02 / B-03）。
   Err(_)=>price_cache().fresh(OI_PRICE_MAX_AGE)?,
  }
 };
 prices.get(symbol).copied()
}
async fn binance_open_interest(symbol:&str)->Result<OpenInterest> {
 let mut oi=match binance_oi_cache().get(symbol,LIVE_TTL) {
  Some(oi)=>oi,
  None=>{
   let body=get_json(&format!("{BINANCE_OI}{symbol}")).await?;
   let oi=parse_binance_oi(&body).ok_or(ApiError(StatusCode::SERVICE_UNAVAILABLE,"invalid_market_response"))?;
   binance_oi_cache().put(symbol,oi);oi
  }
 };
 oi.value=binance_price(symbol).await.map(|price|oi.open_interest*price);
 Ok(oi)
}

// ------------------------------------------------------------------- handlers

#[derive(Deserialize,Default)] #[serde(deny_unknown_fields)] struct MetaQuery {symbols:Option<String>}
async fn meta(Query(q):Query<MetaQuery>)->Result<Json<Value>> {
 if q.symbols.as_ref().is_some_and(|s|s.len()>16*1024) {return Err(ApiError::bad("invalid_symbols"))}
 let table=supply().table().await?;
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
  "okx"=>crate::venues::okx::open_interest(&symbol).await?,
  _=>return Err(ApiError::bad("invalid_source")),
 };
 Ok(envelope(oi_payload(&symbol,&oi)))
}

#[cfg(test)]
mod tests {
 use super::*;

 fn table(pairs:&[(&str,Meta)])->SupplyTable {pairs.iter().map(|(k,v)|((*k).to_owned(),*v)).collect()}
 /// 币安自己认领的一行：它的身份是证据，剥前缀的判断要靠它。
 fn supply(total:f64)->Meta {Meta{total_supply:Some(total),circulating_supply:Some(total),max_supply:None,rank:None,family:Some(Family::Binance),price:None}}
 /// CoinGecko 那一族的一行：同样的数字，但身份是弱的。
 fn weak(total:f64)->Meta {Meta{family:Some(Family::CoinGecko),..supply(total)}}
 /// 一张币表，外加「这些合约写的确实是币」这句声明。没有声明就是 Unknown，
 /// 什么都答不出来——这正是 B-01 要的行为，所以测试里也得明写。
 fn market(coins:SupplyTable,crypto:&[&str])->Market {
  let kinds=crypto.iter().map(|s|(plain(s),Kind::Crypto)).collect();
  Market::fresh(coins,EquityTable::new(),kinds)
 }
 /// 刚算出来的一个股票乘数。
 fn priced(k:f64,price:f64)->Priced {Priced{k,at:SystemTime::now(),price}}
 fn aged(k:f64,price:f64,age:Duration)->Priced {
  Priced{k,at:SystemTime::now()-age,price}
 }

 /// 只有币安那一族的表，合出来给 lookup 用。
 fn binance_table(body:&Value)->SupplyTable {merge_assets(&parse_apex(body),&[])}

 /// P4.8 普查（2026-09-23）里的 `AUSDT`：第一种读法（整个符号）只在 CoinGecko 上撞到
 /// alloy-tether，第二种读法 `A` 是币安自己认的 Vaulta。币安那一族要先把所有读法走完。
 #[test]
 fn a_binance_identity_on_a_later_reading_beats_a_weak_one_on_an_earlier_reading() {
  let t=table(&[("AUSDT",weak(50_000_000.0)),("A",supply(1_727_008_173.0))]);
  assert_eq!(lookup(&t,"AUSDT").and_then(|m|m.total_supply),Some(1_727_008_173.0));
  // 只有弱证据时照旧按读法顺序：第一种读法赢。
  let weak_only=table(&[("AUSDT",weak(50_000_000.0)),("A",weak(1.0))]);
  assert_eq!(lookup(&weak_only,"AUSDT").and_then(|m|m.total_supply),Some(50_000_000.0));
 }
 /// P4.8 普查里的 `1000000BOBUSDT`：CoinGecko 前一千名里叫 BOB 的是 bob-build-on-bitcoin
 /// （单价 0.0057），币安这张合约是一百万个 BNB 链上的 BOB（一张 0.0199，一个 2e-8）。
 /// 按一张合约折算，单价差五个数量级，市值报成 66 美元——身份错了，留空。
 #[test]
 fn a_coingecko_identity_is_published_only_when_the_exchange_price_agrees() {
  let cg=|price:f64|Meta{family:Some(Family::CoinGecko),price:Some(price),..supply(21_000_000.0)};
  let coins=table(&[("BOB",cg(0.005_717_32)),("ZEC",cg(51.0)),("NOPRICE",Meta{price:None,..cg(1.0)}),("BTC",supply(19_800_000.0))]);
  let contracts=vec![
   Contract{symbol:"1000000BOBUSDT".into(),base:"1000000BOB".into(),kind:Kind::Crypto},
   Contract{symbol:"ZECUSDT".into(),base:"ZEC".into(),kind:Kind::Crypto},
   Contract{symbol:"NOPRICEUSDT".into(),base:"NOPRICE".into(),kind:Kind::Crypto},
   Contract{symbol:"UNLISTEDUSDT".into(),base:"UNLISTED".into(),kind:Kind::Crypto},
   Contract{symbol:"BTCUSDT".into(),base:"BTC".into(),kind:Kind::Crypto}];
  let prices:HashMap<String,f64>=[("1000000BOBUSDT",0.019_88),("ZECUSDT",52.3),("NOPRICEUSDT",1.0),("UNLISTEDUSDT",1.0),("BTCUSDT",1.0)]
   .into_iter().map(|(k,v)|(k.to_owned(),v)).collect();
  // Coinbase 的 TON-USD：CoinGecko 撞上的是 tokamak-network（0.37），现货价 1.44。
  let coins={let mut c=coins;c.insert("TON".into(),cg(0.371_415));c};
  let spot:HashMap<String,f64>=[("TON-USD",1.4404),("ZEC-USD",52.2),("BTC-USD",85_465.0)].into_iter().map(|(k,v)|(k.to_owned(),v)).collect();
  let verified=coingecko_verified(&coins,&contracts,&prices,&spot);
  // 只有价格对得上的 ZEC 放行；币安自己的表（BTC）不需要核对，也就不在集合里。
  assert_eq!(verified,["ZECUSDT","ZEC-USD"].into_iter().map(str::to_owned).collect::<HashSet<_>>());
  // 价格整张缺席：CoinGecko 那一族一个都核对不了。
  assert!(coingecko_verified(&coins,&contracts,&HashMap::new(),&HashMap::new()).is_empty());
  let kinds=kinds_of(&contracts);
  let m=Market::fresh(coins,EquityTable::new(),kinds).with_verified(verified);
  assert_eq!(m.meta("1000000BOBUSDT"),None);
  assert_eq!(m.meta("NOPRICEUSDT"),None,"没有单价可比的也留空");
  assert_eq!(m.spot_meta("TON-USD"),None);
  assert!(m.spot_meta("ZEC-USD").is_some());
  assert!(m.spot_meta("BTC-USD").is_some());
  assert_eq!(m.meta("ZECUSDT").and_then(|meta|meta.total_supply),Some(21_000_000.0));
  assert!(m.meta("BTCUSDT").is_some());
  // 单价是内部字段，出门的 JSON 里没有它。
  assert!(m.meta("ZECUSDT").unwrap().value().get("price").is_none());
 }
 #[test]
 fn apex_rows_parse_and_an_absent_cap_means_unknown() {
  let body=json!({"code":"000000","success":true,"data":[
   {"symbol":"BTCUSDT","baseAsset":"BTC","quoteAsset":"USDT","circulatingSupply":19_800_000.0,"totalSupply":19_800_000.0,"maxSupply":21_000_000.0,"rank":1},
   {"symbol":"ETHUSDT","baseAsset":"ETH","quoteAsset":"USDT","circulatingSupply":"120500000","totalSupply":"120500000","maxSupply":null,"rank":"2"}]});
  let t=binance_table(&body);
  assert_eq!(t["BTC"],Meta{total_supply:Some(19_800_000.0),circulating_supply:Some(19_800_000.0),max_supply:Some(21_000_000.0),rank:Some(1),family:Some(Family::Binance),price:None});
  assert_eq!(t["ETH"].max_supply,None);
  assert_eq!(t["ETH"].rank,Some(2));
 }
 #[test]
 fn an_ambiguous_pair_is_read_by_its_declared_base() {
  // USDTUSD is USDT against USD; read off the suffix alone it looks like USD
  // against TUSD, which would file the supply of Tether under the wrong name.
  let body=json!({"data":[{"symbol":"USDTUSD","baseAsset":"USDT","quoteAsset":"USD","circulatingSupply":183_442_587_855.0_f64,"totalSupply":183_442_587_855.0_f64}]});
  let t=binance_table(&body);
  assert!(t.contains_key("USDT")&&!t.contains_key("USD"));
  assert!(lookup(&t,"USDTUSD").is_some(),"and the same pair resolves back out");
 }
 /// B-02：apex 那张表里 `baseAsset` 缺位的一行整行丢掉，不许从 symbol 尾巴上猜身份。
 ///
 /// 猜出来的代号还会盖上 `Family::Binance` 的戳，于是它在合并里的权重跟币安真的
 /// 认领过一样：轻则把 CoinGecko 那个正确的同名资产顶掉，重则被判成有歧义、连
 /// 那个正确的一起删掉。
 #[test]
 fn an_apex_row_without_a_base_asset_is_dropped_instead_of_guessed() {
  let body=json!({"data":[
   {"symbol":"BTCUSDT","baseAsset":"BTC","totalSupply":19_800_000.0},
   // `baseAsset` 缺位。切尾巴的话这一行会被记成 USD 的供应量（`USDTUSD` 的后缀
   // 是 `TUSD`），而它其实是 Tether 的。
   {"symbol":"USDTUSD","totalSupply":183_442_587_855.0_f64},
   {"symbol":"NOSYMBOL","circulatingSupply":7.0}]});
  let assets=parse_apex(&body);
  assert_eq!(assets.len(),1,"只有写了 baseAsset 的那一行进表");
  assert_eq!(assets[0].ticker,"BTC");
  // 而 CoinGecko 那个有身份的 USDT 因此活了下来，值还是对的。
  let cg=parse_coingecko(&json!([{"id":"tether","symbol":"usdt","total_supply":183_442_587_855.0_f64}]));
  let merged=merge_assets(&assets,&cg);
  assert_eq!(merged["USDT"].total_supply,Some(183_442_587_855.0_f64));
  assert_eq!(merged["USDT"].family,Some(Family::CoinGecko));
  assert!(!merged.contains_key("USD"),"猜出来的那个代号一个都没进表");
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
  let t=binance_table(&body);
  assert_eq!(t.len(),1);
  assert_eq!(t["SOL"].total_supply,Some(600_000_000.0));
 }
 #[test]
 fn products_only_fill_what_apex_left_empty() {
  let apex=json!({"data":[{"symbol":"BTCUSDT","baseAsset":"BTC","totalSupply":21_000_000.0}]});
  let body=json!({"data":[{"s":"BTCUSDT","b":"BTC","q":"USDT","cs":19_900_000.0},{"s":"HYPEUSDT","b":"HYPE","q":"USDT","cs":333_000_000.0}]});
  // 同一套资产代号就是同一个身份，所以这两行补成一行。
  let mut binance=parse_apex(&apex);binance.extend(parse_products(&body));
  let t=merge_assets(&binance,&[]);
  assert_eq!(t["BTC"].total_supply,Some(21_000_000.0));
  assert_eq!(t["BTC"].circulating_supply,Some(19_900_000.0));
  assert_eq!(t["HYPE"].circulating_supply,Some(333_000_000.0));
 }
 #[test]
 fn coingecko_fills_the_gap_binance_never_listed() {
  let body=json!([{"id":"monero","symbol":"xmr","total_supply":18_400_000.0,"circulating_supply":18_400_000.0,"max_supply":null,"market_cap_rank":42},
   // 没有 id 的行认不出身份，整行丢掉。
   {"symbol":"ghost","total_supply":1.0}]);
  let t=merge_assets(&[],&parse_coingecko(&body));
  assert_eq!(t["XMR"].total_supply,Some(18_400_000.0));
  assert_eq!(t["XMR"].max_supply,None);
  assert_eq!(t["XMR"].rank,Some(42));
  assert_eq!(t["XMR"].family,Some(Family::CoinGecko));
  assert!(!t.contains_key("GHOST"),"没有 id 的行不进表");
 }
 #[test]
 fn quote_assets_come_off_the_symbol() {
  assert_eq!(strip_quote("BTCUSDT"),"BTC");
  assert_eq!(strip_quote("ETHFDUSD"),"ETH");
  assert_eq!(strip_quote("BTC-USDT-SWAP"),"BTC");
  assert_eq!(strip_quote("USDCUSDT"),"USDC");
  // USD1 / TUSD 计价的那几只以前剥不掉，基础资产读成了 SPCXUSD1 整个。
  assert_eq!(strip_quote("SPCXUSD1"),"SPCX");
  assert_eq!(strip_quote("XTUSD"),"X");
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
 /// B-T05：语法边界。这些名字都是合成的，故意不在现行合约表里——要钉的是规则本身，
 /// 不是「今天恰好没有这样的品种」。
 #[test]
 fn a_name_that_merely_starts_with_digits_is_not_a_bundle() {
  // 一个数字开头的币名，不是打包。
  assert_eq!(strip_multiplier("1INCH"),("1INCH",1.0));
  // 三位数字、而且不是一千：123 个什么都不是币安的写法。
  assert_eq!(strip_multiplier("123ABC"),("123ABC",1.0));
  // 四位数字但不是 10 的整数次幂：以年份开头的名字。以前这里会缩两千倍。
  assert_eq!(strip_multiplier("2024ABC"),("2024ABC",1.0));
  // 剩下的部分只有一个字符：`1000X` 是名字，不是「1000 个 X」。
  assert_eq!(strip_multiplier("1000X"),("1000X",1.0));
  // 老写法的 1K / 1M 仍然算打包。
  assert_eq!(strip_multiplier("1KABC"),("ABC",1e3));
  assert_eq!(strip_multiplier("1MABC"),("ABC",1e6));
 }
 /// B-T06（上半）：打包合约的单位恒等式——供应量除以倍数，市值不变。
 #[test]
 fn a_bundle_keeps_the_coins_market_cap() {
  // One 1000PEPE contract is 1000 PEPE, so it trades at 1000x the coin price.
  // Dividing the supply is the only direction that leaves the cap unchanged.
  let coin_supply=420_690_000_000.0_f64;let coin_price=0.000_012_f64;
  let t=table(&[("PEPE",supply(coin_supply))]);
  assert_eq!(lookup(&t,"1000PEPEUSDT").map(|m|m.total_supply),Some(Some(coin_supply/1000.0)));
  let meta=lookup(&t,"1000PEPEUSDT").expect("bundle resolves to its coin");
  assert_eq!(meta.total_supply,Some(coin_supply/1000.0));
  let bundle_cap=meta.total_supply.unwrap()*(coin_price*1000.0);
  assert!((bundle_cap-coin_supply*coin_price).abs()<1e-6,"{bundle_cap}");
 }
 /// B-T06（下半）：原名本身就已经打包过的（1000SATS）不许再除第二次。
 #[test]
 fn a_bundle_binance_itself_lists_is_not_divided_again() {
  // Binance files 1000SATS as its own asset with the supply already divided:
  // 2.1e15 satoshis become 2.1e12 bundles. Dividing that a second time would
  // report a market cap a thousandth of the real one.
  let coin_supply=2_100_000_000_000_000.0_f64;
  let t=table(&[("1000SATS",supply(coin_supply/1000.0)),("SATS",supply(coin_supply))]);
  assert_eq!(lookup(&t,"1000SATSUSDT").unwrap().total_supply,Some(coin_supply/1000.0));
 }
 /// B-T04：币安自己有 PEPE，CoinGecko 上另有个不相干的东西也叫 1000PEPE。
 /// 原名不得凭「名字一样」抢占一个已经被证明的资产。
 #[test]
 fn a_proven_asset_beats_a_lookalike_on_the_packaged_name() {
  let coin_supply=420_690_000_000.0_f64;
  let t=table(&[("PEPE",supply(coin_supply)),("1000PEPE",weak(7.0))]);
  assert_eq!(lookup(&t,"1000PEPEUSDT").unwrap().total_supply,Some(coin_supply/1000.0),
   "币安自己的 PEPE 说明这是 1000 个 PEPE；CoinGecko 上那个同名的东西不算证据");
  // 反过来：币安两边都没有，只有 CoinGecko 上有个叫这个名字的东西，那就照它的数字
  // 发布，不额外除。
  let only_weak=table(&[("1000PEPE",weak(1_000.0))]);
  assert_eq!(lookup(&only_weak,"1000PEPEUSDT").unwrap().total_supply,Some(1_000.0));
  // 两个都是弱证据：说不清 1000PEPE 是「那个叫 1000PEPE 的东西」还是「1000 个
  // PEPE」，留空。
  let both_weak=table(&[("1000PEPE",weak(1_000.0)),("PEPE",weak(420_690_000_000.0))]);
  assert_eq!(lookup(&both_weak,"1000PEPEUSDT"),None,"说不清就留空，绝不让市值大的那个占住");
 }
 /// B-T03：CoinGecko 上两个不同 id 挂同一个代号，一个有 total、一个没有。
 /// 字段绝不跨 id 拼。
 #[test]
 fn fields_are_never_stitched_across_two_identities() {
  let body=json!([
   {"id":"abc-token","symbol":"abc","total_supply":null,"circulating_supply":1_000.0,"market_cap_rank":50},
   {"id":"abc-finance","symbol":"abc","total_supply":9_999.0,"circulating_supply":null,"market_cap_rank":900}]);
  let t=merge_assets(&[],&parse_coingecko(&body));
  assert!(!t.contains_key("ABC"),"同一个代号指向两个东西，就没有一个能答");
  // 只剩一个身份时照常答，而且答的是它自己那一行，不是两行拼出来的。
  let single=json!([{"id":"abc-token","symbol":"abc","total_supply":null,"circulating_supply":1_000.0}]);
  let t=merge_assets(&[],&parse_coingecko(&single));
  assert_eq!(t["ABC"].total_supply,None,"另一个 id 的 total 不许补进来");
  assert_eq!(t["ABC"].circulating_supply,Some(1_000.0));
 }
 /// 币安那一族有歧义（同一个代号两个资产）时，整个代号留空——哪怕 CoinGecko 有话说。
 #[test]
 fn an_ambiguous_ticker_is_published_by_nobody() {
  let binance=vec![
   Asset{id:"ABC".to_owned(),ticker:"ABC".to_owned(),meta:supply(1.0)},
   Asset{id:"ABC2".to_owned(),ticker:"ABC".to_owned(),meta:supply(2.0)}];
  let gecko=vec![Asset{id:"abc".to_owned(),ticker:"ABC".to_owned(),meta:weak(3.0)}];
  assert!(!merge_assets(&binance,&gecko).contains_key("ABC"));
 }
 #[test]
 fn symbols_filter_omits_what_we_cannot_resolve() {
  let t=market(table(&[("BTC",supply(19_800_000.0)),("ETH",supply(120_500_000.0))]),&["BTCUSDT","ETHUSDT","HYPEUSDT"]);
  let payload=meta_payload(&t,Some("BTCUSDT, ethusdt ,HYPEUSDT,,BTCUSDT"));
  let map=payload.as_object().unwrap();
  assert_eq!(map.len(),2);
  assert!(map.contains_key("BTCUSDT")&&map.contains_key("ETHUSDT"));
  assert!(!map.contains_key("HYPEUSDT"),"an unknown base must be absent, not null");
  assert_eq!(map["BTCUSDT"]["totalSupply"],json!(19_800_000.0));
 }
 /// Coinbase 现货对按 base 查同一张币表；不认识的币、不是 USD 计价的对都不答。
 #[test]
 fn spot_pairs_read_the_coin_table_by_base() {
  let t=market(table(&[("BTC",supply(19_800_000.0))]),&["BTCUSDT"]);
  let payload=meta_payload(&t,Some("BTC-USD,ETH-USD,BTC-EUR,-USD"));
  let map=payload.as_object().unwrap();
  assert_eq!(map.len(),1);
  assert_eq!(map["BTC-USD"]["totalSupply"],json!(19_800_000.0));
 }
 #[test]
 fn omitting_symbols_returns_the_whole_table() {
  let t=market(table(&[("BTC",supply(19_800_000.0))]),&["BTCUSDT"]);
  let payload=meta_payload(&t,None);
  assert_eq!(payload.as_object().unwrap().len(),1);
  assert!(payload["BTCUSDT"]["circulatingSupply"].is_number());
 }
 /// B.9：不带 `symbols` 时只给证明了是币的那些合成 `<base>USDT`，而且跟另一路同一个
 /// 上限。分类未知的一个都不出现。
 #[test]
 fn the_unfiltered_answer_only_synthesises_symbols_for_proven_coins() {
  let coins=table(&[("BTC",supply(19_800_000.0)),("NVDA",supply(91_937.5)),("MYSTERY",supply(5.0))]);
  let kinds=[("BTCUSDT",Kind::Crypto),("NVDAUSDT",Kind::TickerEquity)]
   .iter().map(|(k,v)|((*k).to_owned(),*v)).collect();
  let equities=[("NVDAUSDT".to_owned(),priced(24_100_000_000.0,180.0))].into_iter().collect();
  let m=Market::fresh(coins,equities,kinds);
  let payload=meta_payload(&m,None);
  let map=payload.as_object().unwrap();
  assert_eq!(map.len(),2);
  assert_eq!(map["NVDAUSDT"]["totalSupply"],json!(24_100_000_000.0),"股票走自己那张表");
  assert!(map.contains_key("BTCUSDT"));
  assert!(!map.contains_key("NVDAUSDTUSDT"),"股票不再被合成一次");
  assert!(!map.contains_key("MYSTERYUSDT"),"没有分类的币不合成品种名");
  // 上限跟 symbols 那一路一样，不是无限制。
  let many:SupplyTable=(0..PAYLOAD_LIMIT+50).map(|i|(format!("C{i}"),supply(1.0))).collect();
  let kinds=(0..PAYLOAD_LIMIT+50).map(|i|(format!("C{i}USDT"),Kind::Crypto)).collect();
  let big=Market::fresh(many,EquityTable::new(),kinds);
  assert_eq!(meta_payload(&big,None).as_object().unwrap().len(),PAYLOAD_LIMIT);
 }
 #[test]
 fn missing_fields_are_dropped_rather_than_nulled() {
  let value=Meta{total_supply:Some(1.0),..Meta::default()}.value();
  assert_eq!(value,json!({"totalSupply":1.0}));
  // 身份是内部字段：它绝不出现在客户端看到的 JSON 里。
  let owned=Meta{total_supply:Some(1.0),family:Some(Family::Binance),..Meta::default()}.value();
  assert_eq!(owned,json!({"totalSupply":1.0}));
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
 fn oi_payload_drops_an_unknown_notional() {
  let out=oi_payload("BTCUSDT",&OpenInterest{open_interest:1.5,value:None,time:7});
  assert_eq!(out,json!({"symbol":"BTCUSDT","openInterest":1.5,"time":7}));
 }
 #[test]
 fn a_stock_is_never_answered_out_of_the_coin_table() {
  // NVDA and META are both a listed company and an unrelated altcoin. Before
  // the contract list was consulted, NVDAUSDT reported the altcoin's supply,
  // which put a 15-million-dollar market cap on Nvidia.
  let mut m=market(table(&[("NVDA",supply(91_937.5)),("BTC",supply(19_800_000.0))]),&["BTCUSDT"]);
  m.equities=[("NVDAUSDT".to_owned(),priced(24_100_000_000.0,180.0))].into_iter().collect();
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
  let mut m=market(table(&[("SPY",supply(1_000_000.0))]),&[]);
  m.kinds=[("SPYUSDT".to_owned(),Kind::TickerEquity)].into_iter().collect();
  assert_eq!(m.meta("SPYUSDT"),None);
  assert!(meta_payload(&m,Some("SPYUSDT")).as_object().unwrap().is_empty());
 }
 /// B-01 / B-T01 / B-T02：币安没说这个合约写在什么上面，就什么都不答。
 #[test]
 fn an_unclassified_symbol_is_answered_with_nothing() {
  // 以前这里兜底成「币」，于是 exchangeInfo 一失败，NVDAUSDT 就会报出那个叫 NVDA
  // 的山寨币的供应量。OKX 独有的永续也走这条路：少一个市值，不给一个错市值。
  let unknown=market(table(&[("PEPE",supply(420_690_000_000.0)),("NVDA",supply(91_937.5))]),&[]);
  assert_eq!(unknown.kind("PEPE-USDT-SWAP"),Kind::Unknown);
  assert_eq!(unknown.meta("PEPE-USDT-SWAP"),None);
  assert_eq!(unknown.meta("NVDAUSDT"),None,"股票的查询绝不落到币表上");
  assert!(meta_payload(&unknown,Some("NVDAUSDT,PEPEUSDT")).as_object().unwrap().is_empty());
  // 说清楚是币之后照常答，打包合约也照常。
  let known=market(table(&[("PEPE",supply(420_690_000_000.0))]),&["PEPE-USDT-SWAP","1000PEPEUSDT"]);
  assert!(known.meta("PEPE-USDT-SWAP").is_some());
  assert!(known.meta("1000PEPEUSDT").is_some());
 }
 /// B-T02：exchangeInfo 的行缺 `underlyingType`，结果是 unknown，不是「放行股票市值」。
 #[test]
 fn a_row_without_an_underlying_type_classifies_as_unknown() {
  let body=json!({"symbols":[{"symbol":"MYSTERYUSDT","baseAsset":"MYSTERY"},
   {"symbol":"BLANKUSDT","baseAsset":"BLANK","underlyingType":""}]});
  let contracts=parse_exchange_info(&body);
  assert!(contracts.iter().all(|c|c.kind==Kind::Unknown));
  let m=Market::fresh(table(&[("MYSTERY",supply(1_000.0))]),EquityTable::new(),kinds_of(&contracts));
  assert_eq!(m.meta("MYSTERYUSDT"),None);
 }
 /// B-03：发布出去的数字有年龄上限。缓存可以一直留着，但七天没刷成功就留空。
 #[test]
 fn a_figure_nobody_could_refresh_for_a_week_stops_being_published() {
  let coins=table(&[("BTC",supply(19_800_000.0))]);
  let kinds:HashMap<String,Kind>=[("BTCUSDT",Kind::Crypto),("NVDAUSDT",Kind::TickerEquity)]
   .iter().map(|(k,v)|((*k).to_owned(),*v)).collect();
  let day=Duration::from_secs(24*60*60);
  let equities:EquityTable=[
   ("NVDAUSDT".to_owned(),aged(24_100_000_000.0,180.0,6*day))].into_iter().collect();
  let fresh=Market{coins:coins.clone(),equities:equities.clone(),kinds:kinds.clone(),coins_at:Some(SystemTime::now()-6*day),..Market::default()};
  assert!(fresh.meta("BTCUSDT").is_some(),"六天大的表照常发布");
  assert!(fresh.meta("NVDAUSDT").is_some());

  let stale=Market{coins:coins.clone(),equities:[("NVDAUSDT".to_owned(),aged(24_100_000_000.0,180.0,8*day))].into_iter().collect(),
   kinds:kinds.clone(),coins_at:Some(SystemTime::now()-8*day),..Market::default()};
  assert_eq!(stale.meta("BTCUSDT"),None,"八天没刷成功的供应量不再出门");
  assert_eq!(stale.meta("NVDAUSDT"),None,"股票乘数同一把尺子");
  // 表还在缓存里——留着是为了下一轮刷新有底可依，只是不发布。
  assert!(stale.coins.contains_key("BTC"));
  // 不知道年龄跟过期一样处理。
  let ageless=Market{coins,equities,kinds,coins_at:None,..Market::default()};
  assert_eq!(ageless.meta("BTCUSDT"),None);
  assert!(!expired(Some(SystemTime::now()+Duration::from_secs(60))),"机器对时不算数据变旧");
 }
 /// B-T09：k 的有效期不只是年龄——拆股当天它就作废。
 #[test]
 fn a_split_retires_the_multiplier_even_inside_its_window() {
  assert!(!unit_changed(180.0,183.0),"日常波动不算换单位");
  assert!(unit_changed(180.0,90.0),"2 拆 1：股价腰斩，旧 k 会把市值报成一半");
  assert!(unit_changed(90.0,180.0),"合股同理");
  assert!(unit_changed(0.0,180.0),"不知道旧价格时不敢留");
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
 /// 一张跟真页面同形的页：身份字段在嵌套对象里、而且也是索引，市值在另一个节点上。
 fn listing_page(symbol:&str,name:&str,cap:&str)->Value {
  json!({"type":"data","nodes":[
   {"type":"data","data":[{"symbol":1,"db_symbol":1,"nameFull":2,"name":2,"exchange_symbol":3},symbol,name,"KRX"]},
   {"type":"data","data":[{"marketCap":1,"sharesOut":2},cap,"728.87M"]}]})
 }
 /// B.3 / B-T08：页面 200 了、市值也是个合法数字，但那是另一家公司——不许发布。
 #[test]
 fn a_page_about_another_company_publishes_nothing() {
  let right=listing_page("000660","SK hynix Inc.","929.61B");
  let (code,keyword)=expected_identity("SKHYNIX","quote/krx/000660");
  assert_eq!(code,"000660");
  assert_eq!(keyword,Some("SKHYNIX"));
  assert!(page_is(&right,&code,keyword));
  assert_eq!(parse_stockanalysis_cap(&right),Some(929.61e9));

  // 同一个地址答成了别人：代码不对、名字也不对。市值再合法也不是我们要的那个。
  let wrong=listing_page("ANTH","AN2 Therapeutics, Inc.","192.40M");
  assert!(!page_is(&wrong,&code,keyword),"身份不符就当没有市值");
  // 名字对得上也算：有些页面把代码写成 `000660.KS` 这种带后缀的形式。
  let suffixed=listing_page("000660.KS","SK hynix Inc.","929.61B");
  assert!(page_is(&suffixed,&code,keyword));
  // 一条身份证据都举不出来（验证码页、空壳页）：按「不是」处理。
  assert!(!page_is(&json!({"nodes":[{"data":[{"marketCap":1},"929.61B"]}]}),&code,keyword));
  // 美股那一路的代码就是合约名自己。
  let (code,keyword)=expected_identity("AAPL","stocks/AAPL");
  assert_eq!((code.as_str(),keyword),("AAPL",None));
  assert!(page_is(&listing_page("AAPL","Apple Inc.","4.39T"),"AAPL",None));
  assert!(!page_is(&listing_page("AAPU","Apple 2x Bull ETF","1.2B"),"AAPL",None));
  // BRK.B 这种带点的代码，两边都规范化之后才比。
  let (code,keyword)=expected_identity("BRKB","stocks/BRK.B");
  assert!(page_is(&listing_page("BRK.B","Berkshire Hathaway Inc.","1.07T"),&code,keyword));
 }
 #[test]
 fn an_etf_page_carries_no_capitalisation() {
  // It reports assets under management instead, which is not a market cap and
  // must never be published as one.
  let body=json!({"nodes":[{"data":[{"aum":1,"nav":2},"$475.29B","716.47"]}]});
  assert_eq!(parse_stockanalysis_cap(&body),None);
 }
 /// B-09 / B-T10：未上市公司没有市值，二级市场的估值不当市值发布。
 #[test]
 fn an_unlisted_company_has_no_market_cap_at_all() {
  // 这两个名字已经不在 LISTINGS 里，所以连页面地址都不存在；分类也不再是「股票」。
  assert_eq!(listing(Kind::PreMarket,"OPENAI"),None);
  assert_eq!(listing(Kind::PreMarket,"ANTHROPIC"),None);
  assert_eq!(listing(Kind::NamedEquity,"OPENAI"),None,"就算被误分成股票，也没有地址可猜");
  // 估值页那种 `statsLeft` 里的「Implied Valuation」不再被读成市值。
  let valuation=json!({"nodes":[{"data":[
   {"statsLeft":1},[2],{"label":3,"value":4},"Implied Valuation","$880.67B"]}]});
  assert_eq!(parse_stockanalysis_cap(&valuation),None);
  // payload 那一路也一样：PREMARKET 的合约一个字段都不给。
  let m=Market::fresh(table(&[("OPENAI",supply(1_000.0))]),
   [("OPENAIUSDT".to_owned(),priced(5.0,10.0))].into_iter().collect(),
   [("OPENAIUSDT".to_owned(),Kind::PreMarket)].into_iter().collect());
  assert_eq!(m.meta("OPENAIUSDT"),None);
  assert!(meta_payload(&m,Some("OPENAIUSDT")).as_object().unwrap().is_empty(),
   "字段不是给个 0，是整个不出现");
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
  // Never guessed: `stocks/ANTH` is AN2 Therapeutics, a 192M biotech, and
  // publishing that as Anthropic's market cap is worse than publishing nothing.
  assert_eq!(listing(Kind::NamedEquity,"MOONSHOT"),None);
  assert_eq!(listing(Kind::Other,"XAU"),None);
  assert_eq!(listing(Kind::Unknown,"AAPL"),None,"分类都不知道就不去读任何页面");
  assert_eq!(listing(Kind::PreMarket,"ANTHROPIC"),None);
 }
 #[test]
 fn a_listings_currency_follows_its_exchange() {
  assert_eq!(listing_currency("quote/hkg/0700"),"HKD");
  assert_eq!(listing_currency("quote/krx/000660"),"KRW");
  assert_eq!(listing_currency("quote/sha/688825"),"CNY");
  assert_eq!(listing_currency("stocks/BRK.B"),"USD");
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
  assert_eq!(by["OPENAIUSDT"].kind,Kind::PreMarket,"未上市：没有市值可发布");
  assert_eq!(by["LEGACYUSDT"].kind,Kind::Unknown,"没有这个字段就是不知道，不是「币」");
  // USD1 is a quote asset too, so the base has to come off the row, not off
  // the end of the symbol.
  assert_eq!(by["SPCXUSD1"].base,"SPCX");
  assert_eq!(kinds_of(&contracts)["NVDAUSDT"],Kind::TickerEquity);
 }
 #[test]
 fn a_cached_value_expires_but_stays_readable() {
  let cache=Cache::new();
  cache.store(market(table(&[("BTC",supply(19_800_000.0))]),&["BTCUSDT"]));
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

 // ------------------------------------------------ 刷新调度（单飞、分两次发布、快照）

 /// 一个假上游。记下每个 URL 被抓了几次，这样「到底抓了一遍还是两遍」可以断言，
 /// 而不是靠读代码相信。
 struct Fake {bodies:HashMap<String,Value>,hits:std::sync::Mutex<HashMap<String,usize>>,hang:Option<String>,delay:Duration}
 impl Fake {
  fn new(bodies:HashMap<String,Value>)->Self {
   // 每次抓停一小会儿，好让「刷新还在跑」这个状态真的存在一段时间。
   Fake{bodies,hits:std::sync::Mutex::new(HashMap::new()),hang:None,delay:Duration::from_millis(5)}
  }
  /// 让某个 URL 永远不答——上游卡死，不是报错。
  fn hanging(mut self,url:&str)->Self {self.hang=Some(url.to_owned());self}
  fn hits(&self,url:&str)->usize {self.hits.lock().unwrap_or_else(|e|e.into_inner()).get(url).copied().unwrap_or(0)}
 }
 impl Source for Arc<Fake> {
  fn json<'a>(&'a self,url:&'a str)->Pin<Box<dyn Future<Output=Result<Value>>+Send+'a>> {
   *self.hits.lock().unwrap_or_else(|e|e.into_inner()).entry(url.to_owned()).or_default()+=1;
   let hanging=self.hang.as_deref()==Some(url);
   let body=self.bodies.get(url).cloned();
   let delay=self.delay;
   Box::pin(async move {
    if hanging {std::future::pending::<()>().await}
    tokio::time::sleep(delay).await;
    body.ok_or_else(upstream)
   })
  }
  fn gap(&self)->Duration {Duration::ZERO}
 }
 fn stock_page()->String {format!("{STOCKANALYSIS}stocks/NVDA/__data.json")}
 /// 一个够用的全市场：一个币、一只股票，外加一个跟那只股票同名的山寨币。
 /// CoinGecko 的四页故意不给，页循环第一页就报错退出，省掉那 1200ms 的间隔。
 fn fake_upstream()->Fake {
  Fake::new(HashMap::from([
   (APEX.to_owned(),json!({"data":[
    {"symbol":"BTCUSDT","baseAsset":"BTC","quoteAsset":"USDT","circulatingSupply":19_800_000.0,"totalSupply":19_800_000.0,"maxSupply":21_000_000.0,"rank":1},
    // 同名山寨币。NVDAUSDT 要是被当成币去查，查到的就是这一行。
    {"symbol":"NVDAUSDT","baseAsset":"NVDA","quoteAsset":"USDT","circulatingSupply":1_000_000.0,"totalSupply":1_000_000.0,"rank":900}]})),
   (PRODUCTS.to_owned(),json!({"data":[]})),
   (EXCHANGE_INFO.to_owned(),json!({"symbols":[
    {"symbol":"BTCUSDT","baseAsset":"BTC","underlyingType":"COIN"},
    {"symbol":"NVDAUSDT","baseAsset":"NVDA","underlyingType":"EQUITY"}]})),
   (FX.to_owned(),json!({"rates":{"USD":1.0,"HKD":7.8}})),
   (BINANCE_PRICES.to_owned(),json!([{"symbol":"NVDAUSDT","price":"180.0"}])),
   // 页面要自证身份，否则一律留空（B.3）。
   (stock_page(),listing_page("NVDA","NVIDIA Corporation","4.39T")),
  ]))
 }
 /// 每条用例一份自己的调度，互不干扰；泄漏是为了拿到方法要求的 `&'static`。
 fn instance(source:Arc<Fake>,snapshot:Option<PathBuf>)->&'static Supply {
  Box::leak(Box::new(Supply::new(Box::new(source),snapshot)))
 }

 #[tokio::test]
 async fn a_request_arriving_during_warm_up_waits_for_it_instead_of_fetching_again() {
  let fake=Arc::new(fake_upstream());
  let supply=instance(fake.clone(),None);
  let warm=tokio::spawn(async move {supply.cycle().await});
  // 等预热真的开抓，这样下面这个请求落在「刷新进行中」里。
  while fake.hits(APEX)==0 {tokio::task::yield_now().await}
  let table=supply.table().await.expect("the in-flight refresh answers the cold request");
  assert!(table.meta("BTCUSDT").is_some());
  warm.await.expect("warm-up task").expect("warm-up finished");
  assert_eq!(fake.hits(APEX),1,"整张表只被抓了一遍，请求没有自己再抓一次");
  assert_eq!(fake.hits(EXCHANGE_INFO),1);
  assert_eq!(fake.hits(&stock_page()),1,"股票页面也没有被抓两遍");
 }

 /// P4.8：刷新这一轮就把 CoinGecko 撞错身份的合约认出来，币的那一半第一次发布时
 /// 就已经留空，不会先答一轮错数。
 #[tokio::test]
 async fn the_refresh_blanks_a_coingecko_identity_the_contract_price_refutes() {
  let mut bodies=fake_upstream().bodies;
  bodies.insert(format!("{COINGECKO}1"),json!([
   {"id":"bob-build-on-bitcoin","symbol":"bob","current_price":0.005_717_32,"circulating_supply":3_000_000_000.0,"total_supply":10_000_000_000.0,"market_cap_rank":942},
   {"id":"zcash","symbol":"zec","current_price":51.0,"circulating_supply":16_000_000.0,"total_supply":21_000_000.0,"market_cap_rank":80}]));
  bodies.insert(EXCHANGE_INFO.to_owned(),json!({"symbols":[
   {"symbol":"BTCUSDT","baseAsset":"BTC","underlyingType":"COIN"},
   {"symbol":"1000000BOBUSDT","baseAsset":"1000000BOB","underlyingType":"COIN"},
   {"symbol":"ZECUSDT","baseAsset":"ZEC","underlyingType":"COIN"},
   {"symbol":"NVDAUSDT","baseAsset":"NVDA","underlyingType":"EQUITY"}]}));
  bodies.insert(BINANCE_PRICES.to_owned(),json!([{"symbol":"NVDAUSDT","price":"180.0"},{"symbol":"1000000BOBUSDT","price":"0.01988"},{"symbol":"ZECUSDT","price":"52.3"}]));
  let fake=Arc::new(Fake::new(bodies));
  let supply=instance(fake.clone(),None);
  let table=supply.table().await.expect("table");
  assert_eq!(table.meta("1000000BOBUSDT"),None,"撞错身份的留空");
  assert_eq!(table.meta("ZECUSDT").and_then(|m|m.circulating_supply),Some(16_000_000.0),"价格对得上的照常");
  assert!(table.meta("BTCUSDT").is_some());
 }

 #[tokio::test]
 async fn a_cold_request_is_answered_by_the_one_refresh_it_starts() {
  let fake=Arc::new(fake_upstream());
  let supply=instance(fake.clone(),None);
  let table=supply.table().await.expect("a cold request still gets a table");
  let payload=meta_payload(&table,Some("BTCUSDT"));
  assert_eq!(payload.as_object().map(serde_json::Map::len),Some(1),"问一个品种就只答这一个");
  assert_eq!(fake.hits(APEX),1);
 }

 #[tokio::test]
 async fn a_stock_page_that_never_answers_does_not_hold_up_the_table() {
  let fake=Arc::new(fake_upstream().hanging(&stock_page()));
  let supply=instance(fake.clone(),None);
  // 股票那一趟永远不回，请求拿到的是「币先发布」的那一版。
  let table=supply.table().await.expect("the coin half is published before the equity sweep");
  assert!(table.meta("BTCUSDT").is_some(),"币的那一半照常答");
  assert_eq!(table.meta("NVDAUSDT"),None,"还没定价的股票答空，而不是同名山寨币的供应量");
  assert_eq!(table.kind("NVDAUSDT"),Kind::TickerEquity,"提前发布的表已经分得清股票和币");
 }

 /// B-01：这一轮没拿到任何合约分类、上一轮也没留下可继承的，就一个字都不发布。
 ///
 /// 发了的代价不是「表里全是 Unknown」这么轻——`coins_at` 会写成此刻，于是
 /// `table()` 在 24 小时内都认这张表新鲜，预热循环也把下一轮推到 SUPPLY_TTL 之后。
 /// 冷启动时 exchangeInfo 失败一次，换来的是整天答不出一个市值。
 #[tokio::test]
 async fn a_round_with_no_classification_at_all_publishes_nothing_and_fails() {
  let mut bodies=fake_upstream().bodies;
  bodies.remove(EXCHANGE_INFO);
  let fake=Arc::new(Fake::new(bodies));
  let supply=instance(fake.clone(),None);
  assert!(supply.cycle().await.is_err(),"这一轮算失败，预热循环 600 秒后再来，而不是 24 小时");
  assert!(supply.cache.stale().is_none(),"一张分不出股票和币的表连旧表都不算，缓存里什么都没有");
  assert_eq!(fake.hits(&stock_page()),0,"没有分类就没有股票要定价");
  // 请求这时拿到的是 503，而不是一张会把 NVDAUSDT 报成同名山寨币的表。
  assert!(supply.table().await.is_err(),"没有表就明说没有");

  // exchangeInfo 回来的那一轮照常发布。
  let back=instance(Arc::new(fake_upstream()),None);
  let table=back.cycle().await.expect("分类到手，这一轮就成立");
  assert_eq!(table.kind("NVDAUSDT"),Kind::TickerEquity);
 }

 /// A-06：这道闸门只该由 binance.com 自己按下。
 ///
 /// `get_json` 同一个函数同时服务 CoinGecko、stockanalysis.com 和 open.er-api.com，
 /// 而 CoinGecko 对匿名调用者是按分钟限速的。写侧少一道 `covers` 守卫，它的一个 429
 /// 就会把币安的出口按停两分钟，还连坐 `sector_history` 与 `oi_archive`。
 // 跨 await 持有是故意的：这把锁就是「同时只许一条测试碰那道进程级闸门」的实现。
 #[allow(clippy::await_holding_lock)]
 #[tokio::test]
 async fn a_rate_limited_third_party_does_not_press_the_binance_gate() {
  let _guard=binance_gate::test_lock().lock().unwrap();
  binance_gate::clear();
  // 一个只会回 429 的本地服务器，答两次就收摊。两次的回答完全一样，唯一的变量是
  // 请求的 URL 长得像谁——`covers` 认的就是这个。
  let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.expect("bind");
  let port=listener.local_addr().expect("addr").port();
  let server=tokio::spawn(async move {
   for _ in 0..2 {
    let (mut socket,_)=listener.accept().await.expect("accept");
    use tokio::io::{AsyncReadExt,AsyncWriteExt};
    let _=socket.read(&mut [0u8;2048]).await;
    let _=socket.write_all(b"HTTP/1.1 429 Too Many Requests\r\nRetry-After: 60\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}").await;
    let _=socket.shutdown().await;
   }
  });

  let third_party=format!("http://127.0.0.1:{port}/api/v3/coins/markets?page=1");
  assert!(!binance_gate::covers(&third_party));
  assert!(get_json(&third_party).await.is_err(),"429 仍然是这一次抓取失败");
  assert!(!binance_gate::blocked(),"第三方的 429 不许按下币安的闸门");

  let binance=format!("http://127.0.0.1:{port}/fapi.binance.com/fapi/v1/ticker");
  assert!(binance_gate::covers(&binance));
  assert!(get_json(&binance).await.is_err());
  assert!(binance_gate::blocked(),"币安自己的 429 照常按下闸门");
  binance_gate::clear();
  server.await.expect("server task");
 }

 #[tokio::test]
 async fn the_snapshot_serves_the_next_start_and_a_broken_file_only_means_no_snapshot() {
  let dir=tempfile::tempdir().expect("temp dir");
  let path=dir.path().join("supply.json");
  let fake=Arc::new(fake_upstream());
  instance(fake.clone(),Some(path.clone())).cycle().await.expect("first process fills the table");
  assert!(path.exists(),"一轮完整刷新之后留下快照");

  // 下一个进程：上游一个都不给，快照必须能独立把表顶起来。
  let offline=Arc::new(Fake::new(HashMap::new()));
  let next=instance(offline.clone(),Some(path.clone()));
  assert!(next.restore(),"快照装得进来");
  let table=next.cache.stale().expect("restored table");
  assert!(table.meta("BTCUSDT").is_some());
  assert!(table.meta("NVDAUSDT").is_some_and(|m|m.total_supply.is_some()),"股票的乘数也一起存了");
  assert_eq!(offline.hits(APEX),0,"装快照不碰上游");
  assert!(next.cache.fresh(SUPPLY_TTL).is_none(),"快照算旧表，第一个请求照样会踢一次后台刷新");

  std::fs::write(&path,b"{not json").expect("write");
  assert!(!instance(offline.clone(),Some(path.clone())).restore(),"读坏了只当没有快照");
  let wrong=json!({"version":SNAPSHOT_VERSION+1,"coins":{"BTC":{}},"equities":{},"kinds":{"BTCUSDT":"Crypto"}});
  std::fs::write(&path,serde_json::to_vec(&wrong).expect("encode")).expect("write");
  assert!(!instance(offline,Some(path)).restore(),"版本对不上也只当没有快照");
 }

 /// 快照里必须带着年龄，否则一次重启就把七天上限清零了（B-03）。
 #[tokio::test]
 async fn a_restored_snapshot_keeps_its_age() {
  let dir=tempfile::tempdir().expect("temp dir");
  let path=dir.path().join("supply.json");
  let fake=Arc::new(fake_upstream());
  instance(fake,Some(path.clone())).cycle().await.expect("first process fills the table");
  let raw=std::fs::read(&path).expect("read");
  let mut snapshot:Value=serde_json::from_slice(&raw).expect("decode");
  assert!(!snapshot["coins_at"].is_null(),"时刻写进了快照");
  // 把它改成八天前：装回来之后就不该再发布了，尽管文件是刚写的。
  let eight_days_ago=SystemTime::now()-Duration::from_secs(8*24*60*60);
  snapshot["coins_at"]=serde_json::to_value(eight_days_ago).expect("encode time");
  for (_,priced) in snapshot["equities"].as_object_mut().expect("equities").iter_mut() {
   priced["at"]=serde_json::to_value(eight_days_ago).expect("encode time");
  }
  std::fs::write(&path,serde_json::to_vec(&snapshot).expect("encode")).expect("write");
  let next=instance(Arc::new(Fake::new(HashMap::new())),Some(path));
  assert!(next.restore(),"照样装得进来——缓存是恢复材料，留着");
  let table=next.cache.stale().expect("restored table");
  assert!(table.coins.contains_key("BTC"),"表还在");
  assert_eq!(table.meta("BTCUSDT"),None,"但八天没刷新的数字不再发布");
  assert_eq!(table.meta("NVDAUSDT"),None);
 }

 /// B-T01：币表里有个不相干的 NVDA，exchangeInfo 这一轮失败。股票的查询不得用币的
 /// 供应量作答——而且「有币表、没分类」这种组合本身连发布都不该发生（B-01）。
 #[tokio::test]
 async fn without_the_contract_list_the_table_answers_nothing() {
  let mut bodies=fake_upstream().bodies;
  bodies.remove(EXCHANGE_INFO);
  let fake=Arc::new(Fake::new(bodies));
  let supply=instance(fake.clone(),None);
  assert!(supply.table().await.is_err(),"没有分类就没有表，请求收到的是 503");
  assert!(supply.cache.stale().is_none(),"连半张表都没留在缓存里");

  // 万一这样一张表还是到了手上（比如某个旧版本存下来的快照），它也一个字都答不出来。
  let table=Market::fresh(merge_assets(&parse_apex(&fake.bodies[APEX]),&[]),EquityTable::new(),HashMap::new());
  assert!(table.coins.contains_key("NVDA"),"那个同名山寨币确实在币表里");
  assert_eq!(table.meta("NVDAUSDT"),None,"股票不会拿它作答");
  assert_eq!(table.meta("BTCUSDT"),None,"分类没到手时连币也不答——不猜");
  assert!(meta_payload(&table,None).as_object().unwrap().is_empty());
 }

 fn equity_contracts()->Vec<Contract> {
  vec![Contract{symbol:"NVDAUSDT".to_owned(),base:"NVDA".to_owned(),kind:Kind::TickerEquity},
   Contract{symbol:"SKHYNIXUSDT".to_owned(),base:"SKHYNIX".to_owned(),kind:Kind::NamedEquity}]
 }
 fn hynix_page()->String {format!("{STOCKANALYSIS}quote/krx/000660/__data.json")}
 /// 一份上一轮留下的股票表，一天大。
 fn yesterdays_equities()->EquityTable {
  let day=Duration::from_secs(24*60*60);
  [("NVDAUSDT".to_owned(),aged(24_000_000_000.0,180.0,day)),
   // 929.61e9 韩元市值 / 1369.81 / 183.79：按韩元算出来的那个数。
   ("SKHYNIXUSDT".to_owned(),aged(3_692_674.0,183.79,day))].into_iter().collect()
 }
 fn equity_fake(rows:Vec<(String,Value)>)->Arc<Fake> {Arc::new(Fake::new(rows.into_iter().collect()))}
 fn good_prices()->Value {json!([{"symbol":"NVDAUSDT","price":"180.0"},{"symbol":"SKHYNIXUSDT","price":"183.79"}])}

 /// B-T07 / A.7：汇率与价格表的四种坏法，各自该怎么处置。
 #[tokio::test]
 async fn each_way_the_inputs_can_fail_has_its_own_answer() {
  let contracts=equity_contracts();
  let previous=yesterdays_equities();
  let both_pages=||vec![(stock_page(),listing_page("NVDA","NVIDIA Corporation","4.39T")),
   (hynix_page(),listing_page("000660","SK hynix Inc.","929.61B"))];

  // 1. 汇率整个抓不到：算不出任何一个，整张旧表留着。
  let mut rows=both_pages();rows.push((BINANCE_PRICES.to_owned(),good_prices()));
  let out=refresh_equities(&equity_fake(rows),&contracts,Some(&previous)).await;
  assert_eq!(out,previous,"FX Err：旧表原样留着，连时刻都不变");

  // 2. 汇率 200 但缺 KRW：美元那只照算，韩元那只这一轮跳过——绝不把汇率当 1。
  let mut rows=both_pages();
  rows.push((BINANCE_PRICES.to_owned(),good_prices()));
  rows.push((FX.to_owned(),json!({"rates":{"USD":1.0}})));
  let out=refresh_equities(&equity_fake(rows),&contracts,Some(&previous)).await;
  assert!((out["NVDAUSDT"].k-4.39e12/180.0).abs()<1.0,"美元那只重算了：{}",out["NVDAUSDT"].k);
  assert!(out["NVDAUSDT"].at>previous["NVDAUSDT"].at);
  assert_eq!(out["SKHYNIXUSDT"],previous["SKHYNIXUSDT"],"韩元那只原样留着，继续变老");
  // 汇率真当成 1 的话会是这个数——差了一千三百倍。
  assert!((out["SKHYNIXUSDT"].k-929.61e9/183.79).abs()>1e9);

  // 3. 价格表抓不到：同样是整张旧表留着。
  let mut rows=both_pages();rows.push((FX.to_owned(),json!({"rates":{"USD":1.0,"KRW":1369.81}})));
  let out=refresh_equities(&equity_fake(rows),&contracts,Some(&previous)).await;
  assert_eq!(out,previous,"价格 Err：旧表留着");

  // 4. 价格表 200 但是个空数组：算不出任何东西，跟抓不到一模一样，绝不清表。
  let mut rows=both_pages();
  rows.push((FX.to_owned(),json!({"rates":{"USD":1.0,"KRW":1369.81}})));
  rows.push((BINANCE_PRICES.to_owned(),json!([])));
  let out=refresh_equities(&equity_fake(rows),&contracts,Some(&previous)).await;
  assert_eq!(out,previous,"价格 200 + 空数组：不许把旧乘数删掉");
 }

 /// B-T08 / A.7：页面本身的三种坏法。
 #[tokio::test]
 async fn a_page_we_could_read_decides_between_blank_and_carried() {
  let contracts=equity_contracts();
  let previous=yesterdays_equities();
  let inputs=||vec![(FX.to_owned(),json!({"rates":{"USD":1.0,"KRW":1369.81}})),
   (BINANCE_PRICES.to_owned(),good_prices())];

  // 页面 200、市值也是个合法数字，但那是另一家公司：留空，把旧值清掉。
  let mut rows=inputs();
  rows.push((stock_page(),listing_page("AAPU","Apple 2x Bull ETF","1.20B")));
  rows.push((hynix_page(),listing_page("000660","SK hynix Inc.","929.61B")));
  let out=refresh_equities(&equity_fake(rows),&contracts,Some(&previous)).await;
  assert!(!out.contains_key("NVDAUSDT"),"身份不符的页面：留空，不是留旧值");
  assert_eq!(out["SKHYNIXUSDT"].k,929.61e9/1369.81/183.79);

  // 页面 200、读得出来、就是没有市值（每一只 ETF）：这一项留空。
  let mut rows=inputs();
  rows.push((stock_page(),json!({"nodes":[{"data":[{"symbol":1,"nameFull":2},"NVDA","NVIDIA Corporation"]},
   {"data":[{"aum":1},"$475.29B"]}]})));
  rows.push((hynix_page(),listing_page("000660","SK hynix Inc.","929.61B")));
  let out=refresh_equities(&equity_fake(rows),&contracts,Some(&previous)).await;
  assert!(!out.contains_key("NVDAUSDT"),"200 但没有市值：那就是没有市值");

  // 页面两次都抓不到：这一轮问不出来，留旧值（还要过七天那一关）。
  let mut rows=inputs();
  rows.push((hynix_page(),listing_page("000660","SK hynix Inc.","929.61B")));
  let fake=equity_fake(rows);
  let out=refresh_equities(&fake,&contracts,Some(&previous)).await;
  assert_eq!(out["NVDAUSDT"],previous["NVDAUSDT"],"抓不到不等于没有市值");
  assert_eq!(fake.hits(&stock_page()),2,"抓不到会立刻重试一次，两次都失败才算");
 }

 /// B-T09 的另一半：拆股之后旧乘数不许再被留下来。
 #[tokio::test]
 async fn a_carried_multiplier_is_dropped_when_the_price_changed_units() {
  let contracts=vec![Contract{symbol:"NVDAUSDT".to_owned(),base:"NVDA".to_owned(),kind:Kind::TickerEquity}];
  let previous:EquityTable=[("NVDAUSDT".to_owned(),aged(24_000_000_000.0,180.0,Duration::from_secs(3600)))].into_iter().collect();
  // 页面抓不到（本该留旧值），但股价从 180 变成了 90：2 拆 1。
  let rows=vec![(FX.to_owned(),json!({"rates":{"USD":1.0}})),
   (BINANCE_PRICES.to_owned(),json!([{"symbol":"NVDAUSDT","price":"90.0"}]))];
  let out=refresh_equities(&equity_fake(rows),&contracts,Some(&previous)).await;
  assert!(out.is_empty(),"拆股之后的旧 k 会把市值报成一半，宁可留空");
 }

 /// B-T11 的 Rust 那一半：`underlyingType` 到分类的真值表跟 Swift 那边共用同一个
 /// 样本文件。只对这一列——客户端那两列由 KanpanCore 自己断言。
 #[test]
 fn the_underlying_type_truth_table_is_shared_with_the_client() {
  const FIXTURE:&str=concat!(env!("CARGO_MANIFEST_DIR"),"/../../KanpanCore/Tests/KanpanCoreTests/Fixtures/underlying_kinds.json");
  let raw=std::fs::read(FIXTURE).unwrap_or_else(|e|panic!(
   "两端共用的分类真值表读不出来（{FIXTURE}）：{e}。这个文件是契约的一部分，    丢了就等于两端各说各话——不要把这条用例跳过，把文件补回来。"));
  let rows:Vec<Value>=serde_json::from_slice(&raw).expect("分类真值表不是合法 JSON");
  assert!(rows.len()>=8,"真值表至少要覆盖每一个 underlyingType 加上「缺这个字段」那一行");
  for row in &rows {
   let expected=row["kind"].as_str().expect("每一行都要写明 kind");
   let mut contract=json!({"symbol":"XUSDT","baseAsset":"X"});
   // null 代表币安根本没给这个字段，那一行不写进合约里。
   if let Some(name)=row["underlyingType"].as_str() {contract["underlyingType"]=json!(name);}
   let parsed=parse_exchange_info(&json!({"symbols":[contract]}));
   let kind=parsed.first().expect("一行进一行出").kind;
   assert_eq!(kind.wire(),expected,"underlyingType={:?} 两端对不上",row["underlyingType"]);
  }
  // 反过来也要全：每一个分类都得在真值表里出现过，新增一个分类就必须同时更新契约。
  for kind in [Kind::Crypto,Kind::TickerEquity,Kind::NamedEquity,Kind::PreMarket,Kind::Other,Kind::Unknown] {
   assert!(rows.iter().any(|row|row["kind"].as_str()==Some(kind.wire())),
    "真值表里没有 {} 这一档",kind.wire());
  }
 }
}
