part of '../ingest_review_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _IngestReviewControls on _IngestReviewPageState {
  void _changeScope({
    String? query,
    IngestReviewFilter? filter,
    IngestReviewCategory? category,
    bool clearCategory = false,
  }) {
    if (_isBusy) return;
    _restoreOffset = null;
    setState(() {
      _query = query ?? _query;
      _filter = filter ?? _filter;
      if (clearCategory) _category = null;
      if (category != null) _category = category;
      _expandedGroups.clear();
      _visibleLimit = 100;
      _selection.clear();
    });
    _resetReviewScroll();
  }

  void _resetReviewScroll({bool focusSearch = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _reviewScroll.hasClients) _reviewScroll.jumpTo(0);
      if (mounted && focusSearch) _searchFocus.requestFocus();
    });
  }

  Widget _reviewControls(IngestReviewViewData data) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.ingestReviewQueueCount(data.items.length, data.allItems.length),
          style: context.bodyCaptionStyle,
        ),
        const SizedBox(height: AppSpacing.s8),
        AppSearchField(
          key: const ValueKey('ingest-review-search'),
          focusNode: _searchFocus,
          controller: _search,
          enabled: !_isBusy,
          clearLabel: l10n.ingestClearSearch,
          onChanged: (value) {
            if (!_isBusy && value != _query) _changeScope(query: value);
          },
          hint: l10n.ingestReviewSearchHint,
        ),
        const SizedBox(height: AppSpacing.s8),
        FSelect<IngestReviewSort>.rich(
          key: const ValueKey('ingest-review-sort'),
          enabled: !_isBusy,
          format: (value) => _sortLabel(l10n, value),
          control: FSelectControl<IngestReviewSort>.lifted(
            value: _sort,
            onChange: (value) {
              if (value == null || _isBusy) return;
              setState(() {
                _sort = value;
                _visibleLimit = 100;
              });
              _resetReviewScroll();
            },
          ),
          children: [
            for (final value in IngestReviewSort.values)
              FSelectItem(value: value, title: Text(_sortLabel(l10n, value))),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s4,
          children: [
            FButton(
              key: const ValueKey('ingest-select-filtered'),
              variant: FButtonVariant.ghost,
              onPress: _isBusy || data.items.isEmpty
                  ? null
                  : () => setState(() {
                      _selection.selectAll(
                        data.items
                            .where((item) => !item.recoveryUnreadable)
                            .map((item) => item.draft.draftId),
                      );
                    }),
              mainAxisSize: MainAxisSize.min,
              child: Flexible(child: Text(l10n.ingestSelectFiltered)),
            ),
            FButton(
              key: const ValueKey('ingest-select-ready'),
              variant: FButtonVariant.ghost,
              onPress: _isBusy || data.freshCount == 0
                  ? null
                  : () => setState(() {
                      _selection.clear();
                      _selection.selectAll(
                        data.items
                            .where(
                              (item) =>
                                  item.canBatchConfirm &&
                                  !_pendingFinalize.containsKey(
                                    item.draft.draftId,
                                  ),
                            )
                            .map((item) => item.draft.draftId),
                      );
                    }),
              mainAxisSize: MainAxisSize.min,
              child: Flexible(child: Text(l10n.ingestSelectReady)),
            ),
            if (_query.isNotEmpty ||
                _category != null ||
                _filter != IngestReviewFilter.all ||
                _sort != IngestReviewSort.importOrder)
              AppQuietButton(
                key: const ValueKey('ingest-clear-filters'),
                onPress: _isBusy
                    ? null
                    : () {
                        _search.clear();
                        _sort = IngestReviewSort.importOrder;
                        _changeScope(
                          query: '',
                          filter: IngestReviewFilter.all,
                          clearCategory: true,
                        );
                      },
                label: l10n.ingestClearFilters,
              ),
            if (_selection.selectedIds.isNotEmpty)
              FButton(
                key: const ValueKey('ingest-clear-selection'),
                variant: FButtonVariant.ghost,
                onPress: _isBusy ? null : () => setState(_selection.clear),
                mainAxisSize: MainAxisSize.min,
                child: Flexible(child: Text(l10n.ingestClearSelection)),
              ),
          ],
        ),
        if (_lastBatchOutcome case final outcome?) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            outcome.unprocessedCount > 0
                ? l10n.ingestBatchStopped(
                    outcome.confirmed.length,
                    outcome.failureCount,
                    outcome.unprocessedCount,
                  )
                : l10n.ingestLastBatchResult(
                    outcome.confirmed.length,
                    outcome.failureCount,
                  ),
            key: const ValueKey('ingest-batch-result'),
            style: context.bodyCaptionStyle,
          ),
          if (_lastUndoOffer case final offer?)
            if (identical(ref.watch(formUndoOfferProvider), offer) &&
                offer.available)
              AppActionButton(
                variant: FButtonVariant.outline,
                onPress: _isBusy ? null : () => _runIngestUndo(offer),
                child: Flexible(child: Text(l10n.commonUndo)),
              ),
          if (outcome.hasFailures)
            FButton(
              variant: FButtonVariant.ghost,
              onPress: _isBusy
                  ? null
                  : () {
                      _search.clear();
                      _changeScope(
                        query: '',
                        filter: IngestReviewFilter.attention,
                        clearCategory: true,
                      );
                    },
              child: Flexible(child: Text(l10n.ingestReviewFailures)),
            ),
        ],
      ],
    );
  }

  Widget _pinnedReviewFacets(IngestReviewViewData data) {
    final l10n = AppLocalizations.of(context);
    const allCategories = (
      kind: IngestTransactionKind.expense,
      value: '__all__',
    );
    final categories = {...data.categoryCounts.keys, ?_category}.toList()
      ..sort(
        (a, b) => _categoryLabel(l10n, a).compareTo(_categoryLabel(l10n, b)),
      );
    return PinnedHeaderSliver(
      child: Container(
        key: const ValueKey('ingest-pinned-facets'),
        color: context.theme.colors.background,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in [
                    IngestReviewFilter.all,
                    IngestReviewFilter.attention,
                    IngestReviewFilter.ready,
                    IngestReviewFilter.likelyDuplicate,
                    IngestReviewFilter.duplicate,
                  ])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: AppSpacing.s8,
                      ),
                      child: AppFilterChip(
                        key: ValueKey('ingest-filter-${filter.name}'),
                        label:
                            '${_filterLabel(l10n, filter)} (${data.filterCounts[filter] ?? 0})',
                        active: _filter == filter,
                        onPress: _isBusy
                            ? null
                            : () => _changeScope(filter: filter),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Row(
              children: [
                Expanded(
                  child: FSelect<IngestReviewCategory>.rich(
                    key: const ValueKey('ingest-review-category'),
                    enabled: !_isBusy,
                    format: (value) => value == allCategories
                        ? l10n.ingestAllCategories
                        : _categoryLabel(l10n, value),
                    control: FSelectControl<IngestReviewCategory>.lifted(
                      value: _category ?? allCategories,
                      onChange: (value) {
                        if (value == null) return;
                        _changeScope(
                          category: value == allCategories ? null : value,
                          clearCategory: value == allCategories,
                        );
                      },
                    ),
                    children: [
                      FSelectItem<IngestReviewCategory>(
                        value: allCategories,
                        title: Text(l10n.ingestAllCategories),
                      ),
                      for (final category in categories)
                        FSelectItem<IngestReviewCategory>(
                          value: category,
                          title: Text(
                            '${_categoryLabel(l10n, category)} (${data.categoryCounts[category] ?? 0})',
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: FSelect<IngestReviewGrouping>.rich(
                    key: const ValueKey('ingest-review-grouping'),
                    enabled: !_isBusy,
                    format: (value) => _groupingLabel(l10n, value),
                    control: FSelectControl<IngestReviewGrouping>.lifted(
                      value: _grouping,
                      onChange: (value) {
                        if (value == null || _isBusy) return;
                        setState(() {
                          _grouping = value;
                          _expandedGroups.clear();
                          _visibleLimit = 100;
                        });
                        _resetReviewScroll();
                      },
                    ),
                    children: [
                      for (final grouping in IngestReviewGrouping.values)
                        FSelectItem(
                          value: grouping,
                          title: Text(_groupingLabel(l10n, grouping)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadMore(int total) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
    child: FButton(
      key: const ValueKey('ingest-load-more'),
      variant: FButtonVariant.outline,
      onPress: () => setState(() => _visibleLimit += 100),
      child: Flexible(
        child: Text(
          AppLocalizations.of(context)
              .ingestLoadMore(_visibleLimit.clamp(0, total), total),
        ),
      ),
    ),
  );
}

String _filterLabel(AppLocalizations l10n, IngestReviewFilter filter) =>
    switch (filter) {
      IngestReviewFilter.all => l10n.ingestFilterAll,
      IngestReviewFilter.ready => l10n.ingestFilterReady,
      IngestReviewFilter.likelyDuplicate => l10n.ingestVerdictLikely,
      IngestReviewFilter.duplicate => l10n.ingestVerdictDuplicate,
      IngestReviewFilter.attention => l10n.ingestFilterAttention,
    };

String _sortLabel(AppLocalizations l10n, IngestReviewSort sort) =>
    switch (sort) {
      IngestReviewSort.importOrder => l10n.ingestSortImport,
      IngestReviewSort.newest => l10n.ingestSortNewest,
      IngestReviewSort.oldest => l10n.ingestSortOldest,
      IngestReviewSort.amount => l10n.ingestSortAmount,
    };

String _groupingLabel(AppLocalizations l10n, IngestReviewGrouping grouping) =>
    switch (grouping) {
      IngestReviewGrouping.description => l10n.ingestGroupByDescription,
      IngestReviewGrouping.category => l10n.ingestGroupByCategory,
      IngestReviewGrouping.none => l10n.ingestUngrouped,
    };

String _categoryLabel(AppLocalizations l10n, IngestReviewCategory category) {
  final kind = switch (category.kind) {
    IngestTransactionKind.expense => l10n.ingestKindExpense,
    IngestTransactionKind.income => l10n.ingestKindIncome,
    IngestTransactionKind.transfer => l10n.ingestKindTransfer,
    IngestTransactionKind.trade => l10n.ingestKindTrade,
  };
  final label = category.value == null
      ? l10n.ingestUncategorized
      : _reviewCategoryOptions(l10n, category.kind)[category.value] ??
            category.value!;
  return '$kind · $label';
}
