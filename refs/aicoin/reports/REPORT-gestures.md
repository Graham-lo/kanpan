# AICoin Android — 图表手势 / 缩放语义提取报告

- 材料：jadx 反编译产物，根目录 `/private/tmp/claude-501/-Users-mdd-kanpan/e5a5bf1c-f427-4144-8ae2-a961a321a4b4/scratchpad/aic/src/sources/`
- 本报告所有 `文件:行号` 均相对上述根目录。
- **只读分析**，未修改任何项目代码。
- 标注约定：
  - 无标注 = **代码里确凿读到的**（附原始片段）。
  - `【推断】` = 我的推理，会说明依据。
  - `【未找到】` = 穷举 grep 后没有证据，不编。
- 单位约定：`Xj/a.java` 里 `a(float)`/`b(int)` = **dp→px**，`c(float)`/`d(int)` = **sp→px**（底层 `nk.l.o(1,f)` / `nk.l.o(2,f)`，1=COMPLEX_UNIT_DIP，2=COMPLEX_UNIT_SP）。Android dp ≈ iOS pt 按 1:1 换算。**sp 受系统字体缩放影响**，在 iOS 侧应按 1:1 当 pt 用，但要记住它在 Android 上会随字体大小变。

---

## 0. 整体架构（读懂后面几节的前提）

- 图表是一个自绘 `View`：`sp/aicoin_kline/chart/Chart.java`（878 行，`extends android.view.View`）。
- 手势全部在 `Wj/a.java`（570 行）—— **一台以整型 mode 为状态的有限状态机**，这是最关键的文件。
- 惯性/fling 在 `Rj/C2746s.java`。
- 横向视口（缩放 + 平移 + 十字光标列索引）在 `Rj/y1.java`（650 行）。
- 纵向价格轴（自动范围 + 手动 Y 缩放）在 `Rj/AbstractC2759w0.java`（564 行）。
- 面板高度分配在 `Rj/L0.java`。
- 区域命名规则：`<模板>.main`（K 线数据区，`Data`）、`<模板>.mainRange`（右侧价格轴条，`Range`）、`<模板>.mainTimeline`（时间轴）、`.indic0/.indic1/...`（副图）；绘制层后缀 `.m`（主指标）`.a`（辅助）`.b`（背景）`.s`（选中/十字线）`.d` `.hd` `.i`。
  证据 `Rj/C2757v1.java:1078`：
  ```java
  public static void n(C2732n c2732n, String str, L0 l10, boolean z10) {
      C2702d c2702d = new C2702d(str);
      c2702d.D(C2702d.a.Data);      ...
      C2702d c2702d2 = new C2702d(kk.i.a(str, "Range"));
      c2702d2.D(C2702d.a.Range);    ...
  }
  ```
- `Rj/C2702d.java` 是矩形区域：`u()/z()/y()/p()` = left/top/right/bottom，`A()` = 宽，`t()` = 高，`k(x,y)` = 命中测试，`m(y)` = y 在区间内。

### 手势状态机的 mode 取值（`Wj/a.java`，字段 `f24751k` = 当前 mode，`f24752l` = 上一次 mode）

| mode | 含义 | 证据行 |
|---|---|---|
| 0 | 手指按下，尚未判定 | `Wj/a.java:433` |
| 1 | 横向平移 | `Wj/a.java:~500` |
| 2 | 十字光标 | `Wj/a.java:196` / `:519` |
| 3 | 双指缩放（最新一根不在屏内） | `Wj/a.java:~460` |
| 4 | 双指缩放（最新一根在屏内，走 `y1.P()` 保持右端） | `Wj/a.java:~460` |
| 5 | 判定为竖直滑动，交还给父容器（不拦截） | `Wj/a.java:~505` |
| 6 | 画线工具手柄拖动 | `Wj/a.java:~130` |
| 8 | **价格轴 Y 缩放** | `Wj/a.java:~490` |
| 9 | **价格窗口上下平移** | `Wj/a.java:~498` |

---

## 1. 左右缩放（K 线粗细 / 一屏根数）

### 1.1 用的不是系统 `ScaleGestureDetector`，是 AOSP 源码的逐字拷贝

`Wj/b.java`（281 行）是 AOSP `ScaleGestureDetector` 的完整复制（同名的 `OnScaleGestureListener` 被改成内部 `c` 类）。

```java
// Wj/b.java:~60
this.f24778q = ViewConfiguration.get(context).getScaledTouchSlop() * 2;   // mSpanSlop
this.f24779r = 50;                                                        // mMinSpan = 50 px（硬编码，不是 dp）
...
float fHypot = a() ? f16 : (float) Math.hypot(f15, f16);   // 各向同性的 2D span
public float b() { return this.f24764c; }                  // focusX
public float c() { ... return this.f24768g / f10; }        // scaleFactor = curSpan / prevSpan
```

**quick-scale（双击后上下拖动缩放）被显式关闭**，长按也被关闭（长按由自己的 Handler 接管）：

```java
// Wj/a.java:244-260
Wj.b bVar = new Wj.b(context, new d());
GestureDetector gestureDetector = new GestureDetector(context, new C0387a());
this.f24752l = -1;
this.f24757q = 1.0d;
gestureDetector.setIsLongpressEnabled(false);
bVar.e(false);                       // quick-scale OFF
this.f24753m = ViewConfiguration.get(context).getScaledTouchSlop();
```

### 1.2 缩放变量与上下限：`scale ∈ [0.4, 10.0]`

```java
// Wj/a.java:207-242
public final class d extends Wj.b.c {
    public float f24760a = 1.0f;
    public boolean a(Wj.b bVar) {           // onScaleBegin
        this.f24760a = C2760w1.f19594a.i();     // 取全局当前 scale
        return super.a(bVar);
    }
    public void b(Wj.b bVar) {              // onScaleEnd
        C2760w1.f19594a.l(this.f24760a);        // 写回全局，跨图表重建保留
    }
    public boolean c(Wj.b bVar) {           // onScale
        if (a.this.f24751k == 2) return true;   // 十字光标期间禁止缩放
        this.f24760a = Math.max(0.4f, Math.min(this.f24760a * bVar.c(), 10.0f));
        y1 y1VarG = a.g(a.this);
        if (y1VarG != null) y1VarG.Q(this.f24760a, bVar.b());   // 以 focusX 为锚点
        a.this.f24741a.invalidate();
        return true;
    }
}
```

- `C2760w1` 是全局单例：`Rj/C2760w1.java` —— `public static float f19600g = 1.0f;`，`i()` 读、`l(f)` 写。**缩放比例是全局的、跨周期切换/图表重建保留的**。

### 1.3 蜡烛列宽公式：`colWidth = scale × 12.0f`（原始 px）

```java
// Rj/y1.java:129 构造
this.f19622h = 1.0f;                 // scale
this.f19626l = c.CENTER;             // 锚定模式
this.f19627m = Xj.a.a(30.0f);        // 右侧默认留白 30dp
this.f19631q = 12.0f;                // 基准列宽 = 12 原始 px

// Rj/y1.java:287  Q(scaleFactor, focusX)
public final void Q(float f10, float f11) {
    this.f19622h = f10;
    float f12 = f10 * 12.0f;
    this.f19631q = f12;                              // colWidth
    float f13 = this.f19625k;
    float f14 = f12 * this.f19634t;
    this.f19625k = f14;                              // 内容总宽
    this.f19624j = Math.max(0.0f, f14 - this.f19635u);   // 最大滚动量
    this.f19636v = (int) (this.f19635u / this.f19631q);  // 可见根数
    int i10 = b.f19641a[this.f19626l.ordinal()];
    if (i10 == 1)       fG = this.f19624j - g();         // RIGHT：保持钉在最右
    else if (i10 == 2)  fG = Math.min((nk.A.d(this.f19623i + f11, f13, 0.0f) * f14) - f11,
                                       this.f19624j - g());   // CENTER：保持 focusX 处的内容不动
    this.f19623i = fG;
    ...
}
```

**关键数值（confirmed）：**
| 项 | 值 |
|---|---|
| 基准列宽 | `12.0f` **原始 px** |
| scale 范围 | `[0.4, 10.0]` |
| 实际列宽范围 | `4.8 px ~ 120 px` |
| 可见根数 | `viewportWidthPx / colWidth`，**没有额外的根数上下限**，完全由列宽夹紧推出 |

`【推断】` `12.0f` 是**原始像素、不随屏幕密度变化**：依据是它没有过 `Xj.a.a()`（dp→px）包装，而且直接和像素单位的视口宽 `f19635u` 相除得到可见根数。若如此，在 3x 屏上 1 列 = 12px = 4pt，一屏 (390pt=1170px) 最多约 `1170/4.8 ≈ 243` 根、最少约 `1170/120 ≈ 9.75` 根。**注意这与「一屏 2000 根」的目标差距很大** —— AICoin 在最小列宽 4.8px 下一屏也就 200 多根。

### 1.4 缩放锚点 = 双指中心 focusX（连续、无档位）

- 锚点：`y1VarG.Q(this.f24760a, bVar.b())`，`b()` 即 `ScaleGestureDetector.getFocusX()` → **手指中心**，不是屏幕中心也不是最右一根。
- `Q()` 内按 `f19626l`（`c.LEFT/CENTER/RIGHT`）分三种重新钉位：
  - `RIGHT`（当前贴着最右）→ `offset = maxOffset - g()`，**继续贴最右**；
  - `CENTER` → 保持 focusX 处的时间位置不动；
  - `LEFT` → 走同一路径钉在左端。
- **连续缩放，无档位/无吸附**：`f24760a * bVar.c()` 是浮点连乘，`Q()` 里无任何取整或档位表。
- **无阻尼、无回弹**：`Math.max(0.4f, Math.min(..., 10.0f))` 是硬夹紧，超出后 `scaleFactor` 继续乘但被截断，松手也没有回弹动画。`【未找到】` 任何 scale 的 spring/overshoot 代码。

### 1.5 双指时的 mode 选择

```java
// Wj/a.java:~460
if (motionEvent.getPointerCount() > 1) {
    this.f24754n.removeMessages(1);          // 取消长按计时
    this.f24751k = y1VarM2.M() ? 4 : 3;      // 最新一根可见 → 4，否则 → 3
}
```
`M()`（`Rj/y1.java:241`）判断"最新一根是否在屏内"：
```java
public final boolean M() {
    float f10 = this.f19624j - this.f19623i;
    float f11 = this.f19631q;
    float f12 = f10 - (400 * f11);
    return f12 < f11 && f12 > (-f11);
}
```

---

## 2. 上下缩放（价格轴缩放）

### 2.1 移动端**支持**，触发方式 = **在右侧价格轴条上竖直拖动**

触发判定（`Wj/a.java:~478`，mode 8）：
```java
C2702d c2702dE = this.f24745e.e(this.f24742b + ".mainRange");
if (c2702dE == null || !c2702dE.k(f12, f13) || fAbs4 < this.f24753m || fAbs4 < fAbs3) {
    ... // 不在价格轴上 → 走横向平移 / 价格窗口平移 / 交还父容器
} else {
    // 起点落在 .mainRange 内、且竖直位移 > touchSlop 且 |dy| > |dx| → Y 轴缩放
    float y11 = motionEvent.getY();
    if (w0 != null && w0.j(y11)) {
        this.f24756p = y11;            // 记录起始 y
        this.f24757q = w0.B();         // 记录起始 Y scale
        this.f24751k = 8;
        this.f24754n.removeMessages(1);
        b(motionEvent.getY());
    } else { this.f24751k = 5; ... }
}
```

- **不是双指竖直捏合**。`Wj/b.java` 的 span 是各向同性的 `hypot(dx,dy)`（`a()` 返回 false 时），**双指竖直捏合会被当成普通横向缩放**。`【未找到】` 任何区分 X/Y 方向的双指缩放逻辑。

### 2.2 缩放公式：指数式，**每拖动「价格轴高度 / 4」像素翻一倍**

```java
// Wj/a.java:309-326
public final void b(float f10) {
    AbstractC2759w0 abstractC2759w0L = this.f24745e.l(this.f24742b + ".main");
    if (abstractC2759w0L == null) return;
    C2702d c2702dE = this.f24745e.e(this.f24742b + ".mainRange");
    if (c2702dE == null) return;
    abstractC2759w0L.W(Math.pow(2.0d,
        ((double) (-(f10 - this.f24756p))) / Math.max(((double) c2702dE.t()) / 4.0d, 1.0d))
        * this.f24757q);
    ...
}
```
即 `yScale = yScale0 × 2^( -(y - y0) / max(axisHeight/4, 1) )`。
**向上拖 = 放大**（`y` 变小 → 指数为正）。

### 2.3 Y scale 上下限 `[0.03, 16.0]`，并有「±2% 吸附回 1.0」

```java
// Rj/AbstractC2759w0.java:429
public final void W(double d10) {
    if (this.f19585r > this.f19584q) {
        double dMin = Math.min(16.0d, Math.max(0.03d, d10));   // 夹紧 [0.03, 16.0]
        if (Math.abs(dMin - 1.0d) <= 0.02d) dMin = 1.0d;       // ±2% 吸附回 1
        if (this.f19586s != dMin || this.f19590w) {
            this.f19586s = dMin;
            if (dMin == 1.0d) this.f19587t = 0.5d;             // 回到 1 时锚点回正中
            if (... "main" ... && this.f19586s != 1.0d) chartA.F(true);   // 亮起「A」按钮
            ...
        }
    }
}
```

### 2.4 手动 Y 缩放**在横向平移后保持**，不会自动回到 auto-fit

- `f19586s`（Y scale）和 `f19587t`（竖直锚点比例）是 `AbstractC2759w0` 的持久字段，横向滚动不清它们。
- `k()`（`Rj/AbstractC2759w0.java:499`）就是「当前 Y 是否被手动缩放过」的查询：
  ```java
  public final boolean k() {
      return this.f19585r > this.f19584q && this.f19578k > this.f19577j
          && this.f19576i > 0.0d && this.f19586s != 1.0d;
  }
  ```
- 手动缩放后，**价格窗口可以上下平移**（mode 9），触发条件在 `Wj/c.java`（全文 16 行）：
  ```java
  public final float a(float f10) { return -f10; }
  public final boolean b(float f10, float f11, int i10, boolean z10, boolean z11) {
      return z10 && z11 && f11 >= ((float) i10) && f11 > f10 * 1.5f;
  }
  // = 落在主图内 && Y 已被手动缩放 && |dy| >= touchSlop && |dy| > |dx| * 1.5
  ```
  即：**只有在 Y 已经被手动缩放之后**，主图区内的竖直拖动才会变成"上下平移价格窗口"；否则竖直拖动直接交还给父容器（mode 5）。
- 平移的锚点被夹在一个和 scale 相关的区间里（`Rj/AbstractC2759w0.java:88`，静态内嵌类 `a`）：
  ```java
  public final double a(double d10, double d11) {   // d10=scale, d11=目标锚点比例
      if (... || Math.abs(d10 - 1.0d) <= 0.02d) return 0.5d;
      double d12 = 1.0d / (2.0d * d10);
      Qf.p pVar = d10 <= 1.0d ? new Qf.p(d12 - 3.0d, (1.0d - d12) + 3.0d)
                              : new Qf.p(d12 - 0.75d, (1.0d - d12) + 0.75d);
      return p292ng.i.n(d11, Math.min(...), Math.max(...));
  }
  ```
  `【推断】` 放大时（scale>1）允许锚点越界 ±0.75 个视口高度；缩小时（scale≤1）允许 ±3 个视口高度。依据是这两个常量就是区间端点的外扩量。

### 2.5 **双击价格轴 = 恢复自动范围**（确有此交互）

```java
// Wj/a.java:88-112
public boolean onDoubleTap(MotionEvent motionEvent) {
    if (a.l(a.this, motionEvent.getX(), motionEvent.getY())) {   // l() = 命中 ".mainRange"
        a aVar = a.this;
        aVar.a();
        AbstractC2759w0 abstractC2759w0L = aVar.f24745e.l(aVar.f24742b + ".main");
        if (abstractC2759w0L != null && abstractC2759w0L.F()) {
            aVar.f24752l = 8; aVar.f24751k = -1;
            ... chart.u(); return true;
        }
    }
    C2738p.f19487a.f();
    return super.onDoubleTap(motionEvent);
}
```
```java
// Rj/AbstractC2759w0.java:175
public final boolean F() {          // 恢复自动
    if (this.f19585r <= this.f19584q) return false;
    this.f19590w = false;
    this.f19586s = 1.0d;
    this.f19587t = 0.5d;
    if (... "main" ...) chartA.F(false);      // 熄灭「A」按钮
    this.f19582o = this.f19584q; this.f19583p = this.f19585r;
    ... return true;
}
```
- **除双击外还有一个显式按钮**：资源报告里的 `tv_scale_auto`（"A"，12sp），由 `Chart.F(boolean)`（`sp/aicoin_kline/chart/Chart.java:231`）控制显隐 —— 只有当 `yScale != 1.0` 时才出现。
- 注意：**双击图表主体区（非价格轴）不做缩放**，只走 `C2738p.f19487a.f()` 回调（通知宿主，`【推断】`用于全屏/切换之类）。

### 2.6 Y 缩放时网格线密度变化

```java
// Rj/AbstractC2759w0.java:555
public final int y(int i10, double d10) {
    return p292ng.i.f(p208jg.c.c(((double) i10) * d10 * (this.f19586s != 1.0d ? 1.8d : 1.0d)), 1);
}
```
手动缩放状态下横向网格线/价格标签数量 **×1.8**。

---

## 3. 平移与惯性

### 3.1 用系统 `OverScroller`，默认摩擦系数

```java
// Rj/C2746s.java:99-102
this.f19535g = new OverScroller(context);                          // 默认 fling friction
ViewConfiguration viewConfiguration = ViewConfiguration.get(context);
this.f19536h = viewConfiguration.getScaledMinimumFlingVelocity();  // fling 阈值
this.f19537i = viewConfiguration.getScaledMaximumFlingVelocity();  // 速度上限
```
- `【未找到】` 任何 `setFriction()` 调用 → **用的是 Android 默认 fling 摩擦**（`ViewConfiguration.getScrollFriction()` = 0.015）。
- touchSlop = `ViewConfiguration.get(context).getScaledTouchSlop()`（`Wj/a.java:259`），典型值 8dp → **8pt**。
- fling 速度阈值 = `getScaledMinimumFlingVelocity()`，典型值 **50 px/s**（不是 dp）。

### 3.2 fling 只发生在单指、且当前 mode 不属于 {2, 6, 8, 9}

```java
// Rj/C2746s.java:155
public final void e(MotionEvent motionEvent) {      // ACTION_UP / ACTION_POINTER_UP
    if (motionEvent.getPointerCount() != 1) return;
    this.f19540l = false;
    this.f19538j = (int) motionEvent.getX();
    velocityTracker.computeCurrentVelocity(1000, this.f19537i);
    int xVelocity = (int) velocityTracker.getXVelocity();
    int iS = this.f19531c.s();                       // 上一次 mode
    if (Math.abs(xVelocity) > this.f19536h && iS != 2 && iS != 6 && iS != 8 && iS != 9) {
        this.f19535g.fling(this.f19538j, 0, xVelocity, 0,
                           Integer.MIN_VALUE, SubsamplingScaleImageView.TILE_SIZE_AUTO, 0, 0);
        this.f19530b.invalidate();
    }
    ...
}
```
即：**十字光标 / 画线拖柄 / Y 轴缩放 / 价格窗口平移之后松手，都不会甩惯性。** 只有纯横向平移会。
`fling()` 的 minX/maxX 给的是 `Integer.MIN_VALUE / TILE_SIZE_AUTO`（= `Integer.MAX_VALUE`）→ **scroller 本身不做边界，边界由业务层夹紧**。

### 3.3 边界 = **硬停，没有橡皮筋**

```java
// Rj/C2746s.java:107   computeScroll 的每帧回调
public final void a() {
    ...
    int currX = this.f19535g.getCurrX() - this.f19538j;
    this.f19538j = this.f19535g.getCurrX();
    if (y1VarM != null && y1VarM.O(currX)) {       // O() 返回 true 表示"到边了"
        if (currX > 0) C2738p.m();  else if (currX < 0) C2738p.p();   // 通知宿主到边
        b();                                        // forceFinished(true) → 立刻停
    }
    ...
}
```
`Rj/y1.java:255` 的 `O(float)`：
```java
public final boolean O(float f10) {
    float fG = g();
    float f11 = this.f19623i - f10;
    float f12 = 0.0f;  boolean z10 = true;
    if (f11 >= 0.0f) {
        f12 = this.f19624j - fG;
        if (f11 >= f12) { this.f19626l = c.RIGHT; }
        else { this.f19626l = c.CENTER; z10 = false; }
        this.f19623i = f11;
        this.f19629o = (-f11) % this.f19631q;
        this.f19630p = (-(f11 + this.f19635u)) % this.f19631q;
        return z10;
    }
    this.f19626l = c.LEFT;
    f11 = f12;              // == 0.0f → 左端硬夹到 0
    this.f19623i = f11; ...
    return true;
}
```
- **左端**：`offset` 直接夹到 0，硬停。
- **右端**：`【推断】`jadx 输出里看不到对 `f11` 的 `min()` 夹紧，只是把 `f19626l` 置为 `RIGHT` 并返回 `true`；fling 时靠 `C2746s.a()` 收到 `true` 后 `forceFinished` 停住。**手指拖动时的右端是否能拖过头、有没有视觉回弹，我没有在字节码层面验证**（该 APK 的 apktool 产物只有 `classes*.dex`，没有 smali 可交叉核对）。可确定的是：**代码里没有任何 spring / overshoot / 回弹动画**。

### 3.4 右侧允许的空白：**默认 30dp = 30pt**，可设置为 2/3 屏或 1/2 屏

```java
// Rj/y1.java:481
public final float g() {
    float f10;
    int iQ = this.f19632r.q(18);
    if (iQ == 0)      f10 = this.f19627m;                          // 30dp（默认）
    else if (iQ != 1) f10 = iQ != 2 ? this.f19627m : this.f19635u / 2;   // 2 → 半屏
    else              f10 = (this.f19635u / 3) * 2;                // 1 → 2/3 屏
    return Math.min((400 * this.f19631q) - f10, this.f19624j);
}
```
`q(18)` 的默认值经 `KLineManager.r(int)`（`sp/aicoin_kline/core/KLineManager.java:696`）确认为 **0**（18 不在 `{0}`/`{10,12,15,17}`/`{5}`/`{6,7,8,24,25}` 任何一组里 → `return 0`）→ **默认 30dp = 30pt 空白**。

### 3.5 `400` 这个常量 = **数据尾部补的 400 根虚拟空 K 线**

```java
// Rj/C2765z.java:310-320
public final int B() { return this.f19663i.size(); }        // 含虚拟根的总数
public final int D() { return Math.max(0, B() - 400); }     // 真实根数
```
```java
// Rj/C2765z.java:960-968  全量刷新分支
this.f19661g = ((Sj.b) aVar2.a().get(1)).e() - ((Sj.b) aVar2.a().get(0)).e();   // 周期毫秒
long jE2 = ((Sj.b) aVar2.a().get(aVar2.a().size() - 1)).e();
GregorianCalendar gregorianCalendar2 = new GregorianCalendar();
gregorianCalendar2.setTime(new Date(jE2));
for (int i16 = 0; i16 < 400; i16++) {
    gregorianCalendar2.add(13, (int) (this.f19661g / ((long) 1000)));
    aVar.add(new Sj.b(gregorianCalendar2.getTime().getTime(), Double.NaN, Double.NaN, Double.NaN, Double.NaN, Double.NaN));
}
```
所以 `f19634t`（总列数）里包含 400 根 OHLC 全是 `NaN` 的未来占位根；`g()` 的 `400 * colWidth - blank` 就是"把这 400 根里除了 `blank` 宽度以外的全部滚到屏外"的位置，也就是**「回到最新」的归位点**。

### 3.6 归位 / 居中

```java
// Rj/y1.java:225   回到最新（"回到最新"按钮 tv_back_to_last 触发）
if (this.f19623i != (this.f19624j + this.f19628n) - (400 * this.f19631q)) { P(); return; }
O(-this.f19625k);            // 先滚到最左
... O(f10);                  // 再往右滚 blank
```
```java
// Rj/y1.java:~600  把某个时间戳滚到屏幕正中
public final void S(long j10) {
    ... O(this.f19623i - (((iIntValue + 0.5f) * this.f19631q) - (this.f19635u / 2.0f)));
}
```
新增一根时的处理（`Rj/y1.java:423` `b0()`，按 `C2765z.X()` 的更新模式 1/3/4 分支）：
- 模式 4（前插一根）→ `O(this.f19635u / 10)`（`【推断】`补偿式微调，让画面看起来不跳）
- 模式 1/3（全量/追加）→ 重新钉回 `O(400 * colWidth)`

---

## 4. 十字光标 / 长按

### 4.1 长按时长 = **400 ms**

```java
// Wj/a.java:430-437
if (action2 == 0) {
    this.f24749i = motionEvent.getX(); this.f24750j = motionEvent.getY();
    this.f24752l = -1; this.f24751k = 0;
    this.f24754n.sendEmptyMessageDelayed(1, 400L);    // 长按计时器
}
```
```java
// Wj/a.java:194-205   Handler
// 到点后调用 q(aVar, f24749i, f24750j) → f24751k = 2; y1.Y(true); r(); invalidate();
```
另一条路径：**按住超过 400 ms 后再拖动也进入十字光标**：
```java
// Wj/a.java:~516
} else {        // eventTime >= 400
    this.f24751k = 2;
    this.f24743c = x11; this.f24744d = y12;
    y1VarM3.Y(true); r(); invalidate();
}
```
注意 `gestureDetector.setIsLongpressEnabled(false)`（`Wj/a.java:252`）—— 框架长按被关掉，用的是自己的 400ms Handler。Android 框架默认长按是 500ms，**AICoin 比系统更快 100ms**。

### 4.2 **没有任何震动反馈**

`【已穷举验证】`对 `Rj/`、`Wj/`、`Xj/`、`sp/aicoin_kline/` 全目录 grep `performHapticFeedback` / `Vibrator` / `VibrationEffect` / `HapticFeedbackConstants` —— 零命中。

### 4.3 十字光标出现后的单指拖动 = 跟随，竖线**始终吸附到列中心**

```java
// Wj/a.java:114-155   onScroll 的 mode 分派
// mode 2 → 十字光标跟随；6 → 画线手柄；8 → b(y) 轴缩放；9 → m(a, f11) 价格窗口平移；
// 4 → y1.P()；default → y1.O(-f10) 横向平移
```
竖线 X 的取值是 `y1.C(...)` = `getSelectColumnCenter` → `l(idx)`：
```java
// Rj/y1.java:141
public static /* synthetic */ float C(y1 y1Var, int i10, int i11, Object obj) {
    ... "function: getSelectColumnCenter" ...
    if ((i11 & 1) != 0) i10 = y1Var.f19633s;
    return y1Var.B(i10);
}
// Rj/y1.java:542
public final float l(int i10) {
    float f10 = this.f19631q;
    return (((i10 + 1) * f10) - (f10 / 2)) - this.f19623i;     // 列中心
}
```
```java
// Rj/y1.java:387   由 x 反解列索引
public void U(float f10) {
    if (f10 < 0.0f || !this.f19614A) return;
    if (f10 > this.f19635u) this.f19614A = false;             // 拖出右边界 → 关闭十字光标
    else this.f19633s = (int) ((this.f19623i + f10) / this.f19631q);
}
```
→ **竖线是离散的、一根一根跳，不是自由跟手**。横线才跟手（见 4.5）。

竖线绘制在 `Rj/F0.java`（`.s` 层），`strokeWidth = 2.0f` 原始 px：
```java
// Rj/F0.java:28
this.f19106m.setStrokeWidth(2.0f);
// Rj/F0.java:58-62
if (y1VarM.o() > 0.0f) {          // o() = 手指原始 y，>0 表示手指还按着
    canvas.drawLine(fC, iZ, fC, c2702dE.p(), this.f19106m);   // 拖动中：STROKE 画笔，色 h()
} else if (y1VarM.E()) {
    canvas.drawLine(fC, iZ, fC, c2702dE.p(), this.f19105l);   // 松手后：FILL 画笔，色 t()
}
```
→ **按住时和松手后的竖线用不同颜色**。

### 4.4 松手后十字光标**保持不消失**

```java
// Wj/a.java:~527   ACTION_UP
if (this.f24751k == 2) {
    y1VarM2.Y(true);                    // 保持可见
    y1VarM2.U(motionEvent.getX());      // 吸附列索引
    y1VarM2.Z(motionEvent.getY());      // 记住最后的 y
    y1VarM2.W(-1.0f); y1VarM2.X(-1.0f); // 清掉"手指原始坐标"
}
```
- `【已穷举验证】` `【未找到】` 任何自动消失的定时器（grep `postDelayed` / `sendEmptyMessageDelayed` 在 `Wj/a.java` 只有那一个 400ms 长按）。
- 关闭方式：**单击图表切换**，`Rj/y1.java:418`：
  ```java
  public final void a0() {
      KLineManager.f142490O.a().w0(!this.f19614A);
      this.f19614A = !this.f19614A;
  }
  ```
  且这个状态被写进 `KLineManager`，**跨周期切换保留**。

### 4.5 横线（价格线）与价格标签的三种模式

`Rj/M.java:135` 读 `q(12)`，`KLineManager.r(12)` 返回 **1**（12 ∈ `{10,12,15,17}`）→ 默认值 1。

```java
// Rj/M.java:194-217
float fO = y1VarM.o();                       // 手指原始 y；松手后为 -1
...
boolean z11 = c2702dE.m(fO) && fO > 0.0f;    // 手指还按着
if (!z11) {                                   // 松手之后
    if (z12) {
        int i10 = this.f19207x;               // = q(12)
        if (i10 == 0) {                       // 模式 0：吸附到该根的收盘价
            int iD = y1VarM.D();
            if (nk.z.a(c2765zH.C(), iD)) {
                dA = ((Sj.b) c2765zH.C().get(iD)).a();
                fS = abstractC2759w0L.S(dA);
            }
        } else {
            if (i10 != 1) return;             // 模式 2：松手后不画横线
            if (c2702dE.m(y1VarM.G())) {      // 模式 1（默认）：停在松手时的 y
                float fMax = Math.max(abstractC2759w0L.x(), y1VarM.G());
                double dR3 = abstractC2759w0L.R(fMax);
                fS = fMax; dA = dR3;
            }
        }
    }
}
```
总结：**拖动中横线自由跟手指 Y；松手后默认（q(12)=1）停在松手那一刻的 Y，不吸附收盘价**。可设置为 0（吸附收盘价）或 2（松手后隐藏横线）。

---

## 5. 图表区域高度分配

### 5.1 主图 / 副图高度公式

```java
// Rj/L0.java:70
public void C(C2741q c2741q, int i10, int i11) {           // (width, height)
    ...
    // arrayList = Data/Range 类型的子区域，每个面板贡献 2 个
    int size = (arrayList.size() + 1) >> 1;                // 面板数 = 主图 + 副图数
    int i17 = (int) (((double) i16) / ((double) (size + 2)));   // 每个副图高 = H / (面板数 + 2)
    int[] iArr3 = new int[size];
    for (int i18 = size - 1; i18 > 0; i18--) { iArr3[i18] = i17; i16 -= i17; }
    iArr3[0] = i16;                                        // 主图拿剩下的
    ...
}
// Rj/L0.java:226
public final int M(int i10, int i11) { return ((i10 / (i11 + 3)) * 3) - 40; }   // 主图高
// Rj/L0.java:230
public final int N(int i10, int i11, boolean z10) {
    return (i11 >= 0 && (i11 >= 2 || z10)) ? (i11 + 3) * (i10 / 4) : i10;
}
```

设副图数 = k（面板数 = k+1）：
- 每个副图高 = `H / (k + 3)`
- 主图高 = `H - k·H/(k+3)` = **`3H / (k + 3)`**

| 副图数 k | 主图占比 | 每个副图占比 |
|---|---|---|
| 0 | 100% | — |
| 1 | 3/4 = 75% | 1/4 = 25% |
| 2 | 3/5 = 60% | 1/5 = 20% |
| 3 | 3/6 = 50% | 1/6 ≈ 16.7% |
| 4 | 3/7 ≈ 42.9% | 1/7 ≈ 14.3% |

`M()` 里额外减的 `40` = 时间轴条高度（原始 px），见下。

### 5.2 各面板的内边距（这些是 **sp**，不是 dp —— 注意！）

K 线主图（`Rj/C2757v1.java:1739-1740`）：
```java
c2750t0.J(Xj.a.d(40));     // top padding = 40sp
c2750t0.I(Xj.a.d(8));      // bottom padding = 8sp
```
分时图（`Rj/C2757v1.java:1604-1605`）：`J(Xj.a.d(50))` / `I(Xj.a.d(28))`
绝大多数副图指标面板（`C2757v1.java` 的 110/142/174/206/260/292/648/679/733/778/811/851/921/948/975/1005/1032/1172 等十余处）：
```java
c2750t0.J(Xj.a.d(16));     // top = 16sp
c2750t0.I(Xj.a.d(8));      // bottom = 8sp
```
少数特例：`C2757v1.java:330-331` 为 `12sp / 4sp`；`:707-708`、`:878-879` 为 `8sp / 8sp`。

padding 的施加点（`Rj/AbstractC2759w0.java:214`）：
```java
public final void K(int i10, int i11) {
    int i12 = i10 + this.f19591x;      // top  += topPadding
    int i13 = i11 - this.f19592y;      // bottom -= bottomPadding
    ...
}
```
→ **内边距是固定像素量，不是比例**。主图顶部留 40sp 是为了容纳指标文字行。

### 5.3 时间轴条 & 右侧价格轴宽度

```java
// Rj/L0.java:34   B(...)
if (c2702d2.o() == C2702d.a.Timeline) { int i19 = iV + 40; ... }   // 时间轴 = 40 原始 px
```
```java
// Rj/L0.java:~95   C(...) 里
int iB = Xj.a.b(8);      // 8dp 步长
int i19 = iB * 7;        // 右侧价格轴起始宽 = 56dp = 56pt
int i20 = i10 / 3;       // 上限 = 总宽的 1/3
...
int i29 = i10 - i19;     // 图表绘制宽 = 总宽 - 价格轴宽
```
→ **右侧价格轴最小 56pt，按 8pt 为步长按最长价格文本增长，最多不超过总宽的 1/3。**

---

## 6. 价格轴自动范围

### 6.1 min/max 的来源：**包含 MA / 指标线**，蜡烛高低点是「条件参与」的

```java
// Rj/AbstractC2759w0.java:323   T() 自动范围
// min/max 先取自：
//   c2741qB2.g(d() + ".m")   ← 主指标集合（MA / BOLL 等），必取
//   c2741qB2.g(d() + ".a")   ← 辅助集合（"ds0.indic2" 跳过）
// 然后再叠加可见蜡烛的 low/high 扫描（bVar.c() / bVar.b()），但在以下条件下【跳过】蜡烛扫描：
```
```java
// Rj/AbstractC2759w0.java:354   跳过条件（原始一行）
if (!AbstractC7609s.f(e().a(1), "main") || !C2760w1.f19594a.j()
    || (KLineManager.f142490O.a().q(14) == 0 && y1VarM.u() < 5.0f)
    || (c2765zH = c2741qB.h(c())) == null || c2765zH.D() <= 0) { ... }
```
- `q(14)` 默认值 = **0**（14 不在任何返回非 0 的组里，`KLineManager.java:696` `r()`）。
- `y1.u()` = 当前列宽 `f19631q`。
→ **默认设置下，当列宽 < 5 px 时不再扫描每根蜡烛的高低点**（性能优化），价格范围退化为只看指标线。`【推断】`这对 iOS 侧的意义：极度缩小时价格轴可能"看起来收窄"，是刻意的。

最后调用 `L(min, max)`。

### 6.2 **没有 ±5% 的比例留白**

`【已穷举验证】`在 `AbstractC2759w0.java` 里 `【未找到】`任何形如 `range * 0.05` / `* 1.05` 的比例外扩。留白完全靠 5.2 节的**固定像素 top/bottom padding**（主图 40sp / 8sp）实现。

`【推断】`这带来一个可观察的行为差异：**留白量不随价格波动幅度变化**，缩放时顶部始终是那 40sp 高度的像素条。

### 6.3 范围切换有 **250ms DecelerateInterpolator 动画**

`Rj/AbstractC2759w0.java:249` 的 `L(min,max)` 路由到 `Rj/C2764y0.java`：
```java
// Rj/C2764y0.java:36-48
public C2764y0(C2732n c2732n, p146gg.o oVar) {
    ...
    ValueAnimator valueAnimatorOfObject = ValueAnimator.ofObject(a10,
        new Qf.p(dValueOf, dValueOf), new Qf.p(dValueOf, dValueOf));
    valueAnimatorOfObject.setDuration(250L);
    valueAnimatorOfObject.setStartDelay(0L);
    valueAnimatorOfObject.setInterpolator(new DecelerateInterpolator());
    valueAnimatorOfObject.addUpdateListener(new C2762x0(this));
    this.f19612h = valueAnimatorOfObject;
}
```
```java
// Rj/C2764y0.java:~60   b(oldMin, oldMax, newMin, newMax, firstVisibleTs, lastVisibleTs)
public final void b(double d10, double d11, double d12, double d13, long j10, long j11) {
    if (!this.f19612h.isRunning()) {
        // key = "firstTs+lastTs"，只有当【可见区间变了】才重新起动画
        if (!AbstractC7609s.f(key, this.f19611g)) {
            this.f19609e = j10; this.f19610f = j11;
            this.f19612h.setObjectValues(new Qf.p(d10, d11), new Qf.p(d12, d13));
            this.f19612h.start();
            this.f19611g = key;
        }
    }
    if (j10 == this.f19609e && j11 == this.f19610f) {
        if (this.f19611g.length() > 0) this.f19606b.invoke(this.f19607c, this.f19608d);
    } else if (this.f19612h.isRunning()) {
        this.f19612h.end();     // 可见区间又变了 → 立刻结束，不排队
    }
}
```
**要点：动画的 key 是「可见区间的首/尾时间戳」。滚动/缩放过程中区间一直在变，动画会被 `end()` 立即收尾 → 实际观感是「平移时价格轴瞬时跟随，停下后的那一次范围变化才有 250ms 缓动」。**

### 6.4 最新价虚线

绘制类 `Rj/C2712g0.java`（`.d` 层）：
```java
// Rj/C2712g0.java:57
paint3.setStyle(Paint.Style.STROKE);
paint3.setStrokeWidth(2.0f);                                       // 2 原始 px
paint3.setPathEffect(new DashPathEffect(new float[]{Xj.a.b(3), Xj.a.b(2)}, 0.0f));
                                                                   // 虚线 3dp 实 / 2dp 空 = 3pt / 2pt
// :58-59
Paint paint4 = new Paint(); paint4.setStyle(STROKE); paint4.setStrokeWidth(2.0f);   // 实线版本
// :45
paint.setTextSize(nk.l.p(aVar.a().i(), 2, 9.0f));                  // 价格标签 9sp
// :63
this.f19410q = nk.n.f(10);
this.f19411r = aVar.a().q(12);
```
- 标签的垂直居中基线偏移：`this.f19405l = -(ceil(bottom - top) / 2) - fontMetrics.top;`（`C2712g0.java:48`）—— 标准的"文字块中心对齐到给定 y"公式。

### 6.5 价格轴标签防重叠

```java
// Rj/M.java:390   z(top, bottom, text, region, canvas, ...)
float f14 = this.f19202s;                     // 单行文字高度
float f15 = (i11 + (z10 ? 1 : 0)) * f14;
boolean z11 = (f11 + f15 <= region.bottom) || !(f10 - f15 >= region.top);
if (!z11) { f11 = 0.0f; }                     // 放不下就不画
```
`Rj/M.java:132-135`：
```java
this.f19202s = (int) Math.ceil(fontMetrics.bottom - fontMetrics.top);   // 行高
this.f19203t = (-(((float) Math.ceil(fontMetrics.bottom - fontMetrics.top)) / 2)) - fontMetrics.top;
this.f19204u = (int) nk.l.o(1, 1.0f);     // 1dp
this.f19205v = (int) nk.l.o(1, 2.0f);     // 2dp
```
→ 价格标签框左右各内缩 **2dp**，上下 **1dp**。文字 **9sp**。
`【未找到】` 单独的"最高价 / 最低价"箭头标记绘制类（K 线上标注区间极值的那种小标签）。`Rj/M.java` 是价格轴上的标签绘制器（含报警控件），不是 K 线体上的极值标注。

---

## 7. 其他还原手感有用的常量

| 项 | 值 | 证据 |
|---|---|---|
| 长按阈值 | **400 ms**（系统默认是 500ms） | `Wj/a.java:435` |
| touchSlop | `getScaledTouchSlop()`（典型 8dp = 8pt） | `Wj/a.java:259` |
| 双指 spanSlop | `touchSlop × 2` | `Wj/b.java:~60` |
| 双指最小 span | **50 px**（硬编码） | `Wj/b.java:~61` |
| 竖直手势"交还父容器"判据 | `|dy| > |dx| × 1.5` | `Wj/a.java:~505`、`Wj/c.java:5` |
| 价格窗口平移判据 | 主图内 && Y 已手动缩放 && `|dy| ≥ slop` && `|dy| > |dx|×1.5` | `Wj/c.java:5` |
| 价格范围过渡动画 | **250 ms, DecelerateInterpolator** | `Rj/C2764y0.java:43-45` |
| 画线工具命中容差 | **9.5dp = 9.5pt** | `Rj/G.java` `public static final float f19114w = Xj.a.a(9.5f);` |
| 十字线线宽 | 2 原始 px | `Rj/F0.java:28` |
| 最新价虚线 | 2px 宽，3dp 实 / 2dp 空 | `Rj/C2712g0.java:57` |
| 尾部虚拟空 K 线 | **400 根** | `Rj/C2765z.java:319, 962` |
| 双击主图区 | **不缩放**，只发宿主回调 `C2738p.f()` | `Wj/a.java:110` |
| 双击价格轴 | 恢复 Y 自动范围 | `Wj/a.java:88` |
| 手势期间是否拦截父容器 | `requestDisallowInterceptTouchEvent(mode != 5)` | `Wj/a.java:~545` |
| Y 手动缩放时网格密度 | ×1.8 | `Rj/AbstractC2759w0.java:555` |
| 新增一根时的位移补偿 | `O(viewportWidth / 10)` | `Rj/y1.java:~440` |

### 已确认「没有」的东西（避免过度实现）
- `【未找到】` 任何震动 / 触感反馈。
- `【未找到】` 缩放或平移的橡皮筋 / 回弹 / spring 动画。
- `【未找到】` 缩放档位（detent）或吸附到整数列宽。
- `【未找到】` 十字光标自动消失定时器。
- `【未找到】` 双指竖直捏合做 Y 轴缩放的专用逻辑（span 是各向同性的 hypot）。
- `【未找到】` 价格范围的比例留白（如 ±5%）。

### 来自资源报告的相关 UI 尺寸（`REPORT-resources.md`）
- `tv_scale_auto`（"A" 按钮，恢复 Y 自动）：12sp
- `tv_back_to_last`（"回到最新"）：11sp
- 右侧展开按钮 `iv_show_right`：20dp
- 右侧面板宽：105dp
- 周期条高：34dp；十字光标信息条高：34dp（默认 `gone`）；指标条高：25dp

---

## 8. 对 iOS「看盘」实现的直接建议

以下是可以直接落成常量的数值和规则。凡与 AICoin 不同之处我都说明了理由。

### 8.1 横向缩放
```swift
// 基准列宽：AICoin 用 12 原始 px。iOS 里 CGFloat 单位是 pt，
// 3x 屏上 12px = 4pt。建议直接用 pt 表达：
let baseColumnWidth: CGFloat = 4.0        // pt（= AICoin 3x 屏上的 12px）
let scaleRange: ClosedRange<CGFloat> = 0.4...10.0
var columnWidth: CGFloat { baseColumnWidth * scale }   // 1.6pt ... 40pt
```
- 缩放**连续、无档位、无回弹**，`scale = clamp(scale * gr.scale, 0.4, 10.0)`，每次 `UIPinchGestureRecognizer` 的增量都用 `gr.scale` 相对上一帧（记得每帧 `gr.scale = 1`）。
- **锚点 = 双指中心**（`gr.location(in: view)`），保持该点下的时间位置不变：
  `newOffset = (oldOffset + focusX) / oldContentWidth * newContentWidth - focusX`
- 若当前已贴最右（`anchor == .right`），缩放后**继续贴最右**，不要用 focusX 逻辑 —— 这是 AICoin 手感里很明显的一条。
- **scale 要全局持久化**，切周期、切品种都保留（AICoin 用 `C2760w1` 单例）。
- 一屏根数**不要设硬上下限**，由列宽夹紧自然推出。在 390pt 宽的机器上是 `≈ 10 ~ 244` 根。
  → 如果任务书要求一屏 2000 根，那必须把 `baseColumnWidth` 或 `scale` 下限改小（例如 `baseColumnWidth = 1.0, scale 下限 0.2` → 最小列宽 0.2pt → 一屏 1950 根），**这是有意偏离 AICoin，要在验收记录里写明**。

### 8.2 竖向（价格轴）缩放
```swift
let yScaleRange: ClosedRange<Double> = 0.03...16.0
let snapToOneTolerance = 0.02                      // |s - 1| <= 0.02 → s = 1
// 拖动手势在右侧价格轴条上：
func yScale(from startScale: Double, startY: CGFloat, currentY: CGFloat, axisHeight: CGFloat) -> Double {
    let denom = max(Double(axisHeight) / 4.0, 1.0)
    return startScale * pow(2.0, Double(-(currentY - startY)) / denom)
}
```
- **触发区域 = 右侧价格轴矩形**，判据：起点命中价格轴 && `|dy| >= touchSlop` && `|dy| >= |dx|`。
- 向上拖 = 放大。`axisHeight/4` 的含义：**拖过价格轴高度的 1/4 就翻一倍**，很灵敏，建议照抄。
- `yScale != 1.0` 时在图表角上显示一个「A」小按钮（12pt 字），点它恢复自动。
- **双击价格轴也恢复自动**（`UITapGestureRecognizer(numberOfTapsRequired: 2)` 只挂在价格轴区域）。
- 只有 `yScale != 1.0` 时，主图区内的竖直拖动才切成"上下平移价格窗口"；否则竖直拖动应该让位给外层 `UIScrollView`（对应 `requestDisallowInterceptTouchEvent(false)` → iOS 用 `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` 返回 false + `gestureRecognizerShouldBegin` 返回 false）。
- 手动缩放时价格标签数量 ×1.8。

### 8.3 平移与惯性
- 用 `UIPanGestureRecognizer` 自己算，或直接套一个 `UIScrollView` 的 decelerationRate。
  AICoin 用 Android `OverScroller` 默认摩擦 0.015 —— 对应 iOS 最接近的是 **`UIScrollView.DecelerationRate.normal` (0.998)**；如果觉得滑太远用 `.fast` (0.99)。
- fling 阈值：AICoin 用 `getScaledMinimumFlingVelocity()`（多数机型 50 px/s）。iOS 建议 **|velocity| > 50 pt/s 才起惯性**。
- **以下四种手势结束后一律不起惯性**：十字光标、画线拖柄、Y 轴缩放、价格窗口平移。
- **边界硬停，不要橡皮筋**（`scrollView.bounces = false` 等价物）。到边时发一个"已到最左/最右"的回调，用来触发加载历史。
- **右侧允许的空白 = 30pt**（默认）。实现方式照抄 AICoin 更省事：在数据尾部**追加 400 根 OHLC 为 NaN 的占位根**，"回到最新"的归位点 = 把这 400 根里除 30pt 外全部滚出屏幕。这样"最右"和"能拖到未来"是同一套代码。
- 把某时间戳居中：`offset -= (index + 0.5) * colWidth - viewportWidth / 2`。

### 8.4 十字光标
- **长按 400 ms**（`UILongPressGestureRecognizer.minimumPressDuration = 0.4`）。也支持"按住 >400ms 后开始拖"直接进十字光标态。
- **不加触感反馈**（AICoin 没有）。如果 iOS 侧想加 `UIImpactFeedbackGenerator(.light)`，那是有意增强，要单独标注。
- **竖线始终吸附到列中心**：`x = (index + 0.5) * colWidth - offset`，`index = floor((offset + touchX) / colWidth)`。一根一根跳，不要自由跟手。
- **横线自由跟手指 Y**；松手后**停在松手那一刻的 Y**（不吸附收盘价）。
- 拖出右边界（`touchX > viewportWidth`）→ **自动关闭十字光标**。
- **松手后十字光标保持显示，没有自动消失定时器**；靠**单击图表切换开/关**，且这个开关状态跨周期保留。
- 按住中 / 松手后的竖线用**不同颜色**（AICoin 分别是 `h()` 和 `t()` 两个色值）。
- 十字光标激活期间**禁止双指缩放**（`if mode == .crosshair { return }` in onScale）。

### 8.5 面板高度
```swift
// k = 副图数量
let subPanelHeight = totalHeight / CGFloat(k + 3)
let mainPanelHeight = totalHeight - CGFloat(k) * subPanelHeight   // = 3H/(k+3)
```
| k | 主图 | 每个副图 |
|---|---|---|
| 0 | 100% | — |
| 1 | 75% | 25% |
| 2 | 60% | 20% |
| 3 | 50% | 16.7% |

- 时间轴条高 **40pt**（AICoin 是 40 原始 px；在 3x 屏上 ≈ 13pt，太矮，**建议 iOS 用 20~24pt** 更合理 —— 这里我认为 AICoin 的 40px 是历史遗留，照抄反而不好看）。
- **主图上内边距 40pt、下内边距 8pt**；副图上 16pt、下 8pt。这是**固定像素量、不是比例**。
- **右侧价格轴宽：最小 56pt，以 8pt 为步长按最长价格文本增长，上限 = 容器宽 / 3。**

### 8.6 价格轴自动范围
- min/max = **可见区间内所有指标线（MA/BOLL 等）的极值 ∪ 可见蜡烛的 high/low**。
  **必须把指标线算进去** —— 这是 AICoin 的行为，也是用户预期（MA 不会被裁掉）。
- 当列宽 < 5pt 时可以跳过逐根蜡烛扫描（性能优化，AICoin 默认如此）。iOS 侧如果绘制性能够，建议**不跳过**，视觉更正确。
- **不要加 ±5% 的比例留白** —— 留白全部由 8.5 的固定 top/bottom padding 提供。
- **范围变化用 250ms、ease-out（`DecelerateInterpolator` ≈ `UIView.AnimationCurve.easeOut` / `CAMediaTimingFunction(name: .easeOut)`）过渡**，但要照抄 AICoin 的关键设计：
  **动画的身份键是「可见区间的首尾时间戳」。滚动/缩放过程中区间一直在变 → 动画立即 `end()` 收尾（瞬时跟随）；只有停下之后那一次范围变化才走完整 250ms 缓动。**
  否则滚动时价格轴会一直"糊"。
- 最新价虚线：线宽 **2pt**，虚线 **3pt 实 / 2pt 空**；价格标签 **9pt 字**，标签框左右内缩 2pt、上下 1pt，文字垂直居中用 `-(ceil(lineHeight)/2) - fontMetrics.ascent` 的基线偏移。

### 8.7 手势识别器的优先级（照抄 AICoin 的状态机）
一次 `began` 后按下列顺序**一次性定型**，中途不改：
1. 多指 → 缩放（最新根可见 → 保持右端钉位；否则 focusX 锚定）
2. 已按住 ≥400ms → 十字光标
3. 起点在价格轴 && `|dy| ≥ slop` && `|dy| ≥ |dx|` → Y 轴缩放
4. `yScale != 1` && 主图内 && `|dy| ≥ slop` && `|dy| > |dx| × 1.5` → 价格窗口上下平移
5. `|dy| > |dx| × 1.5` → **交还外层滚动，本 view 不处理**
6. 其余 → 横向平移

---

## 9. 遗留 / 未核实项（老实说明）

1. **`12.0f` 的单位**：强证据指向"原始 px、不随密度变化"（无 `Xj.a.a()` 包装，直接与 px 视口宽相除），但没有找到一处显式的单位声明。`【推断】`
2. **右端拖动的夹紧**：`Rj/y1.java:255` 的 `O()` 在 jadx 输出里看不到右端 `min()` 夹紧，只有左端夹到 0。fling 时靠 `forceFinished` 停住是确凿的；**手指拖动能否拖过头我无法确认**。该 APK 的 apktool 产物只有 `classes*.dex`、没有 smali，**无法做字节码交叉核对**。
3. **K 线体上的"最高价/最低价"箭头标注**：`【未找到】`对应的绘制类。`Rj/M.java` 是价格轴标签绘制器（含报警控件），不是它。
4. **`KLineManager.q(int)` 的语义**：只解出 `q(18)`（右侧留白模式，默认 0）、`q(12)`（十字光标横线模式，默认 1）、`q(14)`（小列宽时是否仍扫描蜡烛极值，默认 0）；`q(6)/q(9)/q(16)/q(24)/q(25)` 的具体含义未解。默认值可从 `sp/aicoin_kline/core/KLineManager.java:696` 的 `r(int)` 读出：`q(0)=21`、`q(5)=48`、`q(6)=q(7)=q(8)=q(24)=q(25)=1`、`q(10)=q(12)=q(15)=q(17)=1`、其余 `=0`。
5. **`Wj/a.java` 里 mode 3 与 mode 4 的差异细节**：确认了 4 会走 `y1.P()`，但 `P()` 的完整实现未逐行读。
