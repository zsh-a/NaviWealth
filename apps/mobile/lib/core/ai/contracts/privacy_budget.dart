/// Context-size classification shared by tool descriptors and AI traces.
/// Actual prompt budgets are enforced by the Agent Runtime context policy.
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
}
