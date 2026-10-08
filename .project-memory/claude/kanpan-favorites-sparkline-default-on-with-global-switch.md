# kanpan-favorites-sparkline-default-on-with-global-switch

**工作习惯 / 用户纠正**：看盘自选行尾的迷你走势 2026-10-08 起默认打开，但要保留一个全局开关（用户点名，不算违反「少设置」）

看盘自选页品种行尾的 24h 迷你走势线：2026-10-08 用户定「默认打开，但要设置一个全局开关」。
（2026-09-28 收设置项 G 时曾把 `favoritesSparkline` 开关与走势线一起收掉、出厂不画；本次按用户要求重新做成默认开 + 全局开关，开关跟人走、随账号同步。）

**Why:** 用户要行有活的信息密度，但也要能一键全关——这是他点名要的设置，不在 `kanpan-minimal-settings-surface` 的「别加设置」范围内。

**How to apply:** 走势线默认开；开关放「我的 / 设置」里一个全局项，不按分类、不按品种。整批视觉整改做完后还要做一次全面压测（见 `kanpan-full-regression-after-feature-batch`）。
