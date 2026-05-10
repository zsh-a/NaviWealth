/// Code-level metadata for an AI tool.
///
/// Mirrors the Rust ToolDescriptor 1:1. The cloud uses this metadata
/// to enforce risk_policy at the orchestrator (not at the prompt). The
/// mobile mirror exists so the device router can inspect an upcoming
/// tool call and decide whether the current ContextPack tier and
/// consent state allow it.
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

class ToolDescriptor {
  const ToolDescriptor({
    required this.name,
    required this.access,
    required this.risk,
    required this.requiresConfirmation,
    required this.allowedContextTier,
  });

  final String name;
  final Access access;
  final RiskLevel risk;
  final Confirmation requiresConfirmation;

  /// Minimum [BudgetTier] required to invoke. A `large`-only tool
  /// cannot be called with a `small` ContextPack — code-enforced
  /// upstream of the model so prompt injection cannot escalate.
  final BudgetTier allowedContextTier;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'access': access.wire,
    'risk': risk.wire,
    'requires_confirmation': requiresConfirmation.wire,
    'allowed_context_tier': allowedContextTier.wire,
  };

  factory ToolDescriptor.fromJson(Map<String, Object?> json) {
    final n = json['name'];
    final a = json['access'];
    final r = json['risk'];
    final c = json['requires_confirmation'];
    final t = json['allowed_context_tier'];
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
    );
  }
}
