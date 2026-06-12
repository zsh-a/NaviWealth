/// Code-level metadata for an AI tool.
///
/// The cloud AI backend was removed, so this catalog no longer mirrors
/// a Rust registry. Each LifeOS domain co-locates tool registrations
/// with its tool barrel and derives descriptor maps from that single
/// source of truth. The full production union lives in
/// `app/production_ai_catalog.dart` so this contract package remains
/// domain-neutral.
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

  /// LifeOS domain this tool belongs to (`finance` / `health` /
  /// `knowledge` / `shell` for cross-domain).
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
/// tools from any single LifeOS domain.
const String kDomainShell = 'shell';
