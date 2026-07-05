/// §5.10.10 / S5a step ⑥–⑦ surface — the review queue.
///
/// Calm Intelligence (§5.6): no chatbot, no glow; a single outline
/// sparkle in the header, surface-tone pills, typography-first rows.
/// The page never auto-applies anything — every write is the user's
/// explicit tap (§5.10.6). All copy is localized via AppLocalizations
/// (S5a.1 — full ARB pass; the data-layer parser tokens stay on the
/// allowlist by nature, see §5.10.9).
library;

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
import '../data/ingest_capture_source.dart';
import '../data/ingest_confirm_service.dart';
import '../data/providers.dart';
import '../domain/ingest_models.dart';

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

  bool get _isBusy => _busy != null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draftsAsync = ref.watch(pendingIngestDraftsProvider);
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
        FHeaderAction(
          icon: const Icon(FLucideIcons.camera),
          onPress: _isBusy ? null : _captureCamera,
        ),
        FHeaderAction(
          icon: const Icon(FLucideIcons.paperclip),
          onPress: _isBusy ? null : _pickFile,
        ),
        FHeaderAction(
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
            error: (e, _) =>
                Center(child: Text(l10n.ingestAccountsLoadError('$e'))),
            data: (accounts) => draftsAsync.whenOrLoading(
              error: (e, _) =>
                  Center(child: Text(l10n.ingestQueueLoadError('$e'))),
              data: (drafts) => _content(l10n, accounts, drafts),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _captureCamera() async {
    final source = await ref.read(cameraIngestCaptureProvider).capture();
    if (source == null || !mounted) return;
    await _runIngest(source);
  }

  Future<void> _onDrop(DropDoneDetails detail) async {
    if (detail.files.isEmpty) return;
    for (final file in detail.files) {
      final source = await xFileToIngestSource(file);
      if (source == null || !mounted) continue;
      await _runIngest(source);
    }
  }

  Widget _content(
    AppLocalizations l10n,
    List<Account> accounts,
    List<IngestDraft> drafts,
  ) {
    if (drafts.isEmpty) {
      final busy = _busy;
      if (busy != null) return _ProcessingState(state: busy);
      return _EmptyState(
        onPaste: _isBusy ? null : _openPasteDialog,
        onImport: _isBusy ? null : _pickFile,
        onCamera: _isBusy ? null : _captureCamera,
      );
    }
    final payable = accounts.where((a) => !a.archived).toList(growable: false);
    final selectedId = _accountId ?? _defaultAccountId(payable);
    final freshCount = drafts
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
            itemBuilder: (context, i) => _DraftCard(
              draft: drafts[i],
              busy: _isBusy,
              onConfirm: () => _confirm(drafts[i], selectedId),
              onSkip: () => _skip(drafts[i]),
            ),
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
              child: FButton(
                variant: FButtonVariant.primary,
                onPress: _isBusy
                    ? null
                    : () => _confirmAllFresh(drafts, selectedId),
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
        title: l10n.ingestRecordingTitle,
        message: l10n.ingestRecordingBody,
        icon: FLucideIcons.badgeCheck,
      ),
    );
    try {
      final svc = await ref.read(ingestConfirmServiceProvider.future);
      if (svc == null) {
        if (mounted) {
          AppMessenger.show(
            context,
            ToastKind.error,
            l10n.ingestServiceNotReady,
          );
        }
        return;
      }
      await svc.confirm(draft, fromAccountId: accountId);
      if (mounted) {
        AppMessenger.show(context, ToastKind.success, l10n.ingestRecorded);
      }
    } on IngestConfirmException catch (e) {
      if (mounted) AppMessenger.show(context, ToastKind.error, e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _skip(IngestDraft draft) async {
    final svc = await ref.read(ingestConfirmServiceProvider.future);
    await svc?.dismiss(draft);
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
        title: l10n.ingestRecordingTitle,
        message: l10n.ingestRecordingBody,
        icon: FLucideIcons.badgeCheck,
      ),
    );
    try {
      final svc = await ref.read(ingestConfirmServiceProvider.future);
      if (svc == null) return;
      final n = await svc.confirmAllFresh(drafts, fromAccountId: accountId);
      if (mounted) {
        AppMessenger.show(context, ToastKind.success, l10n.ingestRecordedN(n));
      }
    } on IngestConfirmException catch (e) {
      if (mounted) AppMessenger.show(context, ToastKind.error, e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _openPasteDialog() async {
    final text = await showGuardedFormSheet<String>(
      context: context,
      builder: (_, dirty) => _PasteSheet(dirty: dirty),
    );
    if (text == null || text.trim().isEmpty) return;
    await _runIngest(
      IngestSource(
        kind: IngestSourceKind.pasteText,
        payload: text,
        // Stable non-display breadcrumb (persisted + traced).
        originLabel: 'paste',
      ),
    );
  }

  Future<void> _pickFile() async {
    // The system picker provides its own modal UI; _runIngest owns the
    // busy state for the parse that follows.
    final source = await ref.read(ingestCaptureSourceProvider).pickFile();
    if (source == null || !mounted) return;
    await _runIngest(source);
  }

  /// Shared tail for every capture entry (paste / file): run the
  /// pipeline and surface the outcome with one consistent toast set.
  Future<void> _runIngest(IngestSource source) async {
    final l10n = AppLocalizations.of(context);
    final sourceLabel = _sourceLabel(l10n, source);
    setState(
      () => _busy = _IngestBusyState(
        title: l10n.ingestProcessingTitle,
        message: l10n.ingestProcessingBody(sourceLabel),
        icon: _sourceIcon(source.kind),
      ),
    );
    try {
      final result = await ref.read(ingestControllerProvider).ingest(source);
      if (!mounted) return;
      if (result.isRejected) {
        AppMessenger.show(context, ToastKind.warning, result.rejectedReason!);
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
    } finally {
      if (mounted) setState(() => _busy = null);
    }
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
