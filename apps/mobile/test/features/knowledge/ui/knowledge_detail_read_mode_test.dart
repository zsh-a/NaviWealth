import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/visual/ai_markdown.dart';
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
import 'package:naviwealth/features/knowledge/ui/knowledge_note_detail_page.dart';
import 'package:naviwealth/features/knowledge/ui/widgets/knowledge_decision_options_editor.dart';
import 'package:naviwealth/features/knowledge/ui/widgets/knowledge_decision_status_badge.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

const _owner = 'knowledge-read-mode-user';

void main() {
  testWidgets('Note read mode renders content and guards the edit toggle', (
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
    await repository.upsertNote(_note());

    await tester.pumpWidget(_wrapNote('note-read', repository));
    await _settle(tester);

    // Rendered title, markdown body, tag chips, source link card, metadata.
    expect(find.text('Reading habits'), findsOneWidget);
    expect(find.byType(AiMarkdown), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('knowledge-note-tag-focus')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('knowledge-note-tag-deep work')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('knowledge-source-link')), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
    expect(find.text('Updated'), findsOneWidget);
    // The form stays hidden until the edit toggle is pressed.
    expect(find.byKey(const Key('knowledge-note-title')), findsNothing);

    await tester.tap(find.byKey(const Key('knowledge-note-edit-toggle')));
    await _settle(tester);
    expect(find.byKey(const Key('knowledge-note-title')), findsOneWidget);

    // Dirty edits must survive an accidental toggle back to read mode.
    await tester.enterText(
      find.byKey(const Key('knowledge-note-title')),
      'Unsaved draft',
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('knowledge-note-edit-toggle')));
    await _settle(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await _settle(tester);
    expect(find.text('Unsaved draft'), findsOneWidget);

    // Confirming the discard restores the pristine read view.
    await tester.tap(find.byKey(const Key('knowledge-note-edit-toggle')));
    await _settle(tester);
    await tester.tap(find.text('Discard'));
    await _settle(tester);
    expect(find.byKey(const Key('knowledge-note-title')), findsNothing);
    expect(find.text('Reading habits'), findsOneWidget);
    await _disposeWidget(tester);
  });

  testWidgets('Decision read mode renders options and tone-mapped status', (
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
    await repository.upsertDecision(_decision());

    await tester.pumpWidget(_wrapDecision('decision-read', repository));
    await _settle(tester);

    expect(find.text('Should we automate this workflow?'), findsOneWidget);
    // Tone-mapped status badge (falsified → error tone).
    final badge = tester.widget<KnowledgeDecisionStatusBadge>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is KnowledgeDecisionStatusBadge &&
                widget.status == DecisionStatus.falsified,
          )
          .first,
    );
    expect(knowledgeDecisionStatusStyle(badge.status).tone, AppBadgeTone.error);
    // Static options list with the selected option highlighted.
    expect(
      find.byKey(const ValueKey<String>('knowledge-decision-read-option-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('knowledge-decision-read-option-1')),
      findsOneWidget,
    );
    expect(find.text('Selected option'), findsOneWidget);
    expect(find.text('Lower setup cost but more recurring effort.'), findsOne);
    // Rendered rationale markdown and expected outcome.
    expect(find.byType(AiMarkdown), findsOneWidget);
    expect(find.text('Expected outcome'), findsOneWidget);
    expect(find.text('Reduce manual work'), findsOneWidget);
    expect(find.text('Decided'), findsOneWidget);
    // The edit form stays hidden until toggled.
    expect(find.byType(KnowledgeDecisionOptionsEditor), findsNothing);

    await tester.tap(find.byKey(const Key('knowledge-decision-edit-toggle')));
    await _settle(tester);
    expect(find.byType(KnowledgeDecisionOptionsEditor), findsOneWidget);
    await _disposeWidget(tester);
  });
}

Widget _base({required Widget home, required KnowledgeRepository repository}) =>
    ProviderScope(
      overrides: [
        knowledgeRepositoryProvider.overrideWith((_) async => repository),
        knowledgeOwnerUserIdProvider.overrideWith((_) async => _owner),
        mutationStamperProvider.overrideWith(
          (_) async => makeStubStamper(userId: _owner),
        ),
        lifeOpenActionCountProvider.overrideWith(
          (_) => const AsyncValue<int?>.data(null),
        ),
        lifeSourceActionReaderProvider.overrideWith(
          (_) =>
              (_) async => null,
        ),
        lifeActionDispatcherProvider.overrideWith(
          (_) =>
              (_) async => null,
        ),
        lifeActionRouteBuilderProvider.overrideWith((_) => null),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: FTheme(data: FTheme.neutral.light.desktop, child: home),
      ),
    );

Widget _wrapNote(String noteId, KnowledgeRepository repository) => _base(
  home: KnowledgeNoteDetailPage(noteId: noteId),
  repository: repository,
);

Widget _wrapDecision(String decisionId, KnowledgeRepository repository) =>
    _base(
      home: KnowledgeDecisionDetailPage(decisionId: decisionId),
      repository: repository,
    );

Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 75), EnginePhase.paint);
  }
}

Future<void> _disposeWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

KnowledgeNote _note() => KnowledgeNote(
  id: 'note-read',
  title: 'Reading habits',
  bodyMd: 'Notes on **deep work** and focus.',
  sourceUrl: 'https://example.com/deep-work',
  tags: const <String>['focus', 'deep work'],
  createdAt: _sync().updatedAt,
  sync: _sync(),
);

KnowledgeDecision _decision() => KnowledgeDecision(
  id: 'decision-read',
  question: 'Should we automate this workflow?',
  options: <DecisionOption>[
    DecisionOption(label: 'Proceed'),
    DecisionOption(
      label: 'Keep it manual',
      rationale: 'Lower setup cost but more recurring effort.',
    ),
  ],
  selectedLabel: 'Keep it manual',
  rationaleMd: 'The evidence supports a **small** rollout.',
  expectedOutcome: 'Reduce manual work',
  status: DecisionStatus.falsified,
  decidedAt: _sync().updatedAt,
  sync: _sync(),
);

SyncMeta _sync() {
  final now = DateTime.utc(2026, 8, 30, 10);
  return SyncMeta(
    ownerUserId: _owner,
    updatedAt: now,
    updatedByDevice: 'knowledge-read-device',
    hlc: Hlc(
      wallMillis: now.millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'knowledge-read-device',
    ),
  );
}
