import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/investment/ui/capital_allocation_plan_editor.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:naviwealth/l10n/gen/app_localizations_en.dart';

const _drafts = [
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
];

Future<void> _open(
  WidgetTester tester, {
  Future<void> Function(List<CapitalAllocationDraft>)? onSave,
  List<CapitalAllocationDraft> drafts = _drafts,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: FTheme(
        data: FTheme.neutral.light.desktop,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: AppMessenger.init(child: child!),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: FButton(
                onPress: () => showCapitalAllocationPlanEditor(
                  context: context,
                  title: 'Allocation',
                  subtitle: 'Set targets',
                  weightLabel: 'Target',
                  singleItemHint: 'Fixed',
                  drafts: drafts,
                  onSave: onSave ?? (_) async {},
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
}

String _input(WidgetTester tester, int index) => tester
    .widget<EditableText>(find.byType(EditableText).at(index))
    .controller
    .text;

void main() {
  final l10n = AppLocalizationsEn();

  testWidgets('normalizes total and preserves precise percentage inputs', (
    tester,
  ) async {
    List<CapitalAllocationDraft>? saved;
    await _open(tester, onSave: (drafts) async => saved = drafts);
    expect(find.byType(AppFormPageScaffold), findsOneWidget);
    expect(find.byType(AppSheet), findsNothing);
    expect(_input(tester, 1), '40');
    await tester.enterText(find.byType(EditableText).first, '63.27');
    await tester.pump();
    expect(_input(tester, 1), '36.73');
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved!.map((draft) => draft.targetWeightBps), [6327, 3673]);
    expect(find.byType(AppFormPageScaffold), findsNothing);
  });

  testWidgets('slider keeps editable numbers synchronized', (tester) async {
    await _open(tester);
    tester.widget<Slider>(find.byType(Slider).first).onChanged!(7000);
    await tester.pump();
    expect(_input(tester, 0), '70');
    expect(_input(tester, 1), '30');
  });

  testWidgets('invalid input blocks save and focuses the visible error', (
    tester,
  ) async {
    var saves = 0;
    await _open(tester, onSave: (_) async => saves++);
    await tester.enterText(find.byType(EditableText).first, '101');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.text(l10n.targetAllocationEditorRangeError), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.enterText(find.byType(EditableText).first, '65');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saves, 1);
  });

  testWidgets('system back protects unsaved percentages', (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(EditableText).first, '65');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(l10n.unsavedChangesTitle), findsOneWidget);
    await tester.tap(find.text(l10n.unsavedChangesKeepEditing));
    await tester.pumpAndSettle();
    expect(_input(tester, 0), '65');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.unsavedChangesDiscard));
    await tester.pumpAndSettle();
    expect(find.byType(AppFormPageScaffold), findsNothing);
  });

  testWidgets('rules use a guarded independent form and apply only to draft', (
    tester,
  ) async {
    List<CapitalAllocationDraft>? saved;
    await _open(tester, onSave: (drafts) async => saved = drafts);
    final before = tester.getTopLeft(find.text('Income'));
    await tester.tap(find.text(l10n.capitalAllocationAdvancedAction).first);
    await tester.pumpAndSettle();
    expect(find.byType(AppSheet), findsOneWidget);
    final field = find.descendant(
      of: find.byType(AppSheet),
      matching: find.byType(EditableText),
    );
    await tester.enterText(field.first, '7.25');
    await tester.pump();
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(find.text(l10n.unsavedChangesTitle), findsOneWidget);
    await tester.tap(find.text(l10n.unsavedChangesKeepEditing));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.capitalAllocationApplyRules));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.byType(AppSheet), findsNothing);
    expect(tester.getTopLeft(find.text('Income')), before);
    expect(find.textContaining('7.25'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved!.first.driftBandBps, 725);
  });

  testWidgets('failed save retains edits and allows retry', (tester) async {
    var attempts = 0;
    await _open(
      tester,
      onSave: (_) async {
        if (attempts++ == 0) throw StateError('write failed');
      },
    );
    await tester.enterText(find.byType(EditableText).first, '62.15');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AppFormPageScaffold), findsOneWidget);
    expect(_input(tester, 0), '62.15');
    expect(find.text(l10n.capitalAllocationSaveFailed), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(AppFormPageScaffold), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('saving blocks dismissal and duplicate writes', (tester) async {
    final save = Completer<void>();
    var calls = 0;
    await _open(
      tester,
      onSave: (_) {
        calls++;
        return save.future;
      },
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AppFormPageScaffold), findsOneWidget);
    expect(calls, 1);
    save.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AppFormPageScaffold), findsNothing);
  });

  testWidgets('single target and large text fit a small phone', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(tester, drafts: [_drafts.first], textScale: 1.8);
    expect(_input(tester, 0), '100');
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(l10n.capitalAllocationAdvancedAction));
    await tester.tap(find.text(l10n.capitalAllocationAdvancedAction));
    await tester.pumpAndSettle();
    expect(find.text(l10n.capitalAllocationToleranceLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
