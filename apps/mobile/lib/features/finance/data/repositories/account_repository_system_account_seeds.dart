part of 'account_repository.dart';

/// Specification for one seeded system account. Static const so the seed
/// is the single source of truth for the default tree shape, picker
/// defaults and the Beancount export naming convention.
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
const List<_SystemAccountSeed> _kSystemAccountTreeSeeds = [
  // ---- Roots ----
  _SystemAccountSeed(
    path: 'income',
    parentPath: null,
    name: 'Income',
    category: AccountSide.income,
    icon: 'south_west',
    color: '#10B981',
  ),
  _SystemAccountSeed(
    path: 'expense',
    parentPath: null,
    name: 'Expenses',
    category: AccountSide.expense,
    icon: 'north_east',
    color: '#EF4444',
  ),
  _SystemAccountSeed(
    path: 'equity',
    parentPath: null,
    name: 'Equity',
    category: AccountSide.equity,
    icon: 'account_balance',
    color: '#3B82F6',
  ),

  // ---- Income leaves ----
  _SystemAccountSeed(
    path: 'income:salary',
    parentPath: 'income',
    name: 'Salary',
    category: AccountSide.income,
    icon: 'work',
    color: '#10B981',
  ),
  _SystemAccountSeed(
    path: 'income:dividend',
    parentPath: 'income',
    name: 'Dividend',
    category: AccountSide.income,
    icon: 'paid',
    color: '#10B981',
  ),
  _SystemAccountSeed(
    path: 'income:interest',
    parentPath: 'income',
    name: 'Interest',
    category: AccountSide.income,
    icon: 'savings',
    color: '#10B981',
  ),
  _SystemAccountSeed(
    path: 'income:capitalGains',
    parentPath: 'income',
    name: 'Capital Gains',
    category: AccountSide.income,
    icon: 'trending_up',
    color: '#10B981',
  ),
  _SystemAccountSeed(
    path: 'income:options',
    parentPath: 'income',
    name: 'Options Income',
    category: AccountSide.income,
    icon: 'show_chart',
    color: '#10B981',
  ),
  _SystemAccountSeed(
    path: 'income:other',
    parentPath: 'income',
    name: 'Other Income',
    category: AccountSide.income,
    icon: 'more_horiz',
    color: '#10B981',
  ),

  // ---- Everyday expense leaves + Trading / Tax branches ----
  // Colours come from kExpenseCategorySeedHexByPath — one distinct hue
  // per leaf so list avatars and the report pie share the same palette.
  _SystemAccountSeed(
    path: 'expense:dining',
    parentPath: 'expense',
    name: 'Dining',
    category: AccountSide.expense,
    icon: 'restaurant',
    color: kExpenseColorDining,
  ),
  _SystemAccountSeed(
    path: 'expense:groceries',
    parentPath: 'expense',
    name: 'Groceries',
    category: AccountSide.expense,
    icon: 'local_grocery_store',
    color: kExpenseColorGroceries,
  ),
  _SystemAccountSeed(
    path: 'expense:coffee',
    parentPath: 'expense',
    name: 'Coffee',
    category: AccountSide.expense,
    icon: 'local_cafe',
    color: kExpenseColorCoffee,
  ),
  _SystemAccountSeed(
    path: 'expense:transport',
    parentPath: 'expense',
    name: 'Transport',
    category: AccountSide.expense,
    icon: 'directions_bus',
    color: kExpenseColorTransport,
  ),
  _SystemAccountSeed(
    path: 'expense:rideHailing',
    parentPath: 'expense',
    name: 'Ride Hailing',
    category: AccountSide.expense,
    icon: 'local_taxi',
    color: kExpenseColorRideHailing,
  ),
  _SystemAccountSeed(
    path: 'expense:housing',
    parentPath: 'expense',
    name: 'Housing',
    category: AccountSide.expense,
    icon: 'home',
    color: kExpenseColorHousing,
  ),
  _SystemAccountSeed(
    path: 'expense:utilities',
    parentPath: 'expense',
    name: 'Utilities',
    category: AccountSide.expense,
    icon: 'bolt',
    color: kExpenseColorUtilities,
  ),
  _SystemAccountSeed(
    path: 'expense:household',
    parentPath: 'expense',
    name: 'Household',
    category: AccountSide.expense,
    icon: 'chair',
    color: kExpenseColorHousehold,
  ),
  _SystemAccountSeed(
    path: 'expense:shopping',
    parentPath: 'expense',
    name: 'Shopping',
    category: AccountSide.expense,
    icon: 'shopping_bag',
    color: kExpenseColorShopping,
  ),
  _SystemAccountSeed(
    path: 'expense:subscriptions',
    parentPath: 'expense',
    name: 'Subscriptions',
    category: AccountSide.expense,
    icon: 'credit_card',
    color: kExpenseColorSubscriptions,
  ),
  _SystemAccountSeed(
    path: 'expense:entertainment',
    parentPath: 'expense',
    name: 'Entertainment',
    category: AccountSide.expense,
    icon: 'sports_esports',
    color: kExpenseColorEntertainment,
  ),
  _SystemAccountSeed(
    path: 'expense:medical',
    parentPath: 'expense',
    name: 'Medical',
    category: AccountSide.expense,
    icon: 'medical_services',
    color: kExpenseColorMedical,
  ),
  _SystemAccountSeed(
    path: 'expense:fitness',
    parentPath: 'expense',
    name: 'Fitness',
    category: AccountSide.expense,
    icon: 'fitness_center',
    color: kExpenseColorFitness,
  ),
  _SystemAccountSeed(
    path: 'expense:education',
    parentPath: 'expense',
    name: 'Education',
    category: AccountSide.expense,
    icon: 'school',
    color: kExpenseColorEducation,
  ),
  _SystemAccountSeed(
    path: 'expense:travel',
    parentPath: 'expense',
    name: 'Travel',
    category: AccountSide.expense,
    icon: 'flight',
    color: kExpenseColorTravel,
  ),
  _SystemAccountSeed(
    path: 'expense:communication',
    parentPath: 'expense',
    name: 'Communication',
    category: AccountSide.expense,
    icon: 'smartphone',
    color: kExpenseColorCommunication,
  ),
  _SystemAccountSeed(
    path: 'expense:gift',
    parentPath: 'expense',
    name: 'Gift',
    category: AccountSide.expense,
    icon: 'card_giftcard',
    color: kExpenseColorGift,
  ),
  _SystemAccountSeed(
    path: 'expense:familySupport',
    parentPath: 'expense',
    name: 'Family Support',
    category: AccountSide.expense,
    icon: 'redeem',
    color: kExpenseColorFamilySupport,
  ),
  _SystemAccountSeed(
    path: 'expense:pets',
    parentPath: 'expense',
    name: 'Pets',
    category: AccountSide.expense,
    icon: 'pets',
    color: kExpenseColorPets,
  ),
  _SystemAccountSeed(
    path: 'expense:trading',
    parentPath: 'expense',
    name: 'Trading',
    category: AccountSide.expense,
    icon: 'show_chart',
    color: kExpenseColorTrading,
  ),
  _SystemAccountSeed(
    path: 'expense:trading:fee',
    parentPath: 'expense:trading',
    name: 'Trading Fee',
    category: AccountSide.expense,
    icon: 'receipt_long',
    color: kExpenseColorTradingFee,
  ),
  _SystemAccountSeed(
    path: 'expense:trading:tax',
    parentPath: 'expense:trading',
    name: 'Trading Tax',
    category: AccountSide.expense,
    icon: 'request_quote',
    color: kExpenseColorTradingTax,
  ),
  _SystemAccountSeed(
    path: 'expense:trading:interest',
    parentPath: 'expense:trading',
    name: 'Trading Interest',
    category: AccountSide.expense,
    icon: 'credit_card',
    color: kExpenseColorTradingInterest,
  ),
  _SystemAccountSeed(
    path: 'expense:tax',
    parentPath: 'expense',
    name: 'Tax',
    category: AccountSide.expense,
    icon: 'request_quote',
    color: kExpenseColorTax,
  ),
  _SystemAccountSeed(
    path: 'expense:tax:withholding',
    parentPath: 'expense:tax',
    name: 'Withholding Tax',
    category: AccountSide.expense,
    icon: 'request_quote',
    color: kExpenseColorTaxWithholding,
  ),
  _SystemAccountSeed(
    path: 'expense:other',
    parentPath: 'expense',
    name: 'Other Expense',
    category: AccountSide.expense,
    icon: 'more_horiz',
    color: kExpenseColorOther,
  ),

  // ---- Equity leaves ----
  _SystemAccountSeed(
    path: 'equity:openingBalance',
    parentPath: 'equity',
    name: 'Opening Balance',
    category: AccountSide.equity,
    icon: 'flag',
    color: '#3B82F6',
  ),
  _SystemAccountSeed(
    path: 'equity:splits',
    parentPath: 'equity',
    name: 'Stock Splits',
    category: AccountSide.equity,
    icon: 'call_split',
    color: '#3B82F6',
  ),
  _SystemAccountSeed(
    path: 'equity:adjustments',
    parentPath: 'equity',
    name: 'Adjustments',
    category: AccountSide.equity,
    icon: 'tune',
    color: '#3B82F6',
  ),
];
