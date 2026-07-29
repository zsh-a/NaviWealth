import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/investment/ui/capital_allocation_plan_editor.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('fills the allocation remainder before saving', (tester) async {
    List<CapitalAllocationDraft>? saved;
    await tester.pumpWidget(
      FTheme(
        data: FThemes.slate.light.desktop,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FButton(
                  onPress: () => showCapitalAllocationPlanEditor(
                    context: context,
                    title: 'Allocation',
                    subtitle: 'Set targets',
                    weightLabel: 'Target',
                    singleItemHint: 'Fixed',
                    drafts: const [
                      CapitalAllocationDraft(
                        id: 'a',
                        name: 'Core',
                        targetWeightBps: 6000,
                        driftBandBps: 500,
                        transferPolicy: GroupTransferPolicy.bidirectional,
                      ),
                      CapitalAllocationDraft(
                        id: 'b',
                        name: 'Income',
                        targetWeightBps: 3000,
                        driftBandBps: 500,
                        transferPolicy: GroupTransferPolicy.inflowsOnly,
                      ),
                    ],
                    onSave: (drafts) async => saved = drafts,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('90%'), findsOneWidget);

    await tester.tap(find.text('Fill remainder'));
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.map((draft) => draft.targetWeightBps), [6000, 4000]);
  });
}
