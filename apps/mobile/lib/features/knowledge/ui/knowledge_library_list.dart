part of 'knowledge_library_page.dart';

class _LibraryList extends ConsumerWidget {
  const _LibraryList({
    required this.segment,
    required this.segmentLabel,
    required this.createLabel,
    required this.onCreate,
    required this.onSegmentChanged,
    required this.query,
    required this.showSearchAssist,
    required this.searchHistory,
    required this.onSearchSelected,
    required this.onSearchHistoryClear,
    required this.onSearchHistoryItemDelete,
    required this.onRefresh,
  });

  final _LibrarySegment segment;
  final String segmentLabel;
  final String createLabel;
  final VoidCallback onCreate;
  final ValueChanged<_LibrarySegment> onSegmentChanged;
  final String query;
  final bool showSearchAssist;
  final List<String> searchHistory;
  final ValueChanged<String> onSearchSelected;
  final VoidCallback onSearchHistoryClear;
  final ValueChanged<String> onSearchHistoryItemDelete;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(activeUserIdProvider);
    if (owner == null) return const AppListPageSkeleton(itemCount: 5);
    final repoAsync = ref.watch(knowledgeRepositoryProvider);
    final l10n = AppLocalizations.of(context);
    // Scope above the loading/data branches: pull-to-refresh reuses the
    // same entrance watermark, so refreshed rows don't replay the entrance.
    return AppEntranceScope(
      child: repoAsync.when(
        loading: () => const AppListPageSkeleton(itemCount: 5),
        error: (e, stackTrace) => AppEmptyState.error(
          title: userSafeErrorMessage(
            context,
            e,
            stackTrace: stackTrace,
            operation: 'load knowledge library',
          ),
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(knowledgeRepositoryProvider),
        ),
        data: (repo) => switch (segment) {
          _LibrarySegment.all => _segmentList<_LibraryEntry>(
            stream: _watchAllKnowledge(repo, ownerUserId: owner),
            searchableText: (entry) => entry.searchText,
            searchSuggestions: (context, entry) => [
              _segmentLabel(l10n, entry.segment),
              entry.status,
              ...entry.suggestions,
            ].whereType<String>().toList(growable: false),
            statusOf: (entry) => _segmentLabel(l10n, entry.segment),
            emptyIcon: FLucideIcons.library,
            emptyTitle: l10n.knowledgeLibraryEmptyAllTitle,
            emptyMessage: l10n.knowledgeLibraryEmptyAllBody,
            tileBuilder: (context, entry, query) => _buildAllTile(
              context,
              entry,
              query: query,
              onDelete: () => _deleteEntry(
                context: context,
                ref: ref,
                repo: repo,
                kind: entry.kind,
                id: entry.id,
                title: entry.title.isEmpty
                    ? AppLocalizations.of(context).knowledgeUntitled
                    : entry.title,
              ),
            ),
          ),
          _LibrarySegment.decisions => _segmentList<KnowledgeDecision>(
            stream: repo.watchDecisions(ownerUserId: owner),
            searchableText: (d) => [
              d.question,
              d.selectedLabel,
              d.rationaleMd,
              d.expectedOutcome,
            ].whereType<String>().join('\n'),
            searchSuggestions: (context, d) => [
              d.status.wire,
              d.selectedLabel,
              d.reviewDate == null
                  ? null
                  : knowledgeDate(context, d.reviewDate!),
            ].whereType<String>().toList(growable: false),
            emptyIcon: FLucideIcons.gitBranch,
            emptyTitle: l10n.knowledgeLibraryEmptyDecisionsTitle,
            emptyMessage: l10n.knowledgeLibraryEmptyDecisionsBody,
            statusOf: (d) => decisionStatusLabelOf(l10n, d.status),
            tileBuilder: (context, d, query) => _buildDecisionTile(
              context,
              d,
              query: query,
              onDelete: () => _deleteEntry(
                context: context,
                ref: ref,
                repo: repo,
                kind: KnowledgeEntryKind.decision,
                id: d.id,
                title: d.question,
              ),
            ),
          ),
          _LibrarySegment.principles => _segmentList<KnowledgePrinciple>(
            stream: repo.watchPrinciples(ownerUserId: owner),
            searchableText: (p) =>
                [p.statement, p.rationaleMd, p.scope, p.status.wire].join('\n'),
            searchSuggestions: (_, p) =>
                [p.status.wire, p.scope].toList(growable: false),
            emptyIcon: FLucideIcons.badgeCheck,
            emptyTitle: l10n.knowledgeLibraryEmptyPrinciplesTitle,
            emptyMessage: l10n.knowledgeLibraryEmptyPrinciplesBody,
            statusOf: (p) => principleStatusLabel(l10n, p.status),
            tileBuilder: (context, p, query) => _buildPrincipleTile(
              context,
              p,
              query: query,
              onDelete: () => _deleteEntry(
                context: context,
                ref: ref,
                repo: repo,
                kind: KnowledgeEntryKind.principle,
                id: p.id,
                title: p.statement,
              ),
            ),
          ),
          _LibrarySegment.assumptions => _segmentList<KnowledgeAssumption>(
            stream: repo.watchAssumptions(ownerUserId: owner),
            searchableText: (a) => [
              a.statement,
              a.scope,
              a.status.wire,
              a.confidence.toStringAsFixed(2),
            ].join('\n'),
            searchSuggestions: (_, a) => [
              a.status.wire,
              a.scope,
              a.confidence.toStringAsFixed(2),
            ],
            emptyIcon: FLucideIcons.lightbulb,
            emptyTitle: l10n.knowledgeLibraryEmptyAssumptionsTitle,
            emptyMessage: l10n.knowledgeLibraryEmptyAssumptionsBody,
            statusOf: (a) => assumptionStatusLabel(l10n, a.status),
            tileBuilder: (context, a, query) => _buildAssumptionTile(
              context,
              a,
              query: query,
              onDelete: () => _deleteEntry(
                context: context,
                ref: ref,
                repo: repo,
                kind: KnowledgeEntryKind.assumption,
                id: a.id,
                title: a.statement,
              ),
            ),
          ),
          _LibrarySegment.notes => _segmentList<KnowledgeNote>(
            stream: repo.watchNotes(ownerUserId: owner),
            searchableText: (n) => [
              n.title,
              n.bodyMd,
              n.projectTag,
              ...n.tags,
            ].whereType<String>().join('\n'),
            searchSuggestions: (_, n) => [
              n.projectTag,
              ...n.tags,
            ].whereType<String>().toList(growable: false),
            emptyIcon: FLucideIcons.fileText,
            emptyTitle: l10n.knowledgeLibraryEmptyNotesTitle,
            emptyMessage: l10n.knowledgeLibraryEmptyNotesBody,
            tileBuilder: (context, n, query) => _buildNoteTile(
              context,
              n,
              query: query,
              onDelete: () => _deleteEntry(
                context: context,
                ref: ref,
                repo: repo,
                kind: KnowledgeEntryKind.note,
                id: n.id,
                title: n.title.isEmpty
                    ? AppLocalizations.of(context).knowledgeUntitled
                    : n.title,
              ),
            ),
          ),
          _LibrarySegment.concepts => _segmentList<KnowledgeConcept>(
            stream: repo.watchConcepts(ownerUserId: owner),
            searchableText: (c) => [
              c.name,
              c.summaryMd,
              ...c.aliases,
            ].whereType<String>().join('\n'),
            searchSuggestions: (_, c) =>
                [c.name, ...c.aliases].toList(growable: false),
            emptyIcon: FLucideIcons.folderTree,
            emptyTitle: l10n.knowledgeLibraryEmptyConceptsTitle,
            emptyMessage: l10n.knowledgeLibraryEmptyConceptsBody,
            tileBuilder: (context, c, query) => _buildConceptTile(
              context,
              c,
              query: query,
              onDelete: () => _deleteEntry(
                context: context,
                ref: ref,
                repo: repo,
                kind: KnowledgeEntryKind.concept,
                id: c.id,
                title: c.name,
              ),
            ),
          ),
          _LibrarySegment.experiments => _segmentList<KnowledgeExperiment>(
            stream: repo.watchExperiments(ownerUserId: owner),
            searchableText: (e) => [
              e.hypothesis,
              e.methodMd,
              e.resultMd,
              ...e.metrics,
            ].whereType<String>().join('\n'),
            searchSuggestions: (_, e) =>
                [e.status.wire, ...e.metrics].toList(growable: false),
            emptyIcon: FLucideIcons.flaskConical,
            emptyTitle: l10n.knowledgeLibraryEmptyExperimentsTitle,
            emptyMessage: l10n.knowledgeLibraryEmptyExperimentsBody,
            statusOf: (e) => experimentStatusLabel(l10n, e.status),
            tileBuilder: (context, e, query) => _buildExperimentTile(
              context,
              e,
              query: query,
              onDelete: () => _deleteEntry(
                context: context,
                ref: ref,
                repo: repo,
                kind: KnowledgeEntryKind.experiment,
                id: e.id,
                title: e.hypothesis,
              ),
            ),
          ),
          _LibrarySegment.routines => _segmentList<KnowledgeRoutine>(
            stream: repo.watchRoutines(ownerUserId: owner),
            searchableText: (r) => [r.statement, r.scope].join('\n'),
            searchSuggestions: (_, r) =>
                [r.status.wire, r.scope].toList(growable: false),
            emptyIcon: FLucideIcons.calendarClock,
            emptyTitle: l10n.knowledgeLibraryEmptyRoutinesTitle,
            emptyMessage: l10n.knowledgeLibraryEmptyRoutinesBody,
            statusOf: (r) => routineStatusLabel(l10n, r.status),
            tileBuilder: (context, r, query) => _buildRoutineTile(
              context,
              r,
              query: query,
              onDelete: () => _deleteEntry(
                context: context,
                ref: ref,
                repo: repo,
                kind: KnowledgeEntryKind.routine,
                id: r.id,
                title: r.statement,
              ),
            ),
          ),
        },
      ),
    );
  }

  Widget _segmentList<T>({
    required Stream<List<T>> stream,
    required String Function(T item) searchableText,
    required List<String> Function(BuildContext context, T item)
    searchSuggestions,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyMessage,
    required Widget Function(BuildContext context, T item, String query)
    tileBuilder,
    String Function(T item)? statusOf,
  }) {
    return _SegmentList<T>(
      storageKey: segment.name,
      stream: stream,
      query: query,
      showSearchAssist: showSearchAssist,
      scopeLabel: segmentLabel,
      createLabel: createLabel,
      onCreate: onCreate,
      onSearchAll: segment == _LibrarySegment.all
          ? null
          : () => onSegmentChanged(_LibrarySegment.all),
      searchableText: searchableText,
      searchSuggestions: searchSuggestions,
      emptyIcon: emptyIcon,
      emptyTitle: emptyTitle,
      emptyMessage: emptyMessage,
      statusOf: statusOf,
      searchHistory: searchHistory,
      onSearchSelected: onSearchSelected,
      onSearchHistoryClear: onSearchHistoryClear,
      onSearchHistoryItemDelete: onSearchHistoryItemDelete,
      onRefresh: onRefresh,
      tileBuilder: tileBuilder,
    );
  }
}
