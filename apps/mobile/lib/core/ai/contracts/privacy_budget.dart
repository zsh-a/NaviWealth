/// Privacy / size budget tiers for [ContextPack].
///
/// The budget caps the JSON-serialized byte size of a ContextPack and,
/// by extension, governs which device tools can receive that context
/// tier (see [ToolDescriptor.allowedContextTier]). Code-enforced — not
/// a prompt rule.
library;

enum BudgetTier { small, standard, large }

extension BudgetTierWire on BudgetTier {
  String get wire => switch (this) {
    BudgetTier.small => 'small',
    BudgetTier.standard => 'standard',
    BudgetTier.large => 'large',
  };

  static BudgetTier parse(String s) => switch (s) {
    'small' => BudgetTier.small,
    'standard' => BudgetTier.standard,
    'large' => BudgetTier.large,
    _ => BudgetTier.standard,
  };

  /// Hard byte cap. Compressors must produce output strictly at or
  /// below this after JSON serialization; [ContextPack.assertBudget]
  /// enforces.
  int get byteCap => switch (this) {
    BudgetTier.small => 4 * 1024,
    BudgetTier.standard => 16 * 1024,
    BudgetTier.large => 64 * 1024,
  };
}

class PrivacyBudget {
  const PrivacyBudget({required this.tier});

  final BudgetTier tier;

  static const PrivacyBudget small = PrivacyBudget(tier: BudgetTier.small);
  static const PrivacyBudget standard = PrivacyBudget(
    tier: BudgetTier.standard,
  );
  static const PrivacyBudget large = PrivacyBudget(tier: BudgetTier.large);

  int get byteCap => tier.byteCap;

  Map<String, Object?> toJson() => <String, Object?>{'tier': tier.wire};

  factory PrivacyBudget.fromJson(Map<String, Object?> json) {
    final t = json['tier'];
    return PrivacyBudget(
      tier: t is String ? BudgetTierWire.parse(t) : BudgetTier.standard,
    );
  }
}
