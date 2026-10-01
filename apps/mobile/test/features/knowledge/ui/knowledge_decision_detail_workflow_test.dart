import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/forms/date_field.dart';
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
import 'package:naviwealth/features/knowledge/ui/knowledge_inbox_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

const _owner = 'knowledge-decision-workflow-user';

void main() {
  testWidgets('review draft stays intact when dismissal is cancelled', (
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
    await tester.tap(find.byKey(const Key('knowledge-decision-review')));
    await _settlePaint(tester);
    await tester.enterText(
      find.byKey(const Key('knowledge-decision-review-actual')),
      'Preserve my review',
    );
    await tester.tapAt(const Offset(4, 4));
    await _settlePaint(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.unsavedChangesTitle), findsOneWidget);
    await tester.tap(find.text(l10n.unsavedChangesKeepEditing));
    await _settlePaint(tester);
    expect(find.text('Preserve my review'), findsOneWidget);
    expect(
      (await repository.findDecision(
        ownerUserId: _owner,
        id: decision.id,
      ))?.actualOutcomeMd,
      isNull,
    );
    await _disposeWidget(tester);
  });
  testWidgets(
    'failed review preserves input and locks dismissal until commit',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final database = makeTestDatabase();
      addTearDown(database.close);
      final repository = _DelayedKnowledgeRepository(
        db: database,
        outbox: InMemoryOutboxStore(),
      );
      final decision = _decision(
        reviewDate: DateTime.now().toUtc().add(const Duration(days: 30)),
      );
      await repository.upsertDecision(decision);
      await tester.pumpWidget(
        _wrap(
          decisionId: decision.id,
          repository: repository,
          executionAvailable: false,
        ),
      );
      await _settlePaint(tester);
      await tester.tap(find.byKey(const Key('knowledge-decision-review')));
      await _settlePaint(tester);
      await tester.enterText(
        find.byKey(const Key('knowledge-decision-review-actual')),
        'Preserved after failure',
      );
      await _settlePaint(tester);
      repository.gate = Completer<void>();
      final submit = find.byKey(const Key('knowledge-decision-review-submit'));
      await tester.tap(submit);
      await _settlePaint(tester);
      expect(repository.attempts, 1);
      await tester.binding.handlePopRoute();
      await _settlePaint(tester);
      expect(find.text('Discard changes?'), findsNothing);
      expect(
        find.byKey(const Key('knowledge-decision-review-actual')),
        findsOneWidget,
      );
      expect(tester.widget<FButton>(submit).onPress, isNull);
      repository.gate!.completeError(
        StateError('internal private storage path'),
      );
      await _settlePaint(tester);
      expect(find.text('Preserved after failure'), findsOneWidget);
      expect(find.byType(AppStatusBanner), findsWidgets);
      expect(
        find.textContaining('internal private storage path'),
        findsNothing,
      );
      expect(
        (await repository.findDecision(
          ownerUserId: _owner,
          id: decision.id,
        ))?.actualOutcomeMd,
        isNull,
      );
      repository.gate = null;
      await tester.tap(submit);
      await _settlePaint(tester);
      expect(repository.attempts, 2);
      expect(
        find.byKey(const Key('knowledge-decision-review-actual')),
        findsNothing,
      );
      expect(
        (await repository.findDecision(
          ownerUserId: _owner,
          id: decision.id,
        ))?.actualOutcomeMd,
        'Preserved after failure',
      );
      await _disposeWidget(tester);
    },
  );

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

    await tester.tap(
      find.byKey(const Key('knowledge-decision-review-details')),
    );
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

  testWidgets(
    'scheduling leads with the date and does not submit unchanged fields',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
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
      await tester.tap(find.byKey(const Key('knowledge-decision-review')));
      await _settlePaint(tester);
      final date = find.byKey(const Key('knowledge-decision-review-date'));
      final actual = find.byKey(const Key('knowledge-decision-review-actual'));
      final submit = find.byKey(const Key('knowledge-decision-review-submit'));
      expect(date, findsOneWidget);
      expect(
        tester.getTopLeft(date).dy,
        lessThan(tester.getTopLeft(actual).dy),
      );
      expect(tester.widget<FButton>(submit).onPress, isNull);
      final now = DateTime.now();
      final scheduled = DateTime(now.year, now.month, now.day + 7).toUtc();
      tester.widget<DateField>(date).onChanged!(scheduled);
      await _settlePaint(tester);
      await tester.tap(submit);
      await _settlePaint(tester);
      final saved = await repository.findDecision(
        ownerUserId: _owner,
        id: decision.id,
      );
      expect(saved!.reviewDate!.toUtc(), scheduled.toUtc());
      expect(saved.actualOutcomeMd, isNull);
      await _disposeWidget(tester);
    },
  );

  testWidgets(
    'continuing an overdue review requires a future date and clears the due list',
    (tester) async {
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
      await tester.tap(find.byKey(const Key('knowledge-decision-review')));
      await _settlePaint(tester);
      final actual = find.byKey(const Key('knowledge-decision-review-actual'));
      final submit = find.byKey(const Key('knowledge-decision-review-submit'));
      expect(tester.widget<FButton>(submit).onPress, isNull);
      await tester.enterText(actual, 'More observation needed');
      await _settlePaint(tester);
      await tester.tap(submit);
      await _settlePaint(tester);
      expect(
        find.text('Choose a future date to continue observing.'),
        findsOneWidget,
      );
      expect(
        (await repository.findDecision(
          ownerUserId: _owner,
          id: decision.id,
        ))!.actualOutcomeMd,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('knowledge-review-next-7')));
      await _settlePaint(tester);
      await tester.tap(submit);
      await _settlePaint(tester);
      final saved = await repository.findDecision(
        ownerUserId: _owner,
        id: decision.id,
      );
      expect(saved!.actualOutcomeMd, 'More observation needed');
      expect(saved.status, DecisionStatus.active);
      expect(saved.reviewDate!.toUtc().isAfter(DateTime.now().toUtc()), isTrue);
      expect(
        await repository.listDueReviews(
          ownerUserId: _owner,
          asOf: DateTime.now().toUtc(),
        ),
        isEmpty,
      );
      await _disposeWidget(tester);
    },
  );

  testWidgets(
    'Inbox reviews a due decision directly and removes completed work',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
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
          child: const KnowledgeInboxPage(),
        ),
      );
      await _settlePaint(tester);
      await tester.tap(
        find.byKey(ValueKey('knowledge-inbox-start-review-${decision.id}')),
      );
      await _settlePaint(tester);
      await tester.enterText(
        find.byKey(const Key('knowledge-decision-review-actual')),
        'Completed from Inbox',
      );
      await tester.tap(find.text('Verified').hitTestable());
      await _settlePaint(tester);
      await tester.tap(
        find.byKey(const Key('knowledge-decision-review-submit')),
      );
      await _settlePaint(tester);
      final saved = await repository.findDecision(
        ownerUserId: _owner,
        id: decision.id,
      );
      expect(saved?.actualOutcomeMd, 'Completed from Inbox');
      expect(saved?.status, DecisionStatus.verified);
      expect(
        find.byKey(ValueKey('knowledge-inbox-review-${decision.id}')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await _disposeWidget(tester);
    },
  );

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

    // The detail page opens in read mode; switch to the edit form first.
    await tester.tap(find.byKey(const Key('knowledge-decision-edit-toggle')));
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
  Widget? child,
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
        child: child ?? KnowledgeDecisionDetailPage(decisionId: decisionId),
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

class _DelayedKnowledgeRepository extends KnowledgeRepository {
  _DelayedKnowledgeRepository({required super.db, required super.outbox});
  Completer<void>? gate;
  int attempts = 0;
  @override
  Future<void> upsertDecision(KnowledgeDecision decision) async {
    if (decision.actualOutcomeMd != null) {
      attempts++;
      await gate?.future;
    }
    await super.upsertDecision(decision);
  }
}
