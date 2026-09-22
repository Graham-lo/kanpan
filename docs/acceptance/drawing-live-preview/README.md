# 画线：按下拖动的一路上就看得见线

- **改了什么**：握着两点及以上的工具按下时，按下点当场吸附成「临时起点」（`DrawingSession.origin`），位移过 8pt（`drawDragSlopPt`）后覆盖层每帧从它画到手指——回撤实时铺出全部档位、矩形实时出框；抬手落地用的是同一份点，松手前后线不跳。位移不够仍旧退回「轻点落第一点」的老路。
- **证据**：`fib-mid-drag.png`（斐波那契回撤，手指还没抬）、`trend-mid-drag.png`（趋势线，同一帧），都是把覆盖层那一帧真的渲染成位图存下来的。
- **测试**：`KanpanChart/Tests/KanpanChartTests/ChartDrawingTests.swift` 里「按下拖动的一路上就有线…」「位移不够就还是轻点…」「三点工具拖第一笔…」「拖到一半取消…」「拖到一半第二根手指落下…」「取证：拖到一半那一帧图上确实画着线」六条。
- **跑法**：`cd KanpanChart && xcodebuild test -scheme KanpanChart -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath .xcbuild -only-testing:KanpanChartTests/ChartDrawingTests`（这两张 png 由最后一条用例重新生成）。
