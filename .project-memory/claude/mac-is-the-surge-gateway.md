---
name: mac-is-the-surge-gateway
description: 这台 Mac 本身是 Surge 网关，手机等设备都走它上网，不要动它的网络接口
metadata:
  pinned: false
---

# 这台 Mac 是网关，别动它的网络

为了让 iPhone 镜像能连上，我用 `networksetup -setairportpower en1 on` 把 Mac 的
Wi-Fi 打开了。用户立刻反问：**「mac 不是网关吗」**。

他是对的，而且这是我该先查清楚再动手的事。实际情况：

- **`surge-dhcpd` 跑在 `en0` 上**（`/Applications/Surge.app/.../surge-dhcpd -4 -f -d -cf .../dhcpd.conf ... en0`），
  en0 处于 `PROMISC` 模式。也就是说 Surge 开着**网关 / 增强模式**，
  局域网 192.168.124.x 里的设备（包括他的 iPhone）都把这台 Mac 当网关走。
- 我一开 Wi-Fi，`en1` 就拿到了 **同网段** 的 192.168.124.131，并且多出一条
  `default 192.168.124.110 UGScIg en1` 的默认路由。同一子网出现第二个接口 + 第二条
  默认路由，对一台正在当网关的机器是有害的。

## 规矩

**不要为了自己的便利去改这台 Mac 的网络状态**——Wi-Fi 开关、接口顺序、路由、DNS、
共享设置都算。需要联网能力时先 `netstat -rn` / `ifconfig` / `pgrep -lf Surge`
看清现状，确认改动不会影响它的网关角色；拿不准就换一条不碰网络的路子。

这条和 `kanpan-surge-proxy-scope.md` 是同一个精神：他的网络环境是生产环境，
只在明确需要时开最小的口子，其余一个字不改。

## 具体到「看手机屏幕」这件事

iPhone 镜像（`com.apple.ScreenContinuity`）**必须要 Wi-Fi**，所以在这台机器上它
本质上是条死路。要看手机画面应该走**不碰网络的 USB 路线**：QuickTime Player 的
「新建影片录制」把 iPhone 选成输入源，通过数据线就能实时镜像画面（只能看不能控）。
