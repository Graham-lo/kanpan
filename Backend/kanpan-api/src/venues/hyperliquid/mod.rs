//! Hyperliquid 公开行情在服务端的那一截。
//!
//! * `hub`：进程里唯一一条上游 `wss://api.hyperliquid.xyz/ws`，按 (频道, 币) 引用计数地订退，
//!   常驻跟踪与给手机 / 网页的中继共用它（Hyperliquid 的限流按 IP 算，见 `hub` 的说明）。
//! * `relay`：`GET /v1/market/ws/hyperliquid` 那条中继的上行白名单与转发——手机那头看起来就像直连
//!   Hyperliquid（帧是上游原文），只是订的东西都经过 hub。
pub mod hub;
pub mod relay;
