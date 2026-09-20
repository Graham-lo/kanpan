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
impl From<sqlx::Error> for ApiError {
 fn from(_: sqlx::Error) -> Self { Self(StatusCode::SERVICE_UNAVAILABLE,"temporarily_unavailable") }
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
