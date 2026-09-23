use axum::{extract::{FromRequest, FromRequestParts, Path, Query, Request, rejection::{JsonRejection, PathRejection, QueryRejection}}, http::{StatusCode, request::Parts}, response::{IntoResponse, Response}, Json};
use serde_json::json;

pub type Result<T> = std::result::Result<T, ApiError>;
#[derive(Debug)]
pub struct ApiError(pub StatusCode, pub &'static str);
impl ApiError {
 pub fn bad(code: &'static str) -> Self { Self(StatusCode::BAD_REQUEST,code) }
 pub fn unauthorized() -> Self { Self(StatusCode::UNAUTHORIZED,"authentication_failed") }
 pub fn missing() -> Self { Self(StatusCode::NOT_FOUND,"not_found") }
 pub fn conflict(code: &'static str) -> Self { Self(StatusCode::CONFLICT,code) }
}
impl IntoResponse for ApiError {
 fn into_response(self) -> Response { (self.0,Json(json!({"error":{"code":self.1}}))).into_response() }
}
/// 数据库错误对外一律是 503 `temporarily_unavailable`（客户端只需要知道「稍后再试」），
/// 但对内必须留下原因：原来这里把错误直接丢掉，线上一条 503 在日志里什么都查不到。
///
/// `#[track_caller]` 让 `?` 折过来时记下的是**写 `?` 的那一行**（例如
/// `src/sync.rs:212`），不是这里——这就是日志里的「上下文」。Postgres 的 SQLSTATE、
/// 约束名、表名也一起带上；锁超时（55P03）、语句超时（57014）一眼就能认出来。
impl From<sqlx::Error> for ApiError {
 #[track_caller]
 fn from(e: sqlx::Error) -> Self {
  let at=std::panic::Location::caller();
  let (code,constraint,table)=match &e {
   sqlx::Error::Database(d)=>(d.code().map(|c|c.into_owned()),d.constraint().map(str::to_owned),d.table().map(str::to_owned)),
   _=>(None,None,None),
  };
  tracing::error!(at=%format_args!("{}:{}",at.file(),at.line()),sqlstate=code.as_deref().unwrap_or("-"),constraint=constraint.as_deref().unwrap_or("-"),table=table.as_deref().unwrap_or("-"),"Database error answered as 503: {e}");
  Self(StatusCode::SERVICE_UNAVAILABLE,"temporarily_unavailable")
 }
}
impl From<serde_json::Error> for ApiError {
 fn from(_: serde_json::Error) -> Self { Self::bad("invalid_payload") }
}

/// 取参的三个包装。axum 自带的拒绝会把「第 1 行第 3 列解析失败」「unknown field
/// `foo`」这类内部细节当成纯文本正文发出去，形状也不是 `{"error":{"code":…}}`。
/// 客户端要的是一个能认的定值错误码，服务端要的是「屏幕上永远不出现内部文本」；
/// 所以正文、查询串、路径参数都从这里过，拒绝一律折成固定码。
pub struct Payload<T>(pub T);
impl<T, S> FromRequest<S> for Payload<T> where Json<T>: FromRequest<S, Rejection = JsonRejection>, S: Send + Sync {
 type Rejection = ApiError;
 async fn from_request(req: Request, state: &S) -> Result<Self> { Json::<T>::from_request(req,state).await.map(|Json(v)|Self(v)).map_err(|_|ApiError::bad("invalid_payload")) }
}
pub struct Params<T>(pub T);
impl<T, S> FromRequestParts<S> for Params<T> where Query<T>: FromRequestParts<S, Rejection = QueryRejection>, S: Send + Sync {
 type Rejection = ApiError;
 async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self> { Query::<T>::from_request_parts(parts,state).await.map(|Query(v)|Self(v)).map_err(|_|ApiError::bad("invalid_query")) }
}
pub struct Route<T>(pub T);
impl<T, S> FromRequestParts<S> for Route<T> where Path<T>: FromRequestParts<S, Rejection = PathRejection>, S: Send + Sync {
 type Rejection = ApiError;
 async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self> { Path::<T>::from_request_parts(parts,state).await.map(|Path(v)|Self(v)).map_err(|_|ApiError::bad("invalid_path")) }
}

#[cfg(test)]
mod tests {
 use super::*;
 use std::sync::{Arc,Mutex};

 #[derive(Clone,Default)] struct Sink(Arc<Mutex<Vec<u8>>>);
 impl std::io::Write for Sink {
  fn write(&mut self,buf:&[u8])->std::io::Result<usize> {self.0.lock().unwrap().extend_from_slice(buf);Ok(buf.len())}
  fn flush(&mut self)->std::io::Result<()> {Ok(())}
 }

 static QUESTION_MARK:std::sync::atomic::AtomicU32=std::sync::atomic::AtomicU32::new(0);
 fn fails()->Result<()> {
  let r:std::result::Result<(),sqlx::Error>=Err(sqlx::Error::PoolTimedOut);
  QUESTION_MARK.store(line!()+1,std::sync::atomic::Ordering::Relaxed);
  r?;
  Ok(())
 }

 /// 对外还是那个 503，对内要记下原因和写 `?` 的那一行。
 #[test] fn a_database_error_is_logged_with_where_it_happened_before_becoming_503() {
  let sink=Sink::default();
  let writer=sink.clone();
  let subscriber=tracing_subscriber::fmt().with_writer(move||writer.clone()).with_ansi(false).finish();
  let e=tracing::subscriber::with_default(subscriber,fails).unwrap_err();
  assert_eq!((e.0,e.1),(StatusCode::SERVICE_UNAVAILABLE,"temporarily_unavailable"));
  let log=String::from_utf8(sink.0.lock().unwrap().clone()).unwrap();
  let line=QUESTION_MARK.load(std::sync::atomic::Ordering::Relaxed);
  assert!(log.contains("ERROR"),"{log}");
  assert!(log.contains(&format!("src/error.rs:{line}")),"要记下 `?` 的位置: {log}");
  assert!(log.contains("pool timed out"),"要带上 sqlx 的原话: {log}");
 }
}
