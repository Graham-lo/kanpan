/* 电脑网页 × 契约：每个跟人走字段，电脑要么认领、要么写明为什么不用（2026-10-10「同步字段解耦」）
 *
 * 契约 Backend/kanpan-api/contract/settings-fields.json 由 iOS PrefsFieldPlan 生成。手机网页早有三方对账
 * （tests/m-prefs.test.ts），电脑网页的 SETTINGS_FIELDS 却是手写的、没人对：手机加了一个字段，电脑这边
 * 没人想过要不要接。这里补上——每个 synced 字段必须二选一：
 *   - 在 sync/codec.ts 的 SETTINGS_FIELDS 里（bridge 的 OWNED.settings 就是它；params 认领 params/<ID>）；
 *   - 或在同文件的 PC_UNUSED_SYNCED_FIELDS 里，带一句真话理由（TODO 不算）。
 */
import { describe, expect, it } from 'vitest'
import contract from '../../Backend/kanpan-api/contract/settings-fields.json'
import { PC_UNUSED_SYNCED_FIELDS, SETTINGS_FIELDS, WEB_ONLY_SETTINGS } from '../src/sync/codec'

const synced = Object.entries(contract.fieldClasses as Record<string, string>).filter(([, c]) => c === 'synced').map(([k]) => k).sort()
/** 电脑认领的根：`params/MA` 认领的是 `params` */
const claimed = new Set(SETTINGS_FIELDS.map(f => f.split('/')[0]))

describe('电脑网页 × 契约 synced 字段', () => {
  it('每个 synced 字段要么电脑认领、要么列进「电脑网页不用」', () => {
    const missing = synced.filter(k => !claimed.has(k) && !(k in PC_UNUSED_SYNCED_FIELDS))
    expect(missing, `契约里这些 synced 字段电脑网页没表态：${missing.join(', ')}。
电脑要接：加进 Web/src/sync/codec.ts 的 SETTINGS_FIELDS，并在 webSetting / encodeSetting / decodeSetting 里写换算；
电脑不用：在同文件 PC_UNUSED_SYNCED_FIELDS 里加一行 \`字段: '为什么电脑不用'\`。`).toEqual([])
  })

  it('「不用」的理由都是真话，没有 TODO 占位', () => {
    const todo = Object.entries(PC_UNUSED_SYNCED_FIELDS).filter(([, why]) => !why.trim() || /TODO/i.test(why)).map(([k]) => k)
    expect(todo, `PC_UNUSED_SYNCED_FIELDS 里这些字段的理由还是 TODO（make new-sync-field 放的占位）：${todo.join(', ')}。
想清楚电脑要不要接：接就挪进 SETTINGS_FIELDS 并写换算，不接就把 TODO 换成一句为什么。`).toEqual([])
  })

  it('认领和「不用」不重叠', () => {
    const both = Object.keys(PC_UNUSED_SYNCED_FIELDS).filter(k => claimed.has(k))
    expect(both, `这些字段电脑既认领了又列在「不用」里：${both.join(', ')}。从 PC_UNUSED_SYNCED_FIELDS 删掉。`).toEqual([])
  })

  it('「不用」里没有契约之外的名字（字段退役了这里要跟着删）', () => {
    const stale = Object.keys(PC_UNUSED_SYNCED_FIELDS).filter(k => !synced.includes(k))
    expect(stale, `PC_UNUSED_SYNCED_FIELDS 里这些名字已不是契约里的 synced 字段：${stale.join(', ')}。删掉那几行。`).toEqual([])
  })

  it('电脑认领的、不是网页独有的，都是契约里的 synced 字段', () => {
    const webOnly = new Set<string>(WEB_ONLY_SETTINGS)
    const extra = [...claimed].filter(k => !webOnly.has(k) && !synced.includes(k))
    expect(extra, `电脑 SETTINGS_FIELDS 里这些名字契约里没有（退役了或拼错了，服务端会整条拒收）：${extra.join(', ')}`).toEqual([])
  })
})
