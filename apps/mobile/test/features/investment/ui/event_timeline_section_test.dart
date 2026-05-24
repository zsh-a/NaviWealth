import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/investment/data/event_timeline_providers.dart';
import 'package:naviwealth/features/investment/domain/reporting/event_timeline.dart';
import 'package:naviwealth/features/investment/ui/event_timeline_section.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

CorporateActionEvent _event({
  required String id,
  String symbol = 'AAPL',
  CorporateActionKind kind = CorporateActionKind.cashDividend,
  required DateTime scheduledFor,
  String cashAmount = '0.22',
  SplitRatio? ratio,
}) =>
    CorporateActionEvent(
      id: id,
      symbol: symbol,
      kind: kind,
      scheduledFor: scheduledFor,
      cashAmount: Decimal.parse(cashAmount),
      currency: 'USD',
      ratio: ratio,
    );

Future<void> _pump(
  WidgetTester tester,
  String symbol,
  List<CorporateActionEvent> events,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        corporateActionEventsProvider(symbol).overrideWith(
          (ref) async => events,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en', 'US'),
        home: Scaffold(body: EventTimelineSection(symbol: symbol)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('renders empty state when provider has no events',
      (tester) async {
    await _pump(tester, 'AAPL', const []);
    expect(
      find.text('No upcoming dividends or splits in the next 90 days.'),
      findsOneWidget,
    );
  });

  testWidgets('renders a dividend row with amount in the suffix',
      (tester) async {
    final inFiveDays = DateTime.now().toUtc().add(const Duration(days: 5));
    await _pump(tester, 'AAPL', [
      _event(
        id: 'div-1',
        scheduledFor: inFiveDays,
        cashAmount: '0.24',
      ),
    ]);
    expect(find.text('Dividend'), findsOneWidget);
    // MoneyText surfaces the amount with grouping.
    expect(find.textContaining('0.24'), findsWidgets);
  });

  testWidgets('renders a split row with ratio label', (tester) async {
    final inTenDays = DateTime.now().toUtc().add(const Duration(days: 10));
    await _pump(tester, 'AAPL', [
      _event(
        id: 'split-1',
        scheduledFor: inTenDays,
        kind: CorporateActionKind.split,
        cashAmount: '0',
        ratio: const SplitRatio(4, 1),
      ),
    ]);
    expect(find.textContaining('Split 4-for-1'), findsOneWidget);
  });

  testWidgets('filters out events outside the 90-day window', (tester) async {
    // Way-future event — the builder's window drops it.
    final inFarFuture = DateTime.now().toUtc().add(const Duration(days: 365));
    await _pump(tester, 'AAPL', [
      _event(id: 'div-far', scheduledFor: inFarFuture),
    ]);
    expect(find.text('Dividend'), findsNothing);
    expect(find.textContaining('No upcoming'), findsOneWidget);
  });

  testWidgets('only renders events for the supplied symbol', (tester) async {
    final inFiveDays = DateTime.now().toUtc().add(const Duration(days: 5));
    await _pump(tester, 'AAPL', [
      _event(id: 'aapl-div', scheduledFor: inFiveDays),
      _event(id: 'msft-div', symbol: 'MSFT', scheduledFor: inFiveDays),
    ]);
    // Both rows would render if the filter were broken; expect exactly 1.
    expect(find.text('Dividend'), findsOneWidget);
  });
}
