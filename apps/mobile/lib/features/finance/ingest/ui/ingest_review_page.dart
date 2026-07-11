/// §5.10.10 / S5a step ⑥–⑦ surface — the review queue.
///
/// Calm Intelligence (§5.6): no chatbot, no glow; a single outline
/// sparkle in the header, surface-tone pills, typography-first rows.
/// The page never auto-applies anything — every write is the user's
/// explicit tap (§5.10.6). All copy is localized via AppLocalizations
/// (S5a.1 — full ARB pass; the data-layer parser tokens stay on the
/// allowlist by nature, see §5.10.9).
library;

import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import '../../../../core/ai/visual/visual.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../shared/l10n/account_l10n.dart';
import '../../shared/ui/forms/forms.dart';
import '../data/capture_encoder.dart';
import '../data/ingest_capture_policy.dart';
import '../data/ingest_capture_source.dart';
import '../data/ingest_confirm_service.dart';
import '../data/providers.dart';
import '../domain/ingest_models.dart';
import 'ingest_capture_presentation.dart';

part 'ingest_review/draft_card.dart';
part 'ingest_review/empty.dart';
part 'ingest_review/processing.dart';

class IngestReviewPage extends ConsumerStatefulWidget {
  const IngestReviewPage({super.key});

  @override
  ConsumerState<IngestReviewPage> createState() => _IngestReviewPageState();
}

class _IngestReviewPageState extends ConsumerState<IngestReviewPage> {
  String? _accountId;
  _IngestBusyState? _busy;
  bool _captureInProgress = false;
  final Map<String, ConfirmedIngestItem> _pendingFinalize = {};

  bool get _isBusy => _busy != null || _captureInProgress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reviewItemsAsync = ref.watch(pendingIngestReviewItemsProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);

    return AppPageScaffold(
      titleWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AiSparkle(size: AppIconSizes.sm),
          const SizedBox(width: AppSpacing.s6),
          Flexible(
            child: Text(
              l10n.ingestReviewTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        AppHeaderAction(
          semanticsLabel: l10n.ingestCameraAction,
          icon: const Icon(FLucideIcons.camera),
          onPress: _isBusy ? null : _captureCamera,
        ),
        AppHeaderAction(
          semanticsLabel: l10n.ingestImportFileAction,
          icon: const Icon(FLucideIcons.paperclip),
          onPress: _isBusy ? null : _pickFile,
        ),
        AppHeaderAction(
          semanticsLabel: l10n.ingestPasteAction,
          icon: const Icon(FLucideIcons.clipboard),
          onPress: _isBusy ? null : _openPasteDialog,
        ),
      ],
      childPad: false,
      // §5.10.10 / S5c-native — drag a receipt/statement onto the page
      // (desktop/web). No-op on touch platforms.
      child: DropTarget(
        onDragDone: _isBusy ? (_) {} : _onDrop,
        child: Material(
          color: Colors.transparent,
          child: accountsAsync.whenOrLoading(
            context: context,
            error: (e, _) =>
                Center(child: Text(userSafeErrorMessage(context, e))),
            data: (accounts) => reviewItemsAsync.whenOrLoading(
              context: context,
              error: (e, _) =>
                  Center(child: Text(userSafeErrorMessage(context, e))),
              data: (items) => _content(l10n, accounts, items),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _captureCamera() async {
    if (!_beginCapture()) return;
    late final IngestCaptureOutcome outcome;
    try {
      outcome = await ref.read(cameraIngestCaptureProvider).capture();
    } catch (_) {
      outcome = const IngestCaptureFailure(IngestCaptureFailureCode.unreadable);
    }
    _endCapture();
    if (!mounted) return;
    await _handleCaptureOutcome(
      outcome,
      retry: _captureCamera,
      actionLabel: AppLocalizations.of(context).ingestRetakePhoto,
    );
  }

  Future<void> _onDrop(DropDoneDetails detail) async {
    if (detail.files.isEmpty || !_beginCapture()) return;
    final failures = <IngestCaptureFailure>[];
    try {
      for (final file in detail.files) {
        try {
          final outcome = await xFileToIngestSource(file);
          if (!mounted) return;
          switch (outcome) {
            case IngestCaptureSuccess(:final source):
              await _runIngest(source);
            case IngestCaptureFailure():
              failures.add(outcome);
            case IngestCaptureCancelled():
              break;
          }
        } catch (_) {
          if (!mounted) return;
          failures.add(
            IngestCaptureFailure(
              IngestCaptureFailureCode.unreadable,
              fileName: file.name,
            ),
          );
        }
      }
    } finally {
      _endCapture();
    }
    if (!mounted || failures.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    AppMessenger.show(
      context,
      ToastKind.error,
      failures.length == 1
          ? localizedIngestCaptureFailure(l10n, failures.single)
          : l10n.ingestDroppedSourcesRejected(failures.length),
    );
  }

  Widget _content(
    AppLocalizations l10n,
    List<Account> accounts,
    List<IngestReviewItem> items,
  ) {
    final drafts = items.map((item) => item.draft).toList(growable: false);
    if (drafts.isEmpty) {
      final busy = _busy;
      if (busy != null) return _ProcessingState(state: busy);
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: _EmptyState(
              onPaste: _isBusy ? null : _openPasteDialog,
              onImport: _isBusy ? null : _pickFile,
              onCamera: _isBusy ? null : _captureCamera,
            ),
          ),
        ),
      );
    }
    final payable = accounts.where((a) => !a.archived).toList(growable: false);
    final selectedId = _accountId ?? _defaultAccountId(payable);
    final actionableDrafts = items
        .where(
          (item) =>
              !item.blocksApply &&
              !_pendingFinalize.containsKey(item.draft.draftId),
        )
        .map((item) => item.draft)
        .toList(growable: false);
    final freshCount = actionableDrafts
        .where((d) => d.verdict == DedupVerdict.newTxn)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s12,
              AppSpacing.s16,
              0,
            ),
            child: _ProcessingNotice(state: _busy!),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            AppSpacing.s12,
            AppSpacing.s16,
            AppSpacing.s4,
          ),
          child: Text(
            l10n.ingestExpenseAccountLabel,
            style: context.captionStyle,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            0,
            AppSpacing.s16,
            AppSpacing.s8,
          ),
          child: Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              for (final a in payable)
                AiPill(
                  label: localizedAccountName(l10n, a),
                  state: a.id == selectedId
                      ? AiPillState.selected
                      : AiPillState.neutral,
                  onTap: () => setState(() => _accountId = a.id),
                ),
            ],
          ),
        ),
        const FDivider(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s12,
              AppSpacing.s16,
              AppSpacing.s12,
            ),
            itemCount: drafts.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
            itemBuilder: (context, i) {
              final item = items[i];
              final draft = item.draft;
              final pending =
                  item.pendingFinalize ?? _pendingFinalize[draft.draftId];
              return _DraftCard(
                draft: draft,
                busy: _isBusy,
                pendingFinalize: pending != null,
                recoveryUnavailable: item.recoveryUnreadable,
                onConfirm: () => _confirm(draft, selectedId),
                onSkip: () => _skip(draft),
                onFinalize: pending == null
                    ? null
                    : () => _finalizeApplied(pending),
              );
            },
          ),
        ),
        if (freshCount > 0)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s16,
                0,
                AppSpacing.s16,
                AppSpacing.s12,
              ),
              child: AppActionButton(
                variant: FButtonVariant.primary,
                onPress: _isBusy
                    ? null
                    : () => _confirmAllFresh(actionableDrafts, selectedId),
                child: Flexible(
                  child: Text(
                    l10n.ingestConfirmAllFresh(freshCount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String? _defaultAccountId(List<Account> accounts) {
    if (accounts.isEmpty) return null;
    for (final c in const [AccountCategory.cash, AccountCategory.bank]) {
      final hit = accounts.where((a) => a.type == c);
      if (hit.isNotEmpty) return hit.first.id;
    }
    return accounts.first.id;
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
      await svc.dismiss(draft);
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.ingestSkipped,
          actionLabel: l10n.commonUndo,
          onAction: () => unawaited(_restoreDismissed(svc, draft)),
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
    List<IngestDraft> drafts,
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
            () => _confirmAllFresh(drafts, accountId),
          );
        }
        return;
      }
      final result = await svc.confirmAllFresh(
        drafts,
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
      if (mounted) {
        final unresolved = <ConfirmedIngestItem>[
          for (final failure in result.failures)
            if (failure.error.recovery == IngestRecovery.finalizeApplied &&
                failure.error.item != null)
              failure.error.item!,
        ];
        if (unresolved.isNotEmpty) {
          setState(() {
            for (final item in unresolved) {
              _pendingFinalize[item.draft.draftId] = item;
            }
          });
        }
        final failed = result.failures.length;
        AppMessenger.show(
          context,
          failed == 0 ? ToastKind.success : ToastKind.warning,
          unresolved.isNotEmpty
              ? l10n.ingestRecordNeedsReview
              : failed == 0
              ? l10n.ingestRecordedN(result.confirmed.length)
              : l10n.ingestRecordedPartial(result.confirmed.length, failed),
          actionLabel: result.confirmed.isEmpty ? null : l10n.commonUndo,
          onAction: result.confirmed.isEmpty
              ? null
              : () => unawaited(_undoAllConfirmed(svc, result.confirmed)),
        );
      }
    } catch (_) {
      if (mounted) {
        _showRetry(
          l10n.ingestRecordFailed,
          () => _confirmAllFresh(drafts, accountId),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _openPasteDialog() async {
    final text = await showGuardedFormSheet<String>(
      context: context,
      builder: (_, dirty) => _PasteSheet(
        dirty: dirty,
        maxTextCodeUnits: ref.read(ingestCaptureTextLimitProvider),
      ),
    );
    if (text == null) return;
    final outcome = ingestSourceFromTextCapture(
      text: text,
      // Stable non-display breadcrumb (persisted + traced).
      originLabel: 'paste',
    );
    if (!mounted) return;
    await _handleCaptureOutcome(
      outcome,
      retry: _openPasteDialog,
      actionLabel: AppLocalizations.of(context).commonRetry,
    );
  }

  Future<void> _pickFile() async {
    // The system picker provides its own modal UI; _runIngest owns the
    // busy state for the parse that follows.
    if (!_beginCapture()) return;
    late final IngestCaptureOutcome outcome;
    try {
      outcome = await ref.read(ingestCaptureSourceProvider).pickFile();
    } catch (_) {
      outcome = const IngestCaptureFailure(IngestCaptureFailureCode.unreadable);
    }
    _endCapture();
    if (!mounted) return;
    await _handleCaptureOutcome(
      outcome,
      retry: _pickFile,
      actionLabel: AppLocalizations.of(context).ingestChooseAnotherFile,
    );
  }

  bool _beginCapture() {
    if (_isBusy) return false;
    setState(() => _captureInProgress = true);
    return true;
  }

  void _endCapture() {
    if (mounted) setState(() => _captureInProgress = false);
  }

  Future<void> _handleCaptureOutcome(
    IngestCaptureOutcome outcome, {
    Future<void> Function()? retry,
    String? actionLabel,
  }) async {
    switch (outcome) {
      case IngestCaptureSuccess(:final source):
        await _runIngest(source, retry: retry, retryLabel: actionLabel);
      case IngestCaptureFailure():
        _showCaptureFailure(outcome, retry: retry, actionLabel: actionLabel);
      case IngestCaptureCancelled():
        break;
    }
  }

  void _showCaptureFailure(
    IngestCaptureFailure failure, {
    Future<void> Function()? retry,
    String? actionLabel,
  }) {
    final l10n = AppLocalizations.of(context);
    AppMessenger.show(
      context,
      ToastKind.error,
      localizedIngestCaptureFailure(l10n, failure),
      actionLabel: retry == null ? null : actionLabel,
      onAction: retry == null ? null : () => unawaited(retry()),
    );
  }

  /// Shared tail for every capture entry (paste / file): run the
  /// pipeline and surface the outcome with one consistent toast set.
  Future<void> _runIngest(
    IngestSource source, {
    Future<void> Function()? retry,
    String? retryLabel,
  }) async {
    final l10n = AppLocalizations.of(context);
    final sourceLabel = _sourceLabel(l10n, source);
    setState(() {
      _busy = _IngestBusyState(
        action: _IngestAction.parsing,
        title: l10n.ingestProcessingTitle,
        message: l10n.ingestProcessingBody(sourceLabel),
        icon: _sourceIcon(source.kind),
      );
    });
    try {
      final result = await ref.read(ingestControllerProvider).ingest(source);
      if (!mounted) return;
      if (result.isRejected) {
        _showCaptureParseFailure(
          result.rejectedReason!,
          retry: retry,
          retryLabel: retryLabel,
        );
      } else if (result.total == 0) {
        AppMessenger.show(context, ToastKind.info, l10n.ingestNoTransactions);
      } else {
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.ingestParseSummary(
            result.total,
            result.newCount,
            result.duplicateCount,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        _showCaptureParseFailure(
          l10n.ingestParseFailed,
          retry: retry,
          retryLabel: retryLabel,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _showCaptureParseFailure(
    String message, {
    Future<void> Function()? retry,
    String? retryLabel,
  }) {
    AppMessenger.show(
      context,
      ToastKind.error,
      message,
      actionLabel: retry == null ? null : retryLabel,
      onAction: retry == null ? null : () => unawaited(retry()),
    );
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

  void _showRetry(String message, Future<void> Function() retry) {
    final l10n = AppLocalizations.of(context);
    AppMessenger.show(
      context,
      ToastKind.error,
      message,
      actionLabel: l10n.commonRetry,
      onAction: () => unawaited(retry()),
    );
  }

  static IconData _sourceIcon(IngestSourceKind kind) {
    return switch (kind) {
      IngestSourceKind.csv => FLucideIcons.fileSpreadsheet,
      IngestSourceKind.pasteText => FLucideIcons.clipboard,
      IngestSourceKind.receiptImage => FLucideIcons.image,
      IngestSourceKind.statementPdf => FLucideIcons.fileText,
      IngestSourceKind.email => FLucideIcons.mail,
    };
  }

  static String _sourceLabel(AppLocalizations l10n, IngestSource source) {
    final label = source.originLabel?.trim();
    if (label != null && label.isNotEmpty && label != 'paste') return label;
    return switch (source.kind) {
      IngestSourceKind.csv => l10n.ingestSourceCsv,
      IngestSourceKind.pasteText => l10n.ingestSourcePaste,
      IngestSourceKind.receiptImage => l10n.ingestSourceImage,
      IngestSourceKind.statementPdf => l10n.ingestSourcePdf,
      IngestSourceKind.email => l10n.ingestSourceEmail,
    };
  }
}
