/// AI Copilot M1 — compact user profile (see `roadmap-midterm-execution.md`
/// §2.5 M1.1).
///
/// The profile is a single small JSON-shaped struct injected into the AI
/// system prompt so the model can ground its answers in the user's actual
/// spending shape and risk posture *without* the chat having to call a
/// tool first. Everything here is **derived**, not stored: the composer
/// runs over the same data the dashboard reads.
///
/// Hard budget: < 8KB serialised. Anything longer must drop precision
/// (truncate categories / round to one decimal) rather than overflow into
/// the conversation prompt.
library;

import 'package:decimal/decimal.dart';

/// One slot in the consumption-concentration top-N list.
class CategoryShare {
  const CategoryShare({
    required this.categoryId,
    required this.label,
    required this.shareFraction,
  });

  final String categoryId;

  /// Human label, e.g. "餐饮" / "Dining". The composer takes whatever the
  /// caller supplies; downstream surfaces don't have to look the label up
  /// again.
  final String label;

  /// Share of total expense in `[0, 1]`. Sum of all shares ≤ 1.
  final double shareFraction;

  Map<String, Object?> toJson() => <String, Object?>{
        'category_id': categoryId,
        'label': label,
        'share': double.parse(shareFraction.toStringAsFixed(3)),
      };

  factory CategoryShare.fromJson(Map<String, Object?> json) => CategoryShare(
        categoryId: json['category_id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        shareFraction: switch (json['share']) {
          final num n => n.toDouble(),
          _ => 0.0,
        },
      );
}

/// Risk-preference proxy. Mirrors the user's settings choice — kept as a
/// label so the model can reason about it in plain language.
enum RiskAppetite { conservative, moderate, aggressive }

extension RiskAppetiteWire on RiskAppetite {
  String get wire => switch (this) {
        RiskAppetite.conservative => 'conservative',
        RiskAppetite.moderate => 'moderate',
        RiskAppetite.aggressive => 'aggressive',
      };

  static RiskAppetite parse(String? s) => switch (s) {
        'conservative' => RiskAppetite.conservative,
        'aggressive' => RiskAppetite.aggressive,
        _ => RiskAppetite.moderate,
      };
}

/// Compact, evidence-free portrait of the user that ships in the AI
/// system prompt. Field set is intentionally narrow — adding a field has
/// a real prompt-budget cost, so each new one needs a current caller.
class UserProfile {
  const UserProfile({
    required this.windowDays,
    required this.savingsRate,
    required this.riskAppetite,
    required this.topCategories,
    required this.baseCurrency,
  });

  /// Trailing window (days) the profile was computed over. Lets the
  /// model say "over the past 90 days" without inferring it.
  final int windowDays;

  /// `(income - expense) / max(income, 1)` clamped to `[-1, 1]`. Negative
  /// = user spent more than they earned over the window.
  final double savingsRate;

  final RiskAppetite riskAppetite;

  /// Top expense categories by share, ordered descending. Limited to keep
  /// the prompt small — typically `<= 5`.
  final List<CategoryShare> topCategories;

  final String baseCurrency;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': '1.0',
        'window_days': windowDays,
        'savings_rate': double.parse(savingsRate.toStringAsFixed(3)),
        'risk_appetite': riskAppetite.wire,
        'top_categories': topCategories
            .map((c) => c.toJson())
            .toList(growable: false),
        'base_currency': baseCurrency,
      };

  factory UserProfile.fromJson(Map<String, Object?> json) => UserProfile(
        windowDays: switch (json['window_days']) {
          final num n => n.toInt(),
          _ => 90,
        },
        savingsRate: switch (json['savings_rate']) {
          final num n => n.toDouble(),
          _ => 0.0,
        },
        riskAppetite: RiskAppetiteWire.parse(json['risk_appetite'] as String?),
        topCategories: switch (json['top_categories']) {
          final List<Object?> list => list
              .whereType<Map<String, Object?>>()
              .map(CategoryShare.fromJson)
              .toList(growable: false),
          _ => const [],
        },
        baseCurrency: json['base_currency'] as String? ?? 'CNY',
      );
}

/// One observation handed to [composeUserProfile] — typically a posting,
/// flattened to the minimum the composer needs.
class ExpenseObservation {
  const ExpenseObservation({
    required this.categoryId,
    required this.categoryLabel,
    required this.amount,
  });

  final String categoryId;
  final String categoryLabel;

  /// Always positive (the composer treats it as the absolute outflow).
  final Decimal amount;
}

/// Compose a [UserProfile] from raw aggregates. **Pure function** — no
/// I/O, no FX conversion (caller pre-converts to [baseCurrency]). The 50ms
/// / 10k-entries perf target in `roadmap-midterm-execution.md` §2.5 M1.6
/// is achievable because this is a single O(n) pass plus a sort over the
/// distinct category set.
///
/// [topCategoryLimit] defaults to 5 — every extra slot in [topCategories]
/// costs ~30B in the serialised prompt; 5 is enough to characterise even
/// fragmented spending without exhausting the 8KB budget.
UserProfile composeUserProfile({
  required Iterable<ExpenseObservation> expenses,
  required Decimal incomeTotal,
  required RiskAppetite riskAppetite,
  required String baseCurrency,
  int windowDays = 90,
  int topCategoryLimit = 5,
}) {
  if (windowDays <= 0) {
    throw ArgumentError.value(
      windowDays,
      'windowDays',
      'must be > 0',
    );
  }
  if (topCategoryLimit <= 0) {
    throw ArgumentError.value(
      topCategoryLimit,
      'topCategoryLimit',
      'must be > 0',
    );
  }

  var totalExpense = Decimal.zero;
  final byCategory = <String, _CategoryAccum>{};
  for (final obs in expenses) {
    final amount = obs.amount.abs();
    totalExpense += amount;
    final acc = byCategory.putIfAbsent(
      obs.categoryId,
      () => _CategoryAccum(label: obs.categoryLabel),
    );
    acc.total += amount;
  }

  final shares = <CategoryShare>[];
  if (totalExpense > Decimal.zero) {
    final totalDouble = totalExpense.toDouble();
    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    for (final entry in entries.take(topCategoryLimit)) {
      shares.add(
        CategoryShare(
          categoryId: entry.key,
          label: entry.value.label,
          shareFraction: entry.value.total.toDouble() / totalDouble,
        ),
      );
    }
  }

  final savingsRate = _savingsRate(income: incomeTotal, expense: totalExpense);

  return UserProfile(
    windowDays: windowDays,
    savingsRate: savingsRate,
    riskAppetite: riskAppetite,
    topCategories: shares,
    baseCurrency: baseCurrency.toUpperCase(),
  );
}

double _savingsRate({required Decimal income, required Decimal expense}) {
  // Saving rate is meaningless without income — surface it as zero so the
  // prompt can flag "savings_rate=0 in a 90d window" rather than NaN.
  if (income <= Decimal.zero) return 0.0;
  final raw = (income - expense).toDouble() / income.toDouble();
  if (raw > 1.0) return 1.0;
  if (raw < -1.0) return -1.0;
  return raw;
}

class _CategoryAccum {
  _CategoryAccum({required this.label});
  final String label;
  Decimal total = Decimal.zero;
}
