# kanpan-coinbase-spot-only

**项目约定**：看盘接 Coinbase 只接现货（USD 计价），不接 Coinbase 的永续 / 国际站衍生品；用户 2026-09-24 在主力订单流上线时明说「coinbase只搞现货」

2026-09-24 主力订单流的服务端历史跟踪上线、我在核对各家簿的接入时，用户插了一句：
「coinbase只搞现货」。

所以在看盘的多交易所模块里（主力订单流、盘口聚合、以后任何按交易所拆产品的功能），
Coinbase 这一家的范围就是**现货、USD 计价**（BTC-USD 这种），不接 Coinbase 的永续合约、
Coinbase International / 衍生品、也不接它的 USDT 计价对（USDT 对已经由币安 / OKX 现货覆盖，
再接一份只会重复）。币安、OKX 才分现货 / U 本位永续 / 币本位永续 / 交割四种产品。

当时的现状已经符合：`Backend/kanpan-api/src/orderflow_instruments.rs` 的 `parse_coinbase`
只列 online、USD 计价的现货，客户端品种表同样。以后扩产品线或有人提议「Coinbase 也接永续」
时，按这条直接不做，不必再问。
