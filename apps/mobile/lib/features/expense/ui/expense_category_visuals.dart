import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';

import '../../../design_system/design_system.dart';

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

const Color _kDefaultExpenseSeedAccent = Color(0xFFEF4444);

const Map<String, Color> _kExpenseCategoryAccentByIcon = <String, Color>{
  'restaurant': Color(0xFFF97316),
  'fastfood': Color(0xFFF97316),
  'local_cafe': Color(0xFFD97706),
  'local_grocery_store': Color(0xFF65A30D),
  'directions_car': Color(0xFF0EA5E9),
  'directions_bus': Color(0xFF0EA5E9),
  'local_taxi': Color(0xFF0284C7),
  'home': Color(0xFF6366F1),
  'apartment': Color(0xFF64748B),
  'bolt': Color(0xFFEAB308),
  'chair': Color(0xFF14B8A6),
  'sports_esports': Color(0xFFA855F7),
  'movie': Color(0xFFA855F7),
  'medical_services': Color(0xFFEF4444),
  'local_hospital': Color(0xFFDC2626),
  'school': Color(0xFF059669),
  'shopping_bag': Color(0xFFEC4899),
  'shopping_cart': Color(0xFF65A30D),
  'flight': Color(0xFF2563EB),
  'phone_android': Color(0xFF475569),
  'smartphone': Color(0xFF475569),
  'card_giftcard': Color(0xFFF59E0B),
  'redeem': Color(0xFFF59E0B),
  'pets': Color(0xFF8B5CF6),
  'fitness_center': Color(0xFF10B981),
  'show_chart': Color(0xFF1F6FEB),
  'receipt_long': Color(0xFF6B7280),
  'request_quote': Color(0xFFBE123C),
  'credit_card': Color(0xFF475569),
  'category': Color(0xFF0891B2),
  'more_horiz': Color(0xFF6B7280),
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
    final raw = color;
    if (raw == null || raw.isEmpty) return null;
    final hex = raw.startsWith('#') ? raw.substring(1) : raw;
    if (hex.length != 6 && hex.length != 8) return null;
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return null;
    return Color(hex.length == 6 ? 0xFF000000 | v : v);
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
