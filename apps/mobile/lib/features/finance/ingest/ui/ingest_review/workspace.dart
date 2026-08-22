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
    if (selectedItems != null && selectedItems.isNotEmpty) {
      return (_) => _IngestSelectionActions(
        count: selectedItems.length,
        busy: _isBusy,
        canConfirm: selectedItems.any((item) => item.canBatchConfirm),
        canDismiss: selectedItems.any((item) => item.canBatchDismiss),
        canFinalize: selectedItems.any((item) => item.pendingFinalize != null),
        onConfirm: () =>
            _confirmSelected(selectedItems, data!.selectedAccountId),
        onDismiss: () => _dismissSelected(selectedItems),
        onFinalize: () => _finalizeSelected(selectedItems),
      );
    }
    if (data == null || data.freshCount == 0) return null;
    return (_) => AppActionButton(
      variant: FButtonVariant.primary,
      onPress: _isBusy
          ? null
          : () => _confirmAllFresh(data.items, data.selectedAccountId),
      child: Flexible(
        child: Text(
          l10n.ingestConfirmAllFresh(data.freshCount),
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
      actions: [
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
              master: Column(
                children: [
                  if (data.items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.s12),
                      child: _accountPicker(data),
                    ),
                  Expanded(
                    child: data.items.isEmpty
                        ? _EmptyState(onPaste: _openPasteDialog)
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.s12,
                              0,
                              AppSpacing.s12,
                              AppSpacing.s12,
                            ),
                            itemCount: data.items.length,
                            itemBuilder: (context, index) {
                              final item = data.items[index];
                              final draftId = item.draft.draftId;
                              return Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.s8,
                                ),
                                child: _DraftMasterRow(
                                  draft: item.draft,
                                  selected: _selection.isSelected(draftId),
                                  selectable: !item.recoveryUnreadable,
                                  focused: _selection.isFocused(draftId),
                                  busy: _isBusy,
                                  pendingFinalize:
                                      item.pendingFinalize != null ||
                                      _pendingFinalize.containsKey(draftId),
                                  recoveryUnavailable: item.recoveryUnreadable,
                                  onSelectionChanged: (selected) =>
                                      _toggleSelection(draftId, selected),
                                  onFocus: () => _focusItem(draftId),
                                ),
                              );
                            },
                          ),
                  ),
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
    if (data.items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _busy == null
              ? _EmptyState(onPaste: _openPasteDialog)
              : _ProcessingState(state: _busy!),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
        sliver: SliverList.builder(
          itemCount: data.items.length,
          itemBuilder: (context, index) {
            final item = data.items[index];
            final draft = item.draft;
            final pending =
                item.pendingFinalize ?? _pendingFinalize[draft.draftId];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == data.items.length - 1 ? 0 : AppSpacing.s8,
              ),
              child: _DraftCard(
                draft: draft,
                selected: _selection.isSelected(draft.draftId),
                selectable: !item.recoveryUnreadable,
                focused: _selection.isFocused(draft.draftId),
                busy: _isBusy,
                pendingFinalize: pending != null,
                recoveryUnavailable: item.recoveryUnreadable,
                onConfirm: () => _confirm(draft, data.selectedAccountId),
                onSkip: () => _skip(draft),
                onEdit: () => _editDraft(draft),
                onTransfer: () => _recordTransfer(draft),
                onTrade: () => _recordTrade(draft),
                onFinalize: pending == null
                    ? null
                    : () => _finalizeApplied(pending),
                onSelectionChanged: (selected) =>
                    _toggleSelection(draft.draftId, selected),
                onFocus: () => _focusItem(draft.draftId),
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
    if (data.items.isEmpty) return const <Widget>[];
    return [
      SliverToBoxAdapter(child: _accountPicker(data)),
      if (_busy != null)
        SliverPadding(
          padding: const EdgeInsets.only(top: AppSpacing.s12),
          sliver: SliverToBoxAdapter(child: _ProcessingNotice(state: _busy!)),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s12)),
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
        if (_busy != null) ...[
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
