// `sqlx::migrate!()` 在编译期把 migrations/ 整个嵌进二进制，但 cargo 默认不盯这个目录：
// 只新加一条迁移、没碰 .rs 的话，`cargo build` 会直接复用上一次的产物，部署上去的二进制
// 里根本没有那条迁移，`kanpan-api migrate` 也就悄悄什么都不做（2026-10-03 加 0041 时实测踩到）。
// sqlx 文档给的解法就是这一句。
fn main() {
    println!("cargo:rerun-if-changed=migrations");
}
