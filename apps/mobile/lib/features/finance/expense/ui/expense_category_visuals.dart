import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/shared/account_color.dart';

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

const Color _kDefaultExpenseSeedAccent = ExpenseCategoryColors.red;

const Map<String, Color> _kExpenseCategoryAccentByIcon = <String, Color>{
  'restaurant': ExpenseCategoryColors.orange,
  'fastfood': ExpenseCategoryColors.orange,
  'local_cafe': ExpenseCategoryColors.amber,
  'local_grocery_store': ExpenseCategoryColors.lime,
  'directions_car': ExpenseCategoryColors.sky,
  'directions_bus': ExpenseCategoryColors.sky,
  'local_taxi': ExpenseCategoryColors.skyDark,
  'home': ExpenseCategoryColors.indigo,
  'apartment': ExpenseCategoryColors.slate,
  'bolt': ExpenseCategoryColors.yellow,
  'chair': ExpenseCategoryColors.cyanBrand,
  'sports_esports': ExpenseCategoryColors.purple,
  'movie': ExpenseCategoryColors.purple,
  'medical_services': ExpenseCategoryColors.red,
  'local_hospital': ExpenseCategoryColors.rose,
  'school': ExpenseCategoryColors.emerald,
  'shopping_bag': ExpenseCategoryColors.pink,
  'shopping_cart': ExpenseCategoryColors.lime,
  'flight': ExpenseCategoryColors.blue,
  'phone_android': ExpenseCategoryColors.slateDark,
  'smartphone': ExpenseCategoryColors.slateDark,
  'card_giftcard': ExpenseCategoryColors.amberLight,
  'redeem': ExpenseCategoryColors.amberLight,
  'pets': ExpenseCategoryColors.violet,
  'fitness_center': ExpenseCategoryColors.emeraldLight,
  'show_chart': ExpenseCategoryColors.blue,
  'receipt_long': ExpenseCategoryColors.gray,
  'request_quote': ExpenseCategoryColors.rose,
  'credit_card': ExpenseCategoryColors.slateDark,
  'category': ExpenseCategoryColors.cyan,
  'more_horiz': ExpenseCategoryColors.gray,
};

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

  /// Display accent for expense surfaces.
  ///
  /// System expense categories were historically seeded with the same red
  /// value, which makes the picker and report read as one flat block. Treat
  /// that seed as a domain default and resolve a softer category-specific
  /// accent by icon; user-picked colours still win.
  Color expenseAccentColor(BuildContext context, {int ordinal = 0}) {
    final stored = accentColor;
    final base = stored == null || _isDefaultExpenseSeedAccent(stored)
        ? _kExpenseCategoryAccentByIcon[icon] ??
              ChartPalette.of(context).accentAt(ordinal)
        : stored;
    return _harmonizeExpenseAccent(context, base);
  }
}

bool _isDefaultExpenseSeedAccent(Color color) {
  return (color.r * 255).round() ==
          (_kDefaultExpenseSeedAccent.r * 255).round() &&
      (color.g * 255).round() == (_kDefaultExpenseSeedAccent.g * 255).round() &&
      (color.b * 255).round() == (_kDefaultExpenseSeedAccent.b * 255).round();
}

Color _harmonizeExpenseAccent(BuildContext context, Color color) {
  final colors = context.theme.colors;
  final isDark = colors.brightness == Brightness.dark;
  final anchor = isDark ? colors.foreground : colors.primary;
  return Color.lerp(color, anchor, isDark ? 0.04 : 0.07) ?? color;
}
