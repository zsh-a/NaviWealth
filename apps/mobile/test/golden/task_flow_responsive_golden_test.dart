import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/write/drift_undo_stack.dart';
import 'package:naviwealth/core/ai/write/persistent_undo_banner.dart';
import 'package:naviwealth/core/ai/write/providers.dart';
import 'package:naviwealth/core/forms/forms.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/accounts/ui/account_form_page.dart';
import 'package:naviwealth/features/finance/accounts/ui/transfer_form_page.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/data/securities_catalog/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/expense/ui/expense_form_page.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_confirm_service.dart';
import 'package:naviwealth/features/finance/ingest/data/providers.dart';
import 'package:naviwealth/features/finance/ingest/ui/ingest_review_page.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_entry_prefill.dart';
import 'package:naviwealth/features/finance/investment/ui/trade_entry_form_page.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_providers.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_execution.dart';
import 'package:naviwealth/features/finance/rebalance/ui/rebalance_execution_workspace_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/persistence/test_database.dart';
import '_golden_setup.dart';
import 'task_flow_golden_fixtures.dart';

void main() {
  late SharedPreferences preferences;
  late TaskFlowGoldenSearchService searchService;
  late AppDatabase database;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'naviwealth.settings.base_currency': 'CNY',
      'naviwealth.forms.expense.account': 'golden-bank-cny',
      'naviwealth.forms.expense.category': 'golden-dining',
      'naviwealth.forms.expense.currency': 'CNY',
      'naviwealth.forms.trade.account': 'golden-broker',
      'naviwealth.forms.trade.cashAccount': 'golden-bank-usd',
      'naviwealth.forms.trade.currency': 'USD',
    });
    preferences = await SharedPreferences.getInstance();
    database = makeTestDatabase();
    searchService = TaskFlowGoldenSearchService(db: database);
  });

  tearDownAll(() async {
    await database.close();
  });

  List<Override> commonOverrides() => <Override>[
    appDatabaseProvider.overrideWith((_) async => database),
    sharedPreferencesProvider.overrideWithValue(preferences),
    formClockProvider.overrideWithValue(() => taskFlowLocalDate),
  ];

  List<Override> accountOverrides() => <Override>[
    ...commonOverrides(),
    accountsStreamProvider.overrideWith(
      (_) => Stream<List<Account>>.value(taskFlowAccounts),
    ),
  ];

  List<Override> expenseOverrides() => <Override>[
    ...commonOverrides(),
    accountsStreamProvider.overrideWith(
      (_) => Stream<List<Account>>.value(
        taskFlowAccounts
            .where((account) => account.category == AccountSide.asset)
            .toList(growable: false),
      ),
    ),
    allAccountsStreamProvider.overrideWith(
      (_) => Stream<List<Account>>.value(taskFlowAccounts),
    ),
  ];

  List<Override> transferOverrides() => <Override>[
    ...commonOverrides(),
    accountsStreamProvider.overrideWith(
      (_) => Stream<List<Account>>.value(
        taskFlowAccounts
            .where((account) => account.category == AccountSide.asset)
            .toList(growable: false),
      ),
    ),
    fxRatesStreamProvider.overrideWith(
      (_) => Stream<List<FxRate>>.value(const <FxRate>[]),
    ),
  ];

  List<Override> tradeOverrides() => <Override>[
    ...commonOverrides(),
    accountsStreamProvider.overrideWith(
      (_) => Stream<List<Account>>.value(
        taskFlowAccounts
            .where((account) => account.category == AccountSide.asset)
            .toList(growable: false),
      ),
    ),
    securitiesSearchServiceProvider.overrideWith((_) async => searchService),
  ];

  List<Override> ingestOverrides() => <Override>[
    ...commonOverrides(),
    pendingIngestReviewItemsProvider.overrideWith(
      (_) => Stream<List<IngestReviewItem>>.value(taskFlowIngestItems),
    ),
    accountsStreamProvider.overrideWith(
      (_) => Stream<List<Account>>.value(
        taskFlowAccounts
            .where((account) => account.category == AccountSide.asset)
            .toList(growable: false),
      ),
    ),
  ];

  Future<void> pumpIngest(
    WidgetTester tester,
    ResponsiveGoldenProfile profile,
    String name,
  ) => pumpAndSnapshotResponsive(
    tester,
    name: name,
    profile: profile,
    overrides: ingestOverrides(),
    child: const IngestReviewPage(),
  );

  Future<void> pumpTransfer(
    WidgetTester tester,
    ResponsiveGoldenProfile profile,
    String name,
  ) => pumpAndSnapshotResponsive(
    tester,
    name: name,
    profile: profile,
    overrides: transferOverrides(),
    child: const TransferFormPage(),
  );

  Future<void> pumpUndo(
    WidgetTester tester,
    ResponsiveGoldenProfile profile,
    String name,
  ) => pumpAndSnapshotResponsive(
    tester,
    name: name,
    profile: profile,
    overrides: <Override>[
      ...commonOverrides(),
      undoEntriesStreamProvider.overrideWith(
        (_) => Stream.value(<PersistedUndoEntry>[taskFlowUndoEntry]),
      ),
    ],
    child: const Scaffold(
      body: Center(child: Text('Today')),
      bottomNavigationBar: PersistentUndoBanner(),
    ),
  );

  Future<void> pumpRebalance(
    WidgetTester tester,
    ResponsiveGoldenProfile profile,
    String name, [
    RebalanceExecutionSession? providedSession,
  ]) {
    final session = providedSession ?? taskFlowRebalanceSession();
    return pumpAndSnapshotResponsive(
      tester,
      name: name,
      profile: profile,
      overrides: <Override>[
        ...commonOverrides(),
        rebalanceExecutionSessionProvider(session.id)
            .overrideWith((_) async => session),
      ],
      child: RebalanceExecutionWorkspacePage(sessionId: session.id),
    );
  }

  runResponsiveGolden(
    'task flow ingest — narrow',
    profile: ResponsiveGoldenProfile.narrow,
    body: (tester, profile) =>
        pumpIngest(tester, profile, 'task_flow_ingest_n'),
  );
  runResponsiveGolden(
    'task flow ingest — wide',
    profile: ResponsiveGoldenProfile.wide,
    body: (tester, profile) =>
        pumpIngest(tester, profile, 'task_flow_ingest_w'),
  );
  runResponsiveGolden(
    'task flow ingest — text 2x',
    profile: ResponsiveGoldenProfile.textScale,
    body: (tester, profile) =>
        pumpIngest(tester, profile, 'task_flow_ingest_t'),
  );
  runResponsiveGolden(
    'task flow account — narrow',
    profile: ResponsiveGoldenProfile.narrow,
    body: (tester, profile) => pumpAndSnapshotResponsive(
      tester,
      name: 'task_flow_account_n',
      profile: profile,
      overrides: accountOverrides(),
      child: const AccountFormPage(),
    ),
  );
  runResponsiveGolden(
    'task flow expense — narrow',
    profile: ResponsiveGoldenProfile.narrow,
    body: (tester, profile) => pumpAndSnapshotResponsive(
      tester,
      name: 'task_flow_expense_n',
      profile: profile,
      overrides: expenseOverrides(),
      child: const ExpenseFormPage(),
    ),
  );
  runResponsiveGolden(
    'task flow transfer — narrow',
    profile: ResponsiveGoldenProfile.narrow,
    body: (tester, profile) =>
        pumpTransfer(tester, profile, 'task_flow_transfer_n'),
  );
  runResponsiveGolden(
    'task flow transfer — wide',
    profile: ResponsiveGoldenProfile.wide,
    body: (tester, profile) =>
        pumpTransfer(tester, profile, 'task_flow_transfer_w'),
  );
  runResponsiveGolden(
    'task flow transfer — text 2x',
    profile: ResponsiveGoldenProfile.textScale,
    body: (tester, profile) =>
        pumpTransfer(tester, profile, 'task_flow_transfer_t'),
  );
  runResponsiveGolden(
    'task flow trade — narrow',
    profile: ResponsiveGoldenProfile.narrow,
    body: (tester, profile) => pumpAndSnapshotResponsive(
      tester,
      name: 'task_flow_trade_n',
      profile: profile,
      overrides: tradeOverrides(),
      child: TradeEntryFormPage(
        accountId: 'golden-broker',
        prefill: TradeEntryPrefill(
          type: TradeType.buy,
          quantity: Decimal.parse('12.5'),
          price: Decimal.parse('189.75'),
          currency: 'USD',
          tradeDate: DateTime(2026, 6, 14, 15),
          fee: Decimal.parse('1.25'),
          tax: Decimal.zero,
          note: 'Quarterly allocation purchase',
        ),
      ),
    ),
  );
  runResponsiveGolden(
    'task flow persistent undo — narrow',
    profile: ResponsiveGoldenProfile.narrow,
    body: (tester, profile) =>
        pumpUndo(tester, profile, 'task_flow_persistent_undo_n'),
  );
  runResponsiveGolden(
    'task flow persistent undo — text 2x',
    profile: ResponsiveGoldenProfile.textScale,
    body: (tester, profile) =>
        pumpUndo(tester, profile, 'task_flow_persistent_undo_t'),
  );
  runResponsiveGolden(
    'task flow rebalance — narrow',
    profile: ResponsiveGoldenProfile.narrow,
    body: (tester, profile) =>
        pumpRebalance(tester, profile, 'task_flow_rebalance_n'),
  );
  runResponsiveGolden(
    'task flow rebalance — wide',
    profile: ResponsiveGoldenProfile.wide,
    body: (tester, profile) =>
        pumpRebalance(tester, profile, 'task_flow_rebalance_w'),
  );
  runResponsiveGolden(
    'task flow rebalance — text 2x',
    profile: ResponsiveGoldenProfile.textScale,
    body: (tester, profile) =>
        pumpRebalance(tester, profile, 'task_flow_rebalance_t'),
  );
  runResponsiveGolden(
    'task flow rebalance offline failure — narrow',
    profile: ResponsiveGoldenProfile.narrow,
    body: (tester, profile) => pumpRebalance(
      tester,
      profile,
      'task_flow_rebalance_offline_n',
      taskFlowRebalanceOfflineSession(),
    ),
  );
}
