//! Cloud-initiated, user-consented drill-down into ledger detail.
//!
//! See module-level docs in `mod.rs`. Mirrors
//! `apps/mobile/lib/core/ai/contracts/scoped_disclosure.dart`.

use serde::{Deserialize, Serialize};

use super::context_pack::{AnonymizationLevel, DateRange};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DisclosurePurpose {
    DrillDownExpense,
    DrillDownInvestment,
    RefundMatching,
    AnomalyExplain,
    RecurringDetect,
    Other,
}

/// Whitelist of fields the cloud may request. Anything not in this
/// enum is unconditionally rejected by the device PrivacyGate. Adding
/// a field requires a deliberate code change (and ideally a
/// [`super::ContextPackVersion`] minor bump).
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum LedgerField {
    Amount,
    Currency,
    Date,
    Category,
    /// Coarse account kind ('cash', 'deposit', ...) — never the name.
    AccountKind,
    /// Hashed merchant token only. Raw merchant name is never disclosable.
    MerchantHashed,
    Note,
    TagIds,
    RecurringPatternId,
    RefundLinkId,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DisclosureRequest {
    pub request_id: String,
    pub purpose: DisclosurePurpose,
    pub fields: Vec<LedgerField>,
    pub range: DateRange,
    pub max_rows: u32,
    pub anonymization: AnonymizationLevel,
    pub human_reason_zh: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum UserConsent {
    OneTime,
    Session,
    Denied,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DisclosureResponse {
    pub request_id: String,
    pub consent: UserConsent,
    /// Rows already anonymised by the device. The planner treats these
    /// as opaque, non-cacheable JSON objects.
    #[serde(default)]
    pub rows: Vec<serde_json::Map<String, serde_json::Value>>,
    /// Original row count before truncation, when the device hit
    /// [`DisclosureRequest::max_rows`].
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub truncated_from: Option<u32>,
}
