/// Code-level metadata for an AI tool.
///
/// Metadata for the active device-dispatchable AI tools.
///
/// W-D7 removed the cloud AI backend, so this catalog no longer mirrors
/// a Rust registry. Keep it aligned with `kDeviceTools`: a descriptor
/// here means the tool can be advertised and dispatched by the device
/// runtime.
library;

import 'intent.dart' show RiskLevel, RiskLevelWire;
import 'privacy_budget.dart' show BudgetTier, BudgetTierWire;

enum Access { read, propose, externalWrite }

extension AccessWire on Access {
  String get wire => switch (this) {
    Access.read => 'read',
    Access.propose => 'propose',
    Access.externalWrite => 'external_write',
  };

  static Access parse(String s) => switch (s) {
    'read' => Access.read,
    'propose' => Access.propose,
    'external_write' => Access.externalWrite,
    _ => Access.read,
  };
}

enum Confirmation { none, oneTap, typed }

extension ConfirmationWire on Confirmation {
  String get wire => switch (this) {
    Confirmation.none => 'none',
    Confirmation.oneTap => 'one_tap',
    Confirmation.typed => 'typed',
  };

  static Confirmation parse(String s) => switch (s) {
    'none' => Confirmation.none,
    'one_tap' => Confirmation.oneTap,
    'typed' => Confirmation.typed,
    _ => Confirmation.typed,
  };
}

/// Which runtimes are allowed to dispatch this tool. Wave 20 introduces
/// the field to support the upcoming `AiRuntime` abstraction (Wave 22).
enum AllowedRuntime { device, cloud }

extension AllowedRuntimeWire on AllowedRuntime {
  String get wire => switch (this) {
    AllowedRuntime.device => 'device',
    AllowedRuntime.cloud => 'cloud',
  };

  static AllowedRuntime parse(String s) => switch (s) {
    'device' => AllowedRuntime.device,
    'cloud' => AllowedRuntime.cloud,
    _ => AllowedRuntime.cloud,
  };
}

/// Side-effect classification (orthogonal to risk). Lets the dispatcher
/// reject `externalCall` in routine chat without a special grant.
enum SideEffect { none, deviceLocalWrite, externalCall }

extension SideEffectWire on SideEffect {
  String get wire => switch (this) {
    SideEffect.none => 'none',
    SideEffect.deviceLocalWrite => 'device_local_write',
    SideEffect.externalCall => 'external_call',
  };

  static SideEffect parse(String s) => switch (s) {
    'none' => SideEffect.none,
    'device_local_write' => SideEffect.deviceLocalWrite,
    'external_call' => SideEffect.externalCall,
    _ => SideEffect.none,
  };
}

/// Which Read Model layer this tool reads (docs/ai-architecture.md §4.3).
/// `null` = not a Read Model consumer (for example proposal tools).
enum ReadModelLayer { snapshot, analytical, scopedDetail }

extension ReadModelLayerWire on ReadModelLayer {
  String get wire => switch (this) {
    ReadModelLayer.snapshot => 'snapshot',
    ReadModelLayer.analytical => 'analytical',
    ReadModelLayer.scopedDetail => 'scoped_detail',
  };

  static ReadModelLayer? parse(String? s) => switch (s) {
    'snapshot' => ReadModelLayer.snapshot,
    'analytical' => ReadModelLayer.analytical,
    'scoped_detail' => ReadModelLayer.scopedDetail,
    _ => null,
  };
}

class ToolDescriptor {
  const ToolDescriptor({
    required this.name,
    required this.access,
    required this.risk,
    required this.requiresConfirmation,
    required this.allowedContextTier,
    // §4.6 W-D7 — the cloud AI backend was deleted; every tool now runs
    // device-only. No descriptor overrides this, so the default *is*
    // the reconciliation (line 1254: "allowed_runtimes … 删 cloud 时一
    // 并 flip"). Registry membership (`kDeviceTools`) remains the real
    // dispatch gate; this field is now consistent metadata, not cloud.
    this.allowedRuntimes = const <AllowedRuntime>{AllowedRuntime.device},
    this.sideEffect = SideEffect.none,
    this.readModelLayer,
  });

  final String name;
  final Access access;
  final RiskLevel risk;
  final Confirmation requiresConfirmation;

  /// Minimum [BudgetTier] required to invoke. A `large`-only tool
  /// cannot be called with a `small` ContextPack — code-enforced
  /// upstream of the model so prompt injection cannot escalate.
  final BudgetTier allowedContextTier;

  /// Which runtimes may dispatch this tool. Empty set never matches.
  final Set<AllowedRuntime> allowedRuntimes;

  /// Side-effect classification (orthogonal to risk level).
  final SideEffect sideEffect;

  /// Read Model layer this tool consumes; `null` means it doesn't.
  final ReadModelLayer? readModelLayer;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'access': access.wire,
    'risk': risk.wire,
    'requires_confirmation': requiresConfirmation.wire,
    'allowed_context_tier': allowedContextTier.wire,
    'allowed_runtimes': <String>[for (final r in allowedRuntimes) r.wire],
    'side_effect': sideEffect.wire,
    'read_model_layer': readModelLayer?.wire,
  };

  factory ToolDescriptor.fromJson(Map<String, Object?> json) {
    final n = json['name'];
    final a = json['access'];
    final r = json['risk'];
    final c = json['requires_confirmation'];
    final t = json['allowed_context_tier'];
    final ar = json['allowed_runtimes'];
    final se = json['side_effect'];
    final rml = json['read_model_layer'];
    return ToolDescriptor(
      name: n is String ? n : '',
      access: a is String ? AccessWire.parse(a) : Access.read,
      risk: r is String ? RiskLevelWire.parse(r) : RiskLevel.info,
      requiresConfirmation: c is String
          ? ConfirmationWire.parse(c)
          : Confirmation.typed,
      allowedContextTier: t is String
          ? BudgetTierWire.parse(t)
          : BudgetTier.standard,
      allowedRuntimes: ar is List
          ? {
              for (final s in ar.whereType<String>())
                AllowedRuntimeWire.parse(s),
            }
          : const <AllowedRuntime>{AllowedRuntime.device},
      sideEffect: se is String ? SideEffectWire.parse(se) : SideEffect.none,
      readModelLayer: rml is String ? ReadModelLayerWire.parse(rml) : null,
    );
  }
}

const allToolDescriptors = <ToolDescriptor>[
  ToolDescriptor(
    name: 'get_anomaly_flags',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    readModelLayer: ReadModelLayer.analytical,
  ),
  ToolDescriptor(
    name: 'get_asset_allocation',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    readModelLayer: ReadModelLayer.snapshot,
  ),
  ToolDescriptor(
    name: 'get_cashflow_buckets',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    readModelLayer: ReadModelLayer.snapshot,
  ),
  ToolDescriptor(
    name: 'get_geo_breakdown',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    readModelLayer: ReadModelLayer.snapshot,
  ),
  ToolDescriptor(
    name: 'get_holdings',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    readModelLayer: ReadModelLayer.snapshot,
  ),
  ToolDescriptor(
    name: 'get_industry_breakdown',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    readModelLayer: ReadModelLayer.snapshot,
  ),
  ToolDescriptor(
    name: 'get_investment_performance',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    readModelLayer: ReadModelLayer.analytical,
  ),
  ToolDescriptor(
    name: 'get_market_cap_breakdown',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    readModelLayer: ReadModelLayer.snapshot,
  ),
  ToolDescriptor(
    name: 'get_net_worth_summary',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    readModelLayer: ReadModelLayer.snapshot,
  ),
  ToolDescriptor(
    name: 'get_recurring_patterns',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    readModelLayer: ReadModelLayer.analytical,
  ),
  ToolDescriptor(
    name: 'get_refund_links',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    readModelLayer: ReadModelLayer.analytical,
  ),
  ToolDescriptor(
    name: 'get_subscription_changes',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    readModelLayer: ReadModelLayer.analytical,
  ),
  ToolDescriptor(
    name: 'get_transfer_links',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    readModelLayer: ReadModelLayer.analytical,
  ),
  ToolDescriptor(
    name: 'list_payment_accounts',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
  ),
  ToolDescriptor(
    name: 'propose_account_create',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
  ),
  ToolDescriptor(
    name: 'propose_asset_valuation',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
  ),
  ToolDescriptor(
    name: 'propose_expense',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.small,
    sideEffect: SideEffect.deviceLocalWrite,
  ),
  ToolDescriptor(
    name: 'propose_liability_payment',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
  ),
  ToolDescriptor(
    name: 'propose_trade',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
  ),
  ToolDescriptor(
    name: 'read_account_window',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    readModelLayer: ReadModelLayer.scopedDetail,
  ),
  ToolDescriptor(
    name: 'read_asset_window',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    readModelLayer: ReadModelLayer.scopedDetail,
  ),
  ToolDescriptor(
    name: 'read_category_window',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    readModelLayer: ReadModelLayer.scopedDetail,
  ),
  // FIRE OS Phase 5 tools — see docs/roadmap-fire-os.md §5.
  ToolDescriptor(
    name: 'get_fire_state',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    readModelLayer: ReadModelLayer.analytical,
  ),
  ToolDescriptor(
    name: 'get_fire_plan',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    readModelLayer: ReadModelLayer.snapshot,
  ),
  ToolDescriptor(
    name: 'get_fire_buckets',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    readModelLayer: ReadModelLayer.analytical,
  ),
  ToolDescriptor(
    name: 'get_fire_stress_tests',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    readModelLayer: ReadModelLayer.analytical,
  ),
  ToolDescriptor(
    name: 'get_fire_review',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    readModelLayer: ReadModelLayer.analytical,
  ),
  ToolDescriptor(
    name: 'simulate_fire_plan',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    readModelLayer: ReadModelLayer.analytical,
  ),
  ToolDescriptor(
    name: 'propose_fire_plan_update',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
  ),
  ToolDescriptor(
    name: 'propose_fire_bucket_rule',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
  ),
];

ToolDescriptor? lookupToolDescriptor(String name) {
  for (final descriptor in allToolDescriptors) {
    if (descriptor.name == name) return descriptor;
  }
  return null;
}
