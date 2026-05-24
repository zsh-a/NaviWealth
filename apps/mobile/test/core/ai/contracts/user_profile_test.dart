import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/user_profile.dart';

ExpenseObservation _obs(String id, String label, String amount) =>
    ExpenseObservation(
      categoryId: id,
      categoryLabel: label,
      amount: Decimal.parse(amount),
    );

void main() {
  group('composeUserProfile', () {
    test('empty expenses yields zero savings rate and no categories', () {
      final profile = composeUserProfile(
        expenses: const [],
        incomeTotal: Decimal.zero,
        riskAppetite: RiskAppetite.moderate,
        baseCurrency: 'cny',
      );
      expect(profile.savingsRate, 0.0);
      expect(profile.topCategories, isEmpty);
      expect(profile.baseCurrency, 'CNY', reason: 'currency is uppercased');
    });

    test('savings rate = (income - expense) / income, clamped', () {
      final profile = composeUserProfile(
        expenses: [_obs('cat-food', 'Food', '3000')],
        incomeTotal: Decimal.parse('10000'),
        riskAppetite: RiskAppetite.moderate,
        baseCurrency: 'CNY',
      );
      expect(profile.savingsRate, closeTo(0.7, 1e-9));
    });

    test('negative savings rate (overspending) is preserved', () {
      final profile = composeUserProfile(
        expenses: [_obs('cat-food', 'Food', '5000')],
        incomeTotal: Decimal.parse('4000'),
        riskAppetite: RiskAppetite.moderate,
        baseCurrency: 'CNY',
      );
      expect(profile.savingsRate, closeTo(-0.25, 1e-9));
    });

    test('zero income → savings rate falls back to 0, not NaN', () {
      final profile = composeUserProfile(
        expenses: [_obs('cat-food', 'Food', '500')],
        incomeTotal: Decimal.zero,
        riskAppetite: RiskAppetite.moderate,
        baseCurrency: 'CNY',
      );
      expect(profile.savingsRate, 0.0);
    });

    test('top categories are sorted by share descending and capped', () {
      final profile = composeUserProfile(
        expenses: [
          _obs('cat-food', 'Food', '3000'),
          _obs('cat-rent', 'Rent', '5000'),
          _obs('cat-trans', 'Transit', '500'),
          _obs('cat-fun', 'Leisure', '700'),
          _obs('cat-misc', 'Misc', '300'),
          _obs('cat-extra', 'Extra', '50'),
        ],
        incomeTotal: Decimal.parse('20000'),
        riskAppetite: RiskAppetite.moderate,
        baseCurrency: 'CNY',
        topCategoryLimit: 3,
      );
      expect(
        profile.topCategories.map((c) => c.categoryId).toList(),
        ['cat-rent', 'cat-food', 'cat-fun'],
      );
      // rent / (rent + food + transit + fun + misc + extra)
      // = 5000 / 9550 ≈ 0.524
      expect(profile.topCategories.first.shareFraction, closeTo(0.524, 0.01));
    });

    test('same-category observations are aggregated', () {
      final profile = composeUserProfile(
        expenses: [
          _obs('cat-food', 'Food', '1000'),
          _obs('cat-food', 'Food', '2000'),
          _obs('cat-rent', 'Rent', '4000'),
        ],
        incomeTotal: Decimal.parse('10000'),
        riskAppetite: RiskAppetite.moderate,
        baseCurrency: 'CNY',
      );
      expect(profile.topCategories, hasLength(2));
      expect(profile.topCategories.first.categoryId, 'cat-rent');
      expect(profile.topCategories[1].categoryId, 'cat-food');
      expect(profile.topCategories[1].shareFraction, closeTo(3000 / 7000, 1e-9));
    });

    test('negative amounts are treated as absolute outflows', () {
      // Postings on expense accounts can be stored as negatives; the
      // composer should treat them as positive expense contributions.
      final profile = composeUserProfile(
        expenses: [
          _obs('cat-food', 'Food', '-1000'),
          _obs('cat-food', 'Food', '500'),
        ],
        incomeTotal: Decimal.parse('10000'),
        riskAppetite: RiskAppetite.moderate,
        baseCurrency: 'CNY',
      );
      expect(profile.topCategories.single.shareFraction, 1.0);
    });

    test('JSON roundtrip preserves fields under the 8KB budget', () {
      final profile = composeUserProfile(
        expenses: [
          _obs('cat-food', 'Food', '3000'),
          _obs('cat-rent', 'Rent', '5000'),
        ],
        incomeTotal: Decimal.parse('20000'),
        riskAppetite: RiskAppetite.aggressive,
        baseCurrency: 'CNY',
      );
      final encoded = jsonEncode(profile.toJson());
      expect(encoded.length, lessThan(8 * 1024));
      final decoded = UserProfile.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      );
      expect(decoded.riskAppetite, RiskAppetite.aggressive);
      expect(decoded.topCategories.first.categoryId, 'cat-rent');
      expect(decoded.savingsRate, closeTo(profile.savingsRate, 1e-3));
      expect(decoded.baseCurrency, 'CNY');
    });

    test('unknown risk appetite falls through to moderate', () {
      final decoded = UserProfile.fromJson(<String, Object?>{
        'version': '1.0',
        'window_days': 90,
        'savings_rate': 0.1,
        'risk_appetite': 'paranoid', // not a real value
        'top_categories': <Object?>[],
        'base_currency': 'CNY',
      });
      expect(decoded.riskAppetite, RiskAppetite.moderate);
    });

    test('rejects non-positive windowDays / topCategoryLimit', () {
      expect(
        () => composeUserProfile(
          expenses: const [],
          incomeTotal: Decimal.zero,
          riskAppetite: RiskAppetite.moderate,
          baseCurrency: 'CNY',
          windowDays: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => composeUserProfile(
          expenses: const [],
          incomeTotal: Decimal.zero,
          riskAppetite: RiskAppetite.moderate,
          baseCurrency: 'CNY',
          topCategoryLimit: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  // §3.4 evidence anchor — tool outputs can reference posting / account
  // IDs alongside the model's response. A minimal type lives in the
  // contracts layer so any tool can emit it without depending on UI.
  group('UserProfile JSON shape stability', () {
    test('toJson uses snake_case wire keys', () {
      final profile = composeUserProfile(
        expenses: [_obs('cat-food', 'Food', '100')],
        incomeTotal: Decimal.parse('1000'),
        riskAppetite: RiskAppetite.moderate,
        baseCurrency: 'CNY',
      );
      final json = profile.toJson();
      expect(json.keys, containsAll(<String>[
        'version',
        'window_days',
        'savings_rate',
        'risk_appetite',
        'top_categories',
        'base_currency',
      ]));
      final cat = (json['top_categories']! as List).first
          as Map<String, Object?>;
      expect(cat.keys, containsAll(<String>['category_id', 'label', 'share']));
    });
  });
}
