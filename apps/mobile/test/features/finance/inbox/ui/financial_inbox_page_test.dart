import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/inbox/data/financial_inbox_providers.dart';
import 'package:naviwealth/features/finance/inbox/domain/financial_inbox.dart';
import 'package:naviwealth/features/finance/inbox/ui/financial_inbox_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('shows concrete expenses in anomaly details', (tester) async {
    final detectedAt = DateTime.utc(2026, 7, 21, 8);
    final item = FinancialInboxItem(
      id: 'signal-1',
      sourceKey: 'expense-anomaly:2026-07',
      kind: FinancialInboxKind.expenseAnomaly,
      priority: FinancialInboxPriority.attention,
      count: 1,
      route: '/activity/spending',
      evidence: const <String, Object?>{
        'period': '2026-07',
        'delta_ratio': 0.4,
        'expense_count': 1,
        'expenses': <Object?>[
          <String, Object?>{
            'id': 'expense-1',
            'date': '2026-07-20T10:00:00.000Z',
            'amount': '88.00',
            'currency': 'CNY',
            'note': 'Coffee',
          },
        ],
      },
      firstDetectedAt: detectedAt,
      lastDetectedAt: detectedAt,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financialInboxScanProvider.overrideWith(
            (_) async => <FinancialInboxItem>[item],
          ),
        ],
        child: FTheme(
          data: FTheme.neutral.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const FinancialInboxPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review unusual spending'));
    await tester.pumpAndSettle();

    expect(find.text('Expense details'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('CNY 88.00'), findsOneWidget);
  });
}
