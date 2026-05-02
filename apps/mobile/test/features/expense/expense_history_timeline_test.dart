import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/audit/domain_event.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/expense/ui/expense_history_timeline.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

DomainEvent _event({
  required String id,
  required DomainEventKind kind,
  required int millis,
  Map<String, Object?>? before,
  Map<String, Object?>? after,
  String? reason,
}) =>
    DomainEvent(
      id: id,
      entityTable: 'transactions',
      entityId: 'exp-1',
      kind: kind,
      actorUserId: 'u-test',
      actorDeviceId: 'dev-test',
      recordedAt: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
      hlc: Hlc(wallMillis: millis, counter: 0, nodeId: 'dev-test'),
      before: before,
      after: after,
      reason: reason,
    );

ProviderScope _wrap({
  required Widget child,
  required List<DomainEvent> events,
}) {
  return ProviderScope(
    overrides: [
      eventTimelineProvider.overrideWith((ref, key) => Stream.value(events)),
      accountsStreamProvider.overrideWith((ref) => Stream.value(const [])),
      expenseCategoriesStreamProvider
          .overrideWith((ref) => Stream.value(const [])),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets(
      'FIR-127 acceptance: 50 → 80 edit shows two history rows '
      '(created + field_changed)', (tester) async {
    final events = [
      _event(
        id: 'evt-create',
        kind: DomainEventKind.created,
        millis: 1_700_000_000_000,
        after: <String, Object?>{
          'amount': '50',
          'currency': 'CNY',
          'trade_date': DateTime.utc(2026, 4, 1).toIso8601String(),
        },
      ),
      _event(
        id: 'evt-change',
        kind: DomainEventKind.fieldChanged,
        millis: 1_700_000_001_000,
        before: <String, Object?>{'amount': '50'},
        after: <String, Object?>{'amount': '80'},
      ),
    ];

    await tester.pumpWidget(
      _wrap(
        child: const ExpenseHistoryTimeline(expenseId: 'exp-1'),
        events: events,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Change history'), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
    expect(find.text('Updated'), findsOneWidget);
    final hasFiftyEighty = find.byWidgetPredicate((widget) {
      if (widget is RichText) {
        final text = widget.text.toPlainText();
        return text.contains('Amount') &&
            text.contains('50') &&
            text.contains('80') &&
            text.contains('→');
      }
      return false;
    });
    expect(hasFiftyEighty, findsOneWidget);
  });

  testWidgets('renders the empty placeholder when no events exist',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        child: const ExpenseHistoryTimeline(expenseId: 'exp-no-history'),
        events: const [],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Change history'), findsOneWidget);
    expect(find.text('No changes recorded yet.'), findsOneWidget);
  });

  testWidgets('soft_deleted event renders the deleted body line',
      (tester) async {
    final events = [
      _event(
        id: 'evt-create',
        kind: DomainEventKind.created,
        millis: 1_700_000_000_000,
        after: <String, Object?>{'amount': '12'},
      ),
      _event(
        id: 'evt-delete',
        kind: DomainEventKind.softDeleted,
        millis: 1_700_000_001_000,
        reason: 'duplicate entry',
      ),
    ];

    await tester.pumpWidget(
      _wrap(
        child: const ExpenseHistoryTimeline(expenseId: 'exp-1'),
        events: events,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Deleted'), findsOneWidget);
    expect(find.text('Expense deleted.'), findsOneWidget);
    expect(find.text('Reason: duplicate entry'), findsOneWidget);
  });
}
