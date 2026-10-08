# kanpan-phone-sessions-want-bypass

**项目约定**：用户要求从手机遥控开的看盘会话一律跑在 bypassPermissions 模式；这道开关我改不动时，给他一条能直接粘的命令，别把整个排查推回去

# 手机遥控会话要跑 bypass 权限模式

2026-09-19 用户三次说到同一件事：「为什么手机开的会话没有 bypass permission」「我手机新开会话还是
没有看到 bypass permission 啊」「**你直接帮我弄好，以后手机新开会话都要有 bypass permission**」。
这是一条长期期望：**他从 iPhone 遥控这台 Mac 开的看盘会话，要直接落在 bypassPermissions 模式，
不要停在 auto 或 default，他不想在手机上一条条点同意。**

机制上有两半，缺一不可：

1. **宿主的启动参数。** 遥控宿主是常驻进程，启动脚本在 `~/.claude/kanpan-remote-control.sh`，
   命令形如 `claude remote-control --name kanpan --permission-mode bypassPermissions`。手机上新开的
   会话继承宿主启动时定的模式，**手机端自己切不了**，所以调整都要回到 Mac 上改启动参数并重启宿主
   （重启会断掉当前所有遥控会话，包括我正在说话的那个）。
2. **这台机器接受过 bypass 免责声明。** 否则宿主带了参数也会被静默降级成 auto。开关是
   `~/.claude/settings.json` 里的 `"skipDangerousModePermissionPrompt": true`，或在终端跑一次
   `claude --dangerously-skip-permissions` 并确认。探针是
   `claude --bg --permission-mode bypassPermissions "echo hi"`：没过闸时它会直接报
   「requires accepting the disclaimer first」。

**我自己改不动第 2 半。** 在 auto 模式的会话里，无论用 Bash 还是 Edit 去写这两处，都会被权限分类器
拦下，用户明确授权之后重试一次仍然被拦——这正是它的设计意图，不要用脱离会话的脚本之类的姿势去绕。

所以用户要的「直接帮我弄好」在这件事上的正确落法是：**一次把诊断做完，然后给他一条可以直接粘到
Mac 终端的命令**（写设置 + 重启宿主），而不是让他自己去读文档、分几步操作，更不是反复换工具试探
分类器。剩下能我做的（重启宿主、验证新会话模式）我做掉。
