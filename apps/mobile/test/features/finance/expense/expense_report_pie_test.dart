import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_category_seed_colors.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_report.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_report_pie.dart';
import 'package:naviwealth/features/finance/expense/ui/expense_category_visuals.dart';

void main() {
  group('kExpenseCategorySeedHexByPath', () {
    test('every path colour is unique', () {
      final hexes = kExpenseCategorySeedHexByPath.values.toList();
      expect(hexes.toSet().length, hexes.length);
    });

    test('icon map does not reuse hex across distinct non-alias icons', () {
      // phone_android / smartphone intentionally share communication hue.
      final sharedAliases = {'phone_android', 'smartphone'};
      final seen = <String, String>{};
      for (final entry in kExpenseCategorySeedHexByIcon.entries) {
        if (sharedAliases.contains(entry.key)) continue;
        final prior = seen[entry.value];
        expect(
          prior,
          isNull,
          reason: 'hex ${entry.value} used by both ${entry.key} and $prior',
        );
        seen[entry.value] = entry.key;
      }
    });
  });

  group('expenseCategoryPathFromAccountId', () {
    test('parses system expense paths', () {
      expect(
        expenseCategoryPathFromAccountId('system-account:u1:expense:dining'),
        'dining',
      );
      expect(
        expenseCategoryPathFromAccountId(
          'system-account:u1:expense:trading:fee',
        ),
        'trading:fee',
      );
      expect(expenseCategoryPathFromAccountId('user-account:abc'), isNull);
    });
  });

  group('collapseExpenseCategoriesForPie', () {
    CategoryBreakdown bucket(String id, int amount) {
      return CategoryBreakdown(
        expenseAccountId: id,
        total: Money(Decimal.fromInt(amount), 'CNY'),
        count: 1,
      );
    }

    test('returns input when at or under max slices', () {
      final input = [bucket('a', 10), bucket('b', 5)];
      final out = collapseExpenseCategoriesForPie(input, maxSlices: 8);
      expect(out, hasLength(2));
      expect(out.map((b) => b.expenseAccountId), ['a', 'b']);
    });

    test('rolls tail into Other keeping top maxSlices-1', () {
      final input = [for (var i = 0; i < 12; i++) bucket('c$i', 100 - i)];
      final out = collapseExpenseCategoriesForPie(input, maxSlices: 8);
      expect(out, hasLength(8));
      expect(out.take(7).map((b) => b.expenseAccountId).toList(), [
        for (var i = 0; i < 7; i++) 'c$i',
      ]);
      final other = out.last;
      expect(other.expenseAccountId, kExpenseReportPieOtherId);
      // amounts 93+92+91+90+89 = 455 for c7..c11
      expect(other.total.amount, Decimal.fromInt(93 + 92 + 91 + 90 + 89));
      expect(other.count, 5);
    });

    test('Other total equals sum of collapsed tail', () {
      final input = [
        bucket('a', 50),
        bucket('b', 40),
        bucket('c', 30),
        bucket('d', 20),
        bucket('e', 10),
      ];
      final out = collapseExpenseCategoriesForPie(input, maxSlices: 3);
      expect(out, hasLength(3));
      expect(out[0].expenseAccountId, 'a');
      expect(out[1].expenseAccountId, 'b');
      expect(out[2].expenseAccountId, kExpenseReportPieOtherId);
      expect(out[2].total.amount, Decimal.fromInt(60));
    });

    test('expenseReportOtherSource returns the collapsed tail only', () {
      final input = [for (var i = 0; i < 10; i++) bucket('c$i', 100 - i)];
      final collapsed = collapseExpenseCategoriesForPie(input, maxSlices: 8);
      final other = collapsed.last;
      final source = expenseReportOtherSource(
        byCategory: input,
        breakdown: other,
        maxSlices: 8,
      );
      expect(source, isNotNull);
      expect(source!.map((b) => b.expenseAccountId).toList(), [
        for (var i = 7; i < 10; i++) 'c$i',
      ]);
      expect(
        expenseReportOtherSource(byCategory: input, breakdown: collapsed.first),
        isNull,
      );
    });
  });
}
