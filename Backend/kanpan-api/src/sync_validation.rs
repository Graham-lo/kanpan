//! Mirrors the native wire types at the boundary, before a merged value can reach another device.
use crate::{error::{ApiError,Result},sync::Object};
use serde_json::Value;
const INDICATORS:[&str;10]=["MA","EMA","BOLL","VOL","MACD","RSI","KDJ","SRSI","ATR","OI"];
// `Drawing.Kind` in full (KanpanCore/Drawing/Drawing.swift:22). The first ten are the
// original tools; the rest arrived with the TradingView-aligned panel and must be listed
// here or the drawing that uses one can never leave the phone.
const KINDS:[&str;38]=[
 "hline","trend","ray","hray","extended","vline","rectangle","channel","fibonacci","measure",
 "position","regression","fibExtension","priceRange","dateRange","note","crossLine","arrowLine",
 "pitchfork","fibChannel","ellipse","triangle","curve","datePriceRange","fibTimeZone","fibFan",
 "gannBox","gannFan","xabcd","abcd","headShoulders","elliottImpulse","elliottCorrection",
 "callout","priceLabel","flag","markerUp","markerDown",
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
fn symbol(v:&Value)->bool {v.as_str().is_some_and(|s|s.len()<=40&&QUOTES.iter().any(|q|s.ends_with(q))&&s.bytes().all(|c|c.is_ascii_uppercase()||c.is_ascii_digit()))}
/// How many anchors a finished drawing of this kind carries: `Drawing.Kind.pointCount`.
fn anchor_count(kind:&str)->usize {
 match kind {
  "hline"|"vline"|"hray"|"note"|"crossLine"|"priceLabel"|"flag"|"markerUp"|"markerDown"=>1,
  "channel"|"regression"|"position"|"fibExtension"|"pitchfork"|"fibChannel"|"triangle"|"curve"=>3,
  "abcd"|"elliottCorrection"=>4,"xabcd"=>5,"elliottImpulse"=>6,"headShoulders"=>7,_=>2
 }
}
fn style(v:&Value)->bool {v.as_object().is_some_and(|o|o.iter().all(|(k,v)|field("drawings",k,v))&&o.contains_key("lineWidth")&&o.contains_key("dash")&&o.contains_key("filled")&&o.contains_key("levels"))}
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
 if v.is_null(){return p.len()==1&&matches!(path,"color"|"groupId"|"text") || collection=="settings"&&p.len()>=2 || collection=="drawingPreferences"&&p.len()==2}
 if collection=="settings" {
  if p.len()>1 {
   if !INDICATORS.contains(&p[1]) {return false}
   return match p[0] {
    "params"=>p.len()==2&&integers(v,20,1,400),
    "hiddenOutputs"=>p.len()==2&&integers(v,21,0,20),
    "indicatorColors"=>p.len()==3&&p[2].parse::<u8>().is_ok_and(|n|n<=20)&&color(v),
    "subHeightOverrides"=>p.len()==2&&number(v,0.25,5.0),
    "subHeights"=>p.len()==2&&v.as_str().is_some_and(|s|["small","medium","large"].contains(&s)),_=>false
   }
  }
  return match path {
   "overlays"=>names(v,3,&INDICATORS[..3]),"subs"=>names(v,7,&INDICATORS[3..]),
   // `subInverted` is a set of sub-panel ids, same vocabulary as `subs`.
   "subInverted"=>names(v,7,&INDICATORS[3..]),
   "quickIntervals"=>names(v,10,&INTERVALS),"interval"=>one_of(v,&INTERVALS),
   "rsiRange"=>v.as_array().is_some_and(|a|a.len()==2&&number(&a[0],0.0,100.0)&&number(&a[1],0.0,100.0)&&a[0].as_f64()<a[1].as_f64()),
   "portraitHeight"=>number(v,0.1,1.0),
   // `Prefs.clampSpacing` never stores anything outside AICoinBehavior's 1.6…40pt.
   "barSpacing"=>number(v,1.6,40.0),
   // Only 1 / 2 / 4, per `Prefs.clampSpeed`.
   "replaySpeed"=>v.as_i64().is_some_and(|n|matches!(n,1|2|4)),
   "skin"=>one_of(v,&["sage","terra","classic"]),
   "routePolicy"=>one_of(v,&["direct","gateway"]),
   "favoritesSort"=>one_of(v,&["custom","name","price","change","volume"]),
   "sectorMarket"=>one_of(v,&["crypto","us"]),
   "sectorWindow"=>one_of(v,&["today","d5","d20"]),
   "sectorSort"=>one_of(v,&["change","volume"]),
   "reviewSearchScope"=>one_of(v,&["history","private"]),
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
   "favoritesExpanded"=>v.as_array().is_some_and(|a|a.len()<=500&&a.iter().all(symbol)),
   "ambientTheme"|"redUp"|"magnet"|"countdown"|"lastLine"|"sinceChange"|"showDrawings"|"allowMainInversion"|"allowSubInversion"|"adaptiveIndicators"|"compactValues"
    |"mainInverted"|"keepAwake"|"favoritesAscending"|"favoritesAmount"|"favoritesSparkline"=>v.is_boolean(),
   "theme"|"styleID"|"priceMode"|"timeZone"|"candleKind"|"gridChoice"|"bodyChoice"|"viewAnchor"|"priceBias"|"dataDisplay"|"crossPrice"|"changeBasis"=>string(v,64),_=>false
  }
 }
 if collection=="drawingPreferences" {return match path {"favorites"=>names(v,KINDS.len(),&KINDS),"magnet"|"continuous"=>v.is_boolean(),_=>p.len()==2&&p[0]=="styles"&&KINDS.contains(&p[1])&&style(v)}}
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
  ("drawings"|"favorites","market")=>v=="usd_m",
  ("drawings"|"favorites","venue")=>v=="binance",
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
  ("groups","members")=>v.as_array().is_some_and(|a|a.len()<=2000&&a.iter().all(|v|string(v,100))),_=>false
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
pub fn object(value:&Object)->Result<()> {
 if value.deleted{return Ok(())}
 if value.body.iter().any(|(k,v)|!field(&value.collection,k,v)){return Err(ApiError::bad("invalid_sync_value"))}
 if value.collection=="drawings" {
  let kind=value.body.get("kind").and_then(Value::as_str).ok_or_else(||ApiError::bad("invalid_drawing"))?;
  let count=anchor_count(kind);
  if value.body.get("anchors").and_then(Value::as_array).is_none_or(|a|a.len()!=count){return Err(ApiError::bad("invalid_drawing"))}
  let symbol=value.body.get("symbol").and_then(Value::as_str).ok_or_else(||ApiError::bad("invalid_drawing"))?;
  if !value.id.starts_with(&format!("binance/usd_m/{symbol}/")) {return Err(ApiError::bad("invalid_drawing_identity"))}
 }
 Ok(())
}

#[cfg(test)]
mod tests {
 use super::*;
 use serde_json::json;
 use std::collections::BTreeMap;
 fn drawing(kind:&str,anchors:usize)->crate::sync::Object {
  let points:Vec<_>=(0..anchors).map(|i|json!({"t":1_800_000_000_000i64+i as i64,"p":100.0+i as f64})).collect();
  let body:BTreeMap<String,Value>=[("kind",json!(kind)),("symbol",json!("BTCUSDT")),("market",json!("usd_m")),
   ("venue",json!("binance")),("anchors",json!(points))].into_iter().map(|(k,v)|(k.to_string(),v)).collect();
  crate::sync::Object{collection:"drawings".into(),id:format!("binance/usd_m/BTCUSDT/{kind}-1"),body,fields:BTreeMap::new(),revision:0,deleted:false,generation:0}
 }
 #[test] fn every_tool_on_the_panel_can_be_stored() {
  for kind in KINDS {assert!(field("drawings","kind",&json!(kind)),"{kind} should be a known tool")}
  assert!(!field("drawings","kind",&json!("telekinesis")));
  assert!(field("drawingPreferences","favorites",&json!(KINDS.to_vec())));
 }
 /// A seven-point head and shoulders used to fail the 1..=3 anchor rule outright.
 #[test] fn a_many_pointed_pattern_keeps_all_its_anchors() {
  for (kind,count) in [("hline",1),("trend",2),("channel",3),("abcd",4),("xabcd",5),("elliottImpulse",6),("headShoulders",7)] {
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
}
