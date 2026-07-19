import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/amortization_entry.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/liability.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';
import 'package:naviwealth/features/finance/liabilities/domain/liability_summary.dart';
import 'package:naviwealth/features/finance/liabilities/ui/liability_detail_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Decimal _d(String value) => Decimal.parse(value);

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'user-1',
  updatedAt: DateTime.utc(2026, 1, 1),
  updatedByDevice: 'device-1',
  hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: 'device-1'),
);

Liability _liability() => Liability(
  id: 'liability-1',
  type: LiabilityType.mortgage,
  name: 'Home loan',
  principal: _d('800000'),
  interestRate: _d('0.04'),
  currency: 'CNY',
  termMonths: 8,
  startDate: DateTime.utc(2026, 1, 1),
  sync: _meta(),
);

List<AmortizationEntry> _schedule() => [
  for (var index = 1; index <= 8; index++)
    AmortizationEntry(
      id: 'period-$index',
      liabilityId: 'liability-1',
      periodIndex: index,
      dueDate: DateTime.utc(2026, index + 1, 1),
      principalPayment: _d('100000'),
      interestPayment: _d('${9000 - index * 500}'),
      remainingBalance: _d('${800000 - index * 100000}'),
      paidAt: index == 1 ? DateTime.utc(2026, 2, 1) : null,
      sync: _meta(),
    ),
];

Future<Widget> _wrapDetailPage() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final liability = _liability();
  final schedule = _schedule();
  final summary = LiabilitySummary.fromSchedule(
    liability: liability,
    schedule: schedule,
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      liabilitySummaryProvider.overrideWith((ref, id) => Stream.value(summary)),
      amortizationScheduleStreamProvider.overrideWith(
        (ref, id) => Stream.value(schedule),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en', 'US'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppMessenger.init(
        child: FTheme(data: FThemes.slate.light.desktop, child: child!),
      ),
      home: const LiabilityDetailPage(id: 'liability-1'),
    ),
  );
}

void main() {
  testWidgets('uses a progressive schedule list on narrow screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(await _wrapDetailPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('liability-schedule-compact')), findsOneWidget);
    expect(find.byKey(const Key('liability-schedule-table')), findsNothing);
    Finder period(int index) => find.byWidgetPredicate(
      (widget) =>
          widget is Text && widget.data?.startsWith('#$index ·') == true,
    );

    expect(period(1), findsOneWidget);
    expect(period(6), findsOneWidget);
    expect(period(7), findsNothing);
    expect(find.text('More · 2'), findsOneWidget);

    await tester.ensureVisible(find.text('More · 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More · 2'));
    await tester.pumpAndSettle();

    expect(period(8), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the aligned schedule table on wide screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(await _wrapDetailPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('liability-schedule-table')), findsOneWidget);
    expect(find.byKey(const Key('liability-schedule-compact')), findsNothing);
    expect(find.text('Mark paid'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
