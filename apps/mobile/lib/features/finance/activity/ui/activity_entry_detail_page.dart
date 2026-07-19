import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/entry_kind.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';

import '../../../../core/ai/write/write.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/format/providers.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../data/repositories/journal_entry_providers.dart';
import '../../data/repositories/providers.dart';
import '../../shared/l10n/account_l10n.dart';
import '../../shared/l10n/entry_kind_labels.dart';
import '../data/activity_entry_insight_client.dart';
import '../data/activity_feed_provider.dart';
import 'activity_feed_grouping.dart';
import 'activity_feed_row.dart';

part 'activity_entry_detail_helpers.dart';
part 'activity_entry_detail_hero.dart';
part 'activity_entry_detail_insight.dart';
part 'activity_entry_detail_ledger.dart';

/// Full-page detail surface for one journal entry. Pushed when the user
/// taps any row in the unified Activity timeline.
///
/// Layout (top → bottom):
///  1. Hero amount + title + date / time
///  2. Local insight block for deterministic transaction patterns
///  3. Posting breakdown (debits / credits in the existing widget)
///  4. Edit (expense) + delete
class ActivityEntryDetailPage extends ConsumerStatefulWidget {
  const ActivityEntryDetailPage({
    super.key,
    required this.entry,
    required this.accountsById,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;

  @override
  ConsumerState<ActivityEntryDetailPage> createState() =>
      _ActivityEntryDetailPageState();
}

class _ActivityEntryDetailPageState
    extends ConsumerState<ActivityEntryDetailPage> {
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final aiInsight = ref
        .watch(
          aiExplainEntryProvider(
            ActivityEntryInsightRequest(
              entry: widget.entry,
              accountsById: widget.accountsById,
              locale: Localizations.localeOf(context),
            ),
          ),
        )
        .value;
    final classification = classifyEntryKind(
      postings: widget.entry.postings,
      resolveCategory: (id) => widget.accountsById[id]?.category,
    );
    return ObjectDetailScaffold(
      title: l10n.activityEntryDetailTitle,
      actions: [
        if (classification.kind == EntryKind.expense)
          AppHeaderAction(
            semanticsLabel: l10n.expenseFormEditTitle,
            icon: const Icon(FLucideIcons.pencil),
            onPress: _deleting
                ? null
                : () =>
                      context.go(FinanceRoutes.expense(widget.entry.entry.id)),
          ),
        AppHeaderAction(
          semanticsLabel: l10n.commonDelete,
          icon: _deleting
              ? const SizedBox.square(
                  dimension: AppIconSizes.md,
                  child: FCircularProgress(size: .xs),
                )
              : const Icon(FLucideIcons.trash2),
          onPress: _deleting ? null : _deleteEntry,
        ),
      ],
      childPad: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s16,
          AppSpacing.s8,
          AppSpacing.s16,
          AppSpacing.s32,
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AiTouchMark(
              entityType: 'journal_entries',
              entityId: widget.entry.entry.id,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          _HeroAmountCard(
            entry: widget.entry,
            accountsById: widget.accountsById,
            formatters: formatters,
          ),
          if (aiInsight != null) ...[
            const SizedBox(height: AppSpacing.s12),
            _AiInsightCard(insight: aiInsight),
          ],
          const SizedBox(height: AppSpacing.s12),
          _LedgerBreakdownCard(
            postings: widget.entry.postings,
            accountsById: widget.accountsById,
            formatters: formatters,
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEntry() async {
    final confirmed = await _confirmDelete(context);
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    await _deleteActivityEntry(context, ref, widget.entry.entry.id);
    if (mounted) setState(() => _deleting = false);
  }
}

Future<bool?> _confirmDelete(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showConfirmDialog(
    context: context,
    title: Text(l10n.activityEntryDeleteTitle),
    body: Text(l10n.activityEntryDeleteBody),
    cancelLabel: l10n.commonCancel,
    confirmLabel: l10n.commonDelete,
    destructive: true,
  );
}

Future<void> _deleteActivityEntry(
  BuildContext context,
  WidgetRef ref,
  String entryId,
) async {
  final l10n = AppLocalizations.of(context);
  final feedbackContext = Navigator.of(context).context;
  AppMessenger.cacheOverlay(feedbackContext);
  try {
    final repo = await ref.read(journalEntryRepositoryProvider.future);
    await repo.softDelete(entryId);
    ref.invalidate(activityFeedProvider);
    if (context.mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(FinanceRoutes.activity);
      }
      AppMessenger.show(
        feedbackContext,
        ToastKind.success,
        l10n.activityEntryDeleted,
        duration: const Duration(seconds: 6),
        actionLabel: l10n.commonUndo,
        onAction: () => unawaited(
          _restoreDeletedEntry(feedbackContext, repo, entryId, l10n),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.activityEntryDeleteFailed,
      );
    }
  }
}

Future<void> _restoreDeletedEntry(
  BuildContext context,
  JournalEntryRepository repo,
  String entryId,
  AppLocalizations l10n,
) async {
  try {
    await repo.restoreSoftDeleted(entryId);
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.success, l10n.commonUndoSucceeded);
    }
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.error, l10n.commonUndoFailed);
    }
  }
}

class ActivityEntryDetailArgs {
  const ActivityEntryDetailArgs({
    required this.entry,
    required this.accountsById,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;
}

class ActivityEntryDetailRoute extends ConsumerWidget {
  const ActivityEntryDetailRoute({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detailAsync = ref.watch(_activityEntryDetailProvider(entryId));
    return detailAsync.when(
      loading: () => AppPageScaffold(
        title: l10n.activityEntryDetailTitle,
        child: const Center(child: FCircularProgress()),
      ),
      error: (error, _) => AppPageScaffold(
        title: l10n.activityEntryDetailTitle,
        child: AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: userSafeErrorMessage(context, error),
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(_activityEntryDetailProvider(entryId)),
        ),
      ),
      data: (detail) {
        if (detail == null) {
          return AppPageScaffold(
            title: l10n.activityEntryDetailTitle,
            child: AppEmptyState.error(
              title: l10n.routeNotFoundTitle,
              message: l10n.routeNotFoundMessage('/activity/entry/$entryId'),
            ),
          );
        }
        return ActivityEntryDetailPage(
          entry: detail.entry,
          accountsById: detail.accountsById,
        );
      },
    );
  }
}

final _activityEntryDetailProvider = FutureProvider.autoDispose
    .family<_ActivityEntryDetailData?, String>((ref, entryId) async {
      final repo = await ref.watch(journalEntryRepositoryProvider.future);
      final accounts = await ref.watch(allAccountsStreamProvider.future);
      final entry = await repo.getById(entryId);
      if (entry == null) return null;
      return _ActivityEntryDetailData(
        entry: entry,
        accountsById: {for (final account in accounts) account.id: account},
      );
    });

class _ActivityEntryDetailData {
  const _ActivityEntryDetailData({
    required this.entry,
    required this.accountsById,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;
}
