// 网络层单独成包了（`KanpanNetwork`：HTTP / WS 接口、币安客户端、行情线路与网关竞速）。
// 这里整包转出去，app 与 `kanpan-feed` 照旧只 `import KanpanData` 就能拿到
// `BinanceREST` / `BinanceHosts` / `MarketRoutePolicy` 这些名字，不用每个文件多写一行。
@_exported import KanpanNetwork
