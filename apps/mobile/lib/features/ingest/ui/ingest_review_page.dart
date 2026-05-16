/// §5.10.10 / S5a step ⑥–⑦ surface — the待确认 queue.
///
/// Calm Intelligence (§5.6): no chatbot, no glow; a single outline
/// sparkle in the header, surface-tone pills, typography-first rows.
/// The page never auto-applies anything — every write is the user's
/// explicit tap (§5.10.6). Strings are zh literals (S5a deviation,
/// see §5.10.9): a full ARB pass for one new page would trip the
/// Wave 42 parity gate for little user benefit on a zh-primary app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/visual/visual.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/enums.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
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
    final draftsAsync = ref.watch(pendingIngestDraftsProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);

    return FScaffold(
      header: FHeader.nested(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AiSparkle(size: 16),
            SizedBox(width: 6),
            Text('录入待确认'),
          ],
        ),
        prefixes: [backHeaderAction(context)],
        suffixes: [
          FHeaderAction(
            icon: const Icon(Icons.content_paste_outlined),
            onPress: _busy ? null : _openPasteDialog,
          ),
        ],
      ),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: accountsAsync.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (e, _) => Center(child: Text('账户加载失败：$e')),
          data: (accounts) => draftsAsync.when(
            loading: () => const Center(child: FCircularProgress()),
            error: (e, _) => Center(child: Text('待确认队列加载失败：$e')),
            data: (drafts) => _content(accounts, drafts),
          ),
        ),
      ),
    );
  }

  Widget _content(List<Account> accounts, List<IngestDraft> drafts) {
    if (drafts.isEmpty) {
      return _EmptyState(onPaste: _busy ? null : _openPasteDialog);
    }
    final payable = accounts
        .where((a) => !a.archived)
        .toList(growable: false);
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
            '支出账户',
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
                child: Text('全部确认 · 仅新增（$freshCount）'),
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
    if (accountId == null || accountId.isEmpty) {
      AppMessenger.show(context, ToastKind.warning, '请先选择支出账户');
      return;
    }
    setState(() => _busy = true);
    try {
      final svc = await ref.read(ingestConfirmServiceProvider.future);
      if (svc == null) {
        if (mounted) {
          AppMessenger.show(context, ToastKind.error, '服务尚未就绪');
        }
        return;
      }
      await svc.confirm(draft, fromAccountId: accountId);
      if (mounted) AppMessenger.show(context, ToastKind.success, '已记录');
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
    if (accountId == null || accountId.isEmpty) {
      AppMessenger.show(context, ToastKind.warning, '请先选择支出账户');
      return;
    }
    setState(() => _busy = true);
    try {
      final svc = await ref.read(ingestConfirmServiceProvider.future);
      if (svc == null) return;
      final n = await svc.confirmAllFresh(drafts, fromAccountId: accountId);
      if (mounted) {
        AppMessenger.show(context, ToastKind.success, '已记录 $n 笔');
      }
    } on IngestConfirmException catch (e) {
      if (mounted) AppMessenger.show(context, ToastKind.error, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPasteDialog() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴账单文本'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            maxLines: 10,
            minLines: 6,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '粘贴 CSV / 账单文本\n例如：2026-05-10,星巴克,-38.00,CNY',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('解析'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(ingestControllerProvider)
          .ingest(
            IngestSource(
              kind: IngestSourceKind.pasteText,
              payload: text,
              originLabel: '粘贴文本',
            ),
          );
      if (!mounted) return;
      if (result.isRejected) {
        AppMessenger.show(context, ToastKind.warning, result.rejectedReason!);
      } else if (result.total == 0) {
        AppMessenger.show(context, ToastKind.info, '未解析出可识别的交易');
      } else {
        AppMessenger.show(
          context,
          ToastKind.success,
          '解析 ${result.total} 笔（新增 ${result.newCount} · '
          '疑似重复 ${result.duplicateCount}）',
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
                p.categoryHint ?? '未分类',
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
                  child: const Text('跳过'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FButton(
                  variant: FButtonVariant.primary,
                  onPress: busy ? null : onConfirm,
                  child: const Text('记录'),
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
    final (label, state) = switch (verdict) {
      DedupVerdict.newTxn => ('新增', AiPillState.neutral),
      DedupVerdict.likelyDuplicate => ('疑似重复', AiPillState.selected),
      DedupVerdict.duplicate => ('重复', AiPillState.error),
    };
    return AiPill(label: label, state: state);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPaste});

  final VoidCallback? onPaste;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.move_to_inbox_outlined,
              size: 40,
              color: colors.mutedForeground.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              '没有待确认的记录',
              style: context.theme.typography.sm.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '粘贴账单 / CSV 文本，自动解析为草稿，\n去重对账后在这里确认入账。',
              textAlign: TextAlign.center,
              style: context.theme.typography.sm.copyWith(
                color: colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 16),
            FButton(
              variant: FButtonVariant.outline,
              onPress: onPaste,
              prefix: const Icon(Icons.content_paste_outlined),
              child: const Text('粘贴文本'),
            ),
          ],
        ),
      ),
    );
  }
}
