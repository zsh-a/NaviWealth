import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_item_actions.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

final _created = DateTime.utc(2026, 8, 21);

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'user',
  updatedAt: _created,
  updatedByDevice: 'device',
  hlc: Hlc.zero('device'),
);

Widget _wrap(List<Object> items, {bool aiAvailable = true}) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: FTheme(
        data: FTheme.neutral.light.desktop,
        child: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Column(
              children: [
                for (final item in items)
                  Text(
                    knowledgeItemActions(
                      context: context,
                      ref: ref,
                      item: item,
                      aiAvailable: aiAvailable,
                    ).swipeActions.map((action) => action.label).join(' · '),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('context command persists a synchronized status transition', (
    tester,
  ) async {
    final AppDatabase db = makeTestDatabase();
    addTearDown(db.close);
    final repo = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
    final principle = KnowledgePrinciple(
      id: 'principle',
      statement: 'Prefer clarity',
      rationaleMd: '',
      scope: '*',
      status: PrincipleStatus.active,
      declaredAt: _created,
      sync: _meta(),
    );
    await repo.upsertPrinciple(principle);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          knowledgeRepositoryProvider.overrideWith((_) async => repo),
          mutationStamperProvider.overrideWith(
            (_) async => makeStubStamper(userId: 'user', deviceId: 'device'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: AppMessenger.init(
              child: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    final action = knowledgeItemActions(
                      context: context,
                      ref: ref,
                      item: principle,
                      aiAvailable: false,
                    ).swipeActions.last;
                    return FButton(
                      onPress: action.onPressed,
                      child: Text(action.label),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    final updated = await repo.findPrinciple(
      ownerUserId: 'user',
      id: principle.id,
    );
    expect(updated?.status, PrincipleStatus.paused);
  });

  testWidgets('maps every knowledge kind to edit plus a contextual command', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(<Object>[
        KnowledgeNote(
          id: 'note',
          title: 'Note',
          bodyMd: 'Body',
          tags: const <String>[],
          createdAt: _created,
          sync: _meta(),
        ),
        KnowledgeDecision(
          id: 'decision',
          question: 'Choose?',
          options: <DecisionOption>[],
          selectedLabel: '',
          rationaleMd: '',
          principleIds: const <String>[],
          assumptionIds: const <String>[],
          status: DecisionStatus.active,
          decidedAt: _created,
          sync: _meta(),
        ),
        KnowledgePrinciple(
          id: 'principle',
          statement: 'Prefer clarity',
          rationaleMd: '',
          scope: '*',
          status: PrincipleStatus.active,
          declaredAt: _created,
          sync: _meta(),
        ),
        KnowledgeAssumption(
          id: 'assumption',
          statement: 'Demand persists',
          confidence: 0.7,
          scope: '*',
          evidenceIds: const <String>[],
          status: AssumptionStatus.active,
          declaredAt: _created,
          sync: _meta(),
        ),
        KnowledgeConcept(
          id: 'concept',
          name: 'Optionality',
          aliases: const <String>[],
          summaryMd: 'Keep choices open.',
          relatedConceptIds: const <String>[],
          createdAt: _created,
          sync: _meta(),
        ),
        KnowledgeExperiment(
          id: 'experiment',
          hypothesis: 'A smaller batch is faster',
          methodMd: '',
          metrics: const <String>[],
          status: ExperimentStatus.planned,
          startedAt: _created,
          sync: _meta(),
        ),
        KnowledgeRoutine(
          id: 'routine',
          statement: 'Review quarterly',
          intervalDays: 90,
          nextDueAt: _created,
          scope: '*',
          status: RoutineStatus.active,
          createdAt: _created,
          sync: _meta(),
        ),
      ]),
    );

    expect(find.textContaining('AI organize'), findsOneWidget);
    expect(find.textContaining('Review'), findsOneWidget);
    expect(find.textContaining('Pause'), findsOneWidget);
    expect(find.textContaining('Verify'), findsOneWidget);
    expect(find.textContaining('Copy summary'), findsOneWidget);
    expect(find.textContaining('Start'), findsOneWidget);
    expect(find.textContaining('Done'), findsOneWidget);
  });

  testWidgets('status-driven commands change without changing row grammar', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(<Object>[
        KnowledgePrinciple(
          id: 'principle',
          statement: 'Prefer clarity',
          rationaleMd: '',
          scope: '*',
          status: PrincipleStatus.paused,
          declaredAt: _created,
          sync: _meta(),
        ),
        KnowledgeExperiment(
          id: 'experiment',
          hypothesis: 'A smaller batch is faster',
          methodMd: '',
          metrics: const <String>[],
          status: ExperimentStatus.running,
          startedAt: _created,
          sync: _meta(),
        ),
        KnowledgeRoutine(
          id: 'routine',
          statement: 'Review quarterly',
          intervalDays: 90,
          nextDueAt: _created,
          scope: '*',
          status: RoutineStatus.paused,
          createdAt: _created,
          sync: _meta(),
        ),
      ]),
    );

    expect(find.textContaining('Resume'), findsNWidgets(2));
    expect(find.textContaining('Record result'), findsOneWidget);
    expect(find.textContaining('Edit'), findsNWidgets(3));
  });
}
