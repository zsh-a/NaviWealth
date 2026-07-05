part of 'knowledge_library_page.dart';

enum _LibrarySegment {
  all,
  decisions,
  principles,
  assumptions,
  notes,
  concepts,
  experiments,
  routines,
}

IconData _segmentIcon(_LibrarySegment segment) => switch (segment) {
  _LibrarySegment.all => FLucideIcons.library,
  _LibrarySegment.decisions => FLucideIcons.gitBranch,
  _LibrarySegment.principles => FLucideIcons.badgeCheck,
  _LibrarySegment.assumptions => FLucideIcons.lightbulb,
  _LibrarySegment.notes => FLucideIcons.fileText,
  _LibrarySegment.concepts => FLucideIcons.folderTree,
  _LibrarySegment.experiments => FLucideIcons.flaskConical,
  _LibrarySegment.routines => FLucideIcons.calendarClock,
};

enum KnowledgeLibraryDateFilter { all, today, week, month, outsideMonth }

const String _kKnowledgeLibrarySearchHistoryPrefsKey =
    'knowledge.library.search_history.v1';
const int _kKnowledgeLibrarySearchHistoryLimit = 6;

List<String> _normalizedSearchHistory(Iterable<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final item in raw) {
    final value = item.trim();
    if (value.length < 2) continue;
    final key = value.toLowerCase();
    if (!seen.add(key)) continue;
    out.add(value);
    if (out.length >= _kKnowledgeLibrarySearchHistoryLimit) break;
  }
  return out;
}

String _segmentLabel(AppLocalizations l10n, _LibrarySegment segment) {
  return switch (segment) {
    _LibrarySegment.all => l10n.knowledgeSegmentAll,
    _LibrarySegment.decisions => l10n.knowledgeSegmentDecisions,
    _LibrarySegment.principles => l10n.knowledgeSegmentPrinciples,
    _LibrarySegment.assumptions => l10n.knowledgeSegmentAssumptions,
    _LibrarySegment.notes => l10n.knowledgeSegmentNotes,
    _LibrarySegment.concepts => l10n.knowledgeSegmentConcepts,
    _LibrarySegment.experiments => l10n.knowledgeSegmentExperiments,
    _LibrarySegment.routines => l10n.knowledgeSegmentRoutines,
  };
}

String _dateFilterLabel(
  AppLocalizations l10n,
  KnowledgeLibraryDateFilter filter,
) {
  return switch (filter) {
    KnowledgeLibraryDateFilter.all => l10n.knowledgeLibraryDateFilterAll,
    KnowledgeLibraryDateFilter.today => l10n.knowledgeLibraryDateFilterToday,
    KnowledgeLibraryDateFilter.week => l10n.knowledgeLibraryDateFilterWeek,
    KnowledgeLibraryDateFilter.month => l10n.knowledgeLibraryDateFilterMonth,
    KnowledgeLibraryDateFilter.outsideMonth =>
      l10n.knowledgeLibraryDateFilterOutsideMonth,
  };
}

/// Weighted search: ranks prefix matches above substring matches, and
/// suggestion-field matches above full-text matches. Returns items
/// sorted by relevance (best first), filtered to only matching items.
List<T> _rankedSearch<T>({
  required List<T> items,
  required String query,
  required String Function(T item) searchableText,
  required List<String> Function(T item) searchSuggestions,
}) {
  final scored = <(T, double)>[];
  for (final item in items) {
    final score = _searchRelevanceScore(
      query: query,
      fullText: searchableText(item),
      suggestions: searchSuggestions(item),
    );
    if (score > 0) scored.add((item, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored.map((e) => e.$1).toList(growable: false);
}

/// Returns a relevance score > 0 if the item matches, 0 otherwise.
/// Higher is better.
double _searchRelevanceScore({
  required String query,
  required String fullText,
  required List<String> suggestions,
}) {
  final lowerQuery = query.toLowerCase();
  final lowerFull = fullText.toLowerCase();

  // No match at all.
  if (!lowerFull.contains(lowerQuery)) return 0;

  double score = 1; // Base: substring match in full text.

  // Boost for matching in suggestion fields (title, status, tags).
  for (final s in suggestions) {
    final lower = s.toLowerCase();
    if (lower.contains(lowerQuery)) {
      score += 2;
      if (lower.startsWith(lowerQuery)) score += 3;
    }
  }

  // Boost for prefix match in full text.
  if (lowerFull.startsWith(lowerQuery)) score += 2;

  return score;
}

class _LibraryEntry {
  const _LibraryEntry({
    required this.kind,
    required this.segment,
    required this.id,
    required this.title,
    required this.date,
    required this.searchText,
    required this.suggestions,
    required this.facets,
    required this.value,
    this.status,
  });

  final KnowledgeEntryKind kind;
  final _LibrarySegment segment;
  final String id;
  final String title;
  final DateTime date;
  final String searchText;
  final List<String> suggestions;
  final List<String> facets;
  final Object value;
  final String? status;
}

Stream<List<_LibraryEntry>> _watchAllKnowledge(
  KnowledgeRepository repo, {
  required String ownerUserId,
}) {
  late StreamController<List<_LibraryEntry>> controller;
  final latest = List<List<_LibraryEntry>?>.filled(7, null);
  final subscriptions = <StreamSubscription<Object?>>[];

  void emitIfReady() {
    if (latest.any((items) => items == null)) return;
    final entries = [for (final items in latest) ...items!]
      ..sort((a, b) => b.date.compareTo(a.date));
    controller.add(entries);
  }

  void listen<T>(
    int index,
    Stream<List<T>> stream,
    List<_LibraryEntry> Function(List<T> items) map,
  ) {
    subscriptions.add(
      stream.listen((items) {
        latest[index] = map(items);
        emitIfReady();
      }, onError: controller.addError),
    );
  }

  controller = StreamController<List<_LibraryEntry>>(
    onListen: () {
      listen<KnowledgeDecision>(
        0,
        repo.watchDecisions(ownerUserId: ownerUserId),
        (items) => [
          for (final d in items)
            _LibraryEntry(
              kind: KnowledgeEntryKind.decision,
              segment: _LibrarySegment.decisions,
              id: d.id,
              title: d.question,
              date: d.decidedAt,
              status: d.status.wire,
              searchText: [
                d.question,
                d.selectedLabel,
                d.rationaleMd,
                d.expectedOutcome,
              ].whereType<String>().join('\n'),
              suggestions: [
                d.question,
                d.status.wire,
                d.selectedLabel,
              ].where((value) => value.isNotEmpty).toList(growable: false),
              facets: [d.status.wire],
              value: d,
            ),
        ],
      );
      listen<KnowledgePrinciple>(
        1,
        repo.watchPrinciples(ownerUserId: ownerUserId),
        (items) => [
          for (final p in items)
            _LibraryEntry(
              kind: KnowledgeEntryKind.principle,
              segment: _LibrarySegment.principles,
              id: p.id,
              title: p.statement,
              date: p.declaredAt,
              status: p.status.wire,
              searchText: [
                p.statement,
                p.rationaleMd,
                p.scope,
                p.status.wire,
              ].join('\n'),
              suggestions: [p.statement, p.status.wire, p.scope],
              facets: [p.status.wire, p.scope],
              value: p,
            ),
        ],
      );
      listen<KnowledgeAssumption>(
        2,
        repo.watchAssumptions(ownerUserId: ownerUserId),
        (items) => [
          for (final a in items)
            _LibraryEntry(
              kind: KnowledgeEntryKind.assumption,
              segment: _LibrarySegment.assumptions,
              id: a.id,
              title: a.statement,
              date: a.declaredAt,
              status: a.status.wire,
              searchText: [
                a.statement,
                a.scope,
                a.status.wire,
                a.confidence.toStringAsFixed(2),
              ].join('\n'),
              suggestions: [
                a.statement,
                a.status.wire,
                a.scope,
                a.confidence.toStringAsFixed(2),
              ],
              facets: [a.status.wire, a.scope],
              value: a,
            ),
        ],
      );
      listen<KnowledgeNote>(
        3,
        repo.watchNotes(ownerUserId: ownerUserId),
        (items) => [
          for (final n in items)
            _LibraryEntry(
              kind: KnowledgeEntryKind.note,
              segment: _LibrarySegment.notes,
              id: n.id,
              title: n.title,
              date: n.createdAt,
              searchText: [
                n.title,
                n.bodyMd,
                n.projectTag,
                ...n.tags,
              ].whereType<String>().join('\n'),
              suggestions: [
                n.title,
                n.projectTag,
                ...n.tags,
              ].whereType<String>().toList(growable: false),
              facets: [
                n.projectTag,
                ...n.tags,
              ].whereType<String>().toList(growable: false),
              value: n,
            ),
        ],
      );
      listen<KnowledgeConcept>(
        4,
        repo.watchConcepts(ownerUserId: ownerUserId),
        (items) => [
          for (final c in items)
            _LibraryEntry(
              kind: KnowledgeEntryKind.concept,
              segment: _LibrarySegment.concepts,
              id: c.id,
              title: c.name,
              date: c.createdAt,
              searchText: [
                c.name,
                c.summaryMd,
                ...c.aliases,
              ].whereType<String>().join('\n'),
              suggestions: [c.name, ...c.aliases],
              facets: [...c.aliases],
              value: c,
            ),
        ],
      );
      listen<KnowledgeExperiment>(
        5,
        repo.watchExperiments(ownerUserId: ownerUserId),
        (items) => [
          for (final e in items)
            _LibraryEntry(
              kind: KnowledgeEntryKind.experiment,
              segment: _LibrarySegment.experiments,
              id: e.id,
              title: e.hypothesis,
              date: e.startedAt,
              status: e.status.wire,
              searchText: [
                e.hypothesis,
                e.methodMd,
                e.resultMd,
                ...e.metrics,
              ].whereType<String>().join('\n'),
              suggestions: [e.hypothesis, e.status.wire, ...e.metrics],
              facets: [e.status.wire, ...e.metrics],
              value: e,
            ),
        ],
      );
      listen<KnowledgeRoutine>(
        6,
        repo.watchRoutines(ownerUserId: ownerUserId),
        (items) => [
          for (final r in items)
            _LibraryEntry(
              kind: KnowledgeEntryKind.routine,
              segment: _LibrarySegment.routines,
              id: r.id,
              title: r.statement,
              date: r.nextDueAt,
              status: r.status.wire,
              searchText: [r.statement, r.scope, r.status.wire].join('\n'),
              suggestions: [r.statement, r.status.wire, r.scope],
              facets: [r.status.wire, r.scope],
              value: r,
            ),
        ],
      );
    },
    onCancel: () async {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    },
  );

  return controller.stream;
}

bool matchesKnowledgeLibraryDateFilter(
  DateTime date,
  KnowledgeLibraryDateFilter filter,
  DateTime now,
) {
  if (filter == KnowledgeLibraryDateFilter.all) return true;
  final dateLocal = date.toLocal();
  final nowLocal = now.toLocal();
  final localDate = DateTime(dateLocal.year, dateLocal.month, dateLocal.day);
  final localNow = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final days = localDate.difference(localNow).inDays.abs();
  return switch (filter) {
    KnowledgeLibraryDateFilter.all => true,
    KnowledgeLibraryDateFilter.today => days == 0,
    KnowledgeLibraryDateFilter.week => days <= 7,
    KnowledgeLibraryDateFilter.month => days <= 30,
    KnowledgeLibraryDateFilter.outsideMonth => days > 30,
  };
}
