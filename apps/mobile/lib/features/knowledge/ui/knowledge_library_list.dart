part of 'knowledge_library_page.dart';

class _LibraryList extends ConsumerWidget {
  const _LibraryList({
    required this.segment,
    required this.query,
    required this.searchHistory,
    required this.onSearchSelected,
    required this.onSearchHistoryClear,
    required this.onSearchHistoryItemDelete,
    required this.onRefresh,
  });

  final _LibrarySegment segment;
  final String query;
  final List<String> searchHistory;
  final ValueChanged<String> onSearchSelected;
  final VoidCallback onSearchHistoryClear;
  final ValueChanged<String> onSearchHistoryItemDelete;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) {
          return const KnowledgeLoadingState();
        }
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        final l10n = AppLocalizations.of(context);
        return repoAsync.when(
          loading: () => const KnowledgeLoadingState(),
          error: (e, _) => KnowledgeErrorState(
            title: l10n.knowledgeLibraryLoadFailed('$e'),
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
              filterFacets: (context, entry) => [...entry.facets],
              dateOf: (entry) => entry.date,
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
              filterFacets: (_, _) => const <String>[],
              dateOf: (d) => d.decidedAt,
              emptyIcon: FLucideIcons.gitBranch,
              emptyTitle: l10n.knowledgeLibraryEmptyDecisionsTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyDecisionsBody,
              statusOf: (d) => d.status.wire,
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
              searchableText: (p) => [
                p.statement,
                p.rationaleMd,
                p.scope,
                p.status.wire,
              ].join('\n'),
              searchSuggestions: (_, p) =>
                  [p.status.wire, p.scope].toList(growable: false),
              filterFacets: (_, p) => [p.scope],
              dateOf: (p) => p.declaredAt,
              emptyIcon: FLucideIcons.badgeCheck,
              emptyTitle: l10n.knowledgeLibraryEmptyPrinciplesTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyPrinciplesBody,
              statusOf: (p) => p.status.wire,
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
              filterFacets: (_, a) => [a.scope],
              dateOf: (a) => a.declaredAt,
              emptyIcon: FLucideIcons.lightbulb,
              emptyTitle: l10n.knowledgeLibraryEmptyAssumptionsTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyAssumptionsBody,
              statusOf: (a) => a.status.wire,
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
              filterFacets: (_, n) =>
                  [n.projectTag, ...n.tags].whereType<String>().toList(),
              dateOf: (n) => n.createdAt,
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
              filterFacets: (_, c) => [...c.aliases],
              dateOf: (c) => c.createdAt,
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
              filterFacets: (_, e) => [...e.metrics],
              dateOf: (e) => e.startedAt,
              emptyIcon: FLucideIcons.flaskConical,
              emptyTitle: l10n.knowledgeLibraryEmptyExperimentsTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyExperimentsBody,
              statusOf: (e) => e.status.wire,
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
              filterFacets: (_, r) => [r.scope],
              dateOf: (r) => r.nextDueAt,
              emptyIcon: FLucideIcons.calendarClock,
              emptyTitle: l10n.knowledgeLibraryEmptyRoutinesTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyRoutinesBody,
              statusOf: (r) => r.status.wire,
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
        );
      },
    );
  }

  Widget _segmentList<T>({
    required Stream<List<T>> stream,
    required String Function(T item) searchableText,
    required List<String> Function(BuildContext context, T item)
    searchSuggestions,
    required List<String> Function(BuildContext context, T item) filterFacets,
    required DateTime Function(T item)? dateOf,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyMessage,
    required Widget Function(BuildContext context, T item, String query)
    tileBuilder,
    String Function(T item)? statusOf,
  }) {
    return _SegmentList<T>(
      stream: stream,
      query: query,
      searchableText: searchableText,
      searchSuggestions: searchSuggestions,
      filterFacets: filterFacets,
      dateOf: dateOf,
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

/// Generic Library segment list. Collapses the 4 per-type list
/// widgets that all did the same StreamBuilder → empty → ListView
/// dance, differing only in row layout (which is the [tileBuilder]
/// callback). Adding a 5th segment (Principle / Assumption browse)
/// is now a one-liner.
class _SegmentList<T> extends StatefulWidget {
  const _SegmentList({
    required this.stream,
    required this.query,
    required this.searchableText,
    required this.searchSuggestions,
    required this.filterFacets,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.tileBuilder,
    required this.searchHistory,
    required this.onSearchSelected,
    required this.onSearchHistoryClear,
    this.onSearchHistoryItemDelete,
    required this.onRefresh,
    required this.dateOf,
    this.statusOf,
  });

  final Stream<List<T>> stream;
  final String query;
  final String Function(T item) searchableText;
  final List<String> Function(BuildContext context, T item) searchSuggestions;
  final List<String> Function(BuildContext context, T item) filterFacets;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final Widget Function(BuildContext, T, String query) tileBuilder;
  final List<String> searchHistory;
  final ValueChanged<String> onSearchSelected;
  final VoidCallback onSearchHistoryClear;
  final ValueChanged<String>? onSearchHistoryItemDelete;
  final Future<void> Function() onRefresh;
  final DateTime Function(T item)? dateOf;
  final String Function(T item)? statusOf;

  @override
  State<_SegmentList<T>> createState() => _SegmentListState<T>();
}

class _SegmentListState<T> extends State<_SegmentList<T>> {
  String? _statusFilter;
  String? _facetFilter;
  KnowledgeLibraryDateFilter _dateFilter = KnowledgeLibraryDateFilter.all;

  @override
  void didUpdateWidget(covariant _SegmentList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emptyTitle != widget.emptyTitle) {
      _statusFilter = null;
      _facetFilter = null;
      _dateFilter = KnowledgeLibraryDateFilter.all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final normalizedQuery = widget.query.trim().toLowerCase();
    return StreamBuilder<List<T>>(
      stream: widget.stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return KnowledgeErrorState(
            title: l10n.knowledgeLibraryLoadFailed('${snap.error}'),
          );
        }
        final items = snap.data ?? <T>[];
        if (items.isEmpty) {
          return KnowledgeEmptyState(
            icon: widget.emptyIcon,
            title: widget.emptyTitle,
            message: widget.emptyMessage,
          );
        }

        final statusOf = widget.statusOf;
        final statuses = <String>[];
        if (statusOf != null) {
          statuses.addAll(items.map(statusOf).toSet());
          statuses.sort();
        }
        if (_statusFilter != null && !statuses.contains(_statusFilter)) {
          _statusFilter = null;
        }
        final facets = _facetsFor(context, items);
        if (_facetFilter != null && !facets.contains(_facetFilter)) {
          _facetFilter = null;
        }
        final searchAssist = _SearchAssistRow(
          history: widget.searchHistory,
          suggestions: _suggestionsFor(context, items, normalizedQuery),
          query: normalizedQuery,
          onSelected: widget.onSearchSelected,
          onHistoryClear: widget.onSearchHistoryClear,
          onHistoryItemDelete: widget.onSearchHistoryItemDelete,
        );

        final statusFilteredItems = _statusFilter == null || statusOf == null
            ? items
            : items
                  .where((item) => statusOf(item) == _statusFilter)
                  .toList(growable: false);
        final facetedItems = _facetFilter == null
            ? statusFilteredItems
            : statusFilteredItems
                  .where(
                    (item) => widget
                        .filterFacets(context, item)
                        .contains(_facetFilter),
                  )
                  .toList(growable: false);
        final dateOf = widget.dateOf;
        final dateFilteredItems =
            dateOf == null || _dateFilter == KnowledgeLibraryDateFilter.all
            ? facetedItems
            : facetedItems
                  .where(
                    (item) => matchesKnowledgeLibraryDateFilter(
                      dateOf(item),
                      _dateFilter,
                      DateTime.now(),
                    ),
                  )
                  .toList(growable: false);

        final visibleItems = normalizedQuery.isEmpty
            ? dateFilteredItems
            : _rankedSearch(
                items: dateFilteredItems,
                query: normalizedQuery,
                searchableText: widget.searchableText,
                searchSuggestions: (item) =>
                    widget.searchSuggestions(context, item),
              );

        if (visibleItems.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchAssist,
              if (searchAssist.hasContent)
                const SizedBox(height: AppSpacing.s8),
              if (statuses.length > 1) ...[
                _FilterChipRow(
                  icon: FLucideIcons.listFilter,
                  values: statuses,
                  selected: _statusFilter,
                  onChanged: (status) => setState(() => _statusFilter = status),
                ),
                const SizedBox(height: AppSpacing.s12),
              ],
              if (dateOf != null) ...[
                _DateFilterChipRow(
                  selected: _dateFilter,
                  onChanged: (filter) => setState(() => _dateFilter = filter),
                ),
                const SizedBox(height: AppSpacing.s12),
              ],
              if (facets.isNotEmpty) ...[
                _FilterChipRow(
                  icon: FLucideIcons.tags,
                  values: facets,
                  selected: _facetFilter,
                  onChanged: (facet) => setState(() => _facetFilter = facet),
                ),
                const SizedBox(height: AppSpacing.s12),
              ],
              Expanded(
                child: KnowledgeEmptyState(
                  icon: FLucideIcons.search,
                  title: l10n.knowledgeLibrarySearchEmptyTitle,
                  message: l10n.knowledgeLibrarySearchEmptyBody,
                ),
              ),
            ],
          );
        }

        final list = KnowledgePullToRefresh(
          onRefresh: widget.onRefresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: visibleItems.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
            itemBuilder: (context, i) =>
                widget.tileBuilder(context, visibleItems[i], widget.query),
          ),
        );
        final filterRows = <Widget>[
          if (statuses.length > 1)
            _FilterChipRow(
              icon: FLucideIcons.listFilter,
              values: statuses,
              selected: _statusFilter,
              onChanged: (status) => setState(() => _statusFilter = status),
            ),
          if (dateOf != null)
            _DateFilterChipRow(
              selected: _dateFilter,
              onChanged: (filter) => setState(() => _dateFilter = filter),
            ),
          if (facets.isNotEmpty)
            _FilterChipRow(
              icon: FLucideIcons.tags,
              values: facets,
              selected: _facetFilter,
              onChanged: (facet) => setState(() => _facetFilter = facet),
            ),
        ];
        if (filterRows.isEmpty) {
          if (!searchAssist.hasContent) return list;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchAssist,
              const SizedBox(height: AppSpacing.s8),
              Expanded(child: list),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            searchAssist,
            if (searchAssist.hasContent) const SizedBox(height: AppSpacing.s8),
            for (var i = 0; i < filterRows.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.s8),
              filterRows[i],
            ],
            if (filterRows.isNotEmpty) const SizedBox(height: AppSpacing.s12),
            Expanded(child: list),
          ],
        );
      },
    );
  }

  List<String> _suggestionsFor(
    BuildContext context,
    List<T> items,
    String query,
  ) {
    return rankKnowledgeSearchSuggestions(
      weightedSuggestions: [
        for (final item in items) ...widget.searchSuggestions(context, item),
      ],
      searchableTexts: [for (final item in items) widget.searchableText(item)],
      query: query,
    );
  }

  List<String> _facetsFor(BuildContext context, List<T> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final item in items) {
      for (final raw in widget.filterFacets(context, item)) {
        final value = raw.trim();
        if (value.length < 2) continue;
        if (!seen.add(value.toLowerCase())) continue;
        out.add(value);
        if (out.length >= 12) return out;
      }
    }
    out.sort();
    return out;
  }
}

Future<void> _refreshKnowledgeRepository(WidgetRef ref) async {
  ref.invalidate(knowledgeRepositoryProvider);
  await ref.read(knowledgeRepositoryProvider.future);
}

Future<void> _deleteEntry({
  required BuildContext context,
  required WidgetRef ref,
  required KnowledgeRepository repo,
  required KnowledgeEntryKind kind,
  required String id,
  required String title,
}) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: Text(AppLocalizations.of(context).knowledgeLibraryDeleteTitle),
    body: Text(AppLocalizations.of(context).knowledgeLibraryDeleteBody(title)),
    confirmLabel: AppLocalizations.of(context).commonDelete,
    cancelLabel: AppLocalizations.of(context).commonCancel,
    destructive: true,
  );
  if (confirmed != true) return;

  try {
    final stamper = await ref.read(mutationStamperProvider.future);
    final stamp = await stamper.stamp();
    await repo.deleteEntry(
      kind: kind,
      id: id,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
        deletedAt: stamp.now,
      ),
    );
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.success,
        AppLocalizations.of(context).knowledgeDeletedToast,
      );
    }
  } catch (e) {
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        AppLocalizations.of(context).knowledgeLibraryDeleteFailed('$e'),
      );
    }
  }
}

/// Unified Library tile shell. Encodes the shared layout:
/// `KnowledgeSection.item` → type icon + `_LibraryTileHeader` (title
/// + trailing row with optional status badge + chevron) → optional subtitle.
