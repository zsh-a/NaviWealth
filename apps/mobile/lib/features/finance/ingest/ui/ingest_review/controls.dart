part of '../ingest_review_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _IngestReviewControls on _IngestReviewPageState {
  void _changeScope({String? query, IngestReviewFilter? filter}) {
    if (_isBusy) return;
    _restoreOffset = null;
    setState(() {
      _query = query ?? _query;
      _filter = filter ?? _filter;
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
        LayoutBuilder(
          builder: (context, constraints) {
            final filter = FSelect<IngestReviewFilter>.rich(
              key: const ValueKey('ingest-review-filter'),
              enabled: !_isBusy,
              format: (value) =>
                  '${_filterLabel(l10n, value)} (${data.filterCounts[value] ?? 0})',
              control: FSelectControl<IngestReviewFilter>.lifted(
                value: _filter,
                onChange: (value) {
                  if (value != null) _changeScope(filter: value);
                },
              ),
              children: [
                for (final value in IngestReviewFilter.values)
                  FSelectItem(
                    value: value,
                    title: Text(
                      '${_filterLabel(l10n, value)} (${data.filterCounts[value] ?? 0})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            );
            final sort = FSelect<IngestReviewSort>.rich(
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
                  FSelectItem(
                    value: value,
                    title: Text(
                      _sortLabel(l10n, value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            );
            if (constraints.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3) {
              return Column(
                children: [
                  filter,
                  const SizedBox(height: AppSpacing.s8),
                  sort,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: filter),
                const SizedBox(width: AppSpacing.s8),
                Expanded(child: sort),
              ],
            );
          },
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
                _filter != IngestReviewFilter.all ||
                _sort != IngestReviewSort.importOrder)
              AppQuietButton(
                key: const ValueKey('ingest-clear-filters'),
                onPress: _isBusy
                    ? null
                    : () {
                        _search.clear();
                        _sort = IngestReviewSort.importOrder;
                        _changeScope(query: '', filter: IngestReviewFilter.all);
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
                      );
                    },
              child: Flexible(child: Text(l10n.ingestReviewFailures)),
            ),
        ],
      ],
    );
  }

  Widget _loadMore(IngestReviewViewData data) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
    child: FButton(
      key: const ValueKey('ingest-load-more'),
      variant: FButtonVariant.outline,
      onPress: () => setState(() => _visibleLimit += 100),
      child: Flexible(
        child: Text(
          AppLocalizations.of(context).ingestLoadMore(
            _visibleLimit.clamp(0, data.items.length),
            data.items.length,
          ),
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
