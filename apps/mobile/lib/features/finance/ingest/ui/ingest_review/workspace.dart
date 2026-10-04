part of '../ingest_review_page.dart';

// Extension methods on a State subclass legitimately call setState, which
// the analyzer flags as protected outside the class body.
// ignore_for_file: invalid_use_of_protected_member

extension _IngestReviewWorkspace on _IngestReviewPageState {
  WidgetBuilder? _footerBuilder(
    IngestReviewViewData? data,
    List<IngestReviewItem>? selectedItems,
  ) {
    final l10n = AppLocalizations.of(context);
    if (_busy != null && _batchControl != null) {
      return (_) => _ProcessingPanel(
        state: _busy!,
        compact: true,
        onStop: _batchControl!.stopRequested ? null : _stopBatch,
        stopRequested: _batchControl!.stopRequested,
      );
    }
    if (selectedItems != null && selectedItems.isNotEmpty) {
      return (_) => _IngestSelectionActions(
        count: selectedItems.length,
        busy: _isBusy,
        confirmCount: selectedItems
            .where(
              (item) =>
                  item.canBatchConfirm &&
                  !_pendingFinalize.containsKey(item.draft.draftId),
            )
            .length,
        dismissCount: selectedItems
            .where(
              (item) =>
                  item.canBatchDismiss &&
                  !_pendingFinalize.containsKey(item.draft.draftId),
            )
            .length,
        finalizeCount: selectedItems
            .where(
              (item) =>
                  item.pendingFinalize != null ||
                  _pendingFinalize.containsKey(item.draft.draftId),
            )
            .length,
        onCategory:
            selectedItems.any(
              (item) =>
                  (item.draft.parsed.kind == IngestTransactionKind.expense ||
                      item.draft.parsed.kind == IngestTransactionKind.income) &&
                  item.isOrdinaryPending &&
                  !_pendingFinalize.containsKey(item.draft.draftId),
            )
            ? () => _editSelectedCategory(selectedItems)
            : null,
        onConfirm: () =>
            _confirmSelected(selectedItems, data!.selectedAccountId),
        onDismiss: () => _dismissSelected(selectedItems),
        onFinalize: () => _finalizeSelected(selectedItems),
        onClear: () => setState(_selection.clear),
      );
    }
    if (data == null || data.freshCount == 0) return null;
    return (_) => AppActionButton(
      variant: FButtonVariant.primary,
      onPress: _isBusy
          ? null
          : () => _confirmAllFresh(
              data.items
                  .where(
                    (item) => !_pendingFinalize.containsKey(item.draft.draftId),
                  )
                  .toList(),
              data.selectedAccountId,
            ),
      child: Flexible(
        child: Text(
          _filter == IngestReviewFilter.all &&
                  _query.isEmpty &&
                  _category == null
              ? l10n.ingestConfirmAllFresh(data.freshCount)
              : l10n.ingestConfirmFiltered(data.freshCount),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _wideWorkspace(
    IngestReviewViewData data,
    List<IngestReviewItem> selectedItems,
  ) {
    final l10n = AppLocalizations.of(context);
    final focused = data.items
        .where((item) => _selection.isFocused(item.draft.draftId))
        .firstOrNull;
    final footer = _footerBuilder(data, selectedItems)?.call(context);
    return AppPageScaffold(
      titleWidget: _title(l10n),
      confirmLeave: _confirmReviewLeave,
      actions: [
        if (data.allItems.isNotEmpty)
          AppIconButton(
            tooltip: l10n.navSearch,
            icon: FLucideIcons.search,
            onPress: _isBusy
                ? null
                : () => _resetReviewScroll(focusSearch: true),
          ),
        _CapturePopoverAction(
          enabled: !_isBusy,
          onCamera: _captureCamera,
          onFile: _pickFile,
          onPaste: _openPasteDialog,
        ),
      ],
      child: Column(
        children: [
          Expanded(
            child: MasterDetailLayout(
              master: CustomScrollView(
                key: const PageStorageKey('ingest-master-scroll'),
                controller: _reviewScroll,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(AppSpacing.s12),
                    sliver: SliverList.list(
                      children: [
                        if (data.allItems.isNotEmpty) _accountPicker(data),
                        if (data.allItems.isNotEmpty ||
                            _lastBatchOutcome != null) ...[
                          const SizedBox(height: AppSpacing.s12),
                          _reviewControls(data),
                        ],
                        if (_busy != null && _batchControl == null)
                          _ProcessingNotice(state: _busy!),
                      ],
                    ),
                  ),
                  if (data.allItems.isNotEmpty) _pinnedReviewFacets(data),
                  ..._queueSlivers(data, master: true),
                ],
              ),
              detail: focused == null
                  ? MasterDetailEmpty(
                      message: l10n.ingestReviewTitle,
                      icon: FLucideIcons.listChecks,
                    )
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.s24),
                      children: [
                        _draftCard(focused, data, showSelection: false),
                      ],
                    ),
            ),
          ),
          if (footer != null)
            AppFormActionBar(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s24),
                child: footer,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _primarySlivers({
    required AsyncValue<List<Account>> accountsAsync,
    required AsyncValue<List<IngestReviewItem>> reviewItemsAsync,
    required IngestReviewViewData? data,
  }) {
    if (accountsAsync.hasError) {
      return [
        _stateSliver(userSafeErrorMessage(context, accountsAsync.error!)),
      ];
    }
    if (reviewItemsAsync.hasError) {
      return [
        _stateSliver(userSafeErrorMessage(context, reviewItemsAsync.error!)),
      ];
    }
    if (data == null) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: FCircularProgress()),
        ),
      ];
    }
    return _queueSlivers(data);
  }

  List<Widget> _queueSlivers(IngestReviewViewData data, {bool master = false}) {
    if (data.items.isEmpty) {
      _queueLength = 0;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: data.allItems.isNotEmpty
              ? Center(
                  child: Text(
                    AppLocalizations.of(context).ingestNoMatchingDrafts,
                  ),
                )
              : _busy == null
              ? _EmptyState(onPaste: _openPasteDialog)
              : _ProcessingState(state: _busy!),
        ),
      ];
    }
    final entries = _queueEntries(data);
    _queueLength = entries.length;
    final visibleCount = _visibleLimit.clamp(0, entries.length);
    final positions = <Key, int>{
      for (var i = 0; i < visibleCount; i++) _queueEntryKey(entries[i]): i,
    };
    return [
      SliverPadding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
        sliver: SliverList.builder(
          itemCount: visibleCount + (visibleCount < entries.length ? 1 : 0),
          findChildIndexCallback: (key) => positions[key],
          itemBuilder: (context, index) {
            if (index == visibleCount) return _loadMore(entries.length);
            final entry = entries[index];
            if (entry is IngestReviewGroup) {
              return KeyedSubtree(
                key: _queueEntryKey(entry),
                child: _groupRow(entry),
              );
            }
            final item = entry as IngestReviewItem;
            final draft = item.draft;
            final pending =
                item.pendingFinalize ?? _pendingFinalize[draft.draftId];
            return Padding(
              key: ValueKey('ingest-row-${draft.draftId}'),
              padding: EdgeInsets.only(
                bottom: index == entries.length - 1 ? 0 : AppSpacing.s4,
              ),
              child: _DraftMasterRow(
                draft: draft,
                selected: _selection.isSelected(draft.draftId),
                selectable: !item.recoveryUnreadable,
                focused: master && _selection.isFocused(draft.draftId),
                busy: _isBusy,
                pendingFinalize: pending != null,
                recoveryUnavailable: item.recoveryUnreadable,
                onSelectionChanged: (selected) =>
                    _toggleSelection(draft.draftId, selected),
                onFocus: master
                    ? () {
                        if (_selection.selectedIds.isNotEmpty) {
                          if (!item.recoveryUnreadable) {
                            _toggleSelection(
                              draft.draftId,
                              !_selection.isSelected(draft.draftId),
                            );
                          }
                        } else {
                          _focusItem(draft.draftId);
                        }
                      }
                    : () => _openDraftDetails(item),
              ),
            );
          },
        ),
      ),
    ];
  }

  Widget _stateSliver(String message) => SliverFillRemaining(
    hasScrollBody: false,
    child: Center(child: Text(message)),
  );

  List<Widget> _compactControlSlivers(IngestReviewViewData data) {
    if (data.allItems.isEmpty && _lastBatchOutcome == null) {
      return const <Widget>[];
    }
    return [
      if (data.allItems.isNotEmpty)
        SliverToBoxAdapter(child: _accountPicker(data)),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s12)),
      SliverToBoxAdapter(child: _reviewControls(data)),
      if (_busy != null && _batchControl == null)
        SliverPadding(
          padding: const EdgeInsets.only(top: AppSpacing.s12),
          sliver: SliverToBoxAdapter(child: _ProcessingNotice(state: _busy!)),
        ),
      if (data.allItems.isNotEmpty) _pinnedReviewFacets(data),
    ];
  }

  Widget _rail(IngestReviewViewData? data) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data != null && data.items.isNotEmpty) ...[
          _accountPicker(data),
          const SizedBox(height: AppSpacing.s16),
        ],
        AppActionButton(
          variant: FButtonVariant.outline,
          onPress: _isBusy ? null : _captureCamera,
          prefix: const Icon(FLucideIcons.camera),
          child: Flexible(child: Text(l10n.ingestCameraAction)),
        ),
        const SizedBox(height: AppSpacing.s8),
        AppActionButton(
          variant: FButtonVariant.outline,
          onPress: _isBusy ? null : _pickFile,
          prefix: const Icon(FLucideIcons.paperclip),
          child: Flexible(child: Text(l10n.ingestImportFileAction)),
        ),
        const SizedBox(height: AppSpacing.s8),
        AppActionButton(
          variant: FButtonVariant.outline,
          onPress: _isBusy ? null : _openPasteDialog,
          prefix: const Icon(FLucideIcons.clipboard),
          child: Flexible(child: Text(l10n.ingestPasteAction)),
        ),
        if (_busy != null && _batchControl == null) ...[
          const SizedBox(height: AppSpacing.s16),
          _ProcessingNotice(state: _busy!),
        ],
      ],
    );
  }

  Widget _accountPicker(IngestReviewViewData data) => AccountPicker(
    accounts: data.payableAccounts,
    value: data.selectedAccountId,
    label: AppLocalizations.of(context).ingestExpenseAccountLabel,
    enabled: !_isBusy,
    contentConstraints: const FAutoWidthPortalConstraints(maxHeight: 280),
    onChanged: _onAccountChanged,
  );

  void _onAccountChanged(String? value) {
    if (value == _accountId) return;
    setState(() => _accountId = value);
    unawaited(
      ref
          .read(productMetricsProvider.notifier)
          .record(ProductFunnelEvent.importReviewCorrected),
    );
  }
}
