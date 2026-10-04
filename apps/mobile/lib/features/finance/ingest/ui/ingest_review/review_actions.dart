part of '../ingest_review_page.dart';

// Extension methods on a State subclass legitimately call setState, which
// the analyzer flags as protected outside the class body.
// ignore_for_file: invalid_use_of_protected_member

extension _IngestReviewActions on _IngestReviewPageState {
  void _toggleSelection(String draftId, bool selected) {
    if (_isBusy) return;
    setState(() => _selection.setSelected(draftId, selected: selected));
  }

  Future<void> _editDraft(IngestDraft draft) async {
    if (_isBusy) return;
    final drafts =
        _currentData?.reviewOrder
            .where(
              (item) =>
                  item.isOrdinaryPending &&
                  !_pendingFinalize.containsKey(item.draft.draftId),
            )
            .map((item) => item.draft)
            .toList() ??
        [draft];
    if (!drafts.any((item) => item.draftId == draft.draftId)) return;
    await showGuardedFormSheet<void>(
      context: context,
      maxHeightFactor: 0.9,
      builder: (_, dirty) => _IngestDraftEditSheet(
        drafts: drafts,
        initialId: draft.draftId,
        dirty: dirty,
        onCurrentChanged: (id) {
          if (!mounted) return;
          _focusItem(id, requestFocus: false);
        },
      ),
    );
  }

  Future<void> _editSelectedCategory(List<IngestReviewItem> items) async {
    if (_isBusy) return;
    final drafts = items
        .where(
          (item) =>
              item.isOrdinaryPending &&
              !_pendingFinalize.containsKey(item.draft.draftId) &&
              (item.draft.parsed.kind == IngestTransactionKind.expense ||
                  item.draft.parsed.kind == IngestTransactionKind.income),
        )
        .map((item) => item.draft)
        .toList();
    if (drafts.isEmpty) return;
    final edit = await showGuardedFormSheet<_IngestCategoryEdit>(
      context: context,
      builder: (_, dirty) => _IngestCategorySheet(drafts: drafts, dirty: dirty),
    );
    if (edit == null || !mounted) return;
    final store = ref.read(ingestDraftStoreProvider);
    if (store == null) return;
    final l10n = AppLocalizations.of(context);
    setState(
      () => _busy = _IngestBusyState(
        action: _IngestAction.confirmingBatch,
        title: l10n.ingestBatchCategory,
        message: l10n.ingestUpdatingCategory,
        icon: FLucideIcons.tags,
      ),
    );
    try {
      final updatedIds = <String>{};
      final conflictedIds = <String>{};
      for (final category in edit.categories.entries) {
        final result = await store.updateSelectedCategories(
          drafts
              .where(
                (draft) =>
                    draft.parsed.kind == category.key &&
                    edit.draftIds.contains(draft.draftId),
              )
              .toList(),
          category.value,
        );
        updatedIds.addAll(result.updatedIds);
        conflictedIds.addAll(result.conflictedIds);
      }
      if (!mounted) return;
      setState(() => _attentionIds = {..._attentionIds, ...conflictedIds});
      AppMessenger.show(
        context,
        conflictedIds.isEmpty ? ToastKind.success : ToastKind.warning,
        l10n.ingestCategoryUpdated(updatedIds.length, conflictedIds.length),
      );
    } catch (_) {
      if (mounted) {
        AppMessenger.show(context, ToastKind.warning, l10n.ingestEditConflict);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _recordTransfer(IngestDraft draft) async {
    if (_isBusy) return;
    final parsed = draft.parsed;
    final route = buildIngestTransferRoute(parsed);
    final confirmed = await context.push<ConfirmedIngestItem>(
      route,
      extra: draft,
    );
    if (confirmed == null || !mounted) return;
    await _recordExternalImportCompletion();
  }

  Future<void> _recordTrade(IngestDraft draft) async {
    if (_isBusy) return;
    final parsed = draft.parsed;
    final route = buildIngestTradeRoute(parsed);
    final confirmed = await context.push<ConfirmedIngestItem>(
      route,
      extra: draft,
    );
    if (confirmed == null || !mounted) return;
    await _recordExternalImportCompletion();
  }

  Future<void> _recordExternalImportCompletion() async {
    await ref.read(financeImportConfirmedProvider.notifier).markConfirmed();
    await ref
        .read(productMetricsProvider.notifier)
        .record(ProductFunnelEvent.importReviewCompleted, success: true);
  }

  Future<void> _confirmSelected(
    List<IngestReviewItem> items,
    String? accountId,
  ) async {
    await _confirmAllFresh(
      items
          .where((item) => !_pendingFinalize.containsKey(item.draft.draftId))
          .toList(),
      accountId,
    );
  }

  Future<void> _dismissSelected(List<IngestReviewItem> items) async {
    if (_isBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(
      () => _busy = _IngestBusyState(
        action: _IngestAction.confirmingBatch,
        title: l10n.ingestRecordingTitle,
        message: l10n.ingestRecordingBody,
        icon: FLucideIcons.archive,
      ),
    );
    try {
      final service = await ref.read(ingestConfirmServiceProvider.future);
      if (service == null) return;
      final result = await service.dismissSelected(
        items
            .where((item) => !_pendingFinalize.containsKey(item.draft.draftId))
            .toList(),
        onProgress: _updateBatchProgress,
      );
      final dismissed = result.succeeded.map((item) => item.draft).toList();
      if (!mounted) return;
      setState(() {
        final succeeded = dismissed.map((draft) => draft.draftId).toSet();
        _selection.removeAll(succeeded);
      });
      final undoOffer = dismissed.isEmpty
          ? null
          : _offerDismissUndo(service, dismissed, l10n);
      AppMessenger.show(
        context,
        result.failures.isEmpty ? ToastKind.success : ToastKind.warning,
        result.failures.isEmpty
            ? l10n.ingestSkipped
            : l10n.ingestRecordedPartial(
                result.succeeded.length,
                result.failures.length,
              ),
        actionLabel: dismissed.isEmpty ? null : l10n.commonUndo,
        onAction: dismissed.isEmpty ? null : () => _runIngestUndo(undoOffer!),
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _finalizeSelected(List<IngestReviewItem> items) async {
    if (_isBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(
      () => _busy = _IngestBusyState(
        action: _IngestAction.confirmingBatch,
        title: l10n.ingestRecordingTitle,
        message: l10n.ingestRecordingBody,
        icon: FLucideIcons.badgeCheck,
      ),
    );
    try {
      final service = await ref.read(ingestConfirmServiceProvider.future);
      if (service == null) return;
      final result = await service.finalizeSelected(
        items
            .map(
              (item) => IngestReviewItem(
                draft: item.draft,
                pendingFinalize:
                    item.pendingFinalize ??
                    _pendingFinalize[item.draft.draftId],
                recoveryUnreadable: item.recoveryUnreadable,
              ),
            )
            .toList(),
        onProgress: _updateBatchProgress,
      );
      if (result.succeeded.isNotEmpty) {
        await ref.read(financeImportConfirmedProvider.notifier).markConfirmed();
      }
      if (!mounted) return;
      setState(() {
        final succeeded = result.succeeded
            .map((item) => item.draft.draftId)
            .toSet();
        _selection.removeAll(succeeded);
        for (final id in succeeded) {
          _pendingFinalize.remove(id);
        }
      });
      // A multi-entry commit earns a deliberate completion moment; single
      // confirms keep the lightweight toast (doc 11 "完成大型操作").
      if (result.succeeded.length >= 2) {
        AppInteraction.signal(AppInteractionIntent.success);
        await showIngestSummarySheet(
          context,
          recorded: result.succeeded.length,
          needsReview: result.failures.length,
        );
      } else {
        AppMessenger.show(
          context,
          result.failures.isEmpty ? ToastKind.success : ToastKind.warning,
          result.failures.isEmpty
              ? l10n.ingestRecorded
              : l10n.ingestRecordNeedsReview,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _confirm(IngestDraft draft, String? accountId) async {
    final l10n = AppLocalizations.of(context);
    if (accountId == null || accountId.isEmpty) {
      AppMessenger.show(
        context,
        ToastKind.warning,
        l10n.ingestSelectAccountFirst,
      );
      return;
    }
    setState(
      () => _busy = _IngestBusyState(
        action: _IngestAction.confirming,
        title: l10n.ingestRecordingTitle,
        message: l10n.ingestRecordingBody,
        icon: FLucideIcons.badgeCheck,
      ),
    );
    try {
      final svc = await ref.read(ingestConfirmServiceProvider.future);
      if (svc == null) {
        if (mounted) {
          _showRetry(
            l10n.ingestServiceNotReady,
            () => _confirm(draft, accountId),
          );
        }
        return;
      }
      final confirmed = await svc.confirm(
        draft,
        fromAccountId: accountId,
        allowDuplicate: draft.verdict.skipByDefault,
      );
      await ref
          .read(productMetricsProvider.notifier)
          .record(ProductFunnelEvent.importReviewCompleted, success: true);
      if (mounted) {
        final undoOffer = _offerBatchUndo(svc, [confirmed], l10n);
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.ingestRecorded,
          actionLabel: l10n.commonUndo,
          onAction: () => _runIngestUndo(undoOffer),
        );
      }
    } on IngestConfirmException catch (error) {
      if (!mounted) return;
      final item = error.item;
      if (error.recovery == IngestRecovery.finalizeApplied && item != null) {
        setState(() => _pendingFinalize[draft.draftId] = item);
        AppMessenger.show(
          context,
          ToastKind.warning,
          l10n.ingestRecordNeedsReview,
        );
      } else if (error.code == IngestConfirmError.duplicateDetected) {
        ref.invalidate(pendingIngestReviewItemsProvider);
        AppMessenger.show(
          context,
          ToastKind.warning,
          l10n.ingestDuplicateChanged,
        );
      } else if (error.code == IngestConfirmError.manualRecoveryRequired ||
          error.code == IngestConfirmError.lifecycleConflict) {
        ref.invalidate(pendingIngestReviewItemsProvider);
        AppMessenger.show(
          context,
          ToastKind.warning,
          l10n.ingestRecordNeedsReview,
        );
      } else {
        _showRetry(l10n.ingestRecordFailed, () => _confirm(draft, accountId));
      }
    } catch (_) {
      if (mounted) {
        _showRetry(l10n.ingestRecordFailed, () => _confirm(draft, accountId));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _skip(IngestDraft draft) async {
    final l10n = AppLocalizations.of(context);
    setState(
      () => _busy = _IngestBusyState(
        action: _IngestAction.confirming,
        title: l10n.ingestRecordingTitle,
        message: l10n.ingestRecordingBody,
        icon: FLucideIcons.archive,
      ),
    );
    try {
      final svc = await ref.read(ingestConfirmServiceProvider.future);
      if (svc == null) {
        if (mounted) {
          _showRetry(l10n.ingestServiceNotReady, () => _skip(draft));
        }
        return;
      }
      final dismissed = await svc.dismiss(draft);
      if (mounted) {
        final undoOffer = _offerDismissUndo(svc, [dismissed], l10n);
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.ingestSkipped,
          actionLabel: l10n.commonUndo,
          onAction: () => _runIngestUndo(undoOffer),
        );
      }
    } catch (_) {
      if (mounted) {
        _showRetry(l10n.ingestSkipFailed, () => _skip(draft));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _confirmAllFresh(
    List<IngestReviewItem> items,
    String? accountId,
  ) async {
    if (_isBusy) return;
    final l10n = AppLocalizations.of(context);
    if (accountId == null || accountId.isEmpty) {
      AppMessenger.show(
        context,
        ToastKind.warning,
        l10n.ingestSelectAccountFirst,
      );
      return;
    }
    final control = IngestBatchControl();
    _batchControl = control;
    _batchFinished = Completer<void>();
    setState(
      () => _busy = _IngestBusyState(
        action: _IngestAction.confirmingBatch,
        title: l10n.ingestRecordingTitle,
        message: l10n.ingestRecordingBody,
        icon: FLucideIcons.badgeCheck,
      ),
    );
    try {
      final svc = await ref.read(ingestConfirmServiceProvider.future);
      if (svc == null) {
        if (mounted) {
          _showRetry(
            l10n.ingestServiceNotReady,
            () => _confirmAllFresh(items, accountId),
          );
        }
        return;
      }
      final result = await svc.confirmAllFresh(
        items,
        fromAccountId: accountId,
        control: control,
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(
            () => _busy = _IngestBusyState(
              action: _IngestAction.confirmingBatch,
              title: l10n.ingestRecordingTitle,
              message: l10n.ingestRecordingProgress(completed, total),
              icon: FLucideIcons.badgeCheck,
              completed: completed,
              total: total,
            ),
          );
        },
      );
      final outcome = IngestBatchReviewOutcome.from(result);
      if (result.failures.any(
        (failure) => failure.error.code == IngestConfirmError.duplicateDetected,
      )) {
        ref.invalidate(pendingIngestReviewItemsProvider);
      }
      if (outcome.confirmed.isNotEmpty) {
        await ref.read(financeImportConfirmedProvider.notifier).markConfirmed();
        await ref
            .read(productMetricsProvider.notifier)
            .record(ProductFunnelEvent.importReviewCompleted, success: true);
      }
      if (mounted) {
        final undoOffer = outcome.canUndo
            ? _offerBatchUndo(svc, outcome.confirmed, l10n)
            : null;
        setState(() {
          _lastBatchOutcome = outcome;
          _lastUndoOffer = undoOffer;
          _attentionIds = result.failures
              .map((failure) => failure.item.draftId)
              .toSet();
          _selection.removeAll(outcome.confirmedDraftIds);
          _pendingFinalize.addAll(outcome.pendingFinalizeByDraftId);
        });
        AppMessenger.show(
          context,
          outcome.hasFailures ? ToastKind.warning : ToastKind.success,
          outcome.unprocessedCount > 0
              ? l10n.ingestBatchStopped(
                  outcome.confirmed.length,
                  outcome.failureCount,
                  outcome.unprocessedCount,
                )
              : outcome.needsManualFinalize
              ? l10n.ingestRecordNeedsReview
              : !outcome.hasFailures
              ? l10n.ingestRecordedN(outcome.confirmed.length)
              : l10n.ingestRecordedPartial(
                  outcome.confirmed.length,
                  outcome.failureCount,
                ),
          actionLabel: undoOffer?.actionLabel,
          onAction: undoOffer == null ? null : () => _runIngestUndo(undoOffer),
        );
      }
    } catch (_) {
      if (mounted) {
        _showRetry(
          l10n.ingestRecordFailed,
          () => _confirmAllFresh(items, accountId),
        );
      }
    } finally {
      _batchFinished?.complete();
      _batchFinished = null;
      _batchControl = null;
      if (mounted) setState(() => _busy = null);
    }
  }

  void _stopBatch() {
    if (_batchControl == null) return;
    setState(() => _batchControl!.stop());
  }

  Future<bool> _confirmReviewLeave() async {
    if (!_isBusy) return true;
    final finished = _batchFinished;
    if (_batchControl == null || finished == null) return false;
    final l10n = AppLocalizations.of(context);
    final stop = await showConfirmDialog(
      context: context,
      title: Text(l10n.ingestStopAndLeaveTitle),
      body: Text(l10n.ingestStopAndLeaveBody),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.ingestStopAndLeave,
    );
    if (stop != true || !mounted) return false;
    _stopBatch();
    await finished.future;
    return mounted;
  }

  FormUndoOffer _offerBatchUndo(
    IngestConfirmService service,
    List<ConfirmedIngestItem> items,
    AppLocalizations l10n,
  ) {
    var failures = <IngestBatchItemFailure<ConfirmedIngestItem>>[];
    return _offerUndo(
      owner: items.first.draft.ownerUserId,
      message: l10n.ingestRecordedN(items.length),
      successMessage: l10n.ingestUndoSucceeded,
      undo: () async {
        final result = failures.isEmpty
            ? await service.undoAllConfirmed(
                items,
                onProgress: _updateBatchProgress,
              )
            : await service.retryUndoFailures(
                failures,
                onProgress: _updateBatchProgress,
              );
        failures = result.failures;
        if (failures.isNotEmpty) throw StateError('Undo needs retry');
        if (mounted) setState(() => _lastBatchOutcome = null);
      },
    );
  }

  FormUndoOffer _offerDismissUndo(
    IngestConfirmService service,
    List<IngestDraft> drafts,
    AppLocalizations l10n,
  ) {
    var remaining = drafts;
    return _offerUndo(
      owner: drafts.first.ownerUserId,
      message: l10n.ingestSkipped,
      successMessage: l10n.ingestRestored,
      undo: () async {
        final result = await service.restoreSelected(
          remaining,
          onProgress: _updateBatchProgress,
        );
        remaining = result.failures.map((failure) => failure.item).toList();
        if (remaining.isNotEmpty) throw StateError('Restore needs retry');
      },
    );
  }

  FormUndoOffer _offerUndo({
    required String owner,
    required String message,
    required String successMessage,
    required Future<void> Function() undo,
  }) {
    final container = ProviderScope.containerOf(context);
    final l10n = AppLocalizations.of(context);
    final offer = FormUndoOffer(
      message: message,
      action: FormUndoAction(() async {
        if (container.read(activeUserIdProvider) != owner) {
          throw StateError('Undo owner changed');
        }
        if (mounted && _isBusy) throw StateError('Review operation is busy');
        if (mounted) {
          setState(
            () => _busy = _IngestBusyState(
              action: _IngestAction.undoing,
              title: l10n.ingestUndoingTitle,
              message: l10n.ingestUndoingTitle,
              icon: FLucideIcons.undo2,
            ),
          );
        }
        try {
          await undo();
        } finally {
          if (mounted) setState(() => _busy = null);
        }
      }),
      actionLabel: l10n.commonUndo,
      successMessage: successMessage,
      failureMessage: (_) => l10n.ingestUndoFailed,
      retryLabel: l10n.commonRetry,
      tag: 'ingest',
    );
    container.read(formUndoOfferProvider.notifier).offer(offer);
    return offer;
  }

  void _runIngestUndo(FormUndoOffer offer) {
    if (_isBusy) return;
    unawaited(
      ref
          .read(formUndoOfferProvider.notifier)
          .run(context, offer, ref.read(loggerProvider)),
    );
  }

  void _updateBatchProgress(int completed, int total) {
    if (!mounted || _busy == null) return;
    final state = _busy!;
    setState(
      () => _busy = _IngestBusyState(
        action: state.action,
        title: state.title,
        message: state.action == _IngestAction.undoing
            ? AppLocalizations.of(context).ingestUndoProgress(completed, total)
            : AppLocalizations.of(context)
                  .ingestRecordingProgress(completed, total),
        icon: state.icon,
        completed: completed,
        total: total,
      ),
    );
  }

  Future<void> _finalizeApplied(ConfirmedIngestItem item) async {
    if (!mounted || _isBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(
      () => _busy = _IngestBusyState(
        action: _IngestAction.confirming,
        title: l10n.ingestResolvingTitle,
        message: l10n.ingestResolvingBody,
        icon: FLucideIcons.shieldCheck,
      ),
    );
    try {
      final service = await ref.read(ingestConfirmServiceProvider.future);
      if (service == null) {
        if (mounted) {
          _showRetry(l10n.ingestServiceNotReady, () => _finalizeApplied(item));
        }
        return;
      }
      await service.finalizeApplied(item);
      await ref.read(financeImportConfirmedProvider.notifier).markConfirmed();
      if (mounted) {
        setState(() => _pendingFinalize.remove(item.draft.draftId));
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.ingestResolveSucceeded,
        );
      }
    } catch (_) {
      if (mounted) {
        _showRetry(l10n.ingestResolveFailed, () => _finalizeApplied(item));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }
}
