import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/income_strategy/application/income_strategy_asset_resolver.dart';
import 'package:naviwealth/features/finance/income_strategy/application/leaps_income_sleeve_adapter.dart';
import 'package:naviwealth/features/finance/income_strategy/application/wheel_income_sleeve_adapter.dart';
import 'package:naviwealth/features/finance/income_strategy/application/wheel_strategy_view.dart';
import 'package:naviwealth/features/finance/income_strategy/data/providers.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy_assembler.dart';
import 'package:naviwealth/features/finance/options_income/domain/leaps_call_position.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/trade_journal_entry.dart';
import 'package:naviwealth/features/finance/options_income/ui/wheel_lifecycle_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 5, 24),
  updatedByDevice: 'd',
  hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd'),
);

List<WheelStrategyView> _views(
  List<TradeJournalEntry> entries,
  List<LeapsCallPosition> leaps,
) {
  final assets = IncomeStrategyAssetResolver(const []);
  return buildWheelStrategyViews(
    const IncomeStrategyAssembler().assemble(
      baseCurrency: 'USD',
      plans: const [],
      contributions: [
        ...const WheelIncomeSleeveAdapter().buildFromEntries(
          entries: entries,
          assets: assets,
        ),
        ...const LeapsIncomeSleeveAdapter().build(
          positions: leaps,
          assets: assets,
        ),
      ],
    ),
  );
}

TradeJournalEntry _entry({
  String id = 'e',
  String symbol = 'TSM',
  required OptionsStrategyKind strategy,
  required TradeJournalStatus status,
  String entryCredit = '0',
  String? exitDebit,
}) => TradeJournalEntry(
  id: id,
  strategy: strategy,
  symbol: symbol,
  optionSymbol: '$symbol-OPT',
  openedAt: DateTime.utc(2026, 5, 1),
  closedAt: status == TradeJournalStatus.open
      ? null
      : DateTime.utc(2026, 5, 15),
  entryCredit: Decimal.parse(entryCredit),
  exitDebit: exitDebit == null ? null : Decimal.parse(exitDebit),
  realizedPnl: null,
  currency: 'USD',
  status: status,
  notes: null,
  sync: _meta(),
);

Future<void> _pump(
  WidgetTester tester,
  List<TradeJournalEntry> entries, {
  List<LeapsCallPosition> leaps = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        wheelStrategyViewsProvider.overrideWith(
          (ref) => AsyncData(_views(entries, leaps)),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en', 'US'),
        home: const WheelLifecyclePage(),
      ),
    ),
  );
  // Avoid pumpAndSettle — FCircularProgress and StreamProvider don't
  // settle. Two bounded pumps flush the override + first data emission.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('renders empty state when no trades exist', (tester) async {
    await _pump(tester, const []);

    expect(find.text('No active cycles'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.refreshCw), findsWidgets);
  });

  testWidgets('lists cycles by underlying with stage label', (tester) async {
    await _pump(tester, [
      _entry(
        id: 'tsm-put',
        symbol: 'TSM',
        strategy: OptionsStrategyKind.cashSecuredPut,
        status: TradeJournalStatus.open,
      ),
      _entry(
        id: 'aapl-call',
        symbol: 'AAPL',
        strategy: OptionsStrategyKind.coveredCall,
        status: TradeJournalStatus.open,
      ),
    ]);

    expect(find.text('TSM'), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
    // Both have open positions, so the stage labels reflect them.
    expect(find.text('Short put (open)'), findsOneWidget);
    expect(find.text('Short call (open)'), findsOneWidget);
    expect(find.text('No active cycles'), findsNothing);
  });

  testWidgets('open positions sort ahead of resting cycles', (tester) async {
    await _pump(tester, [
      // Closed-out cycle — should sink toward the bottom of the list.
      _entry(
        id: 'msft-closed',
        symbol: 'MSFT',
        strategy: OptionsStrategyKind.cashSecuredPut,
        status: TradeJournalStatus.expired,
        entryCredit: '50',
        exitDebit: '0',
      ),
      // Open position on a later-alphabet symbol — should still surface
      // first because open positions rank ahead.
      _entry(
        id: 'zoom-open',
        symbol: 'ZM',
        strategy: OptionsStrategyKind.cashSecuredPut,
        status: TradeJournalStatus.open,
      ),
    ]);

    final tsmFinder = find.text('ZM');
    final msftFinder = find.text('MSFT');
    expect(tsmFinder, findsOneWidget);
    expect(msftFinder, findsOneWidget);
    final tsmTop = tester.getTopLeft(tsmFinder).dy;
    final msftTop = tester.getTopLeft(msftFinder).dy;
    expect(
      tsmTop,
      lessThan(msftTop),
      reason: 'open ZM cycle must render above closed MSFT cycle',
    );
  });

  testWidgets('cycle detail separates LEAPS cost and risk from Wheel stage', (
    tester,
  ) async {
    await _pump(
      tester,
      [
        _entry(
          symbol: 'TSM',
          strategy: OptionsStrategyKind.cashSecuredPut,
          status: TradeJournalStatus.open,
        ),
      ],
      leaps: [
        LeapsCallPosition(
          id: 'leaps',
          symbol: 'TSM',
          optionSymbol: 'TSM280121C00200000',
          openedAt: DateTime.utc(2026, 7, 1),
          expirationAt: DateTime.utc(2028, 1, 21),
          closedAt: null,
          strikePrice: Decimal.fromInt(200),
          entryDebit: Decimal.fromInt(1000),
          exitCredit: null,
          fees: Decimal.zero,
          currency: 'USD',
          contractSize: 100,
          contractQuantity: 1,
          status: LeapsCallStatus.open,
          currentMark: null,
          currentDelta: null,
          markedAt: null,
          brokerageAccountId: null,
          notes: null,
          sync: _meta(),
        ),
      ],
    );

    await tester.tap(find.text('TSM'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('LEAPS upside overlay'), findsOneWidget);
    expect(find.text('Open premium at risk'), findsOneWidget);
    expect(
      find.textContaining('does not hedge put assignment'),
      findsOneWidget,
    );
    expect(find.text('TSM280121C00200000'), findsOneWidget);
  });
}
