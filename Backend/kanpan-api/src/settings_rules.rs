//! settings 字段的**通用值规则**：读契约 `contract/settings-fields.json` 的 `rules`，不再在这里手写。
//!
//! 母表是 iOS 的 `PrefsFieldPlan.rules`（Kanpan/Kanpan/Settings/Model/PrefsFieldRules.swift），`make sync-contract`
//! 把它连同按规则造出来的正反样例写进契约。这边编译期 `include_str!` 读进来（文件缺了、坏了是编译错误 / 首个测试就红，
//! 不会悄悄放过），手机网页读同一份清洗（Web/src/sync/settingsRules.ts）。三边的规则因此只有一份，
//! 「客户端发的值服务端不认」这一类毛病（审查 2026-10-10 查出多起）没有再长出来的地方。
//!
//! 通用描述装不下的（对比品种按交易所分流、订单流门槛表、学到的结论、拍平成路径的指标参数 / 颜色 / 副图高）
//! 在契约里是 `{"type":"custom","name":…}`，函数还在 `sync_validation::custom_setting` 手写。
//! 测试 `every_contract_field_has_exactly_one_rule` 保证契约里每个字段要么有通用描述、要么点名了一个真实存在的手写函数，
//! 两边都没有不行；手写函数没人用了也会红。
use serde_json::Value;
use std::collections::HashMap;
use std::sync::LazyLock;

/// 契约原文。和 `sync` / `sync_validation` 的测试读的是同一个文件。
pub const CONTRACT:&str=include_str!("../contract/settings-fields.json");

/// 一个字段的值规则（契约 `rules.<字段>`，读法和 Swift `PrefsFieldRule`、网页 `settingsRules.ts` 逐项相同）。
#[derive(Debug,Clone,PartialEq)]
pub enum Rule {
 Bool,
 /// 只收这几个串。
 Enum(Vec<String>),
 /// 任意串，UTF-8 ≤ max_bytes 字节。契约里的 `known` 只给客户端看（客户端只认那几个），服务端只看长度。
 Str{max_bytes:usize},
 Number{min:f64,max:f64},
 Int{min:i64,max:i64},
 /// `instruments::is_synced_interval`：现行周期加上老存档里的 8h / 3d。
 Interval,
 Intervals{max_count:usize},
 StringArray{values:Vec<String>,max_count:usize,unique:bool},
 /// 计次表：键在 keys 里、≤ max_keys 个，值是 0…max 的整数。
 CountMap{keys:Vec<String>,max_keys:usize,max:i64},
 /// `sync_validation::custom_setting` 里同名的手写函数。
 Custom(String),
}

fn strings(v:&Value,key:&str,field:&str)->Vec<String> {
 v[key].as_array().unwrap_or_else(||panic!("contract rules.{field}.{key} must be an array"))
  .iter().map(|x|x.as_str().unwrap_or_else(||panic!("contract rules.{field}.{key} must hold strings")).to_string()).collect()
}
fn count(v:&Value,key:&str,field:&str)->usize {
 v[key].as_u64().unwrap_or_else(||panic!("contract rules.{field}.{key} must be a non-negative integer")) as usize
}
fn float(v:&Value,key:&str,field:&str)->f64 {
 v[key].as_f64().unwrap_or_else(||panic!("contract rules.{field}.{key} must be a number"))
}

impl Rule {
 /// 契约里的一条 → 规则。读不懂就 panic：契约是编译进来的，第一条测试就会把它报出来。
 fn parse(field:&str,v:&Value)->Rule {
  match v["type"].as_str().unwrap_or_else(||panic!("contract rules.{field} has no `type`")) {
   "bool"=>Rule::Bool,
   "enum"=>Rule::Enum(strings(v,"values",field)),
   "string"=>Rule::Str{max_bytes:count(v,"maxBytes",field)},
   "number"=>Rule::Number{min:float(v,"min",field),max:float(v,"max",field)},
   "int"=>Rule::Int{min:float(v,"min",field) as i64,max:float(v,"max",field) as i64},
   "interval"=>Rule::Interval,
   "intervals"=>Rule::Intervals{max_count:count(v,"maxCount",field)},
   "stringArray"=>Rule::StringArray{values:strings(v,"values",field),max_count:count(v,"maxCount",field),unique:v["unique"].as_bool().unwrap_or(false)},
   "countMap"=>Rule::CountMap{keys:strings(v,"keys",field),max_keys:count(v,"maxKeys",field),max:float(v,"max",field) as i64},
   "custom"=>Rule::Custom(v["name"].as_str().unwrap_or_else(||panic!("contract rules.{field} is custom but has no `name`")).to_string()),
   other=>panic!("contract rules.{field} has a rule type this server does not know: `{other}`. \
    Teach settings_rules::Rule to read it (and Web/src/sync/settingsRules.ts), or regenerate the contract."),
  }
 }

 /// 一个顶层值过不过这条规则。`Custom` 不在这里判（见 `sync_validation::custom_setting`），一律不收。
 pub fn accepts(&self,v:&Value)->bool {
  match self {
   Rule::Bool=>v.is_boolean(),
   Rule::Enum(values)=>v.as_str().is_some_and(|s|values.iter().any(|x|x==s)),
   Rule::Str{max_bytes}=>v.as_str().is_some_and(|s|s.len()<=*max_bytes),
   Rule::Number{min,max}=>v.as_f64().is_some_and(|n|n.is_finite()&&n>=*min&&n<=*max),
   Rule::Int{min,max}=>v.as_i64().is_some_and(|n|n>=*min&&n<=*max),
   Rule::Interval=>v.as_str().is_some_and(crate::instruments::is_synced_interval),
   Rule::Intervals{max_count}=>v.as_array().is_some_and(|a|a.len()<=*max_count&&a.iter().all(|x|x.as_str().is_some_and(crate::instruments::is_synced_interval))),
   Rule::StringArray{values,max_count,unique}=>v.as_array().is_some_and(|a|a.len()<=*max_count
    &&a.iter().all(|x|x.as_str().is_some_and(|s|values.iter().any(|y|y==s)))
    &&(!*unique||a.iter().enumerate().all(|(i,x)|!a[..i].contains(x)))),
   Rule::CountMap{keys,max_keys,max}=>v.as_object().is_some_and(|o|o.len()<=*max_keys
    &&o.iter().all(|(k,n)|keys.iter().any(|x|x==k)&&n.as_i64().is_some_and(|n|(0..=*max).contains(&n)))),
   Rule::Custom(_)=>false,
  }
 }
}

/// 契约里全部字段的规则，第一次用到时解析一次。
static RULES:LazyLock<HashMap<String,Rule>>=LazyLock::new(||{
 let contract:Value=serde_json::from_str(CONTRACT).expect("contract/settings-fields.json is not valid JSON; regenerate it with `make sync-contract`");
 contract["rules"].as_object().expect("contract/settings-fields.json has no `rules`; regenerate it with `make sync-contract`")
  .iter().map(|(k,v)|(k.clone(),Rule::parse(k,v))).collect()
});

/// 这个 settings 顶层字段在契约里的规则；契约里没有（网页独有的、退役的、不认识的）是 `None`。
pub fn rule(field:&str)->Option<&'static Rule> {RULES.get(field)}

/// 契约里有规则的全部字段名（排好序）。
pub fn fields()->Vec<&'static str> {let mut v:Vec<&str>=RULES.keys().map(String::as_str).collect();v.sort_unstable();v}

#[cfg(test)]
mod tests {
 use super::*;
 use crate::sync_validation::{field,CUSTOM_SETTINGS};

 /// **契约里每个字段恰好有一条规则：要么通用描述，要么点名一个真实存在的手写函数。**
 /// 反过来每个手写函数都得有字段在用——没人用的手写规则是上一次删字段漏下的，留着只会让人以为它还在生效。
 #[test] fn every_contract_field_has_exactly_one_rule() {
  let contract:Value=serde_json::from_str(CONTRACT).unwrap();
  let wire:Vec<String>=contract["wireKeys"].as_array().unwrap().iter().map(|v|v.as_str().unwrap().to_string()).collect();
  for key in &wire {
   let rule=rule(key).unwrap_or_else(||panic!(
    "`{key}` is in the contract's wireKeys but has no entry in `rules`. Give it a rule in \
     PrefsFieldPlan.rules (Kanpan/Kanpan/Settings/Model/PrefsFieldRules.swift) and run `make sync-contract`."));
   if let Rule::Custom(name)=rule {
    assert!(CUSTOM_SETTINGS.contains(&name.as_str()),
     "`{key}` names the hand-written rule `{name}`, but sync_validation::custom_setting has no such function. \
      Add it there (and to CUSTOM_SETTINGS), or describe the field with a generic rule instead.");
   }
  }
  for name in CUSTOM_SETTINGS {
   assert!(fields().iter().any(|k|rule(k)==Some(&Rule::Custom(name.to_string()))),
    "sync_validation::custom_setting still has `{name}`, but no field in the contract uses it any more. Delete the function.");
  }
  let mut ruled=fields();ruled.sort_unstable();
  let mut wire_sorted:Vec<&str>=wire.iter().map(String::as_str).collect();wire_sorted.sort_unstable();
  assert_eq!(ruled,wire_sorted,"contract `rules` and `wireKeys` must name the same fields; regenerate with `make sync-contract`");
 }

 /// **契约里的正反样例，服务端逐条照办。** 样例是 Swift 按规则造的，iOS 解码、手机网页清洗也拿同一批对——
 /// 三边对规则的读法有一处不同，这里或那两边就红。
 #[test] fn contract_samples_are_what_the_server_does() {
  let contract:Value=serde_json::from_str(CONTRACT).unwrap();
  let mut checked=0;
  for (key,doc) in contract["rules"].as_object().unwrap() {
   for v in doc["accept"].as_array().into_iter().flatten() {
    assert!(field("settings",key,v),"contract says settings.{key} = {v} is accepted, the server refuses it");checked+=1;
   }
   for v in doc["reject"].as_array().into_iter().flatten() {
    assert!(!field("settings",key,v),"contract says settings.{key} = {v} is refused, the server accepts it");checked+=1;
   }
  }
  assert!(checked>100,"the contract carries almost no samples ({checked}); regenerate it with `make sync-contract`");
 }

 /// 通用规则只认顶层路径：`redUp/x`、`skin/MA` 这种拍平路径一律不收（和改造前 `field` 的行为一样）。
 #[test] fn generic_rules_refuse_nested_paths() {
  for (path,v) in [("redUp/x",serde_json::json!(true)),("skin/MA",serde_json::json!("sage")),("drawToolUsage/trend",serde_json::json!(1))] {
   assert!(!field("settings",path,&v),"{path}");
  }
 }
}
