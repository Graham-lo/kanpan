//! Native chart records use explicit ranges and frozen first-event rules.
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

#[derive(Clone, Debug, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChartRange {
    pub venue: String, pub market: String, pub symbol: String, pub interval: String,
    pub start: i64, pub end: i64, pub bars: usize,
}
#[derive(Clone, Debug, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NativeRule {
    pub version: String, pub direction: String, pub confirmation: String,
    pub reference: f64, pub target: f64, pub invalidation: f64, pub expires: i64,
    #[serde(default)] pub target_edited: bool,
    #[serde(default)] pub invalidation_edited: bool,
    #[serde(default)] pub expiry_edited: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NativeDraft {
    pub id: Uuid, pub range: ChartRange, pub rule: NativeRule, pub text: String,
    pub confidence: Option<u8>, pub origin: String, pub created: i64,
    pub chart_settings: Option<String>, pub drawing_snapshot: Option<String>,
    pub original_claimed: Option<i64>,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NativeReflection {
    pub note: String, pub next_time: String, pub published_at: Option<i64>, pub revision: i64,
}
#[derive(Clone, Debug, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NativeReflectionInput {
    pub expected_revision: i64, pub reflection: NativeReflection, pub publish: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NativeChange { pub expected_revision: i64 }
#[derive(Clone, Debug, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NativeAssessment {
    pub outcome: String, pub reason: String, pub event_at: Option<i64>, pub assessed_at: i64,
}
#[derive(Clone, Debug, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NativeRecord {
    pub draft: NativeDraft, pub server_id: Uuid, pub submitted: i64, pub revision: i64,
    pub assessment: Option<NativeAssessment>, pub reflection: NativeReflection,
    pub reflection_history: Vec<NativeReflection>, pub sync_error: Option<String>,
    pub eligible: bool, pub voided: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct NativeSearch { pub range: ChartRange, pub cutoff: i64, pub scope: String }
#[derive(Clone, Debug, Default, Serialize, Deserialize, ToSchema)]
#[serde(deny_unknown_fields)]
pub struct NativeFilter { pub after: Option<Uuid> }
