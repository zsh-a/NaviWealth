/// §5.10.10 / S5a step ⑥–⑦ surface — the review queue.
///
/// Calm Intelligence (§5.6): no chatbot, no glow; a single outline
/// sparkle in the header, surface-tone pills, typography-first rows.
/// The page never auto-applies anything — every write is the user's
/// explicit tap (§5.10.6). All copy is localized via AppLocalizations
/// (S5a.1 — full ARB pass; the data-layer parser tokens stay on the
/// FIR-99 allowlist by nature, see §5.10.9).
library;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../../../core/ai/visual/visual.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/forms/forms.dart';
import '../data/ingest_capture_source.dart';
import '../data/ingest_confirm_service.dart';
import '../data/providers.dart';
import '../domain/ingest_models.dart';

class IngestReviewPage extends ConsumerStatefulWidget {
  const IngestReviewPage({super.key});

  @override
  ConsumerState<IngestReviewPage> createState() => _IngestReviewPageState();
}

class _IngestReviewPageState extends ConsumerState<IngestReviewPage> {
  String? _accountId;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draftsAsync = ref.watch(pendingIngestDraftsProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);

    return FScaffold(
      header: FHeader.nested(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AiSparkle(size: 16),
            const SizedBox(width: 6),
            Text(l10n.ingestReviewTitle),
          ],
        ),
        prefixes: [backHeaderAction(context)],
        suffixes: [
          FHeaderAction(
            icon: const Icon(FLucideIcons.camera),
            onPress: _busy ? null : _captureCamera,
          ),
          FHeaderAction(
            icon: const Icon(FLucideIcons.paperclip),
            onPress: _busy ? null : _pickFile,
          ),
          FHeaderAction(
            icon: const Icon(FLucideIcons.clipboard),
            onPress: _busy ? null : _openPasteDialog,
          ),
        ],
      ),
      childPad: false,
      // §5.10.10 / S5c-native — drag a receipt/statement onto the page
      // (desktop/web). No-op on touch platforms.
      child: DropTarget(
        onDragDone: _busy ? (_) {} : _onDrop,
        child: Material(
          color: Colors.transparent,
          child: accountsAsync.when(
            loading: () => const Center(child: FCircularProgress()),
            error: (e, _) =>
                Center(child: Text(l10n.ingestAccountsLoadError('$e'))),
            data: (accounts) => draftsAsync.when(
              loading: () => const Center(child: FCircularProgress()),
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
      return _EmptyState(
        onPaste: _busy ? null : _openPasteDialog,
        onImport: _busy ? null : _pickFile,
        onCamera: _busy ? null : _captureCamera,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            l10n.ingestExpenseAccountLabel,
            style: context.theme.typography.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in payable)
                AiPill(
                  label: a.name,
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            itemCount: drafts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _DraftCard(
              draft: drafts[i],
              busy: _busy,
              onConfirm: () => _confirm(drafts[i], selectedId),
              onSkip: () => _skip(drafts[i]),
            ),
          ),
        ),
        if (freshCount > 0)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: FButton(
                variant: FButtonVariant.primary,
                onPress: _busy
                    ? null
                    : () => _confirmAllFresh(drafts, selectedId),
                child: Text(l10n.ingestConfirmAllFresh(freshCount)),
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
    setState(() => _busy = true);
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
      if (mounted) setState(() => _busy = false);
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
    setState(() => _busy = true);
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
      if (mounted) setState(() => _busy = false);
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
    setState(() => _busy = true);
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
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.busy,
    required this.onConfirm,
    required this.onSkip,
  });

  final IngestDraft draft;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final p = draft.parsed;
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.description,
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              MoneyText(
                amount: p.amountMinor.abs() / 100.0,
                currencyCode: p.currency,
                style: context.theme.typography.sm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                _ymd(p.occurredAt),
                style: context.theme.typography.xs.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                p.categoryHint ?? l10n.ingestUncategorized,
                style: context.theme.typography.xs.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
              const Spacer(),
              _VerdictPill(verdict: draft.verdict),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: busy ? null : onSkip,
                  child: Text(l10n.ingestSkip),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FButton(
                  variant: FButtonVariant.primary,
                  onPress: busy ? null : onConfirm,
                  child: Text(l10n.ingestConfirm),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _ymd(DateTime d) {
    final u = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)}';
  }
}

class _VerdictPill extends StatelessWidget {
  const _VerdictPill({required this.verdict});

  final DedupVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, state) = switch (verdict) {
      DedupVerdict.newTxn => (l10n.ingestVerdictNew, AiPillState.neutral),
      DedupVerdict.likelyDuplicate => (
        l10n.ingestVerdictLikely,
        AiPillState.selected,
      ),
      DedupVerdict.duplicate => (
        l10n.ingestVerdictDuplicate,
        AiPillState.error,
      ),
    };
    return AiPill(label: label, state: state);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onPaste,
    required this.onImport,
    required this.onCamera,
  });

  final VoidCallback? onPaste;
  final VoidCallback? onImport;
  final VoidCallback? onCamera;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FLucideIcons.inbox,
              size: 40,
              color: colors.mutedForeground.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.ingestEmptyTitle,
              style: context.theme.typography.sm.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.ingestEmptyBody,
              textAlign: TextAlign.center,
              style: context.theme.typography.sm.copyWith(
                color: colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: onCamera,
                  prefix: const Icon(FLucideIcons.camera),
                  child: Text(l10n.ingestCameraAction),
                ),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: onImport,
                  prefix: const Icon(FLucideIcons.paperclip),
                  child: Text(l10n.ingestImportFileAction),
                ),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: onPaste,
                  prefix: const Icon(FLucideIcons.clipboard),
                  child: Text(l10n.ingestPasteAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Multiline paste form, presented as a unified app sheet (replaces the
/// old Material `AlertDialog`). Returns the pasted text or null.
class _PasteSheet extends StatefulWidget {
  const _PasteSheet({required this.dirty});

  final FormDirtyController dirty;

  @override
  State<_PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends State<_PasteSheet> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.dirty.bindTextControllers([_controller]);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: l10n.ingestPasteTitle,
      footer: AppSheetFooter(
        submitLabel: l10n.ingestParseAction,
        cancelLabel: l10n.commonCancel,
        onSubmit: () {
          widget.dirty.markPristine();
          Navigator.of(context).pop(_controller.text);
        },
      ),
      child: FTextField(
        control: FTextFieldControl.managed(controller: _controller),
        autofocus: true,
        maxLines: 10,
        minLines: 6,
        hint: l10n.ingestPasteHint,
      ),
    );
  }
}
