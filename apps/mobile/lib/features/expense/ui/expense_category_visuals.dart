import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/features/finance/data/domain/account.dart';

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
  'directions_car': FLucideIcons.car,
  'home': FLucideIcons.house,
  'apartment': FLucideIcons.building,
  'chair': FLucideIcons.armchair,
  'sports_esports': FLucideIcons.gamepad2,
  'medical_services': FLucideIcons.briefcaseMedical,
  'local_hospital': FLucideIcons.hospital,
  'school': FLucideIcons.school,
  'shopping_bag': FLucideIcons.shoppingBag,
  'flight': FLucideIcons.plane,
  'phone_android': FLucideIcons.smartphone,
  'smartphone': FLucideIcons.smartphone,
  'card_giftcard': FLucideIcons.gift,
  'local_cafe': FLucideIcons.coffee,
  'local_grocery_store': FLucideIcons.shoppingCart,
  'pets': FLucideIcons.pawPrint,
  'fitness_center': FLucideIcons.dumbbell,
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
    final raw = color;
    if (raw == null || raw.isEmpty) return null;
    final hex = raw.startsWith('#') ? raw.substring(1) : raw;
    if (hex.length != 6 && hex.length != 8) return null;
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return null;
    return Color(hex.length == 6 ? 0xFF000000 | v : v);
  }
}
