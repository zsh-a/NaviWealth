use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::error::AppError;
use crate::hlc::Hlc;
use crate::sync::materialise::sql_table_name;

/// `fields_diff` ceiling per op (docs/sync-protocol.md §4.4).
pub const FIELDS_DIFF_MAX_BYTES: usize = 64 * 1024;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum OpType {
    Insert,
    Update,
    Delete,
}

impl OpType {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Insert => "insert",
            Self::Update => "update",
            Self::Delete => "delete",
        }
    }
}

/// Wire shape of an OpLog entry (docs/sync-protocol.md §4).
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Op {
    pub op_id: String,
    pub table: String,
    pub row_id: String,
    pub op_type: OpType,
    /// `null` for delete; required object for insert/update.
    #[serde(default)]
    pub fields_diff: Option<Value>,
    pub hlc: Hlc,
    pub device_id: String,
}

impl Op {
    /// Validate a client-generated op against the protocol spec.
    /// Per-op errors are surfaced as `AppError::Coded` and never bring down
    /// the whole batch — callers fold them into the `rejected` array.
    pub fn validate(&self) -> Result<(), AppError> {
        sql_table_name(&self.table)?;

        match self.op_type {
            OpType::Delete => {
                if self.fields_diff.is_some() && !matches!(self.fields_diff, Some(Value::Null)) {
                    return Err(AppError::coded(
                        400,
                        "bad_request",
                        "delete op must have null fields_diff",
                    ));
                }
            }
            OpType::Insert | OpType::Update => {
                let diff = self.fields_diff.as_ref().ok_or_else(|| {
                    AppError::coded(400, "bad_request", "insert/update requires fields_diff")
                })?;
                let obj = diff.as_object().ok_or_else(|| {
                    AppError::coded(400, "bad_request", "fields_diff must be a JSON object")
                })?;
                if obj.is_empty() && matches!(self.op_type, OpType::Update) {
                    return Err(AppError::empty_update());
                }
            }
        }

        if let Some(diff) = &self.fields_diff {
            let serialised = serde_json::to_string(diff).unwrap_or_default();
            if serialised.len() > FIELDS_DIFF_MAX_BYTES {
                return Err(AppError::coded(
                    413,
                    "payload_too_large",
                    "fields_diff exceeds 64 KB",
                ));
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    fn dev() -> Uuid {
        Uuid::parse_str("1f5b0c3a-4e2d-4d31-9b77-3f7c1f0d2c01").unwrap()
    }

    fn op_with(op_type: OpType, diff: Option<Value>) -> Op {
        Op {
            op_id: "00000000-0000-0000-0000-000000000001".to_string(),
            table: "accounts".to_string(),
            row_id: "row1".to_string(),
            op_type,
            fields_diff: diff,
            hlc: Hlc::new(1, 0, dev()),
            device_id: dev().to_string(),
        }
    }

    #[test]
    fn sp_b_4_empty_update_rejected() {
        let op = op_with(OpType::Update, Some(serde_json::json!({})));
        let err = op.validate().unwrap_err();
        assert_eq!(err.code(), "empty_update");
    }

    #[test]
    fn sp_b_3_delete_with_null_diff_ok() {
        let op = op_with(OpType::Delete, None);
        op.validate().unwrap();
    }

    #[test]
    fn sp_k_3_unknown_table_rejected() {
        let mut op = op_with(OpType::Insert, Some(serde_json::json!({"a": 1})));
        op.table = "secret_diary".to_string();
        let err = op.validate().unwrap_err();
        assert_eq!(err.code(), "unknown_table");
    }

    #[test]
    fn sp_b_7_oversize_diff_rejected() {
        let big = "x".repeat(FIELDS_DIFF_MAX_BYTES + 100);
        let op = op_with(OpType::Update, Some(serde_json::json!({"note": big})));
        let err = op.validate().unwrap_err();
        assert_eq!(err.code(), "payload_too_large");
    }
}
