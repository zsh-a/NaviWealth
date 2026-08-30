import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/lifeos/action_dispatcher.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_decision_detail_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

const _owner = 'knowledge-decision-workflow-user';

void main() {
  testWidgets('reviews a due Decision and persists its outcome', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = makeTestDatabase();
    addTearDown(database.close);
    final repository = KnowledgeRepository(
      db: database,
      outbox: InMemoryOutboxStore(),
    );
    final decision = _decision(reviewDate: DateTime.utc(2020));
    await repository.upsertDecision(decision);

    await tester.pumpWidget(
      _wrap(
        decisionId: decision.id,
        repository: repository,
        executionAvailable: false,
      ),
    );
    await _settlePaint(tester);

    expect(find.text('Review now'), findsOneWidget);
    await tester.tap(find.byKey(const Key('knowledge-decision-review')));
    await _settlePaint(tester);

    await tester.enterText(
      find.byKey(const Key('knowledge-decision-review-conditions')),
      'Revenue drops\nThe vendor changes terms',
    );
    await tester.enterText(
      find.byKey(const Key('knowledge-decision-review-actual')),
      'The rollout met its target.',
    );
    final statusControl = find.byKey(
      const Key('knowledge-decision-review-status'),
    );
    await tester.tap(
      find.descendant(of: statusControl, matching: find.text('Active')),
    );
    await _settlePaint(tester);
    await tester.tap(find.text('Verified').last);
    await _settlePaint(tester);
    await tester.tap(find.byKey(const Key('knowledge-decision-review-submit')));
    await _settlePaint(tester);

    final saved = await repository.findDecision(
      ownerUserId: _owner,
      id: decision.id,
    );
    expect(saved?.actualOutcomeMd, 'The rollout met its target.');
    expect(
      saved?.revisitConditions.map((condition) => condition.statement),
      <String>['Revenue drops', 'The vendor changes terms'],
    );
    expect(saved?.reviewDate?.year, 2020);
    expect(saved?.reviewDate?.month, 1);
    expect(saved?.reviewDate?.day, 1);
    expect(saved?.status, DecisionStatus.verified);
    await _disposeWidget(tester);
  });

  testWidgets('creates one source-linked Action from a Decision', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = makeTestDatabase();
    addTearDown(database.close);
    final repository = KnowledgeRepository(
      db: database,
      outbox: InMemoryOutboxStore(),
    );
    final decision = _decision(expectedOutcome: 'Reduce manual work');
    await repository.upsertDecision(decision);
    LifeActionDraft? captured;
    LifeLinkedAction? linked;

    await tester.pumpWidget(
      _wrap(
        decisionId: decision.id,
        repository: repository,
        executionAvailable: true,
        readLinkedAction: (_) async => linked,
        dispatchAction: (draft) async {
          captured = draft;
          linked = const LifeLinkedAction(
            id: 'action-1',
            state: LifeActionState.todo,
          );
          return linked!.id;
        },
      ),
    );
    await _settlePaint(tester);

    await tester.tap(find.byKey(const Key('knowledge-decision-create-action')));
    await _settlePaint(tester);
    await tester.tap(find.text('Create action').last);
    await _settlePaint(tester);

    expect(captured?.title, 'Proceed');
    expect(captured?.sourceDomain, 'knowledge');
    expect(captured?.sourceRowFamily, 'know:knowledge_decisions');
    expect(captured?.sourceRowId, decision.id);
    expect(captured?.sourceLabelSnapshot, decision.question);
    expect(captured?.note, contains('Reduce manual work'));
    expect(find.text('Open action'), findsOneWidget);
    await _disposeWidget(tester);
  });

  testWidgets('edits alternatives and persists an explicit selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = makeTestDatabase();
    addTearDown(database.close);
    final repository = KnowledgeRepository(
      db: database,
      outbox: InMemoryOutboxStore(),
    );
    final decision = _decision();
    await repository.upsertDecision(decision);

    await tester.pumpWidget(
      _wrap(
        decisionId: decision.id,
        repository: repository,
        executionAvailable: false,
      ),
    );
    await _settlePaint(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-decision-detail-add')),
    );
    await _settlePaint(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('knowledge-decision-detail-label-1'),
        ),
        matching: find.byType(EditableText),
      ),
      'Keep it manual',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('knowledge-decision-detail-rationale-1'),
        ),
        matching: find.byType(EditableText),
      ),
      'Lower setup cost but more recurring effort.',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-decision-detail-select-1')),
    );
    await tester.tap(find.text('Save').hitTestable());
    await _settlePaint(tester);

    final saved = await repository.findDecision(
      ownerUserId: _owner,
      id: decision.id,
    );
    expect(saved?.selectedLabel, 'Keep it manual');
    expect(saved?.options.map((option) => option.label), <String>[
      'Proceed',
      'Keep it manual',
    ]);
    expect(
      saved?.options.last.rationale,
      'Lower setup cost but more recurring effort.',
    );
    await _disposeWidget(tester);
  });
}

Widget _wrap({
  required String decisionId,
  required KnowledgeRepository repository,
  required bool executionAvailable,
  LifeSourceActionReader? readLinkedAction,
  LifeActionDispatcher? dispatchAction,
}) {
  return ProviderScope(
    overrides: [
      knowledgeRepositoryProvider.overrideWith((_) async => repository),
      knowledgeOwnerUserIdProvider.overrideWith((_) async => _owner),
      mutationStamperProvider.overrideWith(
        (_) async => makeStubStamper(userId: _owner),
      ),
      lifeOpenActionCountProvider.overrideWith(
        (_) => AsyncValue<int?>.data(executionAvailable ? 0 : null),
      ),
      lifeSourceActionReaderProvider.overrideWith(
        (_) => readLinkedAction ?? (_) async => null,
      ),
      lifeActionDispatcherProvider.overrideWith(
        (_) => dispatchAction ?? (_) async => null,
      ),
      lifeActionRouteBuilderProvider.overrideWith((_) => null),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: FTheme(
        data: FTheme.neutral.light.desktop,
        child: KnowledgeDecisionDetailPage(decisionId: decisionId),
      ),
    ),
  );
}

Future<void> _settlePaint(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 75), EnginePhase.paint);
  }
}

Future<void> _disposeWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

KnowledgeDecision _decision({DateTime? reviewDate, String? expectedOutcome}) =>
    KnowledgeDecision(
      id: 'decision-1',
      question: 'Should we automate this workflow?',
      options: <DecisionOption>[DecisionOption(label: 'Proceed')],
      selectedLabel: 'Proceed',
      rationaleMd: 'The evidence supports a small rollout.',
      expectedOutcome: expectedOutcome,
      reviewDate: reviewDate,
      status: DecisionStatus.active,
      decidedAt: _sync(1).updatedAt,
      sync: _sync(1),
    );

SyncMeta _sync(int tick) {
  final now = DateTime.utc(2026, 8, 30, 10, 0, tick);
  return SyncMeta(
    ownerUserId: _owner,
    updatedAt: now,
    updatedByDevice: 'knowledge-device',
    hlc: Hlc(
      wallMillis: now.millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'knowledge-device',
    ),
  );
}
