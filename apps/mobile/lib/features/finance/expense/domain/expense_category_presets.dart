import 'expense_category_seed_colors.dart';

class ExpenseCategoryPreset {
  const ExpenseCategoryPreset({
    required this.key,
    this.parentKey,
    required this.nameEn,
    required this.nameZh,
    required this.icon,
    required this.color,
  });

  final String key;
  final String? parentKey;
  final String nameEn;
  final String nameZh;
  final String icon;
  final String color;
}

/// Built-in category tree. This is the only seed-shape SSOT used by category
/// persistence and the hidden ledger-account bridge.
const List<ExpenseCategoryPreset> kExpenseCategoryPresets = [
  ExpenseCategoryPreset(
    key: 'dining',
    nameEn: 'Dining',
    nameZh: '餐饮',
    icon: 'restaurant',
    color: kExpenseColorDining,
  ),
  ExpenseCategoryPreset(
    key: 'groceries',
    nameEn: 'Groceries',
    nameZh: '生鲜日用',
    icon: 'local_grocery_store',
    color: kExpenseColorGroceries,
  ),
  ExpenseCategoryPreset(
    key: 'coffee',
    nameEn: 'Coffee',
    nameZh: '咖啡',
    icon: 'local_cafe',
    color: kExpenseColorCoffee,
  ),
  ExpenseCategoryPreset(
    key: 'transport',
    nameEn: 'Transport',
    nameZh: '公共交通',
    icon: 'directions_bus',
    color: kExpenseColorTransport,
  ),
  ExpenseCategoryPreset(
    key: 'rideHailing',
    nameEn: 'Ride Hailing',
    nameZh: '打车',
    icon: 'local_taxi',
    color: kExpenseColorRideHailing,
  ),
  ExpenseCategoryPreset(
    key: 'housing',
    nameEn: 'Housing',
    nameZh: '住房',
    icon: 'home',
    color: kExpenseColorHousing,
  ),
  ExpenseCategoryPreset(
    key: 'utilities',
    nameEn: 'Utilities',
    nameZh: '水电燃气',
    icon: 'bolt',
    color: kExpenseColorUtilities,
  ),
  ExpenseCategoryPreset(
    key: 'household',
    nameEn: 'Household',
    nameZh: '家居日用',
    icon: 'chair',
    color: kExpenseColorHousehold,
  ),
  ExpenseCategoryPreset(
    key: 'shopping',
    nameEn: 'Shopping',
    nameZh: '购物',
    icon: 'shopping_bag',
    color: kExpenseColorShopping,
  ),
  ExpenseCategoryPreset(
    key: 'subscriptions',
    nameEn: 'Subscriptions',
    nameZh: '订阅',
    icon: 'credit_card',
    color: kExpenseColorSubscriptions,
  ),
  ExpenseCategoryPreset(
    key: 'entertainment',
    nameEn: 'Entertainment',
    nameZh: '娱乐',
    icon: 'sports_esports',
    color: kExpenseColorEntertainment,
  ),
  ExpenseCategoryPreset(
    key: 'medical',
    nameEn: 'Medical',
    nameZh: '医疗',
    icon: 'medical_services',
    color: kExpenseColorMedical,
  ),
  ExpenseCategoryPreset(
    key: 'fitness',
    nameEn: 'Fitness',
    nameZh: '运动健身',
    icon: 'fitness_center',
    color: kExpenseColorFitness,
  ),
  ExpenseCategoryPreset(
    key: 'education',
    nameEn: 'Education',
    nameZh: '教育',
    icon: 'school',
    color: kExpenseColorEducation,
  ),
  ExpenseCategoryPreset(
    key: 'travel',
    nameEn: 'Travel',
    nameZh: '旅行',
    icon: 'flight',
    color: kExpenseColorTravel,
  ),
  ExpenseCategoryPreset(
    key: 'communication',
    nameEn: 'Communication',
    nameZh: '通讯',
    icon: 'smartphone',
    color: kExpenseColorCommunication,
  ),
  ExpenseCategoryPreset(
    key: 'gift',
    nameEn: 'Gift',
    nameZh: '礼物',
    icon: 'card_giftcard',
    color: kExpenseColorGift,
  ),
  ExpenseCategoryPreset(
    key: 'familySupport',
    nameEn: 'Family Support',
    nameZh: '家庭支持',
    icon: 'redeem',
    color: kExpenseColorFamilySupport,
  ),
  ExpenseCategoryPreset(
    key: 'pets',
    nameEn: 'Pets',
    nameZh: '宠物',
    icon: 'pets',
    color: kExpenseColorPets,
  ),
  ExpenseCategoryPreset(
    key: 'trading',
    nameEn: 'Trading',
    nameZh: '交易',
    icon: 'show_chart',
    color: kExpenseColorTrading,
  ),
  ExpenseCategoryPreset(
    key: 'trading:fee',
    parentKey: 'trading',
    nameEn: 'Trading Fee',
    nameZh: '手续费',
    icon: 'receipt_long',
    color: kExpenseColorTradingFee,
  ),
  ExpenseCategoryPreset(
    key: 'trading:tax',
    parentKey: 'trading',
    nameEn: 'Trading Tax',
    nameZh: '交易税费',
    icon: 'request_quote',
    color: kExpenseColorTradingTax,
  ),
  ExpenseCategoryPreset(
    key: 'trading:interest',
    parentKey: 'trading',
    nameEn: 'Trading Interest',
    nameZh: '融资利息',
    icon: 'credit_card',
    color: kExpenseColorTradingInterest,
  ),
  ExpenseCategoryPreset(
    key: 'tax',
    nameEn: 'Tax',
    nameZh: '税务',
    icon: 'request_quote',
    color: kExpenseColorTax,
  ),
  ExpenseCategoryPreset(
    key: 'tax:withholding',
    parentKey: 'tax',
    nameEn: 'Withholding Tax',
    nameZh: '预扣税',
    icon: 'request_quote',
    color: kExpenseColorTaxWithholding,
  ),
  ExpenseCategoryPreset(
    key: 'other',
    nameEn: 'Other Expense',
    nameZh: '其他支出',
    icon: 'more_horiz',
    color: kExpenseColorOther,
  ),
];

ExpenseCategoryPreset? expenseCategoryPresetByKey(String key) {
  for (final preset in kExpenseCategoryPresets) {
    if (preset.key == key) return preset;
  }
  return null;
}
