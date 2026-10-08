# kanpan-watch-machine-resources

**项目约定**：看盘里 Claude 跑多任务前必须先看机器资源并排队（scripts/machine-guard.sh），不一次开很多模拟器和子线程；Surge / ChatGPT / Claude 必须保住；模拟器只维护 iPhone 16 Pro / 17 Pro Max 两台（09-23 从四台再砍到两台）；可再生资源用完即删，Docker 按需开、不用就退出；僵尸进程要清

# 看盘：多任务前先看机器资源、要排队，Surge / ChatGPT / Claude 必须保住

2026-09-23 中午用户说：「现在开多个进程多个模拟器，机器顶不住反而拖慢了任务进度，claude 执行
多任务时必须看看机器的资源」。随后补了更硬的一句：「机器已经多次出现一些软件应用崩溃情况，
不能再交给 mac 本身处理，系统会强制清除进程导致任务无法正常执行；在保证必须的任务进程时
可以更大程度地应用机器资源，但不能出现这种情况；surge、网关、GPT、Claude 是必须的」。
他手动停了几个任务，让我「把能删掉的都删掉」，最后把规矩说成一般原则：

> 「不再维护那么多机器，重点维护 16 Pro / Pro Max、17 Pro / Pro Max。可重生资源尽量用完即删除，
> 像 Docker 这类不用的时候就退出，用的时候再打开，按需使用。不要一次性开很多个模拟器、很多个
> 子线程，根据实际情况来，不仅拖慢进度还导致崩溃。还有一些僵尸进程、错误线程占着资源。
> Claude 执行任务的时候特别要注意，每次开很多模拟器进程，不根据资源情况来使用，也没有排队机制。」

当时的实况（以后判断「机器能不能再开一个」时对照）：这台 Mac 是 10 核 / 16 GB 的 M4，磁盘
460 GB。同时开着 5 台模拟器、4 个 xcodebuild（40 个 swift-frontend，其中一个窗口自己并行起了
三个）、一台上限 10 GB 的 Docker 虚拟机（只跑 Scorebook 的 Postgres）、8 个 Claude 会话；
负载 54、交换区 12 GB 打满、磁盘只剩 15 GB——其中 117 GB 是各窗口自建的 57 台模拟器攒的数据，
另外约 100 GB 是散在 /tmp 和仓库里的十几份 DerivedData / .build / cargo target。交换区没地方长，
macOS 就开始杀进程，这就是他看到的「应用崩溃」。

所以在看盘里这是一条长期规矩（规则原文在仓库 AGENTS.md「机器资源纪律」，工具是
`scripts/machine-guard.sh`）：

- **派子代理或起编译之前先跑 `scripts/machine-guard.sh status`**；负载、交换区、磁盘超预算时
  子代理串行派、不并行派，会跑编译的子代理同一时刻最多两个。「根据实际情况来」是他的原话，
  不是「默认能并行就并行」。
- **重活一律经 `make` 目标或 `scripts/machine-guard.sh run`**，它会排队、nice 10；不裸跑
  xcodebuild，一个窗口不同时起两个编译。预算按点数记：重活（xcodebuild 跑测试 / 带模拟器目标）2 点、轻活（swift/cargo）1 点，基础 4 点，机器空闲（内存 ≥ 35%、交换 ≤ 4 GB、CPU 空闲 ≥ 25%）时自动放宽到 6 点，空闲内存 ≥ 50% 再放到 8 点；瓶颈是 16 GB 内存不是 CPU（实测 3 重活 + 2 模拟器就把空闲内存压到 31%）；开机模拟器最多 2 台、
  磁盘空闲 ≥ 40 GB、交换区 ≤ 8 GB。
- **模拟器只维护两台**：iPhone 16 Pro、iPhone 17 Pro Max。同一天用户先说四台
  （16 Pro / 16 Pro Max / 17 Pro / 17 Pro Max），几分钟后又说「机器再去掉几个，只维护
  16 Pro 和 17 Pro Max，如果后续有新的需求再说」。矩阵、截图、验收都按这两台来，不再建
  别的机型、更不给每个窗口建整套副本；一个窗口同一时刻只用一台，用完关机。兼容范围
  （iOS 26.6 以上与 27）见 kanpan-min-ios-26-and-ipad-scope。
- **可再生资源用完即删**：DerivedData、.build、cargo target、/tmp 构建目录、关机模拟器里攒的数据、
  工具缓存、Docker 无用镜像。任务做完就 `scripts/machine-guard.sh clean`，不要留到磁盘告急。
  不删源码、证据、`DerivedData-archive`（TestFlight 归档）和线上服务。
- **Docker 按需**：用的时候再开，用完退出（`osascript -e 'quit app "Docker"'`）；虚拟机上限
  已降到 3 GB。
- **僵尸进程要清**：会话结束后残留的 xcodebuild / xctest / swift-frontend / launchd_sim / cargo，
  父进程已经没了的一律杀掉（`scripts/machine-guard.sh zombie-gc`，看门狗每分钟也会做）。
- **Surge、ChatGPT、Claude（app 与 `claude remote-control`）是必须活着的**，看门狗掉了就拉起。

## 「任务慢了很多」的根因：遥控宿主把所有会话钉进了后台节流带（2026-09-23 下午）

用户下午说「我发现任务的速度变慢了很多」。查下来不是排队太保守，而是遥控宿主的
LaunchAgent `~/Library/LaunchAgents/com.mdd.kanpan.remote-control.plist` 写着
`ProcessType=Background`：宿主、它下面全部 Claude 会话、会话起的每个 xcodebuild /
swift-frontend 都继承进 macOS 的后台节流带（`ps -o pri=` 显示 4），Apple Silicon 只让这一带
用 6 个能效核，4 个性能核一直空着——之前观察到「CPU 空闲常年 35–40%」就是这 4 个核。
同一段 CPU 循环在会话里 5.64 s，`launchctl submit` 起的 0.53 s；`nice`、`taskpolicy -B/-c`、
`setpriority(PRIO_DARWIN_PROCESS)`、`launchctl asuser` 都出不了这个带。

所以以后：

同一天傍晚用户把目标说得更明确：「**在保证不崩溃的情况下最大限度使用资源。不要浪费。**」
所以守门的目标函数不是「保守」，是两头都要：不让 macOS 杀进程（内存、交换区、磁盘的红线
不能破），但红线以内的 CPU、内存、槽位空着就是浪费——性能核闲着、槽位没发满、
Docker 没人用还开着、都算浪费。审查资源调度时要同时报两边：有没有崩溃风险，
以及有多少资源在闲置、为什么闲置。

- **判断「慢」先看 `ps -o pri= -p $$`**，是 4 就是在节流带里，别先去怀疑排队预算或机器负载。
- **重活一律经 `scripts/machine-guard.sh run`**：它发现自己在节流带时会把命令交给 launchd 起
  （正常带 pri 20，仍 renice 10 让 Surge / ChatGPT / Claude 优先）。会话里裸跑的编译只能用能效核。
- **装遥控宿主的 LaunchAgent 时绝不写 `ProcessType=Background`**，用 `Standard`。改完 plist
  必须 `launchctl bootout` 再 `launchctl bootstrap`——2026-09-23 实测 `kickstart -k` 只是杀掉重启进程，
  launchd 不重读 plist，`launchctl print` 里 `spawn type` 仍是 `background (5)`，改了等于没改。
  改 plist、bootout/bootstrap、以及「延时脱离脚本去重启」在会话里都会被自动模式分类器拦
  （「持久化」），要打包成桌面上的一个脚本交给用户在终端里跑（`~/Desktop/kanpan-fix-host.sh`
  已经是修正后的版本），而且重启会掐掉他所有在跑的窗口，要提醒他挑没有任务在跑的时候做。
  验证生效的判据：`ps -o pri= -p $$` ≥ 20、`launchctl print` 里 `spawn type` 不再是 background。
