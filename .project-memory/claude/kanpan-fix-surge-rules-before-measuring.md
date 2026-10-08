# kanpan-fix-surge-rules-before-measuring

**项目约定**：看盘排查真机网络问题时，先确认并改正 Surge 规则再测量，规则错了测出来的一切都不作数

2026-09-18 排查看盘真机「直连模式行情不跳」时，我查出用户 Surge 的
`BinanceDirect.list` 把 `fstream.binance.com` 等几个推送主机强制 DIRECT，而那条路
国内已经被掐断；`fapi.binance.com` 落到 `Binance.list` 走代理所以 REST 正常——
「WS 不行 REST 可以」就是这么来的。我把结论报给用户、问要不要改规则，用户回的是：
「你先把 surge 规则改对再测试，不然现在测试有很大的问题」。

所以在这个项目里，只要真机是通过 Mac 上的 Surge 网关出网，排查顺序就是：
**先把 Surge 规则核对、改正、让它生效，再做任何关于 app 网络表现的测量**。
规则把某个主机按在错误的策略上时，首帧耗时、连接成功率、丢帧这些数字全是噪音，
拿它们去推断 app 的问题只会把排查带偏。改规则不用再单独请示——用户既然让先改对，
就改对了再往下走，改完还要实测验证策略真的换过来了（`surge-cli rule match` 只看
规则命中，还要 `dump active` 确认手机上新建的连接确实走了新策略）。

规则集在用户自己的 GitHub 仓库 `Graham-lo/surge`（本机没有 checkout，需要克隆），
改完 push 之后 Surge 不会自动拿到新版本，要用
`surge-cli external-resource list` 找到那条 ruleset 的 key，再
`surge-cli external-resource update <key>`，然后 `surge-cli reload`。
另外已经建立的连接会保持原策略，必须重启 app 才能验证新规则。
