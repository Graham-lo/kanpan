//! 首页异动一列（原型 §12 `highlights/board`）：自选（客户端带上）∪ 热点层，每只取它此刻权重最高的一条要点代表它。
//!
//! 只读每分钟算好的那一份（[`super::snapshot`]），不在这里起跟：登录用户的自选由服务端的自选层补跟，热点层本来就在跟；
//! 没在跟或这一分钟没有要点的不出行。强度三格按这一份答复里各行权重的三分位点亮（最强的三分之一为 3）。
use super::state::Snap;
use super::instruments;
use serde_json::{Value,json};
use std::collections::HashSet;
use std::sync::Arc;

pub(in super::super) const PATH:&str="/v1/market/orderflow/highlights/board";
/// 客户端最多带多少只自选（自选层每人 30 只，留余量）。
pub(super) const MAX_BASES:usize=60;

/// 解析 `bases=BTC,ETH,…`：去空白、转大写、去重、丢掉不合法的，最多 [`MAX_BASES`] 只，排好序（做缓存键）。
pub(super) fn parse(bases:Option<&str>)->Vec<String> {
 let mut seen=HashSet::new();
 let mut out:Vec<String>=bases.unwrap_or("").split(',').map(|b|b.trim().to_ascii_uppercase())
  .filter(|b|!b.is_empty()&&instruments::valid_base(b)&&seen.insert(b.clone())).take(MAX_BASES).collect();
 out.sort();
 out
}

/// 拼一份答复：`favorites` 是客户端带的自选，`hot` 是热点层名单，`snap` 取一只此刻的那一份。
pub(super) fn answer(favorites:&[String],hot:&[String],snap:impl Fn(&str)->Option<Arc<Snap>>,now:i64)->Value {
 let fav:HashSet<&str>=favorites.iter().map(String::as_str).collect();
 let mut seen=HashSet::new();
 let mut rows:Vec<(f64,Value)>=Vec::new();
 for base in favorites.iter().chain(hot.iter()) {
  if !seen.insert(base.as_str()) {continue}
  let Some(s)=snap(base) else {continue};
  let Some(item)=s.board.as_ref() else {continue};
  if s.json.get("tracked")!=Some(&json!(true)) {continue}
  rows.push((item.weight,json!({"base":base,"favorite":fav.contains(base.as_str()),"count":item.count,"cat":item.cat,"tier":0,
   "top":item.top,"price":s.price,"changePct":s.change_pct,"atMs":item.at})));
 }
 rows.sort_by(|a,b|b.0.total_cmp(&a.0).then_with(||a.1["base"].as_str().cmp(&b.1["base"].as_str())));
 let n=rows.len();
 let rows:Vec<Value>=rows.into_iter().enumerate().map(|(i,(_,mut v))|{v["tier"]=json!(tier(i,n));v}).collect();
 json!({"generatedAtMs":now,"rows":rows})
}

/// 按权重从高到低第 `i` 行（共 `n` 行）的强度：前三分之一 3、中间 2、后三分之一 1。
fn tier(i:usize,n:usize)->u8 {if n==0 {return 1} 3-((3*i)/n).min(2) as u8}

#[cfg(test)]
mod tests {
 use super::*;
 use super::super::state::BoardItem;

 fn snap(weight:f64,tracked:bool)->Arc<Snap> {
  Arc::new(Snap{json:json!({"tracked":tracked}),board:Some(BoardItem{count:2,cat:"book",top:json!({"kind":"event","t":"wallEaten"}),weight,at:7}),price:Some(1.5),change_pct:Some(-2.0)})
 }

 #[test]
 fn parse_dedupes_uppercases_and_caps() {
  assert_eq!(parse(Some(" eth,BTC,eth,,bad base,SOL ")),vec!["BTC","ETH","SOL"]);
  assert!(parse(None).is_empty());
  let many=(0..100).map(|i|format!("A{i}")).collect::<Vec<_>>().join(",");
  assert_eq!(parse(Some(&many)).len(),MAX_BASES);
 }

 #[test]
 fn tiers_are_terciles_from_the_top() {
  assert_eq!((0..3).map(|i|tier(i,3)).collect::<Vec<_>>(),vec![3,2,1]);
  assert_eq!(tier(0,1),3);
  assert_eq!((0..6).map(|i|tier(i,6)).collect::<Vec<_>>(),vec![3,3,2,2,1,1]);
 }

 #[test]
 fn rows_union_favorites_and_hot_ranked_by_weight() {
  let favs=vec!["AXS".to_string(),"BTC".to_string(),"NOPE".to_string()];
  let hot=vec!["BTC".to_string(),"HO".to_string(),"OFF".to_string()];
  let v=answer(&favs,&hot,|b|match b {"AXS"=>Some(snap(0.2,true)),"BTC"=>Some(snap(0.9,true)),"HO"=>Some(snap(0.5,true)),"OFF"=>Some(snap(0.99,false)),_=>None},5);
  let rows=v["rows"].as_array().unwrap();
  let bases:Vec<&str>=rows.iter().map(|r|r["base"].as_str().unwrap()).collect();
  assert_eq!(bases,vec!["BTC","HO","AXS"],"untracked and missing bases have no row; each base once");
  assert_eq!(rows[0]["favorite"],true);
  assert_eq!(rows[1]["favorite"],false);
  assert_eq!(rows.iter().map(|r|r["tier"].as_u64().unwrap()).collect::<Vec<_>>(),vec![3,2,1]);
  for k in ["base","favorite","count","cat","tier","top","price","changePct","atMs"] {assert!(rows[0].get(k).is_some(),"{k}");}
  assert_eq!(v["generatedAtMs"],5);
 }
}
