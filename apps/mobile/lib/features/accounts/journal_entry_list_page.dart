import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/formatters.dart';
import '../../data/domain/account.dart';
import '../../data/domain/entry_kind.dart';
import '../../data/domain/enums.dart';
import '../../data/domain/posting.dart';
import '../../data/repositories/journal_entry_providers.dart';
import '../../data/repositories/journal_entry_repository.dart';
import '../../data/repositories/providers.dart';
import '../../design_system/design_system.dart';
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

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(l10n.journalTitle),
      ),
      body: journalAsync.when(
        data: (entries) {
          if (entries.isEmpty) return const _EmptyJournal();
          final accountsById = <String, Account>{
            for (final a in accountsAsync.value ?? const <Account>[]) a.id: a,
          };
          return _JournalList(entries: entries, accountsById: accountsById);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.journalLoadError('$e'))),
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
        padding: Spacing.pageMobile,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: Spacing.s12),
            Text(
              l10n.journalEmptyHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      padding: Spacing.pageMobile,
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: Spacing.s8),
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
    final scheme = Theme.of(context).colorScheme;
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    final summary = _summariseAmount(entry.postings, accountsById);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: Radii.brSm,
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Drop the default ExpansionTile divider lines so the card
        // border + the PostingsPreview's inner divider line do the
        // visual work.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: Spacing.s12,
            vertical: Spacing.s4,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            Spacing.s8,
            0,
            Spacing.s8,
            Spacing.s8,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  entry.entry.narration,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (summary != null)
                Padding(
                  padding: const EdgeInsets.only(left: Spacing.s8),
                  child: Text(
                    summary,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: scheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: Spacing.s4),
            child: Row(
              children: [
                EntryKindBadge(classification: classification, compact: true),
                const SizedBox(width: Spacing.s8),
                Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (entry.entry.payee != null) ...[
                  const SizedBox(width: Spacing.s8),
                  Flexible(
                    child: Text(
                      '· ${entry.entry.payee}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          children: [
            PostingsPreview(postings: entry.postings, accounts: accountsById),
          ],
        ),
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
      if (account.category != AccountCategory.asset &&
          account.category != AccountCategory.liability) {
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
