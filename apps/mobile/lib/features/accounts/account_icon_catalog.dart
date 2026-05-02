import 'package:flutter/material.dart';

/// FIR-131 wave 3b — curated catalogue mapping the icon-name strings
/// stored in [Account.icon] to a concrete [IconData] the picker / list
/// rows can render.
///
/// We keep the set deliberately small (a few dozen entries) so the icon
/// picker stays scannable and the codebase doesn't bloat with the full
/// Material Icons font reference. The names are exactly the ones used
/// by the FIR-133 seeded default tree, plus a handful of common
/// expense / income / banking flavours so user-created accounts have a
/// reasonable picker grid.
///
/// Storage convention: [Account.icon] holds the *string* name (e.g.
/// `restaurant`); [resolveAccountIcon] is the only translation point
/// from string to [IconData]. Keeping the persisted form a string keeps
/// us robust against future Material icon renames and lets sync ship
/// the column verbatim — peers on older app versions just fall back to
/// the bullet glyph for unknown names.

/// Ordered list driving the picker grid. Order matters because users
/// scan left-to-right; we group banking / income / food / transit /
/// housing / trading / generic so the picker reads as a small taxonomy
/// rather than a random pile.
const List<AccountIconChoice> kAccountIconCatalogue = [
  // Banking / cash
  AccountIconChoice('account_balance', Icons.account_balance),
  AccountIconChoice('account_balance_wallet', Icons.account_balance_wallet),
  AccountIconChoice('savings', Icons.savings),
  AccountIconChoice('credit_card', Icons.credit_card),
  AccountIconChoice('payments', Icons.payments),

  // Income
  AccountIconChoice('work', Icons.work),
  AccountIconChoice('paid', Icons.paid),
  AccountIconChoice('trending_up', Icons.trending_up),
  AccountIconChoice('south_west', Icons.south_west),
  AccountIconChoice('north_east', Icons.north_east),

  // Food / dining
  AccountIconChoice('restaurant', Icons.restaurant),
  AccountIconChoice('fastfood', Icons.fastfood),
  AccountIconChoice('local_cafe', Icons.local_cafe),
  AccountIconChoice('local_grocery_store', Icons.local_grocery_store),

  // Transit
  AccountIconChoice('directions_bus', Icons.directions_bus),
  AccountIconChoice('directions_car', Icons.directions_car),
  AccountIconChoice('flight', Icons.flight),
  AccountIconChoice('local_taxi', Icons.local_taxi),

  // Housing / utilities
  AccountIconChoice('home', Icons.home),
  AccountIconChoice('apartment', Icons.apartment),
  AccountIconChoice('bolt', Icons.bolt),

  // Shopping / lifestyle
  AccountIconChoice('shopping_cart', Icons.shopping_cart),
  AccountIconChoice('shopping_bag', Icons.shopping_bag),
  AccountIconChoice('redeem', Icons.redeem),

  // Health / leisure
  AccountIconChoice('medical_services', Icons.medical_services),
  AccountIconChoice('fitness_center', Icons.fitness_center),
  AccountIconChoice('movie', Icons.movie),

  // Trading / equity
  AccountIconChoice('show_chart', Icons.show_chart),
  AccountIconChoice('receipt_long', Icons.receipt_long),
  AccountIconChoice('request_quote', Icons.request_quote),
  AccountIconChoice('call_split', Icons.call_split),

  // Generic / misc
  AccountIconChoice('flag', Icons.flag_outlined),
  AccountIconChoice('tune', Icons.tune),
  AccountIconChoice('more_horiz', Icons.more_horiz),
];

/// Single entry in the catalogue: `(name, IconData)`.
class AccountIconChoice {
  const AccountIconChoice(this.name, this.icon);

  /// Stable string stored in [Account.icon].
  final String name;

  /// Concrete icon to render.
  final IconData icon;
}

/// Index built once from the catalogue list; [resolveAccountIcon] uses
/// it for an O(1) lookup. Public so tests can assert that every seeded
/// icon name has a catalogue entry.
final Map<String, IconData> kAccountIconByName = <String, IconData>{
  for (final c in kAccountIconCatalogue) c.name: c.icon,
};

/// Resolves a stored [name] to its [IconData], or `null` when the name
/// isn't in the catalogue. Callers that want a guaranteed fallback can
/// chain `?? Icons.circle_outlined`; the picker / list rows prefer
/// `null` so they fall back to the same bullet glyph the picker uses
/// for accounts without an icon at all.
IconData? resolveAccountIcon(String? name) {
  if (name == null || name.isEmpty) return null;
  return kAccountIconByName[name];
}

/// Default colour palette offered by the colour picker. Hex strings to
/// match the storage shape of [Account.color]. Picked to read clearly
/// against both light and dark surfaces; the row also includes a
/// "no colour" sentinel via the explicit `null` cleared state in the
/// picker.
const List<String> kAccountColorPalette = [
  '#10B981', // emerald — Income
  '#3B82F6', // blue — Equity / banking
  '#EF4444', // red — Expense
  '#F59E0B', // amber — Trading / liability accent
  '#8B5CF6', // violet — Investments
  '#EC4899', // pink — Lifestyle
  '#14B8A6', // teal — Savings
  '#6B7280', // slate — Generic
];
