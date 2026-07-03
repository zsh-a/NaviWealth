import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/entry_kind.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';

import '../../../../core/ai/write/write.dart';
import '../../../../core/format/formatters.dart';
import '../../../../core/format/providers.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../data/repositories/journal_entry_providers.dart';
import '../../data/repositories/providers.dart';
import '../../shared/account_l10n.dart';
import '../../shared/entry_kind_labels.dart';
import '../data/activity_entry_insight_client.dart';

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
///  4. (Future) tags, notes, edit / delete actions
class ActivityEntryDetailPage extends ConsumerWidget {
  const ActivityEntryDetailPage({
    super.key,
    required this.entry,
    required this.accountsById,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final aiInsight = ref
        .watch(
          aiExplainEntryProvider(
            ActivityEntryInsightRequest(
              entry: entry,
              accountsById: accountsById,
              locale: Localizations.localeOf(context),
            ),
          ),
        )
        .value;
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    return ObjectDetailScaffold(
      title: l10n.activityEntryDetailTitle,
      actions: [
        if (classification.kind == EntryKind.expense)
          FHeaderAction(
            icon: const Icon(FLucideIcons.pencil),
            onPress: () => context.go(FinanceRoutes.expense(entry.entry.id)),
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
          // AiTouchMark: surfaces when this journal entry was created
          // by an accepted AI proposal. Self-gating: hidden otherwise.
          Align(
            alignment: Alignment.centerLeft,
            child: AiTouchMark(
              entityType: 'journal_entries',
              entityId: entry.entry.id,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          _HeroAmountCard(
            entry: entry,
            accountsById: accountsById,
            formatters: formatters,
          ),
          if (aiInsight != null) ...[
            const SizedBox(height: AppSpacing.s12),
            _AiInsightCard(insight: aiInsight),
          ],
          const SizedBox(height: AppSpacing.s12),
          _LedgerBreakdownCard(
            postings: entry.postings,
            accountsById: accountsById,
            formatters: formatters,
          ),
        ],
      ),
    );
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
          message: '$error',
          action: FButton(
            variant: FButtonVariant.ghost,
            onPress: () =>
                ref.invalidate(_activityEntryDetailProvider(entryId)),
            child: Text(l10n.commonRetry),
          ),
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
