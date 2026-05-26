/// Code-level metadata for an AI tool.
///
/// Metadata for the active device-dispatchable AI tools.
///
/// W-D7 removed the cloud AI backend, so this catalog no longer mirrors
/// a Rust registry. Keep it aligned with `kDeviceTools`: a descriptor
/// here means the tool can be advertised and dispatched by the device
/// runtime.
library;

import 'intent.dart' show RiskLevel, RiskLevelWire, kDefaultDomain;
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

class ToolDescriptor {
  const ToolDescriptor({
    required this.name,
    required this.access,
    required this.risk,
    required this.requiresConfirmation,
    required this.allowedContextTier,
    this.sideEffect = SideEffect.none,
    this.domain = kDefaultDomain,
  });

  final String name;
  final Access access;
  final RiskLevel risk;
  final Confirmation requiresConfirmation;

  /// Minimum [BudgetTier] required to invoke. A `large`-only tool
  /// cannot be called with a `small` ContextPack — code-enforced
  /// upstream of the model so prompt injection cannot escalate.
  final BudgetTier allowedContextTier;

  /// Side-effect classification (orthogonal to risk level).
  final SideEffect sideEffect;

  /// LifeOS domain this tool belongs to. Cross-domain shell tools
  /// (Memory Layer `query_memory` / `build_context`) use `shell`. All
  /// Finance business tools use `finance` (default). Phase D-2 will
  /// add `health` tools.
  final String domain;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'access': access.wire,
    'risk': risk.wire,
    'requires_confirmation': requiresConfirmation.wire,
    'allowed_context_tier': allowedContextTier.wire,
    'side_effect': sideEffect.wire,
    'domain': domain,
  };

  factory ToolDescriptor.fromJson(Map<String, Object?> json) {
    final n = json['name'];
    final a = json['access'];
    final r = json['risk'];
    final c = json['requires_confirmation'];
    final t = json['allowed_context_tier'];
    final se = json['side_effect'];
    final domain = json['domain'];
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
      sideEffect: se is String ? SideEffectWire.parse(se) : SideEffect.none,
      domain: domain is String && domain.isNotEmpty ? domain : kDefaultDomain,
    );
  }
}

/// Cross-domain shell tools (Memory Layer). Distinguishes shell-level
/// tools from any single domain so registry / lint can treat them
/// separately from `kDomainFinance` / future `kDomainHealth`.
const String kDomainShell = 'shell';

const allToolDescriptors = <ToolDescriptor>[
  ToolDescriptor(
    name: 'get_anomaly_flags',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
  ),
  ToolDescriptor(
    name: 'get_asset_allocation',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
  ),
  ToolDescriptor(
    name: 'get_cashflow_buckets',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
  ),
  ToolDescriptor(
    name: 'get_geo_breakdown',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
  ),
  ToolDescriptor(
    name: 'get_holdings',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
  ),
  ToolDescriptor(
    name: 'get_industry_breakdown',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
  ),
  ToolDescriptor(
    name: 'get_investment_performance',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
  ),
  ToolDescriptor(
    name: 'get_market_cap_breakdown',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
  ),
  ToolDescriptor(
    name: 'get_net_worth_summary',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
  ),
  ToolDescriptor(
    name: 'get_recurring_patterns',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
  ),
  ToolDescriptor(
    name: 'get_refund_links',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
  ),
  ToolDescriptor(
    name: 'get_subscription_changes',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
  ),
  ToolDescriptor(
    name: 'get_transfer_links',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
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
  ),
  ToolDescriptor(
    name: 'read_asset_window',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
  ),
  ToolDescriptor(
    name: 'read_category_window',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
  ),
  // FIRE OS Phase 5 tools — see docs/roadmap-fire-os.md §5.
  ToolDescriptor(
    name: 'get_fire_state',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
  ),
  ToolDescriptor(
    name: 'get_fire_plan',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
  ),
  ToolDescriptor(
    name: 'get_fire_buckets',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
  ),
  ToolDescriptor(
    name: 'get_fire_stress_tests',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
  ),
  ToolDescriptor(
    name: 'get_fire_review',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
  ),
  ToolDescriptor(
    name: 'simulate_fire_plan',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
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
  // Options Income Planner — see docs/options-income.md §8.2.
  ToolDescriptor(
    name: 'get_options_income_opportunities',
    access: Access.read,
    risk: RiskLevel.suggest,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
  ),
  ToolDescriptor(
    name: 'get_options_strategy_profile',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
  ),
  ToolDescriptor(
    name: 'propose_options_profile_update',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
  ),
  ToolDescriptor(
    name: 'propose_options_journal_entry',
    access: Access.propose,
    risk: RiskLevel.propose,
    requiresConfirmation: Confirmation.oneTap,
    allowedContextTier: BudgetTier.standard,
    sideEffect: SideEffect.deviceLocalWrite,
  ),
  // Income Planner P4 — Wheel cycle lifecycle (`roadmap-next.md` §3.3).
  ToolDescriptor(
    name: 'get_wheel_lifecycle',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
  ),
  // Memory Runtime (`lifeos-shell.md` §6, D-1.7b). Shell-level (cross-domain).
  ToolDescriptor(
    name: 'query_memory',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.small,
    domain: kDomainShell,
  ),
  ToolDescriptor(
    name: 'build_context',
    access: Access.read,
    risk: RiskLevel.info,
    requiresConfirmation: Confirmation.none,
    allowedContextTier: BudgetTier.standard,
    domain: kDomainShell,
  ),
];

ToolDescriptor? lookupToolDescriptor(String name) {
  for (final descriptor in allToolDescriptors) {
    if (descriptor.name == name) return descriptor;
  }
  return null;
}
