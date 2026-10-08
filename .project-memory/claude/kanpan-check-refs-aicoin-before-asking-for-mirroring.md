# kanpan-check-refs-aicoin-before-asking-for-mirroring

**项目约定**：要确认 AICoin 某个交互怎么做的时候，先查仓库里的逆向素材 refs/aicoin（反编译 java + res-full 布局 + reports），查不到才请用户开 iPhone 镜像

2026-09-20 用户问「连续看图是不是像 AICoin 那样在 K 线区横滑切品种」，我回答说这一点我证不了，
请他开 iPhone 镜像我才能核对。他的回复是：「**不是有逆向文件吗，你可以看看怎么实现的**」。

看盘仓库里 `refs/aicoin/` 就是 AICoin 安卓包的一手逆向素材（jadx 反编译），足以回答绝大多数
「AICoin 这个交互是怎么做的」的问题：

- `refs/aicoin/res-full/layout/`：全量布局 XML。页面骨架用了什么容器一眼可见——比如
  `act_ticker_detail.xml` 里整页内容装在 `app.aicoin.common.widget.GestureViewPager` 里，
  这就是「整页左右滑翻品种」的直接证据。
- `refs/aicoin/res-full/values-zh-rCN/strings.xml`：文案权威来源（设置项叫什么、二选一怎么措辞）。
- `refs/aicoin/java/`：图表自绘层与手势层。`java/Wj/a.java` 是手势分发，能看出图自己什么时候
  `requestDisallowInterceptTouchEvent` 把手势从父容器抢走。
- `refs/aicoin/reports/`：已经写好的代码级报告（手势状态机取值表、蜡烛几何、指标、资源），
  先读报告往往比自己读混淆代码快。
- `docs/AICoin-前端全量盘点-2026-09-17.md` 与 `docs/AICoin-盘点原始清单-2026-09-17/`：
  按页面模块整理过的清单，适合先定位到是哪个布局文件。

所以顺序是：**先查 refs/aicoin 与那两份盘点文档，用文件名 + 行号给出证据；确实只有运行时才看得出来的
（动效时长、手感、视觉细节）才请用户开 iPhone 镜像。** 不要一上来就把问题推回给用户。
这条是 kanpan-aicoin-reference-is-the-phone-app（真机 AICoin 才是最终基准）的前置步骤，
不冲突：证据等级仍然是真机实测 > 反编译源码，但反编译素材已经在仓库里，不查就说「证不了」是偷懒。
