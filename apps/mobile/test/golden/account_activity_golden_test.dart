import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/write/providers.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/activity/ui/activity_entry_detail_page.dart';
import 'package:naviwealth/features/finance/accounts/data/account_balances_provider.dart';
import 'package:naviwealth/features/finance/accounts/domain/account_balances.dart';
import 'package:naviwealth/features/finance/accounts/ui/accounts_master.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/journal_entry.dart';
import 'package:naviwealth/features/finance/data/domain/posting.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/ui/wealth/wealth_hub_page.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';

import '_golden_setup.dart';

const _locale = Locale('zh');
const _hlc = Hlc(wallMillis: 1700000000000, counter: 0, nodeId: 'dev');
final _sync = SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 5, 1),
  updatedByDevice: 'dev',
  hlc: _hlc,
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
}) {
  return Account(
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
}

Posting _posting({
  required String id,
  required String journalEntryId,
  required String accountId,
  required String units,
  required String unit,
  int position = 0,
}) {
  return Posting(
    id: id,
    journalEntryId: journalEntryId,
    position: position,
    accountId: accountId,
    units: Decimal.parse(units),
    unit: unit,
    sync: _sync,
  );
}

List<Account> _accounts() {
  return [
    _account(
      id: 'assets:wallet',
      name: '招商储蓄卡',
      type: AccountCategory.bank,
      currency: 'CNY',
      category: AccountSide.asset,
      institution: '招商银行',
      icon: 'account_balance',
      color: '#2563EB',
    ),
    _account(
      id: 'assets:broker',
      name: '长期投资账户',
      type: AccountCategory.broker,
      currency: 'USD',
      category: AccountSide.asset,
      institution: 'Navi Broker',
      icon: 'show_chart',
      color: '#059669',
    ),
    _account(
      id: 'liabilities:card',
      name: '信用卡',
      type: AccountCategory.credit,
      currency: 'CNY',
      category: AccountSide.liability,
      institution: 'Navi Bank',
      icon: 'credit_card',
      color: '#DC2626',
    ),
  ];
}

Map<String, AccountBalances> _balances() {
  return {
    'assets:wallet': AccountBalances(
      accountId: 'assets:wallet',
      legs: [AccountBalanceLeg(unit: 'CNY', units: Decimal.parse('123456.78'))],
    ),
    'assets:broker': AccountBalances(
      accountId: 'assets:broker',
      legs: [
        AccountBalanceLeg(unit: 'USD', units: Decimal.parse('3280.40')),
        AccountBalanceLeg(unit: 'us_stock:AAPL', units: Decimal.parse('12')),
      ],
    ),
    'liabilities:card': AccountBalances(
      accountId: 'liabilities:card',
      legs: [AccountBalanceLeg(unit: 'CNY', units: Decimal.parse('-8600.20'))],
    ),
  };
}

JournalEntryWithPostings _entry() {
  return JournalEntryWithPostings(
    entry: JournalEntry(
      id: 'je-subscription',
      date: DateTime.utc(2026, 5, 1, 9, 30),
      narration: '网易云音乐会员',
      payee: '网易云音乐',
      sync: _sync,
    ),
    postings: [
      _posting(
        id: 'p-expense',
        journalEntryId: 'je-subscription',
        accountId: 'expenses:subscription',
        units: '1288.50',
        unit: 'CNY',
      ),
      _posting(
        id: 'p-wallet',
        journalEntryId: 'je-subscription',
        accountId: 'assets:wallet',
        units: '-1288.50',
        unit: 'CNY',
        position: 1,
      ),
    ],
  );
}

Map<String, Account> _entryAccountsById() {
  return {
    for (final account in _accounts()) account.id: account,
    'expenses:subscription': _account(
      id: 'expenses:subscription',
      name: '订阅服务',
      type: AccountCategory.cash,
      currency: 'CNY',
      category: AccountSide.expense,
    ),
  };
}

DashboardSnapshot _snapshot() {
  return DashboardSnapshot(
    asOf: DateTime.utc(2026, 5, 1),
    baseCurrency: 'CNY',
    allocations: const [],
    totalAssets: Money(Decimal.parse('146500.00'), 'CNY'),
    totalLiabilities: Money(Decimal.parse('8600.20'), 'CNY'),
    netWorth: Money(Decimal.parse('137899.80'), 'CNY'),
  );
}

List<Override> _accountOverrides() {
  final accounts = _accounts();
  return [
    accountsStreamProvider.overrideWith((_) => Stream.value(accounts)),
    accountBalancesByIdProvider.overrideWith((_) => Stream.value(_balances())),
    dashboardSnapshotProvider.overrideWith((_) async => _snapshot()),
  ];
}

void main() {
  setUpAll(AppFormatters.ensureInitialized);

  runAllVariants('activity_entry_detail_page', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'activity_entry_detail_page',
      variant: variant,
      locale: _locale,
      overrides: [
        aiTouchedAtProvider.overrideWith((ref, key) => Stream.value(null)),
      ],
      child: ActivityEntryDetailPage(
        entry: _entry(),
        accountsById: _entryAccountsById(),
      ),
    );
  });

  runAllVariants('wealth_hub_page', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'wealth_hub_page',
      variant: variant,
      locale: _locale,
      overrides: _accountOverrides(),
      child: const WealthHubPage(),
    );
  });

  runAllVariants('accounts_list_page', (tester, variant) async {
    await pumpAndSnapshotMobile(
      tester,
      name: 'accounts_list_page',
      variant: variant,
      locale: _locale,
      overrides: _accountOverrides(),
      child: const AccountsMaster(selectedId: null, inMasterDetail: false),
    );
  });
}
