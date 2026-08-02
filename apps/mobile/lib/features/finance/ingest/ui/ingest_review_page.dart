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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';

import '../../../../core/ai/visual/visual.dart';
import '../../../../core/product/product_metrics.dart';
import '../../../../core/shell/master_detail_layout.dart';
import '../../../../core/shortcuts/keyboard_platform.dart';
import '../../../../core/shortcuts/master_detail_shortcuts.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../activation/data/finance_activation_store.dart';
import '../../shared/ui/forms/forms.dart';
import '../data/capture_encoder.dart';
import '../data/ingest_capture_feedback.dart';
import '../data/ingest_capture_policy.dart';
import '../data/ingest_capture_source.dart';
import '../data/ingest_confirm_service.dart';
import '../data/providers.dart';
import '../domain/ingest_models.dart';
import '../domain/ingest_quality_report.dart';
import '../domain/minor_unit_amount.dart';
import 'ingest_batch_review_outcome.dart';
import 'ingest_capture_lease.dart';
import 'ingest_capture_presentation.dart';
import 'ingest_external_route.dart';
import 'ingest_review_selection.dart';
import 'ingest_review_view_data.dart';
import 'ingest_summary_sheet.dart';

part 'ingest_review/capture_actions.dart';
part 'ingest_review/draft_card.dart';
part 'ingest_review/edit_sheet.dart';
part 'ingest_review/empty.dart';
part 'ingest_review/processing.dart';
part 'ingest_review/selection_actions.dart';

class IngestReviewPage extends ConsumerStatefulWidget {
  const IngestReviewPage({super.key});

  @override
  ConsumerState<IngestReviewPage> createState() => _IngestReviewPageState();
}

class _IngestReviewPageState extends ConsumerState<IngestReviewPage> {
  String? _accountId;
  _IngestBusyState? _busy;
  final IngestCaptureLease _captureLease = IngestCaptureLease();
  ProviderSubscription<List<IngestCaptureFeedbackEvent>>?
  _captureFeedbackSubscription;
  bool _captureFeedbackDrainScheduled = false;
  final Map<String, ConfirmedIngestItem> _pendingFinalize = {};
  final IngestReviewSelection _selection = IngestReviewSelection();
  final FocusNode _masterFocus = FocusNode(debugLabel: 'ingest review master');
  IngestQualityReport? _latestQualityReport;

  bool get _isBusy => _busy != null || _captureLease.isHeld;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _captureFeedbackSubscription != null) return;
      _captureFeedbackSubscription = ref.listenManual(
        ingestCaptureFeedbackQueueProvider,
        (_, events) {
          if (events.isNotEmpty) _scheduleCaptureFeedbackDrain();
        },
        fireImmediately: true,
      );
    });
  }

  @override
  void dispose() {
    _captureFeedbackSubscription?.close();
    _masterFocus.dispose();
    super.dispose();
  }

  void _scheduleCaptureFeedbackDrain() {
    if (_captureFeedbackDrainScheduled) return;
    _captureFeedbackDrainScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureFeedbackDrainScheduled = false;
      if (!mounted) return;
      final events = ref
          .read(ingestCaptureFeedbackQueueProvider.notifier)
          .drain();
      final l10n = AppLocalizations.of(context);
      for (final event in events) {
        AppMessenger.show(
          context,
          ToastKind.error,
          localizedIngestCaptureFeedback(l10n, event),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reviewItemsAsync = ref.watch(pendingIngestReviewItemsProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final accounts = accountsAsync.value;
    final items = reviewItemsAsync.value;
    return LayoutBuilder(
      builder: (context, constraints) {
        final useMasterDetail = MasterDetailLayout.shouldUseMasterDetail(
          constraints.maxWidth,
        );
        final viewData =
            accountsAsync.hasError ||
                reviewItemsAsync.hasError ||
                accounts == null ||
                items == null
            ? null
            : IngestReviewViewData.from(
                accounts: accounts,
                items: items,
                selectedAccountId: _accountId,
                pendingFinalizeIds: _pendingFinalize.keys.toSet(),
              );
        if (viewData != null) {
          _scheduleSelectionPrune(
            viewData.items,
            ensureWideFocus: useMasterDetail,
          );
        }
        final selectedItems = viewData?.items
            .where((item) => _selection.isSelected(item.draft.draftId))
            .toList(growable: false);

        final content = useMasterDetail && viewData != null
            ? _wideWorkspace(viewData, selectedItems ?? const [])
            : AppTaskScaffold(
                titleWidget: _title(l10n),
                actionsBuilder: (context, wide) => wide
                    ? const <Widget>[]
                    : <Widget>[
                        _CapturePopoverAction(
                          enabled: !_isBusy,
                          onCamera: _captureCamera,
                          onFile: _pickFile,
                          onPaste: _openPasteDialog,
                        ),
                      ],
                compactLeadingSliversBuilder: viewData == null
                    ? null
                    : (_) => _compactControlSlivers(viewData),
                primarySliversBuilder: (_) => _primarySlivers(
                  accountsAsync: accountsAsync,
                  reviewItemsAsync: reviewItemsAsync,
                  data: viewData,
                ),
                railBuilder: (_) => _rail(viewData),
                footerBuilder: _footerBuilder(viewData, selectedItems),
              );
        return DropTarget(
          onDragDone: _isBusy ? (_) {} : _onDrop,
          child: Focus(
            focusNode: _masterFocus,
            onKeyEvent: (_, event) => viewData == null
                ? KeyEventResult.ignored
                : _onMasterKey(viewData, event),
            child: MasterDetailShortcuts(
              onSelectNext: viewData == null
                  ? null
                  : () => _moveFocus(viewData, 1),
              onSelectPrevious: viewData == null
                  ? null
                  : () => _moveFocus(viewData, -1),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _title(AppLocalizations l10n) => Row(
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
      if (_latestQualityReport != null)
        AppIconButton(
          tooltip: l10n.ingestCopyDiagnostics,
          onPress: _copyLatestQualityReport,
          icon: FLucideIcons.clipboardCopy,
          iconSize: AppIconSizes.sm,
        ),
    ],
  );

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

  Widget _draftCard(
    IngestReviewItem item,
    IngestReviewViewData data, {
    bool showSelection = true,
  }) {
    final draft = item.draft;
    final pending = item.pendingFinalize ?? _pendingFinalize[draft.draftId];
    return _DraftCard(
      draft: draft,
      selected: _selection.isSelected(draft.draftId),
      selectable: !item.recoveryUnreadable,
      focused: _selection.isFocused(draft.draftId),
      busy: _isBusy,
      pendingFinalize: pending != null,
      recoveryUnavailable: item.recoveryUnreadable,
      showSelection: showSelection,
      onConfirm: () => _confirm(draft, data.selectedAccountId),
      onSkip: () => _skip(draft),
      onEdit: () => _editDraft(draft),
      onTransfer: () => _recordTransfer(draft),
      onTrade: () => _recordTrade(draft),
      onFinalize: pending == null ? null : () => _finalizeApplied(pending),
      onSelectionChanged: (selected) =>
          _toggleSelection(draft.draftId, selected),
      onFocus: () => _focusItem(draft.draftId),
    );
  }

  void _focusItem(String draftId) {
    if (_isBusy) return;
    setState(() => _selection.focus(draftId));
    _masterFocus.requestFocus();
  }

  void _moveFocus(IngestReviewViewData data, int delta) {
    if (_isBusy || isTextInputFocused() || data.items.isEmpty) return;
    final next = _selection.focusByOffset(
      data.items.map((item) => item.draft.draftId).toList(growable: false),
      delta,
    );
    if (next != null) _focusItem(next);
  }

  KeyEventResult _onMasterKey(IngestReviewViewData data, KeyEvent event) {
    if (!_masterFocus.hasPrimaryFocus || _isBusy || isTextInputFocused()) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveFocus(data, 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveFocus(data, -1);
      return KeyEventResult.handled;
    }
    final focused = data.items
        .where((item) => _selection.isFocused(item.draft.draftId))
        .firstOrNull;
    if (focused == null) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (!focused.recoveryUnreadable) {
        _toggleSelection(
          focused.draft.draftId,
          !_selection.isSelected(focused.draft.draftId),
        );
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _focusItem(focused.draft.draftId);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
    final recorded = await context.push<bool>(route);
    if (recorded != true || !mounted) return;
    await _settleExternalDraft(
      draft,
      AppLocalizations.of(context).ingestTransferRecorded,
    );
  }

  Future<void> _recordTrade(IngestDraft draft) async {
    if (_isBusy) return;
    final parsed = draft.parsed;
    final route = buildIngestTradeRoute(parsed);
    final recorded = await context.push<bool>(route);
    if (recorded != true || !mounted) return;
    await _settleExternalDraft(
      draft,
      AppLocalizations.of(context).ingestTradeRecorded,
    );
  }

  Future<void> _settleExternalDraft(
    IngestDraft draft,
    String successMessage,
  ) async {
    final store = ref.read(ingestDraftStoreProvider);
    if (store == null) return;
    final result = await store.transition(
      IngestLifecycleTransition(
        ownerUserId: draft.ownerUserId,
        draftId: draft.draftId,
        expectedStatus: DraftStatus.pending,
        expectedRevision: draft.revision,
        nextStatus: DraftStatus.confirmed,
      ),
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    AppMessenger.show(
      context,
      result.outcome == IngestLifecycleMutationOutcome.applied
          ? ToastKind.success
          : ToastKind.warning,
      result.outcome == IngestLifecycleMutationOutcome.applied
          ? successMessage
          : l10n.ingestEditConflict,
    );
  }

  void _scheduleSelectionPrune(
    List<IngestReviewItem> items, {
    required bool ensureWideFocus,
  }) {
    final ids = items.map((item) => item.draft.draftId).toSet();
    final fallbackFocusId = ensureWideFocus ? _preferredFocusId(items) : null;
    if (!_selection.needsReconcile(ids, fallbackFocusId: fallbackFocusId)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(
        () => _selection.reconcile(ids, fallbackFocusId: fallbackFocusId),
      );
    });
  }

  String? _preferredFocusId(List<IngestReviewItem> items) {
    if (items.isEmpty) return null;
    for (final item in items) {
      final draftId = item.draft.draftId;
      final pending = item.pendingFinalize ?? _pendingFinalize[draftId];
      if (!item.recoveryUnreadable &&
          (item.isOrdinaryPending || pending != null)) {
        return draftId;
      }
    }
    return items.first.draft.draftId;
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
    if (_busy != null || !_captureLease.tryAcquire()) return false;
    setState(() {});
    return true;
  }

  void _endCapture() {
    if (mounted) setState(_captureLease.release);
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
      final qualityReport = IngestQualityReport.fromResult(source.kind, result);
      setState(() => _latestQualityReport = qualityReport);
      await _recordIngestQualityMetrics(result);
      if (!mounted) return;
      if (result.isRejected) {
        final rejection = result.rejectedReason!;
        _showCaptureParseFailure(
          rejection == ingestDatabaseUnavailableReason
              ? l10n.ingestParseFailed
              : rejection,
          retry: retry,
          retryLabel: retryLabel,
        );
      } else if (result.total == 0) {
        AppMessenger.show(context, ToastKind.info, l10n.ingestNoTransactions);
      } else {
        final hasAuditedSkips =
            result.parseDiagnosticsComplete && result.skippedCount > 0;
        AppMessenger.show(
          context,
          hasAuditedSkips ? ToastKind.warning : ToastKind.success,
          hasAuditedSkips
              ? l10n.ingestParseSummaryWithSkipped(
                  result.total,
                  result.newCount,
                  result.duplicateCount,
                  result.skippedCount,
                )
              : l10n.ingestParseSummary(
                  result.total,
                  result.newCount,
                  result.duplicateCount,
                ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _latestQualityReport = IngestQualityReport.failed(source.kind),
        );
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

  Future<void> _recordIngestQualityMetrics(IngestResult result) async {
    final metrics = ref.read(productMetricsProvider.notifier);
    await metrics.record(
      ProductFunnelEvent.importCycleCompleted,
      success: !result.isRejected,
    );
    await metrics.record(
      ProductFunnelEvent.importRowsAccepted,
      success: true,
      quantity: result.newCount,
    );
    await metrics.record(
      ProductFunnelEvent.importRowsDeduplicated,
      success: true,
      quantity: result.duplicateCount,
    );
    await metrics.record(
      ProductFunnelEvent.importRowsRejected,
      success: false,
      quantity: result.skippedCount + (result.isRejected ? 1 : 0),
    );
  }

  void _copyLatestQualityReport() {
    final report = _latestQualityReport;
    if (report == null) return;
    Clipboard.setData(ClipboardData(text: report.encode()));
    AppMessenger.show(
      context,
      ToastKind.success,
      AppLocalizations.of(context).ingestDiagnosticsCopied,
    );
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
