// 网络层单独成包了（`KanpanNetwork`：HTTP / WS 接口、各家交易所的提供者、行情线路与网关竞速）。
// 这里整包转出去，app 与 `kanpan-feed` 照旧只 `import KanpanData` 就能拿到
// `MarketProvider` / `RouteResolver` / `MarketRoutePolicy` 这些名字，不用每个文件多写一行。
@_exported import KanpanNetwork
