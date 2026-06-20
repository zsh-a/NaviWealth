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
            _LibrarySegment.all => _SegmentList<_LibraryEntry>(
              stream: _watchAllKnowledge(repo, ownerUserId: owner),
              query: query,
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
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
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
            _LibrarySegment.decisions => _SegmentList<KnowledgeDecision>(
              stream: repo.watchDecisions(ownerUserId: owner),
              query: query,
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
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
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
            _LibrarySegment.principles => _SegmentList<KnowledgePrinciple>(
              stream: repo.watchPrinciples(ownerUserId: owner),
              query: query,
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
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
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
            _LibrarySegment.assumptions => _SegmentList<KnowledgeAssumption>(
              stream: repo.watchAssumptions(ownerUserId: owner),
              query: query,
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
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
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
            _LibrarySegment.notes => _SegmentList<KnowledgeNote>(
              stream: repo.watchNotes(ownerUserId: owner),
              query: query,
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
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
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
            _LibrarySegment.concepts => _SegmentList<KnowledgeConcept>(
              stream: repo.watchConcepts(ownerUserId: owner),
              query: query,
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
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
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
            _LibrarySegment.experiments => _SegmentList<KnowledgeExperiment>(
              stream: repo.watchExperiments(ownerUserId: owner),
              query: query,
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
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
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
            _LibrarySegment.routines => _SegmentList<KnowledgeRoutine>(
              stream: repo.watchRoutines(ownerUserId: owner),
              query: query,
              searchableText: (r) => [r.statement, r.scope].join('\n'),
              searchSuggestions: (_, r) =>
                  [r.status.wire, r.scope].toList(growable: false),
              filterFacets: (_, r) => [r.scope],
              dateOf: (r) => r.nextDueAt,
              emptyIcon: FLucideIcons.calendarClock,
              emptyTitle: l10n.knowledgeLibraryEmptyRoutinesTitle,
              emptyMessage: l10n.knowledgeLibraryEmptyRoutinesBody,
              statusOf: (r) => r.status.wire,
              searchHistory: searchHistory,
              onSearchSelected: onSearchSelected,
              onSearchHistoryClear: onSearchHistoryClear,
              onSearchHistoryItemDelete: onSearchHistoryItemDelete,
              onRefresh: onRefresh,
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

class _SearchAssistRow extends StatelessWidget {
  const _SearchAssistRow({
    required this.history,
    required this.suggestions,
    required this.query,
    required this.onSelected,
    required this.onHistoryClear,
    this.onHistoryItemDelete,
  });

  final List<String> history;
  final List<String> suggestions;
  final String query;
  final ValueChanged<String> onSelected;
  final VoidCallback onHistoryClear;
  final ValueChanged<String>? onHistoryItemDelete;

  bool get hasContent =>
      suggestions.isNotEmpty ||
      (query.isEmpty
          ? history.isNotEmpty
          : history.any((item) => item.toLowerCase().contains(query)));

  @override
  Widget build(BuildContext context) {
    if (!hasContent) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final visibleHistory = query.isEmpty
        ? history
        : history
              .where((item) => item.toLowerCase().contains(query))
              .toList(growable: false);
    final chips = <Widget>[
      if (visibleHistory.isNotEmpty)
        _SearchAssistGroup(
          label: l10n.knowledgeLibrarySearchRecent,
          values: visibleHistory,
          icon: FLucideIcons.history,
          onSelected: onSelected,
          onClear: query.isEmpty ? onHistoryClear : null,
          onItemDelete: onHistoryItemDelete,
        ),
      if (suggestions.isNotEmpty)
        _SearchAssistGroup(
          label: l10n.knowledgeLibrarySearchSuggestions,
          values: suggestions,
          icon: FLucideIcons.sparkles,
          onSelected: onSelected,
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s8),
          chips[i],
        ],
      ],
    );
  }
}

class _SearchAssistGroup extends StatelessWidget {
  const _SearchAssistGroup({
    required this.label,
    required this.values,
    required this.icon,
    required this.onSelected,
    this.onClear,
    this.onItemDelete,
  });

  final String label;
  final List<String> values;
  final IconData icon;
  final ValueChanged<String> onSelected;
  final VoidCallback? onClear;
  final ValueChanged<String>? onItemDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final visibleValues = values.take(6).toList(growable: false);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIconSizes.xs, color: colors.mutedForeground),
            const SizedBox(width: AppSpacing.s4),
            Text(label, style: context.captionStyle),
            if (onClear != null) ...[
              const SizedBox(width: AppSpacing.s4),
              FButton.icon(
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                onPress: onClear,
                child: Icon(
                  FLucideIcons.x,
                  size: AppIconSizes.xs,
                  color: colors.mutedForeground,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < visibleValues.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.s6),
                  _SearchAssistChip(
                    value: visibleValues[i],
                    onPress: () => onSelected(visibleValues[i]),
                    onDelete: onItemDelete != null
                        ? () => onItemDelete!(visibleValues[i])
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchAssistChip extends StatelessWidget {
  const _SearchAssistChip({
    required this.value,
    required this.onPress,
    this.onDelete,
  });

  final String value;
  final VoidCallback onPress;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: onPress,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.s8,
            right: onDelete != null ? AppSpacing.s4 : AppSpacing.s8,
            top: AppSpacing.s4,
            bottom: AppSpacing.s4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 112),
                child: Text(
                  value,
                  style: context.captionLabelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: AppSpacing.s2),
                GestureDetector(
                  onTap: onDelete,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s2),
                    child: Icon(
                      FLucideIcons.x,
                      size: AppIconSizes.xs,
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({
    required this.icon,
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final IconData icon;
  final List<String> values;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Icon(
          icon,
          size: AppIconSizes.xs,
          color: context.theme.colors.mutedForeground,
        ),
        const SizedBox(width: AppSpacing.s6),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterPill(
                  label: l10n.knowledgeLibraryFilterAll,
                  active: selected == null,
                  onTap: () => onChanged(null),
                ),
                for (final value in values)
                  _FilterPill(
                    label: value,
                    active: selected == value,
                    onTap: () => onChanged(value),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.s4),
      child: AppFilterChip(label: label, active: active, onPress: onTap),
    );
  }
}

class _DateFilterChipRow extends StatelessWidget {
  const _DateFilterChipRow({required this.selected, required this.onChanged});

  final KnowledgeLibraryDateFilter selected;
  final ValueChanged<KnowledgeLibraryDateFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Icon(
          FLucideIcons.calendarDays,
          size: AppIconSizes.xs,
          color: context.theme.colors.mutedForeground,
        ),
        const SizedBox(width: AppSpacing.s6),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in KnowledgeLibraryDateFilter.values)
                  _FilterPill(
                    label: _dateFilterLabel(l10n, filter),
                    active: selected == filter,
                    onTap: () => onChanged(filter),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Horizontally scrollable tab bar for the 7 Library segments. Every
/// segment keeps its label visible; icon-only tabs made the object
/// families hard to recognize unless the user already knew the order.
class _LibraryTabBar extends StatelessWidget {
  const _LibraryTabBar({required this.selected, required this.onChanged});

  final _LibrarySegment selected;
  final ValueChanged<_LibrarySegment> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return SizedBox(
      height: AppControlHeights.compactChipRail,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _LibrarySegment.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.s6),
        itemBuilder: (context, i) {
          final segment = _LibrarySegment.values[i];
          final active = segment == selected;
          return FTappable(
            onPress: () => onChanged(segment),
            child: AnimatedContainer(
              duration: motionDuration(context, Motion.fast),
              curve: Motion.standardDecelerate,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s10,
                vertical: AppSpacing.s6,
              ),
              decoration: BoxDecoration(
                color: active
                    ? colors.primary.withValues(alpha: AppOpacity.subtle)
                    : colors.background,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: active
                      ? colors.primary.withValues(alpha: AppOpacity.light)
                      : colors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _segmentIcon(segment),
                    size: AppIconSizes.xs,
                    color: active ? colors.primary : colors.mutedForeground,
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  Text(
                    _segmentLabel(l10n, segment),
                    style: active
                        ? context.captionLabelStyle.copyWith(
                            color: colors.primary,
                          )
                        : context.captionMediumStyle.copyWith(
                            color: colors.mutedForeground,
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
