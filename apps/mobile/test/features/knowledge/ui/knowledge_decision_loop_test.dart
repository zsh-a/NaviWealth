import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/lifeos/action_dispatcher.dart';
import 'package:naviwealth/core/product/product_metrics.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_decision_detail_page.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_decision_from_note_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

const _owner = 'knowledge-decision-loop-user';

void main() {
  testWidgets('Note to Decision to Action to Review remains source-linked', (
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
    final note = _note();
    await repository.upsertNote(note);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final metrics = ProductMetricsController(preferences);
    await metrics.setEnabled(true);

    String? decisionId;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => FButton(
            onPress: () async {
              decisionId = await showKnowledgeDecisionFromNoteSheet(
                context: context,
                note: note,
              );
            },
            child: const Text('Start decision'),
          ),
        ),
        repository: repository,
        metrics: metrics,
        executionAvailable: false,
      ),
    );
    await tester.tap(find.text('Start decision'));
    await _settle(tester);
    await _enter(
      tester,
      const ValueKey<String>('knowledge-decision-from-note-question'),
      'Should we automate this workflow?',
    );
    await _enter(
      tester,
      const ValueKey<String>('knowledge-decision-from-note-label-0'),
      'Run a pilot',
    );
    final addOption = find.byKey(
      const ValueKey<String>('knowledge-decision-from-note-add'),
    );
    await tester.ensureVisible(addOption);
    await tester.pump(const Duration(milliseconds: 75), EnginePhase.paint);
    await tester.tap(addOption);
    await _settle(tester);
    await _enter(
      tester,
      const ValueKey<String>('knowledge-decision-from-note-label-1'),
      'Keep it manual',
    );
    await _enter(
      tester,
      const ValueKey<String>('knowledge-decision-from-note-rationale-0'),
      'A pilot is reversible and produces evidence.',
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>('knowledge-decision-from-note-select-0'),
      ),
    );
    await tester.tap(
      find.byKey(const Key('knowledge-decision-from-note-submit')),
    );
    await _settle(tester);

    expect(decisionId, isNotNull);
    final created = await repository.findDecision(
      ownerUserId: _owner,
      id: decisionId!,
    );
    final relations = await repository.listRelationsForObject(
      ownerUserId: _owner,
      kind: KnowledgeEntryKind.decision.name,
      id: decisionId!,
    );
    expect(created?.selectedLabel, 'Run a pilot');
    expect(created?.options, hasLength(2));
    expect(relations.single.fromId, note.id);
    expect(relations.single.relation, KnowledgeRelationType.informs);

    LifeLinkedAction? linked;
    await tester.pumpWidget(
      _wrap(
        KnowledgeDecisionDetailPage(decisionId: decisionId!),
        repository: repository,
        metrics: metrics,
        executionAvailable: true,
        readLinkedAction: (_) async => linked,
        dispatchAction: (draft) async {
          expect(draft.sourceDomain, 'knowledge');
          expect(draft.sourceRowFamily, 'know:knowledge_decisions');
          expect(draft.sourceRowId, decisionId);
          linked = const LifeLinkedAction(
            id: 'loop-action',
            state: LifeActionState.done,
          );
          return linked!.id;
        },
      ),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('knowledge-decision-create-action')));
    await _settle(tester);
    await tester.tap(find.text('Create action').last);
    await _settle(tester);

    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.byKey(const Key('knowledge-decision-review')));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const Key('knowledge-decision-review-actual')),
      'The pilot removed the repetitive handoff.',
    );
    final statusControl = find.byKey(
      const Key('knowledge-decision-review-status'),
    );
    await tester.tap(
      find.descendant(of: statusControl, matching: find.text('Active')),
    );
    await _settle(tester);
    await tester.tap(find.text('Verified').last);
    await _settle(tester);
    await tester.tap(find.byKey(const Key('knowledge-decision-review-submit')));
    await _settle(tester);

    final reviewed = await repository.findDecision(
      ownerUserId: _owner,
      id: decisionId!,
    );
    expect(reviewed?.status, DecisionStatus.verified);
    expect(
      reviewed?.actualOutcomeMd,
      'The pilot removed the repetitive handoff.',
    );

    final totals =
        metrics.exportAggregates()['totals']! as Map<String, Object?>;
    expect(
      totals[ProductFunnelEvent.knowledgeDecisionCreated.name],
      containsPair('count', 1),
    );
    expect(
      totals[ProductFunnelEvent.knowledgeDecisionActionCreated.name],
      containsPair('count', 1),
    );
    expect(
      totals[ProductFunnelEvent.knowledgeDecisionReviewed.name],
      containsPair('count', 1),
    );
    expect(
      preferences.getString('naviwealth.product_metrics.aggregates.v5'),
      isNot(contains('pilot removed')),
      reason: 'product evidence must never contain Knowledge text',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}

Widget _wrap(
  Widget child, {
  required KnowledgeRepository repository,
  required ProductMetricsController metrics,
  required bool executionAvailable,
  LifeSourceActionReader? readLinkedAction,
  LifeActionDispatcher? dispatchAction,
}) {
  return ProviderScope(
    overrides: [
      knowledgeRepositoryProvider.overrideWith((ref) async => repository),
      knowledgeOwnerUserIdProvider.overrideWith((ref) async => _owner),
      mutationStamperProvider.overrideWith(
        (ref) async => makeStubStamper(userId: _owner),
      ),
      productMetricsProvider.overrideWith((ref) => metrics),
      lifeOpenActionCountProvider.overrideWith(
        (ref) => AsyncValue<int?>.data(executionAvailable ? 0 : null),
      ),
      lifeSourceActionReaderProvider.overrideWith(
        (ref) => readLinkedAction ?? (_) async => null,
      ),
      lifeActionDispatcherProvider.overrideWith(
        (ref) => dispatchAction ?? (_) async => null,
      ),
      lifeActionRouteBuilderProvider.overrideWith((ref) => null),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: FTheme(
        data: FTheme.neutral.light.desktop,
        child: Scaffold(body: child),
      ),
    ),
  );
}

Future<void> _enter(WidgetTester tester, Key key, String text) async {
  final field = find.byKey(key);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pump(const Duration(milliseconds: 75), EnginePhase.paint);
  tester.testTextInput.enterText(text);
  await tester.pump(const Duration(milliseconds: 75), EnginePhase.paint);
}

Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 14; index++) {
    await tester.pump(const Duration(milliseconds: 75), EnginePhase.paint);
  }
}

KnowledgeNote _note() => KnowledgeNote(
  id: 'source-note',
  title: 'Workflow evidence',
  bodyMd: 'The current handoff is repetitive and measurable.',
  tags: const <String>['work'],
  createdAt: _sync(1).updatedAt,
  sync: _sync(1),
);

SyncMeta _sync(int tick) {
  final now = DateTime.utc(2026, 8, 30, 10, 0, tick);
  return SyncMeta(
    ownerUserId: _owner,
    updatedAt: now,
    updatedByDevice: 'knowledge-loop-device',
    hlc: Hlc(
      wallMillis: now.millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'knowledge-loop-device',
    ),
  );
}
