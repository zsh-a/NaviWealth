/// Canonical expense-category accent colours as `#RRGGBB` strings.
///
/// Single source of truth for:
/// - system account seed `color` columns
/// - runtime icon / path accent resolution
/// - report pie slices and legends
///
/// Values are spaced for categorical distinguishability (wide hue steps,
/// no shared hex across taxonomy leaves). Keep this list aligned with
/// seeded `expense:*` paths.
///
/// `ExpenseCategoryColors` in `design_system/tokens/color_palette.dart`
/// mirrors these values for UI code. Neither side may import the other
/// (features must not import `ColorPalette`; design_system must not depend
/// on features). Parity is enforced by
/// `test/design_system/tokens/expense_category_colors_lockstep_test.dart` —
/// adjust hues on both sides together.
library;

/// Root expense account — family marker, not a pie slice.
const String kExpenseRootSeedHex = '#EF4444';

// ── Path accents (const so seeds can reference them) ─────────────────────
const String kExpenseColorDining = '#EA580C';
const String kExpenseColorGroceries = '#65A30D';
const String kExpenseColorCoffee = '#CA8A04';
const String kExpenseColorTransport = '#0284C7';
const String kExpenseColorRideHailing = '#0F766E';
const String kExpenseColorHousing = '#4F46E5';
const String kExpenseColorUtilities = '#EAB308';
const String kExpenseColorHousehold = '#0891B2';
const String kExpenseColorShopping = '#DB2777';
const String kExpenseColorSubscriptions = '#7C3AED';
const String kExpenseColorEntertainment = '#C026D3';
const String kExpenseColorMedical = '#E11D48';
const String kExpenseColorFitness = '#059669';
const String kExpenseColorEducation = '#2563EB';
const String kExpenseColorTravel = '#1D4ED8';
const String kExpenseColorCommunication = '#0E7490';
const String kExpenseColorGift = '#D97706';
const String kExpenseColorFamilySupport = '#BE123C';
const String kExpenseColorPets = '#9333EA';
const String kExpenseColorTrading = '#334155';
const String kExpenseColorTradingFee = '#64748B';
const String kExpenseColorTradingTax = '#9F1239';
const String kExpenseColorTradingInterest = '#475569';
const String kExpenseColorTax = '#B91C1C';
const String kExpenseColorTaxWithholding = '#881337';
const String kExpenseColorOther = '#6B7280';

// Icon-only extras (custom categories / aliases).
const String kExpenseColorFastfood = '#F97316';
const String kExpenseColorCar = '#0369A1';
const String kExpenseColorApartment = '#6366F1';
const String kExpenseColorMovie = '#A855F7';
const String kExpenseColorHospital = '#FB7185';
const String kExpenseColorCart = '#16A34A';
const String kExpenseColorRedeem = '#F43F5E';
const String kExpenseColorCategory = '#06B6D4';

/// Path relative to the `expense:` prefix → seed / accent hex.
///
/// Parent branch nodes (`trading`, `tax`) have their own hues so a
/// roll-up that lands on the parent still paints distinctly from leaves.
const Map<String, String> kExpenseCategorySeedHexByPath = {
  'dining': kExpenseColorDining,
  'groceries': kExpenseColorGroceries,
  'coffee': kExpenseColorCoffee,
  'transport': kExpenseColorTransport,
  'rideHailing': kExpenseColorRideHailing,
  'housing': kExpenseColorHousing,
  'utilities': kExpenseColorUtilities,
  'household': kExpenseColorHousehold,
  'shopping': kExpenseColorShopping,
  'subscriptions': kExpenseColorSubscriptions,
  'entertainment': kExpenseColorEntertainment,
  'medical': kExpenseColorMedical,
  'fitness': kExpenseColorFitness,
  'education': kExpenseColorEducation,
  'travel': kExpenseColorTravel,
  'communication': kExpenseColorCommunication,
  'gift': kExpenseColorGift,
  'familySupport': kExpenseColorFamilySupport,
  'pets': kExpenseColorPets,
  'trading': kExpenseColorTrading,
  'trading:fee': kExpenseColorTradingFee,
  'trading:tax': kExpenseColorTradingTax,
  'trading:interest': kExpenseColorTradingInterest,
  'tax': kExpenseColorTax,
  'tax:withholding': kExpenseColorTaxWithholding,
  'other': kExpenseColorOther,
};

/// Material icon token → same hex space as [kExpenseCategorySeedHexByPath].
///
/// Icons used by different taxonomy leaves never share a hex. Alias icons
/// for the same leaf may share.
const Map<String, String> kExpenseCategorySeedHexByIcon = {
  'restaurant': kExpenseColorDining,
  'fastfood': kExpenseColorFastfood,
  'local_cafe': kExpenseColorCoffee,
  'local_grocery_store': kExpenseColorGroceries,
  'directions_car': kExpenseColorCar,
  'directions_bus': kExpenseColorTransport,
  'local_taxi': kExpenseColorRideHailing,
  'home': kExpenseColorHousing,
  'apartment': kExpenseColorApartment,
  'bolt': kExpenseColorUtilities,
  'chair': kExpenseColorHousehold,
  'sports_esports': kExpenseColorEntertainment,
  'movie': kExpenseColorMovie,
  'medical_services': kExpenseColorMedical,
  'local_hospital': kExpenseColorHospital,
  'school': kExpenseColorEducation,
  'shopping_bag': kExpenseColorShopping,
  'shopping_cart': kExpenseColorCart,
  'flight': kExpenseColorTravel,
  'phone_android': kExpenseColorCommunication,
  'smartphone': kExpenseColorCommunication,
  'card_giftcard': kExpenseColorGift,
  'redeem': kExpenseColorRedeem,
  'pets': kExpenseColorPets,
  'fitness_center': kExpenseColorFitness,
  'show_chart': kExpenseColorTrading,
  'receipt_long': kExpenseColorTradingFee,
  'request_quote': kExpenseColorTradingTax,
  'credit_card': kExpenseColorSubscriptions,
  'category': kExpenseColorCategory,
  'more_horiz': kExpenseColorOther,
};
