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
    final parsed = await showAppFormSheet<ParsedTransaction>(
      context: context,
      maxHeightFactor: 0.9,
      builder: (_) => _IngestDraftEditSheet(parsed: draft.parsed),
    );
    if (parsed == null || !mounted) return;
    final store = ref.read(ingestDraftStoreProvider);
    if (store == null) return;
    final updated = await store.updateParsed(
      draftId: draft.draftId,
      expectedRevision: draft.revision,
      parsed: parsed,
    );
    if (!mounted) return;
    if (!updated) {
      AppMessenger.show(
        context,
        ToastKind.warning,
        AppLocalizations.of(context).ingestEditConflict,
      );
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
    await _confirmAllFresh(items, accountId);
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
      final result = await service.dismissSelected(items);
      final dismissed = result.succeeded.map((item) => item.draft).toList();
      if (!mounted) return;
      setState(() {
        final succeeded = dismissed.map((draft) => draft.draftId).toSet();
        _selection.removeAll(succeeded);
      });
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
        onAction: dismissed.isEmpty
            ? null
            : () => unawaited(_restoreSelected(service, dismissed)),
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _restoreSelected(
    IngestConfirmService service,
    List<IngestDraft> drafts,
  ) async {
    final result = await service.restoreSelected(drafts);
    if (!mounted) return;
    AppMessenger.show(
      context,
      result.failures.isEmpty ? ToastKind.success : ToastKind.warning,
      result.failures.isEmpty
          ? AppLocalizations.of(context).ingestRestored
          : AppLocalizations.of(context).ingestUndoFailed,
    );
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
      final result = await service.finalizeSelected(items);
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
      final confirmed = await svc.confirm(draft, fromAccountId: accountId);
      await ref
          .read(productMetricsProvider.notifier)
          .record(ProductFunnelEvent.importReviewCompleted, success: true);
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.ingestRecorded,
          actionLabel: l10n.commonUndo,
          onAction: () => unawaited(_undoConfirmed(svc, confirmed)),
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
      } else if (error.code == IngestConfirmError.manualRecoveryRequired ||
          error.code == IngestConfirmError.lifecycleConflict) {
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
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.ingestSkipped,
          actionLabel: l10n.commonUndo,
          onAction: () => unawaited(_restoreDismissed(svc, dismissed)),
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
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(
            () => _busy = _IngestBusyState(
              action: _IngestAction.confirmingBatch,
              title: l10n.ingestRecordingTitle,
              message: l10n.ingestRecordingProgress(completed, total),
              icon: FLucideIcons.badgeCheck,
            ),
          );
        },
      );
      final outcome = IngestBatchReviewOutcome.from(result);
      if (outcome.confirmed.isNotEmpty) {
        await ref.read(financeImportConfirmedProvider.notifier).markConfirmed();
        await ref
            .read(productMetricsProvider.notifier)
            .record(ProductFunnelEvent.importReviewCompleted, success: true);
      }
      if (mounted) {
        setState(() {
          _selection.removeAll(outcome.confirmedDraftIds);
          _pendingFinalize.addAll(outcome.pendingFinalizeByDraftId);
        });
        AppMessenger.show(
          context,
          outcome.hasFailures ? ToastKind.warning : ToastKind.success,
          outcome.needsManualFinalize
              ? l10n.ingestRecordNeedsReview
              : !outcome.hasFailures
              ? l10n.ingestRecordedN(outcome.confirmed.length)
              : l10n.ingestRecordedPartial(
                  outcome.confirmed.length,
                  outcome.failureCount,
                ),
          actionLabel: outcome.canUndo ? l10n.commonUndo : null,
          onAction: !outcome.canUndo
              ? null
              : () => unawaited(_undoAllConfirmed(svc, outcome.confirmed)),
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
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _undoConfirmed(
    IngestConfirmService service,
    ConfirmedIngestItem item,
  ) async {
    if (!mounted || _isBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(
      () => _busy = _IngestBusyState(
        action: _IngestAction.undoing,
        title: l10n.ingestUndoingTitle,
        message: l10n.ingestUndoProgress(0, 1),
        icon: FLucideIcons.undo2,
      ),
    );
    try {
      await service.undoConfirmed(item);
      if (mounted) {
        AppMessenger.show(context, ToastKind.success, l10n.ingestUndoSucceeded);
      }
    } on IngestConfirmException catch (error) {
      if (!mounted) return;
      if (error.recovery == IngestRecovery.restoreDraft) {
        _showRetry(
          l10n.ingestUndoFailed,
          () => _resumeUndo(service, error.item ?? item),
        );
      } else {
        _showRetry(l10n.ingestUndoFailed, () => _undoConfirmed(service, item));
      }
    } catch (_) {
      if (mounted) {
        _showRetry(l10n.ingestUndoFailed, () => _undoConfirmed(service, item));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _undoAllConfirmed(
    IngestConfirmService service,
    List<ConfirmedIngestItem> items, {
    List<IngestBatchItemFailure<ConfirmedIngestItem>> retryFailures = const [],
  }) async {
    if (!mounted || _isBusy || (items.isEmpty && retryFailures.isEmpty)) return;
    final l10n = AppLocalizations.of(context);
    final total = retryFailures.isEmpty ? items.length : retryFailures.length;
    setState(
      () => _busy = _IngestBusyState(
        action: _IngestAction.undoing,
        title: l10n.ingestUndoingTitle,
        message: l10n.ingestUndoProgress(0, total),
        icon: FLucideIcons.undo2,
      ),
    );
    try {
      void onProgress(int completed, int total) {
        if (!mounted) return;
        setState(
          () => _busy = _IngestBusyState(
            action: _IngestAction.undoing,
            title: l10n.ingestUndoingTitle,
            message: l10n.ingestUndoProgress(completed, total),
            icon: FLucideIcons.undo2,
          ),
        );
      }

      final result = retryFailures.isEmpty
          ? await service.undoAllConfirmed(items, onProgress: onProgress)
          : await service.retryUndoFailures(
              retryFailures,
              onProgress: onProgress,
            );
      if (mounted) {
        AppMessenger.show(
          context,
          result.failures.isEmpty ? ToastKind.success : ToastKind.warning,
          result.failures.isEmpty
              ? l10n.ingestUndoSucceeded
              : l10n.ingestUndoFailed,
          actionLabel: result.failures.isEmpty ? null : l10n.commonRetry,
          onAction: result.failures.isEmpty
              ? null
              : () => unawaited(
                  _undoAllConfirmed(
                    service,
                    const [],
                    retryFailures: result.failures,
                  ),
                ),
        );
      }
    } catch (_) {
      if (mounted) {
        _showRetry(
          l10n.ingestUndoFailed,
          () => _undoAllConfirmed(service, items, retryFailures: retryFailures),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _resumeUndo(
    IngestConfirmService service,
    ConfirmedIngestItem item,
  ) async {
    if (!mounted || _isBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(
      () => _busy = _IngestBusyState(
        action: _IngestAction.undoing,
        title: l10n.ingestUndoingTitle,
        message: l10n.ingestUndoProgress(0, 1),
        icon: FLucideIcons.undo2,
      ),
    );
    try {
      await service.resumeUndo(item);
      if (mounted) {
        AppMessenger.show(context, ToastKind.success, l10n.ingestUndoSucceeded);
      }
    } catch (_) {
      if (mounted) {
        _showRetry(l10n.ingestUndoFailed, () => _resumeUndo(service, item));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
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

  Future<void> _restoreDismissed(
    IngestConfirmService service,
    IngestDraft draft,
  ) async {
    if (!mounted || _isBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(
      () => _busy = _IngestBusyState(
        action: _IngestAction.undoing,
        title: l10n.ingestUndoingTitle,
        message: l10n.ingestUndoProgress(0, 1),
        icon: FLucideIcons.undo2,
      ),
    );
    try {
      await service.restore(draft);
      if (mounted) {
        AppMessenger.show(context, ToastKind.success, l10n.ingestRestored);
      }
    } catch (_) {
      if (mounted) {
        _showRetry(
          l10n.ingestUndoFailed,
          () => _restoreDismissed(service, draft),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }
}
