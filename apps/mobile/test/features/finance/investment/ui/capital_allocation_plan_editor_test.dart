import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/investment/ui/capital_allocation_plan_editor.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('normalizes allocation to 100 percent before saving', (
    tester,
  ) async {
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
    expect(find.text('100%'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider).first);
    slider.onChanged!(7000);
    await tester.pump();
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.map((draft) => draft.targetWeightBps), [7000, 3000]);
  });

  testWidgets('expands advanced settings for only one sleeve on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
                        targetWeightBps: 4000,
                        driftBandBps: 500,
                        transferPolicy: GroupTransferPolicy.inflowsOnly,
                      ),
                    ],
                    onSave: (_) async {},
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
    expect(find.text('Allowed deviation (%)'), findsNothing);

    await tester.tap(find.byIcon(FLucideIcons.settings2).first);
    await tester.pumpAndSettle();
    expect(find.text('Allowed deviation (%)'), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.settings2).last);
    await tester.pumpAndSettle();
    expect(find.text('Allowed deviation (%)'), findsOneWidget);
  });
}
