//! Mirrors the native wire types at the boundary, before a merged value can reach another device.
use crate::{error::{ApiError,Result},sync::Object};
use serde_json::Value;
const INDICATORS:[&str;10]=["MA","EMA","BOLL","VOL","MACD","RSI","KDJ","SRSI","ATR","OI"];
const KINDS:[&str;10]=["hline","trend","ray","hray","extended","vline","rectangle","channel","fibonacci","measure"];
fn color(v:&Value)->bool {v.as_object().is_some_and(|o|o.len()==1)&&v["value"].as_str().is_some_and(|s|matches!(s.len(),7|9)&&s.starts_with('#')&&s[1..].bytes().all(|c|c.is_ascii_hexdigit()))}
fn number(v:&Value,lo:f64,hi:f64)->bool {v.as_f64().is_some_and(|v|v.is_finite()&&v>=lo&&v<=hi)}
fn integers(v:&Value,count:usize,lo:i64,hi:i64)->bool {v.as_array().is_some_and(|a|a.len()<=count&&a.iter().all(|v|v.as_i64().is_some_and(|n|n>=lo&&n<=hi)))}
fn names(v:&Value,count:usize,names:&[&str])->bool {v.as_array().is_some_and(|a|a.len()<=count&&a.iter().all(|v|v.as_str().is_some_and(|s|names.contains(&s))))}
fn string(v:&Value,limit:usize)->bool {v.as_str().is_some_and(|s|s.len()<=limit)}
fn style(v:&Value)->bool {v.as_object().is_some_and(|o|o.iter().all(|(k,v)|field("drawings",k,v))&&o.contains_key("lineWidth")&&o.contains_key("dash")&&o.contains_key("filled")&&o.contains_key("levels"))}
pub fn field(collection:&str,path:&str,v:&Value)->bool {
 let p:Vec<_>=path.split('/').collect();
 // A null is a field tombstone; required drawing fields are checked again after merging.
 if v.is_null(){return p.len()==1&&matches!(path,"color"|"groupId") || collection=="settings"&&p.len()>=2 || collection=="drawingPreferences"&&p.len()==2}
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
   "quickIntervals"=>names(v,8,&["1m","3m","5m","15m","30m","1h","2h","4h","6h","8h","12h","1d","3d","1w","1M","1y"]),
   "rsiRange"=>v.as_array().is_some_and(|a|a.len()==2&&number(&a[0],0.0,100.0)&&number(&a[1],0.0,100.0)&&a[0].as_f64()<a[1].as_f64()),
   "portraitHeight"=>number(v,0.1,1.0),
   "ambientTheme"|"redUp"|"magnet"|"countdown"|"lastLine"|"sinceChange"|"showDrawings"|"allowMainInversion"|"allowSubInversion"|"adaptiveIndicators"|"compactValues"=>v.is_boolean(),
   "theme"|"styleID"|"priceMode"|"timeZone"|"candleKind"|"gridChoice"|"bodyChoice"|"viewAnchor"|"priceBias"|"dataDisplay"|"crossPrice"|"changeBasis"=>string(v,64),_=>false
  }
 }
 if collection=="drawingPreferences" {return match path {"favorites"=>names(v,10,&KINDS),"magnet"|"continuous"=>v.is_boolean(),_=>p.len()==2&&p[0]=="styles"&&KINDS.contains(&p[1])&&style(v)}}
 if p.len()!=1 {return false}
 match (collection,path) {
  ("drawings","kind")=>v.as_str().is_some_and(|s|KINDS.contains(&s)),
  ("drawings","anchors")=>v.as_array().is_some_and(|a|(1..=3).contains(&a.len())&&a.iter().all(|p|p.as_object().is_some_and(|o|o.len()==2)&&number(&p["t"],0.0,9e15)&&number(&p["p"],-1e15,1e15))),
  ("drawings","color")=>color(v),
  ("drawings","lineWidth")=>number(v,0.5,6.0),
  ("drawings","dash")=>v.as_str().is_some_and(|s|["solid","dashed","dotted"].contains(&s)),
  ("drawings","filled"|"locked"|"hidden")|("favorites","pinned"|"alerts")=>v.is_boolean(),
  ("drawings","levels")=>v.as_array().is_some_and(|a|a.len()<=24&&a.iter().all(|v|number(v,-10.0,10.0))),
  ("drawings"|"favorites","market")=>v=="usd_m",
  ("drawings"|"favorites","venue")=>v=="binance",
  ("drawings"|"favorites","symbol")=>v.as_str().is_some_and(|s|s.len()<=40&&s.ends_with("USDT")&&s.bytes().all(|c|c.is_ascii_uppercase()||c.is_ascii_digit())),
  ("drawings","created")=>number(v,0.0,9e15),
  ("favorites","groupId")=>string(v,100),
  ("favorites"|"groups","order")=>number(v,0.0,1e9),
  ("groups","name")=>string(v,100),
  ("groups","members")=>v.as_array().is_some_and(|a|a.len()<=2000&&a.iter().all(|v|string(v,100))),_=>false
 }
}
pub fn object(value:&Object)->Result<()> {
 if value.deleted{return Ok(())}
 if value.body.iter().any(|(k,v)|!field(&value.collection,k,v)){return Err(ApiError::bad("invalid_sync_value"))}
 if value.collection=="drawings" {
  let kind=value.body.get("kind").and_then(Value::as_str).ok_or_else(||ApiError::bad("invalid_drawing"))?;
  let count=match kind {"hline"|"vline"|"hray"=>1,"channel"=>3,_=>2};
  if value.body.get("anchors").and_then(Value::as_array).is_none_or(|a|a.len()!=count){return Err(ApiError::bad("invalid_drawing"))}
  let symbol=value.body.get("symbol").and_then(Value::as_str).ok_or_else(||ApiError::bad("invalid_drawing"))?;
  if !value.id.starts_with(&format!("binance/usd_m/{symbol}/")) {return Err(ApiError::bad("invalid_drawing_identity"))}
 }
 Ok(())
}
