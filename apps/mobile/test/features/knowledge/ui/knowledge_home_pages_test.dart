import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_search_service.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_inbox_page.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_library_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('Inbox focuses due reviews and recent Notes', (tester) async {
    final notes = List<KnowledgeNote>.generate(
      10,
      (index) => _note('note-$index', 'Note $index', index),
    );
    final due = _decision(
      id: 'due',
      question: 'Review this decision',
      reviewDate: DateTime.utc(2020),
      status: DecisionStatus.active,
      tick: 20,
    );
    final future = _decision(
      id: 'future',
      question: 'Future review',
      reviewDate: DateTime.utc(2099),
      status: DecisionStatus.active,
      tick: 21,
    );
    final complete = _decision(
      id: 'complete',
      question: 'Already verified',
      reviewDate: DateTime.utc(2020),
      status: DecisionStatus.verified,
      tick: 22,
    );

    await tester.pumpWidget(
      _wrap(
        const KnowledgeInboxPage(),
        notes: notes,
        decisions: <KnowledgeDecision>[due, future, complete],
      ),
    );
    await _settlePaint(tester);

    expect(find.text('Due for review'), findsOneWidget);
    expect(find.text('Recent notes'), findsOneWidget);
    expect(find.text('Review this decision'), findsOneWidget);
    expect(find.text('Future review'), findsNothing);
    expect(find.text('Already verified'), findsNothing);
    expect(find.text('Note 0'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
  });

  testWidgets('Library searches across Notes and Decisions with a type scope', (
    tester,
  ) async {
    final note = _note('note', 'Local note', 1);
    final decision = _decision(
      id: 'decision',
      question: 'Local decision',
      status: DecisionStatus.active,
      tick: 2,
    );
    KnowledgeLibrarySearchRequest? lastRequest;
    final result = KnowledgeSearchHit(
      document: KnowledgeSearchDocument.fromDecision(decision),
      score: 0.9,
      semanticScore: null,
      semanticSim: null,
      lexicalScore: 0.9,
      matchedFields: const <String>['title'],
    );

    await tester.pumpWidget(
      _wrap(
        const KnowledgeLibraryPage(),
        notes: <KnowledgeNote>[note],
        decisions: <KnowledgeDecision>[decision],
        search: (request) {
          lastRequest = request;
          return <KnowledgeSearchHit>[result];
        },
      ),
    );
    await _settlePaint(tester);

    expect(find.text('Local note'), findsOneWidget);
    expect(find.text('Local decision'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('knowledge-library-search')),
      'decision',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _settlePaint(tester);

    expect(lastRequest?.query, 'decision');
    expect(lastRequest?.kind, isNull);
    expect(lastRequest?.tag, isNull);
    expect(find.text('Local note'), findsNothing);
    expect(find.text('Local decision'), findsOneWidget);

    await tester.tap(find.text('Decisions'));
    await _settlePaint(tester);

    expect(lastRequest?.kind, 'decision');
    expect(lastRequest?.tag, isNull);
  });

  testWidgets('Library tag facets filter browse and compose with search', (
    tester,
  ) async {
    final workNote = _note(
      'work-note',
      'Quarterly plan',
      1,
      tags: const <String>['work', 'planning'],
    );
    final personalNote = _note(
      'personal-note',
      'Weekend ideas',
      2,
      tags: const <String>['personal'],
    );
    final decision = _decision(
      id: 'decision',
      question: 'Choose next project',
      status: DecisionStatus.active,
      tick: 3,
    );
    KnowledgeLibrarySearchRequest? lastRequest;
    final result = KnowledgeSearchHit(
      document: KnowledgeSearchDocument.fromNote(workNote),
      score: 1,
      semanticScore: null,
      semanticSim: null,
      lexicalScore: 1,
      matchedFields: const <String>['title'],
    );

    await tester.pumpWidget(
      _wrap(
        const KnowledgeLibraryPage(),
        notes: <KnowledgeNote>[workNote, personalNote],
        decisions: <KnowledgeDecision>[decision],
        search: (request) {
          lastRequest = request;
          return <KnowledgeSearchHit>[result];
        },
      ),
    );
    await _settlePaint(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-library-tag-work')),
    );
    await _settlePaint(tester);

    expect(find.text('Quarterly plan'), findsOneWidget);
    expect(find.text('Weekend ideas'), findsNothing);
    expect(find.text('Choose next project'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('knowledge-library-search')),
      'plan',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _settlePaint(tester);

    expect(lastRequest?.query, 'plan');
    expect(lastRequest?.kind, 'note');
    expect(lastRequest?.tag, 'work');

    await tester.tap(find.text('Decisions'));
    await _settlePaint(tester);

    expect(lastRequest?.kind, 'decision');
    expect(lastRequest?.tag, isNull);
  });
}

Future<void> _settlePaint(WidgetTester tester) async {
  for (var index = 0; index < 8; index++) {
    await tester.pump(const Duration(milliseconds: 50), EnginePhase.paint);
  }
}

Widget _wrap(
  Widget child, {
  required List<KnowledgeNote> notes,
  required List<KnowledgeDecision> decisions,
  List<KnowledgeSearchHit> Function(KnowledgeLibrarySearchRequest request)?
  search,
}) {
  return ProviderScope(
    overrides: [
      knowledgeNotesProvider.overrideWith((_) => Stream.value(notes)),
      knowledgeDecisionsProvider.overrideWith((_) => Stream.value(decisions)),
      if (search != null)
        knowledgeLibrarySearchProvider.overrideWith(
          (_, request) async => search(request),
        ),
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

KnowledgeNote _note(
  String id,
  String title,
  int tick, {
  List<String> tags = const <String>['work'],
}) => KnowledgeNote(
  id: id,
  title: title,
  bodyMd: 'Body for $title',
  tags: tags,
  createdAt: _sync(tick).updatedAt,
  sync: _sync(tick),
);

KnowledgeDecision _decision({
  required String id,
  required String question,
  required DecisionStatus status,
  required int tick,
  DateTime? reviewDate,
}) => KnowledgeDecision(
  id: id,
  question: question,
  options: <DecisionOption>[DecisionOption(label: 'Proceed')],
  selectedLabel: 'Proceed',
  rationaleMd: 'Rationale',
  reviewDate: reviewDate,
  status: status,
  decidedAt: _sync(tick).updatedAt,
  sync: _sync(tick),
);

SyncMeta _sync(int tick) {
  final now = DateTime.utc(2026, 8, 30, 10, 0, tick);
  return SyncMeta(
    ownerUserId: 'knowledge-home-user',
    updatedAt: now,
    updatedByDevice: 'knowledge-device',
    hlc: Hlc(
      wallMillis: now.millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'knowledge-device',
    ),
  );
}
