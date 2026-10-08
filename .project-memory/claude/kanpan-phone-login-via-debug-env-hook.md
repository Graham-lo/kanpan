# kanpan-phone-login-via-debug-env-hook

**项目约定**：看盘真机上要替用户登录账号时，XCUITest 在 Wi-Fi 隧道上起不来（code 74）；改用 Debug 包 + devicectl 环境变量登录钩子，再把 Release 覆盖装回去

2026-10-07 起看盘真机登录账号的可靠路线：装一个 Debug 包（`xcodebuild -configuration Debug -destination 'generic/platform=iOS'`），
用 `xcrun devicectl device process launch --device <id> --terminate-existing -e '{"KANPAN_TEST_LOGIN_USER":"…","KANPAN_TEST_LOGIN_PASS":"…"}' com.yj27y32.hkline`
起一次，`AccountFeature.restore()` 里的 DEBUG 钩子 `loginFromEnvironment()` 会按这对凭据走一遍 `submit()`；
然后 `make install-release` 覆盖装回 Release（容器与钥匙串都保留，登录态跟着）。服务器上
`sudo docker exec kanpan-postgres psql -U kanpan_app -d kanpan` 查 `account_sessions` 核对新会话。

**Why:** 09-24 能跑的真机 XCUITest 登录用例（`ZZPhoneLoginOnce`）10-07 四次都 code 74——手机改走 Wi-Fi 隧道（transportType localNetwork）后 runner 建不起 testmanagerd 通道；用户常不在电脑旁，等不到插 USB。

**How to apply:** 用户再要「帮我把账号登上手机」就走这条，不要再反复试 XCUITest；钩子只在 DEBUG 里（`ReleaseHookScanTests` 会查），密码只读 scratchpad 文件、不要打进对话。相关：`kanpan-account-flow-must-be-tested`、`kanpan-skip-device-install-when-phone-unavailable`。
