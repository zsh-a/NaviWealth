import 'dart:async';

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
    expect(find.text('8'), findsNothing); // A preview count is not a total.
  });

  testWidgets('Inbox renders note subtitles as plain-text excerpts', (
    tester,
  ) async {
    final note = KnowledgeNote(
      id: 'markdown-note',
      title: 'Markdown note',
      bodyMd: '**Bold claim** with `code` inline',
      tags: const <String>['work'],
      createdAt: _sync(1).updatedAt,
      sync: _sync(1),
    );

    await tester.pumpWidget(
      _wrap(
        const KnowledgeInboxPage(),
        notes: <KnowledgeNote>[note],
        decisions: const <KnowledgeDecision>[],
      ),
    );
    await _settlePaint(tester);

    expect(find.text('Bold claim with code inline'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
  });

  testWidgets('Inbox keeps notes usable when reviews fail', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const KnowledgeInboxPage(),
        notes: [_note('kept', 'Available note', 1)],
        decisions: const [],
        reviewsStream: Stream.error(StateError('review unavailable')),
      ),
    );
    await _settlePaint(tester);
    expect(find.text('Available note'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Inbox is empty'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inbox keeps due work usable when notes fail', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const KnowledgeInboxPage(),
        notes: const [],
        decisions: [
          _decision(
            id: 'due',
            question: 'Available review',
            reviewDate: DateTime.utc(2020),
            status: DecisionStatus.active,
            tick: 1,
          ),
        ],
        notesStream: Stream.error(StateError('notes unavailable')),
      ),
    );
    await _settlePaint(tester);
    expect(find.text('Available review'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inbox previews three reviews and expands the complete list', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const KnowledgeInboxPage(),
        notes: [_note('note', 'Recent capture', 1)],
        decisions: List.generate(
          5,
          (i) => _decision(
            id: 'due-$i',
            question: 'Review $i',
            reviewDate: DateTime.utc(2020),
            status: DecisionStatus.active,
            tick: i,
          ),
        ),
      ),
    );
    await _settlePaint(tester);
    expect(find.text('Review 3'), findsNothing);
    await tester.scrollUntilVisible(find.text('Show all 5 reviews'), 100);
    await tester.tap(find.text('Show all 5 reviews'));
    await _settlePaint(tester);
    await tester.scrollUntilVisible(find.text('Review 4'), 100);
    expect(find.text('Review 4'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Show fewer reviews'), 100);
    await tester.tap(find.text('Show fewer reviews'));
    await _settlePaint(tester);
    expect(find.text('Review 4'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inbox refresh waits for both independent sections', (
    tester,
  ) async {
    final notes = StreamController<List<KnowledgeNote>>.broadcast();
    final reviews = StreamController<List<KnowledgeDecision>>.broadcast();
    addTearDown(notes.close);
    addTearDown(reviews.close);
    await tester.pumpWidget(
      _wrap(
        const KnowledgeInboxPage(),
        notes: const [],
        decisions: const [],
        notesStream: notes.stream,
        reviewsStream: reviews.stream,
      ),
    );
    await tester.pump();
    notes.add(const []);
    reviews.add(const []);
    await _settlePaint(tester);
    var completed = false;
    final refresh = tester
        .widget<BriefLazyListScaffold>(find.byType(BriefLazyListScaffold))
        .onRefresh!()
        .then((_) => completed = true);
    await tester.pump();
    notes.add([_note('new', 'Refreshed note', 2)]);
    await _settlePaint(tester);
    expect(completed, isFalse);
    reviews.add(const []);
    await _settlePaint(tester);
    await refresh;
    expect(completed, isTrue);
  });

  testWidgets('Library loads the next window without jumping to the top', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const KnowledgeLibraryPage(),
        notes: [
          for (var i = 0; i < 60; i++) _note('page-$i', 'Page note $i', 60 - i),
        ],
        decisions: const [],
      ),
    );
    await _settlePaint(tester);
    await tester.scrollUntilVisible(
      find.text('Load more'),
      500,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 50,
    );
    await _settlePaint(tester);
    final before = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position
        .pixels;
    await tester.tap(find.text('Load more'));
    await _settlePaint(tester);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .pixels,
      closeTo(before, 1),
    );
    await tester.scrollUntilVisible(
      find.text('Page note 59'),
      400,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 30,
    );
    expect(find.text('Page note 59'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
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
  Stream<List<KnowledgeNote>>? notesStream,
  Stream<List<KnowledgeDecision>>? reviewsStream,
}) {
  return ProviderScope(
    overrides: [
      knowledgeLibraryNotesProvider.overrideWith(
        (_, request) => Stream.value(
          notes
              .where(
                (note) =>
                    request.tag == null || note.tags.contains(request.tag),
              )
              .take(request.limit + 1)
              .toList(),
        ),
      ),
      knowledgeLibraryDecisionsProvider.overrideWith(
        (_, limit) => Stream.value(decisions.take(limit + 1).toList()),
      ),
      knowledgeLibraryTagsProvider.overrideWith(
        (_) => Stream.value(notes.expand((note) => note.tags).toSet().toList()),
      ),
      knowledgeNotesProvider.overrideWith(
        (_) => notesStream ?? Stream.value(notes),
      ),
      knowledgeDueReviewsProvider.overrideWith(
        (_) =>
            reviewsStream ??
            Stream.value(
              decisions
                  .where(
                    (decision) =>
                        decision.reviewDate != null &&
                        !decision.reviewDate!.isAfter(DateTime.now()) &&
                        {
                          DecisionStatus.active,
                          DecisionStatus.draft,
                          DecisionStatus.paused,
                        }.contains(decision.status),
                  )
                  .toList(),
            ),
      ),
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
