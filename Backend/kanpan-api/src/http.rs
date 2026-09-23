//! 整个进程只有一个出站 HTTP 客户端。
//!
//! 以前 apns、oi_archive、market_meta、复盘的币安适配器各自 `Client::builder()` 一个，
//! 每个都有自己的连接池、自己的 DNS 缓存、自己那一份 TLS 会话（审查 A7）：同一台
//! `www.binance.com` 被三个池子各握一次手，空闲连接各留一份。reqwest 的 `Client`
//! 内部就是 `Arc`，`clone()` 共用同一个池子，所以这里建一个，谁要谁拿。
//!
//! 各家对超时的要求不一样时，在请求上用 `RequestBuilder::timeout` 覆盖（APNs 10 秒、
//! 盘口深度按它自己的预算），不要为此再建一个客户端。
use std::sync::OnceLock;
use std::time::Duration;

/// 浏览器的 UA。币安网站主机（`www.binance.com`）是给浏览器用的前门，reqwest 默认的
/// 空 UA 这类请求它会拒；其余上游（CoinGecko、data.binance.vision、APNs、Coinbase）都不在乎。
pub const BROWSER_UA:&str="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

/// 整体超时：请求可以单独改短（`.timeout(..)`），这是没改时的上限。
pub const TIMEOUT:Duration=Duration::from_secs(20);
/// 单独的连接超时。只有整体超时的话，一个黑洞路由（SYN 出去没人回）会把请求按满
/// 20 秒，而 market_meta 的刷新是串着跑的：几百个页面各占 20 秒，一轮就再也跑不完。
/// 连上一个活着的主机从来不需要五秒。
pub const CONNECT_TIMEOUT:Duration=Duration::from_secs(5);
/// 空闲连接留多久。APNs 一次触发要推两三台设备、归档预热十六路并发，都靠留着的连接
/// 省掉 TLS + HTTP/2 握手；再长就是替对面已经关掉的连接占位。
pub const POOL_IDLE:Duration=Duration::from_secs(90);

/// 那一个客户端。HTTP/2 由 ALPN 协商（Cargo.toml 开了 `http2`）：APNs 只说 h2，
/// 币安、CoinGecko 说什么就用什么。
pub fn shared()->&'static reqwest::Client {
 static CLIENT:OnceLock<reqwest::Client>=OnceLock::new();
 CLIENT.get_or_init(||reqwest::Client::builder()
  .timeout(TIMEOUT)
  .connect_timeout(CONNECT_TIMEOUT)
  .pool_idle_timeout(POOL_IDLE)
  .user_agent(BROWSER_UA)
  .build().expect("HTTP client"))
}

#[cfg(test)]
mod tests {
 use super::*;
 /// 拿到的永远是同一个客户端（同一个池子），不是每次新建。
 #[test] fn one_client_for_the_process() {
  assert!(std::ptr::eq(shared(),shared()));
 }
 /// 复盘的币安适配器在 vendor 里有自己一份 UA 常量（它不能依赖 kanpan-api）；
 /// 两份必须一字不差，否则同一台主机会看到两种来路。
 #[test] fn the_vendor_adapter_says_the_same_thing() {
  let vendor=include_str!("../vendor/scorebook-market/src/adapters/binance.rs");
  assert!(vendor.contains(&format!("const BROWSER_UA: &str = \"{BROWSER_UA}\";")));
 }
}
