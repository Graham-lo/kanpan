/* 手机网页版 · 琉璃底（照 iOS DesignSystem/LiuliMaterial.swift 的 LiuliBackdrop）
 *
 * 一层绝对定位的底：底色 + 三团光斑（只有青苔 / 陶土浅色画，--lg-lobes 管）+ 一层颗粒（::after）。
 * 样式在 styles/ui.css「琉璃材质」，令牌在 tokens.css。光斑是径向渐变 + transform 漂移，不开 filter，
 * 一页只铺一层，滚动时不跟着重绘。
 */

/** 整页底：插在页 / 层的第一个子节点，内容压在它上面 */
export function liuliBackdropHTML(lobes = true): string {
  return `<div class="lg-bg" aria-hidden="true">${lobes ? '<i class="lg-blob b1"></i><i class="lg-blob b2"></i><i class="lg-blob b3"></i><i class="lg-wash"></i>' : ''}</div>`
}
