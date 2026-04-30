import 'package:flutter/material.dart';

import '../../../data/domain/expense_category.dart';

/// FIR-69 — UI-side visual lookup for [ExpenseCategory].
///
/// The category row stores `icon` (a string token) and `color` (a hex
/// string) so they ride through sync as plain text. This helper resolves
/// those tokens to Material icons / `Color`s for the picker, list, and
/// management screens. Lives in `features/expense/ui` (not on the domain
/// entity) so the data layer doesn't pull in `flutter/material.dart`.
const Map<String, IconData> kExpenseCategoryIcons = <String, IconData>{
  'restaurant': Icons.restaurant,
  'directions_car': Icons.directions_car,
  'home': Icons.home,
  'apartment': Icons.apartment,
  'chair': Icons.chair,
  'sports_esports': Icons.sports_esports,
  'medical_services': Icons.medical_services,
  'local_hospital': Icons.local_hospital,
  'school': Icons.school,
  'shopping_bag': Icons.shopping_bag,
  'flight': Icons.flight,
  'phone_android': Icons.phone_android,
  'smartphone': Icons.smartphone,
  'card_giftcard': Icons.card_giftcard,
  'local_cafe': Icons.local_cafe,
  'local_grocery_store': Icons.local_grocery_store,
  'pets': Icons.pets,
  'fitness_center': Icons.fitness_center,
  'category': Icons.category,
  'more_horiz': Icons.more_horiz,
};

/// Fallback glyph for unknown / missing icon tokens. Keeps the picker from
/// rendering an invisible tile when a sync peer ships an icon name we
/// don't know about yet.
const IconData kExpenseCategoryFallbackIcon = Icons.local_offer_outlined;

extension ExpenseCategoryVisuals on ExpenseCategory {
  /// Material icon resolved from [icon]. Falls back to a generic glyph so
  /// the picker never shows a missing-icon hole.
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
}
