use lifeos::sync::SyncMeta;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EntryFlag {
    Confirmed,
    Pending,
    /// Synthetic reconciliation row; skips the balance check by design.
    Padding,
}

impl EntryFlag {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Confirmed => "confirmed",
            Self::Pending => "pending",
            Self::Padding => "padding",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "confirmed" => Self::Confirmed,
            "pending" => Self::Pending,
            "padding" => Self::Padding,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct JournalEntry {
    pub id: String,
    /// Trade date, epoch seconds.
    pub date: i64,
    /// T+2 settlement date, epoch seconds.
    pub settled_on: Option<i64>,
    /// Required and non-empty; empty narrations are reserved for synthetic
    /// padding rows.
    pub narration: String,
    pub payee: Option<String>,
    pub flag: EntryFlag,
    /// Denormalized tag id list (`["id", ...]` JSON).
    pub tag_ids: Vec<String>,
    pub sync: SyncMeta,
}
