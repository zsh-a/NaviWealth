import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution/ui/execution_relation_picker.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('plan picker supports search and selection', (tester) async {
    String? picked;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => FButton(
            onPress: () async {
              picked = await showExecutionPlanPicker(
                context: context,
                plans: [
                  for (var i = 0; i < 8; i++)
                    ExecutionPlan(
                      id: 'plan-$i',
                      title: i == 6 ? 'Execution polish' : 'Plan $i',
                      description: i == 6 ? 'Production readiness' : '',
                      createdAt: DateTime.utc(2026, 6, 1),
                      sync: _sync(),
                    ),
                ],
                selectedId: null,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Search by title or note'), findsOneWidget);
    await tester.enterText(find.byType(FTextField), 'polish');
    // Paint-phase pumps: forui text fields wrap their input in
    // MergeSemantics, which trips a Flutter test-framework semantics
    // assertion when the filtered list rebuilds under full pumps.
    await _settlePaint(tester);

    expect(find.text('Execution polish'), findsOneWidget);
    expect(find.text('Plan 1'), findsNothing);

    await tester.tap(find.text('Execution polish'));
    await _settlePaint(tester);

    expect(picked, 'plan-6');
  });
}

Future<void> _settlePaint(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 75), EnginePhase.paint);
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: FTheme(data: FTheme.neutral.light.desktop, child: child),
  );
}

SyncMeta _sync() {
  final now = DateTime.utc(2026, 6, 1, 8);
  return SyncMeta(
    ownerUserId: 'u-test',
    updatedAt: now,
    updatedByDevice: 'dev-test',
    hlc: Hlc(
      wallMillis: now.millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'dev-test',
    ),
  );
}
