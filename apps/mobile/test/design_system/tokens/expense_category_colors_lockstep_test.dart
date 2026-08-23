import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/tokens/color_palette.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_category_seed_colors.dart';

/// Lockstep guard for the duplicated expense-category color tables.
///
/// `ExpenseCategoryColors` (design_system tokens) and the `kExpenseColor*` /
/// `kExpenseCategorySeedHexByPath` hex strings (Finance expense domain, the
/// DB-seed source of truth) are two hand-maintained copies of the same
/// palette. Neither side may import the other (features must not import
/// `ColorPalette`; design_system must not depend on features), so this test
/// is the enforcement mechanism: it parses both sides and asserts pairwise
/// equality. If it fails, update both tables together.
void main() {
  Color parseHex(String hex) {
    assert(hex.startsWith('#') && hex.length == 7, 'expected #RRGGBB: $hex');
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }

  group('ExpenseCategoryColors ↔ expense seed hex lockstep', () {
    // Seed path (relative to `expense:`) → ExpenseCategoryColors token.
    const pathTokens = <String, Color>{
      'dining': ExpenseCategoryColors.dining,
      'groceries': ExpenseCategoryColors.groceries,
      'coffee': ExpenseCategoryColors.coffee,
      'transport': ExpenseCategoryColors.transport,
      'rideHailing': ExpenseCategoryColors.rideHailing,
      'housing': ExpenseCategoryColors.housing,
      'utilities': ExpenseCategoryColors.utilities,
      'household': ExpenseCategoryColors.household,
      'shopping': ExpenseCategoryColors.shopping,
      'subscriptions': ExpenseCategoryColors.subscriptions,
      'entertainment': ExpenseCategoryColors.entertainment,
      'medical': ExpenseCategoryColors.medical,
      'fitness': ExpenseCategoryColors.fitness,
      'education': ExpenseCategoryColors.education,
      'travel': ExpenseCategoryColors.travel,
      'communication': ExpenseCategoryColors.communication,
      'gift': ExpenseCategoryColors.gift,
      'familySupport': ExpenseCategoryColors.familySupport,
      'pets': ExpenseCategoryColors.pets,
      'trading': ExpenseCategoryColors.trading,
      'trading:fee': ExpenseCategoryColors.tradingFee,
      'trading:tax': ExpenseCategoryColors.tradingTax,
      'trading:interest': ExpenseCategoryColors.tradingInterest,
      'tax': ExpenseCategoryColors.tax,
      'tax:withholding': ExpenseCategoryColors.taxWithholding,
      'other': ExpenseCategoryColors.other,
    };

    test('every seed path hex matches its design-system token', () {
      expect(
        kExpenseCategorySeedHexByPath.keys.toSet(),
        pathTokens.keys.toSet(),
        reason: 'path sets drifted — update both tables and this test',
      );
      for (final entry in kExpenseCategorySeedHexByPath.entries) {
        expect(
          pathTokens[entry.key],
          parseHex(entry.value),
          reason: 'path "${entry.key}" drifted',
        );
      }
    });

    test('icon-only extras match the seed icon hex map', () {
      // Icon token in kExpenseCategorySeedHexByIcon → design-system token.
      const iconExtras = <String, Color>{
        'fastfood': ExpenseCategoryColors.fastfood,
        'directions_car': ExpenseCategoryColors.car,
        'apartment': ExpenseCategoryColors.apartment,
        'movie': ExpenseCategoryColors.movie,
        'local_hospital': ExpenseCategoryColors.hospital,
        'redeem': ExpenseCategoryColors.redeem,
        'category': ExpenseCategoryColors.category,
      };
      for (final entry in iconExtras.entries) {
        final seedHex = kExpenseCategorySeedHexByIcon[entry.key];
        expect(seedHex, isNotNull, reason: 'icon "${entry.key}" missing');
        expect(
          iconExtras[entry.key],
          parseHex(seedHex!),
          reason: 'icon "${entry.key}" drifted',
        );
      }
    });

    test('pieOther stays aliased to the "other" bucket color', () {
      expect(ExpenseCategoryColors.pieOther, ExpenseCategoryColors.other);
      expect(
        ExpenseCategoryColors.pieOther,
        parseHex(kExpenseCategorySeedHexByPath['other']!),
      );
    });
  });
}
