---
name: prefer-doing-over-handing-commands
description: 用户希望我直接动手把事情做完，而不是把命令列出来让他自己跑
metadata:
  node_type: memory
  pinned: true
  originSessionId: 6c4bd828-d529-42c8-8a4e-430ebcd5a1a8
  modified: 2026-09-14T07:36:48.556Z
---

# 能自己跑的就自己跑，别把命令甩给用户

用户明确要求过「直接帮我弄好开发环境」。在那之前，我连续几轮把 `sudo mas get`、`sudo xcodebuild -downloadPlatform iOS` 这类命令整理成代码块交给他自己执行，他对这种「列清单让我照做」的方式不满意。

## 正确做法

**先自己试着执行，失败了再说。** 例如 `xcodebuild -downloadPlatform iOS` 我原以为要 `sudo`，实际不带 `sudo` 就能跑起来 8.5 GB 的下载——如果不试就交给用户，等于白白多绕一圈。长时间的下载和构建放后台跑，不要因为耗时就推给用户。

**只有真正需要用户本人的时候才交出去**，主要是这两类：
- 需要输入他的开机密码（`sudo` 在非交互终端下会直接报 `a terminal is required to read the password`，这时才把命令交给他）
- 需要他本人的身份或账号操作（App Store 登录、开发者账号申请、真机上开开发者模式）

看盘项目的任务书里也写了同样的规矩：装 Xcode 这类要密码的步骤交给用户自己跑，**不要索要、不要代输密码**。但这条只针对密码，不是让我把所有命令都推出去。

## 遇到阻碍时也别急着交出去

环境类报错先自己排查。例如 CLT 下 `swift test` 报 `no such module 'Testing'`，看上去像是 CLT 不支持，实际只是 SwiftPM 没自动加上 `Testing.framework` 和 `lib_TestingInterop.dylib` 的搜索路径，补四条 `-F` / `-rpath` 就能跑通。这种问题应该我查到底并把修复固化进构建脚本，而不是报告「CLT 跑不了」。

## GUI 操作同样算「甩给用户」

不只是命令行。我曾让用户在 Xcode 里一步步点「Settings ▸ Accounts ▸ + ▸ Apple ID」「TARGETS ▸ Signing & Capabilities ▸ Team 下拉框」，还让他把 Team ID 抄给我，他直接回了「你直接帮我弄就行」。

**界面里能看到的配置，多半在某个 plist 或缓存里读得到，先去翻。** 那次的 Team ID 就躺在 `defaults read com.apple.dt.Xcode` 的 `IDEProvisioningTeamByIdentifier` 里（含 `teamID` / `teamName` / `isFreeProvisioningTeam`），根本不用他动手。拿到之后直接 `sed` 写进 `project.pbxproj`，再用 `xcodebuild -allowProvisioningUpdates` 让工具链自己申请证书、注册设备、下发描述文件——整条链路不需要 GUI。

只有**手机上的物理操作**（插线、点信任、开开发者模式、信任开发者证书）和**输账号密码**这两类是真的必须他本人做。
