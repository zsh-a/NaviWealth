import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/formatters.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/entry_kind.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/posting.dart';
import '../../../data/repositories/journal_entry_providers.dart';
import '../../../data/repositories/journal_entry_repository.dart';
import '../../../data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/entry_kind_badge.dart';
import '../../shared/postings_preview.dart';

/// Timeline feed that groups journal entries by date and renders each
/// as an expandable glass row.
class ActivityFeed extends ConsumerWidget {
  const ActivityFeed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final journalAsync = ref.watch(journalEntriesWithPostingsStreamProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);

    return journalAsync.when(
      data: (entries) {
        if (entries.isEmpty) return _EmptyFeed(message: l10n.activityFeedEmpty);
        final accountsById = <String, Account>{
          for (final a in accountsAsync.value ?? const <Account>[]) a.id: a,
        };
        final groups = _groupByDate(entries);
        final formatter = AppFormatters(
          locale: Localizations.localeOf(context),
        );
        return _FeedList(
          groups: groups,
          accountsById: accountsById,
          formatter: formatter,
          l10n: l10n,
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load feed: $e')),
    );
  }
}

// ---------------------------------------------------------------------------
// Date grouping
// ---------------------------------------------------------------------------

enum _DateGroup { today, yesterday, thisWeek, earlier }

List<_DateSection> _groupByDate(List<JournalEntryWithPostings> entries) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final weekStart = today.subtract(Duration(days: today.weekday - 1));

  final map = <_DateGroup, List<JournalEntryWithPostings>>{};
  for (final e in entries) {
    final d = DateTime(e.entry.date.year, e.entry.date.month, e.entry.date.day);
    final group = d.isAtSameMomentAs(today)
        ? _DateGroup.today
        : d.isAtSameMomentAs(yesterday)
            ? _DateGroup.yesterday
            : !d.isBefore(weekStart)
                ? _DateGroup.thisWeek
                : _DateGroup.earlier;
    map.putIfAbsent(group, () => []).add(e);
  }

  return [
    for (final g in _DateGroup.values)
      if (map[g]?.isNotEmpty ?? false)
        _DateSection(group: g, entries: map[g]!),
  ];
}

class _DateSection {
  const _DateSection({required this.group, required this.entries});

  final _DateGroup group;
  final List<JournalEntryWithPostings> entries;
}

// ---------------------------------------------------------------------------
// Feed list
// ---------------------------------------------------------------------------

class _FeedList extends StatelessWidget {
  const _FeedList({
    required this.groups,
    required this.accountsById,
    required this.formatter,
    required this.l10n,
  });

  final List<_DateSection> groups;
  final Map<String, Account> accountsById;
  final AppFormatters formatter;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final items = <_FeedItem>[];
    for (final section in groups) {
      items.add(_FeedItem.header(section.group));
      for (final entry in section.entries) {
        items.add(_FeedItem.entry(entry));
      }
    }

    return ListView.builder(
      padding: Spacing.pageMobile.copyWith(
        bottom: Spacing.pageMobile.bottom +
            Spacing.floatingBarClearance +
            MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return switch (item) {
          _FeedItemHeader(:final group) => _DateSectionHeader(
              group: group,
              l10n: l10n,
            ),
          _FeedItemEntry(:final entry) => Padding(
              padding: const EdgeInsets.only(bottom: Spacing.s8),
              child: _FeedEntryRow(
                entry: entry,
                accountsById: accountsById,
                formatter: formatter,
              ),
            ),
        };
      },
    );
  }
}

sealed class _FeedItem {
  const _FeedItem();
  factory _FeedItem.header(_DateGroup group) = _FeedItemHeader;
  factory _FeedItem.entry(JournalEntryWithPostings entry) = _FeedItemEntry;
}

class _FeedItemHeader extends _FeedItem {
  const _FeedItemHeader(this.group);
  final _DateGroup group;
}

class _FeedItemEntry extends _FeedItem {
  const _FeedItemEntry(this.entry);
  final JournalEntryWithPostings entry;
}

// ---------------------------------------------------------------------------
// Date section header
// ---------------------------------------------------------------------------

class _DateSectionHeader extends StatelessWidget {
  const _DateSectionHeader({required this.group, required this.l10n});

  final _DateGroup group;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final title = switch (group) {
      _DateGroup.today => l10n.activityFeedToday,
      _DateGroup.yesterday => l10n.activityFeedYesterday,
      _DateGroup.thisWeek => l10n.activityFeedThisWeek,
      _DateGroup.earlier => l10n.activityFeedEarlier,
    };
    return GlassSectionHeader(title: title);
  }
}

// ---------------------------------------------------------------------------
// Feed entry row
// ---------------------------------------------------------------------------

class _FeedEntryRow extends StatelessWidget {
  const _FeedEntryRow({
    required this.entry,
    required this.accountsById,
    required this.formatter,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;
  final AppFormatters formatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    final summary = _summariseAmount(entry.postings, accountsById);
    final timeStr = _formatTime(entry.entry.date);

    return LiquidGlassCard(
      layer: GlassLayer.tertiary,
      padding: EdgeInsets.zero,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
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
          leading: EntryKindBadge(
            classification: classification,
            compact: true,
          ),
          title: Text(
            entry.entry.narration,
            style: theme.textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: Spacing.s2),
            child: Row(
              children: [
                if (entry.entry.payee != null) ...[
                  Flexible(
                    child: Text(
                      entry.entry.payee!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.s4),
                    child: Text(
                      '·',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                Text(
                  timeStr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          trailing: summary != null
              ? Text(
                  summary,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: scheme.onSurface,
                  ),
                )
              : null,
          children: [
            PostingsPreview(
              postings: entry.postings,
              accounts: accountsById,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _formatTime(DateTime date) {
  final h = date.hour.toString().padLeft(2, '0');
  final m = date.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

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
  return '${value > Decimal.zero ? '+' : ''}${_formatDecimal(value)} ${headline.unit}';
}

String _formatDecimal(Decimal d) {
  if (d == Decimal.zero) return '0';
  final s = d.toString();
  if (!s.contains('.')) return s;
  final trimmed = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: Spacing.pageMobile,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: Spacing.s12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
