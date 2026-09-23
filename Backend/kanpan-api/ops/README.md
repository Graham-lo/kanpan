# kanpan-api 运维手册

部署、备份与异地容灾见上一级 `README.md` 与本目录的 `OFFSITE.md`。这里只收日常要手动做的几件事。

## 忘了密码：重置成一次性密码

账号只有用户名 + 密码，没有邮箱，所以「忘记密码」由运维在服务器上重置：

```sh
ssh orderflow-vps
sudo bash -c 'set -a; . /etc/kanpan-api/service.env; set +a; /opt/kanpan-api/target/release/kanpan-api reset-password <用户名>'
```

- 标准输出只有一行：新的一次性密码（14 位，不含 0/O/1/l/I 这类易混字符）。把它私下发给本人，让他登录后在「账号」里改掉。
- 同时会做两件事：吊销这个人**所有设备**上的会话（原因记作 `password_change`，和用户自己改密码同一类，旧设备下一次请求就回 401、回到登录页），并清掉该用户名的登录失败锁定。
- 用户名不存在或已停用时，退出码非 0，输出 `reset-password failed: unknown_username`，库里什么都不改。
- 必须用 `service.env` 里的运行时角色（`kanpan_app`）跑：程序开头会拒绝超级用户或 BYPASSRLS 角色，和 `serve` 同一道闸。不用停服务，线上照常。

## 导出一个人的数据

用户自己在 app「账号」页点「导出我的数据」即可（`GET /v1/auth/me/export`，一小时最多十次，单份上限 20 MB，超过回 413 `export_too_large`）。导出内容：用户名与注册时间、同步的自选 / 画线 / 提醒 / 设置、复盘记录与事件、存下的相似案例、朋友名单、往来的画线分享。不含密码哈希、会话与推送令牌，也不含截图等二进制。

## 隐私政策与服务条款

`/privacy`、`/terms` 两张静态页，正文在 `src/legal.rs`，改文案 = 改那里再部署。Caddy 需要把这两个路径转发到 `127.0.0.1:8794`（和 `/v1/auth/*` 同一个上游）。
