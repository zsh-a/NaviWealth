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
import '../../../../core/auth/current_user.dart';
import '../../../../core/logging/providers.dart';
import '../../../../core/product/product_metrics.dart';
import '../../../../core/shell/master_detail_layout.dart';
import '../../../../core/shortcuts/keyboard_platform.dart';
import '../../../../core/shortcuts/master_detail_shortcuts.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../activation/data/finance_activation_store.dart';
import '../../expense/domain/expense_category_presets.dart';
import '../../expense/domain/expense_category_taxonomy.dart';
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
part 'ingest_review/capture_feedback_listener.dart';
part 'ingest_review/capture_flow.dart';
part 'ingest_review/draft_card.dart';
part 'ingest_review/edit_sheet.dart';
part 'ingest_review/empty.dart';
part 'ingest_review/focus_keys.dart';
part 'ingest_review/processing.dart';
part 'ingest_review/review_actions.dart';
part 'ingest_review/selection_actions.dart';
part 'ingest_review/workspace.dart';
part 'ingest_review/controls.dart';
part 'ingest_review/duplicate_comparison.dart';
part 'ingest_review/category_picker.dart';
part 'ingest_review/view_state.dart';
part 'ingest_review/groups.dart';

class IngestReviewPage extends ConsumerStatefulWidget {
  const IngestReviewPage({super.key});

  @override
  ConsumerState<IngestReviewPage> createState() => _IngestReviewPageState();
}

class _IngestReviewPageState extends ConsumerState<IngestReviewPage>
    with WidgetsBindingObserver {
  String? _accountId;
  _IngestBusyState? _busy;
  final IngestCaptureLease _captureLease = IngestCaptureLease();
  final Map<String, ConfirmedIngestItem> _pendingFinalize = {};
  final IngestReviewSelection _selection = IngestReviewSelection();
  final FocusNode _masterFocus = FocusNode(debugLabel: 'ingest review master');
  IngestQualityReport? _latestQualityReport;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'ingest review search');
  String _query = '';
  IngestReviewFilter _filter = IngestReviewFilter.all;
  IngestReviewSort _sort = IngestReviewSort.importOrder;
  IngestReviewCategory? _category;
  IngestReviewGrouping _grouping = IngestReviewGrouping.description;
  final Set<IngestReviewGroupKey> _expandedGroups = {};
  int _queueLength = 0;
  int _visibleLimit = 100;
  IngestReviewViewData? _currentData;
  Object? _projectionKey;
  IngestBatchReviewOutcome? _lastBatchOutcome;
  Set<String> _attentionIds = {};
  List<String> _previousReviewOrder = const [];
  final ScrollController _reviewScroll = ScrollController();
  IngestBatchControl? _batchControl;
  Completer<void>? _batchFinished;
  FormUndoOffer? _lastUndoOffer;
  bool _leaving = false;
  LocalFormDraftSession? _viewSession;
  double? _restoreOffset;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreReviewView(ref.read(localFormDraftStoreProvider));
    ref.listenManual(localFormDraftStoreProvider, (_, store) {
      if (mounted) setState(() => _restoreReviewView(store));
    });
    _reviewScroll.addListener(_onReviewScroll);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _viewSession?.flush();
  }

  bool get _isBusy => _busy != null || _captureLease.isHeld;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureReviewView();
    _viewSession?.dispose();
    _masterFocus.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _reviewScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _captureReviewView();
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
        if (accountsAsync.hasError ||
            reviewItemsAsync.hasError ||
            accounts == null ||
            items == null) {
          _currentData = null;
          _projectionKey = null;
        } else {
          final key = (
            accounts,
            items,
            _accountId,
            _query,
            _filter,
            _sort,
            _category,
            _grouping,
            l10n.localeName,
            _pendingFinalize.keys.join('\u0000'),
            _attentionIds,
          );
          if (_projectionKey != key) {
            _currentData = IngestReviewViewData.from(
              accounts: accounts,
              items: items,
              selectedAccountId: _accountId,
              pendingFinalizeIds: _pendingFinalize.keys.toSet(),
              query: _query,
              filter: _filter,
              sort: _sort,
              attentionIds: _attentionIds,
              category: _category,
              grouping: _grouping,
              categoryLabels: {
                for (final kind in [
                  IngestTransactionKind.expense,
                  IngestTransactionKind.income,
                ]) ...{
                  (kind: kind, value: null): l10n.ingestUncategorized,
                  for (final entry in _reviewCategoryOptions(
                    l10n,
                    kind,
                  ).entries)
                    (kind: kind, value: entry.key): entry.value,
                },
              },
            );
            _projectionKey = key;
          }
        }
        final viewData = _currentData;
        if (viewData != null) {
          _scheduleSelectionPrune(
            viewData.reviewOrder.toList(),
            ensureFocus: true,
          );
          _restoreReviewScroll();
        }
        final selectedItems = viewData?.items
            .where((item) => _selection.isSelected(item.draft.draftId))
            .toList(growable: false);

        final content = useMasterDetail && viewData != null
            ? _wideWorkspace(viewData, selectedItems ?? const [])
            : AppTaskScaffold(
                titleWidget: _title(l10n),
                scrollController: _reviewScroll,
                confirmLeave: _confirmReviewLeave,
                actionsBuilder: (context, wide) => <Widget>[
                  if (viewData != null && viewData.allItems.isNotEmpty)
                    AppIconButton(
                      tooltip: l10n.navSearch,
                      icon: FLucideIcons.search,
                      onPress: _isBusy
                          ? null
                          : () => _resetReviewScroll(focusSearch: true),
                    ),
                  if (!wide)
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
        return PopScope(
          canPop: !_isBusy || _leaving,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop || !await _confirmReviewLeave() || !mounted) return;
            setState(() => _leaving = true);
            await WidgetsBinding.instance.endOfFrame;
            if (context.mounted) smartPop(context);
          },
          child: IngestCaptureFeedbackListener(
            child: DropTarget(
              onDragDone: _isBusy ? (_) {} : _onDrop,
              child: Focus(
                focusNode: _masterFocus,
                onKeyEvent: (_, event) => viewData == null
                    ? KeyEventResult.ignored
                    : _onMasterKey(viewData, event, wide: useMasterDetail),
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
      busy: _isBusy || _selection.selectedIds.isNotEmpty,
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
}
