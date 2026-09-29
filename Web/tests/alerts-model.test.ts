import { describe, expect, it } from 'vitest'
import { st, subscribe } from '../src/app/store'
import { fire, makePriceAlert, notifyAlerts, onAlertFired, onAlertsChange, webhookByPage, type Alert } from '../src/alerts/model'
import { makeConditionAlert } from '../src/alerts/shape'

describe('提醒模块', () => {
  it('fire：先以「已触发」留在表里落一次盘，报完再删掉落第二次（记账看得到 active → fired）', () => {
    const a = makePriceAlert('BTCUSDT', 101000, 100000, { now: 1 })
    st.alerts = [a]
    const seen: string[] = []
    const off1 = subscribe(s => seen.push(s.alerts.map(x => x.status).join(',') || '空'))
    const off2 = onAlertFired(f => seen.push('报:' + f.alert.status + ':' + (st.alerts.includes(f.alert) ? '在表里' : '不在')))
    fire(a, 101001, 101000)
    fire(a, 101002, 101000) // 响一次就结束
    off1(); off2()
    expect(seen).toEqual(['fired', '报:fired:在表里', '空'])
    expect(a.firedPrice).toBe(101001)
    expect(st.alerts).toEqual([])
  })

  it('notifyAlerts：云端改了提醒表时，自己订阅的弹层（onAlertsChange）也会收到', () => {
    let n = 0
    const off = onAlertsChange(() => n++)
    notifyAlerts()
    off()
    notifyAlerts()
    expect(n).toBe(1)
  })

  it('Webhook 谁发：条件提醒本机判到的本机发；价格 / 画线登录着由服务端发；服务端判响的一律不发', () => {
    const p: Alert = makePriceAlert('BTCUSDT', 1, 2, { webhook: 'https://x.test/h' })
    const c: Alert = makeConditionAlert('BTCUSDT', { type: 'openInterestChange', threshold: '0.05' }, { webhook: 'https://x.test/h' })
    expect(webhookByPage(p, false, false)).toBe(true)
    expect(webhookByPage(p, false, true)).toBe(false)
    expect(webhookByPage(c, false, true)).toBe(true)
    expect(webhookByPage(c, true, false)).toBe(false)
    expect(webhookByPage({ ...p, webhook: null }, false, false)).toBe(false)
  })
})
