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
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    final summary = _summariseAmount(entry.postings, accountsById);
    final timeStr = _formatTime(entry.entry.date);

    return FCard.raw(
      child: FAccordion(
        children: [
          FAccordionItem(
            title: Row(
              children: [
                EntryKindBadge(classification: classification, compact: true),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.entry.narration,
                        style: context.theme.typography.sm,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            if (entry.entry.payee != null) ...[
                              Flexible(
                                child: Text(
                                  entry.entry.payee!,
                                  style: context.theme.typography.xs2.copyWith(
                                    color: context.theme.colors.mutedForeground,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Text(
                                  '\u00B7',
                                  style: context.theme.typography.xs2.copyWith(
                                    color: context.theme.colors.mutedForeground,
                                  ),
                                ),
                              ),
                            ],
                            Text(
                              timeStr,
                              style: context.theme.typography.xs2.copyWith(
                                color: context.theme.colors.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (summary != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    summary,
                    style: context.theme.typography.sm.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: context.theme.colors.foreground,
                    ),
                  ),
                ],
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
