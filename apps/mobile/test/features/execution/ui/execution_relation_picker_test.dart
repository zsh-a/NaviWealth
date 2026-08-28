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
  test('relation selection keeps commitment and project ids consistent', () {
    final commitments = [
      ExecutionCommitment(
        id: 'commit-1',
        title: 'Weekly execution review',
        projectId: 'proj-1',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(),
      ),
      ExecutionCommitment(
        id: 'commit-independent',
        title: 'Independent promise',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(),
      ),
    ];

    expect(
      executionRelationAfterCommitmentPick(
        commitments: commitments,
        currentProjectId: null,
        pickedCommitmentId: 'commit-1',
      ),
      (projectId: 'proj-1', commitmentId: 'commit-1'),
    );
    expect(
      executionRelationAfterProjectPick(
        commitments: commitments,
        currentCommitmentId: 'commit-1',
        pickedProjectId: 'proj-2',
      ),
      (projectId: 'proj-2', commitmentId: null),
    );
    expect(
      executionRelationAfterCommitmentPick(
        commitments: commitments,
        currentProjectId: 'proj-2',
        pickedCommitmentId: 'commit-independent',
      ),
      (projectId: 'proj-2', commitmentId: 'commit-independent'),
    );
    expect(
      executionRelationAfterCommitmentPick(
        commitments: commitments,
        currentProjectId: 'proj-2',
        pickedCommitmentId: kExecutionPickerNone,
      ),
      (projectId: 'proj-2', commitmentId: null),
    );
  });

  testWidgets('project picker supports search and selection', (tester) async {
    String? picked;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => FButton(
            onPress: () async {
              picked = await showExecutionProjectPicker(
                context: context,
                projects: [
                  for (var i = 0; i < 8; i++)
                    ExecutionProject(
                      id: 'project-$i',
                      title: i == 6 ? 'Execution polish' : 'Project $i',
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
    await tester.enterText(find.byType(TextField), 'polish');
    await tester.pumpAndSettle();

    expect(find.text('Execution polish'), findsOneWidget);
    expect(find.text('Project 1'), findsNothing);

    await tester.tap(find.text('Execution polish'));
    await tester.pumpAndSettle();

    expect(picked, 'project-6');
  });
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
