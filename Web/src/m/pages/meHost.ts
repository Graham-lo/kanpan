/* 手机网页版 · 「我的」推进去的几层共用的宿主接口
 *
 * 「我的」整页是一摞层（model/navStack）：根一层，推进去的每一层从右滑入、左上 44 圆片返回、
 * 系统返回手势退一层。复盘本、朋友与收件箱这些页各写在自己的文件里，只经这个接口推层、退层、换页。
 */

/** 一层：整层元素、正文容器（.me-body）、这一层退出时要解绑的东西 */
export interface MeLayer {
  el: HTMLElement
  body: HTMLElement
  off: (() => void)[]
  /** 导航栏右侧那一格（.me-nav-side）：要放按钮（「+」「…」）的页自己往里填 */
  trailing: HTMLElement
}

export interface MeHost {
  /** 推一层；build 里填正文 */
  push(title: string, build: (body: HTMLElement, layer: MeLayer) => void): MeLayer
  /** 退一层 */
  back(): void
  /** 退回「我的」根 */
  popToRoot(): void
  /** 这一层是不是还在栈顶（异步请求回来时判断要不要动导航） */
  isTop(layer: MeLayer): boolean
  /** 退回根并切到行情页看这只品种（可带周期） */
  openSymbol(symbol: string, interval?: string): void
  /** 推登录页 */
  openLogin(): void
}
