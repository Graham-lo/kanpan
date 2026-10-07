// 用一次性账号验证线上 kanpan-api 是否接受 settings/chart 的 webChart 字段。
const BASE = 'https://kanpan.43-160-232-253.sslip.io'
const ts = Date.now()
const username = `kpchk_${ts.toString(36)}`
const password = `Chk${ts}a1`
const device = { id: crypto.randomUUID(), name: 'kp-check', secret: crypto.randomUUID().replace(/-/g, ''), kind: 'desktop' }
const j = async (path, init = {}, token) => {
  const r = await fetch(BASE + path, { ...init, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}), ...(init.headers ?? {}) } })
  const text = await r.text()
  let body; try { body = JSON.parse(text) } catch { body = text }
  return { status: r.status, body }
}
const reg = await j('/v1/auth/register', { method: 'POST', body: JSON.stringify({ username, password, device }) })
console.log('register', reg.status, typeof reg.body === 'object' ? Object.keys(reg.body) : reg.body)
if (reg.status !== 200 && reg.status !== 201) process.exit(2)
const token = reg.body.accessToken ?? reg.body.data?.accessToken; console.log("token?", !!token)
const op = { id: crypto.randomUUID(), collection: 'settings', objectId: 'chart', deviceId: device.id, baseRevision: 0, generation: 0, timestamp: ts, logical: 1, action: 'patch', fields: { webChart: { marginTop: 20, marginRight: 8 } }, importBatch: null }
const push = await j('/v1/sync/operations', { method: 'POST', body: JSON.stringify({ operations: [op] }) }, token)
console.log('push', push.status, JSON.stringify(push.body).slice(0, 300))
const boot = await j('/v1/sync/bootstrap', {}, token)
const s = JSON.stringify(boot.body)
console.log('bootstrap', boot.status, 'hasWebChart=', s.includes('webChart'), s.slice(0, 300))
const del = await j('/v1/auth/account', { method: 'DELETE', body: JSON.stringify({ password }) }, token)
console.log('delete', del.status, JSON.stringify(del.body).slice(0, 200))
process.exit(push.status === 200 && s.includes('"marginTop":20') ? 0 : 1)
