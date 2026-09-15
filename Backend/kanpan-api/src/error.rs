use axum::{http::StatusCode, response::{IntoResponse, Response}, Json};
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
