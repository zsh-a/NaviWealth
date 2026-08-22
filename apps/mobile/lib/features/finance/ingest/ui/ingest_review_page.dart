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

class IngestReviewPage extends ConsumerStatefulWidget {
  const IngestReviewPage({super.key});

  @override
  ConsumerState<IngestReviewPage> createState() => _IngestReviewPageState();
}

class _IngestReviewPageState extends ConsumerState<IngestReviewPage> {
  String? _accountId;
  _IngestBusyState? _busy;
  final IngestCaptureLease _captureLease = IngestCaptureLease();
  final Map<String, ConfirmedIngestItem> _pendingFinalize = {};
  final IngestReviewSelection _selection = IngestReviewSelection();
  final FocusNode _masterFocus = FocusNode(debugLabel: 'ingest review master');
  IngestQualityReport? _latestQualityReport;

  bool get _isBusy => _busy != null || _captureLease.isHeld;

  @override
  void dispose() {
    _masterFocus.dispose();
    super.dispose();
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
          _scheduleSelectionPrune(viewData.items, ensureFocus: true);
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
        return IngestCaptureFeedbackListener(
          child: DropTarget(
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
}
