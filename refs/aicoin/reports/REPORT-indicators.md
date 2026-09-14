# 指标参数与展示补充逆向

用户当前手机参数是权威，见 ../USER-CHART-PROFILE.json；本报告源码来自 Android 2.6.32，仅解释绘制与计算路径。路径相对 refs/aicoin/java。

## 用户当前有效集合

主图 MA(10,30,120,256)，从上到下 VOL(5,10,30,60,120)、OI、MACD(10,30,9)。MA槽位的 enabled 与 period 必须分开记录：7–10槽勾选但周期0，不代表画MA0。MACD三项开启，样式均透明度100/四档线宽第一档。MA16–20、OI完整样式未读；不能填成猜测值。

## 计算及渲染

- gk/C7490t0.java：DIF=EMA(short)−EMA(long)，DEA=EMA(DIF,signal)，MACD=2×(DIF−DEA)。Pj/d.java 的 EMA 使用 SMA seed、alpha=2/(n+1)，未形成的区间为 NaN。
- fk/M.java：MACD全宽路径数学柱宽2w/3，非蜡烛实体一半。正负决定涨跌色；与前柱数值比较决定空心：当前值≥前值时空心，否则实心（首项走空心分支）。不能写成“绝对动能增加就实心”。近零不足2px画横线；空心矩形右/底边减1px。
- **反编译纠错**：fk/M.java 高层 jadx 输出有错误的数组边界条件与重复索引递进。已从 classes7.dex 用 simple 模式重新核对，保存 bytecode-check/fk-M-simple.java。其 :98 后分支为索引小于长度才读取、NaN 跳过；不要直接复制高层伪代码。
- Rj/C2697b0.java:40：最小样式0/1且w<7px时切 fk/N 细线柱，否则 fk/M。N 正负柱的 x 偏移和配色读取仍有可疑反编译/实现细节，尚未宣称 iOS完全一致。
- Rj/W1.java:17：MACD所有有效序列共同求范围，以最大绝对值形成正负对称轴。
- Rj/H1.java:48：VOL left=w/6−J、right=5w/6−J−1；底从0起，极小量画横线，上涨空/实由阳线设置决定，阴柱填充。Rj/J1.java 在w<7px时可切 I1 高低细线。
- fk/D.java:250：通用线按列中心连接，NaN断开，开启抗锯齿，线宽直接读取配置；ek/m.java:31 的默认掩码将宽设为2px，不能因构造时传0就写成默认0。
- fk/E.java：RSI/Stoch参考带、参考线10px/8px dash；Rj/C2757v1.java:762 的 RSI 范围用自动轴，不能一概锁死0…100。KDJ允许J超出0…100。
- fk/L.java:63：MACD图例按文本测宽顺序摆放，放不下的项不继续挤进价格轴。并非所有标签换成无约束一行。
- 用户手机 OI 为青色线，未看到当前画面有面积填充。底座不得拿原型渐变面积作为已验证 AICoin 设计。

## 安卓默认值（只作参考，不能盖用户设置）

| 指标 | 配置源 | APK 默认 |
|---|---|---|
| MA | config/L.java:12 | 7/30 启用，其他0 |
| EMA | config/C10517y.java | 7/30 |
| VOL | config/f0.java:11 | 5/10 |
| MACD | config/M.java:125 | 12/26/9 |
| BOLL | config/r.java:137 | 20/2 |
| RSI | config/V.java:50 | 6/12/24，参考50/70/30 |
| KDJ | config/H.java:129 | 9/3/3 |
| StochRSI | config/Z.java:139 | 14/14/3/3，80/20 |
| ATR | config/C10504k.java:86 | 14 |
| OI | config/S.java:67 | 单线 |

config 路径为 sp/aicoin_kline/core/indicator/config。ek/o.java 的 registry 后写入值覆盖前写入值，BOLL须按最终 r 而非早先 C10510q 解读。资源主题色、用户线色、MACD符号色是不同来源，不可混用。

其它可选指标的全部交互、参数编辑与画线工具尚未完成真机覆盖；本报告补齐原先缺失的主要指标报告，不声称覆盖 AICoin 的全部指标产品。
