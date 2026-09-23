//! Mirrors the native wire types at the boundary, before a merged value can reach another device.
use crate::{error::{ApiError,Result},sync::Object};
use serde_json::Value;
// `IndicatorID` (KanpanCore/Indicator/IndicatorID.swift), split the way `IndicatorID.placement`
// splits it: main chart first, sub-panels second. `overlays` accepts only the first half and
// `subs` / `subInverted` only the second, so which half an indicator is in is part of the
// contract, not a detail — an indicator on the wrong side is refused and 400s the whole
// operation. Both halves are generated into `contract/settings-fields.json` as
// `overlayIndicatorIDs` / `subIndicatorIDs`; `the_indicator_vocabulary_is_the_contract_one`
// holds these to it. Slices, not fixed arrays: adding one is a single string, no length to
// keep in step (same reason `sync::SETTINGS_FIELDS` is a slice).
const OVERLAY_INDICATORS:&[&str]=&["MA","EMA","BOLL","VWAP","ST","SAR"];
const SUB_INDICATORS:&[&str]=&["VOL","MACD","RSI","KDJ","SRSI","ATR","OI","LSR","TAKER","BASIS","DMI","CVD"];
fn indicator(name:&str)->bool {OVERLAY_INDICATORS.contains(&name)||SUB_INDICATORS.contains(&name)}
// `Drawing.Kind` in full (KanpanCore/Drawing/Drawing.swift:22). The first ten are the
// original tools; the rest arrived with the TradingView-aligned panel and must be listed
// here or the drawing that uses one can never leave the phone. Generated into the contract as
// `drawingKinds`; `every_drawing_tool_is_in_the_contract` is what notices when this drifts.
const KINDS:&[&str]=&[
 "hline","trend","ray","hray","extended","vline","rectangle","channel","fibonacci","measure",
 "position","regression","fibExtension","priceRange","dateRange","note","crossLine","arrowLine",
 "pitchfork","fibChannel","ellipse","triangle","curve","datePriceRange","fibTimeZone","fibFan",
 "gannBox","gannFan","xabcd","abcd","headShoulders","elliottImpulse","elliottCorrection",
 "callout","priceLabel","flag","markerUp","markerDown",
 // The computed tools (2026-09-20): their shape is derived from the bars the anchors enclose,
 // not from the anchors themselves. Same vocabulary rules apply — the server only stores them.
 "anchoredVWAP","fixedVolumeProfile","anchoredVolumeProfile",
];
// A superset of `Interval` (KanpanCore/Model/Interval.swift:4); 3d and 8h are not offered.
const INTERVALS:[&str;16]=["1m","3m","5m","15m","30m","1h","2h","4h","6h","8h","12h","1d","3d","1w","1M","1y"];
// `SectorQuotePreference.quoteAssets` (KanpanCore/Sector/SectorAggregate.swift:178). Binance
// lists USDC-margined contracts too, so a USDT-only rule refused perfectly real favourites.
const QUOTES:[&str;6]=["USDT","USDC","FDUSD","BUSD","USD1","TUSD"];
fn color(v:&Value)->bool {v.as_object().is_some_and(|o|o.len()==1)&&v["value"].as_str().is_some_and(|s|matches!(s.len(),7|9)&&s.starts_with('#')&&s[1..].bytes().all(|c|c.is_ascii_hexdigit()))}
fn number(v:&Value,lo:f64,hi:f64)->bool {v.as_f64().is_some_and(|v|v.is_finite()&&v>=lo&&v<=hi)}
fn integers(v:&Value,count:usize,lo:i64,hi:i64)->bool {v.as_array().is_some_and(|a|a.len()<=count&&a.iter().all(|v|v.as_i64().is_some_and(|n|n>=lo&&n<=hi)))}
fn names(v:&Value,count:usize,names:&[&str])->bool {v.as_array().is_some_and(|a|a.len()<=count&&a.iter().all(|v|v.as_str().is_some_and(|s|names.contains(&s))))}
fn string(v:&Value,limit:usize)->bool {v.as_str().is_some_and(|s|s.len()<=limit)}
fn one_of(v:&Value,all:&[&str])->bool {v.as_str().is_some_and(|s|all.contains(&s))}
fn symbol(v:&Value)->bool {
 if v.as_str().is_some_and(|s|s.len()<=40 && s.strip_suffix("-USD").is_some_and(|base| !base.is_empty() && base.bytes().all(|c|c.is_ascii_uppercase()||c.is_ascii_digit()))) {return true}
v.as_str().is_some_and(|s|s.len()<=40&&QUOTES.iter().any(|q|s.ends_with(q))&&s.bytes().all(|c|c.is_ascii_uppercase()||c.is_ascii_digit()))}
/// How many anchors a finished drawing of this kind carries: `Drawing.Kind.pointCount`.
fn anchor_count(kind:&str)->usize {
 match kind {
  "hline"|"vline"|"hray"|"note"|"crossLine"|"priceLabel"|"flag"|"markerUp"|"markerDown"
   |"anchoredVWAP"|"anchoredVolumeProfile"=>1,
  "channel"|"regression"|"position"|"fibExtension"|"pitchfork"|"fibChannel"|"triangle"|"curve"=>3,
  "abcd"|"elliottCorrection"=>4,"xabcd"=>5,"elliottImpulse"=>6,"headShoulders"=>7,_=>2
 }
}
/// 一条提醒摊平出来的价格折线组：`[{points:[{t,p}],extendLeft,extendRight}]`。
///
/// 服务端不认识画线的种类——客户端负责把趋势线、通道、矩形、斐波那契各级都摊成若干条
/// 「时间→价格」的折线，服务端只在时间上做线性插值 / 按 extend 标志外推。所以这里的
/// 规则只管形状：每个元素恰好三个键，点按 `drawings.anchors` 的 {t,p} 同一形状，
/// 数字必须有限（`number` 已经挡了 NaN / ±∞：一条 NaN 的线会让触发判断恒假或恒真，
/// 而且它一路存到 jsonb 里之后谁也看不出哪儿不对）。
///
/// 一条线一个点是合法的：水平线摊平之后就是「一个价 + 两端都延伸」。
fn lines(v:&Value)->bool {
 v.as_array().is_some_and(|all|all.len()<=32&&all.iter().all(|line|{
  line.as_object().is_some_and(|o|o.len()==3&&o.contains_key("points")&&o.contains_key("extendLeft")&&o.contains_key("extendRight"))
   && line["extendLeft"].is_boolean() && line["extendRight"].is_boolean()
   && line["points"].as_array().is_some_and(|ps|(1..=64).contains(&ps.len())
    && ps.iter().all(|p|p.as_object().is_some_and(|o|o.len()==2)&&number(&p["t"],0.0,9e15)&&number(&p["p"],-1e15,1e15)))
 }))
}
fn style(v:&Value)->bool {v.as_object().is_some_and(|o|o.iter().all(|(k,v)|field("drawings",k,v))&&o.contains_key("lineWidth")&&o.contains_key("dash")&&o.contains_key("filled")&&o.contains_key("levels"))}
fn compare_key(v:&Value)->bool {
 let Some(s)=v.as_str() else {return false};
 let p:Vec<_>=s.split('/').collect();
 s.len()<=128 && p.len()==3 && p.iter().all(|v|!v.is_empty())
 && p[..2].iter().all(|v|v.bytes().all(|c|c.is_ascii_lowercase()||c.is_ascii_digit()||c==b'_'))
 && p[2].bytes().all(|c|c.is_ascii_uppercase()||c.is_ascii_digit()||c==b'-'||c==b'_')
}
pub fn field(collection:&str,path:&str,v:&Value)->bool {
 let p:Vec<_>=path.split('/').collect();
 // A null is a field tombstone; required drawing fields are checked again after merging.
 //
 // `text` is here because a phone that is already in someone's pocket still sends it that
 // way: the old encoder dropped an empty caption from the JSON altogether, and the client's
 // diff turns a key that used to be there and is not any more into `text: null`. Refusing
 // that null is what made "clear the caption on a note" a 400 for the whole operation.
 // New clients send `""` instead (see `Drawing.encode`); `clear_tombstones` folds the null
 // into the same `""` so nothing downstream has to remember that null also means empty.
 // 提醒里那几个可空字段同理：「再次提醒」把一条已触发的提醒重新武装，客户端把
 // firedAt / firedPrice 清掉；`kind` 从 drawing 改成别的时 drawingID 也会被清。
 // 客户端的 diff 把「这次不写这个 key」发成 null，拒收它就等于整条 op 400。
 if v.is_null(){return p.len()==1&&matches!(path,"color"|"groupId"|"text")
  || collection=="alerts"&&p.len()==1&&matches!(path,"drawingID"|"firedAt"|"firedPrice"|"dueAt"|"reviewID")
  || collection=="settings"&&p.len()>=2 || collection=="drawingPreferences"&&p.len()==2}
 if collection=="settings" {
  if p.len()>1 {
   if !indicator(p[1]) {return false}
   return match p[0] {
    "params"=>p.len()==2&&integers(v,20,1,400),
    "hiddenOutputs"=>p.len()==2&&integers(v,21,0,20),
    "indicatorColors"=>p.len()==3&&p[2].parse::<u8>().is_ok_and(|n|n<=20)&&color(v),
    "subHeightOverrides"=>p.len()==2&&number(v,0.25,5.0),
    "subHeights"=>p.len()==2&&v.as_str().is_some_and(|s|["small","medium","large"].contains(&s)),_=>false
   }
  }
  return match path {
   "overlays"=>names(v,OVERLAY_INDICATORS.len(),OVERLAY_INDICATORS),"subs"=>names(v,SUB_INDICATORS.len(),SUB_INDICATORS),
   // `subInverted` is a set of sub-panel ids, same vocabulary as `subs`.
   "subInverted"=>names(v,SUB_INDICATORS.len(),SUB_INDICATORS),
   "quickIntervals"=>names(v,10,&INTERVALS),"interval"=>one_of(v,&INTERVALS),
   "rsiRange"=>v.as_array().is_some_and(|a|a.len()==2&&number(&a[0],0.0,100.0)&&number(&a[1],0.0,100.0)&&a[0].as_f64()<a[1].as_f64()),
   "portraitHeight"=>number(v,0.1,1.0),
   // `Prefs.clampSpacing` never stores anything outside AICoinBehavior's 1.6…40pt.
   "barSpacing"=>number(v,1.6,40.0),
   // Only 1 / 2 / 4, per `Prefs.clampSpeed`.
   "compareSymbols"=>v.as_array().is_some_and(|a|a.len()<=3 && a.iter().all(compare_key) && a.iter().enumerate().all(|(i,v)| !a[..i].contains(v))),
   "replaySpeed"=>v.as_i64().is_some_and(|n|matches!(n,1|2|4)),
   "skin"=>one_of(v,&["sage","terra","classic"]),
   "routePolicy"=>one_of(v,&["direct","gateway"]),
   // `alert`（离提醒线最近）是 2026-09-20 随提醒功能加的。这一档和客户端
   // `Prefs.favoriteSorts` 是同一张表，少一个值就会把整条 settings 操作顶回去。
   "favoritesSort"=>one_of(v,&["custom","name","price","change","volume","alert"]),
   "sectorMarket"=>one_of(v,&["crypto","us"]),
   "sectorWindow"=>one_of(v,&["today","d5","d20"]),
   "sectorSort"=>one_of(v,&["change","volume"]),
   "reviewSearchScope"=>one_of(v,&["history","private"]),
   "alertSound"=>one_of(v,&["default","crisp","electronic","glass"]),
   // 自选波动提醒的幅度（百分数），和客户端 `WatchMove.thresholdRange` 同一个区间。
   "watchMoveThreshold"=>number(v,0.1,50.0),
   // Empty means "has not picked one yet" for both.
   "lastDrawTool"=>v.as_str().is_some_and(|s|s.is_empty()||KINDS.contains(&s)),
   // A tab label on the drawing panel, not an enum with any server meaning; the client
   // falls back when the saved one is gone, so the length is the only real rule.
   "drawToolGroup"=>string(v,128),
   // The favorites category the person is parked on: a client-side UUID, and the client falls
   // back to the first category when the saved one is gone. Same tier as `drawToolGroup`:
   // length is the only rule the server can honestly enforce. Empty means "has not picked one".
   // Being on the allowlist without a rule here would make the field a poison pill — the
   // `_=>false` fallthrough rejects the whole operation with a 400.
   "favoritesGroup"=>string(v,128),
   // Capped at `Prefs.maxExpanded`.
   "favoritesExpanded"=>v.as_array().is_some_and(|a|a.len()<=500&&a.iter().all(|v|symbol(v)||v.as_str().is_some_and(|s|{let p:Vec<_>=s.split('/').collect();p.len()==3&&identity(p[0],p[1],p[2])}))),
   "ambientTheme"|"redUp"|"magnet"|"countdown"|"depth"|"orderFlow"|"lastLine"|"sinceChange"|"showDrawings"|"allowMainInversion"|"allowSubInversion"|"adaptiveIndicators"|"compactValues"
    |"mainInverted"|"keepAwake"|"favoritesAscending"|"favoritesAmount"|"favoritesSparkline"|"watchMoveAlert"=>v.is_boolean(),
   "theme"|"styleID"|"priceMode"|"timeZone"|"candleKind"|"gridChoice"|"bodyChoice"|"viewAnchor"|"priceBias"|"dataDisplay"|"crossPrice"|"changeBasis"=>string(v,64),_=>false
  }
 }
 if collection=="drawingPreferences" {return match path {"favorites"=>names(v,KINDS.len(),KINDS),"magnet"|"continuous"=>v.is_boolean(),
  _=>p.len()==2&&KINDS.contains(&p[1])&&match p[0] {"styles"=>style(v),"variants"=>v.as_str().is_some_and(|s|KINDS.contains(&s)),_=>false}}}
 if p.len()!=1 {return false}
 match (collection,path) {
  ("drawings","kind")=>v.as_str().is_some_and(|s|KINDS.contains(&s)),
  // Up to eight: `Drawing.Part.anchors`, which the seven-point head-and-shoulders needs.
  ("drawings","anchors")=>v.as_array().is_some_and(|a|(1..=8).contains(&a.len())&&a.iter().all(|p|p.as_object().is_some_and(|o|o.len()==2)&&number(&p["t"],0.0,9e15)&&number(&p["p"],-1e15,1e15))),
  ("drawings","color")=>color(v),
  ("drawings","lineWidth")=>number(v,0.5,6.0),
  ("drawings","dash")=>v.as_str().is_some_and(|s|["solid","dashed","dotted"].contains(&s)),
  ("drawings","filled"|"locked"|"hidden")|("favorites","pinned"|"alerts")=>v.is_boolean(),
  ("drawings","levels")=>v.as_array().is_some_and(|a|a.len()<=24&&a.iter().all(|v|number(v,-10.0,10.0))),
  ("drawings"|"favorites","market")=>v=="usd_m"||v=="spot",
  ("drawings"|"favorites","venue")=>v=="binance"||v=="coinbase",
  ("drawings"|"favorites","symbol")=>symbol(v),
  ("drawings","created")=>number(v,0.0,9e15),
  // An anti-abuse ceiling, deliberately not a copy of the client's UX rule. The client caps a
  // caption at 60 Swift Characters (grapheme clusters) because that is what still reads as one
  // line over the candles; this function can only count UTF-8 bytes, and the two do not convert
  // into each other. The old comment here claimed "240 bytes covers 60 of any of them" and was
  // simply wrong: eleven family emoji are eleven Characters and 275 bytes, so input the client
  // considered legal came back as a 400. Sixty skin-toned family emoji reach ~2.5 KB, which is
  // why 1 KB would not be enough either. 4 KB clears any realistic caption by a wide margin and
  // still stops someone pasting a novel; the per-field 64 KB rule in `Operation::validate` is
  // the real backstop. Whatever the client accepts, the server must be able to store.
  ("drawings","text")=>string(v,4096),
  ("favorites","groupId")=>string(v,100),
  ("favorites"|"groups","order")=>number(v,0.0,1e9),
  ("groups","name")=>string(v,100),
  ("groups","members")=>v.as_array().is_some_and(|a|a.len()<=2000&&a.iter().all(|v|string(v,100))),
  // ——— 提醒（方案文档 2.2） ———
  // 三种都真的在用（P3.1）：`drawing` / `price` 按线判，`reviewDue` 按 `dueAt` 判。
  ("alerts","kind")=>one_of(v,&["drawing","price","reviewDue"]),
  // 这个集合的 market 是整串 `binance/usd_m`（drawings / favorites 是 `usd_m` 加单独的
  // venue）。形状是文档定的，照抄，不要「统一」。
  ("alerts","market")=>v=="binance/usd_m"||v=="coinbase/spot",
  ("alerts","symbol")=>symbol(v),
  // 画线的同步对象 id 原样，和 `drawings` 的 id 同一套形态。
  ("alerts","drawingID")=>string(v,180),
  ("alerts","lines")=>lines(v),
  // `close`（收盘穿过）是第二种条件，见文档第 10 节。两侧评估器都判它
  // （`alerts::crossed_on_close` / 客户端 `AlertEvaluator.closeHit`）。
  ("alerts","condition")=>one_of(v,&["touch","close"]),
  ("alerts","status")=>one_of(v,&["active","fired","paused"]),
  ("alerts","once")=>v.is_boolean(),
  ("alerts","armedAt"|"firedAt"|"dueAt"|"created")=>number(v,0.0,9e15),
  ("alerts","firedPrice")=>number(v,-1e15,1e15),
  ("alerts","reviewID")=>string(v,100),
  // 通知标题是客户端生成的中文短句。和 `drawings.text` 同一档理由：这里数的是 UTF-8
  // 字节，客户端数的是字素，两者换算不了，所以给一个宽到不可能误伤的上限。
  ("alerts","title")=>string(v,1024),_=>false
 }
}
/// Folds the tombstones whose "no value" is actually a real value back into that value.
///
/// Today that is `drawings.text` alone. Clearing a note's caption is something the person did
/// on purpose, not "this drawing has no caption field": an old client encodes it by leaving the
/// key out, which the client's diff sends as `text: null`. Both spellings have to be accepted
/// (see the tombstone rule in `field`), and both have to land in storage as the same thing, or
/// every reader of this body — this server, the phone that syncs next, the one after it — has
/// to remember on its own that null means empty. Miss it once and the old caption is back on
/// screen. Runs after the field merge and before validation, so what is stored is already
/// canonical.
pub fn clear_tombstones(value:&mut Object) {
 if value.collection=="drawings" && value.body.get("text").is_some_and(Value::is_null) {
  value.body.insert("text".into(),Value::String(String::new()));
 }
}
pub fn identity(venue:&str,market:&str,symbol:&str)->bool {
 match (venue,market) {
  ("binance","usd_m") => symbol.bytes().all(|c|c.is_ascii_uppercase()||c.is_ascii_digit()) && QUOTES.iter().any(|q|symbol.ends_with(q)),
  ("coinbase","spot") => symbol.strip_suffix("-USD").is_some_and(|b|!b.is_empty() && b.bytes().all(|c|c.is_ascii_uppercase()||c.is_ascii_digit())),
  _ => false,
 }
}
pub fn object(value:&Object)->Result<()> {
 if value.deleted{return Ok(())}
 if value.body.iter().any(|(k,v)|!field(&value.collection,k,v)){return Err(ApiError::bad("invalid_sync_value"))}
 if value.collection=="favorites" {
  let part=|k:&str|value.body.get(k).and_then(Value::as_str).unwrap_or("");
  let (venue,market,symbol)=(part("venue"),part("market"),part("symbol"));
  if !identity(venue,market,symbol) || value.id!=format!("{venue}/{market}/{symbol}") {return Err(ApiError::bad("invalid_favorite_identity"))}
 }
 if value.collection=="drawings" {
  let kind=value.body.get("kind").and_then(Value::as_str).ok_or_else(||ApiError::bad("invalid_drawing"))?;
  let count=anchor_count(kind);
  if value.body.get("anchors").and_then(Value::as_array).is_none_or(|a|a.len()!=count){return Err(ApiError::bad("invalid_drawing"))}
  let symbol=value.body.get("symbol").and_then(Value::as_str).ok_or_else(||ApiError::bad("invalid_drawing"))?;
  let venue=value.body.get("venue").and_then(Value::as_str).unwrap_or("binance");
  let market=value.body.get("market").and_then(Value::as_str).unwrap_or("usd_m");
  if !identity(venue,market,symbol) || !value.id.starts_with(&format!("{venue}/{market}/{symbol}/")) {return Err(ApiError::bad("invalid_drawing_identity"))}
 }
 if value.collection=="alerts" {
  // 和 drawings 同一套 id 形态：binance/usd_m/<SYMBOL>/<alertID>。物化表按 symbol 订阅
  // 行情、按 id 回写状态，两者对不上就会订阅一个品种、推另一个品种的价。
  let kind=value.body.get("kind").and_then(Value::as_str).ok_or_else(||ApiError::bad("invalid_alert"))?;
  let symbol=value.body.get("symbol").and_then(Value::as_str).ok_or_else(||ApiError::bad("invalid_alert"))?;
  let market=value.body.get("market").and_then(Value::as_str).unwrap_or("");
  let pair=market.split_once('/').unwrap_or(("",""));
  if !identity(pair.0,pair.1,symbol) || !value.id.starts_with(&format!("{market}/{symbol}/")) {return Err(ApiError::bad("invalid_alert_identity"))}
  // 画线提醒必须指得出是哪条线：物化表存它，通知的深链也靠它跳回那条线上。
  if kind=="drawing" && value.body.get("drawingID").and_then(Value::as_str).is_none_or(str::is_empty) {
   return Err(ApiError::bad("invalid_alert"))
  }
  // 价格提醒（画线与裸价格）要有线可判：`lines` 字段本身允许空数组，是因为复盘到点那一种
  // 不看价、没有线；但一条没有线的价格提醒是永远不会响的死提醒。
  if matches!(kind,"drawing"|"price") && value.body.get("lines").and_then(Value::as_array).is_none_or(Vec::is_empty) {
   return Err(ApiError::bad("invalid_alert"))
  }
  // 复盘到点必须说得出「什么时候」和「哪一条」：评估器按 dueAt 判，推送的深链靠 reviewID。
  if kind=="reviewDue" && (value.body.get("dueAt").and_then(Value::as_f64).is_none()
   || value.body.get("reviewID").and_then(Value::as_str).is_none_or(str::is_empty)) {
   return Err(ApiError::bad("invalid_alert"))
  }
 }
 Ok(())
}

#[cfg(test)]
mod tests {
 use super::*;
 use serde_json::json;
 use std::collections::BTreeMap;
 #[test] fn venue_identity_is_not_a_route() {
  assert!(identity("binance","usd_m","BTCUSDT"));
  assert!(identity("coinbase","spot","BTC-USD"));
  for (v,m,s) in [("okx","usd_m","BTCUSDT"),("coinbase","usd_m","BTC-USD"),("binance","spot","BTCUSDT"),("coinbase","spot","BTC-USDC")] {assert!(!identity(v,m,s))}
 }
 #[test] fn spot_drawing_and_alert_roundtrip_without_prefix_collision() {
  let mut d=drawing("hline",1);
  d.id="coinbase/spot/BTC-USD/line-1".into();
  d.body.insert("venue".into(),json!("coinbase")); d.body.insert("market".into(),json!("spot")); d.body.insert("symbol".into(),json!("BTC-USD"));
  assert!(object(&d).is_ok());
  d.id="binance/usd_m/BTCUSDT/line-1".into(); assert!(object(&d).is_err());
  let mut a=alert(&[("market",json!("coinbase/spot")),("symbol",json!("BTC-USD"))]);
  a.id="coinbase/spot/BTC-USD/9F1E".into(); assert!(object(&a).is_ok());
  a.id="binance/usd_m/BTCUSDT/9F1E".into(); assert!(object(&a).is_err());
  let mut f=Object{collection:"favorites".into(),id:"coinbase/spot/BTC-USD".into(),body:BTreeMap::from([("venue".into(),json!("coinbase")),("market".into(),json!("spot")),("symbol".into(),json!("BTC-USD"))]),fields:BTreeMap::new(),revision:0,deleted:false,generation:0};
  assert!(object(&f).is_ok()); f.id="binance/usd_m/BTCUSDT".into(); assert!(object(&f).is_err());
 }
 fn drawing(kind:&str,anchors:usize)->crate::sync::Object {
  let points:Vec<_>=(0..anchors).map(|i|json!({"t":1_800_000_000_000i64+i as i64,"p":100.0+i as f64})).collect();
  let body:BTreeMap<String,Value>=[("kind",json!(kind)),("symbol",json!("BTCUSDT")),("market",json!("usd_m")),
   ("venue",json!("binance")),("anchors",json!(points))].into_iter().map(|(k,v)|(k.to_string(),v)).collect();
  crate::sync::Object{collection:"drawings".into(),id:format!("binance/usd_m/BTCUSDT/{kind}-1"),body,fields:BTreeMap::new(),revision:0,deleted:false,generation:0}
 }
 /// The same generated contract `sync`'s tests read, compiled in for the same reason: a file
 /// that is missing or unparseable is a compile error here, not a test that quietly passes.
 const CONTRACT:&str=include_str!("../contract/settings-fields.json");
 /// One array of strings out of the contract.
 fn contract_list(key:&str)->Vec<String> {
  let contract:Value=serde_json::from_str(CONTRACT)
   .expect("contract/settings-fields.json is not valid JSON; regenerate it with `make sync-contract`");
  contract[key].as_array()
   .unwrap_or_else(||panic!("contract/settings-fields.json has no `{key}` array. It is generated \
     from the client's enums, so the file is stale: run `make sync-contract` from the repo root."))
   .iter().map(|v|v.as_str().expect("contract list entries must be strings").to_string()).collect()
 }

 /// **The indicator vocabulary is the client's `IndicatorID`, in the client's order.**
 ///
 /// Both lists used to be hand-copied here with a length baked into the type, guarded by
 /// nothing: today's ten happen to match, and the next indicator would have matched only if
 /// whoever added it remembered this file. That is exactly how a161bb0 and 0f09f7e happened on
 /// the settings half.
 ///
 /// Order matters as much as membership. `overlays` accepts the main-chart half only and
 /// `subs` / `subInverted` the sub-panel half only, so an indicator that lands on the wrong
 /// side is refused — and a refused value fails the *whole* operation with a 400, which the
 /// client then queues behind forever.
 #[test] fn the_indicator_vocabulary_is_the_contract_one() {
  let all=contract_list("indicatorIDs");
  let overlays=contract_list("overlayIndicatorIDs");
  let subs=contract_list("subIndicatorIDs");
  let ours=|list:&[&str]|list.iter().map(|s|s.to_string()).collect::<Vec<_>>();
  let note="contract/settings-fields.json is generated from `IndicatorID`, so it is the side \
   that is right: edit the lists at the top of sync_validation.rs to match. Only if the \
   contract itself is stale — because someone edited IndicatorID without regenerating — run \
   `make sync-contract` from the repo root first.";
  assert_eq!(ours(OVERLAY_INDICATORS),overlays,
   "OVERLAY_INDICATORS drifted from the contract's `overlayIndicatorIDs`. {note}");
  assert_eq!(ours(SUB_INDICATORS),subs,
   "SUB_INDICATORS drifted from the contract's `subIndicatorIDs`. {note}");
  let joined:Vec<String>=OVERLAY_INDICATORS.iter().chain(SUB_INDICATORS).map(|s|s.to_string()).collect();
  assert_eq!(joined,all,
   "main chart + sub panels is not the contract's `indicatorIDs`, so the two halves here are \
    not the whole vocabulary — `params/<id>` and friends would refuse an indicator the client \
    really does send. {note}");
 }

 /// **Every drawing tool the client can draw with is a tool this server stores.**
 ///
 /// A kind missing from `KINDS` is not a cosmetic gap: `drawings.kind` refuses it, the whole
 /// operation 400s, and the line drawn with that tool never leaves the phone.
 #[test] fn every_drawing_tool_is_in_the_contract() {
  let want=contract_list("drawingKinds");
  let have:Vec<String>=KINDS.iter().map(|s|s.to_string()).collect();
  let missing:Vec<_>=want.iter().filter(|k|!have.contains(k)).collect();
  let extra:Vec<_>=have.iter().filter(|k|!want.contains(k)).collect();
  assert!(missing.is_empty()&&extra.is_empty(),
   "the drawing vocabulary drifted from contract/settings-fields.json.\n\
    in the contract (`Drawing.Kind`), missing from KINDS: {missing:?}\n\
    in KINDS, not in the contract:                        {extra:?}\n\
    The contract is generated from the client's `Drawing.Kind`, so it is the side that is \
    right: add each missing name to KINDS *and*, if the tool does not take two anchors, an arm \
    in `anchor_count` (the `_=>2` default would otherwise refuse every drawing of that kind). \
    Only if the contract itself is stale — because someone edited Drawing.Kind without \
    regenerating — run `make sync-contract` from the repo root first.");
 }

 #[test] fn every_tool_on_the_panel_can_be_stored() {
  for &kind in KINDS {assert!(field("drawings","kind",&json!(kind)),"{kind} should be a known tool")}
  assert!(!field("drawings","kind",&json!("telekinesis")));
  assert!(field("drawingPreferences","favorites",&json!(KINDS.to_vec())));
 }
 /// 「趋势线我要两端延伸」这一族的画法记忆跟着账号走：`variants/<面板那一格>` = 同族里的一种。
 /// 进了白名单却没有值规则就是毒丸（整条操作 400），所以名字与值两头都要认。
 #[test] fn the_remembered_drawing_method_travels_with_the_account() {
  for (head,chosen) in [("trend","extended"),("trend","ray"),("trend","arrowLine"),("hline","hray"),("vline","crossLine")] {
   assert!(field("drawingPreferences",&format!("variants/{head}"),&json!(chosen)),"variants/{head}={chosen} should be accepted");
  }
  // 用户换回面板那一格本身（线段）也是一个值；清掉走 null 墓碑。
  assert!(field("drawingPreferences","variants/trend",&json!("trend")));
  assert!(field("drawingPreferences","variants/trend",&json!(null)));
  for bad in [json!("telekinesis"),json!(1),json!(true),json!({"kind":"extended"})] {
   assert!(!field("drawingPreferences","variants/trend",&bad),"{bad} should be refused");
  }
  assert!(!field("drawingPreferences","variants/telekinesis",&json!("trend")));
  assert!(!field("drawingPreferences","variants",&json!({"trend":"extended"})),"only the flattened path is a field");
  assert!(!field("drawingPreferences","variants/trend/x",&json!("extended")));
 }
 /// A seven-point head and shoulders used to fail the 1..=3 anchor rule outright.
 #[test] fn a_many_pointed_pattern_keeps_all_its_anchors() {
  for (kind,count) in [("hline",1),("trend",2),("channel",3),("abcd",4),("xabcd",5),("elliottImpulse",6),("headShoulders",7),
                       ("anchoredVWAP",1),("fixedVolumeProfile",2)] {
   assert_eq!(anchor_count(kind),count);
   object(&drawing(kind,count)).unwrap_or_else(|_|panic!("{kind} with {count} anchors should be valid"));
   assert!(object(&drawing(kind,count+1)).is_err(),"{kind} with {} anchors should be refused",count+1);
  }
 }
 #[test] fn a_usdc_margined_contract_is_a_real_symbol() {
  for good in ["BTCUSDT","1000BONKUSDC","ETHFDUSD"] {assert!(field("favorites","symbol",&json!(good)),"{good} should be accepted")}
  for bad in ["btcusdt","BTC-USDT","BTCEUR",""] {assert!(!field("favorites","symbol",&json!(bad)),"{bad} should be refused")}
 }
 #[test] fn a_caption_travels_with_its_note() {
  assert!(field("drawings","text",&json!("顶背离")));
  assert!(!field("drawings","text",&json!("x".repeat(4097))));
 }
 /// Erasing a caption is an ordinary edit, and it arrives in two spellings.
 ///
 /// A current client sends `""` (`Drawing.encode` always writes `text` for the tools that
 /// carry one); a client already installed on a phone omits the key, which its diff turns into
 /// `text: null`. Refusing either one 400s the whole operation, the client quarantines it, and
 /// the caption the person deleted comes back from the cloud.
 #[test] fn clearing_a_caption_is_accepted_in_both_spellings() {
  assert!(field("drawings","text",&json!("")),"an empty caption is a real value");
  assert!(field("drawings","text",&Value::Null),"an old client still clears it with a null");
  // The null is not left lying in storage: it is folded into the same empty string, so nobody
  // downstream has to remember that null also means empty.
  let mut note=drawing("note",1);
  note.body.insert("text".into(),Value::Null);
  clear_tombstones(&mut note);
  assert_eq!(note.body.get("text"),Some(&json!("")));
  object(&note).expect("a note whose caption was cleared is still a valid drawing");
  // Nothing else is touched by the fold.
  let mut kept=drawing("note",1);
  kept.body.insert("text".into(),json!("顶背离"));
  clear_tombstones(&mut kept);
  assert_eq!(kept.body.get("text"),Some(&json!("顶背离")));
 }
 /// The client's limit is 60 grapheme clusters; this one is bytes, and it must be loose enough
 /// that everything the client calls legal fits. Eleven family emoji used to blow past the old
 /// 240-byte line while being only eleven characters on screen.
 #[test] fn sixty_characters_of_anything_still_fit() {
  let family="\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}";      // 25 bytes
  let toned="\u{1F468}\u{1F3FB}\u{200D}\u{1F469}\u{1F3FB}\u{200D}\u{1F467}\u{1F3FB}\u{200D}\u{1F466}\u{1F3FB}"; // 41 bytes
  assert!(field("drawings","text",&json!(family.repeat(11))),"eleven family emoji are eleven characters");
  for caption in [family.repeat(60),toned.repeat(60),"顶".repeat(60),"x".repeat(60)] {
   assert!(field("drawings","text",&json!(caption)),"{} bytes of a 60-character caption must fit",caption.len());
  }
 }
 #[test] fn the_new_settings_carry_their_own_limits() {
  assert!(field("settings","barSpacing",&json!(4.0))&&!field("settings","barSpacing",&json!(1.5))&&!field("settings","barSpacing",&json!(41.0)));
  assert!(field("settings","interval",&json!("1M"))&&!field("settings","interval",&json!("1x")));
  assert!(field("settings","subInverted",&json!(["VOL","MACD"]))&&!field("settings","subInverted",&json!(["MA"])));
  assert!(field("settings","quickIntervals",&json!(["1m","3m","5m","15m","30m","1h","2h","4h","6h","12h"])));
  assert!(field("settings","skin",&json!("classic"))&&field("settings","routePolicy",&json!("gateway")));
  assert!(field("settings","favoritesSort",&json!("volume"))&&!field("settings","favoritesSort",&json!("marketCap")));
  assert!(field("settings","favoritesSort",&json!("alert")),"客户端多了「离提醒线最近」这一档，白名单要跟着加");
  assert!(field("settings","sectorWindow",&json!("d20"))&&field("settings","sectorMarket",&json!("us"))&&field("settings","sectorSort",&json!("change")));
  assert!(field("settings","reviewSearchScope",&json!("private"))&&!field("settings","reviewSearchScope",&json!("world")));
  assert!(field("settings","lastDrawTool",&json!(""))&&field("settings","lastDrawTool",&json!("gannFan"))&&!field("settings","lastDrawTool",&json!("laser")));
  assert!(field("settings","drawToolGroup",&json!("斐波那契"))&&!field("settings","drawToolGroup",&json!("x".repeat(129))));
  assert!(field("settings","favoritesGroup",&json!("F1E0A6C2-0000-4000-8000-000000000001"))&&!field("settings","favoritesGroup",&json!("x".repeat(129))));
  assert!(field("settings","replaySpeed",&json!(4))&&!field("settings","replaySpeed",&json!(8)));
  assert!(field("settings","favoritesExpanded",&json!(["BTCUSDT"]))&&!field("settings","favoritesExpanded",&json!(["btc"])));
  for flag in ["mainInverted","keepAwake","favoritesAscending","favoritesAmount","favoritesSparkline"] {
   assert!(field("settings",flag,&json!(true))&&!field("settings",flag,&json!(1)),"{flag} is a boolean");
  }
 }

 /// P2.17 加了第三种画法「收盘价」（`CandleKind.line`，rawValue `line`）。`candleKind` 在这里
 /// 只按长度收（`string(v,64)`），三个值都得过——少认一个，带它的整条 settings 操作就是 400，
 /// 那台手机的同步队列会被堵死。
 #[test] fn every_candle_kind_the_panel_offers_is_accepted() {
  for kind in ["candle","heikin","line"] {
   assert!(field("settings","candleKind",&json!(kind)),"candleKind {kind} must be accepted");
  }
  assert!(!field("settings","candleKind",&json!(1)),"candleKind is a string");
 }

 fn alert(extra:&[(&str,Value)])->crate::sync::Object {
  let mut body:BTreeMap<String,Value>=[("kind",json!("drawing")),("symbol",json!("BTCUSDT")),("market",json!("binance/usd_m")),
   ("drawingID",json!("binance/usd_m/BTCUSDT/trend-1")),("condition",json!("touch")),("status",json!("active")),
   ("once",json!(true)),("armedAt",json!(1_800_000_000_000i64)),("created",json!(1_800_000_000_000i64)),
   ("title",json!("BTC 触到你画的趋势线")),
   ("lines",json!([{"points":[{"t":1_800_000_000_000i64,"p":63_000.0},{"t":1_800_003_600_000i64,"p":64_000.0}],"extendLeft":false,"extendRight":true}]))
  ].into_iter().map(|(k,v)|(k.to_string(),v)).collect();
  for (k,v) in extra {body.insert((*k).to_string(),v.clone());}
  crate::sync::Object{collection:"alerts".into(),id:"binance/usd_m/BTCUSDT/9F1E".into(),body,fields:BTreeMap::new(),revision:0,deleted:false,generation:0}
 }

 /// **表 2.2 的每一个字段都有值规则，而且认的是文档写的那些值。**
 ///
 /// 白名单上有名字、这里没规则，等于给整个集合下毒：`_=>false` 会让带这个字段的**整条**
 /// 操作 400，客户端把它隔离起来，后面所有提醒排在它后面（commit a161bb0 的原样重演）。
 #[test] fn an_alert_carries_every_field_the_document_names() {
  for kind in ["drawing","price","reviewDue"] {assert!(field("alerts","kind",&json!(kind)),"{kind} is a real alert kind")}
  assert!(!field("alerts","kind",&json!("telepathy")));
  // market 在这个集合里是整串，不是 drawings 的那个 `usd_m`。
  assert!(field("alerts","market",&json!("binance/usd_m"))&&!field("alerts","market",&json!("usd_m")));
  assert!(field("alerts","symbol",&json!("BTCUSDT"))&&!field("alerts","symbol",&json!("btcusdt")));
  assert!(field("alerts","drawingID",&json!("binance/usd_m/BTCUSDT/trend-1")));
  assert!(field("alerts","status",&json!("active"))&&field("alerts","status",&json!("fired"))&&field("alerts","status",&json!("paused")));
  assert!(!field("alerts","status",&json!("armed")));
  assert!(field("alerts","once",&json!(true))&&!field("alerts","once",&json!(1)));
  for key in ["armedAt","firedAt","dueAt","created"] {
   assert!(field("alerts",key,&json!(1_800_000_000_000i64)),"{key} is a millisecond stamp");
   assert!(!field("alerts",key,&json!(-1)),"{key} cannot be before the epoch");
  }
  assert!(field("alerts","firedPrice",&json!(63_120.5))&&!field("alerts","firedPrice",&json!("63120.5")));
  assert!(field("alerts","reviewID",&json!("9F1E"))&&field("alerts","title",&json!("BTC 触到你画的趋势线")));
  assert!(!field("alerts","title",&json!("x".repeat(1025))));
 }

 /// **`close` 是协议里的合法值，而且现在真的有人评估它。**
 ///
 /// 文档第 10 节把「收盘确认」定成第二种 condition，提醒列表里可以切。这一层的工作是
 /// 认不认：拒收会让客户端那条 op 永远推不上去。曾经有一段时间它只到这儿为止——白名单
 /// 放行、界面能选、`alerts::load` 却带着一条 TODO 静默跳过，于是「收盘穿过后」是一条
 /// 用户走得进去、永远走不出来的死路。现在两侧都判它：服务端 `alerts::crossed_on_close`、
 /// 客户端 `AlertEvaluator.closeHit`。**改这条测试之前先确认那两处还在。**
 #[test] fn a_close_confirmation_alert_is_accepted_and_evaluated() {
  assert!(field("alerts","condition",&json!("touch")));
  assert!(field("alerts","condition",&json!("close")));
  assert!(!field("alerts","condition",&json!("wick")));
  object(&alert(&[("condition",json!("close"))])).expect("a close-confirmation alert is storable");
  // 存得下只是一半。另一半是评估器认不认这个字符串——白名单放行的 `"close"` 必须
  // 正好是评估器路由到收盘穿过的那个 `"close"`。它要是退回 `Touch`，「收盘穿过后」
  // 就悄悄变回「触碰时」，而且没有任何迹象。
  assert_eq!(crate::alerts::Condition::of("close"),crate::alerts::Condition::Close,
   "白名单认的 close 必须就是评估器判收盘穿过的那个 close");
 }

 /// 几何的形状：`[{points:[{t,p}],extendLeft,extendRight}]`，数字必须有限。
 ///
 /// 服务端不认识画线的种类，只认这一种形状——所以这条规则就是它对几何的全部理解，
 /// 松一点点就会有一条 NaN 的线存进 jsonb，之后谁也看不出哪儿不对。
 #[test] fn the_geometry_is_polylines_of_finite_numbers() {
  let good=json!([{"points":[{"t":1.0,"p":2.0},{"t":3.0,"p":4.0}],"extendLeft":true,"extendRight":false}]);
  assert!(field("alerts","lines",&good));
  // 一个点也是一条线：水平线摊平之后就是「一个价 + 两端延伸」。
  assert!(field("alerts","lines",&json!([{"points":[{"t":1.0,"p":2.0}],"extendLeft":true,"extendRight":true}])));
  // 一条提醒可以带好几条线（矩形两条边、斐波那契每一级一条）。
  assert!(field("alerts","lines",&json!([
   {"points":[{"t":1.0,"p":2.0},{"t":3.0,"p":4.0}],"extendLeft":false,"extendRight":false},
   {"points":[{"t":1.0,"p":9.0},{"t":3.0,"p":9.0}],"extendLeft":false,"extendRight":false}])));
  // 空数组这一层放行：复盘到点那一种没有线。有没有线该不该空，交给 `object` 按种类判。
  assert!(field("alerts","lines",&json!([])));
  for bad in [
   json!([{"points":[],"extendLeft":false,"extendRight":false}]),
   json!([{"points":[{"t":1.0,"p":2.0}],"extendLeft":false}]),
   json!([{"points":[{"t":1.0,"p":2.0}],"extendLeft":"yes","extendRight":false}]),
   json!([{"points":[{"t":1.0,"p":2.0,"x":3.0}],"extendLeft":false,"extendRight":false}]),
   json!([{"points":[{"t":-1.0,"p":2.0}],"extendLeft":false,"extendRight":false}]),
   json!([{"points":[{"t":1.0,"p":1e18}],"extendLeft":false,"extendRight":false}]),
   json!("a line"),
  ] {assert!(!field("alerts","lines",&bad),"{bad} is not a usable set of polylines")}
 }

 /// 对象身份：id 必须和它自己的 symbol 对得上，画线提醒必须指得出是哪条线。
 ///
 /// 订阅按 symbol、回写按 id，两者对不上就会订阅一个品种、推另一个品种的价。
 #[test] fn an_alert_must_agree_with_its_own_identity() {
  object(&alert(&[])).expect("a well-formed drawing alert");
  let mut wrong=alert(&[]);
  wrong.id="binance/usd_m/ETHUSDT/9F1E".into();
  assert!(object(&wrong).is_err(),"the id names a different symbol than the body does");
  let mut orphan=alert(&[]);
  orphan.body.remove("drawingID");
  assert!(object(&orphan).is_err(),"a drawing alert that names no drawing cannot deep-link anywhere");
  // 复盘待办的提醒不指画线，它整条链路都在客户端本地通知里。
  let due=alert(&[("kind",json!("reviewDue")),("dueAt",json!(1_800_000_000_000i64)),("reviewID",json!("9F1E"))]);
  let mut due=due;due.body.remove("drawingID");
  object(&due).expect("a review reminder needs no drawing");
 }

 /// 三种提醒各有各的必填：价格类（画线、裸价格）必须有线，复盘到点必须有 `dueAt` 与 `reviewID`。
 ///
 /// 裸价格提醒不指画线（没有 `drawingID`），复盘到点没有线——少了这一层，一条没有线的价格
 /// 提醒会存进去、永远不会响；一条没有 `dueAt` 的到点提醒永远不会到点。
 #[test] fn each_alert_kind_carries_what_it_is_judged_by() {
  let mut price=alert(&[("kind",json!("price")),("title",json!("BTC 涨到 70,000"))]);
  price.body.remove("drawingID");
  object(&price).expect("a price alert needs no drawing");
  let mut lineless=price.clone();
  lineless.body.insert("lines".into(),json!([]));
  assert!(object(&lineless).is_err(),"a price alert without a line can never fire");
  let mut drawing_lineless=alert(&[]);
  drawing_lineless.body.insert("lines".into(),json!([]));
  assert!(object(&drawing_lineless).is_err(),"neither can a drawing alert");

  let mut due=alert(&[("kind",json!("reviewDue")),("dueAt",json!(1_800_000_000_000i64)),("reviewID",json!("7C0A")),("lines",json!([]))]);
  due.body.remove("drawingID");
  object(&due).expect("a review reminder has no line and needs none");
  let mut undated=due.clone();
  undated.body.remove("dueAt");
  assert!(object(&undated).is_err(),"a review reminder without dueAt never comes due");
  let mut anonymous=due.clone();
  anonymous.body.insert("reviewID".into(),json!(""));
  assert!(object(&anonymous).is_err(),"a review reminder must name its record");
 }

 /// 「再次提醒」把一条已触发的提醒重新武装：firedAt / firedPrice 被清掉。
 ///
 /// 客户端的 diff 把「这次不写这个 key」发成 null。拒收那个 null 就等于整条 op 400，
 /// 于是「再次提醒」这个按钮永远按不动——`drawings.text` 当年就是这么坏的。
 #[test] fn re_arming_an_alert_clears_the_fired_marks() {
  for key in ["firedAt","firedPrice","drawingID","dueAt","reviewID"] {
   assert!(field("alerts",key,&Value::Null),"{key} must be clearable");
  }
  assert!(!field("alerts","status",&Value::Null),"status always has a value");
  assert!(!field("alerts","lines",&Value::Null),"geometry is never a tombstone");
 }
 #[test] fn compare_symbols_are_bounded_distinct_full_instrument_keys() {
  assert!(crate::sync::SETTINGS_FIELDS.contains(&"compareSymbols"));
  for good in [json!([]), json!(["binance/usd_m/ETHUSDT", "coinbase/spot/BTC-USD", "future/spot/ABC"])] {
   assert!(field("settings","compareSymbols",&good));
  }
  for bad in [
   json!(null), json!("binance/usd_m/ETHUSDT"), json!([1]), json!(["ETHUSDT"]),
   json!(["binance/usd_m/ethusdt"]), json!(["binance//ETHUSDT"]),
   json!(["binance/usd_m/ETHUSDT/x"]), json!([" binance/usd_m/ETHUSDT"]),
   json!(["binance/usd_m/ETHUSDT", "binance/usd_m/ETHUSDT"]),
   json!(["binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT", "binance/usd_m/DOGEUSDT", "binance/usd_m/XRPUSDT"])
  ] { assert!(!field("settings","compareSymbols",&bad), "{bad}"); }
 }
}
