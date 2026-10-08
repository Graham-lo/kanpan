//! Bybit v5 公开行情在服务端的那一截。
//!
//! - `relay`：`GET /v1/market/ws/bybit?category=spot|linear|inverse` 那条中继放行哪些上行帧
//!   （传输、名额、超时由 `market_relay` 统一管，这里只认 Bybit 的报文）；
//! - `orderflow`：主力订单流用的品种表解析、连接种类（地址 / 订阅消息 / 解帧）与爆仓源。
//!
//! 上游 `wss://stream.bybit.com/v5/public/{category}`，连不上换备用主机 `stream.bytick.com`。
pub mod orderflow;
pub mod relay;

/// 公开行情 WS 的主机（按先后试）。后面拼 `/{category}`。
pub const WS_BASES:[&str;2]=["wss://stream.bybit.com/v5/public","wss://stream.bytick.com/v5/public"];

/// 三个 category。
pub fn valid_category(category:&str)->bool {matches!(category,"spot"|"linear"|"inverse")}
