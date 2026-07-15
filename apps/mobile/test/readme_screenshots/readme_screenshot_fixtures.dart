import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/accounts/data/account_balances_provider.dart';
import 'package:naviwealth/features/finance/accounts/domain/account_balances.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_action.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_calculator.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_plan.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_projection.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_state.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_trend_builder.dart';

final readmeNow = DateTime.utc(2026, 7, 12, 9, 30);

final _sync = SyncMeta(
  ownerUserId: 'readme-user',
  updatedAt: readmeNow,
  updatedByDevice: 'readme-device',
  hlc: const Hlc(
    wallMillis: 1783829400000,
    counter: 0,
    nodeId: 'readme-device',
  ),
);

Account _account({
  required String id,
  required String name,
  required AccountCategory type,
  required String currency,
  required AccountSide category,
  String? institution,
  String? icon,
  String? color,
}) => Account(
  id: id,
  type: type,
  name: name,
  currency: currency,
  category: category,
  institution: institution,
  icon: icon,
  color: color,
  sync: _sync,
);

final readmeAccounts = <Account>[
  _account(
    id: 'assets:checking',
    name: '日常账户',
    type: AccountCategory.bank,
    currency: 'CNY',
    category: AccountSide.asset,
    institution: 'Navi Bank',
    icon: 'account_balance',
    color: '#2AC4D6',
  ),
  _account(
    id: 'assets:broker',
    name: '长期投资',
    type: AccountCategory.broker,
    currency: 'USD',
    category: AccountSide.asset,
    institution: 'Navi Broker',
    icon: 'show_chart',
    color: '#22C55E',
  ),
  _account(
    id: 'liabilities:card',
    name: '信用卡',
    type: AccountCategory.credit,
    currency: 'CNY',
    category: AccountSide.liability,
    institution: 'Navi Bank',
    icon: 'credit_card',
    color: '#FB7185',
  ),
];

final _readmeBalances = <String, AccountBalances>{
  'assets:checking': AccountBalances(
    accountId: 'assets:checking',
    legs: <AccountBalanceLeg>[
      AccountBalanceLeg(unit: 'CNY', units: Decimal.parse('123456.78')),
    ],
  ),
  'assets:broker': AccountBalances(
    accountId: 'assets:broker',
    legs: <AccountBalanceLeg>[
      AccountBalanceLeg(unit: 'USD', units: Decimal.parse('3280.40')),
    ],
  ),
  'liabilities:card': AccountBalances(
    accountId: 'liabilities:card',
    legs: <AccountBalanceLeg>[
      AccountBalanceLeg(unit: 'CNY', units: Decimal.parse('-8600.20')),
    ],
  ),
};

DashboardSnapshot _snapshot() => DashboardSnapshot(
  asOf: readmeNow,
  baseCurrency: 'CNY',
  allocations: const [],
  totalAssets: Money(Decimal.parse('146500.00'), 'CNY'),
  totalLiabilities: Money(Decimal.parse('8600.20'), 'CNY'),
  netWorth: Money(Decimal.parse('137899.80'), 'CNY'),
);

DashboardTrend _trend() {
  final range = DashboardTimeRange.resolve(
    preset: DashboardRangePreset.y1,
    now: readmeNow,
  );
  TrendPoint point(DateTime asOf, String assets, String liabilities) {
    final assetMoney = Money(Decimal.parse(assets), 'CNY');
    final liabilityMoney = Money(Decimal.parse(liabilities), 'CNY');
    return TrendPoint(
      asOf: asOf,
      assets: assetMoney,
      liabilities: liabilityMoney,
      netWorth: assetMoney - liabilityMoney,
    );
  }

  return DashboardTrend(
    range: range,
    baseCurrency: 'CNY',
    points: <TrendPoint>[
      point(DateTime.utc(2025, 7, 12), '126000', '12400'),
      point(DateTime.utc(2026, 1, 12), '136400', '10300'),
      point(readmeNow, '146500', '8600.20'),
    ],
  );
}

List<Override> readmeWealthOverrides() => <Override>[
  accountsStreamProvider.overrideWith(
    (_) => Stream<List<Account>>.value(readmeAccounts),
  ),
  accountBalancesByIdProvider.overrideWith(
    (_) => Stream<Map<String, AccountBalances>>.value(_readmeBalances),
  ),
  dashboardBaseCurrencyProvider.overrideWith((_) => 'CNY'),
  dashboardSnapshotProvider.overrideWith((_) => _snapshot()),
  dashboardTrendProvider.overrideWith((_, _) => _trend()),
];

FireGoal readmeFireGoal() => FireGoal(
  targetAmount: Decimal.parse('1000000'),
  monthlyExpenses: Decimal.parse('4000'),
  monthlySurplus: Decimal.parse('5000'),
  inflationRate: 0.03,
);

FireDashboardView readmeFireView() => const FireCalculator().buildView(
  goal: readmeFireGoal(),
  currentNetWorth: Decimal.parse('820000'),
  baseCurrency: 'CNY',
  start: readmeNow,
);

FireState readmeFireState() => FireState(
  plan: FirePlan.fromGoal(readmeFireGoal(), baseCurrency: 'CNY'),
  baseCurrency: 'CNY',
  netWorth: Money(Decimal.parse('820000'), 'CNY'),
  investableAssets: Money(Decimal.parse('780000'), 'CNY'),
  liquidAssets: Money(Decimal.parse('36000'), 'CNY'),
  annualSpend: Money(Decimal.parse('48000'), 'CNY'),
  monthlyExpense: Money(Decimal.parse('4000'), 'CNY'),
  withdrawalRate: 0.0615,
  cashBucketMonths: 9,
  fireEtaMonths: 84,
  safetyLevel: FireSafetyLevel.cautious,
  suggestedActions: const <FireAction>[
    FireAction(
      kind: FireActionKind.topUpCashBucket,
      severity: FireActionSeverity.warning,
      months: 12,
    ),
    FireAction(
      kind: FireActionKind.reduceSpending,
      severity: FireActionSeverity.warning,
      pct: 0.0215,
    ),
  ],
  stressTests: const [],
  currencyMismatchCount: 0,
  computedAt: readmeNow,
);

Override readmeFireStateOverride() => fireStateProvider.overrideWith(
  (_) => AsyncValue<FireState>.data(readmeFireState()),
);
