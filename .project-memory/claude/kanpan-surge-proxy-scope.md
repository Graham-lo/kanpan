---
name: kanpan-surge-proxy-scope
description: 看盘项目的网络测试必须走代理才算数；Surge 主配置只给本项目开口，其余一个字不改
metadata:
  node_type: memory
  pinned: false
  originSessionId: e9dbcbc0-29db-4fc1-9d26-863d0b737f12
  modified: 2026-09-14T11:11:56.039Z
---

# 看盘：测网络前先把本项目的域名接上代理，但只给本项目开口

用户的这台 Mac 跑着 Surge，并且**手机是通过这台 Mac 的 Surge 网关上网的**。主配置里
有一条 `RULE-SET,…/BinanceDirect.list,DIRECT`，把 `fstream` / `stream` / `dstream` /
`nbstream` 这批币安域名钉死成直连——那是照着网关上抓到的币安 App 流量调的（国内加速
IP，直连 28ms、走代理 172ms），**是对的，不要动**。

## 用户定的两条规矩

1. **「surge 的这段配置是为了手机优化的，所以你看看能不能单独为了项目走通代理，
   其它不变」** —— 只给本项目的进程/域名开一个口子，别的流量（手机、币安 App、
   浏览器）继续吃原来的直连优化。
2. **「你还是让这几个走代理吧，不然没法真实测试」** —— 排查网络问题时，如果测试用的
   进程没被规则命中，跑出来的数就是废的。改配置这件事用户是**授权**的（原话「你改
   一下」），不要把命令列出来让他自己改。

## 具体怎么落

规则插在主配置 `[Rule]` 段**最前面**（Surge 首条命中即生效，必须抢在
`BinanceDirect.list` 前面），用 `AND` 把进程名和域名两个条件绑在一起：

```
AND,((PROCESS-NAME,kanpan-feed),(DOMAIN-SUFFIX,binance.com)),Binance
```

排查用的临时二进制也要起成规则里写着的名字，否则不命中、结果无效——我就因为把探针
编译成 `kanpan-feed-url` 而白跑过一轮。

## 工具

`/Applications/Surge.app/Contents/Applications/surge-cli` 能干完所有事，不用点界面：

- `surge-cli reload` —— 外部改了配置文件之后 Surge **不会自己重载**，必须显式调这个。
- `surge-cli rule match <host> 443 process-path=<路径>` —— 验证某个进程访问某个域名
  最终走哪条规则、落到哪个策略。改完规则先用它确认，再去跑真实流量。
- `surge-cli policy-group list / set <组> <节点>` —— 换出口做对照实验，做完记得换回去。

改主配置之前先 `cp` 一份 `…conf.backup-before-<做什么>-<时间戳>`，这是这份配置一贯的
备份命名习惯。
