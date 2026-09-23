//! 隐私政策与服务条款：两张静态页，app 设置里「关于」直接打开它们。
//! 正文随二进制一起发，改文案就是改这里再部署，不另起一个静态站。
use axum::{Router,routing::get,response::Html};

pub fn routes<S:Clone+Send+Sync+'static>()->Router<S> {
 Router::new().route("/privacy",get(||async{Html(page("隐私政策",PRIVACY))})).route("/terms",get(||async{Html(page("服务条款",TERMS))}))
}

pub const PRIVACY:&str=r#"<p>Hkline 是几个朋友之间自用的看盘工具。我们尽量少存东西，存下的也只为你自己服务。</p>
<h2>我们存什么</h2>
<ul>
<li>你的用户名，以及密码哈希（不存密码原文）。</li>
<li>你自己的自选、画线、提醒、图表设置与复盘记录，用来在你的几台设备之间同步。</li>
<li>你主动发给朋友的画线分享，只有你和收件人看得到。</li>
</ul>
<h2>我们不收集什么</h2>
<p>除为推送提醒所需的设备标识外，不收集任何其他信息：不做统计分析，不接广告，不读取通讯录、位置或相册（除非你在复盘里自己选一张图上传）。</p>
<h2>数据在哪</h2>
<p>数据存放在美国的一台 VPS 上，个人数据按账号隔离，别人读不到你的数据。</p>
<h2>导出与注销</h2>
<p>你可以随时在 app 的账号页「导出我的数据」拿到一份完整副本，也可以随时注销账号；注销后你的全部数据会被删除。</p>"#;

pub const TERMS:&str=r#"<p>Hkline 是一个免费的、朋友之间自用的看盘与复盘工具。</p>
<ul>
<li>行情数据来自交易所的公开接口，可能延迟、中断或出错；app 里的任何内容都不构成投资建议，交易决策与盈亏由你自己负责。</li>
<li>请保管好自己的账号密码，不要把账号借给他人使用。</li>
<li>请不要用它发送违法或骚扰他人的内容；滥用的账号会被停用。</li>
<li>服务按现状提供，可能随时调整或停止；停止前会尽量留出时间让你导出数据。</li>
</ul>"#;

fn page(title:&str,body:&str)->String {
 format!(r#"<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Hkline {title}</title>
<style>body{{font:16px/1.65 -apple-system,system-ui,sans-serif;max-width:640px;margin:0 auto;padding:24px 20px 48px;color:#1d2a26;background:#f6f7f4}}h1{{font-size:22px}}h2{{font-size:17px;margin-top:28px}}@media(prefers-color-scheme:dark){{body{{color:#e6ece9;background:#141a18}}}}</style></head>
<body><h1>Hkline {title}</h1>{body}</body></html>"#)
}

#[cfg(test)]
mod tests {
 use super::*;
 #[test] fn privacy_says_what_the_handoff_promised() {
  for needle in ["用户名","密码哈希","自选","画线","提醒","复盘记录","设备标识","美国","导出","注销"] {
   assert!(PRIVACY.contains(needle),"隐私政策缺「{needle}」");
  }
  assert!(page("服务条款",TERMS).starts_with("<!doctype html>"));
 }
}
