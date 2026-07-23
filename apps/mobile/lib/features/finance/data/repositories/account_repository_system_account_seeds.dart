part of 'account_repository.dart';

/// Specification for one seeded system account. Expense rows are derived from
/// [kExpenseCategoryPresets], the user-facing taxonomy SSOT.
class _SystemAccountSeed {
  const _SystemAccountSeed({
    required this.path,
    required this.parentPath,
    required this.name,
    required this.category,
    required this.icon,
    required this.color,
  });

  /// Stable path under the user's prefix, e.g. `income`,
  /// `expense:trading`, `expense:trading:fee`. The full id is
  /// `system-account:<userId>:<path>`.
  final String path;

  /// Parent path, or `null` on the three roots. Always one segment
  /// shorter than [path] when set.
  final String? parentPath;

  /// English Beancount-canonical name (e.g. `Salary`, `Trading Fee`).
  /// Roots ignore this and use the localised display name instead.
  final String name;

  final AccountSide category;

  /// Material icon name (e.g. `work`, `restaurant`).
  final String icon;

  /// Hex color used for the avatar tint and categorical charts.
  /// Income leaves share a green family, equity a blue family; each
  /// expense leaf uses a distinct hue from
  /// [kExpenseCategorySeedHexByPath].
  final String color;

  bool get isRoot => parentPath == null;
}

/// Default account tree seeded on a fresh install. Iterated in parent-
/// before-child order so `seedSystemAccounts` can rely on the parent already
/// existing for the audit-log capture (the SQL layer doesn't enforce a foreign
/// key, so this is a soft contract).
final List<_SystemAccountSeed> _kSystemAccountTreeSeeds = [
  // ---- Roots ----
  const _SystemAccountSeed(
    path: 'income',
    parentPath: null,
    name: 'Income',
    category: AccountSide.income,
    icon: 'south_west',
    color: '#10B981',
  ),
  const _SystemAccountSeed(
    path: 'expense',
    parentPath: null,
    name: 'Expenses',
    category: AccountSide.expense,
    icon: 'north_east',
    color: '#EF4444',
  ),
  const _SystemAccountSeed(
    path: 'equity',
    parentPath: null,
    name: 'Equity',
    category: AccountSide.equity,
    icon: 'account_balance',
    color: '#3B82F6',
  ),

  // ---- Income leaves ----
  const _SystemAccountSeed(
    path: 'income:salary',
    parentPath: 'income',
    name: 'Salary',
    category: AccountSide.income,
    icon: 'work',
    color: '#10B981',
  ),
  const _SystemAccountSeed(
    path: 'income:dividend',
    parentPath: 'income',
    name: 'Dividend',
    category: AccountSide.income,
    icon: 'paid',
    color: '#10B981',
  ),
  const _SystemAccountSeed(
    path: 'income:interest',
    parentPath: 'income',
    name: 'Interest',
    category: AccountSide.income,
    icon: 'savings',
    color: '#10B981',
  ),
  const _SystemAccountSeed(
    path: 'income:capitalGains',
    parentPath: 'income',
    name: 'Capital Gains',
    category: AccountSide.income,
    icon: 'trending_up',
    color: '#10B981',
  ),
  const _SystemAccountSeed(
    path: 'income:options',
    parentPath: 'income',
    name: 'Options Income',
    category: AccountSide.income,
    icon: 'show_chart',
    color: '#10B981',
  ),
  const _SystemAccountSeed(
    path: 'income:other',
    parentPath: 'income',
    name: 'Other Income',
    category: AccountSide.income,
    icon: 'more_horiz',
    color: '#10B981',
  ),

  // ---- Expense categories ----
  // The user-facing category presets are the SSOT. Ledger accounts are only
  // hidden posting targets derived from that taxonomy.
  for (final preset in kExpenseCategoryPresets)
    _SystemAccountSeed(
      path: 'expense:${preset.key}',
      parentPath: preset.parentKey == null
          ? 'expense'
          : 'expense:${preset.parentKey}',
      name: preset.nameEn,
      category: AccountSide.expense,
      icon: preset.icon,
      color: preset.color,
    ),

  // ---- Equity leaves ----
  const _SystemAccountSeed(
    path: 'equity:openingBalance',
    parentPath: 'equity',
    name: 'Opening Balance',
    category: AccountSide.equity,
    icon: 'flag',
    color: '#3B82F6',
  ),
  const _SystemAccountSeed(
    path: 'equity:splits',
    parentPath: 'equity',
    name: 'Stock Splits',
    category: AccountSide.equity,
    icon: 'call_split',
    color: '#3B82F6',
  ),
  const _SystemAccountSeed(
    path: 'equity:adjustments',
    parentPath: 'equity',
    name: 'Adjustments',
    category: AccountSide.equity,
    icon: 'tune',
    color: '#3B82F6',
  ),
];
