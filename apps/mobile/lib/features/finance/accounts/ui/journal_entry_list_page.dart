import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../activity/ui/activity_feed_grouping.dart';
import '../../activity/ui/activity_feed_row.dart';

/// Read surface for the `journal_entries` / `postings` stack.
/// Lists every JE the user has written through any ledger form
/// with its full posting layout one tap away.
class JournalEntryListPage extends ConsumerWidget {
  const JournalEntryListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final journalAsync = ref.watch(journalEntriesWithPostingsStreamProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);

    return AppPageScaffold(
      title: l10n.journalTitle,
      childPad: false,
      child: journalAsync.whenOrLoading(
        context: context,
        data: (entries) {
          if (entries.isEmpty) return const _EmptyJournal();
          final accountsById = <String, Account>{
            for (final a in accountsAsync.value ?? const <Account>[]) a.id: a,
          };
          return AdaptiveContentFrame(
            maxWidth: AdaptiveMaxWidth.page,
            expandSinglePrimary: true,
            primary: _JournalList(entries: entries, accountsById: accountsById),
          );
        },
        error: (_, _) => Center(
          child: AppEmptyState.error(
            title: l10n.commonLoadFailed,
            retryLabel: l10n.commonRetry,
            onRetry: () {
              ref
                ..invalidate(journalEntriesWithPostingsStreamProvider)
                ..invalidate(accountsStreamProvider);
            },
          ),
        ),
      ),
    );
  }
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.history,
      title: l10n.journalEmptyHint,
      action: FButton(
        onPress: () => context.push(FinanceRoutes.tradeEntry),
        prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
        child: Text(l10n.tradeEntryAppBarTitle),
      ),
    );
  }
}

class _JournalList extends StatelessWidget {
  const _JournalList({required this.entries, required this.accountsById});

  final List<JournalEntryWithPostings> entries;
  final Map<String, Account> accountsById;

  @override
  Widget build(BuildContext context) {
    final formatter = AppFormatters(locale: Localizations.localeOf(context));
    final groups = groupActivityEntriesByDay(
      entries,
      accountsById: accountsById,
    );
    final items = _flattenJournalItems(groups);
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (context, index) {
        return switch (items[index]) {
          _JournalDayItem(:final day, :final isFirst) => Padding(
            padding: EdgeInsets.only(
              top: isFirst ? AppSpacing.s0 : AppSpacing.s8,
              bottom: AppSpacing.s8,
            ),
            child: SectionHeader(
              title: formatter.date(day),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s4,
              ),
            ),
          ),
          _JournalEntryItem(
            :final entry,
            :final isFirstInDay,
            :final isLastInDay,
          ) =>
            Padding(
              padding: EdgeInsets.only(
                bottom: isLastInDay ? AppSpacing.s12 : AppSpacing.s0,
              ),
              child: ActivityFeedEntrySurface(
                key: ValueKey('journal-entry-${entry.entry.id}'),
                entry: entry,
                accountsById: accountsById,
                formatter: formatter,
                isFirstInGroup: isFirstInDay,
                isLastInGroup: isLastInDay,
                showTime: false,
              ),
            ),
        };
      },
    );
  }
}

List<_JournalListItem> _flattenJournalItems(List<ActivityDaySection> groups) {
  final items = <_JournalListItem>[];
  for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
    final group = groups[groupIndex];
    items.add(_JournalDayItem(day: group.day, isFirst: groupIndex == 0));
    for (var entryIndex = 0; entryIndex < group.entries.length; entryIndex++) {
      items.add(
        _JournalEntryItem(
          entry: group.entries[entryIndex],
          isFirstInDay: entryIndex == 0,
          isLastInDay: entryIndex == group.entries.length - 1,
        ),
      );
    }
  }
  return items;
}

sealed class _JournalListItem {
  const _JournalListItem();
}

class _JournalDayItem extends _JournalListItem {
  const _JournalDayItem({required this.day, required this.isFirst});

  final DateTime day;
  final bool isFirst;
}

class _JournalEntryItem extends _JournalListItem {
  const _JournalEntryItem({
    required this.entry,
    required this.isFirstInDay,
    required this.isLastInDay,
  });

  final JournalEntryWithPostings entry;
  final bool isFirstInDay;
  final bool isLastInDay;
}
