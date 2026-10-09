/** 盘口洞察文案集中于此；与 iOS OrderFlowInsightLabels 对齐。 */
export const INSIGHT = {
  title: '盘口洞察', entry: '上滑查看盘口洞察', observation: '当前观察', walls: '附近关键挂单',
  zones: '今日大单聚集区', activity: '主动成交与价格反应', liquidation: '爆仓与后续反应', events: '最近重要变化',
  evidence: '查看依据', barEvidence: '逐根成交证据', chart: '回到图表定位',
  loading: '正在获取有效信息', unavailable: '暂时无法更新，稍后重试', untracked: '这只品种暂未持续记录',
  noZones: '覆盖时段内暂无达到门槛的真实大额成交价区', noCoverage: '尚无今日真实成交覆盖',
  noWall: '当前交易所暂无可确认的关键挂单', noPrices: '同所分钟行情不足，暂不判断价格反应',
  noFlow: '这段时间的同所成交覆盖不足', noLiq: '暂无可用爆仓数据', noEvents: '近 15 分钟暂无重要生命周期变化',
  incomplete: '数据仍在补齐，暂不判断成交方向', stale: '数据暂未更新，以下保留最近一次观察',
  neutral: '近 15 分钟主动买卖相对均衡', inspect: '先观察附近挂单与真实成交价区',
  partial: '今日 · 从', today: '今日 · 北京时间', mainVenue: '当前交易所', allVenues: '多所聚合',
  coverage: '只包含已记录时段，成交密集不直接等于支撑或压力。',
  flowEvidence: '同一交易所、同一产品；主动买占比 ≥60% 或 ≤40% 才描述方向。连续 1 分钟行情首开盘至末收盘，0.05% 为推进观察门槛。仅描述已发生的成交与价格反应。',
  liqEvidence: '独立展示已收到的强平数据，不与大单相加。币安推送存在抽样，金额是已观测下限；Bybit 破产价不作精确成交价区。后续反应使用最大爆仓分钟结束后的完整分钟行情，至少 2 根。',
} as const
