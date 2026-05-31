/// Canonical Finance expense category taxonomy.
///
/// The slug is the writable account path segment under `expense:<slug>`.
/// Keep this list aligned with the seeded expense accounts; callers should
/// never introduce ad-hoc category slugs.
library;

final RegExp expenseCategoryTokenRun = RegExp(r'[一-鿿]+|[a-z0-9]+');
final RegExp expenseCategoryCjkRun = RegExp(r'[一-鿿]');

class ExpenseCategoryDefinition {
  const ExpenseCategoryDefinition({
    required this.slug,
    required this.labelZh,
    required this.merchantAliases,
    required this.queryKeywords,
  });

  final String slug;
  final String labelZh;
  final List<String> merchantAliases;
  final List<String> queryKeywords;

  String get accountPath => 'expense:$slug';
}

const List<ExpenseCategoryDefinition> kExpenseCategoryTaxonomy = [
  ExpenseCategoryDefinition(
    slug: 'dining',
    labelZh: '餐饮',
    merchantAliases: [
      'mcdonald',
      'kfc',
      'subway',
      'uber eats',
      'ubereats',
      'doordash',
      'grubhub',
      'meituan',
      '美团外卖',
      '美团',
      '饿了么',
      'eleme',
      '麦当劳',
      '肯德基',
    ],
    queryKeywords: ['餐饮', '吃饭', '外卖', 'dining', 'delivery', 'food delivery'],
  ),
  ExpenseCategoryDefinition(
    slug: 'groceries',
    labelZh: '生鲜日用',
    merchantAliases: [
      'whole foods',
      'wholefoods',
      'safeway',
      'costco',
      'trader joes',
      'traderjoes',
      'walmart',
      '盒马',
      '沃尔玛',
      '山姆',
    ],
    queryKeywords: ['生鲜', '日用', '超市', 'groceries', 'grocery'],
  ),
  ExpenseCategoryDefinition(
    slug: 'coffee',
    labelZh: '咖啡',
    merchantAliases: [
      'starbucks',
      'luckin',
      'blue bottle',
      'bluebottle',
      '星巴克',
      '瑞幸咖啡',
      '瑞幸',
      'manner',
    ],
    queryKeywords: ['咖啡', 'coffee'],
  ),
  ExpenseCategoryDefinition(
    slug: 'transport',
    labelZh: '公共交通',
    merchantAliases: ['metro', 'subway transit', '公交', '地铁'],
    queryKeywords: ['公共交通', '公交', '地铁', 'transport', 'transit'],
  ),
  ExpenseCategoryDefinition(
    slug: 'rideHailing',
    labelZh: '打车',
    merchantAliases: ['uber', 'lyft', 'didi', '滴滴'],
    queryKeywords: ['打车', '网约车', 'ride hailing', 'rideshare'],
  ),
  ExpenseCategoryDefinition(
    slug: 'housing',
    labelZh: '住房',
    merchantAliases: ['rent', 'mortgage', '房租', '租金', '物业'],
    queryKeywords: ['住房', '房租', '租金', 'housing', 'rent'],
  ),
  ExpenseCategoryDefinition(
    slug: 'utilities',
    labelZh: '水电燃气',
    merchantAliases: [
      'verizon',
      'comcast',
      'pge',
      'pg&e',
      '中国移动',
      '中国联通',
      '国家电网',
      '燃气',
      '自来水',
    ],
    queryKeywords: ['水电', '燃气', 'utilities'],
  ),
  ExpenseCategoryDefinition(
    slug: 'household',
    labelZh: '家居日用',
    merchantAliases: ['ikea', '宜家'],
    queryKeywords: ['家居', 'household'],
  ),
  ExpenseCategoryDefinition(
    slug: 'shopping',
    labelZh: '购物',
    merchantAliases: [
      'apple store',
      'applestore',
      'amazon',
      'taobao',
      '淘宝',
      '京东',
      'jd',
      'tmall',
      '天猫',
    ],
    queryKeywords: ['购物', 'shopping'],
  ),
  ExpenseCategoryDefinition(
    slug: 'subscriptions',
    labelZh: '订阅',
    merchantAliases: [
      'netflix',
      'spotify',
      'apple music',
      'apple.com/bill',
      'icloud',
      'dropbox',
      'github',
      'openai',
      '腾讯视频',
      '爱奇艺',
    ],
    queryKeywords: ['订阅', 'subscription'],
  ),
  ExpenseCategoryDefinition(
    slug: 'entertainment',
    labelZh: '娱乐',
    merchantAliases: ['cinema', 'movie', 'steam', '影院', '电影'],
    queryKeywords: ['娱乐', '电影', '游戏', 'entertainment'],
  ),
  ExpenseCategoryDefinition(
    slug: 'medical',
    labelZh: '医疗',
    merchantAliases: ['hospital', 'pharmacy', '医院', '药房', '药店'],
    queryKeywords: ['医疗', '医院', '药', 'medical'],
  ),
  ExpenseCategoryDefinition(
    slug: 'fitness',
    labelZh: '运动健身',
    merchantAliases: ['gym', 'fitness', '健身房'],
    queryKeywords: ['健身', '运动', 'fitness'],
  ),
  ExpenseCategoryDefinition(
    slug: 'education',
    labelZh: '教育',
    merchantAliases: ['school', 'coursera', 'udemy', '学校', '培训'],
    queryKeywords: ['教育', '学习', '培训', 'education'],
  ),
  ExpenseCategoryDefinition(
    slug: 'travel',
    labelZh: '旅行',
    merchantAliases: ['airbnb', 'booking.com', 'hotel', 'ctrip', '携程', '酒店'],
    queryKeywords: ['旅行', '酒店', '机票', 'travel'],
  ),
  ExpenseCategoryDefinition(
    slug: 'communication',
    labelZh: '通讯',
    merchantAliases: ['phone bill', 'mobile bill', '话费', '通信'],
    queryKeywords: ['通讯', '话费', 'communication'],
  ),
  ExpenseCategoryDefinition(
    slug: 'gift',
    labelZh: '礼物',
    merchantAliases: ['gift', '礼物', '礼品'],
    queryKeywords: ['礼物', 'gift'],
  ),
  ExpenseCategoryDefinition(
    slug: 'familySupport',
    labelZh: '家庭支持',
    merchantAliases: ['family support', '赡养', '家庭支持'],
    queryKeywords: ['家庭支持', '赡养', 'family support'],
  ),
  ExpenseCategoryDefinition(
    slug: 'pets',
    labelZh: '宠物',
    merchantAliases: ['petco', 'petsmart', '宠物'],
    queryKeywords: ['宠物', 'pets'],
  ),
  ExpenseCategoryDefinition(
    slug: 'trading:fee',
    labelZh: '手续费',
    merchantAliases: ['trading fee', 'commission', '手续费'],
    queryKeywords: ['手续费', '交易手续费', 'trading fee'],
  ),
  ExpenseCategoryDefinition(
    slug: 'trading:tax',
    labelZh: '交易税费',
    merchantAliases: ['trading tax', '交易税费'],
    queryKeywords: ['交易税费', 'trading tax'],
  ),
  ExpenseCategoryDefinition(
    slug: 'trading:interest',
    labelZh: '融资利息',
    merchantAliases: ['margin interest', '融资利息'],
    queryKeywords: ['融资利息', 'margin interest'],
  ),
  ExpenseCategoryDefinition(
    slug: 'tax:withholding',
    labelZh: '预扣税',
    merchantAliases: ['withholding tax', '预扣税'],
    queryKeywords: ['预扣税', 'withholding tax'],
  ),
  ExpenseCategoryDefinition(
    slug: 'other',
    labelZh: '其他支出',
    merchantAliases: [],
    queryKeywords: ['其他支出', '其它', 'other'],
  ),
];

String normalizeExpenseCategoryText(String input) =>
    expenseCategoryTokenRun.allMatches(input.toLowerCase()).map((m) {
      return m.group(0)!;
    }).join();

ExpenseCategoryDefinition? expenseCategoryBySlug(String slug) {
  for (final category in kExpenseCategoryTaxonomy) {
    if (category.slug == slug) return category;
  }
  return null;
}

ExpenseCategoryDefinition? expenseCategoryByInput(String input) {
  final normalized = normalizeExpenseCategoryText(input);
  if (normalized.isEmpty) return null;
  for (final category in kExpenseCategoryTaxonomy) {
    if (normalized == normalizeExpenseCategoryText(category.slug) ||
        normalized == normalizeExpenseCategoryText(category.labelZh)) {
      return category;
    }
    for (final term in [
      ...category.queryKeywords,
      ...category.merchantAliases,
    ]) {
      if (normalized == normalizeExpenseCategoryText(term)) return category;
    }
  }
  return null;
}

bool isExpenseCategorySlug(String slug) => expenseCategoryBySlug(slug) != null;

List<ExpenseCategoryDefinition> fallbackExpenseCategoryCandidates() => [
  kExpenseCategoryTaxonomy.firstWhere((c) => c.slug == 'dining'),
  kExpenseCategoryTaxonomy.firstWhere((c) => c.slug == 'shopping'),
  kExpenseCategoryTaxonomy.firstWhere((c) => c.slug == 'other'),
];
