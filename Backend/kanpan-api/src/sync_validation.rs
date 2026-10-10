//! Mirrors the native wire types at the boundary, before a merged value can reach another device.
use crate::{error::{ApiError,Result},sync::{Object,SETTINGS,DRAWING_PREFERENCES,DRAWINGS,FAVORITES,GROUPS,ALERTS}};
use serde_json::Value;
// `IndicatorID` (KanpanCore/Indicator/IndicatorID.swift), split the way `IndicatorID.placement`
// splits it: main chart first, sub-panels second. `overlays` accepts only the first half and
// `subs` / `subInverted` only the second, so which half an indicator is in is part of the
// contract, not a detail — an indicator on the wrong side is refused and 400s the whole
// operation. Both halves are generated into `contract/settings-fields.json` as
// `overlayIndicatorIDs` / `subIndicatorIDs`; `the_indicator_vocabulary_is_the_contract_one`
// holds these to it. Slices, not fixed arrays: adding one is a single string, no length to
// keep in step (same reason `sync::SETTINGS_FIELDS` is a slice).
const OVERLAY_INDICATORS:&[&str]=&["MA","EMA","BOLL","VWAP","ST","SAR","ORDERFLOW"];
const SUB_INDICATORS:&[&str]=&["VOL","MACD","RSI","KDJ","SRSI","ATR","OI","LSR","TAKER","BASIS","DMI","CVD"];
// `settings.autoLayers` 的白名单（原来这里手抄的 AUTO_LAYERS）2026-10-10 起直接读契约 `rules.autoLayers`
// （`settings_rules`），不再有第二份。
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
// Intervals: `instruments::is_synced_interval` — what the period bar offers today plus the two it
// used to (8h, 3d), which old archives still carry.
// Quotes: `instruments::QUOTE_ASSETS`, the client's `QuoteAssets.tradable` (both checked against contract/instruments.json). Binance
// lists USDC-margined contracts too, so a USDT-only rule refused perfectly real favourites.
use crate::instruments::{DEFAULT_VENUE,DEFAULT_MARKET,is_synced_interval};
fn color(v:&Value)->bool {v.as_object().is_some_and(|o|o.len()==1)&&v["value"].as_str().is_some_and(|s|matches!(s.len(),7|9)&&s.starts_with('#')&&s[1..].bytes().all(|c|c.is_ascii_hexdigit()))}
fn number(v:&Value,lo:f64,hi:f64)->bool {v.as_f64().is_some_and(|v|v.is_finite()&&v>=lo&&v<=hi)}
fn integers(v:&Value,count:usize,lo:i64,hi:i64)->bool {v.as_array().is_some_and(|a|a.len()<=count&&a.iter().all(|v|v.as_i64().is_some_and(|n|n>=lo&&n<=hi)))}
fn string(v:&Value,limit:usize)->bool {v.as_str().is_some_and(|s|s.len()<=limit)}
// `settings.drawToolUsage` / `analysisUsage`（每把画线工具 / 「分析」面板每节用了几次）2026-10-10 起是契约里的
// 通用规则 `countMap`（键的词表、最多几个键、0…100000 的整数都在契约 `rules` 里），不再在这里手写。
/// 提醒的 Webhook 地址：≤ 1024 字节、`http://` 或 `https://` 开头、不含空白。
fn webhook(v:&Value)->bool {
 v.as_str().is_some_and(|s|s.len()<=1024&&(s.starts_with("http://")||s.starts_with("https://"))&&!s.chars().any(char::is_whitespace))
}
/// 主力订单流改过的门槛 / 步长：`{ base: { spot?, usdtPerp?, coinPerp?, delivery?, step? } }`。
/// base 和客户端 `OrderFlowBase.isValid` 同一条规矩（`^[A-Z0-9]{1,20}$`），最多 200 只
/// （`Prefs.maxOrderFlowOverrides`）；门槛 1e3…1e9 美元、步长 1e-8…1e6，和
/// `OrderFlowOverride.thresholdRange / stepRange` 同一组数。空的一只（`{}`）客户端从来不发——
/// 一项不剩就是恢复默认，那只 base 直接从表里拿掉。
///
/// 这几个数和客户端经 `contract/settings-fields.json` 的 `orderFlow` 一段对账
/// （测试 `order_flow_limits_are_the_contract_ones`），改一边不改另一边测试就红。
const ORDER_FLOW_MAX_OVERRIDES:usize=200;
const ORDER_FLOW_BASE_MAX_LEN:usize=20;
const ORDER_FLOW_THRESHOLD:(f64,f64)=(1e3,1e9);
const ORDER_FLOW_STEP:(f64,f64)=(1e-8,1e6);
const ORDER_FLOW_THRESHOLD_KEYS:[&str;4]=["spot","usdtPerp","coinPerp","delivery"];
fn order_flow_overrides(v:&Value)->bool {
 v.as_object().is_some_and(|all|all.len()<=ORDER_FLOW_MAX_OVERRIDES&&all.iter().all(|(base,o)|{
  !base.is_empty()&&base.len()<=ORDER_FLOW_BASE_MAX_LEN&&base.bytes().all(|c|c.is_ascii_uppercase()||c.is_ascii_digit())
  && o.as_object().is_some_and(|o|!o.is_empty()&&o.iter().all(|(k,v)|match k.as_str() {
   "step"=>number(v,ORDER_FLOW_STEP.0,ORDER_FLOW_STEP.1),
   k if ORDER_FLOW_THRESHOLD_KEYS.contains(&k)=>number(v,ORDER_FLOW_THRESHOLD.0,ORDER_FLOW_THRESHOLD.1),
   _=>false,
  }))
 }))
}
fn one_of(v:&Value,all:&[&str])->bool {v.as_str().is_some_and(|s|all.contains(&s))}
/// 「按我的习惯自动调整」学到的结论（客户端 `LearnedDefaults`，Kanpan/Kanpan/Habits/LearnedDefaults.swift）：
/// `{ intervals?: {品种: 条}, priceAxis?: {类别: 条}, sectorWindow?: {市场: 条}, watchMove?: {品种: 条} }`，
/// 每条 `{ v, n, at }`——v 是学到的值、n 依据几次（非负整数）、at 最近一次的秒级时刻。
/// 整份序列化 ≤ 16 KB（客户端 `LearnedDefaults.maxBytes`，写之前按最旧的先丢裁到这以内）。
/// 值的规则和客户端 `LearnedDefaults.sanitized()` 逐项对齐：周期同 `interval`，价格轴只有
/// 线性 / 对数（百分比不学），板块只有今日 / 5 日，灵敏度系数 0.5…2。
/// `settings.chartLayouts`：电脑网页版的多套图表布局（2026-10-07，Web/src/app/layouts.ts）。
/// 只有网页版读写，手机端原样留着不认识的键；服务端只校验、不读。
/// `{active, sets:[{id,name,layout,cells:[{symbol,iv,footprint?,ha?,range?,…}]}]}`，最多 20 套、每套最多 16 格，整份 ≤ 32 KB。
/// 格子里除了品种 / 周期 / 三个布尔开关（足迹 `footprint`、平均 K 线 `ha`、区间 K 线 `range`，和网页
/// `CELL_FLAGS` 一一对上），留最多 6 个短键给以后的格子配置（值只能是布尔、数、≤ 16 字的串），老服务端不挡新网页。
/// 品种两种写法，和网页 `validSymbol` 逐字对齐：裸代号（2–40 个字母数字与 `._-`），或者多交易所的
/// `venue/market/代号`（交易所 2–20、市场 2–10，小写字母开头、只有小写字母数字与 `_`；代号 1–40）。
/// 整串最长 72 字（20 + 1 + 10 + 1 + 40）：比「约 64」宽一点，是因为三段各自的上限就是网页那边的，
/// 这里卡得比网页紧，网页存得下的格子推上来就会被当成坏值丢掉。
const CHART_LAYOUTS_MAX_BYTES:usize=32_768;
const CHART_LAYOUT_KINDS:&[&str]=&["1","2","2v","3","4","6","8","9","12","16"];
/// 布局格子里的品种（见 `chart_layouts` 的说明）。
fn cell_symbol(s:&str)->bool {
 let code=|s:&str,min:usize|(min..=40).contains(&s.chars().count())&&s.chars().all(|c|c.is_alphanumeric()||matches!(c,'.'|'_'|'-'));
 let tag=|s:&str,max:usize|(2..=max).contains(&s.len())&&s.as_bytes()[0].is_ascii_lowercase()&&s.bytes().all(|c|c.is_ascii_lowercase()||c.is_ascii_digit()||c==b'_');
 match s.split('/').collect::<Vec<_>>()[..] {
  [bare]=>code(bare,2),
  [venue,market,symbol]=>tag(venue,20)&&tag(market,10)&&code(symbol,1),
  _=>false,
 }
}
fn chart_layouts(v:&Value)->bool {
 fn id(v:&Value)->bool {v.as_str().is_some_and(|s|(1..=32).contains(&s.len())&&s.bytes().all(|c|c.is_ascii_alphanumeric()||c==b'_'||c==b'-'))}
 fn cell(c:&Value)->bool {
  let Some(o)=c.as_object() else {return false};
  const CORE:[&str;5]=["symbol","iv","footprint","ha","range"];
  let extra=o.keys().filter(|k|!CORE.contains(&k.as_str())).count();
  o.get("symbol").and_then(Value::as_str).is_some_and(cell_symbol)
   && o.get("iv").and_then(Value::as_str).is_some_and(|s|(1..=8).contains(&s.len())&&s.bytes().all(|c|c.is_ascii_alphanumeric()))
   && ["footprint","ha","range"].iter().all(|k|o.get(*k).is_none_or(Value::is_boolean))
   && extra<=6
   && o.iter().all(|(k,v)|CORE.contains(&k.as_str())
     ||(1..=16).contains(&k.len())&&k.as_bytes()[0].is_ascii_alphabetic()&&k.bytes().all(|c|c.is_ascii_alphanumeric())
      &&(v.is_boolean()||number(v,-1e15,1e15)||v.as_str().is_some_and(|s|s.chars().count()<=16)))
 }
 fn set(x:&Value)->bool {
  x.as_object().is_some_and(|o|o.len()==4)
   && id(&x["id"])
   && x["name"].as_str().is_some_and(|s|!s.trim().is_empty()&&s.len()<=96)
   && one_of(&x["layout"],CHART_LAYOUT_KINDS)
   && x["cells"].as_array().is_some_and(|a|(1..=16).contains(&a.len())&&a.iter().all(cell))
 }
 serde_json::to_string(v).is_ok_and(|s|s.len()<=CHART_LAYOUTS_MAX_BYTES)
  && v.as_object().is_some_and(|o|o.len()==2)
  && id(&v["active"])
  && v["sets"].as_array().is_some_and(|a|(1..=20).contains(&a.len())&&a.iter().all(set))
}
const LEARNED_DEFAULTS_MAX_BYTES:usize=16_384;
const LEARNED_KEY_MAX_LEN:usize=128;
fn learned_defaults(v:&Value)->bool {
 fn entry(e:&Value,value:&dyn Fn(&Value)->bool)->bool {
  e.as_object().is_some_and(|o|o.len()==3&&o.contains_key("v")&&o.contains_key("n")&&o.contains_key("at"))
   &&value(&e["v"])&&e["n"].as_u64().is_some()&&number(&e["at"],0.0,9e15)
 }
 fn table(t:&Value,key:&dyn Fn(&str)->bool,value:&dyn Fn(&Value)->bool)->bool {
  t.as_object().is_some_and(|m|m.iter().all(|(k,e)|!k.is_empty()&&k.len()<=LEARNED_KEY_MAX_LEN&&key(k)&&entry(e,value)))
 }
 serde_json::to_string(v).is_ok_and(|s|s.len()<=LEARNED_DEFAULTS_MAX_BYTES)
 && v.as_object().is_some_and(|o|o.iter().all(|(k,t)|match k.as_str() {
  "intervals"=>table(t,&|_|true,&|v|v.as_str().is_some_and(is_synced_interval)),
  "priceAxis"=>table(t,&|k|["crypto","equity","metal","index","other"].contains(&k),&|v|one_of(v,&["linear","log"])),
  "sectorWindow"=>table(t,&|k|["crypto","us"].contains(&k),&|v|one_of(v,&["today","d5"])),
  "watchMove"=>table(t,&|_|true,&|v|number(v,0.5,2.0)),
  _=>false,
 }))
}
/// 一个代号字段：注册表里**某一家**认它就收（单看这一个字段不知道是哪一家；是不是那一家的，
/// 由 [`identity`] 在整个对象上按 `venue` / `market` 再判一次）。各家的代号规则在各家目录里
/// （币安收中文底名、Coinbase `BASE-USD`、Hyperliquid 大写 coin 名……），这里不再手抄。
fn symbol(v:&Value)->bool {
 v.as_str().is_some_and(|s|crate::venues::venues().iter().any(|venue|venue.symbol_ok(s)))
}
/// How many anchors a finished drawing of this kind carries: `Drawing.Kind.pointCount`.
/// Checked kind by kind against `contract/drawing-fields.json`'s `anchorCounts` (generated from
/// the client's enum) by `anchor_counts_are_the_clients_point_counts`.
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
/// 画线的扩展样式 `drawings.style`（网页独有，`crate::sync::WEB_DRAWING_FIELDS`；网页那份清洗在 Web/src/chart/drawStyle.ts `cleanStyle`，
/// 两边同一组上限）：一个对象、序列化 ≤ 4 KB；键 1…32 个 ASCII 字母数字（字母打头）；值是布尔、有限数、≤ 64 字节的串，
/// 或同样规则的对象，最多套三层；不收数组与 null（「恢复默认」是整个 style 发 null，见 `field` 的墓碑规则）。
pub const DRAWING_STYLE_MAX_BYTES:usize=4096;
fn drawing_style(v:&Value)->bool {
 fn key(k:&str)->bool {(1..=32).contains(&k.len())&&k.as_bytes()[0].is_ascii_alphabetic()&&k.bytes().all(|c|c.is_ascii_alphanumeric())}
 fn level(v:&Value,depth:usize)->bool {
  v.as_object().is_some_and(|o|o.iter().all(|(k,x)|key(k)&&(x.is_boolean()||number(x,-1e15,1e15)||string(x,64)||depth<3&&level(x,depth+1))))
 }
 level(v,1)&&serde_json::to_string(v).is_ok_and(|s|s.len()<=DRAWING_STYLE_MAX_BYTES)
}
/// 电脑网页独有的习惯 `settings.webPrefs`（`crate::sync::WEB_SETTINGS_FIELDS`）：一个对象、序列化 ≤ 8 KB。
/// 里面有哪些键由网页自己清洗（Web/src/sync/webPrefs.ts），服务端只管类型与体积——和 webChart 同一档。
pub const WEB_PREFS_MAX_BYTES:usize=8192;
fn style(v:&Value)->bool {v.as_object().is_some_and(|o|o.iter().all(|(k,v)|field(DRAWINGS,k,v))&&o.contains_key("lineWidth")&&o.contains_key("dash")&&o.contains_key("filled")&&o.contains_key("levels"))}
/// 「对比 K 线」的一只品种：完整身份键 `venue/market/SYMBOL`，和 favorites 的 id 同一形态。
///
/// 代号段按交易所分流交给 `identity`（也就是注册表里那一家的 `symbol_ok`），不另写一套：
/// 以前这里自己抄了一条只收 ASCII 的规则，于是自选、画线、提醒都收得下的 `币安人生USDT`，
/// 一加进对比就让整条 settings 操作 400、同步队列卡死在那一条上。一只品种能收藏就能对比，
/// 两处规则必须是同一条。认不得的交易所 / 市场一样拒（favorites 的 id 也是这样判的）。
/// 128 字节只是切分之前的粗上限：合法键最长 `binance/usd_m/` + 36 个汉字 + `USDT` = 126 字节。
fn compare_key(v:&Value)->bool {
 let Some(s)=v.as_str() else {return false};
 let mut p=s.splitn(3,'/');
 let (Some(venue),Some(market),Some(symbol))=(p.next(),p.next(),p.next()) else {return false};
 s.len()<=128 && identity(venue,market,symbol)
}
/// 契约里 `{"type":"custom","name":…}` 点名的那几个手写规则（`settings_rules` 的测试保证两边一一对上）。
pub const CUSTOM_SETTINGS:&[&str]=&["compare_symbols","order_flow_overrides","learned_defaults","indicator_params","indicator_colors","sub_height_overrides"];
/// settings 里通用描述装不下的字段：按契约点的名字找函数。`p` 是按 `/` 切开的路径。
fn custom_setting(name:&str,p:&[&str],v:&Value)->bool {
 match name {
  "compare_symbols"=>p.len()==1&&v.as_array().is_some_and(|a|a.len()<=3 && a.iter().all(compare_key) && a.iter().enumerate().all(|(i,v)| !a[..i].contains(v))),
  "order_flow_overrides"=>p.len()==1&&order_flow_overrides(v),
  "learned_defaults"=>p.len()==1&&learned_defaults(v),
  // 下面三个线上是拍平的：第二段只认指标词表（契约 `indicatorIDs`）。
  "indicator_params"=>p.len()==2&&indicator(p[1])&&integers(v,20,1,400),
  "indicator_colors"=>p.len()==3&&indicator(p[1])&&p[2].parse::<u8>().is_ok_and(|n|n<=20)&&color(v),
  "sub_height_overrides"=>p.len()==2&&indicator(p[1])&&number(v,0.25,5.0),
  _=>false,
 }
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
  // 网页画线「恢复默认样式」：扩展样式整个清掉（`drawings.style`，网页独有）。
  || collection==DRAWINGS&&path=="style"
  // note / webhook / webhookText（从图上加提醒）：客户端永远写出这三个键，空就是 null。
  || collection==ALERTS&&p.len()==1&&matches!(path,"drawingID"|"firedAt"|"firedPrice"|"dueAt"|"reviewID"|"note"|"webhook"|"webhookText"|"rule")
  || collection==SETTINGS&&p.len()>=2 || collection==DRAWING_PREFERENCES&&p.len()==2}
 if collection==SETTINGS {
  // 网页独有的三个（`crate::sync::WEB_SETTINGS_FIELDS` 与 WEB_ONLY_SETTINGS_FIELDS）：不在 iOS 生成的契约里，规则留在这里。
  match path {
   "chartLayouts"=>return chart_layouts(v),
   // 网页图表设置：一个对象，序列化 ≤ 8 KB；里面的键由网页自己清洗
   "webChart"=>return v.is_object()&&serde_json::to_string(v).is_ok_and(|s|s.len()<=8192),
   "webPrefs"=>return v.is_object()&&serde_json::to_string(v).is_ok_and(|s|s.len()<=WEB_PREFS_MAX_BYTES),
   _=>{}
  }
  // 其余全部按契约 `rules` 判（2026-10-10「同步字段解耦」）：通用描述直接判，`custom` 交给同名手写函数。
  // 契约里没有的名字（退役的、不认识的）一律不收——和原来 `_=>false` 一样。
  // `indicatorLayouts/<minute|hour|day>`（09-27~10-02 的周期分组）2026-10-10 退役，规则随名字一起删了
  // （`sync::RETIRED_SETTINGS_FIELDS`）：老客户端发上来先被当成未知字段丢掉，走不到这里。
  return match crate::settings_rules::rule(p[0]) {
   Some(crate::settings_rules::Rule::Custom(name))=>custom_setting(name,&p,v),
   Some(rule)=>p.len()==1&&rule.accepts(v),
   None=>false,
  }
 }
 // `favorites`（收藏的画线工具）2026-10-10 退役（`sync::RETIRED_DRAWING_PREFERENCE_FIELDS`），规则一起删了。
 if collection==DRAWING_PREFERENCES {return match path {"magnet"|"continuous"=>v.is_boolean(),
  _=>p.len()==2&&KINDS.contains(&p[1])&&match p[0] {"styles"=>style(v),"variants"=>v.as_str().is_some_and(|s|KINDS.contains(&s)),_=>false}}}
 if p.len()!=1 {return false}
 match (collection,path) {
  (DRAWINGS,"kind")=>v.as_str().is_some_and(|s|KINDS.contains(&s)),
  // Up to eight: `Drawing.Part.anchors`, which the seven-point head-and-shoulders needs.
  (DRAWINGS,"anchors")=>v.as_array().is_some_and(|a|(1..=8).contains(&a.len())&&a.iter().all(|p|p.as_object().is_some_and(|o|o.len()==2)&&number(&p["t"],0.0,9e15)&&number(&p["p"],-1e15,1e15))),
  (DRAWINGS,"color")=>color(v),
  (DRAWINGS,"lineWidth")=>number(v,0.5,6.0),
  (DRAWINGS,"dash")=>v.as_str().is_some_and(|s|["solid","dashed","dotted"].contains(&s)),
  (DRAWINGS,"filled"|"locked"|"hidden")|(FAVORITES,"alerts")=>v.is_boolean(),
  (DRAWINGS,"levels")=>v.as_array().is_some_and(|a|a.len()<=24&&a.iter().all(|v|number(v,-10.0,10.0))),
  (DRAWINGS|FAVORITES,"market")=>v.as_str().is_some_and(|m|crate::venues::venues().iter().any(|x|x.market()==m)),
  (DRAWINGS|FAVORITES,"venue")=>v.as_str().is_some_and(|s|crate::venues::venue(s).is_some()),
  (DRAWINGS|FAVORITES,"symbol")=>symbol(v),
  (DRAWINGS,"created")=>number(v,0.0,9e15),
  // An anti-abuse ceiling, deliberately not a copy of the client's UX rule. The client caps a
  // caption at 60 Swift Characters (grapheme clusters) because that is what still reads as one
  // line over the candles; this function can only count UTF-8 bytes, and the two do not convert
  // into each other. The old comment here claimed "240 bytes covers 60 of any of them" and was
  // simply wrong: eleven family emoji are eleven Characters and 275 bytes, so input the client
  // considered legal came back as a 400. Sixty skin-toned family emoji reach ~2.5 KB, which is
  // why 1 KB would not be enough either. 4 KB clears any realistic caption by a wide margin and
  // still stops someone pasting a novel; the per-field 64 KB rule in `Operation::validate` is
  // the real backstop. Whatever the client accepts, the server must be able to store.
  (DRAWINGS,"text")=>string(v,4096),
  (DRAWINGS,"style")=>drawing_style(v),
  (FAVORITES,"groupId")=>string(v,100),
  (FAVORITES|GROUPS,"order")=>number(v,0.0,1e9),
  (GROUPS,"name")=>string(v,100),
  (GROUPS,"members")=>v.as_array().is_some_and(|a|a.len()<=2000&&a.iter().all(|v|string(v,100))),
  // ——— 提醒（方案文档 2.2） ———
  // 三种都真的在用（P3.1）：`drawing` / `price` 按线判，`reviewDue` 按 `dueAt` 判。
  // `condition`（2026-09-27）：费率 / 持仓量 / 均线 / 大单，条件本体在 `rule` 里，只有服务端判。
  (ALERTS,"kind")=>one_of(v,&["drawing","price","reviewDue","condition"]),
  // 条件提醒的条件本体（docs/条件提醒-协议-2026-09-27.md 第 2 节）。已知 `type` 严格校验，
  // 认不得的 `type` 收下不判（`conditions::Rule::Unknown`）；null 见上面的可空名单。没有 `type`、用 `kind`
  // 区分的是技术指标条件（2026-10-07，`conditions::indicators`），三种严格校验。
  (ALERTS,"rule")=>crate::conditions::valid_rule(v),
  // 这个集合的 market 是整串 `binance/usd_m`（drawings / favorites 是 `usd_m` 加单独的
  // venue）。形状是文档定的，照抄，不要「统一」。
  (ALERTS,"market")=>v.as_str().is_some_and(|m|crate::venues::by_market_key(m).is_some()),
  (ALERTS,"symbol")=>symbol(v),
  // 画线的同步对象 id 原样，和 `drawings` 的 id 同一套形态。
  (ALERTS,"drawingID")=>string(v,180),
  (ALERTS,"lines")=>lines(v),
  // `close`（收盘穿过）是第二种条件，见文档第 10 节。两侧评估器都判它
  // （`alerts::crossed_on_close` / 客户端 `AlertEvaluator.closeHit`）。
  (ALERTS,"condition")=>one_of(v,&["touch","close"]),
  (ALERTS,"status")=>one_of(v,&["active","fired","paused"]),
  (ALERTS,"once")=>v.is_boolean(),
  (ALERTS,"armedAt"|"firedAt"|"dueAt"|"created")=>number(v,0.0,9e15),
  (ALERTS,"firedPrice")=>number(v,-1e15,1e15),
  (ALERTS,"reviewID")=>string(v,100),
  // 通知标题是客户端生成的中文短句。和 `drawings.text` 同一档理由：这里数的是 UTF-8
  // 字节，客户端数的是字素，两者换算不了，所以给一个宽到不可能误伤的上限。
  (ALERTS,"title")=>string(v,1024),
  // 从图上加提醒：备注 ≤ 256 字节；Webhook 地址 ≤ 1024 字节、http(s) 开头、不含空白；
  // Webhook 文案模板 ≤ 1024 字节。和客户端的字段契约逐字一致——这里多收紧一点，
  // 带它的整条 op 就是 400、那台手机的同步队列会被堵死。
  (ALERTS,"note")=>string(v,256),
  (ALERTS,"webhook")=>webhook(v),
  (ALERTS,"webhookText")=>string(v,1024),_=>false
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
///
/// 同一个地方还做一件规范化：**提醒上有 `rule` 对象，`kind` 就是 `condition`**
/// （条件提醒协议第 5 节）。老客户端认不得 `condition` 这个 kind，解成 `drawing`、下次记账时
/// 又原样编码成 `drawing` 发上来；`rule` 它不认识，只能原样留在对象上。不改回来的话，
/// 那条 op 会因为「画线提醒没有线」整条 400、堵住那台手机的队列，条件也就丢了。
pub fn clear_tombstones(value:&mut Object) {
 if value.collection==DRAWINGS && value.body.get("text").is_some_and(Value::is_null) {
  value.body.insert("text".into(),Value::String(String::new()));
 }
 if value.collection==ALERTS && value.body.get("rule").is_some_and(Value::is_object)
  && value.body.get("kind").and_then(Value::as_str)!=Some("condition") {
  value.body.insert("kind".into(),Value::String("condition".into()));
 }
}
/// `venue/market/symbol` 是不是一只真品种：`(venue, market)` 是注册表里的一家，代号是那一家的形状。
/// 条件提醒仍只认币安（`object` 里另有一道），交易复盘的回合也只认币安 U 本位（`trade_round`）。
pub fn identity(venue:&str,market:&str,symbol:&str)->bool {
 crate::venues::listed(venue,market).is_some_and(|v|v.symbol_ok(symbol))
}
pub fn object(value:&Object)->Result<()> {
 if value.deleted{return Ok(())}
 if value.body.iter().any(|(k,v)|!field(&value.collection,k,v)){return Err(ApiError::bad("invalid_sync_value"))}
 if value.collection==FAVORITES {
  let part=|k:&str|value.body.get(k).and_then(Value::as_str).unwrap_or("");
  let (venue,market,symbol)=(part("venue"),part("market"),part("symbol"));
  if !identity(venue,market,symbol) || value.id!=format!("{venue}/{market}/{symbol}") {return Err(ApiError::bad("invalid_favorite_identity"))}
 }
 if value.collection==DRAWINGS {
  let kind=value.body.get("kind").and_then(Value::as_str).ok_or_else(||ApiError::bad("invalid_drawing"))?;
  let count=anchor_count(kind);
  if value.body.get("anchors").and_then(Value::as_array).is_none_or(|a|a.len()!=count){return Err(ApiError::bad("invalid_drawing"))}
  let symbol=value.body.get("symbol").and_then(Value::as_str).ok_or_else(||ApiError::bad("invalid_drawing"))?;
  let venue=value.body.get("venue").and_then(Value::as_str).unwrap_or(DEFAULT_VENUE);
  let market=value.body.get("market").and_then(Value::as_str).unwrap_or(DEFAULT_MARKET);
  if !identity(venue,market,symbol) || !value.id.starts_with(&format!("{venue}/{market}/{symbol}/")) {return Err(ApiError::bad("invalid_drawing_identity"))}
 }
 if value.collection==ALERTS {
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
  // 条件提醒：必须带条件本体，而且只在币安 U 本位上（四种条件的数据都只来自那里）。
  if kind=="condition" && (!value.body.get("rule").is_some_and(Value::is_object) || market!=crate::alerts::BINANCE) {
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

// ——— 交易复盘的回合（`docs/交易复盘-协议-2026-09-27.md` 第 1、2 节）———
//
// 回合是手机从交易所成交机械拼出来的，所以这里只校验协议列为「必填」的键，未知键原样放行
// （协议第 1 节：客户端升级加字段时老服务端不能整条拒收，2026-09-19 同步白名单的坑）。
// 数字一律是十进制字符串，按 decimal 解，不经过浮点。

/// 一份回合最多几笔成交。请求体上限 6 MiB、一笔成交三百来字节，一万笔已经是整批的上限了。
pub const ROUND_MAX_FILLS:usize=10_000;
/// 服务端认得的回合结构版本。
pub const ROUND_VERSION:i64=1;
/// 最早收得下的时刻：2017-01-01（币安开张之前不会有成交）。
const EARLIEST_MS:i64=1_483_228_800_000;
/// 允许手机时钟比服务器快这么多。
const CLOCK_SKEW_MS:i64=300_000;
/// 协议第 1 节的十进制字符串：可带前导 `-`，一个 `.`，不带 `+`、指数、千分位。
/// 整数部分最多 12 位、小数部分最多 18 位：价格 × 数量在 `rust_decimal` 的 28 位里放得下，
/// 算浮盈浮亏时不会溢出。
pub fn decimal(s:&str)->Option<rust_decimal::Decimal> {
 let body=s.strip_prefix('-').unwrap_or(s);
 let (whole,fraction)=match body.split_once('.') {Some((w,f))=>(w,Some(f)),None=>(body,None)};
 if whole.is_empty()||whole.len()>12||!whole.bytes().all(|c|c.is_ascii_digit()) {return None}
 if let Some(f)=fraction && (f.is_empty()||f.len()>18||!f.bytes().all(|c|c.is_ascii_digit())) {return None}
 s.parse().ok()
}
fn dec(v:&Value)->Option<rust_decimal::Decimal> {v.as_str().and_then(decimal)}
fn positive(v:&Value)->bool {dec(v).is_some_and(|d|d.is_sign_positive()&&!d.is_zero())}
fn non_negative(v:&Value)->bool {dec(v).is_some_and(|d|d.is_zero()||d.is_sign_positive())}
/// 资产代号：`USDT`、`BNB`、`1000SHIB` 这类，只有 ASCII 大写与数字。
fn asset(v:&Value)->bool {v.as_str().is_some_and(|s|(1..=20).contains(&s.len())&&s.bytes().all(|c|c.is_ascii_uppercase()||c.is_ascii_digit()))}
/// 交易所给的 id（成交号、订单号）：数字转成的字符串，这里只要是一段可见 ASCII。
fn exchange_id(v:&Value)->bool {v.as_str().is_some_and(|s|(1..=64).contains(&s.len())&&s.bytes().all(|c|c.is_ascii_graphic()))}
fn millis(v:&Value,now:i64)->Option<i64> {v.as_i64().filter(|t|*t>=EARLIEST_MS&&*t<=now+CLOCK_SKEW_MS)}
/// 一份回合过不过协议。只看必填键；错了一律 `invalid_round`，版本比服务端新是 `unsupported_round_version`。
pub fn trade_round(v:&Value,now:i64)->Result<()> {
 let bad=||ApiError::bad("invalid_round");
 let o=v.as_object().ok_or_else(bad)?;
 let version=o.get("version").and_then(Value::as_i64).ok_or_else(bad)?;
 if version>ROUND_VERSION {return Err(ApiError::bad("unsupported_round_version"))}
 if version<1 {return Err(bad())}
 let text=|k:&str|o.get(k).and_then(Value::as_str).ok_or_else(bad);
 if uuid::Uuid::parse_str(text("id")?).is_err() {return Err(bad())}
 if !identity(text("venue")?,text("market")?,text("symbol")?)||(text("venue")?,text("market")?)!=("binance","usd_m") {return Err(bad())}
 let tag=text("accountTag")?;
 if !(1..=32).contains(&tag.len())||!tag.bytes().all(|c|c.is_ascii_alphanumeric()||c==b'_'||c==b'-') {return Err(bad())}
 let side=text("positionSide")?;let direction=text("direction")?;let status=text("status")?;
 if !matches!(side,"BOTH"|"LONG"|"SHORT")||!matches!(direction,"long"|"short")||!matches!(status,"open"|"closed") {return Err(bad())}
 if (side=="LONG"&&direction!="long")||(side=="SHORT"&&direction!="short") {return Err(bad())}
 let get=|k:&str|o.get(k).ok_or_else(bad);
 if !asset(get("quoteAsset")?) {return Err(bad())}
 let opened=millis(get("openedAt")?,now).ok_or_else(bad)?;
 let closed=get("closedAt")?;let holding=get("holdingMs")?;let close_avg=get("closeAvgPrice")?;
 let closed=if closed.is_null() {None} else {Some(millis(closed,now).filter(|c|*c>=opened).ok_or_else(bad)?)};
 match (status,closed) {("closed",Some(_))|("open",None)=>{},_=>return Err(bad())}
 match closed {
  Some(c)=>if holding.as_i64()!=Some(c-opened)||!positive(close_avg) {return Err(bad())},
  None=>if !holding.is_null()||!(close_avg.is_null()||positive(close_avg)) {return Err(bad())},
 }
 let updated=millis(get("updatedAt")?,now).filter(|u|*u>=opened&&closed.is_none_or(|c|*u>=c)).ok_or_else(bad)?;
 if !positive(get("openAvgPrice")?)||!positive(get("openedQty")?) {return Err(bad())}
 for k in ["closedQty","maxQty","peakNotional"] {if !non_negative(get(k)?) {return Err(bad())}}
 for k in ["realizedPnl","commission","funding","netPnl"] {if dec(get(k)?).is_none() {return Err(bad())}}
 let leverage=get("leverage")?;
 if !leverage.is_null()&&leverage.as_i64().is_none_or(|l|!(1..=1000).contains(&l)) {return Err(bad())}
 let fees=get("commissionByAsset")?.as_object().ok_or_else(bad)?;
 if fees.len()>32||fees.iter().any(|(k,v)|!asset(&Value::String(k.clone()))||dec(v).is_none()) {return Err(bad())}
 if !get("commissionUnpriced")?.is_boolean() {return Err(bad())}
 let fills=get("fills")?.as_array().ok_or_else(bad)?;
 if fills.is_empty()||fills.len()>ROUND_MAX_FILLS {return Err(bad())}
 let last=closed.unwrap_or(updated);let mut previous=opened;
 for f in fills {
  let f=f.as_object().ok_or_else(bad)?;
  let get=|k:&str|f.get(k).ok_or_else(bad);
  if !exchange_id(get("id")?)||!exchange_id(get("orderId")?)||!asset(get("commissionAsset")?) {return Err(bad())}
  let time=get("time")?.as_i64().filter(|t|*t>=previous&&*t<=last).ok_or_else(bad)?;previous=time;
  if !one_of(get("side")?,&["BUY","SELL"])||get("positionSide")?.as_str()!=Some(side)||!one_of(get("role")?,&["open","add","reduce","close"]) {return Err(bad())}
  if !positive(get("price")?)||!positive(get("qty")?)||!non_negative(get("quoteQty")?) {return Err(bad())}
  if dec(get("commission")?).is_none()||dec(get("realizedPnl")?).is_none() {return Err(bad())}
  if !get("maker")?.is_boolean()||!get("split")?.is_boolean() {return Err(bad())}
 }
 Ok(())
}

#[cfg(test)]
mod tests {
 use super::*;
 use serde_json::json;
 use std::collections::BTreeMap;
 /// 网页画线扩展样式：对象、键短、值是标量或再套对象（≤ 三层）、≤ 4 KB；数组、坏键、超长串、过深、过大一律拒。
 #[test] fn drawing_style_is_a_small_flat_ish_object() {
  assert!(field(DRAWINGS,"style",&json!({"vp":true,"widthPct":30,"up":"#26C6DA80","poc":{"on":true,"width":1.5,"dash":"dashed"},"bg":{"on":false}})));
  assert!(field(DRAWINGS,"style",&json!({})));
  assert!(field(DRAWINGS,"style",&json!({"a":{"b":{"c":1}}})),"三层可以");
  assert!(!field(DRAWINGS,"style",&json!({"a":{"b":{"c":{"d":1}}}})),"四层不行");
  assert!(!field(DRAWINGS,"style",&json!([1])));
  assert!(!field(DRAWINGS,"style",&json!("x")));
  assert!(!field(DRAWINGS,"style",&json!({"levels":[1,2]})),"不收数组");
  assert!(!field(DRAWINGS,"style",&json!({"1x":true})),"键要字母打头");
  assert!(!field(DRAWINGS,"style",&json!({"a-b":true})));
  assert!(!field(DRAWINGS,"style",&json!({"t":"x".repeat(65)})));
  assert!(!field(DRAWINGS,"style",&json!({"n":Value::Null})));
  let big:serde_json::Map<String,Value>=(0..300).map(|i|(format!("k{i}"),json!("#26C6DA80"))).collect();
  assert!(!field(DRAWINGS,"style",&Value::Object(big)),"超过 4 KB");
  assert!(field(DRAWINGS,"style",&Value::Null),"整个清掉可以");
  assert!(!field(SETTINGS,"style",&json!({})),"只在画线集合里认");
 }
 /// 电脑网页独有习惯：对象、≤ 8 KB，别的不管。
 #[test] fn web_prefs_is_any_object_up_to_8kb() {
  assert!(field(SETTINGS,"webPrefs",&json!({"theme":"dark","skin":"terra","subs":["macd","cvd","atr"],"links":{"cross":true}})));
  assert!(!field(SETTINGS,"webPrefs",&json!(["dark"])));
  assert!(!field(SETTINGS,"webPrefs",&json!(true)));
  assert!(!field(SETTINGS,"webPrefs/theme",&json!("dark")),"只认整个对象");
  assert!(!field(SETTINGS,"webPrefs",&json!({"x":"y".repeat(WEB_PREFS_MAX_BYTES)})));
 }
 #[test] fn venue_identity_is_not_a_route() {
  assert!(identity("binance","usd_m","BTCUSDT"));
  assert!(identity("coinbase","spot","BTC-USD"));
  // 2026-10-08：OKX / Bybit / Hyperliquid 是自己的一家（不再是币安的替身），各认各的代号。
  assert!(identity("okx","usd_m","BTCUSDT")&&identity("bybit","usd_m","1000PEPEUSDT")&&identity("hyperliquid","usd_m","KPEPE"));
  for (v,m,s) in [("coinbase","usd_m","BTC-USD"),("binance","spot","BTCUSDT"),("coinbase","spot","BTC-USDC"),("okx","spot","BTCUSDT"),
   ("okx","usd_m","BTC-USDT-SWAP"),("okx","usd_m","BTCUSDC"),("bybit","usd_m","BTCUSD"),("hyperliquid","usd_m","kPEPE"),("hyperliquid","usd_m","BTC-USD"),("ftx","usd_m","BTCUSDT")] {assert!(!identity(v,m,s),"{v}/{m}/{s}")}
  let mut a=alert(&[("market",json!("hyperliquid/usd_m")),("symbol",json!("BTC"))]);
  a.id="hyperliquid/usd_m/BTC/A1".into(); assert!(object(&a).is_ok());
  assert!(field("alerts","market",&json!("okx/usd_m"))&&!field("alerts","market",&json!("okx/spot")));
  assert!(field("favorites","venue",&json!("bybit"))&&!field("favorites","venue",&json!("ftx")));
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
 /// 美元指数（2026-10-05）：`macro/index` 只收 `DXY`，自选、画线、价格 / 画线提醒、对比四处
 /// 同一条规则；条件提醒仍只认币安，别的交易所 / 市场 / 代号的搭配一律拒。
 #[test] fn macro_index_dxy_syncs_everywhere_a_symbol_can() {
  assert!(identity("macro","index","DXY"));
  for (v,m,s) in [("macro","index","EURUSD"),("macro","index","dxy"),("macro","usd_m","DXY"),("macro","spot","DXY"),
   ("binance","index","DXY"),("binance","usd_m","DXY"),("coinbase","spot","DXY"),("macro","index","BTCUSDT")] {assert!(!identity(v,m,s),"{v}/{m}/{s}")}
  // 自选
  let mut f=Object{collection:"favorites".into(),id:"macro/index/DXY".into(),body:BTreeMap::from([("venue".into(),json!("macro")),("market".into(),json!("index")),("symbol".into(),json!("DXY"))]),fields:BTreeMap::new(),revision:0,deleted:false,generation:0};
  assert!(object(&f).is_ok());
  f.id="binance/usd_m/DXY".into(); assert!(object(&f).is_err());
  f.id="macro/index/DXY".into(); f.body.insert("symbol".into(),json!("EURUSD")); assert!(object(&f).is_err());
  // 画线
  let mut d=drawing("hline",1);
  d.id="macro/index/DXY/line-1".into();
  d.body.insert("venue".into(),json!("macro")); d.body.insert("market".into(),json!("index")); d.body.insert("symbol".into(),json!("DXY"));
  assert!(object(&d).is_ok());
  d.body.insert("market".into(),json!("usd_m")); assert!(object(&d).is_err());
  // 价格提醒与画线提醒
  let mut a=alert(&[("kind",json!("price")),("market",json!("macro/index")),("symbol",json!("DXY")),("title",json!("美元指数 价格达到 100"))]);
  a.id="macro/index/DXY/A1".into(); assert!(object(&a).is_ok());
  a.id="binance/usd_m/DXY/A1".into(); assert!(object(&a).is_err());
  let mut a=alert(&[("market",json!("macro/index")),("symbol",json!("DXY")),("drawingID",json!("macro/index/DXY/hline-1"))]);
  a.id="macro/index/DXY/A2".into(); assert!(object(&a).is_ok());
  assert!(field("alerts","market",&json!("macro/index")));
  assert!(!field("alerts","market",&json!("macro/usd_m")));
  assert!(!field("alerts","market",&json!("binance/index")));
  // 条件提醒：数据只来自币安，美元指数上一样拒。
  let mut c=alert(&[("kind",json!("condition")),("market",json!("macro/index")),("symbol",json!("DXY")),("lines",json!([])),
   ("rule",json!({"type":"funding","side":"above","rate":"0.0005"}))]);
  c.id="macro/index/DXY/C1".into(); assert!(object(&c).is_err());
  // 对比
  assert!(field("settings","compareSymbols",&json!(["macro/index/DXY","binance/usd_m/BTCUSDT"])));
  for bad in [json!(["macro/index/EURUSD"]),json!(["macro/usd_m/DXY"]),json!(["binance/index/DXY"]),json!(["macro/index/DXY","macro/index/DXY"])] {
   assert!(!field("settings","compareSymbols",&bad),"{bad}");
  }
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

 /// **主力订单流的取值范围和客户端是同一组数。** 客户端认为合法、服务端拒掉的值会让那条
 /// 设置操作整条 400、从此同步不上去；反过来服务端放过客户端不认的值，读回时被 `normalized` 丢掉。
 #[test] fn order_flow_limits_are_the_contract_ones() {
  let contract:Value=serde_json::from_str(CONTRACT).expect("contract/settings-fields.json is not valid JSON");
  let of=&contract["orderFlow"];
  assert!(of.is_object(),"contract has no `orderFlow` section; run `make sync-contract` from the repo root");
  let f=|k:&str|of[k].as_f64().unwrap_or_else(||panic!("orderFlow.{k} missing"));
  assert_eq!((f("thresholdMin"),f("thresholdMax")),ORDER_FLOW_THRESHOLD);
  assert_eq!((f("stepMin"),f("stepMax")),ORDER_FLOW_STEP);
  assert_eq!(of["maxOverrides"].as_u64(),Some(ORDER_FLOW_MAX_OVERRIDES as u64));
  assert_eq!(of["baseMaxLength"].as_u64(),Some(ORDER_FLOW_BASE_MAX_LEN as u64));
  let keys:Vec<&str>=of["overrideKeys"].as_array().expect("orderFlow.overrideKeys").iter().map(|v|v.as_str().unwrap()).collect();
  let mut ours:Vec<&str>=ORDER_FLOW_THRESHOLD_KEYS.to_vec(); ours.push("step");
  assert_eq!(keys,ours);
  // 边界本身合法、刚出界不合法：常量真的是校验在用的那组数。
  let (lo,hi)=ORDER_FLOW_THRESHOLD;
  assert!(order_flow_overrides(&json!({"BTC":{"spot":lo,"delivery":hi,"step":ORDER_FLOW_STEP.0}})));
  assert!(!order_flow_overrides(&json!({"BTC":{"spot":lo*0.999}})));
  assert!(!order_flow_overrides(&json!({"BTC":{"step":ORDER_FLOW_STEP.1*1.001}})));
  let long="A".repeat(ORDER_FLOW_BASE_MAX_LEN);
  assert!(order_flow_overrides(&json!({long.clone():{"spot":lo}})));
  assert!(!order_flow_overrides(&json!({format!("{long}A"):{"spot":lo}})));
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

 /// **Every tool's anchor count is the client's `Drawing.Kind.pointCount`.**
 ///
 /// `anchor_count` is a hand-written match with a `_=>2` default, and the client's
 /// `pointCount` is another; a three-point tool added on one side only would have every line
 /// drawn with it refused (wrong anchor count → the whole operation 400s). The contract is
 /// generated from the client's enum, so it is the side that is right: fix the match arm here.
 /// Only if the contract is stale — someone edited `Drawing.Kind` without regenerating — run
 /// `make sync-contract` from the repo root first.
 #[test] fn anchor_counts_are_the_clients_point_counts() {
  let contract:Value=serde_json::from_str(include_str!("../contract/drawing-fields.json"))
   .expect("contract/drawing-fields.json is not valid JSON; regenerate it with `make sync-contract`");
  let counts=contract["anchorCounts"].as_object().expect("contract/drawing-fields.json has no `anchorCounts`; run `make sync-contract`");
  let mut theirs:Vec<&str>=counts.keys().map(String::as_str).collect(); theirs.sort();
  let mut ours:Vec<&str>=KINDS.to_vec(); ours.sort();
  assert_eq!(ours,theirs,"KINDS is not the set of kinds the client counts anchors for");
  for (kind,count) in counts {
   let n=count.as_u64().expect("anchor count") as usize;
   assert_eq!(anchor_count(kind),n,"anchor_count(\"{kind}\") drifted from the client's pointCount");
   assert!(object(&drawing(kind,n)).is_ok(),"{kind} with {n} anchors should be valid");
   assert!(object(&drawing(kind,n+1)).is_err(),"{kind} with {} anchors should be refused",n+1);
  }
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
  // 收藏的画线工具 2026-10-10 退役：规则随名字删掉（老客户端发上来先被当成未知字段丢掉）。
  assert!(!field("drawingPreferences","favorites",&json!(KINDS.to_vec())));
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
  for bad in ["btcusdt","BTC-USDT",""] {assert!(!field("favorites","symbol",&json!(bad)),"{bad} should be refused")}
  // 单看代号字段只能问「有没有哪一家认它」（`BTCEUR` 是 Hyperliquid coin 名的形状）；是不是币安 U 本位，
  // 由整个对象的 `identity` 判（2026-10-08 起多交易所）。
  assert!(!identity("binance","usd_m","BTCEUR"));
 }
 /// 币安有纯中文底名的 U 本位合约；它们的自选 / 画线 / 提醒以前整条被拒。
 #[test] fn a_binance_symbol_may_carry_a_unicode_base() {
  for good in ["币安人生USDT","我踏马来了USDT","ÅBCUSDT","1000币USDC"] {
   assert!(field("favorites","symbol",&json!(good)),"{good} should be accepted");
   assert!(identity("binance","usd_m",good),"{good} is a binance usd_m identity");
  }
  // 40 个字符是上限，按字符数算：39 个汉字 + USDT 超了，36 个 + USDT 刚好。
  assert!(field("favorites","symbol",&json!(format!("{}USDT","币".repeat(36)))));
  assert!(!field("favorites","symbol",&json!(format!("{}USDT","币".repeat(37)))));
  for bad in ["币安人生","币安人生usdt","币安 人生USDT","币安-人生USDT","😀USDT","btc币USDT"] {
   assert!(!field("favorites","symbol",&json!(bad)),"{bad} should be refused");
   assert!(!identity("binance","usd_m",bad),"{bad} is not a binance usd_m identity");
  }
  // `USDT` 单看是 Hyperliquid coin 名的形状（字段层收），但不是币安合约。
  assert!(!identity("binance","usd_m","USDT"));
  // Coinbase 不变：底名只有 ASCII 大写与数字。
  assert!(identity("coinbase","spot","BTC-USD"));
  assert!(!identity("coinbase","spot","币安-USD"));
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
  assert!(field("settings","skin",&json!("classic")));
  // 2026-10-10 退役的六个键：值规则一起删了，任何值都不认（`sync::RETIRED_SETTINGS_FIELDS`）。
  for (name,value) in [("routePolicy",json!("gateway")),("portraitHeight",json!(0.5)),("styleID",json!("aicoin")),
   ("compactValues",json!(true)),("drawToolGroup",json!("斐波那契")),("indicatorLayouts/hour",json!({"subs":["RSI"]}))] {
   assert!(!field("settings",name,&value),"{name} 已退役");
  }
  // 复盘本停在哪一面 / 哪一档筛选（2026-10-10）。
  for good in ["views","trades"] {assert!(field("settings","reviewSegment",&json!(good)),"reviewSegment {good}")}
  for bad in [json!("stats"),json!(""),json!(null),json!(1),json!(true)] {assert!(!field("settings","reviewSegment",&bad),"reviewSegment {bad}")}
  for good in ["all","todo","decided"] {assert!(field("settings","reviewBookFilter",&json!(good)),"reviewBookFilter {good}")}
  for bad in [json!("records"),json!(""),json!(null),json!(0),json!(false)] {assert!(!field("settings","reviewBookFilter",&bad),"reviewBookFilter {bad}")}
  assert!(field("settings","sectorWindow",&json!("d20"))&&field("settings","sectorMarket",&json!("us")));
  for name in ["favoritesSort","favoritesAscending","favoritesAmount","favoritesSparkline","sectorSort"] {
   assert!(!field("settings",name,&json!("volume"))&&!field("settings",name,&json!(true)),"{name} 已退役（收设置项 G 组）");
  }
  assert!(field("settings","reviewSearchScope",&json!("private"))&&!field("settings","reviewSearchScope",&json!("world")));
  assert!(field("settings","lastDrawTool",&json!(""))&&field("settings","lastDrawTool",&json!("gannFan"))&&!field("settings","lastDrawTool",&json!("laser")));
  assert!(field("settings","drawToolUsage",&json!({}))&&field("settings","drawToolUsage",&json!({"trend":12,"fibonacci":3,"gannFan":0})));
  assert!(field("settings","drawToolUsage",&json!({"hline":100_000})));
  for bad in [json!({"laser":1}),json!({"trend":-1}),json!({"trend":1.5}),json!({"trend":"3"}),json!({"trend":100_001}),
              json!(["trend"]),json!("trend"),json!(null)] {
   assert!(!field("settings","drawToolUsage",&bad),"{bad}");
  }
  let thirteen:serde_json::Map<String,Value>=KINDS.iter().take(13).map(|k|(k.to_string(),json!(1))).collect();
  assert!(!field("settings","drawToolUsage",&Value::Object(thirteen)),"最多十二个键");
  assert!(crate::sync::SETTINGS_FIELDS.contains(&"drawToolUsage"));
  // 「分析」面板节序计次：键只认四个节名。
  assert!(field("settings","analysisUsage",&json!({}))&&field("settings","analysisUsage",&json!({"draw":12,"orderFlow":3,"indicators":0,"compare":7})));
  assert!(field("settings","analysisUsage",&json!({"compare":100_000})));
  for bad in [json!({"trend":1}),json!({"draw":-1}),json!({"draw":1.5}),json!({"draw":"3"}),json!({"draw":100_001}),
              json!(["draw"]),json!("draw"),json!(null)] {
   assert!(!field("settings","analysisUsage",&bad),"analysisUsage {bad}");
  }
  assert!(!field("settings","analysisUsage",&json!({"draw":1,"orderFlow":1,"indicators":1,"compare":1,"alerts":1})),"最多四个键");
  assert!(crate::sync::SETTINGS_FIELDS.contains(&"analysisUsage"));
  // 横屏根间距：和 barSpacing 同一个范围。
  assert!(field("settings","landscapeBarSpacing",&json!(1.6))&&field("settings","landscapeBarSpacing",&json!(40))&&field("settings","landscapeBarSpacing",&json!(9.5)));
  for bad in [json!(1.5),json!(41.0),json!("4"),json!(null),json!(true)] {
   assert!(!field("settings","landscapeBarSpacing",&bad),"landscapeBarSpacing {bad}");
  }
  assert!(crate::sync::SETTINGS_FIELDS.contains(&"landscapeBarSpacing"));
  assert!(field("settings","favoritesGroup",&json!("F1E0A6C2-0000-4000-8000-000000000001"))&&!field("settings","favoritesGroup",&json!("x".repeat(129))));
  assert!(!field("settings","favoritesExpanded",&json!(["BTCUSDT"])),"favoritesExpanded 已退役（审查 U9）");
  // 网页版多套图表布局（2026-10-07）
  let one=json!({"active":"default","sets":[{"id":"default","name":"默认","layout":"1","cells":[{"symbol":"BTCUSDT","iv":"1h"}]}]});
  assert!(field("settings","chartLayouts",&one));
  let two=json!({"active":"l1","sets":[{"id":"default","name":"默认","layout":"4","cells":[{"symbol":"BTCUSDT","iv":"1h","footprint":true},{"symbol":"ETHUSDT","iv":"15m"},{"symbol":"XAUUSDT","iv":"4h","style":"line"},{"symbol":"DXY","iv":"7m"}]},
                                     {"id":"l1","name":"十六图 盯盘","layout":"16","cells":[{"symbol":"SOLUSDT","iv":"1s"}]}]});
  assert!(field("settings","chartLayouts",&two));
  let cells17:Vec<Value>=(0..17).map(|_|json!({"symbol":"BTCUSDT","iv":"1h"})).collect();
  let sets21:Vec<Value>=(0..21).map(|k|json!({"id":format!("l{k}"),"name":"x","layout":"1","cells":[{"symbol":"BTCUSDT","iv":"1h"}]})).collect();
  for bad in [json!({}),json!({"active":"default","sets":[]}),json!({"active":"a b","sets":one["sets"].clone()}),
              json!({"active":"default","sets":one["sets"].clone(),"x":1}),
              json!({"active":"l0","sets":sets21}),
              json!({"active":"d","sets":[{"id":"d","name":"","layout":"1","cells":[{"symbol":"BTCUSDT","iv":"1h"}]}]}),
              json!({"active":"d","sets":[{"id":"d","name":"a","layout":"5","cells":[{"symbol":"BTCUSDT","iv":"1h"}]}]}),
              json!({"active":"d","sets":[{"id":"d","name":"a","layout":"16","cells":cells17}]}),
              json!({"active":"d","sets":[{"id":"d","name":"a","layout":"1","cells":[{"symbol":"B","iv":"1h"}]}]}),
              json!({"active":"d","sets":[{"id":"d","name":"a","layout":"1","cells":[{"symbol":"BTCUSDT","iv":"1h","footprint":1}]}]}),
              json!({"active":"d","sets":[{"id":"d","name":"a","layout":"1","cells":[{"symbol":"BTCUSDT","iv":"1h","x":{"deep":1}}]}]}),
              json!({"active":"d","sets":[{"id":"d","name":"a","layout":"1","cells":[{"symbol":"BTCUSDT","iv":"1h","a":1,"b":1,"c":1,"d":1,"e":1,"f":1,"g":1}]}]}),
              json!([]),json!("default"),json!(true)] {
   assert!(!field("settings","chartLayouts",&bad),"chartLayouts {bad}");
  }
  assert!(crate::sync::SETTINGS_FIELDS.contains(&"chartLayouts"));
  assert!(crate::sync::SETTINGS_FIELDS.contains(&"drawingsHidden"));
  assert!(crate::sync::SETTINGS_FIELDS.contains(&"favoritesTrend"));
  assert!(crate::sync::SETTINGS_FIELDS.contains(&"bigTradeSigns"));
  for flag in ["mainInverted","watchMoveAlert","drawingOverlaysShown","drawingsHidden","favoritesTrend","bigTradeSigns"] {
   assert!(field("settings",flag,&json!(true))&&!field("settings",flag,&json!(1)),"{flag} is a boolean");
  }
 }

 /// `settings.autoLayers`（2026-10-10）：白名单字符串数组，和 `overlays` 同一种规则，外加不许重复。
 #[test] fn auto_layers_are_a_whitelisted_list() {
  assert!(crate::sync::SETTINGS_FIELDS.contains(&"autoLayers"));
  for ok in [json!([]),json!(["FVG"])] {assert!(field("settings","autoLayers",&ok),"autoLayers {ok}")}
  for bad in [json!(["X"]),json!(["fvg"]),json!(["FVG","FVG"]),json!([1]),json!("FVG"),json!(true),json!({"FVG":true}),json!(null)] {
   assert!(!field("settings","autoLayers",&bad),"autoLayers {bad}");
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
  // 从图上加提醒的三个键：备注、Webhook 地址、Webhook 文案模板。
  assert!(field("alerts","note",&json!("突破就加仓"))&&field("alerts","note",&json!("x".repeat(256))));
  assert!(!field("alerts","note",&json!("x".repeat(257)))&&!field("alerts","note",&json!(1)));
  // 256 是字节不是字：86 个汉字是 258 字节。
  assert!(!field("alerts","note",&json!("备".repeat(86))));
  for good in ["https://hooks.example.com/a?b=c","http://1.2.3.4:8080/x"] {assert!(field("alerts","webhook",&json!(good)),"{good}")}
  let long=format!("https://{}",("x".repeat(1024-8)));
  assert!(field("alerts","webhook",&json!(long)));
  assert!(!field("alerts","webhook",&json!(format!("{long}x"))),"超过 1024 字节");
  for bad in ["ftp://example.com","example.com","HTTPS://example.com","https://exa mple.com","https://example.com/\t","https://example.com\n",""] {
   assert!(!field("alerts","webhook",&json!(bad)),"{bad:?}")
  }
  assert!(!field("alerts","webhook",&json!(1)));
  assert!(field("alerts","webhookText",&json!("{品种} {条件} {目标价}，现价 {价格}"))&&field("alerts","webhookText",&json!("x".repeat(1024))));
  assert!(!field("alerts","webhookText",&json!("x".repeat(1025)))&&!field("alerts","webhookText",&json!(false)));
  // 客户端永远写出这三个键，空就是 null：null 必须放行，否则每一条提醒都推不上去。
  for key in ["note","webhook","webhookText"] {assert!(field("alerts",key,&Value::Null),"{key}: null 是空")}
  // 三个键都在白名单上：不在的话服务端静默丢掉，另一台设备就收不到。
  for key in ["note","webhook","webhookText"] {assert!(crate::sync::allowlist("alerts").contains(&key),"{key} 要进 ALERT_FIELDS")}
  // 整条对象带着它们（值或 null）都存得下。
  object(&alert(&[("note",json!("看量")),("webhook",json!("https://hooks.example.com/x")),("webhookText",json!("{品种} {价格}"))])).expect("带备注与 Webhook 的提醒存得下");
  object(&alert(&[("note",Value::Null),("webhook",Value::Null),("webhookText",Value::Null)])).expect("三个键都是 null 也存得下");
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
  for good in [json!([]), json!(["binance/usd_m/ETHUSDT", "coinbase/spot/BTC-USD", "binance/usd_m/1000BONKUSDC"])] {
   assert!(field("settings","compareSymbols",&good));
  }
  for bad in [
   json!(null), json!("binance/usd_m/ETHUSDT"), json!([1]), json!(["ETHUSDT"]),
   json!(["binance/usd_m/ethusdt"]), json!(["binance//ETHUSDT"]),
   json!(["binance/usd_m/ETHUSDT/x"]), json!([" binance/usd_m/ETHUSDT"]),
   json!(["binance/usd_m/ETHUSDT", "binance/usd_m/ETHUSDT"]),
   json!(["binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT", "binance/usd_m/DOGEUSDT", "binance/usd_m/XRPUSDT"]),
   // 认不得的交易所 / 市场，或者交易所与市场配错了：favorites 的 id 也不收。
   json!(["future/spot/ABC"]), json!(["binance/spot/BTCUSDT"]), json!(["coinbase/usd_m/BTC-USD"]),
  ] { assert!(!field("settings","compareSymbols",&bad), "{bad}"); }
 }
 /// 对比 K 线的代号段和自选同一条规则：中文底名的币安合约能收藏就能对比。
 /// 以前 `compare_key` 只收 ASCII，把 `币安人生USDT` 加进对比会让整条 settings 操作 400。
 #[test] fn compare_symbols_follow_the_favorites_symbol_rule() {
  let key=|s:&str|json!([s]);
  for good in ["binance/usd_m/币安人生USDT","binance/usd_m/我踏马来了USDT","binance/usd_m/1000币USDC","binance/usd_m/SPCXUSD1"] {
   assert!(field("settings","compareSymbols",&key(good)),"{good} should be accepted");
   let symbol=good.rsplit('/').next().unwrap();
   assert!(field("favorites","symbol",&json!(symbol)),"compare and favorites must agree on {symbol}");
  }
  assert!(field("settings","compareSymbols",&json!(["binance/usd_m/币安人生USDT","binance/usd_m/ETHUSDT","coinbase/spot/BTC-USD"])));
  // 40 个字符是上限，按字符数：36 个汉字 + USDT 刚好（整键 126 字节，没碰到 128 的粗上限），37 个超了。
  let longest=format!("binance/usd_m/{}USDT","币".repeat(36));
  assert!(longest.len()<=128);
  assert!(field("settings","compareSymbols",&key(&longest)));
  assert!(!field("settings","compareSymbols",&key(&format!("binance/usd_m/{}USDT","币".repeat(37)))));
  assert!(!field("settings","compareSymbols",&key(&format!("binance/usd_m/{}USDT","A".repeat(37)))));
  // 缺底名、缺计价资产、小写、夹空格或横杠、表情：和 favorites 一样拒。
  for bad in ["binance/usd_m/USDT","binance/usd_m/币安人生","binance/usd_m/币安人生usdt","binance/usd_m/币安 人生USDT",
              "binance/usd_m/币安-人生USDT","binance/usd_m/😀USDT","coinbase/spot/-USD","coinbase/spot/币安-USD"] {
   assert!(!field("settings","compareSymbols",&key(bad)),"{bad} should be refused");
  }
  // 币本位 / 交割（`BTCUSD_PERP`、`BTCUSDT_251226`）不是 U 本位永续的代号，按既有规则拒——自选也不收。
  for bad in ["binance/usd_m/BTCUSD_PERP","binance/usd_m/BTCUSDT_251226"] {
   assert!(!field("settings","compareSymbols",&key(bad)),"{bad} should be refused");
   assert!(!field("favorites","symbol",&json!(bad.rsplit('/').next().unwrap())));
  }
  // 同一只中文底名不能出现两次。
  assert!(!field("settings","compareSymbols",&json!(["binance/usd_m/币安人生USDT","binance/usd_m/币安人生USDT"])));
 }
 // 网页图表设置（2026-10-07）：一个对象（空对象 = 全默认），序列化 ≤ 8 KB；别的形状、子路径、null 都不收。
 #[test] fn web_chart_settings_are_one_bounded_object() {
  assert!(field("settings","webChart",&json!({})));
  assert!(field("settings","webChart",&json!({"marginTop":20,"marginBottom":5,"rightBars":30,"bodyUp":"#26A69A","grid":"none"})));
  assert!(field("settings","webChart",&json!({"k":"x".repeat(8000)})));
  assert!(!field("settings","webChart",&json!({"k":"x".repeat(8200)})));
  for bad in [json!([]),json!("x"),json!(1),json!(true),Value::Null] {assert!(!field("settings","webChart",&bad),"{bad}")}
  assert!(!field("settings","webChart/marginTop",&json!(10)));
 }
 // 网页布局格子（审查 2026-10-10 第 6 项）：多交易所的 `venue/market/代号` 和平均 K 线 / 区间 K 线
 // 两个开关，和网页 `validSymbol` / `CELL_FLAGS` 对齐；从前它们一出现整份 chartLayouts 就是坏值。
 #[test] fn chart_layout_cells_take_venue_symbols_and_the_three_flags() {
  let with=|cell:Value|json!({"active":"d","sets":[{"id":"d","name":"a","layout":"1","cells":[cell]}]});
  for good in [json!({"symbol":"okx/usd_m/BTC-USDT-SWAP","iv":"1h"}),json!({"symbol":"hyperliquid/usd_m/BTC","iv":"1h"}),
               json!({"symbol":"coinbase/spot/BTC-USD","iv":"4h","ha":true}),json!({"symbol":"BTCUSDT","iv":"1h","range":false}),
               json!({"symbol":"bybit/usd_m/币安人生USDT","iv":"1h","footprint":true,"ha":true,"range":true}),
               // 三段各取网页上限：20 + 10 + 40，整串 72 字。
               json!({"symbol":format!("{}/{}/{}","v".repeat(20),"m".repeat(10),"S".repeat(40)),"iv":"1h"}),
               // 三个开关不占「以后的格子配置」那 6 个名额。
               json!({"symbol":"BTCUSDT","iv":"1h","footprint":true,"ha":true,"range":true,"a":1,"b":1,"c":1,"d":1,"e":1,"f":1})] {
   assert!(field("settings","chartLayouts",&with(good.clone())),"{good}");
  }
  for bad in [json!({"symbol":"okx/BTCUSDT","iv":"1h"}),json!({"symbol":"okx/usd_m/BTC/X","iv":"1h"}),
              json!({"symbol":"OKX/usd_m/BTC","iv":"1h"}),json!({"symbol":"okx/USD_M/BTC","iv":"1h"}),
              json!({"symbol":"1okx/usd_m/BTC","iv":"1h"}),json!({"symbol":"o/usd_m/BTC","iv":"1h"}),
              json!({"symbol":"okx/usd_m/","iv":"1h"}),json!({"symbol":"okx/usd_m/BTC USDT","iv":"1h"}),
              json!({"symbol":format!("{}/usd_m/BTC","v".repeat(21)),"iv":"1h"}),
              json!({"symbol":format!("okx/{}/BTC","m".repeat(11)),"iv":"1h"}),
              json!({"symbol":format!("okx/usd_m/{}","S".repeat(41)),"iv":"1h"}),
              json!({"symbol":"BTCUSDT","iv":"1h","ha":1}),json!({"symbol":"BTCUSDT","iv":"1h","range":"yes"}),
              json!({"symbol":"BTCUSDT","iv":"1h","a":1,"b":1,"c":1,"d":1,"e":1,"f":1,"g":1})] {
   assert!(!field("settings","chartLayouts",&with(bad.clone())),"{bad}");
  }
 }

 /// 同一只币四家同时在：自选 id、画线 id、提醒的 `market` 各带各的交易所，四个对象互不冒充；
 /// 拿别家的 id 配这一家的 body（或者反过来）整条拒——同步表里它们就不会落在同一行上互相覆盖。
 #[test] fn one_coin_on_four_venues_stays_four_objects() {
  let four=[("binance","BTCUSDT"),("okx","BTCUSDT"),("bybit","BTCUSDT"),("hyperliquid","BTC")];
  let mut ids=std::collections::BTreeSet::new();
  for (venue,symbol) in four {
   let fav=Object{collection:"favorites".into(),id:format!("{venue}/usd_m/{symbol}"),
    body:BTreeMap::from([("venue".into(),json!(venue)),("market".into(),json!("usd_m")),("symbol".into(),json!(symbol))]),fields:BTreeMap::new(),revision:0,deleted:false,generation:0};
   assert!(object(&fav).is_ok(),"{venue}");
   assert!(ids.insert(fav.id.clone()),"自选 id 撞了：{}",fav.id);
   let mut a=alert(&[("market",json!(format!("{venue}/usd_m"))),("symbol",json!(symbol)),("drawingID",json!(format!("{venue}/usd_m/{symbol}/trend-1")))]);
   a.id=format!("{venue}/usd_m/{symbol}/A1");
   assert!(object(&a).is_ok(),"{venue} 的提醒");
   assert!(ids.insert(a.id.clone()));
   let mut d=drawing("hline",1);
   d.id=format!("{venue}/usd_m/{symbol}/line-1");
   d.body.insert("venue".into(),json!(venue));d.body.insert("symbol".into(),json!(symbol));
   assert!(object(&d).is_ok(),"{venue} 的画线");
   for (other,other_symbol) in four.iter().filter(|(o,_)|*o!=venue) {
    let mut f=fav.clone();f.id=format!("{other}/usd_m/{other_symbol}");
    assert!(object(&f).is_err(),"{other} 的 id 配 {venue} 的 body");
    let mut x=a.clone();x.id=format!("{other}/usd_m/{symbol}/A1");
    assert!(object(&x).is_err(),"{other} 的提醒 id 配 {venue}/usd_m 的 market");
    let mut y=d.clone();y.id=format!("{other}/usd_m/{symbol}/line-1");
    assert!(object(&y).is_err(),"{other} 的画线 id 配 {venue} 的 body");
   }
  }
  assert_eq!(ids.len(),8);
 }

 /// 三端交叉契约 `contract/venue-identity-cases.json`：同一组完整键，`accept` 每条服务端都收、`reject` 每条都拒。
 /// 三个入口一起过：对比 K 线的 `compare_key`、按三段拆开的 `identity`、自选对象（id 与 body 三段要一致）。
 /// iOS（`InstrumentSyncIdentityTests`）与网页（`venue-identity-contract.test.ts`）读的是同一个文件。
 #[test] fn venue_identity_contract_cases() {
  let cases:Value=serde_json::from_str(include_str!("../contract/venue-identity-cases.json")).expect("venue-identity-cases.json");
  let list=|k:&str|cases[k].as_array().unwrap_or_else(||panic!("缺 {k}")).iter().map(|v|v.as_str().expect("字符串").to_owned()).collect::<Vec<_>>();
  let (accept,reject)=(list("accept"),list("reject"));
  assert!(accept.len()>=10&&reject.len()>=10,"夹具被删空了");
  let favorite=|key:&str|{
   let mut p=key.splitn(3,'/');
   let (venue,market,symbol)=(p.next().unwrap_or(""),p.next().unwrap_or(""),p.next().unwrap_or(""));
   let f=Object{collection:"favorites".into(),id:key.into(),body:BTreeMap::from([("venue".into(),json!(venue)),("market".into(),json!(market)),("symbol".into(),json!(symbol))]),fields:BTreeMap::new(),revision:0,deleted:false,generation:0};
   object(&f).is_ok()
  };
  let split=|key:&str|{let mut p=key.splitn(3,'/');(p.next().unwrap_or("").to_owned(),p.next().unwrap_or("").to_owned(),p.next().unwrap_or("").to_owned())};
  for key in &accept {
   let (v,m,s)=split(key);
   assert!(compare_key(&json!(key)),"compare_key 该收 {key}");
   assert!(identity(&v,&m,&s),"identity 该收 {key}");
   assert!(favorite(key),"自选该收 {key}");
  }
  for key in &reject {
   let (v,m,s)=split(key);
   assert!(!compare_key(&json!(key)),"compare_key 该拒 {key}");
   assert!(!identity(&v,&m,&s),"identity 该拒 {key}");
   assert!(!favorite(key),"自选该拒 {key}");
  }
  // 每一家（注册表里的每个 `(venue, market)`）都至少有一条 `accept`：新接一家不能只改注册表、不给三端对账的用例。
  for v in crate::venues::venues() {
   let prefix=format!("{}/{}/",v.source(),v.market());
   assert!(accept.iter().any(|k|k.starts_with(&prefix)),"{prefix} 在夹具里一条可收的用例都没有");
  }
  // `accept` 里出现的每一家都在注册表里（和 `contract/instruments.json` 的 `venues` 清单是同一张，见 instruments 的
  // `the_contract_file_is_what_both_sides_use`）。
  for key in &accept {let (v,m,_)=split(key);assert!(crate::venues::listed(&v,&m).is_some(),"{key} 的交易所不在注册表里")}
 }
}
