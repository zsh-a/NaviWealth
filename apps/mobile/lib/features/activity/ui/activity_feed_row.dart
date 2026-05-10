import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/entry_kind.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/posting.dart';
import '../../../data/repositories/journal_entry_repository.dart';
import '../../shared/entry_kind_badge.dart';
import '../../shared/postings_preview.dart';

class ActivityFeedEntryRow extends StatelessWidget {
  const ActivityFeedEntryRow({
    super.key,
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

    return FCard.raw(
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
            padding: const EdgeInsets.only(top: 2),
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
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '\u00B7',
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
            PostingsPreview(postings: entry.postings, accounts: accountsById),
          ],
        ),
      ),
    );
  }
}

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
