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
