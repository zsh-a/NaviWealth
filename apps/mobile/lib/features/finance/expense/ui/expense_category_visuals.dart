import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/shared/ui/account_color.dart';

import '../domain/expense_category_seed_colors.dart';
import '../domain/expense_report.dart';
import '../domain/expense_report_pie.dart';

/// UI-side visual lookup for expense [Account]s.
///
/// The account row stores `icon` (a string token) and `color` (a hex
/// string) so they ride through sync as plain text. This helper resolves
/// those tokens to Lucide icons (via Forui's `FLucideIcons`) and `Color`s
/// for the picker, list, and report screens. The token strings are the
/// stable wire format; the IconData they resolve to may evolve as the
/// design system swaps icon sets.
const Map<String, IconData> kExpenseCategoryIcons = <String, IconData>{
  'restaurant': FLucideIcons.utensils,
  'fastfood': FLucideIcons.sandwich,
  'directions_car': FLucideIcons.car,
  'directions_bus': FLucideIcons.bus,
  'local_taxi': FLucideIcons.carTaxiFront,
  'home': FLucideIcons.house,
  'apartment': FLucideIcons.building,
  'bolt': FLucideIcons.zap,
  'chair': FLucideIcons.armchair,
  'sports_esports': FLucideIcons.gamepad2,
  'movie': FLucideIcons.film,
  'medical_services': FLucideIcons.briefcaseMedical,
  'local_hospital': FLucideIcons.hospital,
  'school': FLucideIcons.school,
  'shopping_bag': FLucideIcons.shoppingBag,
  'shopping_cart': FLucideIcons.shoppingCart,
  'flight': FLucideIcons.plane,
  'phone_android': FLucideIcons.smartphone,
  'smartphone': FLucideIcons.smartphone,
  'card_giftcard': FLucideIcons.gift,
  'redeem': FLucideIcons.gift,
  'local_cafe': FLucideIcons.coffee,
  'local_grocery_store': FLucideIcons.shoppingCart,
  'pets': FLucideIcons.pawPrint,
  'fitness_center': FLucideIcons.dumbbell,
  'show_chart': FLucideIcons.chartLine,
  'receipt_long': FLucideIcons.receipt,
  'request_quote': FLucideIcons.fileText,
  'credit_card': FLucideIcons.creditCard,
  'category': FLucideIcons.layoutGrid,
  'more_horiz': FLucideIcons.ellipsis,
};

/// Fallback glyph for unknown / missing icon tokens.
const IconData kExpenseCategoryFallbackIcon = FLucideIcons.tag;

extension ExpenseAccountVisuals on Account {
  /// Icon resolved from [icon]. Falls back to a generic glyph so the
  /// picker never shows a missing-icon hole.
  IconData get iconData =>
      kExpenseCategoryIcons[icon] ?? kExpenseCategoryFallbackIcon;

  /// Tinted accent color derived from [color]. Returns `null` when unset
  /// so the caller can fall back to the theme default. Accepts `#RRGGBB`
  /// or `#AARRGGBB`; an unparseable value returns `null` rather than
  /// surfacing an exception mid-list.
  Color? get accentColor {
    return parseAccountColor(color);
  }

  /// Display accent for expense surfaces (list, picker, report).
  ///
  /// Resolution order (unified):
  /// 1. system path from the account id → [kExpenseCategorySeedHexByPath]
  /// 2. persisted [color]
  /// 3. icon token → [kExpenseCategorySeedHexByIcon]
  /// 4. [ChartPalette.accentAt] for the series ordinal
  Color expenseAccentColor(BuildContext context, {int ordinal = 0}) {
    final pathHex = expenseCategoryHexForAccountId(id);
    if (pathHex != null) {
      final parsed = parseAccountColor(pathHex);
      if (parsed != null) return parsed;
    }

    final stored = accentColor;
    if (stored != null) return stored;

    final iconToken = icon;
    if (iconToken != null) {
      final iconHex = kExpenseCategorySeedHexByIcon[iconToken];
      if (iconHex != null) {
        final parsed = parseAccountColor(iconHex);
        if (parsed != null) return parsed;
      }
    }

    return ChartPalette.of(context).accentAt(ordinal);
  }
}

/// Extracts the `expense:`-relative path from a system account id, e.g.
/// `system-account:u1:expense:dining` → `dining`.
String? expenseCategoryPathFromAccountId(String accountId) {
  const marker = ':expense:';
  final index = accountId.indexOf(marker);
  if (index < 0) return null;
  final path = accountId.substring(index + marker.length);
  return path.isEmpty ? null : path;
}

/// Canonical hex for a system expense account id, if known.
String? expenseCategoryHexForAccountId(String accountId) {
  final path = expenseCategoryPathFromAccountId(accountId);
  if (path == null) return null;
  return kExpenseCategorySeedHexByPath[path];
}

/// Colour for a report category row / pie slice.
Color expenseReportSliceColor(
  BuildContext context, {
  required String expenseAccountId,
  Account? account,
  int ordinal = 0,
}) {
  if (expenseAccountId == kExpenseReportPieOtherId) {
    return ExpenseCategoryColors.pieOther;
  }
  if (account != null) {
    return account.expenseAccentColor(context, ordinal: ordinal);
  }
  final pathHex = expenseCategoryHexForAccountId(expenseAccountId);
  if (pathHex != null) {
    final parsed = parseAccountColor(pathHex);
    if (parsed != null) return parsed;
  }
  return ChartPalette.of(context).accentAt(ordinal);
}

/// One resolved pie slice: breakdown + colour + display label.
typedef ExpenseReportPieSlice = ({
  CategoryBreakdown breakdown,
  Color color,
  String labelKey,
});

/// Builds pie slices for [report], collapsing the long tail and resolving
/// colours once so the donut and legend stay in lockstep.
List<ExpenseReportPieSlice> buildExpenseReportPieSlices(
  BuildContext context, {
  required ExpenseReport report,
  required Map<String, Account> categoryById,
  required String Function(CategoryBreakdown breakdown) labelOf,
}) {
  final collapsed = collapseExpenseCategoriesForPie(report.byCategory);
  return [
    for (var i = 0; i < collapsed.length; i++)
      (
        breakdown: collapsed[i],
        color: expenseReportSliceColor(
          context,
          expenseAccountId: collapsed[i].expenseAccountId,
          account: categoryById[collapsed[i].expenseAccountId],
          ordinal: i,
        ),
        labelKey: labelOf(collapsed[i]),
      ),
  ];
}
