import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/entry_kind.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../shared/ui/entry_kind_badge.dart';
import '../../shared/ui/postings_preview.dart';

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
        data: (entries) {
          if (entries.isEmpty) return const _EmptyJournal();
          final accountsById = <String, Account>{
            for (final a in accountsAsync.value ?? const <Account>[]) a.id: a,
          };
          return _JournalList(entries: entries, accountsById: accountsById);
        },
        error: (_, _) => Center(
          child: AppEmptyState.error(
            title: l10n.commonLoadFailed,
            action: FButton(
              variant: FButtonVariant.ghost,
              onPress: () {
                ref
                  ..invalidate(journalEntriesWithPostingsStreamProvider)
                  ..invalidate(accountsStreamProvider);
              },
              child: Text(l10n.commonRetry),
            ),
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
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.s16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
      itemBuilder: (context, index) {
        final je = entries[index];
        return _JournalEntryRow(
          entry: je,
          accountsById: accountsById,
          formatter: formatter,
          dateLabel: formatter.date(je.entry.date),
        );
      },
    );
  }
}

class _JournalEntryRow extends StatelessWidget {
  const _JournalEntryRow({
    required this.entry,
    required this.accountsById,
    required this.formatter,
    required this.dateLabel,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;
  final AppFormatters formatter;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    final headline = _headlinePosting(entry.postings, accountsById);

    return Container(
      decoration: BoxDecoration(
        color: context.theme.colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.theme.colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: FAccordion(
        children: [
          FAccordionItem(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.entry.narration,
                        style: context.theme.typography.body.sm,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (headline != null)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.s8),
                        child: SignedMoneyText(
                          amount: headline.units,
                          unit: headline.unit,
                          formatters: formatter,
                          style: context.mediumLabelStyle,
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s4),
                  child: Row(
                    children: [
                      EntryKindIndicator(
                        classification: classification,
                        compact: true,
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Text(dateLabel, style: context.microCaptionStyle),
                      if (entry.entry.payee != null) ...[
                        const SizedBox(width: AppSpacing.s8),
                        Flexible(
                          child: Text(
                            '· ${entry.entry.payee}',
                            style: context.microCaptionStyle,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            child: PostingsPreview(
              postings: entry.postings,
              accounts: accountsById,
            ),
          ),
        ],
      ),
    );
  }

  /// Pick a single "headline amount" for the collapsed row. We use
  /// the largest |units| posting on an asset / cash account, which
  /// matches the "what changed for me" intuition for transfers,
  /// trades, expenses and dividends alike. Returns `null` when no
  /// posting matches (e.g. unit-self-balanced split with no cash leg).
  Posting? _headlinePosting(
    List<Posting> postings,
    Map<String, Account> accounts,
  ) {
    Posting? headline;
    Decimal? best;
    for (final p in postings) {
      final account = accounts[p.accountId];
      if (account == null) continue;
      if (account.category != AccountSide.asset &&
          account.category != AccountSide.liability) {
        continue;
      }
      final magnitude = p.units.abs();
      if (best == null || magnitude > best) {
        best = magnitude;
        headline = p;
      }
    }
    return headline;
  }
}
