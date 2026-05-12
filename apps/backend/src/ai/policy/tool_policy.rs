//! Static tool catalogue with typed metadata.
//!
//! Mirrors `apps/mobile/lib/core/ai/contracts/tool_descriptor.dart` —
//! the device router consults the same axes when deciding whether to
//! invoke a tool. The two sides are kept aligned by review (the
//! descriptor types don't cross the wire).

use serde::{Serialize, Serializer};

use crate::ai::context::{BudgetTier, RiskLevel};

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Access {
    Read,
    Propose,
    /// Reserved for tools that touch external systems (broker / bank
    /// / outbound webhook). Currently empty — anything in this class
    /// is rejected by [`risk_policy::check_tool_call`].
    ExternalWrite,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Confirmation {
    None,
    OneTap,
    Typed,
}

/// Wave 20 — which runtimes are allowed to dispatch this tool. Bitset
/// instead of `Vec` so the descriptor stays `Copy` / `const`-able.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AllowedRuntimes(pub u8);

impl AllowedRuntimes {
    pub const DEVICE: u8 = 0b01;
    pub const CLOUD: u8 = 0b10;
    pub const ALL: AllowedRuntimes = AllowedRuntimes(Self::DEVICE | Self::CLOUD);
    pub const CLOUD_ONLY: AllowedRuntimes = AllowedRuntimes(Self::CLOUD);

    pub fn allows_device(self) -> bool {
        self.0 & Self::DEVICE != 0
    }
    pub fn allows_cloud(self) -> bool {
        self.0 & Self::CLOUD != 0
    }
}

impl Serialize for AllowedRuntimes {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut runtimes = Vec::new();
        if self.allows_device() {
            runtimes.push("device");
        }
        if self.allows_cloud() {
            runtimes.push("cloud");
        }
        runtimes.serialize(serializer)
    }
}

/// Wave 20 — side-effect classification (orthogonal to risk level).
/// Lets the dispatcher reject `ExternalCall` in routine chat without
/// a special grant.
#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SideEffect {
    None,
    /// Creates a device-local write proposal (the user still must confirm).
    DeviceLocalWrite,
    /// Hits a third-party system (broker / bank / outbound webhook).
    ExternalCall,
}

/// Wave 20 — which Read Model layer this tool consumes (or `None` for
/// inline computers / proposals).
#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ReadModelLayer {
    Snapshot,
    Analytical,
    ScopedDetail,
}

#[derive(Debug, Clone, Copy, Serialize)]
pub struct ToolDescriptor {
    pub name: &'static str,
    pub access: Access,
    pub risk: RiskLevel,
    pub requires_confirmation: Confirmation,
    /// Minimum [`BudgetTier`] the device must have sent for this tool
    /// to be admissible. `Small` means the tool is universally
    /// allowed; `Large` reserves it for the user-gestured 'deep
    /// analysis' surfaces.
    pub allowed_context_tier: BudgetTier,
    /// Wave 20 — which runtimes may dispatch (device LLM vs cloud
    /// orchestrator). All tools default to `CloudOnly` until the device
    /// LLM runtime ships in Phase 5.
    pub allowed_runtimes: AllowedRuntimes,
    /// Wave 20 — side-effect class. Orthogonal to risk level.
    pub side_effect: SideEffect,
    /// Wave 20 — which Read Model layer this tool consumes. `None` for
    /// inline computers (e.g. `compute_xirr`) and proposals.
    pub read_model_layer: Option<ReadModelLayer>,
}
