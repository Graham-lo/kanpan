//! Personal changes only. Market candles never enter this protocol.
use crate::{AppState,auth::Identity,crypto::digest,envelope,error::{ApiError,Result}};
use axum::{Router,Json,extract::{State,Query},routing::{get,post}};
use serde::{Deserialize,Serialize};
use serde_json::{Value,json};
use sqlx::Row;
use std::collections::BTreeMap;
use uuid::Uuid;
use chrono::Utc;

#[derive(Deserialize,Serialize,Clone)]
#[serde(rename_all="camelCase",deny_unknown_fields)]
pub struct Operation {
 pub id:Uuid,pub collection:String,pub object_id:String,pub device_id:Uuid,
 pub base_revision:i64,pub generation:i64,pub timestamp:i64,pub logical:u64,
 pub action:String,#[serde(default)] pub fields:BTreeMap<String,Value>,pub import_batch:Option<Uuid>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Push {operations:Vec<Operation>}
#[derive(Deserialize,Default)]
#[serde(rename_all="camelCase",deny_unknown_fields)]
struct Scope {collection:Option<String>,prefix:Option<String>,after:Option<String>,cursor:Option<i64>}
#[derive(Serialize,Deserialize,Clone,Default)]
#[serde(rename_all="camelCase")]
struct Stamp {revision:i64,timestamp:i64,logical:u64,device_id:String,operation_id:String}
#[derive(Serialize,Deserialize,Clone)]
#[serde(rename_all="camelCase")]
pub struct Object {
 pub collection:String,pub id:String,pub body:BTreeMap<String,Value>,
 pub fields:BTreeMap<String,Value>,pub revision:i64,pub deleted:bool,pub generation:i64,
}
// 集合名只在这里写一次（审查 A4）。服务端别处要点名一个集合——评估器读设置、
// 波动提醒读自选、分享校验画线——一律用这些常量，不再手写字符串：拼错一个字母
// 不会报错，只会安静地读到「这个人什么都没有」。
pub const SETTINGS:&str="settings";
pub const DRAWING_PREFERENCES:&str="drawingPreferences";
pub const DRAWINGS:&str="drawings";
pub const FAVORITES:&str="favorites";
pub const GROUPS:&str="groups";
pub const ALERTS:&str="alerts";
pub const COLLECTIONS:[&str;6]=[SETTINGS,DRAWING_PREFERENCES,DRAWINGS,FAVORITES,GROUPS,ALERTS];
/// `settings` 集合里那一条设置对象的 id（客户端 `PersonalSyncCodec` 固定写 `chart`）。
pub const SETTINGS_OBJECT:&str="chart";
fn collection(v:&str)->Result<()> {if !COLLECTIONS.contains(&v){Err(ApiError::bad("invalid_collection"))}else{Ok(())}}
/// Settings names that used to be on the wire and were deleted from both ends (2026-09-24:
/// `showDrawings` had no switch left and nobody read it; `subHeights` had no writer since pane
/// heights became drag-to-resize `subHeightOverrides`). Production had `showDrawings:true` on
/// every settings object and `subHeights` empty on all of them, so nothing is lost.
///
/// They are **not** in `SETTINGS_FIELDS` any more: a sync push from an older build still
/// carrying them has them dropped and reported in `droppedFields`, like any unknown name. The
/// one place that refuses unknown names outright is a review chart snapshot (`review::validate`),
/// and every older build encodes `showDrawings` into every snapshot — so the snapshot check lets
/// these through instead of 400-ing every review an older build tries to save. Readers ignore
/// them: the client only applies names it still declares.
/// `favoritesExpanded` (2026-09-24, review U9): the favorites page had two detail forms for the
/// same symbol — the inline expansion and the long-press preview card. Only the card is left, so
/// the set of expanded rows has nothing to remember any more.
/// `orderFlowFilledBid/Ask`, `orderFlowCancelledBid/Ask` (2026-09-24, review item 41): the order-flow
/// display switches went from six to four — filled and cancelled are no longer split by side. The
/// client now sends `orderFlowShowFilled` / `orderFlowShowCancelled` and migrates its own archive as
/// bid || ask; stored bodies still carrying the four old names are cleaned on their next merge.
///
/// 2026-09-28「收设置项」（只有必须由用户自己定的才留成设置，其余由客户端定默认、自动适应；
/// 逐项的 Prefs 字段、面板位置与恢复办法见 `.project-memory/PROJECT.md`「收设置项」一节，
/// 收之前的代码在 tag `settings-before-trim-2026-09-28`）：
/// - A 组 `ambientTheme`（按屏幕亮度切深浅）、`timeZone`（全 app 固定上海 UTC+8）、
///   `changeBasis`（涨跌幅口径按品种类型自动定）、`keepAwake`（图表页在前台就常亮）。
/// - B 组（图表设置）`magnet`（十字线常吸附）、`countdown` / `lastLine` / `sinceChange`（常开）、
///   `gridChoice`（按皮肤：经典不画、青苔 / 陶土淡网格）、`bodyChoice`（实心）、`viewAnchor`（靠右）、
///   `priceBias`（居中）、`dataDisplay`（顶部）、`crossPrice`（选中价）、`allowMainInversion` /
///   `allowSubInversion`（翻转手势直接生效）、`adaptiveIndicators`（常开）。
/// - 复盘 `replaySpeed`（回放倍速）：每一趟按要走的根数自动挑 1 / 2 / 4×（整趟 20–40 秒），
///   回放条上那颗倍速键只改这一趟、不再存。
/// - C 组（指标）`hiddenOutputs`（指标编辑页「输出」开关，线一律全画）、`rsiRange`（客户端
///   `rsiUpper` / `rsiLower` 合成的键，RSI 超买超卖线定在 70 / 30）。`indicatorLayouts/<组>`
///   里嵌着的 `hiddenOutputs` 仍按老规则放行（老客户端还会发），新客户端读时忽略。
/// - D 组（主力订单流）`orderFlowSpot` / `orderFlowContract` / `orderFlowShowFilled` /
///   `orderFlowShowCancelled`：四个显示开关收掉，一律全画（现货合约按色分、已成交满色、没吃到的淡一档）。
/// - E 组（提醒）`watchMoveThreshold`：自选波动提醒的幅度不再让人填，按每只自己最近一天的
///   1 分钟波动自动定（`watch_move::auto_threshold`，客户端同一个公式）。
/// - G 组（自选页 / 板块页）`favoritesSort` / `favoritesAscending` / `favoritesAmount`（自选页
///   2026-09-25 起就没有排序 UI，永远按自选顺序、涨跌写涨跌幅）、`favoritesSparkline`（行尾迷你
///   走势开关，收掉后不画）、`sectorSort`（板块品种列表一律按当前窗口涨跌幅降序）。
pub const RETIRED_SETTINGS_FIELDS:&[&str]=&["showDrawings","subHeights","favoritesExpanded",
 "orderFlowFilledBid","orderFlowFilledAsk","orderFlowCancelledBid","orderFlowCancelledAsk",
 // 收设置项 A 组（2026-09-28）。
 "ambientTheme","timeZone","changeBasis","keepAwake",
 // 收设置项 B 组（2026-09-28）。
 "magnet","countdown","lastLine","sinceChange","gridChoice","bodyChoice","viewAnchor","priceBias",
 "dataDisplay","crossPrice","allowMainInversion","allowSubInversion","adaptiveIndicators",
 // 收设置项 · 复盘（2026-09-28）。
 "replaySpeed",
 // 收设置项 C 组（2026-09-28）。
 "hiddenOutputs","rsiRange",
 // 收设置项 D 组（2026-09-28）。
 "orderFlowSpot","orderFlowContract","orderFlowShowFilled","orderFlowShowCancelled",
 // 收设置项 E 组（2026-09-28）。
 "watchMoveThreshold",
 // 收设置项 G 组（2026-09-28）。
 "favoritesSort","favoritesAscending","favoritesAmount","favoritesSparkline","sectorSort",
 // 同步字段整理（2026-10-10，退役前的代码在 tag `sync-fields-before-retire-2026-10-10`）：
 // `portraitHeight` 三端只读不写、永远 0.5，读端改用出厂值；`styleID` / `drawToolGroup` /
 // `compactValues` / `routePolicy` 是早就不发的四个 wireOnly 键（`routePolicy` 在 iOS 仍是本机字段，只是不再上线）；
 // `indicatorLayouts`（含 `indicatorLayouts/<组>`）是 09-27~10-02 周期分组留下的键，10-03 之前的老客户端已经没了。
 "portraitHeight","styleID","drawToolGroup","compactValues","routePolicy","indicatorLayouts",
];
/// Favorite names deleted from both ends. `pinned` (2026-09-24): the favorites page never had a
/// way to pin anything once custom groups were judged 「不做」, so `setPinned` had no caller and
/// the Widget's pinned-first ordering only ever saw an empty list. Same treatment as the settings
/// ones: an older build pushing it has it dropped and named in `droppedFields`, and stored
/// bodies still carrying it are cleaned on their next merge (see `strip_retired`).
pub const RETIRED_FAVORITE_FIELDS:&[&str]=&["pinned"];
/// 画线偏好里两端删掉的名字。`favorites`（收藏的画线工具，2026-10-10 退役）：09-22 工具砍到十二把、
/// 面板去掉收藏之后就没有入口了，客户端只为兼容一直原样带着它。老客户端推上来照样只丢这个字段并在
/// `droppedFields` 报回，库里老 body 带着的下次合并时洗掉（`strip_retired`）。
pub const RETIRED_DRAWING_PREFERENCE_FIELDS:&[&str]=&["favorites"];
/// Retired names, per collection.
pub fn retired_fields(c:&str)->&'static [&'static str] {
 match c {SETTINGS=>RETIRED_SETTINGS_FIELDS,FAVORITES=>RETIRED_FAVORITE_FIELDS,DRAWING_PREFERENCES=>RETIRED_DRAWING_PREFERENCE_FIELDS,_=>&[]}
}
/// First path segment is a retired name in that collection (`subHeights/MACD` counts).
pub fn retired_field(c:&str,path:&str)->bool {retired_fields(c).contains(&path.split('/').next().unwrap_or_default())}
/// First path segment is a retired settings name (`subHeights/MACD` counts).
pub fn retired_settings_field(path:&str)->bool {retired_field(SETTINGS,path)}
/// Take retired names out of a stored object before it is validated and written back.
///
/// Without this, retiring a name is a trap: the value rule goes away with the name, but every
/// body already in the database still carries it (production had `showDrawings:true` on all 66
/// settings objects), so `sync_validation::object` finds a key with no rule and 400s *every*
/// later merge onto that object with `invalid_sync_value` — nothing the person changes syncs
/// again. Readers already ignore these names, so dropping them loses nothing; an older build
/// reading the cleaned body falls back to its own default, which is what production held.
pub fn strip_retired(object:&mut Object) {
 let c=object.collection.clone();
 object.body.retain(|k,_|!retired_field(&c,k));
 object.fields.retain(|k,_|!retired_field(&c,k));
}
/// 把库里**存量**的、按现行值规则已经不合规的字段洗掉（连同它的字段戳），返回洗掉了哪几个。
///
/// 和 `strip_retired` 是同一类陷阱的另一半（审查 2026-10-10 第 4 项）：值规则一收紧，云端存量
/// 老值就再也过不了 `sync_validation::object` 那一道整份校验，于是这条对象之后的**每一次**
/// 写入都 400——用户改的是别的字段，被拒的理由却是一个他早就没碰过的旧值。准入校验只该管
/// 「这一次写进来的」，那一半已经在 `validate` 里做过了（宽容集合的坏值在 `admit` 里丢掉），
/// 所以走到这里还不合规的只可能是存量；洗掉它，读的一方按自己的默认值走，和退役字段同一个姿态。
/// 在 `merge` 里跑，位置在字段合并、`clear_tombstones` / `strip_retired` 之后、整份校验之前。
pub fn strip_invalid(object:&mut Object)->Vec<String> {
 let c=object.collection.clone();
 let bad:Vec<String>=object.body.iter().filter(|(k,v)|!crate::sync_validation::field(&c,k,v)).map(|(k,_)|k.clone()).collect();
 for k in &bad {object.body.remove(k);object.fields.remove(k);}
 bad
}
/// 值规则不过时**只丢这个字段**、不拒整条操作的集合。
///
/// 设置与画线工具偏好是两个单例大对象，几十个互不相干的字段挤在一条对象上：一个字段的值
/// 永久不合规（客户端比服务端先放宽了规则、或者服务端规则写紧了），从前是整条 400，客户端
/// 把这条操作隔离、拒绝记录按对象锁住整个设置——别处的改动从此进不了本机，每轮全量还要
/// 再吃一次 400（审查 2026-10-10 第 3 项）。现在照未知字段那条路：丢掉、在 `droppedFields`
/// 里报回，另在 `invalidFields` 里点名是「值不对」而不是「不认识」，其余字段照常合并。
/// 画线、提醒、自选这些对象的字段彼此牵连（锚点数对不上种类、提醒没有线就是死提醒），
/// 丢一个字段等于存下一份半截的对象，所以仍然整条拒。
pub fn lenient(c:&str)->bool {matches!(c,SETTINGS|DRAWING_PREFERENCES)}
// One enumerable allowlist per collection, mirroring what iOS actually sends.
//
// `settings` is not a hand-copy any more: it must equal, name for name, the `wireKeys` array
// in `contract/settings-fields.json`, which `make sync-contract` generates from the single
// table on the client (`PrefsFieldPlan.table`, Kanpan/Kanpan/Settings/Model/PrefsFieldPlan.swift).
// `the_allowlist_is_what_ios_sends` reads that file with `include_str!` and fails loudly on any
// drift, so the two sides can no longer disagree in silence — which is exactly how commit
// a161bb0 happened: this list was nineteen names short, and because an operation carrying an
// unknown field used to be refused whole, that account never synced anything again.
//
// A name here still needs a value rule in `sync_validation::field`, or the field is a poison
// pill: the `_=>false` fallthrough 400s the whole operation. `every_wire_key_has_a_value_rule`
// is the guard for that half.
//
// A slice rather than `[&str;N]`: adding a field should not also mean editing a length.
pub const SETTINGS_FIELDS:&[&str]=&[
 "compareSymbols",
 "overlays","subs","subHeightOverrides","params","indicatorColors",
 // `indicatorLayouts`、`portraitHeight`、`styleID`、`compactValues`、`routePolicy`（2026-10-10）在 RETIRED_SETTINGS_FIELDS 里。
 "quickIntervals","theme","skin","redUp","priceMode",
 "depth","orderFlow","orderFlowHistory","candleKind",
 "barSpacing","mainInverted","subInverted","interval",
 // How the person left each page looking: which category, which market, which tool.
 // 自选排序 / 迷你走势与板块排序（收设置项 G 组）在 RETIRED_SETTINGS_FIELDS 里。
 // Which category the favorites page is parked on. It used to live in the phone's own symbol
 // archive (`SymbolPrefs.selectedGroupID`), so it never followed the person to a second device.
 "favoritesGroup",
 "sectorMarket","sectorWindow","lastDrawTool","reviewSearchScope",
 // 复盘本「观点 / 交易」停在哪一面、筛选停在「全部 / 待判定 / 已判定」哪一档（2026-10-10，跟人走）。
 // `drawToolGroup`（2026-10-10）在 RETIRED_SETTINGS_FIELDS 里。
 "reviewSegment","reviewBookFilter",
 "alertSound",
 // 自选五分钟波动提醒（P3.1）：开关。幅度按波动自动定，`watchMoveThreshold` 已退役。
 "watchMoveAlert",
 // 主力订单流（2026-09-24 逐单模型）：用户改过门槛 / 步长的那几只 base（整张表一个键）。
 // 服务端只校验、不读。四个显示开关（以及更早按买卖拆开的旧键）在 RETIRED_SETTINGS_FIELDS 里。
 "orderFlowOverrides",
 // 条件提醒（docs/条件提醒-协议-2026-09-27.md 第 6 节）：设置 › 通知里「品种上新与下架」开关。
 // 服务端 `listing_watch.rs` 读它；2026-09-27 客户端已生成进契约（原先挂在 SERVER_AHEAD_SETTINGS_FIELDS 里）。
 "notifyListingChanges",
 // 「按我的习惯自动调整」（2026-09-28）：开关 + 学到的结论（整份一个对象，≤ 16 KB，
 // 规则见 `sync_validation::learned_defaults`）。行为日志只在手机上，不上传。
 "habitLearning","learnedDefaults",
 // 横屏画线台顶行「指标」胶囊：画线台里主图指标画不画（2026-10-05，布尔）。
 "drawingOverlaysShown",
 // 画线条上露哪几把：每把画线工具用了几次（2026-10-05，对象，规则见契约 `rules.drawToolUsage`）。
 "drawToolUsage",
 // 「分析」面板四节按用得多少排：每节用了几次（2026-10-08，对象，规则见契约 `rules.analysisUsage`）。
 "analysisUsage",
 // 横屏自己记的根间距（2026-10-05，pt，1.6…40，同 barSpacing）：横屏图宽是竖屏两倍多，两边各记一份。
 "landscapeBarSpacing",
 // 画线面板「隐藏画线」（2026-10-06，布尔）：看行情时把画线整片藏起来，提醒照常。
 // 不复用已退役的 `showDrawings`（RETIRED_SETTINGS_FIELDS 里，老客户端写的是另一种语义）。
 "drawingsHidden",
 // 设置 › 通用「自选走势线」（2026-10-08，布尔）：自选行上那条 24 小时迷你走势，出厂开。
 // 不复用已退役的 `favoritesSparkline`（RETIRED_SETTINGS_FIELDS 里，老客户端写的是另一种语义）。
 "favoritesTrend",
 // 主力订单流「图上大单签」（2026-10-08，布尔）：大单主动成交按根在 K 线高 / 低外标签，出厂开；和挂单墙 `orderFlow` 互不依赖。
 "bigTradeSigns",
 // 「分析」面板的自动分析层（2026-10-10，跟人走）：字符串数组，白名单见契约 `rules.autoLayers`（目前只有公允价值缺口 FVG）。
 "autoLayers",
 // 电脑网页版的多套图表布局（2026-10-07，整份布局集一个对象，规则见 `sync_validation::chart_layouts`）。
 // 只有网页版读写，不在 iOS 的 PrefsFieldPlan 契约里，见 WEB_ONLY_SETTINGS_FIELDS。
 "chartLayouts",
];
/// 只有网页版读写、不进 iOS 契约（`contract/settings-fields.json` 由 iOS `PrefsFieldPlan` 生成）的设置字段。
/// 手机端原样留着不认识的键，所以它们不会被手机抹掉；对账测试把契约 ∪ 这张表当成白名单应有的样子。
pub const WEB_ONLY_SETTINGS_FIELDS:&[&str]=&["chartLayouts"];
/// 服务端先行上线、客户端还没 `make sync-contract` 进契约的设置字段。
///
/// 服务端总是先于客户端部署，所以一个新设置在一段时间里只在这边有。对账测试把契约
/// ∪ 这张表当成「客户端会发的」；客户端把它生成进契约之后，这里那一项就是冗余的，
/// 删掉即可（留着也不会让测试变红）。这里只能放**已经在 SETTINGS_FIELDS 里、并且有值规则**的名字。
pub const SERVER_AHEAD_SETTINGS_FIELDS:&[&str]=&[];
/// 只有网页端（PC 浏览器）发的设置字段：不在 iOS 契约里，所以不进 `SETTINGS_FIELDS`（那张表和契约一一对上），
/// 单列在这里，`known_field` 认它、`sync_validation::field` 给值规则。
/// `webChart`（2026-10-07）：网页「图表设置」（照 TradingView 的商品 / 状态栏 / 比例尺与线 / 画布），
/// 只存和默认值不同的那几项，一个对象、序列化 ≤ 8 KB。手机端不读。
/// `webPrefs`（2026-10-10）：电脑网页用手改出来、别的端没有的习惯（自己的皮肤 / 深浅、网页独有指标的开关与参数、
/// 超出共用字段上限的周期 / 副图、联动、侧栏与抽屉、订单流面板偏好、副图高与网格比例……），一个对象、序列化 ≤ 8 KB；
/// 里面的键由网页自己清洗（Web/src/sync/webPrefs.ts）。手机端不读、原样留着。
pub const WEB_SETTINGS_FIELDS:&[&str]=&["webChart","webPrefs"];
/// 只有网页端写的画线字段：不在 iOS 的画线契约（contract/drawing-fields.json）里，所以不进 `DRAWING_FIELDS`
/// （那张表和契约一一对上），单列在这里，`known_field` 认它、`sync_validation::field` 给值规则。
/// `style`（2026-10-10）：TradingView 设置里主字段之外的扩展样式（成交量分布四色与各条线、延伸、可见周期……），
/// 一个对象、序列化 ≤ 4 KB、键与值类型受限（`sync_validation::drawing_style`）。手机端不认、原样留着。
pub const WEB_DRAWING_FIELDS:&[&str]=&["style"];
// `variants/<palette tool>` is the drawing method last picked for that family in the style sheet
// (trend → extended, hline → hray, vline → crossLine): the next line from that tool is drawn that way.
// `favorites`（收藏的画线工具）2026-10-10 退役，见 RETIRED_DRAWING_PREFERENCE_FIELDS。
pub const DRAWING_PREFERENCE_FIELDS:[&str;4]=["magnet","continuous","styles","variants"];
// `text` is the note/callout/flag caption; `created` only old archives carry.
// Checked against `contract/drawing-fields.json` (`syncFields` + `legacySyncFields`, generated from what
// the client's `PersonalSyncCodec.drawings` really sends) by `drawing_fields_are_what_the_codec_sends`.
pub const DRAWING_FIELDS:[&str;14]=["kind","symbol","market","venue","anchors","color","lineWidth","dash","filled","levels","locked","hidden","created","text"];
pub const FAVORITE_FIELDS:[&str;6]=["symbol","market","venue","groupId","order","alerts"];
pub const GROUP_FIELDS:[&str;3]=["name","order","members"];
// 提醒（方案文档 2.2 的整张表）。`condition` 的两档（`touch` / `close`）两侧评估器都判。
// `kind` 里的 `price` 只进白名单与值规则：客户端没有入口能产生它，这张表也没给它放
// 目标价的字段，所以两侧评估器都**显式**挡住它（`alerts::materialize` 的注释、客户端
// `AlertEvaluator.hit`）——要开这个入口，先去把那两处的判定实现掉。
//
// 注意 `market` 在这个集合里是 `"binance/usd_m"` 整串，而 `drawings`/`favorites` 的
// `market` 是 `"usd_m"`、场所另放在 `venue`。这不是笔误，是方案文档 2.2 写死的形状，
// 所以值规则也按集合分开写——把两者混成一条规则会让客户端发上来的整条 op 400。
pub const ALERT_FIELDS:[&str;19]=[
 "kind","symbol","market","drawingID","lines","condition","armedAt","once",
 "status","firedAt","firedPrice","dueAt","reviewID","title","created",
 // 从图上加提醒：备注、Webhook 地址、Webhook 文案模板（值规则见 sync_validation）。
 "note","webhook","webhookText",
 // 条件提醒（`kind:"condition"`）的条件本体：费率 / 持仓量 / 均线 / 大单 / 技术指标。
 // 形状见 docs/条件提醒-协议-2026-09-27.md 第 2 节与 `conditions::Rule`。
 "rule",
];
pub fn allowlist(c:&str)->&'static [&'static str] {
 match c {SETTINGS=>SETTINGS_FIELDS,DRAWING_PREFERENCES=>&DRAWING_PREFERENCE_FIELDS,DRAWINGS=>&DRAWING_FIELDS,FAVORITES=>&FAVORITE_FIELDS,GROUPS=>&GROUP_FIELDS,ALERTS=>&ALERT_FIELDS,_=>&[]}
}
// Malformed paths are rejected; unknown-but-well-formed names are only dropped.
fn valid_path(path:&str)->bool {!path.is_empty() && path.len()<=160 && !path.split('/').any(|p|p.is_empty()||p==".."||p.starts_with('_'))}
fn known_field(c:&str,path:&str)->bool {let h=path.split('/').next().unwrap_or_default();allowlist(c).contains(&h)||(c==SETTINGS&&WEB_SETTINGS_FIELDS.contains(&h))||(c==DRAWINGS&&WEB_DRAWING_FIELDS.contains(&h))}
impl Operation {
 /// Well-formed paths this server has never heard of. A newer client always runs
 /// ahead of a deployed server, and rejecting the whole operation left it in the
 /// client's queue forever, so the field is dropped and reported back instead.
 pub fn unknown_fields(&self)->Vec<String> {
  self.fields.keys().filter(|k|!known_field(&self.collection,k)).cloned().collect()
 }
 /// 宽容集合（见 [`lenient`]）里认得、但值过不了规则的字段。别的集合永远是空的。
 pub fn invalid_fields(&self)->Vec<String> {
  if !lenient(&self.collection) {return vec![]}
  // 超过单字段 64 KB 的不算「值不对」而算滥用，留给 `validate` 整条拒，不在回执里体面地丢掉。
  self.fields.iter().filter(|(k,v)|valid_path(k)&&known_field(&self.collection,k)&&!crate::sync_validation::field(&self.collection,k,v)
   &&serde_json::to_vec(v).is_ok_and(|s|s.len()<=64_000)).map(|(k,_)|k.clone()).collect()
 }
 /// 推送路径上的准入：把宽容集合里值不对的字段从这条操作里拿掉，返回（拿掉之后的操作，拿掉了哪几个）。
 ///
 /// `validate` 本身仍是严格的（复盘快照、单测都靠它判「这个值对不对」），宽容只发生在这一步：
 /// 拿掉之后的那条再交给 `validate` / `merge`，幂等摘要仍按客户端发来的原样算。
 pub fn admit(&self)->(Operation,Vec<String>) {
  let invalid=self.invalid_fields();
  let mut admitted=self.clone();
  for k in &invalid {admitted.fields.remove(k);}
  (admitted,invalid)
 }
 /// 回执里 `droppedFields` 的那张表：不认识的（含退役的）加上值不对被丢掉的，按名字排好、不重复。
 pub fn dropped_fields(&self,invalid:&[String])->Vec<String> {
  let mut all:Vec<String>=self.unknown_fields();
  all.extend(invalid.iter().cloned());
  all.sort();all.dedup();all
 }
 pub fn validate(&self)->Result<()> {
  collection(&self.collection)?;
  // 技术指标提醒的条件不对，回具体的错误码（带中文原因），不折成笼统的 invalid_operation。
  if self.collection==ALERTS && let Some(code)=self.fields.get("rule").and_then(crate::conditions::indicators::rejection) {
   return Err(ApiError::bad(code))
  }
  if self.object_id.is_empty()||self.object_id.len()>180||self.base_revision<0||self.generation<0||self.logical>i64::MAX as u64||self.timestamp<0
   || !matches!(self.action.as_str(),"patch"|"delete"|"restore") || self.fields.len()>256
   || self.fields.keys().any(|k|!valid_path(k))
   || self.fields.iter().any(|(k,v)|known_field(&self.collection,k)&&!crate::sync_validation::field(&self.collection,k,v))
   || self.fields.values().any(|v|serde_json::to_vec(v).map_or(true,|s|s.len()>64_000)) {return Err(ApiError::bad("invalid_operation"))}
  Ok(())
 }
}
pub fn merge(mut object:Object,op:&Operation,now:i64)->Result<Object> {
 op.validate()?;
 if op.base_revision>object.revision || op.generation!=object.generation {return Err(ApiError::conflict("resync_required"))}
 if op.action=="restore" {
  if !object.deleted||op.base_revision!=object.revision {return Err(ApiError::conflict("resync_required"))}
  object.deleted=false;object.generation+=1;
 } else if op.action=="delete" {object.deleted=true;}
 else if object.deleted {return Ok(object)}
 let next=object.revision+1;
 if !object.deleted {
  for (path,value) in &op.fields {
   if !known_field(&op.collection,path) {continue}
   let previous=object.fields.get(path).and_then(|s|serde_json::from_value::<Stamp>(s.clone()).ok());
   if op.import_batch.is_some()&&object.body.contains_key(path) {continue}
   let stamp=Stamp{revision:next,timestamp:op.timestamp.min(now+300_000),logical:op.logical,device_id:op.device_id.to_string(),operation_id:op.id.to_string()};
   let accept=previous.as_ref().is_none_or(|old|op.base_revision>=old.revision || (stamp.timestamp,stamp.logical,&stamp.device_id,&stamp.operation_id)>(old.timestamp,old.logical,&old.device_id,&old.operation_id));
   if accept {object.body.insert(path.clone(),value.clone());object.fields.insert(path.clone(),json!(stamp));}
  }
 }
 crate::sync_validation::clear_tombstones(&mut object);
 strip_retired(&mut object);
 // 这一条写进来的值上面 `validate` 已经判过；还过不了规则的只可能是库里的存量，洗掉、记一笔，不拒这次写入。
 // 删了的对象不洗：`sync_validation::object` 也不看它，留到 restore 那一次合并再洗。
 if !object.deleted {
  let washed=strip_invalid(&mut object);
  if !washed.is_empty() {tracing::warn!(collection=%object.collection,id=%object.id,fields=?washed,"Sync merge: stored values no longer valid were washed out");}
 }
 if let Some(v)=object.body.get("lineWidth")&& !v.as_f64().is_some_and(|n|n>0.0&&n<=12.0){return Err(ApiError::bad("invalid_line_width"))}
 crate::sync_validation::object(&object)?;
 object.revision=next;Ok(object)
}
pub fn routes()->Router<AppState> {
 Router::new().route("/v1/sync/bootstrap",get(bootstrap)).route("/v1/sync/changes",get(changes)).route("/v1/sync/operations",post(push))
}
fn object(r:&sqlx::postgres::PgRow)->Result<Object> {
 Ok(Object{collection:r.get("collection"),id:r.get("id"),body:serde_json::from_value(r.get("body"))?,fields:serde_json::from_value(r.get("fields"))?,revision:r.get("revision"),deleted:r.get("deleted"),generation:r.get("generation")})
}
/// 这个人的同步日志的串行闸。评估器触发时也要先拿它（`alerts::fire`），
/// 而且要在拿行锁**之前**拿，和 `push` 同一个顺序——否则 worker 与 API 两条路
/// 会以相反的顺序拿同两把锁，那就是教科书上的死锁。
pub async fn lock(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid)->Result<()> {
 sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))").bind(format!("sync:{owner}")).execute(&mut **tx).await?;Ok(())
}
// ------------------------------------------------------------ 服务端的出入口
//
// `sync_objects` 只有这个文件直接读写（审查 A4）。服务端别的模块要看一个人同步上来的
// 东西，走 `read_object` / `live_objects`；要以服务端身份改一条，走 `apply_server_op`。
// 这样「删了的不算」「body 是 json 对象」这些约定只在一处，别处不会各写一版 SQL。

/// 一条**还活着**的同步对象（删了的当作没有）。调用方在自己的个人事务里调用。
pub async fn read_object(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid,collection:&str,id:&str)->Result<Option<Object>> {
 let row=sqlx::query("SELECT * FROM sync_objects WHERE user_id=$1 AND collection=$2 AND id=$3 AND NOT deleted")
  .bind(owner).bind(collection).bind(id).fetch_optional(&mut **tx).await?;
 row.as_ref().map(object).transpose()
}
/// 这个人某个集合里全部还活着的对象，按 id 排序。只给小集合用（自选、分组）。
pub async fn live_objects(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid,collection:&str)->Result<Vec<Object>> {
 let rows=sqlx::query("SELECT * FROM sync_objects WHERE user_id=$1 AND collection=$2 AND NOT deleted ORDER BY id")
  .bind(owner).bind(collection).fetch_all(&mut **tx).await?;
 rows.iter().map(object).collect()
}
/// 这个人的设置对象的 body（评估器取提醒声音、波动提醒的开关与幅度）。没有就是 `None`。
pub async fn settings_body(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid)->Result<Option<Value>> {
 Ok(read_object(tx,owner,SETTINGS,SETTINGS_OBJECT).await?.map(|o|json!(o.body)))
}
/// 「导出我的数据」里的同步那一段：全部活着的对象，连同字段戳与最后修改时间。
///
/// 按数据库给出的 JSON 原文交回去（`::text`），不在进程里解析成 JSON 树：导出只是
/// 原样转交，树只会把内存摊大几倍（见 `export.rs` 顶上的说明）。
pub async fn export(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid)->Result<Box<serde_json::value::RawValue>> {
 let text:String=sqlx::query_scalar("SELECT coalesce(jsonb_agg(jsonb_build_object('collection',collection,'id',id,'body',body,'fields',fields,'revision',revision,'changedAt',changed_at) ORDER BY collection,id),'[]')::text FROM sync_objects WHERE user_id=$1 AND NOT deleted")
  .bind(owner).fetch_one(&mut **tx).await?;
 Ok(serde_json::value::RawValue::from_string(text)?)
}

// ------------------------------------------------------------------ 保留窗口

/// 推送回执（`sync_operations`）留多久。回执只为一件事存在：客户端发出去一条 op、
/// 没收到回话，拿同一个 op id 重发时，服务端原样交回上一次的结果而不是再合并一遍。
/// 客户端的发件箱几秒到几天内就会重试完；一个月前的回执没有人会再来要（审查 A2）。
pub const OPERATION_RETENTION_DAYS:i32=30;
/// 变更日志（`sync_changes`）留多久。现在的客户端只用 bootstrap（整页拉取）、不走
/// `/v1/sync/changes`，所以截断碰不到它们；将来走增量的客户端落后超过这个窗口，
/// 会拿到 410 `cursor_expired` 再重新 bootstrap（审查 A3）。
pub const CHANGE_RETENTION_DAYS:i32=30;

/// 这个人的回执与变更日志各按窗口截一次。maintenance 每小时对每个人调一次。
///
/// 删的时候拿着 `lock` 那一把（和 push / changes 同一把）：水位和删除必须对 `changes` 原子可见——
/// 否则一次 `changes` 可能读到旧水位、却撞上已经删掉的那几行，悄悄漏一段改动。
/// 每个人**最新的那一行变更永远不删**：bootstrap 交出去的游标是 max(sequence)，
/// 那一行没了，游标会退回 0、落到水位以下，刚 bootstrap 完的设备立刻就「过期」。
/// 返回这一批删掉的（回执数，变更数）；这个人正在同步、这一轮让开了，也是 (0, 0)。
///
/// 这把锁是这个人所有 push / changes / bootstrap 的串行闸，API 那边等它只等 5 秒
/// （serve 的 lock_timeout），等不到就回 503。清理是晚一小时也无妨的活，所以它**不许**
/// 把这把锁攥久。2026-09-30 压测 C 实测：worker 刚起的那轮清理里，一条一行都没删掉的
/// 回执 DELETE 跑了 146 秒（原来按人筛回执没有索引可走，每个人都要把整张回执表的堆页
/// 读一遍，而那会儿 IO 正被检查点与全局清理占满），这段时间这个人的 162 次同步全是 503。
/// 所以现在是三道关：
/// 1. 先**不拿锁**看一眼有没有到期的（`past_window`）。回执和变更只会越来越老、不会有新写进来的
///    老行，「没有」的结论不会被并发的 push 推翻；绝大多数人、绝大多数小时到这里就结束了，
///    根本不碰那把锁。这一眼走 (user_id, created_at) 索引（迁移 0034 / 0035），只读几个索引页。
/// 2. 有到期的才去拿锁，而且只**试**一次：这个人正在同步就让他，下一小时再来。
/// 3. 拿到了，这个事务里每条语句最多 2 秒（worker 连接池本身不设语句死线）：两条删除加起来
///    也短于 API 那边的 5 秒；超时就整批回滚、记一笔，下一小时再来。
pub async fn prune(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid,limit:i64)->Result<(u64,u64)> {
 if !past_window(tx,owner).await? {return Ok((0,0))}
 let locked:bool=sqlx::query_scalar("SELECT pg_try_advisory_xact_lock(hashtextextended($1,0))").bind(format!("sync:{owner}")).fetch_one(&mut **tx).await?;
 if !locked {tracing::info!(%owner,"Cleanup: this person is syncing right now, pruning waits for the next round");return Ok((0,0))}
 sqlx::query("SET LOCAL statement_timeout='2s'").execute(&mut **tx).await?;
 // 一次最多删 `limit` 行（`maintenance` 一批一个事务地滚，见 `maintenance::in_batches`）：
 // 攒了几个月的回执一条 DELETE 删完，锁和 WAL 都会一下子冲上去，还把这个人的 push 堵在锁后面。
 let receipts=sqlx::query("DELETE FROM sync_operations WHERE ctid IN (SELECT ctid FROM sync_operations \
   WHERE user_id=$1 AND created_at<now()-make_interval(days=>$2) LIMIT $3)")
  .bind(owner).bind(OPERATION_RETENTION_DAYS).bind(limit).execute(&mut **tx).await?.rows_affected();
 // 变更按 sequence 从老到新删，水位随之一步步往上抬，不会先删掉中间一段、把还在那之前的游标提前判过期。
 let changes:i64=sqlx::query_scalar("WITH gone AS (\
   DELETE FROM sync_changes WHERE ctid IN (SELECT ctid FROM sync_changes WHERE user_id=$1 AND created_at<now()-make_interval(days=>$2) \
    AND sequence<(SELECT max(sequence) FROM sync_changes WHERE user_id=$1) ORDER BY sequence LIMIT $3) RETURNING sequence), \
  floor AS (INSERT INTO sync_change_floors(user_id,sequence) SELECT $1,max(sequence) FROM gone HAVING count(*)>0 \
   ON CONFLICT(user_id) DO UPDATE SET sequence=GREATEST(sync_change_floors.sequence,EXCLUDED.sequence),updated_at=now() RETURNING 1) \
  SELECT count(*) FROM gone")
  .bind(owner).bind(CHANGE_RETENTION_DAYS).bind(limit).fetch_one(&mut **tx).await?;
 Ok((receipts,u64::try_from(changes).unwrap_or(0)))
}
/// 这个人有没有过了保留窗口、该删的回执或变更（最新的那一行变更不算，见 `prune`）。不拿锁。
async fn past_window(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid)->Result<bool> {
 Ok(sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM sync_operations WHERE user_id=$1 AND created_at<now()-make_interval(days=>$2)) \
   OR EXISTS(SELECT 1 FROM sync_changes WHERE user_id=$1 AND created_at<now()-make_interval(days=>$3) \
    AND sequence<(SELECT max(sequence) FROM sync_changes WHERE user_id=$1))")
  .bind(owner).bind(OPERATION_RETENTION_DAYS).bind(CHANGE_RETENTION_DAYS).fetch_one(&mut **tx).await?)
}
/// 这个人的变更日志从哪里往后是完整的：`sequence` 不大于它的变更可能已经删掉了。
async fn floor(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid)->Result<i64> {
 Ok(sqlx::query_scalar::<_,i64>("SELECT sequence FROM sync_change_floors WHERE user_id=$1").bind(owner).fetch_optional(&mut **tx).await?.unwrap_or(0))
}
/// 游标落在水位以下：它要的那一段（cursor, floor] 可能已经不在了，只能重新 bootstrap。
/// 正好等于水位不算过期——要的是 floor 之后的，一行都没删。
fn expired(cursor:i64,floor:i64)->bool {cursor<floor}
fn cursor_expired()->ApiError {ApiError(axum::http::StatusCode::GONE,"cursor_expired")}

/// 以服务端自己的身份改一条同步对象，走的是和客户端 op 完全一样的那条路。
///
/// 评估器判定触发之后要把 `status=fired` 告诉这个人的每一台设备，而设备只认同步日志：
/// 不写 `sync_changes`，手机下次拉取时什么都收不到，界面上那条提醒会一直显示「活动」。
/// 所以这里不是直接 UPDATE 一行，而是拼一条 op 交给 `merge` ——校验、LWW 戳、
/// 游标一样都不少，客户端读到的东西和别的改动没有区别。
///
/// `device_id` 是全零：那不是任何一台真设备，客户端的「这条是我自己刚发的」判断因此
/// 不会把它当成回声丢掉。调用方必须**已经**拿了 `lock`（本文件 `push` 的同一把）。
///
/// 对象不存在就报错而不是新建：服务端只会去改一条客户端已经同步上来的提醒。
pub async fn apply_server_op(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,owner:Uuid,collection:&str,object_id:&str,fields:BTreeMap<String,Value>)->Result<Object> {
 let row=sqlx::query("SELECT * FROM sync_objects WHERE user_id=$1 AND collection=$2 AND id=$3 FOR UPDATE").bind(owner).bind(collection).bind(object_id).fetch_optional(&mut **tx).await?;
 let Some(row)=row else {return Err(ApiError::bad("unknown_object"))};
 let old=object(&row)?;
 let now=Utc::now().timestamp_millis();
 let op=Operation{id:Uuid::new_v4(),collection:collection.into(),object_id:object_id.into(),device_id:Uuid::nil(),
  base_revision:old.revision,generation:old.generation,timestamp:now,logical:0,action:"patch".into(),fields,import_batch:None};
 let next=merge(old,&op,now)?;
 sqlx::query("INSERT INTO sync_objects(user_id,collection,id,body,fields,revision,deleted,generation) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(user_id,collection,id) DO UPDATE SET body=excluded.body,fields=excluded.fields,revision=excluded.revision,deleted=excluded.deleted,generation=excluded.generation,changed_at=now()")
  .bind(owner).bind(&next.collection).bind(&next.id).bind(json!(next.body)).bind(json!(next.fields)).bind(next.revision).bind(next.deleted).bind(next.generation).execute(&mut **tx).await?;
 sqlx::query("INSERT INTO sync_changes(user_id,collection,object_id,revision,deleted) VALUES($1,$2,$3,$4,$5)").bind(owner).bind(&next.collection).bind(&next.id).bind(next.revision).bind(next.deleted).execute(&mut **tx).await?;
 Ok(next)
}
/// `POST /v1/sync/operations` 的查询串。`rejections=inline`：一条操作自己的毛病只拒它这一条，
/// 写进它那一格结果（见 [`rejection`]），同一批里其余的照常合并、照常提交。
///
/// 不带这个参数的老客户端照旧：任何一条有毛病就整批 400——它们只会读成功回执的形状，
/// 一格 `status:"rejected"` 会被当成解码失败，那比整批 400 更糟。
#[derive(Deserialize,Default)]
#[serde(deny_unknown_fields)]
struct PushMode {rejections:Option<String>}
/// 能落到「这一条」头上的错：值不对、设备不对、品种认不得、幂等摘要对不上。
/// 409 `resync_required` / `batch_already_claimed` 和 5xx 仍是整批的事，照旧整批回。
fn per_operation(e:&ApiError)->bool {e.0==axum::http::StatusCode::BAD_REQUEST||e.1=="idempotency_mismatch"}
/// 一条被拒的操作在结果里的那一格。不进 `sync_operations`：拒绝不是回执，客户端改好了用同一个 id 重发要能重新判。
fn rejection(id:Uuid,e:&ApiError)->Value {
 let mut r=json!({"operationId":id,"status":"rejected","code":e.1});
 if let Some(m)=crate::error::message(e.1) {r["message"]=json!(m)}
 r
}
/// 一条操作进合并之前的准入：自己的值、这台设备、指标提醒的品种。纯函数，单测直接打它。
/// `op` 是 `admit` 拿掉宽容集合坏值之后的那条。
fn screen(op:&Operation,device:Uuid,unlisted:&std::collections::BTreeSet<String>)->Result<()> {
 op.validate()?;
 // 设备不对是这条操作的事，不是这一批的事：手机冷启动那一下用旧设备号记的改动、退出再登回来
 // 遗留的那几条，客户端收到这一格会把未发出的改成当前设备号重发（审查 2026-10-10 第 1、5 项）。
 if op.device_id!=device {return Err(ApiError::bad("invalid_device"))}
 if crate::conditions::indicators::symbol_of(&op.collection,&op.object_id,&op.action,&op.fields).is_some_and(|s|unlisted.contains(&s)) {
  return Err(ApiError::bad(crate::conditions::indicators::code::SYMBOL))
 }
 Ok(())
}
async fn push(State(s):State<AppState>,i:Identity,crate::error::Params(mode):crate::error::Params<PushMode>,Json(v):Json<Push>)->Result<Json<Value>> {
 if v.operations.is_empty()||v.operations.len()>100{return Err(ApiError::bad("invalid_batch"))}
 let inline=mode.rejections.as_deref()==Some("inline");
 // 技术指标提醒只判币安 U 本位里正在交易的品种。查合约表可能出站，所以在开事务、上锁之前做。
 let indicator_symbols:Vec<String>=v.operations.iter().filter_map(|op|crate::conditions::indicators::symbol_of(&op.collection,&op.object_id,&op.action,&op.fields)).collect();
 let unlisted=crate::conditions::indicators::unlisted(&indicator_symbols).await;
 let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 let device:Uuid=sqlx::query_scalar("SELECT device_id FROM account_sessions WHERE id=$1 AND user_id=$2 AND revoked_at IS NULL").bind(i.session).bind(i.user).fetch_optional(&mut *tx).await?.ok_or_else(ApiError::unauthorized)?;
 let mut results=vec![];
 // 客户端报上来的「响了」要替它发的 Webhook（`alerts::materialize`）。事务提交之后才发：
 // 回滚了就当没报过，客户端重推时再发，不会多一封。
 let mut fires=vec![];
 for op in v.operations {
  // 幂等摘要按客户端发来的原样算（拿掉坏值之前），重发同一条才对得上。
  let hash=digest(serde_json::to_vec(&op)?);
  // 先看回执：已经落过库的那一条原样交回，哪怕它是换设备之前、旧会话发的——
  // 那一次早就合并过了，现在再按设备号拒它，客户端只会把一条已经生效的改动当成失败。
  if let Some(r)=sqlx::query("SELECT digest,result FROM sync_operations WHERE user_id=$1 AND id=$2").bind(i.user).bind(op.id).fetch_optional(&mut *tx).await? {
   if r.get::<String,_>("digest")!=hash {
    let e=ApiError::conflict("idempotency_mismatch");
    if inline {results.push(rejection(op.id,&e));continue}
    return Err(e)
   }
   results.push(r.get::<Value,_>("result"));continue
  }
  let (admitted,invalid)=op.admit();
  if let Err(e)=screen(&admitted,device,&unlisted) {
   if inline&&per_operation(&e) {results.push(rejection(op.id,&e));continue}
   return Err(e)
  }
  if !invalid.is_empty() {tracing::info!(collection=%op.collection,fields=?invalid,"Sync push: invalid values dropped from the operation");}
  if let Some(batch)=op.import_batch {
   sqlx::query("INSERT INTO sync_claims(batch_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING").bind(batch).bind(i.user).execute(&mut *tx).await?;
   let claimed:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM sync_claims WHERE batch_id=$1 AND user_id=$2)").bind(batch).bind(i.user).fetch_one(&mut *tx).await?;
   if !claimed{return Err(ApiError::conflict("batch_already_claimed"))}
  }
  let row=sqlx::query("SELECT * FROM sync_objects WHERE user_id=$1 AND collection=$2 AND id=$3 FOR UPDATE").bind(i.user).bind(&op.collection).bind(&op.object_id).fetch_optional(&mut *tx).await?;
  let old=match row {Some(ref r)=>object(r)?,None=>Object{collection:op.collection.clone(),id:op.object_id.clone(),body:BTreeMap::new(),fields:BTreeMap::new(),revision:0,deleted:false,generation:0}};
  // `merge` 是纯函数，失败时这条什么都还没写，跳过它、接着合并下一条是安全的。
  let next=match merge(old,&admitted,Utc::now().timestamp_millis()) {
   Ok(next)=>next,
   Err(e) if inline&&per_operation(&e)=>{results.push(rejection(op.id,&e));continue}
   Err(e)=>return Err(e),
  };
  sqlx::query("INSERT INTO sync_objects(user_id,collection,id,body,fields,revision,deleted,generation) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(user_id,collection,id) DO UPDATE SET body=excluded.body,fields=excluded.fields,revision=excluded.revision,deleted=excluded.deleted,generation=excluded.generation,changed_at=now()")
   .bind(i.user).bind(&next.collection).bind(&next.id).bind(json!(next.body)).bind(json!(next.fields)).bind(next.revision).bind(next.deleted).bind(next.generation).execute(&mut *tx).await?;
  // 提醒对象落库的同一口气里刷新物化表：评估器读的是 alert_watches，不是 sync_objects。
  // 放在同一个事务里，所以「同步成功了但评估器还在用旧几何」这个中间态不存在——
  // 用户把被提醒的线拖到别处、客户端用同一个 alert id 重传 lines，下一帧就是新形状。
  if next.collection==ALERTS {fires.extend(crate::alerts::materialize(&mut tx,i.user,&next).await?);}
  let cursor:i64=sqlx::query_scalar("INSERT INTO sync_changes(user_id,collection,object_id,revision,deleted) VALUES($1,$2,$3,$4,$5) RETURNING sequence").bind(i.user).bind(&next.collection).bind(&next.id).bind(next.revision).bind(next.deleted).fetch_one(&mut *tx).await?;
  let result=receipt(&op,&next,cursor,&invalid);
  sqlx::query("INSERT INTO sync_operations(user_id,id,digest,result) VALUES($1,$2,$3,$4)").bind(i.user).bind(op.id).bind(hash).bind(&result).execute(&mut *tx).await?;results.push(result);
 }
 tx.commit().await?;
 crate::alerts::send_reported(fires);
 Ok(envelope(json!({"results":results,"serverTime":Utc::now().timestamp_millis()})))
}
/// 一条合并成功的操作的回执。
///
/// `droppedFields` is always present, so a client can tell "this server does not
/// report drops" (field absent) from "nothing was dropped" (empty list). Older
/// clients decode it as an unknown key and ignore it.
/// 它是「不认识的」与「值不对的」两类的并集；`invalidFields` 单独点出后一类——客户端对这一类
/// 不该再重发同一个值（发多少次都还是被丢），而前一类等服务端升级之后是会落地的。
fn receipt(op:&Operation,next:&Object,cursor:i64,invalid:&[String])->Value {
 json!({"operationId":op.id,"object":next,"cursor":cursor,"droppedFields":op.dropped_fields(invalid),"invalidFields":invalid})
}
async fn bootstrap(State(s):State<AppState>,i:Identity,Query(v):Query<Scope>)->Result<Json<Value>> {
 if let Some(c)=&v.collection{collection(c)?}
 // Default bootstrap contains only small personal settings. Histories require an explicit scope.
 let c=v.collection.unwrap_or_else(||SETTINGS.into());
 let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 // 主键 (user_id,collection,id) 就够了，前缀这一条是过滤器、不指望走索引。
 // 0007 曾经为它建过 sync_objects_prefix（…,id text_pattern_ops）：那种操作符族按字节
 // 序比较，只有在字节序下 starts_with() 才降得成范围扫；可这个库是 en_US.utf8，下面这句
 // `ORDER BY id` 走的是默认排序规则，和它对不上。于是规划器每次都选主键（边扫边出序、
 // LIMIT 101 立刻停），把前缀降级成 Filter——实测 Rows Removed by Filter: 200，那条索引
 // 从建出来到被删（0011）一次都没被用过。真要让前缀走索引，得连同 ORDER BY 一起改成
 // `COLLATE "C"`，而分页游标的顺序是协议的一部分，不值得为一个过滤条件动它。
 let rows=sqlx::query("SELECT * FROM sync_objects WHERE user_id=$1 AND collection=$2 AND ($3::text IS NULL OR starts_with(id,$3)) AND ($4::text IS NULL OR id>$4) ORDER BY id LIMIT 101")
  .bind(i.user).bind(c).bind(v.prefix).bind(v.after).fetch_all(&mut *tx).await?;
 let more=rows.len()>100;let objects=rows.iter().take(100).map(object).collect::<Result<Vec<_>>>()?;
 // 水位是兜底：prune 永远留着每个人最新的一行，正常情况下 max(sequence) 不会低于水位；
 // 真低了（手工删过日志），交出去的游标也不能一出门就是过期的。
 let cursor:i64=sqlx::query_scalar::<_,i64>("SELECT COALESCE(max(sequence),0) FROM sync_changes WHERE user_id=$1").bind(i.user).fetch_one(&mut *tx).await?
  .max(floor(&mut tx,i.user).await?);
 let next=if more {objects.last().map(|o|o.id.clone())}else{None};tx.commit().await?;
 Ok(envelope(json!({"objects":objects,"next":next,"cursor":cursor,"serverTime":Utc::now().timestamp_millis()})))
}
async fn changes(State(s):State<AppState>,i:Identity,Query(v):Query<Scope>)->Result<Json<Value>> {
 if let Some(c)=&v.collection{collection(c)?}
 let cursor=v.cursor.unwrap_or(0);if cursor<0{return Err(ApiError::bad("invalid_cursor"))}
 let mut tx=s.personal(i.user).await?;lock(&mut tx,i.user).await?;
 if expired(cursor,floor(&mut tx,i.user).await?) {return Err(cursor_expired())}
 // One join instead of one query per changed row. A device coming back after a
 // long trip made up to 201 extra round trips inside a single locked
 // transaction, which is also how long every other device of that user waited.
 // The join condition carries the subscription filter, so a row outside the
 // scope simply has no object attached and stays an invalidation.
 let rows=sqlx::query("SELECT c.sequence,c.collection,c.object_id,c.revision,c.deleted,o.body AS current_body,o.fields AS current_fields,o.revision AS current_revision,o.deleted AS current_deleted,o.generation AS current_generation FROM sync_changes c LEFT JOIN sync_objects o ON o.user_id=c.user_id AND o.collection=c.collection AND o.id=c.object_id AND c.collection IS NOT DISTINCT FROM $3::text AND ($4::text IS NULL OR starts_with(c.object_id,$4)) WHERE c.user_id=$1 AND c.sequence>$2 ORDER BY c.sequence LIMIT 201")
  .bind(i.user).bind(cursor).bind(v.collection.as_deref()).bind(v.prefix.as_deref()).fetch_all(&mut *tx).await?;
 let has_more=rows.len()>200;let next=rows.iter().take(200).last().map(|r|r.get::<i64,_>("sequence")).unwrap_or(cursor);
 let mut items=vec![];let mut invalidations=vec![];
 for r in rows.iter().take(200) {
  let c:String=r.get("collection");let id:String=r.get("object_id");
  let subscribed=v.collection.as_ref().is_some_and(|want|want==&c)&&v.prefix.as_ref().is_none_or(|p|id.starts_with(p));
  if subscribed {
   // Absent here means the object row vanished under us, which the old
   // fetch_one reported the same way.
   let body:Option<Value>=r.get("current_body");let body=body.ok_or(sqlx::Error::RowNotFound)?;
   items.push(Object{collection:c,id,body:serde_json::from_value(body)?,fields:serde_json::from_value(r.get::<Value,_>("current_fields"))?,revision:r.get("current_revision"),deleted:r.get("current_deleted"),generation:r.get("current_generation")});
  }else{invalidations.push(json!({"collection":c,"id":id,"deleted":r.get::<bool,_>("deleted"),"revision":r.get::<i64,_>("revision")}));}
 }
 tx.commit().await?;Ok(envelope(json!({"objects":items,"invalidations":invalidations,"cursor":next,"hasMore":has_more,"serverTime":Utc::now().timestamp_millis()})))
}

#[cfg(test)]
mod tests {
 use super::*;
 /// 游标低于水位才算过期；等于水位时要的是水位之后的，一行都没删。
 #[test] fn a_cursor_below_the_floor_has_expired() {
  assert!(!expired(0,0),"从没截断过的人，游标 0 照样能从头拉");
  assert!(!expired(120,120)&&!expired(121,120));
  assert!(expired(119,120)&&expired(0,120));
  let e=cursor_expired();assert_eq!((e.0,e.1),(axum::http::StatusCode::GONE,"cursor_expired"));
 }
 /// 两个窗口都比客户端任何一次重试长得多，也不能是零（零等于每小时清空回执）。
 #[test] fn retention_windows_are_a_month() {
  assert_eq!((OPERATION_RETENTION_DAYS,CHANGE_RETENTION_DAYS),(30,30));
 }
 /// 集合名常量就是协议里的那六个，每个都有白名单；拼错的名字没有白名单。
 // 网页独有的设置字段：认得（不进 droppedFields、能存进对象），但不在和 iOS 契约对账的 SETTINGS_FIELDS 里。
 #[test] fn web_only_settings_fields_are_known_but_not_in_the_ios_contract() {
  for name in WEB_SETTINGS_FIELDS {
   assert!(!SETTINGS_FIELDS.contains(name),"{name}");
   assert!(known_field(SETTINGS,name),"{name}");
   assert!(!known_field(FAVORITES,name),"{name}");
  }
  assert!(op(SETTINGS,&[("webChart",json!({"marginTop":20}))]).unknown_fields().is_empty());
  assert!(op(SETTINGS,&[("webPrefs",json!({"theme":"dark","links":{"cross":true}}))]).unknown_fields().is_empty());
  assert!(op(SETTINGS,&[("webPrefs",json!("dark"))]).validate().is_err());
  assert_eq!(applied(SETTINGS,&[("webPrefs",json!({"skin":"terra"}))]).body["webPrefs"],json!({"skin":"terra"}));
  assert!(op(SETTINGS,&[("webChart",json!([1]))]).validate().is_err());
  assert_eq!(applied(SETTINGS,&[("webChart",json!({"marginTop":20}))]).body["webChart"],json!({"marginTop":20}));
 }
 // 网页独有的画线字段（style）：认得、能存，但不在和 iOS 画线契约对账的 DRAWING_FIELDS 里。
 #[test] fn web_only_drawing_fields_are_known_but_not_in_the_ios_contract() {
  for name in WEB_DRAWING_FIELDS {
   assert!(!DRAWING_FIELDS.contains(name),"{name}");
   assert!(known_field(DRAWINGS,name),"{name}");
   assert!(!known_field(SETTINGS,name)&&!known_field(FAVORITES,name),"{name}");
  }
  assert!(op(DRAWINGS,&[("style",json!({"vp":true,"poc":{"on":true,"color":"#FF0000"}}))]).unknown_fields().is_empty());
  assert!(op(DRAWINGS,&[("style",json!([1]))]).validate().is_err());
  // 清掉扩展样式发 null：要收（不然网页「恢复默认」整条 400）
  assert!(op(DRAWINGS,&[("style",Value::Null)]).validate().is_ok());
 }
 #[test] fn every_collection_constant_has_an_allowlist() {
  assert_eq!(COLLECTIONS,["settings","drawingPreferences","drawings","favorites","groups","alerts"]);
  for c in COLLECTIONS {assert!(!allowlist(c).is_empty(),"{c}");assert!(collection(c).is_ok())}
  assert!(allowlist("alert").is_empty()&&collection("alert").is_err());
 }
 fn op(collection:&str,fields:&[(&str,Value)])->Operation {
  Operation{id:Uuid::nil(),collection:collection.into(),object_id:"chart".into(),device_id:Uuid::nil(),
   base_revision:0,generation:0,timestamp:1,logical:1,action:"patch".into(),
   fields:fields.iter().map(|(k,v)|((*k).to_string(),v.clone())).collect(),import_batch:None}
 }
 fn blank(collection:&str,id:&str)->Object {
  Object{collection:collection.into(),id:id.into(),body:BTreeMap::new(),fields:BTreeMap::new(),revision:0,deleted:false,generation:0}
 }
 fn applied(collection:&str,fields:&[(&str,Value)])->Object {merge(blank(collection,"chart"),&op(collection,fields),1_800_000_000_000).unwrap()}
 /// The cross-language contract, generated from the client's one table by `make sync-contract`.
 ///
 /// Compiled in, not read at run time: `include_str!` resolves against this source file, so the
 /// test cannot be broken by whatever directory cargo happens to be invoked from, and a missing
 /// or unparseable contract is a compile error rather than a test that quietly skips.
 const CONTRACT:&str=include_str!("../contract/settings-fields.json");

 /// The wire keys the contract says exist, sorted.
 /// **The drawings allowlist is what the client's codec sends, plus the keys only old archives carry.**
 ///
 /// `DRAWING_FIELDS` used to be a third hand-copy of the drawing shape. A key the client starts
 /// encoding that is missing here makes every such line 400 and jam the sync queue behind it.
 /// The contract is generated from real encodes, so it is the side that is right.
 #[test] fn drawing_fields_are_what_the_codec_sends() {
  let contract:Value=serde_json::from_str(include_str!("../contract/drawing-fields.json"))
   .expect("contract/drawing-fields.json is not valid JSON; regenerate it with `make sync-contract`");
  let mut theirs:Vec<String>=contract["syncFields"].as_array().expect("syncFields").iter()
   .map(|v|v.as_str().expect("string").to_string())
   .chain(contract["legacySyncFields"].as_object().expect("legacySyncFields").keys().cloned()).collect();
  theirs.sort();
  let mut ours:Vec<String>=DRAWING_FIELDS.iter().map(|s|s.to_string()).collect(); ours.sort();
  assert_eq!(ours,theirs,"DRAWING_FIELDS drifted from the contract's syncFields + legacySyncFields; \
   edit DRAWING_FIELDS (and give a new key a value rule in sync_validation::field)");
 }
 fn contract_wire_keys()->Vec<String> {
  let contract:Value=serde_json::from_str(CONTRACT)
   .expect("contract/settings-fields.json is not valid JSON; regenerate it with `make sync-contract`");
  assert_eq!(contract["version"],json!(1),
   "contract/settings-fields.json is a format version this test does not know how to read; \
    update both readers (Swift SettingsFieldContract and this test) together");
  let mut keys:Vec<String>=contract["wireKeys"].as_array()
   .expect("contract/settings-fields.json has no `wireKeys` array")
   .iter().map(|v|v.as_str().expect("`wireKeys` must be strings").to_string()).collect();
  keys.sort_unstable();
  keys
 }

 /// **`SETTINGS_FIELDS` ≡ the contract's `wireKeys`, name for name.**
 ///
 /// The settings half used to be a hand-copy of a hand-copy: the same 53 strings lived here, in
 /// `SETTINGS_FIELDS`, and a third time in the iOS test. Three copies only work while three
 /// people all remember to edit them together, and commit a161bb0 is what it costs when they do
 /// not. Now both sides read `contract/settings-fields.json`, which is generated from
 /// `PrefsFieldPlan.table` — the one place a field is declared.
 ///
 /// The other four collections have no client-side table to generate from, so they keep the
 /// written-twice trick: the expectation below is a second copy on purpose.
 #[test] fn the_allowlist_is_what_ios_sends() {
  let mut have:Vec<String>=allowlist("settings").iter().map(|s|s.to_string()).collect();
  have.sort_unstable();
  let mut want=contract_wire_keys();
  for ahead in SERVER_AHEAD_SETTINGS_FIELDS.iter().chain(WEB_ONLY_SETTINGS_FIELDS) {if !want.iter().any(|k|k==ahead) {want.push(ahead.to_string())}}
  want.sort_unstable();
  let missing:Vec<_>=want.iter().filter(|k|!have.contains(k)).collect();
  let extra:Vec<_>=have.iter().filter(|k|!want.contains(k)).collect();
  assert!(missing.is_empty()&&extra.is_empty(),
   "settings allowlist drifted from contract/settings-fields.json.\n\
    in the contract, missing from SETTINGS_FIELDS: {missing:?}\n\
    in SETTINGS_FIELDS, not in the contract:       {extra:?}\n\
    The contract is generated from the client's `PrefsFieldPlan.table`, so it is the side that \
    is right: add each missing name to SETTINGS_FIELDS *and* a value rule for it in \
    sync_validation::field (a name without a rule 400s the whole operation). Only if the \
    contract itself is stale — because someone edited PrefsFieldPlan.table without \
    regenerating — run `make sync-contract` from the repo root first.");

  let expected=[
   ("drawingPreferences",&["magnet","continuous","styles","variants"][..]),
   ("drawings",&["kind","symbol","market","venue","anchors","color","lineWidth","dash","filled","levels","locked","hidden","created","text"][..]),
   ("favorites",&["symbol","market","venue","groupId","order","alerts"][..]),
   ("groups",&["name","order","members"][..]),
   ("alerts",&["kind","symbol","market","drawingID","lines","condition","armedAt","once","status","firedAt","firedPrice","dueAt","reviewID","title","created",
    "note","webhook","webhookText","rule"][..]),
  ];
  for (collection,want) in expected {
   let (mut have,mut want)=(allowlist(collection).to_vec(),want.to_vec());
   have.sort_unstable();want.sort_unstable();
   assert_eq!(have,want,
    "{collection} allowlist drifted. iOS sends `PersonalSyncCodec.drawings`/`symbols` for these; \
     a field added there needs one line in \
     sync::{{DRAWING_PREFERENCE,DRAWING,FAVORITE,GROUP}}_FIELDS, one line in this expectation, \
     and a value rule in sync_validation::field — or the setting silently never reaches the \
     person's other device.");
  }
 }

 /// **Every wire key also has a value rule.** A name on the allowlist that
 /// `sync_validation::field` has no arm for is a poison pill: the `_=>false` fallthrough makes
 /// `validate` reject the *whole* operation with a 400, the client quarantines it, and every
 /// later preference queues up behind it. Being on the allowlist is only half of "supported".
 ///
 /// `field` takes a value, so the only honest way to ask "is there a rule for this name?" is to
 /// offer it values and see whether any is accepted. The probes below cover every shape the
 /// settings rules accept today, at the three path depths settings fields use (top level,
 /// `key/<indicator>`, `key/<indicator>/<slot>`). A new field whose rule accepts none of them
 /// fails here — add a probe for it in the same commit that adds the rule.
 #[test] fn every_wire_key_has_a_value_rule() {
  let probes=[
   json!(true),json!(""),json!(0.5),json!(1),json!(4.0),json!([5]),
   json!(["MA"]),json!(["VOL"]),json!(["FVG"]),json!(["1m"]),json!(["BTCUSDT"]),json!(["binance/usd_m/BTCUSDT"]),json!([30,70]),
   json!("1m"),json!("sage"),json!("custom"),json!("crypto"),json!("today"),json!("views"),json!("todo"),
   json!("change"),json!("history"),json!("medium"),json!({"value":"#112233"}),json!("default"),json!({}),
   json!({"active":"default","sets":[{"id":"default","name":"默认","layout":"1","cells":[{"symbol":"BTCUSDT","iv":"1h"}]}]}),
  ];
  let accepts=|key:&str|{
   [key.to_string(),format!("{key}/MA"),format!("{key}/MA/0"),format!("{key}/hour")].iter()
    .any(|path|probes.iter().any(|v|crate::sync_validation::field("settings",path,v)))
  };
  // The probe sweep would be vacuous if `field` said yes to anything, so prove it discriminates.
  assert!(!accepts("telepathy"),"a name with no rule must be refused for every probe");
  for key in contract_wire_keys().into_iter().chain(SERVER_AHEAD_SETTINGS_FIELDS.iter().chain(WEB_ONLY_SETTINGS_FIELDS).map(|k|k.to_string())) {
   assert!(accepts(&key),
    "`{key}` is on the settings allowlist but sync_validation::field has no rule that accepts \
     any probe value for it. Either the rule is missing — and the field is a poison pill that \
     400s every operation carrying it (see commit a161bb0) — or its rule is real and none of \
     the probes in this test fit its shape, in which case add one.");
  }
 }
 /// 画线工具「这一族上次选的画法」：客户端发的是拍平的 `variants/<面板那一格>`，
 /// 要过白名单（不被当成未知字段丢掉）、过值校验，并且真的合并进对象。
 #[test] fn the_remembered_drawing_method_is_stored() {
  let fields=[("variants/trend",json!("extended")),("variants/hline",json!("hray")),("variants/vline",json!("crossLine"))];
  let operation=op("drawingPreferences",&fields);
  assert!(operation.validate().is_ok());
  assert!(operation.unknown_fields().is_empty());
  let object=applied("drawingPreferences",&fields);
  assert_eq!(object.body["variants/trend"],json!("extended"));
  assert_eq!(object.body["variants/vline"],json!("crossLine"));
  assert!(op("drawingPreferences",&[("variants/trend",json!("telekinesis"))]).validate().is_err());
 }
 /// 同步字段整理（2026-10-10）：`portraitHeight`、四个 wireOnly 键（`styleID` / `drawToolGroup` /
 /// `compactValues` / `routePolicy`）与 `indicatorLayouts`（含拍平的 `indicatorLayouts/<组>`）退役。
 /// 老客户端推上来只丢这几个字段并在回执里点名、同一条里别的照常合并；库里老 body 带着的下次合并洗掉，
 /// 不会因为没有值规则把整条对象拖死。退役前的代码在 tag `sync-fields-before-retire-2026-10-10`。
 #[test] fn retired_2026_10_10_settings_are_dropped_and_stripped() {
  let retired:[(&str,Value);7]=[("portraitHeight",json!(0.5)),("styleID",json!("aicoin")),("drawToolGroup",json!("斐波那契")),
   ("compactValues",json!(true)),("routePolicy",json!("gateway")),
   ("indicatorLayouts/hour",json!({"subs":["RSI"]})),("indicatorLayouts/day",Value::Null)];
  for name in ["portraitHeight","styleID","drawToolGroup","compactValues","routePolicy","indicatorLayouts"] {
   assert!(RETIRED_SETTINGS_FIELDS.contains(&name)&&!SETTINGS_FIELDS.contains(&name),"{name} 应已退役");
  }
  let mut fields:Vec<(&str,Value)>=retired.iter().cloned().collect();
  fields.push(("reviewSegment",json!("trades")));
  let operation=op("settings",&fields);
  assert!(operation.validate().is_ok(),"老版本带着退役字段推上来不能整条 400");
  let mut named=operation.unknown_fields();named.sort();
  let mut expected:Vec<String>=retired.iter().map(|(n,_)|n.to_string()).collect();expected.sort();
  assert_eq!(named,expected);
  assert!(named.iter().all(|k|retired_settings_field(k)),"回执里点名的都是退役名");
  let mut stored=blank("settings","chart");
  for (path,value) in [("portraitHeight",json!(0.5)),("styleID",json!("aicoin")),("drawToolGroup",json!("绘图")),("compactValues",json!(false)),
   ("routePolicy",json!("direct")),("indicatorLayouts/minute",json!({"overlays":["EMA"]})),("indicatorLayouts/hour",json!({"subs":["KDJ"]}))] {
   stored.body.insert(path.into(),value);stored.fields.insert(path.into(),json!({"revision":1}));
  }
  let merged=merge(stored,&operation,1_800_000_000_000).unwrap_or_else(|e|panic!("merge onto an old settings body: {}",e.1));
  assert_eq!(merged.body["reviewSegment"],json!("trades"));
  for key in merged.body.keys().chain(merged.fields.keys()) {
   assert!(!retired_settings_field(key),"{key} 没被清掉");
  }
 }
 /// 复盘本「观点 / 交易」停在哪一面、筛选停在哪一档（2026-10-10，跟人走）：过白名单、过值规则、真的合并；
 /// 认不出的值整条拒（客户端只会发这几个字面量）。
 #[test] fn review_book_position_travels_with_the_account() {
  for (name,good) in [("reviewSegment","views"),("reviewSegment","trades"),("reviewBookFilter","all"),("reviewBookFilter","todo"),("reviewBookFilter","decided")] {
   let operation=op("settings",&[(name,json!(good))]);
   assert!(operation.validate().is_ok(),"{name}={good}");
   assert!(operation.unknown_fields().is_empty());
   assert_eq!(applied("settings",&[(name,json!(good))]).body[name],json!(good));
  }
  for (name,bad) in [("reviewSegment",json!("stats")),("reviewSegment",json!(null)),("reviewBookFilter",json!("records")),("reviewBookFilter",json!(1))] {
   assert!(op("settings",&[(name,bad.clone())]).validate().is_err(),"{name}={bad} 应整条拒");
  }
 }
 /// 画线偏好里的 `favorites`（收藏的画线工具，2026-10-10 退役）：老客户端推上来只丢这个字段、吸附照常合并；
 /// 库里老 body 带着的下次合并洗掉。`retired_fields` 只认它在画线偏好这个集合里。
 #[test] fn retired_drawing_preference_favorites_are_dropped_and_stripped() {
  assert!(!DRAWING_PREFERENCE_FIELDS.contains(&"favorites"));
  assert!(retired_field(DRAWING_PREFERENCES,"favorites")&&!retired_field(DRAWING_PREFERENCES,"magnet"));
  assert!(!retired_field(SETTINGS,"favorites")&&!retired_field(FAVORITES,"favorites"));
  let operation=op("drawingPreferences",&[("favorites",json!(["trend","hline"])),("magnet",json!(true))]);
  assert!(operation.validate().is_ok(),"老版本带着 favorites 推上来不能整条 400");
  assert_eq!(operation.unknown_fields(),vec!["favorites".to_string()]);
  let mut stored=blank("drawingPreferences","drawing");
  stored.body.insert("favorites".into(),json!(["fibonacci"]));stored.fields.insert("favorites".into(),json!({"revision":1}));
  stored.body.insert("continuous".into(),json!(false));
  let merged=merge(stored,&operation,1_800_000_000_000).unwrap_or_else(|e|panic!("merge onto an old drawing preference body: {}",e.1));
  assert_eq!(merged.body["magnet"],json!(true));
  assert!(!merged.body.contains_key("favorites")&&!merged.fields.contains_key("favorites"),"favorites 没被清掉");
 }
 /// 铃声同时通过字段白名单、值校验与实际合并。
 #[test] fn alert_sound_is_accepted_and_invalid_values_are_refused() {
  for sound in ["default","crisp","electronic","glass"] {
   let operation=op("settings",&[("alertSound",json!(sound))]);
   assert!(operation.validate().is_ok());
   assert!(operation.unknown_fields().is_empty());
   assert_eq!(applied("settings",&[("alertSound",json!(sound))]).body["alertSound"],json!(sound));
  }
  for bad in [json!("future"),json!("alert-glass.caf"),json!(null),json!(1),json!(false)] {
   assert!(op("settings",&[("alertSound",bad)]).validate().is_err());
  }
 }
 /// 自选波动提醒的两项设置：过白名单、过值规则、真的合并进去；越界的一律拒。
 #[test] fn order_flow_settings_are_accepted_and_bounded() {
  use crate::sync_validation::field;
  // 六合四：按买卖拆开的四个旧键退役——老版本推上来只丢字段不丢操作，存量 body 合并时洗掉。
  // （合出来的四个显示开关 2026-09-28 也退役了，见 `trimmed_settings_group_d_are_dropped_and_stripped`。）
  let old=op("settings",&[("orderFlowFilledBid",json!(false)),("orderFlowCancelledAsk",json!(false)),("orderFlowOverrides",json!({}))]);
  assert!(old.validate().is_ok(),"老版本带着旧开关推上来不能整条 400");
  let mut dropped=old.unknown_fields();dropped.sort();
  assert_eq!(dropped,vec!["orderFlowCancelledAsk".to_string(),"orderFlowFilledBid".to_string()]);
  let mut stored=blank("settings","chart");
  stored.body.insert("orderFlowCancelledBid".into(),json!(true));
  let merged=merge(stored,&old,1_800_000_000_000).unwrap();
  assert_eq!(merged.body["orderFlowOverrides"],json!({}));
  assert!(!merged.body.contains_key("orderFlowCancelledBid")&&!merged.body.contains_key("orderFlowFilledBid"));
  assert!(SETTINGS_FIELDS.contains(&"orderFlowOverrides"));
  for good in [json!({}),json!({"BTC":{"spot":2000000.0,"step":50}}),json!({"PEPE":{"usdtPerp":1000}}),
               json!({"XAU":{"usdtPerp":1e9,"step":0.00000001},"ETH":{"coinPerp":3e6,"delivery":4e6}})] {
   assert!(field("settings","orderFlowOverrides",&good),"{good}");
  }
  let many:serde_json::Map<String,Value>=(0..201).map(|i|(format!("C{i}"),json!({"spot":1e6}))).collect();
  for bad in [json!(null),json!([]),json!({"btc":{"spot":1e6}}),json!({"":{"spot":1e6}}),json!({"BTC-USDT":{"spot":1e6}}),
              json!({"ABCDEFGHIJKLMNOPQRSTU":{"spot":1e6}}),json!({"BTC":{}}),json!({"BTC":{"spot":999}}),
              json!({"BTC":{"spot":1.1e9}}),json!({"BTC":{"step":0}}),json!({"BTC":{"step":1e7}}),
              json!({"BTC":{"spot":"1000000"}}),json!({"BTC":{"swap":1e6}}),json!({"BTC":1e6}),Value::Object(many)] {
   assert!(!field("settings","orderFlowOverrides",&bad),"{bad}");
  }
 }
 /// 「按我的习惯自动调整」：开关是布尔、结论表按 `learned_defaults` 的规则收，越界的一律拒。
 #[test] fn habit_learning_settings_are_accepted_and_bounded() {
  use crate::sync_validation::field;
  assert!(SETTINGS_FIELDS.contains(&"habitLearning")&&SETTINGS_FIELDS.contains(&"learnedDefaults"));
  let operation=op("settings",&[("habitLearning",json!(false)),("learnedDefaults",json!({}))]);
  assert!(operation.validate().is_ok());
  assert!(operation.unknown_fields().is_empty());
  let merged=merge(blank("settings","chart"),&operation,1_800_000_000_000).unwrap();
  assert_eq!(merged.body["habitLearning"],json!(false));
  assert!(!field("settings","habitLearning",&json!("on")));
  let at=1_790_000_000.5;
  for good in [json!({}),
               json!({"intervals":{"binance/usd_m/BTCUSDT":{"v":"4h","n":3,"at":at}}}),
               json!({"intervals":{"coinbase/spot/ETH-USD":{"v":"8h","n":0,"at":0}},
                      "priceAxis":{"crypto":{"v":"log","n":5,"at":at},"equity":{"v":"linear","n":1,"at":at}},
                      "sectorWindow":{"crypto":{"v":"d5","n":6,"at":at},"us":{"v":"today","n":3,"at":at}},
                      "watchMove":{"binance/usd_m/SOLUSDT":{"v":1.6,"n":4,"at":at},"binance/usd_m/XRPUSDT":{"v":0.5,"n":2,"at":at}}})] {
   assert!(field("settings","learnedDefaults",&good),"{good}");
  }
  let e=|v:Value|json!({"v":v,"n":1,"at":at});
  let huge:serde_json::Map<String,Value>=(0..400).map(|i|(format!("binance/usd_m/COIN{i:04}USDT"),e(json!("1h")))).collect();
  for bad in [json!(null),json!([]),json!({"intervals":[]}),json!({"other":{}}),
              json!({"intervals":{"BTC":e(json!("7h"))}}),json!({"intervals":{"":e(json!("1h"))}}),
              json!({"intervals":{"x".repeat(129):e(json!("1h"))}}),
              json!({"intervals":{"BTC":{"v":"1h","n":1}}}),json!({"intervals":{"BTC":{"v":"1h","n":-1,"at":at}}}),
              json!({"intervals":{"BTC":{"v":"1h","n":1.5,"at":at}}}),json!({"intervals":{"BTC":{"v":"1h","n":1,"at":-1}}}),
              json!({"intervals":{"BTC":{"v":"1h","n":1,"at":at,"x":1}}}),
              json!({"priceAxis":{"crypto":e(json!("percent"))}}),json!({"priceAxis":{"fx":e(json!("log"))}}),
              json!({"sectorWindow":{"crypto":e(json!("d20"))}}),json!({"sectorWindow":{"eu":e(json!("today"))}}),
              json!({"watchMove":{"BTC":e(json!(2.5))}}),json!({"watchMove":{"BTC":e(json!(0.4))}}),json!({"watchMove":{"BTC":e(json!("1"))}}),
              json!({"intervals":Value::Object(huge)})] {
   assert!(!field("settings","learnedDefaults",&bad),"{bad}");
  }
 }
 #[test] fn watch_move_settings_are_accepted_and_bounded() {
  for (key,value) in [("watchMoveAlert",json!(true)),("watchMoveAlert",json!(false))] {
   let operation=op("settings",&[(key,value.clone())]);
   assert!(operation.validate().is_ok(),"{key}={value}");
   assert!(operation.unknown_fields().is_empty(),"{key} 要在白名单里");
   assert_eq!(applied("settings",&[(key,value.clone())]).body[key],value);
  }
  for (key,bad) in [("watchMoveAlert",json!(1)),("watchMoveAlert",json!(null))] {
   assert!(op("settings",&[(key,bad.clone())]).validate().is_err(),"{key} 不该收 {bad}");
  }
 }
 /// The bug this whole allowlist pass is about: one pinch on the chart used to come back
 /// 400, sit in the client's outbox and block every later preference behind it.
 #[test] fn pinching_the_chart_now_reaches_the_server() {
  let object=applied("settings",&[("barSpacing",json!(9.5)),("skin",json!("terra")),("interval",json!("15m"))]);
  assert_eq!(object.body["barSpacing"],json!(9.5));
  assert_eq!(object.body["skin"],json!("terra"));
  assert_eq!(object.revision,1);
 }
 /// A newer client always runs ahead of a deployed server. The unknown name is dropped and
 /// named in the receipt; everything else in the same operation still merges.
 #[test] fn a_name_this_server_never_heard_of_loses_the_field_not_the_operation() {
  let operation=op("settings",&[("barSpacing",json!(9.5)),("telepathy",json!(true))]);
  assert!(operation.validate().is_ok());
  assert_eq!(operation.unknown_fields(),vec!["telepathy".to_string()]);
  let object=merge(blank("settings","chart"),&operation,1_800_000_000_000).unwrap();
  assert_eq!(object.body["barSpacing"],json!(9.5));
  assert!(!object.body.contains_key("telepathy"));
  assert!(!object.fields.contains_key("telepathy"));
 }
 /// Unknown *names* are forgiven. Known names with impossible values are not.
 #[test] fn a_value_that_cannot_be_right_is_still_refused() {
  for bad in [json!(0.0),json!(4000.0),json!("wide"),json!(f64::MAX)] {
   assert!(op("settings",&[("barSpacing",bad.clone())]).validate().is_err(),"barSpacing {bad} should be refused");
  }
  assert!(op("settings",&[("skin",json!("neon"))]).validate().is_err());
  assert!(op("settings",&[("interval",json!("7h"))]).validate().is_err());
  assert!(op("settings",&[("redUp",json!("yes"))]).validate().is_err());
 }
 /// 审查 2026-10-10 第 3 项：设置里一个值永久过不了规则，推送路径上只丢这一个字段、在回执里点名，
 /// 同一条操作里的别的字段照常落库；`validate` 本身仍然严格（复盘快照靠它）。
 #[test] fn a_bad_settings_value_loses_the_field_not_the_operation() {
  let operation=op(SETTINGS,&[("barSpacing",json!(4000.0)),("skin",json!("terra")),("telepathy",json!(true))]);
  assert!(operation.validate().is_err(),"validate 仍按原样严格");
  let (admitted,invalid)=operation.admit();
  assert_eq!(invalid,vec!["barSpacing".to_string()]);
  assert!(screen(&admitted,Uuid::nil(),&Default::default()).is_ok(),"拿掉坏值之后这一条照常进合并");
  let merged=merge(blank(SETTINGS,"chart"),&admitted,1_800_000_000_000).unwrap();
  assert_eq!(merged.body["skin"],json!("terra"));
  assert!(!merged.body.contains_key("barSpacing")&&!merged.fields.contains_key("barSpacing"),"坏值不落库");
  let r=receipt(&operation,&merged,7,&invalid);
  assert_eq!(r["droppedFields"],json!(["barSpacing","telepathy"]),"droppedFields 是两类的并集");
  assert_eq!(r["invalidFields"],json!(["barSpacing"]),"值不对的单独点名");
  // 画线工具偏好同理。
  let (_,invalid)=op(DRAWING_PREFERENCES,&[("magnet",json!("yes")),("continuous",json!(true))]).admit();
  assert_eq!(invalid,vec!["magnet".to_string()]);
  // 字段彼此牵连的集合仍整条拒：丢一个字段就是存下半截对象。
  let mut line=op(DRAWINGS,&[("lineWidth",json!(99))]);line.object_id="binance/usd_m/BTCUSDT/line-1".into();
  let (admitted,invalid)=line.admit();
  assert!(invalid.is_empty());
  let e=screen(&admitted,Uuid::nil(),&Default::default()).unwrap_err();
  assert_eq!((e.0,e.1),(axum::http::StatusCode::BAD_REQUEST,"invalid_operation"));
  // 坏路径、超大的值不在「丢掉」之列，仍整条拒。
  assert!(op(SETTINGS,&[("../x",json!(1))]).admit().1.is_empty());
  let (huge,invalid)=op(SETTINGS,&[("theme",json!("x".repeat(100_000)))]).admit();
  assert!(invalid.is_empty()&&huge.validate().is_err());
 }
 /// 审查 2026-10-10 第 4 项：库里存量的一个值按现行规则已经不合规（规则收紧过、或者绕过校验写进去的），
 /// 之后对这条对象写**别的**字段不能被它拖死——它被洗掉，这次写入照常落库。
 #[test] fn a_stored_value_that_no_longer_passes_is_washed_out_not_refused() {
  let mut settings=blank(SETTINGS,"chart");
  settings.body.insert("barSpacing".into(),json!(4000.0));
  settings.fields.insert("barSpacing".into(),json!({"revision":1}));
  settings.body.insert("skin".into(),json!("neon"));
  settings.body.insert("redUp".into(),json!(true));
  settings.revision=1;
  let mut patch=op(SETTINGS,&[("interval",json!("1h"))]);patch.base_revision=1;
  let merged=merge(settings,&patch,1_800_000_000_000).unwrap_or_else(|e|panic!("存量坏值把这次写入拖死了：{}",e.1));
  assert_eq!(merged.body["interval"],json!("1h"));
  assert_eq!(merged.body["redUp"],json!(true),"合规的存量原样留着");
  assert!(!merged.body.contains_key("barSpacing")&&!merged.fields.contains_key("barSpacing"));
  assert!(!merged.body.contains_key("skin"));
  assert!(crate::sync_validation::object(&merged).is_ok());
  // 存量的坏值也照样能被这一次写进来的好值盖掉。
  let mut stored=blank(SETTINGS,"chart");stored.body.insert("skin".into(),json!("neon"));
  assert_eq!(merge(stored,&op(SETTINGS,&[("skin",json!("sage"))]),1_800_000_000_000).unwrap().body["skin"],json!("sage"));
 }
 /// 审查 2026-10-10 第 5 项：设备号不对、指标提醒的品种认不得，都是**这一条**的事，`push` 把它写进
 /// 这一条的结果格（`?rejections=inline`），不再整批 400。409 / 5xx 仍是整批的事。
 #[test] fn per_operation_problems_stay_with_their_operation() {
  let device=Uuid::from_u128(7);
  let mut mine=op(SETTINGS,&[("skin",json!("terra"))]);mine.device_id=device;
  assert!(screen(&mine,device,&Default::default()).is_ok());
  let e=screen(&op(SETTINGS,&[("skin",json!("terra"))]),device,&Default::default()).unwrap_err();
  assert_eq!((e.0,e.1),(axum::http::StatusCode::BAD_REQUEST,"invalid_device"));
  assert!(per_operation(&e));
  // 认不得的品种只拒带着它的那一条。
  let rule=json!({"kind":"rsi_level","interval":"1h","period":14,"level":70,"direction":"up"});
  let mut alert=op(ALERTS,&[("rule",rule)]);alert.object_id="binance/usd_m/NOPEUSDT/a1".into();alert.device_id=device;
  let unlisted=std::collections::BTreeSet::from(["NOPEUSDT".to_string()]);
  let e=screen(&alert,device,&unlisted).unwrap_err();
  assert_eq!(e.1,crate::conditions::indicators::code::SYMBOL);
  assert!(screen(&alert,device,&Default::default()).is_ok(),"合约表认得（或者取不到）就放行");
  assert!(screen(&mine,device,&unlisted).is_ok(),"同一批里别的操作不受牵连");
  // 结果格的形状：带 code，有中文原因的再带 message；拒绝不是回执，不带 object / cursor。
  let r=rejection(alert.id,&e);
  assert_eq!(r["status"],json!("rejected"));
  assert_eq!(r["code"],json!(crate::conditions::indicators::code::SYMBOL));
  assert!(r["message"].is_string()&&r.get("object").is_none()&&r.get("cursor").is_none());
  assert!(rejection(alert.id,&ApiError::bad("invalid_device")).get("message").is_none());
  // 整批的事：要重新拉取、导入批次被别人认领、数据库不可用。
  assert!(per_operation(&ApiError::conflict("idempotency_mismatch")));
  assert!(!per_operation(&ApiError::conflict("resync_required")));
  assert!(!per_operation(&ApiError::conflict("batch_already_claimed")));
  assert!(!per_operation(&ApiError(axum::http::StatusCode::SERVICE_UNAVAILABLE,"temporarily_unavailable")));
 }
 #[test] fn a_malformed_path_is_still_refused() {
  for path in ["","../secrets","params/../..","_internal","a//b",&"x".repeat(161)] {
   assert!(op("settings",&[(path,json!(true))]).validate().is_err(),"path {path:?} should be refused");
  }
 }
 #[test] fn bulk_and_oversized_payloads_are_still_refused() {
  assert!(op("settings",&[("telepathy",json!("x".repeat(70_000)))]).validate().is_err());
  let many:Vec<_>=(0..257).map(|i|(format!("f{i}"),json!(true))).collect();
  let mut operation=op("settings",&[]);operation.fields=many.into_iter().collect();
  assert!(operation.validate().is_err());
  let mut wrong=op("settings",&[]);wrong.collection="secrets".into();
  assert!(wrong.validate().is_err());
  let mut action=op("settings",&[]);action.action="drop".into();
  assert!(action.validate().is_err());
 }
 /// Dropping a field must not pretend the value landed: the receipt has to carry the name
 /// so the client keeps its dirty mark and retries the value later.
 #[test] fn a_dropped_field_keeps_its_name_in_the_receipt() {
  let operation=op("settings",&[("telepathy",json!(true)),("moodRing",json!("blue"))]);
  let mut named=operation.unknown_fields();named.sort();
  assert_eq!(named,vec!["moodRing".to_string(),"telepathy".to_string()]);
  assert!(op("settings",&[("barSpacing",json!(9.5))]).unknown_fields().is_empty());
 }
 /// 退役名字留在**已经存下的** body 里时，之后对这条对象的每一次合并都不能被它拖死：
 /// 值规则随名字删掉了，`sync_validation::object` 会把它当成没有规则的键整条 400
 /// （`invalid_sync_value`）。线上 66 份设置对象都还躺着 `showDrawings:true`。
 #[test] fn a_stored_body_with_retired_names_still_merges() {
  let mut settings=blank("settings","chart");
  settings.body.insert("showDrawings".into(),json!(true));
  settings.body.insert("subHeights".into(),json!({"MACD":"large"}));
  settings.fields.insert("showDrawings".into(),json!({"revision":1}));
  let merged=merge(settings,&op("settings",&[("barSpacing",json!(9.5))]),1_800_000_000_000)
   .unwrap_or_else(|e|panic!("merge onto an old settings body: {}",e.1));
  assert_eq!(merged.body["barSpacing"],json!(9.5));
  assert!(!merged.body.contains_key("showDrawings")&&!merged.body.contains_key("subHeights")&&!merged.fields.contains_key("showDrawings"));

  let mut favorite=blank("favorites","binance/usd_m/BTCUSDT");
  for (k,v) in [("symbol",json!("BTCUSDT")),("market",json!("usd_m")),("venue",json!("binance")),("order",json!(0)),("pinned",json!(false))] {favorite.body.insert(k.into(),v);}
  let mut move_it=op("favorites",&[("groupId",json!("crypto"))]);move_it.object_id="binance/usd_m/BTCUSDT".into();
  let merged=merge(favorite,&move_it,1_800_000_000_000).unwrap_or_else(|e|panic!("merge onto an old favorite body: {}",e.1));
  assert_eq!(merged.body["groupId"],json!("crypto"));
  assert!(!merged.body.contains_key("pinned"));
 }
 /// 老版本推上来的自选操作里带着 `pinned`：只丢这个字段，操作照常合并。
 #[test] fn retired_favorite_names_are_dropped_not_refused() {
  for name in RETIRED_FAVORITE_FIELDS {assert!(!FAVORITE_FIELDS.contains(name),"{name} 已退役，不该还在白名单里")}
  let mut operation=op("favorites",&[("symbol",json!("BTCUSDT")),("market",json!("usd_m")),("venue",json!("binance")),("order",json!(3)),("pinned",json!(true))]);
  operation.object_id="binance/usd_m/BTCUSDT".into();
  assert!(operation.validate().is_ok(),"老版本带着 pinned 推上来不能整条 400");
  assert_eq!(operation.unknown_fields(),vec!["pinned".to_string()]);
  let object=merge(blank("favorites","binance/usd_m/BTCUSDT"),&operation,1_800_000_000_000).unwrap();
  assert_eq!(object.body["order"],json!(3));
  assert!(!object.body.contains_key("pinned"));
  assert!(retired_field("favorites","pinned")&&!retired_field("settings","pinned")&&!retired_field("favorites","order"));
 }
 /// 两端删掉的 `showDrawings` / `subHeights`：老版本推上来照旧只丢字段、不丢操作，
 /// 回执里点名；它们也不许再混回白名单（不然就是没删干净）。
 #[test] fn retired_settings_names_are_dropped_not_refused() {
  for name in RETIRED_SETTINGS_FIELDS {assert!(!SETTINGS_FIELDS.contains(name),"{name} 已退役，不该还在白名单里")}
  let operation=op("settings",&[("showDrawings",json!(true)),("subHeights/MACD",json!("large")),("barSpacing",json!(9.5))]);
  assert!(operation.validate().is_ok(),"老版本带着退役字段推上来不能整条 400");
  let mut named=operation.unknown_fields();named.sort();
  assert_eq!(named,vec!["showDrawings".to_string(),"subHeights/MACD".to_string()]);
  assert!(named.iter().all(|k|retired_settings_field(k)));
  assert!(!retired_settings_field("subHeightOverrides/MACD")&&!retired_settings_field("telepathy"));
  let object=merge(blank("settings","chart"),&operation,1_800_000_000_000).unwrap();
  assert_eq!(object.body["barSpacing"],json!(9.5));
  assert!(!object.body.contains_key("showDrawings")&&!object.body.contains_key("subHeights"));
 }
 /// 收设置项 A 组（2026-09-28）：`ambientTheme` / `timeZone` / `changeBasis` / `keepAwake`
 /// 两端都收掉了。老版本推上来只丢这几个字段、别的照常合并；已经存下的 body 里带着它们的，
 /// 下一次合并时被清掉，不会因为没有值规则把整条对象拖死。
 #[test] fn trimmed_settings_group_a_are_dropped_and_stripped() {
  let names=["ambientTheme","timeZone","changeBasis","keepAwake"];
  for name in names {
   assert!(RETIRED_SETTINGS_FIELDS.contains(&name)&&!SETTINGS_FIELDS.contains(&name),"{name} 应已退役");
  }
  let operation=op("settings",&[("ambientTheme",json!(true)),("timeZone",json!("local")),("changeBasis",json!("utcMidnight")),
   ("keepAwake",json!(false)),("redUp",json!(false))]);
  assert!(operation.validate().is_ok(),"老版本带着 A 组字段推上来不能整条 400");
  let mut named=operation.unknown_fields();named.sort();
  let mut expected:Vec<String>=names.iter().map(|s|s.to_string()).collect();expected.sort();
  assert_eq!(named,expected);
  let mut stored=blank("settings","chart");
  for name in names {stored.body.insert(name.into(),json!("old"));stored.fields.insert(name.into(),json!({"revision":1}));}
  let merged=merge(stored,&operation,1_800_000_000_000).unwrap_or_else(|e|panic!("merge onto an old settings body: {}",e.1));
  assert_eq!(merged.body["redUp"],json!(false));
  for name in names {assert!(!merged.body.contains_key(name)&&!merged.fields.contains_key(name),"{name} 没被清掉");}
 }
 /// 收设置项 B 组（2026-09-28，图表设置那十三项）：同 A 组，老版本推上来只丢字段，老 body 下次合并洗掉。
 /// 画线偏好里的 `magnet`（画线端点吸附）是另一个集合里的同名字段，不受影响。
 #[test] fn trimmed_settings_group_b_are_dropped_and_stripped() {
  let names=["magnet","countdown","lastLine","sinceChange","gridChoice","bodyChoice","viewAnchor","priceBias",
   "dataDisplay","crossPrice","allowMainInversion","allowSubInversion","adaptiveIndicators"];
  for name in names {
   assert!(RETIRED_SETTINGS_FIELDS.contains(&name)&&!SETTINGS_FIELDS.contains(&name),"{name} 应已退役");
  }
  let mut fields:Vec<(&str,Value)>=names.iter().map(|n|(*n,json!(true))).collect();
  fields.push(("depth",json!(true)));
  let operation=op("settings",&fields);
  assert!(operation.validate().is_ok(),"老版本带着 B 组字段推上来不能整条 400");
  let mut named=operation.unknown_fields();named.sort();
  let mut expected:Vec<String>=names.iter().map(|s|s.to_string()).collect();expected.sort();
  assert_eq!(named,expected);
  let mut stored=blank("settings","chart");
  for name in names {stored.body.insert(name.into(),json!("old"));stored.fields.insert(name.into(),json!({"revision":1}));}
  let merged=merge(stored,&operation,1_800_000_000_000).unwrap_or_else(|e|panic!("merge onto an old settings body: {}",e.1));
  assert_eq!(merged.body["depth"],json!(true));
  for name in names {assert!(!merged.body.contains_key(name)&&!merged.fields.contains_key(name),"{name} 没被清掉");}
  assert!(!retired_field(DRAWING_PREFERENCES,"magnet"),"画线偏好的吸附不在退役表里");
 }
 /// 收设置项 · 复盘（2026-09-28）：`replaySpeed` 两端收掉，倍速每趟按根数自动挑。老版本推上来
 /// 只丢这个字段（连原来就不合法的 3 也不再整条 400），`reviewSearchScope` 照常合并；老 body 下次合并洗掉。
 #[test] fn trimmed_replay_speed_is_dropped_and_stripped() {
  assert!(RETIRED_SETTINGS_FIELDS.contains(&"replaySpeed")&&!SETTINGS_FIELDS.contains(&"replaySpeed"));
  for speed in [json!(4),json!(3)] {
   let operation=op("settings",&[("replaySpeed",speed.clone()),("reviewSearchScope",json!("private"))]);
   assert!(operation.validate().is_ok(),"老版本带着 replaySpeed {speed} 推上来不能整条 400");
   assert_eq!(operation.unknown_fields(),vec!["replaySpeed".to_string()]);
  }
  let operation=op("settings",&[("replaySpeed",json!(2)),("reviewSearchScope",json!("private"))]);
  let mut stored=blank("settings","chart");
  stored.body.insert("replaySpeed".into(),json!(4));stored.fields.insert("replaySpeed".into(),json!({"revision":1}));
  let merged=merge(stored,&operation,1_800_000_000_000).unwrap_or_else(|e|panic!("merge onto an old settings body: {}",e.1));
  assert_eq!(merged.body["reviewSearchScope"],json!("private"));
  assert!(!merged.body.contains_key("replaySpeed")&&!merged.fields.contains_key("replaySpeed"),"replaySpeed 没被清掉");
 }
 /// 收设置项 C 组（2026-09-28，指标）：`hiddenOutputs`（含 `hiddenOutputs/<指标>` 这种拍平路径）
 /// 与 `rsiRange` 退役。老版本推上来只丢字段；老 body 里一条倒挂的 `rsiRange` 也不再让合并 400；
 /// `indicatorLayouts/<组>`（嵌着 `hiddenOutputs` 的老分组布局）2026-10-10 起整条退役。
 #[test] fn trimmed_settings_group_c_are_dropped_and_stripped() {
  for name in ["hiddenOutputs","rsiRange"] {
   assert!(RETIRED_SETTINGS_FIELDS.contains(&name)&&!SETTINGS_FIELDS.contains(&name),"{name} 应已退役");
  }
  let operation=op("settings",&[("hiddenOutputs/MA",json!([0,2])),("rsiRange",json!([30,70])),("params/RSI",json!([9]))]);
  assert!(operation.validate().is_ok(),"老版本带着 C 组字段推上来不能整条 400");
  let mut named=operation.unknown_fields();named.sort();
  assert_eq!(named,vec!["hiddenOutputs/MA".to_string(),"rsiRange".to_string()]);
  let mut stored=blank("settings","chart");
  for (path,value) in [("hiddenOutputs/MACD",json!([1])),("rsiRange",json!([80,20]))] {
   stored.body.insert(path.into(),value);stored.fields.insert(path.into(),json!({"revision":1}));
  }
  let merged=merge(stored,&operation,1_800_000_000_000).unwrap_or_else(|e|panic!("merge onto an old settings body: {}",e.1));
  assert_eq!(merged.body["params/RSI"],json!([9]));
  for path in ["hiddenOutputs/MACD","hiddenOutputs/MA","rsiRange"] {
   assert!(!merged.body.contains_key(path)&&!merged.fields.contains_key(path),"{path} 没被清掉");
  }
  // `indicatorLayouts/<组>`（连同里面嵌着的 hiddenOutputs）2026-10-10 整条退役，老客户端发上来只丢不拒。
  assert!(retired_settings_field("indicatorLayouts/hour"),"分组布局整条退役");
 }
 /// 收设置项 D 组（2026-09-28，主力订单流四个显示开关）：老版本推上来只丢字段，门槛表照常合并；老 body 下次合并洗掉。
 #[test] fn trimmed_settings_group_d_are_dropped_and_stripped() {
  let names=["orderFlowSpot","orderFlowContract","orderFlowShowFilled","orderFlowShowCancelled"];
  for name in names {
   assert!(RETIRED_SETTINGS_FIELDS.contains(&name)&&!SETTINGS_FIELDS.contains(&name),"{name} 应已退役");
  }
  let mut fields:Vec<(&str,Value)>=names.iter().map(|n|(*n,json!(false))).collect();
  fields.push(("orderFlowOverrides",json!({"BTC":{"spot":2000000.0}})));
  let operation=op("settings",&fields);
  assert!(operation.validate().is_ok(),"老版本带着 D 组字段推上来不能整条 400");
  let mut named=operation.unknown_fields();named.sort();
  let mut expected:Vec<String>=names.iter().map(|s|s.to_string()).collect();expected.sort();
  assert_eq!(named,expected);
  let mut stored=blank("settings","chart");
  for name in names {stored.body.insert(name.into(),json!(false));stored.fields.insert(name.into(),json!({"revision":1}));}
  let merged=merge(stored,&operation,1_800_000_000_000).unwrap_or_else(|e|panic!("merge onto an old settings body: {}",e.1));
  assert_eq!(merged.body["orderFlowOverrides"],json!({"BTC":{"spot":2000000.0}}));
  for name in names {assert!(!merged.body.contains_key(name)&&!merged.fields.contains_key(name),"{name} 没被清掉");}
 }
 /// 收设置项 E 组：`watchMoveThreshold` 退役。老客户端连同开关一起推上来：开关照收，幅度丢掉并报回；
 /// 库里老 body 带着的幅度下次合并洗掉（`watch_move::enabled` 本来也不再看它）。
 #[test] fn trimmed_settings_group_e_are_dropped_and_stripped() {
  let name="watchMoveThreshold";
  assert!(RETIRED_SETTINGS_FIELDS.contains(&name)&&!SETTINGS_FIELDS.contains(&name),"{name} 应已退役");
  let operation=op("settings",&[("watchMoveAlert",json!(true)),(name,json!(2.5))]);
  assert!(operation.validate().is_ok(),"老版本带着幅度推上来不能整条 400");
  assert_eq!(operation.unknown_fields(),vec![name.to_string()]);
  let mut stored=blank("settings","chart");
  stored.body.insert(name.into(),json!(1.5));stored.fields.insert(name.into(),json!({"revision":1}));
  let merged=merge(stored,&operation,1_800_000_000_000).unwrap_or_else(|e|panic!("merge onto an old settings body: {}",e.1));
  assert_eq!(merged.body["watchMoveAlert"],json!(true));
  assert!(!merged.body.contains_key(name)&&!merged.fields.contains_key(name),"{name} 没被清掉");
 }
 /// 收设置项 G 组（2026-09-28，自选排序 / 迷你走势、板块排序）：老版本推上来只丢这五个字段，
 /// 同一条里的分类、板块窗口照常合并；库里老 body 带着的下次合并洗掉。
 #[test] fn trimmed_settings_group_g_are_dropped_and_stripped() {
  let retired:[(&str,Value);5]=[("favoritesSort",json!("volume")),("favoritesAscending",json!(true)),
   ("favoritesAmount",json!(true)),("favoritesSparkline",json!(true)),("sectorSort",json!("volume"))];
  for (name,_) in &retired {
   assert!(RETIRED_SETTINGS_FIELDS.contains(name)&&!SETTINGS_FIELDS.contains(name),"{name} 应已退役");
  }
  let mut fields:Vec<(&str,Value)>=retired.iter().cloned().collect();
  fields.push(("sectorWindow",json!("d5")));
  fields.push(("favoritesGroup",json!("g1")));
  let operation=op("settings",&fields);
  assert!(operation.validate().is_ok(),"老版本带着 G 组字段推上来不能整条 400");
  let mut named=operation.unknown_fields();named.sort();
  let mut expected:Vec<String>=retired.iter().map(|(n,_)|n.to_string()).collect();expected.sort();
  assert_eq!(named,expected);
  let mut stored=blank("settings","chart");
  for (name,value) in &retired {stored.body.insert((*name).into(),value.clone());stored.fields.insert((*name).into(),json!({"revision":1}));}
  let merged=merge(stored,&operation,1_800_000_000_000).unwrap_or_else(|e|panic!("merge onto an old settings body: {}",e.1));
  assert_eq!(merged.body["sectorWindow"],json!("d5"));
  assert_eq!(merged.body["favoritesGroup"],json!("g1"));
  for (name,_) in &retired {assert!(!merged.body.contains_key(*name)&&!merged.fields.contains_key(*name),"{name} 没被清掉");}
 }
}
