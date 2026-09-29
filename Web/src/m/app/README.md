# 手机网页版 · 壳、令牌与控件合同

入口 `Web/m/index.html` → `/web/m/`（本机 `http://localhost:5178/web/m/`）。总说明见 `docs/手机网页版-2026-09-29.md`。
本文件是**各页与壳之间的合同**：写页面只需要看这里。

## 1. 页面合同

四个整页，与底栏四格一一对应：`chart` `favorites` `sectors` `me`（hash 路由 `#chart` …）。

每页一个模块 `Web/src/m/pages/<id>.ts`，导出：

```ts
import type { PageHandle } from '../app/shell'
export function initFavorites(root: HTMLElement): PageHandle   // 名字 = 'init' + 首字母大写的 id；也认 default 导出
// PageHandle = { show(): void; hide(): void; reselect?(): void }
```

- `root` 是壳建好的 `<section class="page" id="page-<id>">`，页往里面填内容。
- `main.ts` 用 `import.meta.glob('./pages/*.ts')` 懒加载：先挂当前页，其余空闲时挂。模块不存在 / 没导出 init / 抛错时挂「即将到来」占位，不挡别的页。
- `show()` 每次切到这一页都调（首次紧跟在 init 之后）；`hide()` 离开时调。`reselect()`：已经站在这页又点了一次底栏那一格（回到本页的根；不给就滚回顶部）。
- 搜索、提醒、弹层里的二级页不是整页：用 `ui/sheet.ts` 的面板，或在本页 root 里自己推层。

### 页的滚动与布局

- 默认 `section.page` 自己就是滚动容器，已经留好：顶 `--safe-top`、左右安全区、底 `--tabbar-clearance`（底栏 + 渐变 50）。滚动位置由壳自动记、冷启动接回（异步渲染的内容也会等它长高再接）。
- 想要固定头 + 内部滚动列表：给 root 加类 `page-fixed`（section 不滚、没有内边距，安全区自己用 `var(--safe-top)` 等垫），内部滚动容器调 `trackScroll(el, '<页>.<名>')` + `restoreScroll(el, '<页>.<名>')`（`app/shell.ts`）。
- 页底色：在页的 css 里给 `#page-<id>` 设 `--page-bg`（默认 `var(--app)`）；底栏身后那道渐变会自动用同一个变量收尾——壳把底栏打上 `data-page="<id>"`，也可以写 `.m-tabbar[data-page="favorites"] { --tabbar-fade: … }` 单独指定。行情页不铺渐变。

### 壳提供的（`app/shell.ts`）

| 名字 | 用途 |
|---|---|
| `go(page, { fromTab? })` | 切页（关掉所有弹层、收回左划） |
| `openSymbol(sym)` | 点一行打开图：记最近打开、记来路 `nav.origin`、切到 `chart`、广播 `hooks.onSymbol` |
| `nav.origin` | 图表页的来路（从自选 / 板块点进来时是那一页；点底栏作废），图表页顶栏据此画「‹」 |
| `setMeBadge(n)` | 「我的」记号右上角的待判定条数（0 不画，封顶 99） |
| `hooks.onTheme` | 皮肤 / 深浅 / 涨跌色变了（画布在这里重取颜色） |
| `hooks.onForeground` / `onBackground` | 切前后台（行情 WS 由 `market/stream.ts` 自己重连；页面在这里补拉 REST）。同时发 `window` 事件 `hkline:foreground` |
| `hooks.onPage(page, prev)` / `hooks.onSymbol(sym)` | 换页 / 换品种之后 |
| `applyTheme()` | 改了 `st.theme / skin / redUp` 之后调（再 `save()`） |
| `trackScroll` / `restoreScroll` | 自管滚动容器的现场 |

### 状态（`app/store.ts`）

`st` 是唯一的可变状态（`localStorage['hkline-m-v1']`），改完调 `save()`（立刻落盘并通知 `subscribe` 的订阅者，不节流）。
字段：iOS `Prefs` 全部（`app/prefs.ts`，同名同义；`SYNCED_FIELDS` 进账号同步）+ `page` `symbol` `scroll` `symbols{ favorites, recents, groups, groupForSymbol, seeded }` + 不落盘的 `stale`。
账号用 `Web/src/account/*`（入口已 `configureAccount({ keyPrefix: 'hkline-m', kind: 'phone' })`，键名与 PC 版分开）。

## 2. 设计令牌（`styles/tokens.css`，名字定了不改）

`<html>` 上三个开关：`data-skin = sage | terra | classic`、`data-theme = light | dark`、`data-updown = red-up | green-up`。

- 字：`font: var(--t-price | --t-title | --t-heading | --t-body | --t-body-emph | --t-control | --t-control-on | --t-footnote | --t-footnote-emph | --t-caption | --t-caption-emph | --t-caption2 | --t-caption2-emph | --t-number)`；字体栈 `--font-ui` `--font-num`。数字加类 `.num`（等宽数字）。
- 间距 `--s-xxs/xs/s/m/l/xl/xxl/section` = 2/4/8/12/16/20/24/32；内边距 `--inset-page`（16，≥428 宽 20）`--inset-card` 16 `--inset-card-compact` 12 `--inset-row-v` 12 `--row-min` 44。
- 圆角 `--r-xs/s/m/l` = 4/8/12/16；尺寸 `--hit` 44 `--pill-h` 28 `--icon-disc` 32 `--badge` 28 `--list-badge` 32 `--chevron` 12 `--empty-glyph` 36 `--disabled-opacity` 0.4。
- 安全区 `--safe-top/bottom/left/right`；底栏 `--tabbar-h`（58）`--tabbar-clearance`。
- 动效 `--ease-spring` `--ease-out` `--dur-fast` 160ms `--dur` 280ms `--dur-page` 340ms。
- 颜色：`--ground --app --chart --raised --raised2 --line --grid --hair --ink --ink2 --ink3 --stale --amber（图上暖金）--accent（界面强调色）--danger --accent-soft --accent-line --badge-ink --control-line --seg-on --veil --scrim`、`--palette-0..5` `--sub-0..5`。
- 图外文字涨跌 `--up --down`（已按 data-updown 对调；类 `.up` `.down`）；行情停住 `.stale`。
- K 线画布 `--k-up --k-down`（蜡烛本色，已对调）`--k-bg --k-grid --k-axis --k-text --k-dim --k-ink --k-cross --k-amber --k-band --k-oi --k-oi-fill --k-chip --k-panel --k-cross-bg --k-cross-ink --k-hair --k-amber-soft --k-amber-line`；订单流 `--of-contract-bid/ask --of-spot-bid/ask`。
- 釉 `--glaze-accent-a/b --glaze-accent-light-a/b --glaze-gold-a/b`，`--glow` `--glyph-shadow` `--toast-shadow`。
- 画布读色：`getComputedStyle(document.documentElement).getPropertyValue('--k-up')`，在 `hooks.onTheme` 里重读。

## 3. 小控件（`Web/src/m/ui/`）

| 文件 | API | 照 iOS |
|---|---|---|
| `icons.ts` | `glyph(name, size=27, cls?)`：实心带釉记号 `chart favorites sectors me review draw`；`icon(name, size=17, cls?)`：线框小图标 `chevron search star chevronRight chevronLeft style draw settings chart adjust landscape close more plus check trash grip question share bell`（描边 currentColor）。都返回 SVG 字符串 | `Main/TabBar.swift`、`Main/VectorIcon.swift` |
| `sheet.ts` | `openSheet(build(body, sheet), { title, subtitle, action:{title,run}, detent:'medium'｜'large'｜'auto', expandable, modal=true, noBack, onClose, className, id }) → Sheet{ root, body, close, setTitle, setDetent, push(title, build), back, closed }`；`openPopover(anchor, build(root, pop), { onClose, className, cover })`（从 anchor 下沿展开、盖在内容上、下方遮罩）；`openMenu(anchor, items[], onClose?)`（`MenuItem{ title, icon?, destructive?, checked?, disabled?, run }`，`null` 为分隔）；`confirmDialog({ title, message?, confirm?, cancel?, destructive? }) → Promise<boolean>`；`closeAllSheets()` `sheetOpen()` | `PanelChrome.swift` PanelSheet、`PanelPresentation.swift`、`IntervalGridPopover.swift` |
| `swipeDelete.ts` | `swipeRow(row, { trailing?, leading?, brick:'flush'｜'pill', fullSwipe=true }) → { close, isOpen, destroy }`；`deleteAction(run, title='删除')`；`SwipeAction{ id, title, fill?, destructive?, run }`；`closeOpenSwipe()`。行底色用 `--sw-bg`（默认 `--app`） | `DesignSystem/SwipeToDelete.swift` |
| `reorder.ts` | `reorderable(list, { item, handle?, longPress=350, enabled?, onMove(from, to) }) → { destroy }`；`moveIndex(arr, from, to)`；`longPress(el, run, ms=450) → 解绑` | `List.onMove` |
| `hint.ts` | `termMark(term) → HTMLButtonElement`；`registerTerms([...])` + `termHTML(id)`（拼模板用，点击全局委托）；`showTerm(term)`；`Term{ id, title:'短标签 · 全称', body }` | `Glossary/TermMark.swift`、`GlossaryCard.swift` |
| `toast.ts` | `toast(text, action?: { title, run })`（带动作停 5 秒，否则 1.6 秒，新的顶掉旧的）；`dismissToast()` | `Main/ToastCenter.swift` |
| `dom.ts` | `esc` `el(tag, cls, html)` `scrollParent` `nextFrame` `reducedMotion` `layer()`（最上层 `#m-layer`）`safeArea()` | — |

样式在 `styles/ui.css`（类名前缀 `m-`），各页自己的 css 放 `styles/<页>.css` 并在页模块里 `import`。
