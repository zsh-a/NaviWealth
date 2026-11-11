//! Execution models. Plan is the only grouping primitive, Action the only
//! next-step primitive; wire names follow the Flutter enums where they
//! exist (`status`, `period` = the old horizon) plus a new `kind`.

use lifeos::sync::SyncMeta;

/// What kind of outcome the plan tracks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlanKind {
    /// A concrete outcome with an end state.
    Project,
    /// An ongoing area of focus without a finish line.
    Focus,
}

impl PlanKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Project => "project",
            Self::Focus => "focus",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "project" => Self::Project,
            "focus" => Self::Focus,
            _ => return None,
        })
    }
}

/// Planning period (the Flutter `ExecutionHorizon` wire names).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlanPeriod {
    Week,
    Month,
    Quarter,
    Open,
}

impl PlanPeriod {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Week => "week",
            Self::Month => "month",
            Self::Quarter => "quarter",
            Self::Open => "open",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "week" => Self::Week,
            "month" => Self::Month,
            "quarter" => Self::Quarter,
            "open" => Self::Open,
            _ => return None,
        })
    }
}

/// Lifecycle of a plan (the Flutter `ExecutionPlanStatus` wire names).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlanStatus {
    Active,
    Paused,
    Completed,
    Archived,
}

impl PlanStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Active => "active",
            Self::Paused => "paused",
            Self::Completed => "completed",
            Self::Archived => "archived",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "active" => Self::Active,
            "paused" => Self::Paused,
            "completed" => Self::Completed,
            "archived" => Self::Archived,
            _ => return None,
        })
    }

    /// Open plans still accept new actions.
    pub fn is_open(self) -> bool {
        matches!(self, Self::Active | Self::Paused)
    }
}

/// Status of an action (the Flutter `ExecutionActionStatus` wire names).
/// The transition to `done` is the progress record for this phase.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActionStatus {
    Todo,
    Doing,
    Blocked,
    Done,
    Dropped,
}

impl ActionStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Todo => "todo",
            Self::Doing => "doing",
            Self::Blocked => "blocked",
            Self::Done => "done",
            Self::Dropped => "dropped",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "todo" => Self::Todo,
            "doing" => Self::Doing,
            "blocked" => Self::Blocked,
            "done" => Self::Done,
            "dropped" => Self::Dropped,
            _ => return None,
        })
    }

    /// Open actions are still follow-through work.
    pub fn is_open(self) -> bool {
        matches!(self, Self::Todo | Self::Doing | Self::Blocked)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Plan {
    pub id: String,
    pub title: String,
    pub kind: PlanKind,
    pub period: PlanPeriod,
    pub status: PlanStatus,
    /// Epoch seconds the plan was created.
    pub created_at: i64,
    pub sync: SyncMeta,
}

#[derive(Debug, Clone)]
pub struct NewPlan {
    pub title: String,
    pub kind: PlanKind,
    pub period: PlanPeriod,
    /// Defaults to [`PlanStatus::Active`]; tests may override.
    pub status: PlanStatus,
    pub created_at: i64,
}

impl NewPlan {
    pub fn now(title: impl Into<String>, kind: PlanKind, period: PlanPeriod) -> Self {
        Self {
            title: title.into(),
            kind,
            period,
            status: PlanStatus::Active,
            created_at: lifeos::ids::now_secs(),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Action {
    pub id: String,
    pub plan_id: String,
    pub title: String,
    pub status: ActionStatus,
    /// Due moment (epoch seconds), `None` when unscheduled.
    pub due: Option<i64>,
    pub created_at: i64,
    pub sync: SyncMeta,
}

#[derive(Debug, Clone)]
pub struct NewAction {
    pub plan_id: String,
    pub title: String,
    pub due: Option<i64>,
    pub created_at: i64,
}

impl NewAction {
    pub fn now(plan_id: impl Into<String>, title: impl Into<String>) -> Self {
        Self {
            plan_id: plan_id.into(),
            title: title.into(),
            due: None,
            created_at: lifeos::ids::now_secs(),
        }
    }
}
