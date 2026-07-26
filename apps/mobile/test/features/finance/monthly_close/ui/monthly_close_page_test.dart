import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/monthly_close/data/monthly_close_providers.dart';
import 'package:naviwealth/features/finance/monthly_close/domain/monthly_close.dart';
import 'package:naviwealth/features/finance/monthly_close/ui/monthly_close_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets(
    'waits for an explicit start before opening the close checklist',
    (tester) async {
      const evidence = MonthlyCloseEvidence(
        states: <MonthlyCloseStep, MonthlyCloseStepState>{
          MonthlyCloseStep.importReview: MonthlyCloseStepState.verified,
          MonthlyCloseStep.inboxClear: MonthlyCloseStepState.ready,
          MonthlyCloseStep.accountReconcile: MonthlyCloseStepState.ready,
          MonthlyCloseStep.runwayReview: MonthlyCloseStepState.verified,
          MonthlyCloseStep.actionReview: MonthlyCloseStepState.ready,
        },
        details: <String, Object?>{},
      );
      const comparison = MonthlyCloseComparison(
        newSignalKeys: <String>{},
        clearedSignalKeys: <String>{},
        carriedSignalKeys: <String>{},
        carriedReconciliationKeys: <String>{},
        previousDuration: null,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentClosePeriodProvider.overrideWithValue('2026-07'),
            currentMonthlyCloseProvider.overrideWith((_) => Stream.value(null)),
            monthlyCloseEvidenceProvider.overrideWith(
              (_) => const AsyncValue.data(evidence),
            ),
            reconciliationTargetsProvider.overrideWith(
              (_) => const AsyncValue.data([]),
            ),
            monthlyCloseComparisonProvider.overrideWith(
              (_) => const AsyncValue.data(comparison),
            ),
            monthlyCloseHistoryProvider.overrideWith(
              (_) => Stream.value(const <MonthlyClose>[]),
            ),
          ],
          child: FTheme(
            data: FThemes.slate.light.desktop,
            child: MaterialApp(
              theme: AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: const MonthlyClosePage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Start monthly close'), findsOneWidget);
      expect(find.text('Close 2026-07'), findsOneWidget);
      expect(find.text('Review imported transactions'), findsNothing);
      expect(find.text('Account reconciliation'), findsNothing);
    },
  );
}
