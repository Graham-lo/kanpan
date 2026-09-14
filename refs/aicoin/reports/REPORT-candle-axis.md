# 蜡烛、图框、轴与手势补充逆向

来源：用户 APK AICoin Android 2.6.32 / versionCode 325。SHA256 `16e53ce563a58c967e2fd87f43c9dcd7b8ceef5c85c6a86a99d718cff215284b`。以下相对路径均从 refs/aicoin/java 起算。不是 iOS 源码；手机参数与实测冲突时手机优先。

## 单位与蜡烛

- Xj/a.java:11 的 a/b 通过 nk.l 的 DIP 转换，c/d 是 SP。Canvas 直接写 2.0f 则是物理 px。不得把 2px 写成 2pt，也不能证明 SP 不跟系统字号。
- Rj/y1.java:287：列宽 w=12×scale（px）。Wj/a.java:234：scale 夹在 0.4…10，即 w=4.8…120px。在 3x 上换算 1.6…40pt，只是安卓尺寸换算，不是本次 iOS 双指边界实测。
- Rj/C2723k.java:95：每列数学位置 left=w/6−J、center=w/2−J、right=5w/6−J，实体占 2/3。上涨实矩形右侧再收 1px，下跌路径不完全相同，描边又可能外扩；数学宽不等于最终光栅宽。
- C2723k.java:43：影线 2px。实体高度不足阈值时画水平线，不能强制放大成圆角短柱。Sj/b.java 的 d/a/b/c 分别为开/收/高/低。
- Rj/C2717i.java:35：最小“线状”在 w<5px 时走 bk/a 收盘折线；5≤w<7px 时走 C2714h 高低竖线；w≥7px 时画蜡烛。“条状”在 w<7px 画高低线，否则蜡烛。“柱状”始终蜡烛。bk/a 虽支持填充，工厂 v(false) 明确关闭此路径的面积填充。不能把“条状”误解为独立 OHLC bar 类型。

## 图框与轴

- Rj/L0.java:69：设 k 个副图，u=floor(H/(k+3))，副图各 u、主图 H−k×u；带时间轴的区域另扣 40px。因此 3:1 只是近似，不可漏掉时间轴与取整。
- L0.java:97：共享右轴按全部区域的标签宽度计算，56dp 起、8dp 步进，以 W/3 为限制目标。Rj/C2741q.java:529 通过 clipRect 隔离数据区和坐标区。
- Rj/C2757v1.java:1423：主图顶40sp/底8sp；普通副图常见16sp/8sp，但 VOL (:330) 是12sp/4sp，KDJ (:707) 是8sp/8sp。不是所有 pane 一个比例留白。
- L0.java:227 的主高度辅助为 3×floor(H/(k+3))−40；:231 的总高辅助可扩成 (k+3)×floor(baseH/4)。结合真机自适应关闭，副图可超出可见屏幕，不能硬塞一屏。
- AbstractC2759w0.java:323 扫可见段及有效叠加序列；极窄 close-line 路径不再用原始 high/low 撑范围。J/I 管留白。未证明其它路径不存在任何比例留白，旧“已穷举不存在”的断言撤销。
- Rj/C2750t0.java 是线性 nice-step 1/2/5×10^k；用户手机当前对数轴历史截图观测到 ln 步长 .01/.025/.1，不能把两个算法混为一谈或仅凭三档声称完整阶梯已知。
- Rj/C1.java:72 时间标签9sp；以“yyyy年M月”测宽+16dp，:110 使用约1.6倍标签宽进行时间间隔选择。日历步进不同于固定每78pt打一条标签。
- Rj/B0.java:43 轴字9sp；Rj/T.java:43 图例9sp，左内距8px。Rj/M.java:124 价格徽标9sp，基线按 font metrics 居中，内距非简单统一2pt。
- Rj/C2712g0.java:56 最新价虚线宽2px，dash 3dp/2dp；Rj/F0.java 十字线竖线2px并居中对齐列。极值标注的全部避让规则尚未完成源码追踪。

## 缩放与状态

- Wj/a.java:318：s=s0×2^(−dy/max(axisHeight/4,1))；AbstractC2759w0.java:427 夹 .03…16、距1≤.02吸回1。显示跨度自动跨度/s。
- AbstractC2759w0.java 的 j/D/L 保持倍率及归一化中心；更新可见数据时会重算自动区间。不能拿 Mac 的绝对价格区间锁定宣称手机就是同一实现。
- Rj/y1.java:287 支持 Start/End/None 对齐；只有 None 走手指焦点，End 维持右端。用户当前“靠右”，不能固定采用双指质心。
- Rj/C2746s.java:99 使用 OverScroller、平台最小/最大速度及 touch slop；未见摩擦覆盖，但这不等于 iOS 使用 Android 默认摩擦。:145 落指停动画；:166 十字线、手柄、Y轴缩放/平移不甩动。
- Rj/C2764y0.java:41 范围动画250ms DecelerateInterpolator；仅为安卓已读常量，未测得 iOS 同值。
- 早期一次 Y 拖动倍率 .310 同时接近距离比 .313 与指数 .301，单样本不能判定 iOS 公式。

真实点击行为及纠错见 live-capture/codex-2026-09-14/FINDINGS.md。完整双指、惯性、边界与极值标注验收仍待补，不能标“全部逆向完成”。
