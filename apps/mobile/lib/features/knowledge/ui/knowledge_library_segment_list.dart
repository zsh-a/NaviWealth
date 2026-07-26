part of 'knowledge_library_page.dart';

/// Generic Library segment list for streams that share the same
/// StreamBuilder -> empty -> filter/search -> ListView flow and differ
/// only in row layout via [tileBuilder].
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
            title: userSafeErrorMessage(
              context,
              snap.error!,
              stackTrace: snap.stackTrace,
              operation: 'load knowledge library segment',
            ),
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
        final dateOf = widget.dateOf;
        final searchAssist = _SearchAssistRow(
          history: widget.searchHistory,
          suggestions: _suggestionsFor(context, items, normalizedQuery),
          query: normalizedQuery,
          onSelected: widget.onSearchSelected,
          onHistoryClear: widget.onSearchHistoryClear,
          onHistoryItemDelete: widget.onSearchHistoryItemDelete,
        );
        final activeFilterCount =
            (_statusFilter == null ? 0 : 1) +
            (_facetFilter == null ? 0 : 1) +
            (_dateFilter == KnowledgeLibraryDateFilter.all ? 0 : 1);
        final hasFilterDimensions =
            statuses.length > 1 || dateOf != null || facets.isNotEmpty;
        final filterTrigger = hasFilterDimensions
            ? _LibraryFilterTrigger(
                activeCount: activeFilterCount,
                onPress: () => _showFilters(
                  statuses: statuses,
                  facets: facets,
                  showDate: dateOf != null,
                ),
              )
            : null;

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
              if (filterTrigger != null) ...[
                filterTrigger,
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

        final list = AppRefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: visibleItems.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
            itemBuilder: (context, i) =>
                widget.tileBuilder(context, visibleItems[i], widget.query),
          ),
        );
        if (filterTrigger == null) {
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
            filterTrigger,
            const SizedBox(height: AppSpacing.s12),
            Expanded(child: list),
          ],
        );
      },
    );
  }

  Future<void> _showFilters({
    required List<String> statuses,
    required List<String> facets,
    required bool showDate,
  }) async {
    final l10n = AppLocalizations.of(context);
    var status = _statusFilter;
    var facet = _facetFilter;
    var date = _dateFilter;
    final selection =
        await showAppSheet<
          ({String? status, String? facet, KnowledgeLibraryDateFilter date})
        >(
          context: context,
          title: l10n.knowledgeLibraryFilterTitle,
          footer: Row(
            children: [
              Expanded(
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => Navigator.of(context).pop((
                    status: null,
                    facet: null,
                    date: KnowledgeLibraryDateFilter.all,
                  )),
                  child: Text(l10n.knowledgeLibraryFilterClear),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: FButton(
                  onPress: () => Navigator.of(
                    context,
                  ).pop((status: status, facet: facet, date: date)),
                  child: Text(l10n.commonDone),
                ),
              ),
            ],
          ),
          builder: (sheetContext) => StatefulBuilder(
            builder: (context, setSheetState) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (statuses.length > 1) ...[
                  Text(
                    l10n.knowledgeLibraryFilterStatus,
                    style: context.captionLabelStyle,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  _FilterChipRow(
                    icon: FLucideIcons.listFilter,
                    values: statuses,
                    selected: status,
                    onChanged: (value) => setSheetState(() => status = value),
                  ),
                ],
                if (showDate) ...[
                  if (statuses.length > 1)
                    const SizedBox(height: AppSpacing.s16),
                  Text(
                    l10n.knowledgeLibraryFilterDate,
                    style: context.captionLabelStyle,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  _DateFilterChipRow(
                    selected: date,
                    onChanged: (value) => setSheetState(() => date = value),
                  ),
                ],
                if (facets.isNotEmpty) ...[
                  if (statuses.length > 1 || showDate)
                    const SizedBox(height: AppSpacing.s16),
                  Text(
                    l10n.knowledgeLibraryFilterFacet,
                    style: context.captionLabelStyle,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  _FilterChipRow(
                    icon: FLucideIcons.tags,
                    values: facets,
                    selected: facet,
                    onChanged: (value) => setSheetState(() => facet = value),
                  ),
                ],
              ],
            ),
          ),
        );
    if (!mounted || selection == null) return;
    setState(() {
      _statusFilter = selection.status;
      _facetFilter = selection.facet;
      _dateFilter = selection.date;
    });
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
