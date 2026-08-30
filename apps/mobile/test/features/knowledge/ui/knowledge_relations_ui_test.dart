import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_search_service.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_decision_from_note_sheet.dart';
import 'package:naviwealth/features/knowledge/ui/widgets/knowledge_relations_section.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

const _owner = 'knowledge-relations-user';

void main() {
  testWidgets('links, displays, and removes related knowledge', (tester) async {
    final database = makeTestDatabase();
    addTearDown(database.close);
    final repository = KnowledgeRepository(
      db: database,
      outbox: InMemoryOutboxStore(),
    );
    final source = _note('source', 'Source evidence', 1);
    final candidate = _note('candidate', 'Follow-up evidence', 2);
    final decision = _decision('decision', 3);
    await repository.upsertNote(source);
    await repository.upsertNote(candidate);
    await repository.upsertDecision(decision);
    await repository.upsertRelation(
      KnowledgeRelation(
        id: knowledgeRelationId(
          fromKind: KnowledgeEntryKind.note.name,
          fromId: source.id,
          relation: KnowledgeRelationType.informs,
          toKind: KnowledgeEntryKind.decision.name,
          toId: decision.id,
        ),
        fromKind: KnowledgeEntryKind.note.name,
        fromId: source.id,
        relation: KnowledgeRelationType.informs,
        toKind: KnowledgeEntryKind.decision.name,
        toId: decision.id,
        createdAt: _sync(4).updatedAt,
        sync: _sync(4),
      ),
    );

    await tester.pumpWidget(
      _wrap(
        KnowledgeRelationsSection(
          subjectKind: KnowledgeEntryKind.decision,
          subjectId: decision.id,
        ),
        repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Source evidence'), findsOneWidget);
    expect(find.textContaining('Source note'), findsOneWidget);

    await tester.tap(find.byKey(const Key('knowledge-relations-add')));
    await _settleSheet(tester);
    expect(
      find.byKey(const ValueKey('knowledge-relation-target-note:candidate')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('knowledge-relation-target-note:source')),
      findsNothing,
    );

    await tester.tap(find.text('Follow-up evidence'));
    await _settleSheet(tester);
    expect(find.text('Follow-up evidence'), findsOneWidget);
    expect(find.textContaining('Related note'), findsOneWidget);

    final relationId = knowledgeRelationId(
      fromKind: KnowledgeEntryKind.decision.name,
      fromId: decision.id,
      relation: KnowledgeRelationType.relatedTo,
      toKind: KnowledgeEntryKind.note.name,
      toId: candidate.id,
    );
    await tester.tap(
      find.byKey(ValueKey('knowledge-relation-remove-$relationId')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Follow-up evidence'), findsNothing);
    expect(
      await repository.findRelation(ownerUserId: _owner, id: relationId),
      isNotNull,
    );
    expect(
      (await repository.findRelation(
        ownerUserId: _owner,
        id: relationId,
      ))?.sync.deletedAt,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('creates a Decision with its source Note relation', (
    tester,
  ) async {
    final database = makeTestDatabase();
    addTearDown(database.close);
    final repository = KnowledgeRepository(
      db: database,
      outbox: InMemoryOutboxStore(),
    );
    final source = _note('source', 'Source evidence', 1);
    await repository.upsertNote(source);
    String? createdId;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => FButton(
            onPress: () async {
              createdId = await showKnowledgeDecisionFromNoteSheet(
                context: context,
                note: source,
              );
            },
            child: const Text('Open'),
          ),
        ),
        repository,
      ),
    );
    await tester.tap(find.text('Open'));
    await _settleSheet(tester);

    await _enterTextWithoutSemantics(
      tester,
      find.byKey(const Key('knowledge-decision-from-note-question')),
      'Should we proceed?',
    );
    await _enterTextWithoutSemantics(
      tester,
      find.byKey(const Key('knowledge-decision-from-note-selection')),
      'Proceed',
    );
    await tester.tap(
      find.byKey(const Key('knowledge-decision-from-note-submit')),
    );
    await _settleSheet(tester);

    expect(createdId, isNotNull);
    final created = await repository.findDecision(
      ownerUserId: _owner,
      id: createdId!,
    );
    final relations = await repository.listRelationsForObject(
      ownerUserId: _owner,
      kind: KnowledgeEntryKind.decision.name,
      id: createdId!,
    );
    expect(created?.question, 'Should we proceed?');
    expect(created?.selectedLabel, 'Proceed');
    expect(relations.single.relation, KnowledgeRelationType.informs);
    expect(relations.single.fromId, source.id);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('discovers and explicitly links similar knowledge', (
    tester,
  ) async {
    final database = makeTestDatabase();
    addTearDown(database.close);
    final repository = KnowledgeRepository(
      db: database,
      outbox: InMemoryOutboxStore(),
    );
    final source = _note('source', 'Source evidence', 1);
    final candidate = _note('candidate', 'Similar evidence', 2);
    final existing = _note('existing', 'Already linked', 3);
    await repository.upsertNote(source);
    await repository.upsertNote(candidate);
    await repository.upsertNote(existing);
    await repository.upsertRelation(
      KnowledgeRelation(
        id: knowledgeRelationId(
          fromKind: KnowledgeEntryKind.note.name,
          fromId: source.id,
          relation: KnowledgeRelationType.relatedTo,
          toKind: KnowledgeEntryKind.note.name,
          toId: existing.id,
        ),
        fromKind: KnowledgeEntryKind.note.name,
        fromId: source.id,
        relation: KnowledgeRelationType.relatedTo,
        toKind: KnowledgeEntryKind.note.name,
        toId: existing.id,
        createdAt: _sync(4).updatedAt,
        sync: _sync(4),
      ),
    );
    final suggestions = <KnowledgeSimilarityHit>[
      KnowledgeSimilarityHit(
        document: KnowledgeSearchDocument.fromNote(existing),
        similarity: 0.94,
        tokenOverlap: 0.5,
        source: 'know:notes',
      ),
      KnowledgeSimilarityHit(
        document: KnowledgeSearchDocument.fromNote(candidate),
        similarity: 0.91,
        tokenOverlap: 0.4,
        source: 'know:notes',
      ),
    ];

    await tester.pumpWidget(
      _wrap(
        KnowledgeRelationsSection(
          subjectKind: KnowledgeEntryKind.note,
          subjectId: source.id,
        ),
        repository,
        suggestions: suggestions,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('knowledge-relations-discover')));
    await _settleSheet(tester);
    expect(
      find.byKey(
        const ValueKey('knowledge-relation-suggestion-link-note:candidate'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('knowledge-relation-suggestion-link-note:existing'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('knowledge-relation-suggestion-link-note:candidate'),
      ),
    );
    await _settleSheet(tester);

    final relationId = knowledgeRelationId(
      fromKind: KnowledgeEntryKind.note.name,
      fromId: source.id,
      relation: KnowledgeRelationType.relatedTo,
      toKind: KnowledgeEntryKind.note.name,
      toId: candidate.id,
    );
    final linked = await repository.findRelation(
      ownerUserId: _owner,
      id: relationId,
    );
    expect(linked, isNotNull);
    expect(linked?.sync.deletedAt, isNull);
    expect(find.text('All suggestions are linked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}

Future<void> _settleSheet(WidgetTester tester) async {
  for (var index = 0; index < 8; index++) {
    await tester.pump(const Duration(milliseconds: 100), EnginePhase.paint);
  }
}

Future<void> _enterTextWithoutSemantics(
  WidgetTester tester,
  Finder finder,
  String value,
) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100), EnginePhase.paint);
  tester.testTextInput.enterText(value);
  await tester.pump(const Duration(milliseconds: 100), EnginePhase.paint);
}

Widget _wrap(
  Widget child,
  KnowledgeRepository repository, {
  List<KnowledgeSimilarityHit> suggestions = const <KnowledgeSimilarityHit>[],
}) {
  return ProviderScope(
    overrides: [
      knowledgeRepositoryProvider.overrideWith((_) async => repository),
      knowledgeOwnerUserIdProvider.overrideWith((_) async => _owner),
      knowledgeRelationSuggestionsProvider.overrideWith(
        (_, _) async => suggestions,
      ),
      mutationStamperProvider.overrideWith(
        (_) async => makeStubStamper(userId: _owner),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: FTheme(
        data: FTheme.neutral.light.desktop,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: child,
          ),
        ),
      ),
    ),
  );
}

KnowledgeNote _note(String id, String title, int tick) => KnowledgeNote(
  id: id,
  title: title,
  bodyMd: 'Body for $title',
  createdAt: _sync(tick).updatedAt,
  sync: _sync(tick),
);

KnowledgeDecision _decision(String id, int tick) => KnowledgeDecision(
  id: id,
  question: 'Choose a direction?',
  options: <DecisionOption>[DecisionOption(label: 'Proceed')],
  selectedLabel: 'Proceed',
  rationaleMd: 'Because the evidence supports it.',
  status: DecisionStatus.active,
  decidedAt: _sync(tick).updatedAt,
  sync: _sync(tick),
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
