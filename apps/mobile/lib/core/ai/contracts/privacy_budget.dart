/// Privacy / size budget tiers for [ContextPack].
///
/// The budget caps the JSON-serialized byte size of a ContextPack and,
/// by extension, governs which tools the cloud planner is allowed to
/// call (see [ToolDescriptor.allowedContextTier]). Code-enforced — not
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

/// How aggressively the device should anonymize ledger fields before
/// returning them to the cloud planner via DisclosureResponse.
enum AnonymizationLevel {
  /// Verbatim. Only allowed for non-PII fields like amount / category.
  none,

  /// Bucketed (e.g. amounts to nearest 10, dates to week).
  bucket,

  /// One-way hash with per-session salt. Stable within a session for
  /// correlation, opaque across sessions.
  hash,

  /// Replaced with a constant placeholder. Used when the cloud asked
  /// for a field the privacy gate disagreed with.
  redact,
}

extension AnonymizationLevelWire on AnonymizationLevel {
  String get wire => switch (this) {
    AnonymizationLevel.none => 'none',
    AnonymizationLevel.bucket => 'bucket',
    AnonymizationLevel.hash => 'hash',
    AnonymizationLevel.redact => 'redact',
  };

  static AnonymizationLevel parse(String s) => switch (s) {
    'none' => AnonymizationLevel.none,
    'bucket' => AnonymizationLevel.bucket,
    'hash' => AnonymizationLevel.hash,
    'redact' => AnonymizationLevel.redact,
    _ => AnonymizationLevel.redact,
  };
}
