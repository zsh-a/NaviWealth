part of 'knowledge_library_page.dart';

/// Generic Library segment list for streams that share the same
/// StreamBuilder -> empty -> filter/search -> ListView flow and differ
/// only in row layout via [tileBuilder].
class _SegmentList<T> extends StatefulWidget {
  const _SegmentList({
    required this.storageKey,
    required this.stream,
    required this.query,
    required this.showSearchAssist,
    required this.scopeLabel,
    required this.createLabel,
    required this.onCreate,
    this.onSearchAll,
    required this.searchableText,
    required this.searchSuggestions,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.tileBuilder,
    required this.searchHistory,
    required this.onSearchSelected,
    required this.onSearchHistoryClear,
    this.onSearchHistoryItemDelete,
    required this.onRefresh,
    this.statusOf,
  });

  final String storageKey;
  final Stream<List<T>> stream;
  final String query;
  final bool showSearchAssist;
  final String scopeLabel;
  final String? createLabel;
  final VoidCallback? onCreate;
  final VoidCallback? onSearchAll;
  final String Function(T item) searchableText;
  final List<String> Function(BuildContext context, T item) searchSuggestions;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final Widget Function(BuildContext, T, String query) tileBuilder;
  final List<String> searchHistory;
  final ValueChanged<String> onSearchSelected;
  final VoidCallback onSearchHistoryClear;
  final ValueChanged<String>? onSearchHistoryItemDelete;
  final Future<void> Function() onRefresh;
  final String Function(T item)? statusOf;

  @override
  State<_SegmentList<T>> createState() => _SegmentListState<T>();
}

class _SegmentListState<T> extends State<_SegmentList<T>> {
  String? _statusFilter;

  @override
  void didUpdateWidget(covariant _SegmentList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emptyTitle != widget.emptyTitle) {
      _statusFilter = null;
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
          return AppEmptyState.error(
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
          if (normalizedQuery.isNotEmpty) {
            return AppEmptyState(
              icon: FLucideIcons.search,
              title: l10n.knowledgeLibrarySearchEmptyTitle,
              message: widget.onSearchAll == null
                  ? l10n.knowledgeLibrarySearchEmptyBody
                  : l10n.knowledgeLibrarySearchEmptyScopedBody(
                      widget.scopeLabel,
                    ),
              action: widget.onSearchAll == null
                  ? null
                  : AppQuietButton(
                      label: l10n.knowledgeLibrarySearchAllAction,
                      onPress: widget.onSearchAll,
                    ),
            );
          }
          return AppEmptyState(
            icon: widget.emptyIcon,
            title: widget.emptyTitle,
            message: widget.emptyMessage,
            action: switch ((widget.onCreate, widget.createLabel)) {
              (final onCreate?, final createLabel?) => FButton(
                onPress: onCreate,
                prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.xs),
                child: Text(createLabel),
              ),
              _ => null,
            },
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
        final searchAssist = _SearchAssistRow(
          history: widget.showSearchAssist
              ? widget.searchHistory
              : const <String>[],
          suggestions: widget.showSearchAssist
              ? _suggestionsFor(context, items, normalizedQuery)
              : const <String>[],
          query: normalizedQuery,
          onSelected: widget.onSearchSelected,
          onHistoryClear: widget.onSearchHistoryClear,
          onHistoryItemDelete: widget.onSearchHistoryItemDelete,
        );
        final filterTrigger = statuses.length > 1
            ? _LibraryFilterTrigger(
                activeCount: _statusFilter == null ? 0 : 1,
                onPress: () => _showStatusFilter(statuses),
              )
            : null;

        final statusFilteredItems = _statusFilter == null || statusOf == null
            ? items
            : items
                  .where((item) => statusOf(item) == _statusFilter)
                  .toList(growable: false);
        final visibleItems = normalizedQuery.isEmpty
            ? statusFilteredItems
            : _rankedSearch(
                items: statusFilteredItems,
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
                child: AppEmptyState(
                  icon: FLucideIcons.search,
                  title: l10n.knowledgeLibrarySearchEmptyTitle,
                  message: widget.onSearchAll == null
                      ? l10n.knowledgeLibrarySearchEmptyBody
                      : l10n.knowledgeLibrarySearchEmptyScopedBody(
                          widget.scopeLabel,
                        ),
                  action: widget.onSearchAll == null
                      ? null
                      : AppQuietButton(
                          label: l10n.knowledgeLibrarySearchAllAction,
                          onPress: widget.onSearchAll,
                        ),
                ),
              ),
            ],
          );
        }

        final list = AppRefreshIndicator(
          onRefresh: widget.onRefresh,
          child: AppSwipeActionGroup(
            child: ListView.separated(
              key: PageStorageKey<String>(
                'knowledge-library.${widget.storageKey}',
              ),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: visibleItems.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
              itemBuilder: (context, i) => AppOnceEntrance(
                index: i,
                child: widget.tileBuilder(
                  context,
                  visibleItems[i],
                  widget.query,
                ),
              ),
            ),
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

  Future<void> _showStatusFilter(List<String> statuses) async {
    final l10n = AppLocalizations.of(context);
    final selection = await showAppSheet<String>(
      context: context,
      title: l10n.knowledgeLibraryFilterTitle,
      builder: (sheetContext) => AppActionSheetList(
        children: [
          AppActionSheetTile(
            icon: FLucideIcons.library,
            title: l10n.knowledgeLibraryFilterAll,
            showChevron: false,
            onPress: () => Navigator.of(sheetContext).pop(''),
          ),
          for (final status in statuses)
            AppActionSheetTile(
              icon: FLucideIcons.listFilter,
              title: status,
              showChevron: false,
              onPress: () => Navigator.of(sheetContext).pop(status),
            ),
        ],
      ),
    );
    if (!mounted || selection == null) return;
    setState(() => _statusFilter = selection.isEmpty ? null : selection);
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
}
