//! Health models. One row = one measurement keyed by kind + recorded_at.
//! The canonical kinds are the minimal manual set for this phase; the
//! column is TEXT so a new kind can land without a schema bump.

use rust_decimal::Decimal;

use lifeos::sync::SyncMeta;

/// Canonical metric kinds for manual capture. Wire names are `snake_case`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MetricKind {
    /// Daily step count (`count`).
    Steps,
    /// One sleep session duration (`min` for manual entry).
    Sleep,
    /// One body-weight measurement (`kg`).
    Weight,
}

impl MetricKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Steps => "steps",
            Self::Sleep => "sleep",
            Self::Weight => "weight",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "steps" => Self::Steps,
            "sleep" => Self::Sleep,
            "weight" => Self::Weight,
            _ => return None,
        })
    }

    /// The unit manual captures default to per kind.
    pub fn default_unit(self) -> &'static str {
        match self {
            Self::Steps => "count",
            Self::Sleep => "min",
            Self::Weight => "kg",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Metric {
    pub id: String,
    pub kind: MetricKind,
    /// Numeric value in `unit` — exact decimal, stored as TEXT.
    pub quantity: Decimal,
    /// Wall time the measurement is about (epoch seconds).
    pub recorded_at: i64,
    /// SI-style unit string (`count`, `min`, `kg`).
    pub unit: String,
    /// Best-effort attribution (`manual`, a device name, …).
    pub source: Option<String>,
    pub sync: SyncMeta,
}

#[derive(Debug, Clone)]
pub struct NewMetric {
    pub kind: MetricKind,
    pub quantity: Decimal,
    pub recorded_at: i64,
    /// Empty → the kind's default unit.
    pub unit: String,
    pub source: Option<String>,
}

impl NewMetric {
    pub fn now(kind: MetricKind, quantity: Decimal) -> Self {
        Self {
            kind,
            quantity,
            recorded_at: lifeos::ids::now_secs(),
            unit: kind.default_unit().to_owned(),
            source: Some("manual".to_owned()),
        }
    }
}
