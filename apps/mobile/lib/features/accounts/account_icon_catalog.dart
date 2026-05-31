import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import '../../design_system/design_system.dart';

/// FIR-131 wave 3b — curated catalogue mapping the icon-name strings
/// stored in [Account.icon] to a concrete [IconData] the picker / list
/// rows can render.
///
/// We keep the set deliberately small (a few dozen entries) so the icon
/// picker stays scannable and the codebase doesn't bloat with the full
/// icon font reference. The names are exactly the ones used by the
/// FIR-133 seeded default tree, plus a handful of common expense /
/// income / banking flavours so user-created accounts have a reasonable
/// picker grid.
///
/// Storage convention: [Account.icon] holds the *string* name (e.g.
/// `restaurant`); [resolveAccountIcon] is the only translation point
/// from string to [IconData]. Keeping the persisted form a string keeps
/// us robust against future icon-set renames and lets sync ship the
/// column verbatim — peers on older app versions just fall back to the
/// bullet glyph for unknown names.

/// Ordered list driving the picker grid. Order matters because users
/// scan left-to-right; we group banking / income / food / transit /
/// housing / trading / generic so the picker reads as a small taxonomy
/// rather than a random pile.
const List<AccountIconChoice> kAccountIconCatalogue = [
  // Banking / cash
  AccountIconChoice('account_balance', FLucideIcons.landmark),
  AccountIconChoice('account_balance_wallet', FLucideIcons.wallet),
  AccountIconChoice('savings', FLucideIcons.piggyBank),
  AccountIconChoice('credit_card', FLucideIcons.creditCard),
  AccountIconChoice('payments', FLucideIcons.banknote),

  // Income
  AccountIconChoice('work', FLucideIcons.briefcase),
  AccountIconChoice('paid', FLucideIcons.circleDollarSign),
  AccountIconChoice('trending_up', FLucideIcons.trendingUp),
  AccountIconChoice('south_west', FLucideIcons.arrowDownLeft),
  AccountIconChoice('north_east', FLucideIcons.arrowUpRight),

  // Food / dining
  AccountIconChoice('restaurant', FLucideIcons.utensils),
  AccountIconChoice('fastfood', FLucideIcons.sandwich),
  AccountIconChoice('local_cafe', FLucideIcons.coffee),
  AccountIconChoice('local_grocery_store', FLucideIcons.shoppingCart),

  // Transit
  AccountIconChoice('directions_bus', FLucideIcons.bus),
  AccountIconChoice('directions_car', FLucideIcons.car),
  AccountIconChoice('flight', FLucideIcons.plane),
  AccountIconChoice('local_taxi', FLucideIcons.carTaxiFront),

  // Housing / utilities
  AccountIconChoice('home', FLucideIcons.house),
  AccountIconChoice('apartment', FLucideIcons.building),
  AccountIconChoice('bolt', FLucideIcons.zap),
  AccountIconChoice('chair', FLucideIcons.armchair),

  // Shopping / lifestyle
  AccountIconChoice('shopping_cart', FLucideIcons.shoppingCart),
  AccountIconChoice('shopping_bag', FLucideIcons.shoppingBag),
  AccountIconChoice('redeem', FLucideIcons.gift),
  AccountIconChoice('card_giftcard', FLucideIcons.gift),

  // Health / leisure
  AccountIconChoice('medical_services', FLucideIcons.briefcaseMedical),
  AccountIconChoice('fitness_center', FLucideIcons.dumbbell),
  AccountIconChoice('pets', FLucideIcons.pawPrint),
  AccountIconChoice('movie', FLucideIcons.film),
  AccountIconChoice('sports_esports', FLucideIcons.gamepad2),

  // Education / communication
  AccountIconChoice('school', FLucideIcons.graduationCap),
  AccountIconChoice('smartphone', FLucideIcons.smartphone),

  // Trading / equity
  AccountIconChoice('show_chart', FLucideIcons.chartLine),
  AccountIconChoice('receipt_long', FLucideIcons.receipt),
  AccountIconChoice('request_quote', FLucideIcons.fileText),
  AccountIconChoice('call_split', FLucideIcons.gitBranch),

  // Generic / misc
  AccountIconChoice('flag', FLucideIcons.flag),
  AccountIconChoice('tune', FLucideIcons.slidersHorizontal),
  AccountIconChoice('more_horiz', FLucideIcons.ellipsis),
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
/// chain `?? FLucideIcons.circle`; the picker / list rows prefer `null`
/// so they fall back to the same bullet glyph the picker uses for
/// accounts without an icon at all.
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
