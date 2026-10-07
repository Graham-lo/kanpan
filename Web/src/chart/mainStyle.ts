/* Hkline Web · 主图画法三选一（2026-10-07）：足迹 / 平均 K 线 / 等幅 K 线
 *
 * 都放在周期「更多」菜单里原来足迹那一行的位置，打勾即开、再点即关；开一个就把另外两个关掉（不叠加）。
 * 等幅 K 线只能由 1 分钟线合成：当前不是 1 分钟就先切到 1 分钟，关掉时切回开之前的周期（这期间没换过周期的话）。
 */
import type { MenuItem } from '../ui/overlay'
import { term } from '../ui/overlay'
import { footprintMenuItem, footprintOn, setFootprint } from './footprint'
import { heikinAshiOn, setHeikinAshi } from './heikinAshi'
import { rangeBarsOn, setRangeBars } from './rangeBars'

/** 开等幅前的周期（关掉时切回去） */
const before = new Map<number, string>()

function only(idx: number, keep: 'fp' | 'ha' | 'range'): void {
  if (keep !== 'fp' && footprintOn(idx)) setFootprint(idx, false)
  if (keep !== 'ha' && heikinAshiOn(idx)) setHeikinAshi(idx, false)
  if (keep !== 'range' && rangeBarsOn(idx)) setRangeBars(idx, false)
}

/** 周期菜单末尾那一组；setIv 换当前格的周期 */
export function styleMenuItems(idx: number, iv: string, setIv: (iv: string) => void): MenuItem[] {
  const fp = footprintMenuItem(idx, iv)
  const fpItem: MenuItem = typeof fp === 'object' && fp.run ? { ...fp, run: () => { const on = !footprintOn(idx); if (on) only(idx, 'fp'); fp.run!() } } : fp
  const ha = heikinAshiOn(idx), range = rangeBarsOn(idx)
  return [
    fpItem,
    { html: term('平均 K 线'), check: true, checked: ha, run: () => { if (!ha) only(idx, 'ha'); setHeikinAshi(idx, !ha) } },
    {
      html: term('等幅 K 线'), check: true, checked: range,
      run: () => {
        if (range) {
          setRangeBars(idx, false)
          const prev = before.get(idx); before.delete(idx)
          if (prev && iv === '1m') setIv(prev)
          return
        }
        only(idx, 'range')
        setRangeBars(idx, true)
        if (iv !== '1m') { before.set(idx, iv); setIv('1m') } else before.delete(idx)
      },
    },
  ]
}
