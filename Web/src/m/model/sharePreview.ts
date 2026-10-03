/* 手机网页版 · 行情页看朋友的线：纯逻辑（照 iOS MainScreen.shareAndAlertCard / ShareCard / AlertPromptModel.offerBatch /
 * ShareItem.preferred / SharePreviewInterval）
 *
 * 头部价格行那一格同一时刻只摆一样，先后照 iOS：
 *   「顺便建提醒」那一句 > 正在看的那封信 > 最新一封没看过的信（回信进行中时不摆） > 「回给他」那一条。
 * 预览时的周期是临时的：不写偏好；人自己在周期条上换过就算他的选择，退出时不改回去。
 */

export type HeaderCard = 'prompt' | 'preview' | 'unseen' | 'reply' | null

export function headerCard(s: { prompt: boolean; previewing: boolean; replying: boolean; unseen: number }): HeaderCard {
  if (s.prompt) return 'prompt'
  if (s.previewing) return 'preview'
  if (!s.replying && s.unseen > 0) return 'unseen'
  if (s.replying) return 'reply'
  return null
}

/** 卡上第一行：正在看 / 回了你 / 谁 */
export function cardTitle(from: string, previewing: boolean, isReply: boolean): string {
  return previewing ? `正在看 ${from} 的线` : isReply ? `${from} 回了你` : from
}
/** 卡上第二行（只在没看时有）：「BTC · 3 条线  +2」 */
export function cardSubtitle(short: string, lines: number, extra: number): string {
  return `${short} · ${lines} 条线` + (extra > 0 ? `  +${extra}` : '')
}

/**
 * 留下之后对应的新线里，哪几条是发信人设了提醒的（ShareItem.preferred）：
 * 原线与新线按下标一一对应；原线解不开（null）那一位不算。
 */
export function preferredCopies(originals: readonly ({ id: string } | null)[], copies: readonly ({ id: string } | null)[], alerted: readonly string[]): Set<string> {
  const want = new Set(alerted)
  const out = new Set<string>()
  originals.forEach((o, i) => {
    const c = copies[i]
    if (o && c && want.has(o.id)) out.add(c.id)
  })
  return out
}

export interface BatchOffer<T> { sentence: string; batch: T[] }
/**
 * 收下一组线时问的那一句（AlertPromptModel.offerBatch）：只问能挂提醒的线；
 * 发信人设了提醒的那几条优先（「也给你设上？」），一条都没有就问整组。
 */
export function offerBatch<T extends { id: string }>(lines: readonly T[], supported: (d: T) => boolean, preferred: ReadonlySet<string>, from: string): BatchOffer<T> | null {
  const ok = lines.filter(supported)
  if (!ok.length) return null
  const picked = ok.filter(d => preferred.has(d.id))
  return picked.length
    ? { sentence: `${from} 在其中 ${picked.length} 条上设了提醒，也给你设上？`, batch: picked }
    : { sentence: `要在这 ${ok.length} 条线上提醒你吗？`, batch: ok }
}

/** 提醒总数上限（AlertArchive.limit） */
export const ALERT_LIMIT = 200
/** 这一组里还能加几条：已经挂着的不重复，满了就停 */
export function batchRoom(total: number, wanted: number): number {
  return Math.max(0, Math.min(wanted, ALERT_LIMIT - total))
}

/** 头部卡横划算「划掉」（ShareCard：横向 > 44 且明显比竖向大） */
export const isDismissSwipe = (dx: number, dy: number): boolean => Math.abs(dx) > 44 && Math.abs(dx) > Math.abs(dy) * 1.5
