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
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import '../../../../core/ai/visual/visual.dart';
import '../../../../core/product/product_metrics.dart';
import '../../../../core/shell/master_detail_layout.dart';
import '../../../../core/shortcuts/keyboard_platform.dart';
import '../../../../core/shortcuts/master_detail_shortcuts.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../activation/data/finance_activation_store.dart';
import '../../composition/finance_route_paths.dart';
import '../../shared/ui/forms/forms.dart';
import '../data/capture_encoder.dart';
import '../data/ingest_capture_feedback.dart';
import '../data/ingest_capture_policy.dart';
import '../data/ingest_capture_source.dart';
import '../data/ingest_confirm_service.dart';
import '../data/providers.dart';
import '../domain/ingest_models.dart';
import '../domain/ingest_quality_report.dart';
import 'ingest_capture_presentation.dart';
import 'ingest_summary_sheet.dart';

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
  ProviderSubscription<List<IngestCaptureFeedbackEvent>>?
  _captureFeedbackSubscription;
  bool _captureFeedbackDrainScheduled = false;
  final Map<String, ConfirmedIngestItem> _pendingFinalize = {};
  final List<String> _selectedIds = [];
  final FocusNode _masterFocus = FocusNode(debugLabel: 'ingest review master');
  String? _focusedId;
  IngestQualityReport? _latestQualityReport;

  bool get _isBusy => _busy != null || _captureInProgress;

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
    final useMasterDetail = MasterDetailLayout.shouldUseMasterDetail(
      MediaQuery.sizeOf(context).width,
    );
    final viewData =
        accountsAsync.hasError ||
            reviewItemsAsync.hasError ||
            accounts == null ||
            items == null
        ? null
        : _IngestReviewViewData.from(
            accounts: accounts,
            items: items,
            selectedAccountId: _accountId,
            pendingFinalize: _pendingFinalize,
          );
    if (viewData != null) {
      _scheduleSelectionPrune(viewData.items, ensureWideFocus: useMasterDetail);
    }
    final selectedItems = viewData?.items
        .where((item) => _selectedIds.contains(item.draft.draftId))
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
          onSelectNext: viewData == null ? null : () => _moveFocus(viewData, 1),
          onSelectPrevious: viewData == null
              ? null
              : () => _moveFocus(viewData, -1),
          child: content,
        ),
      ),
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
    _IngestReviewViewData? data,
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
    _IngestReviewViewData data,
    List<IngestReviewItem> selectedItems,
  ) {
    final l10n = AppLocalizations.of(context);
    final focused = data.items
        .where((item) => item.draft.draftId == _focusedId)
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
                                  selected: _selectedIds.contains(draftId),
                                  selectable: !item.recoveryUnreadable,
                                  focused: _focusedId == draftId,
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
    _IngestReviewViewData data, {
    bool showSelection = true,
  }) {
    final draft = item.draft;
    final pending = item.pendingFinalize ?? _pendingFinalize[draft.draftId];
    return _DraftCard(
      draft: draft,
      selected: _selectedIds.contains(draft.draftId),
      selectable: !item.recoveryUnreadable,
      focused: _focusedId == draft.draftId,
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
    setState(() => _focusedId = draftId);
    _masterFocus.requestFocus();
  }

  void _moveFocus(_IngestReviewViewData data, int delta) {
    if (_isBusy || isTextInputFocused() || data.items.isEmpty) return;
    final current = data.items.indexWhere(
      (item) => item.draft.draftId == _focusedId,
    );
    final next = current < 0
        ? (delta > 0 ? 0 : data.items.length - 1)
        : (current + delta).clamp(0, data.items.length - 1);
    _focusItem(data.items[next].draft.draftId);
  }

  KeyEventResult _onMasterKey(_IngestReviewViewData data, KeyEvent event) {
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
        .where((item) => item.draft.draftId == _focusedId)
        .firstOrNull;
    if (focused == null) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (!focused.recoveryUnreadable) {
        _toggleSelection(
          focused.draft.draftId,
          !_selectedIds.contains(focused.draft.draftId),
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
    required _IngestReviewViewData? data,
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
                selected: _selectedIds.contains(draft.draftId),
                selectable: !item.recoveryUnreadable,
                focused: _focusedId == draft.draftId,
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
    setState(() {
      _selectedIds.remove(draftId);
      if (selected) _selectedIds.add(draftId);
    });
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
    final route = Uri(
      path: FinanceRoutes.transfer,
      queryParameters: <String, String>{
        'amount': (parsed.amountMinor.abs() / 100).toStringAsFixed(2),
        'date': _ingestYmd(parsed.occurredAt),
        'note': parsed.description,
      },
    ).toString();
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
    final route = Uri(
      path: FinanceRoutes.tradeEntry,
      queryParameters: <String, String>{
        if (parsed.activitySide != null) 'side': parsed.activitySide!,
        if (parsed.instrumentSymbol != null) 'symbol': parsed.instrumentSymbol!,
        if (parsed.quantity != null) 'quantity': parsed.quantity!,
        if (parsed.unitPrice != null) 'price': parsed.unitPrice!,
        'currency': parsed.currency,
        'date': _ingestYmd(parsed.occurredAt),
        'note': parsed.description,
        'ingest': '1',
      },
    ).toString();
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
    final focusIsValid = ids.contains(_focusedId);
    final fallbackFocusId = ensureWideFocus ? _preferredFocusId(items) : null;
    if (_selectedIds.every(ids.contains) &&
        (focusIsValid || _focusedId == fallbackFocusId)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedIds.retainWhere(ids.contains);
        if (!ids.contains(_focusedId)) {
          _focusedId = fallbackFocusId;
        }
      });
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
        _selectedIds.removeWhere(succeeded.contains);
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
        _selectedIds.removeWhere(succeeded.contains);
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

  List<Widget> _compactControlSlivers(_IngestReviewViewData data) {
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

  Widget _rail(_IngestReviewViewData? data) {
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

  Widget _accountPicker(_IngestReviewViewData data) => AccountPicker(
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
      if (result.confirmed.isNotEmpty) {
        await ref.read(financeImportConfirmedProvider.notifier).markConfirmed();
        await ref
            .read(productMetricsProvider.notifier)
            .record(ProductFunnelEvent.importReviewCompleted, success: true);
      }
      if (mounted) {
        final confirmedIds = result.confirmed
            .map((item) => item.draft.draftId)
            .toSet();
        setState(() => _selectedIds.removeWhere(confirmedIds.contains));
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

class _IngestReviewViewData {
  const _IngestReviewViewData({
    required this.items,
    required this.payableAccounts,
    required this.selectedAccountId,
    required this.actionableDrafts,
    required this.freshCount,
  });

  factory _IngestReviewViewData.from({
    required List<Account> accounts,
    required List<IngestReviewItem> items,
    required String? selectedAccountId,
    required Map<String, ConfirmedIngestItem> pendingFinalize,
  }) {
    final payable = accounts
        .where((account) => !account.archived)
        .toList(growable: false);
    final effectiveSelectedId =
        payable.any((account) => account.id == selectedAccountId)
        ? selectedAccountId
        : _IngestReviewPageState._defaultAccountId(payable);
    final actionableDrafts = items
        .where(
          (item) =>
              item.isOrdinaryPending &&
              !pendingFinalize.containsKey(item.draft.draftId),
        )
        .map((item) => item.draft)
        .toList(growable: false);
    return _IngestReviewViewData(
      items: items,
      payableAccounts: payable,
      selectedAccountId: effectiveSelectedId,
      actionableDrafts: actionableDrafts,
      freshCount: actionableDrafts
          .where((draft) => draft.verdict == DedupVerdict.newTxn)
          .length,
    );
  }

  final List<IngestReviewItem> items;
  final List<Account> payableAccounts;
  final String? selectedAccountId;
  final List<IngestDraft> actionableDrafts;
  final int freshCount;
}

class _IngestSelectionActions extends StatelessWidget {
  const _IngestSelectionActions({
    required this.count,
    required this.busy,
    required this.canConfirm,
    required this.canDismiss,
    required this.canFinalize,
    required this.onConfirm,
    required this.onDismiss,
    required this.onFinalize,
  });

  final int count;
  final bool busy;
  final bool canConfirm;
  final bool canDismiss;
  final bool canFinalize;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;
  final VoidCallback onFinalize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Text(l10n.commonSelectedCount(count), style: context.labelStyle),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (canConfirm)
                  AppActionButton(
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy ? null : onConfirm,
                    child: Text(l10n.ingestConfirm),
                  ),
                if (canDismiss) ...[
                  const SizedBox(width: AppSpacing.s8),
                  AppActionButton(
                    variant: FButtonVariant.outline,
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy ? null : onDismiss,
                    child: Text(l10n.ingestSkip),
                  ),
                ],
                if (canFinalize) ...[
                  const SizedBox(width: AppSpacing.s8),
                  AppActionButton(
                    variant: FButtonVariant.primary,
                    mainAxisSize: MainAxisSize.min,
                    onPress: busy ? null : onFinalize,
                    child: Text(l10n.ingestResolveAction),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CapturePopoverAction extends StatefulWidget {
  const _CapturePopoverAction({
    required this.enabled,
    required this.onCamera,
    required this.onFile,
    required this.onPaste,
  });

  final bool enabled;
  final VoidCallback onCamera;
  final VoidCallback onFile;
  final VoidCallback onPaste;

  @override
  State<_CapturePopoverAction> createState() => _CapturePopoverActionState();
}

class _CapturePopoverActionState extends State<_CapturePopoverAction>
    with SingleTickerProviderStateMixin {
  late final FPopoverController _controller;
  final FocusNode _triggerFocus = FocusNode(debugLabel: 'ingest capture menu');

  @override
  void initState() {
    super.initState();
    _controller = FPopoverController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FPopover(
      control: FPopoverControl.managed(controller: _controller),
      popoverAnchor: AlignmentDirectional.topEnd,
      childAnchor: AlignmentDirectional.bottomEnd,
      constraints: const FPortalConstraints(
        minWidth: 200,
        maxWidth: 280,
        maxHeight: 360,
      ),
      popoverBuilder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CaptureOption(
              icon: FLucideIcons.camera,
              label: l10n.ingestCameraAction,
              onPress: () => _select(widget.onCamera),
            ),
            _CaptureOption(
              icon: FLucideIcons.paperclip,
              label: l10n.ingestImportFileAction,
              onPress: () => _select(widget.onFile),
            ),
            _CaptureOption(
              icon: FLucideIcons.clipboard,
              label: l10n.ingestPasteAction,
              onPress: () => _select(widget.onPaste),
            ),
          ],
        ),
      ),
      child: AppHeaderAction(
        semanticsLabel: l10n.ingestCaptureMenuAction,
        icon: const Icon(FLucideIcons.plus),
        focusNode: _triggerFocus,
        onPress: widget.enabled ? _controller.toggle : null,
      ),
    );
  }

  Future<void> _select(VoidCallback action) async {
    await _controller.hide();
    if (!mounted) return;
    _triggerFocus.requestFocus();
    action();
  }
}

class _CaptureOption extends StatelessWidget {
  const _CaptureOption({
    required this.icon,
    required this.label,
    required this.onPress,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onPress,
      excludeSemantics: true,
      child: AppTappable(
        onPress: onPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s10,
          ),
          child: Row(
            children: [
              Icon(icon, size: AppIconSizes.sm),
              const SizedBox(width: AppSpacing.s10),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }
}

class _IngestDraftEditSheet extends StatefulWidget {
  const _IngestDraftEditSheet({required this.parsed});

  final ParsedTransaction parsed;

  @override
  State<_IngestDraftEditSheet> createState() => _IngestDraftEditSheetState();
}

String _ingestYmd(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

class _IngestDraftEditSheetState extends State<_IngestDraftEditSheet> {
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _category;
  late DateTime _date;
  late IngestTransactionKind _kind;
  String? _error;

  @override
  void initState() {
    super.initState();
    final parsed = widget.parsed;
    _description = TextEditingController(text: parsed.description);
    _amount = TextEditingController(
      text: (parsed.amountMinor.abs() / 100).toStringAsFixed(2),
    );
    _currency = TextEditingController(text: parsed.currency);
    _category = TextEditingController(text: parsed.categoryHint);
    _date = parsed.occurredAt;
    _kind = parsed.kind;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _currency.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.ingestEditDraft,
      footer: AppSheetFooter(
        submitLabel: l10n.commonSave,
        cancelLabel: l10n.commonCancel,
        onSubmit: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppAdaptiveChoice<IngestTransactionKind>(
            title: l10n.ingestEditDraft,
            options: IngestTransactionKind.values,
            value: _kind,
            labelOf: (kind) => switch (kind) {
              IngestTransactionKind.income => l10n.ingestKindIncome,
              IngestTransactionKind.expense => l10n.ingestKindExpense,
              IngestTransactionKind.transfer => l10n.ingestKindTransfer,
              IngestTransactionKind.trade => l10n.ingestKindTrade,
            },
            iconOf: (kind) => switch (kind) {
              IngestTransactionKind.income => FLucideIcons.arrowDownLeft,
              IngestTransactionKind.expense => FLucideIcons.arrowUpRight,
              IngestTransactionKind.transfer => FLucideIcons.arrowRightLeft,
              IngestTransactionKind.trade => FLucideIcons.chartCandlestick,
            },
            onChanged: (kind) => setState(() => _kind = kind),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _description),
            label: Text(l10n.ingestEditDescription),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _amount),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text(l10n.ingestEditAmount),
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _currency),
            textCapitalization: TextCapitalization.characters,
            label: Text(l10n.ingestEditCurrency),
          ),
          const SizedBox(height: AppSpacing.s12),
          DateField(
            label: l10n.ingestEditDate,
            initialValue: _date,
            firstDate: DateTime(1970),
            lastDate: DateTime.now().add(const Duration(days: 1)),
            required: true,
            onChanged: (value) {
              if (value != null) setState(() => _date = value);
            },
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextField(
            control: FTextFieldControl.managed(controller: _category),
            label: Text(l10n.ingestEditCategory),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.s12),
            AppStatusBanner(kind: AppStatusKind.error, message: _error!),
          ],
        ],
      ),
    );
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.trim());
    final currency = _currency.text.trim().toUpperCase();
    final description = _description.text.trim();
    if (amount == null ||
        amount <= 0 ||
        currency.isEmpty ||
        description.isEmpty) {
      setState(() {
        _error = AppLocalizations.of(context).ingestEditInvalid;
      });
      return;
    }
    final unsignedMinor = (amount * 100).round();
    final amountMinor = _kind == IngestTransactionKind.income
        ? unsignedMinor
        : -unsignedMinor;
    Navigator.of(context).pop(
      widget.parsed.copyWith(
        description: description,
        amountMinor: amountMinor,
        currency: currency,
        occurredAt: _date,
        kind: _kind,
        clearCategoryHint: _category.text.trim().isEmpty,
        categoryHint: _category.text.trim().isEmpty
            ? null
            : _category.text.trim(),
      ),
    );
  }
}
