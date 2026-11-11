//! Knowledge models. Field set is deliberately minimal (title/content/
//! source for notes; title/context/choice/outcome/status for decisions)
//! — a fresh schema, not a port of the Flutter one.

use lifeos::sync::SyncMeta;

/// A captured note. `source` is free text (a URL, a book, a conversation).
#[derive(Debug, Clone, PartialEq)]
pub struct Note {
    pub id: String,
    pub title: String,
    pub content: String,
    pub source: Option<String>,
    /// Epoch seconds the note was captured (sort key for the list).
    pub created_at: i64,
    pub sync: SyncMeta,
}

#[derive(Debug, Clone)]
pub struct NewNote {
    pub title: String,
    pub content: String,
    pub source: Option<String>,
    /// Epoch seconds; callers pass `now` so tests stay deterministic.
    pub created_at: i64,
}

impl NewNote {
    pub fn now(title: impl Into<String>, content: impl Into<String>) -> Self {
        Self {
            title: title.into(),
            content: content.into(),
            source: None,
            created_at: lifeos::ids::now_secs(),
        }
    }
}

/// Review status of a decision (same wire names as the Flutter
/// `DecisionStatus`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecisionStatus {
    Draft,
    Active,
    Paused,
    Expired,
    Verified,
    Falsified,
    Superseded,
}

impl DecisionStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Draft => "draft",
            Self::Active => "active",
            Self::Paused => "paused",
            Self::Expired => "expired",
            Self::Verified => "verified",
            Self::Falsified => "falsified",
            Self::Superseded => "superseded",
        }
    }

    /// Unknown stored values fall back to `active` (mirrors the Flutter
    /// parser, so a new wire name from a newer device does not lose rows).
    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "draft" => Self::Draft,
            "active" => Self::Active,
            "paused" => Self::Paused,
            "expired" => Self::Expired,
            "verified" => Self::Verified,
            "falsified" => Self::Falsified,
            "superseded" => Self::Superseded,
            _ => return None,
        })
    }
}

/// A decision record: the question (`title`), its context, the chosen
/// option (`choice`) and, once reviewed, the `outcome`.
#[derive(Debug, Clone, PartialEq)]
pub struct Decision {
    pub id: String,
    pub title: String,
    pub context: String,
    pub choice: String,
    pub outcome: Option<String>,
    pub status: DecisionStatus,
    /// Epoch seconds the decision was made.
    pub created_at: i64,
    pub sync: SyncMeta,
}

#[derive(Debug, Clone)]
pub struct NewDecision {
    pub title: String,
    pub context: String,
    pub choice: String,
    pub outcome: Option<String>,
    pub status: DecisionStatus,
    pub created_at: i64,
}

impl NewDecision {
    /// A fresh decision starts as a draft with no outcome.
    pub fn now(
        title: impl Into<String>,
        context: impl Into<String>,
        choice: impl Into<String>,
    ) -> Self {
        Self {
            title: title.into(),
            context: context.into(),
            choice: choice.into(),
            outcome: None,
            status: DecisionStatus::Draft,
            created_at: lifeos::ids::now_secs(),
        }
    }
}
