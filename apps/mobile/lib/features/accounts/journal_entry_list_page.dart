import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/format/formatters.dart';
import '../../data/domain/account.dart';
import '../../data/domain/entry_kind.dart';
import '../../data/domain/enums.dart';
import '../../data/domain/posting.dart';
import '../../data/repositories/journal_entry_providers.dart';
import '../../data/repositories/journal_entry_repository.dart';
import '../../data/repositories/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../shared/entry_kind_badge.dart';
import '../shared/postings_preview.dart';

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

    return FScaffold(
      header: FHeader.nested(title: Text(l10n.journalTitle)),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: journalAsync.when(
          data: (entries) {
            if (entries.isEmpty) return const _EmptyJournal();
            final accountsById = <String, Account>{
              for (final a in accountsAsync.value ?? const <Account>[]) a.id: a,
            };
            return _JournalList(entries: entries, accountsById: accountsById);
          },
          loading: () => const Center(child: FCircularProgress()),
          error: (e, _) => Center(child: Text(l10n.journalLoadError('$e'))),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 48,
              color: context.theme.colors.mutedForeground,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.journalEmptyHint,
              textAlign: TextAlign.center,
              style: context.theme.typography.sm.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ],
        ),
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
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final je = entries[index];
        return _JournalEntryRow(
          entry: je,
          accountsById: accountsById,
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
    required this.dateLabel,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    final summary = _summariseAmount(entry.postings, accountsById);

    return Container(
      decoration: BoxDecoration(
        color: context.theme.colors.muted,
        borderRadius: BorderRadius.circular(8),
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
                        style: context.theme.typography.sm,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (summary != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          summary,
                          style: context.theme.typography.sm.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: context.theme.colors.foreground,
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      EntryKindBadge(
                        classification: classification,
                        compact: true,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dateLabel,
                        style: context.theme.typography.xs2.copyWith(
                          color: context.theme.colors.mutedForeground,
                        ),
                      ),
                      if (entry.entry.payee != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '· ${entry.entry.payee}',
                            style: context.theme.typography.xs2.copyWith(
                              color: context.theme.colors.mutedForeground,
                            ),
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
  String? _summariseAmount(
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
    if (headline == null) return null;
    final value = headline.units;
    return '${value > Decimal.zero ? '+' : ''}${_format(value)} ${headline.unit}';
  }
}

String _format(Decimal d) {
  if (d == Decimal.zero) return '0';
  final s = d.toString();
  if (!s.contains('.')) return s;
  final trimmed = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}
