/// Intent typing surface for AI policy, tracing, and prompt assembly.
///
/// Every AI-mediated user action in NaviWealth carries an [IntentHint].
/// The hint describes capability/risk/domain without coupling the
/// feature module to the device runtime implementation.
library;

/// Coarse capability the user is requesting. Forms one axis of the
/// intent policy matrix.
enum Capability {
  /// Categorise / tag / classify a single item. Local-first, very high
  /// frequency.
  classify,

  /// Structured search over the local ledger ('上月咖啡花了多少').
  search,

  /// Summarise a slice of state ('月报', '账户摘要').
  summarize,

  /// Multi-step reasoning that requires planning over portfolio /
  /// tax / FIRE state.
  plan,

  /// Read-only analysis or explanation ('为什么现金流异常').
  analyze,

  /// User-initiated mutation. The actual side-effect scope is captured
  /// downstream via the chosen [ProposalEnvelope] subtype.
  write,
}

/// Risk level of the action being routed. Orthogonal to [Capability]:
/// the same capability ('write') can manifest as either a low-risk
/// `LocalImmediateWrite` (memo edit) or an `ExternalSideEffect`
/// (broker order).
enum RiskLevel {
  /// Read-only, explanatory. No state changes, no side effects.
  info,

  /// Recommendation. The user is free to ignore. No state changes.
  suggest,

  /// Generates a [ProposalEnvelope] the user must confirm. State
  /// changes are staged, never auto-applied.
  propose,

  /// User-initiated direct mutation. Confirmation policy is decided by
  /// the proposal dispatcher (none for undoable local writes, typed for
  /// external side effects).
  commit,
}

extension CapabilityWire on Capability {
  String get wire => switch (this) {
    Capability.classify => 'classify',
    Capability.search => 'search',
    Capability.summarize => 'summarize',
    Capability.plan => 'plan',
    Capability.analyze => 'analyze',
    Capability.write => 'write',
  };

  static Capability parse(String s) => switch (s) {
    'classify' => Capability.classify,
    'search' => Capability.search,
    'summarize' => Capability.summarize,
    'plan' => Capability.plan,
    'analyze' => Capability.analyze,
    'write' => Capability.write,
    _ => Capability.analyze,
  };
}

extension RiskLevelWire on RiskLevel {
  String get wire => switch (this) {
    RiskLevel.info => 'info',
    RiskLevel.suggest => 'suggest',
    RiskLevel.propose => 'propose',
    RiskLevel.commit => 'commit',
  };

  static RiskLevel parse(String s) => switch (s) {
    'info' => RiskLevel.info,
    'suggest' => RiskLevel.suggest,
    'propose' => RiskLevel.propose,
    'commit' => RiskLevel.commit,
    _ => RiskLevel.info,
  };
}

/// Side-effect classification for `Capability.write` intents. Decides
/// which [ProposalEnvelope] subtype and confirmation flow are eligible
/// for a write intent. `null` for read-only intents.
enum SideEffectScope {
  /// Pure-local, undoable. Memo / tag / categorisation / dismissed
  /// insight / draft budget. Stays on-device, applies through
  /// LocalImmediateWrite or LocalProposal.
  local,

  /// Cross-cutting ledger mutation that needs multi-account reasoning
  /// (rebalance, FIRE plan adjustment, batch budget rebuild). Applied
  /// via the device propose flow + `proposal_applier`.
  crossCutting,

  /// Touches an external system (broker order, bank transfer,
  /// outbound webhook). Always typed-confirmation, always opt-in on
  /// every invocation. Maps to ExternalSideEffect.
  external,
}

extension SideEffectScopeWire on SideEffectScope {
  String get wire => switch (this) {
    SideEffectScope.local => 'local',
    SideEffectScope.crossCutting => 'cross_cutting',
    SideEffectScope.external => 'external',
  };

  static SideEffectScope parse(String s) => switch (s) {
    'local' => SideEffectScope.local,
    'cross_cutting' => SideEffectScope.crossCutting,
    'external' => SideEffectScope.external,
    _ => SideEffectScope.crossCutting,
  };
}

/// LifeOS domain identifier. Phase D-1.3 — every Intent / Trace /
/// ToolDescriptor carries a domain so tools, intents, and trace rows
/// can be partitioned per active domain (`finance`, `health`, ...).
///
/// Free-form string by design: the registry isn't a closed enum because
/// 1) the active domain set evolves slowly (Phase D-2 = `health`); 2)
/// trace rows written before Phase D-1.3 land with no `domain` field
/// and must decode to `finance` for backward compat.
const String kDomainFinance = 'finance';
const String kDomainHealth = 'health';
const String kDomainKnowledge = 'knowledge';

/// Default for legacy intents/traces/tools. Reading code outside
/// `core/ai/contracts/` should reference this constant rather than
/// hard-coding the string.
const String kDefaultDomain = kDomainFinance;

/// Typed input for a device AI turn. Every feature surface that wants
/// AI help produces one of these.
class IntentHint {
  const IntentHint({
    required this.capability,
    required this.risk,
    this.sideEffect,
    this.label,
    this.domain = kDefaultDomain,
  });

  final Capability capability;
  final RiskLevel risk;

  /// Required for [Capability.write]; ignored otherwise. When `null`
  /// on a write intent, the dispatcher conservatively treats it as a
  /// cross-cutting proposal that needs user confirmation.
  final SideEffectScope? sideEffect;

  /// Optional short label for tracing / UI ('monthly_report',
  /// 'expense_search'). Free-form, not policy-bearing.
  final String? label;

  /// LifeOS domain that owns this intent ('finance', 'health', ...).
  /// Phase D-1.3: required for new code; defaults to `finance` to keep
  /// pre-Phase-D trace rows decoding correctly.
  final String domain;

  Map<String, Object?> toJson() => <String, Object?>{
    'capability': capability.wire,
    'risk': risk.wire,
    if (sideEffect != null) 'side_effect': sideEffect!.wire,
    if (label != null) 'label': label,
    'domain': domain,
  };

  factory IntentHint.fromJson(Map<String, Object?> json) {
    final cap = json['capability'];
    final risk = json['risk'];
    final se = json['side_effect'];
    final label = json['label'];
    final domain = json['domain'];
    return IntentHint(
      capability: cap is String
          ? CapabilityWire.parse(cap)
          : Capability.analyze,
      risk: risk is String ? RiskLevelWire.parse(risk) : RiskLevel.info,
      sideEffect: se is String ? SideEffectScopeWire.parse(se) : null,
      label: label is String ? label : null,
      domain: domain is String && domain.isNotEmpty ? domain : kDefaultDomain,
    );
  }
}
