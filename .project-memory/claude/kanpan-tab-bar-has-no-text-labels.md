# kanpan-tab-bar-has-no-text-labels

**项目约定**：看盘底栏五格只放图标，不放「画线/图表/自选/板块分类/设置」这类文字标签——图标本身就看得懂

2026-09-18 我给看盘底栏做新方案时，每个格子都按常规做成「图标 + 下面一行小字」。
用户看完说：「其实没必要把名字标出来，这图表 icon 一看就懂」。

所以看盘的底栏是**纯图标标签栏**：五格（画线 · 图表 · 自选 · 板块分类 · 设置，见 `kanpan-bottom-tab-bar`）只画图标，不带文字。省下文字的高度之后图标可以画得更大，
整条栏也更轻——带一行小灰字的图标栏正是「后台管理系统」的长相，去掉文字本身就是在往
`kanpan-visual-direction-beauty-first` 要的方向走。

前提是图标必须自解释（这也是不能用线框示意图的又一个理由，见 `kanpan-icons-are-not-wireframes`）。
无障碍标签不受影响：SwiftUI 侧仍要给每格留 `accessibilityLabel` 和既有的
`accessibilityIdentifier("bottom.*")`，UI 测试靠它们定位。
