import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/ai/write/write.dart';
import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../data/domain/account.dart';
import '../../../data/domain/entry_kind.dart';
import '../../../data/domain/posting.dart';
import '../../../data/repositories/journal_entry_repository.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/entry_kind_labels.dart';
import '../../shared/postings_preview.dart';

/// Full-page detail surface for one journal entry. Pushed when the user
/// taps any row in the unified Activity timeline.
///
/// Layout (top → bottom):
///  1. Hero amount + title + date / time
///  2. AI Insight block (rule-based stub for now; future will hit the
///     AI agent through `aiExplainEntryProvider`)
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
    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.activityEntryDetailTitle),
        prefixes: [backHeaderAction(context)],
      ),
      childPad: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Wave 40 — surfaces when this journal entry was created
          // by an accepted AI proposal (propose_trade /
          // propose_expense / propose_liability_payment). Self-
          // gating: hidden otherwise.
          Align(
            alignment: Alignment.centerLeft,
            child: AiTouchMark(
              entityType: 'journal_entries',
              entityId: entry.entry.id,
            ),
          ),
          const SizedBox(height: 8),
          _HeroAmountCard(
            entry: entry,
            accountsById: accountsById,
            formatters: formatters,
          ),
          const SizedBox(height: 16),
          _AiInsightCard(entry: entry),
          const SizedBox(height: 16),
          FCard.raw(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: PostingsPreview(
                postings: entry.postings,
                accounts: accountsById,
              ),
            ),
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

class _HeroAmountCard extends StatelessWidget {
  const _HeroAmountCard({
    required this.entry,
    required this.accountsById,
    required this.formatters,
  });

  final JournalEntryWithPostings entry;
  final Map<String, Account> accountsById;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final classification = classifyEntryKind(
      postings: entry.postings,
      resolveCategory: (id) => accountsById[id]?.category,
    );
    final headline = _headlinePosting(entry.postings, accountsById);
    final dateLine = _formatDate(entry.entry.date);
    final title = entry.entry.narration.isEmpty ? '—' : entry.entry.narration;
    final payee = entry.entry.payee;
    final colors = context.theme.colors;
    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entryKindLabel(AppLocalizations.of(context), classification.kind),
              style: context.theme.typography.xs.copyWith(
                color: colors.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: context.theme.typography.lg.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (payee != null && payee.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                payee,
                style: context.theme.typography.sm.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (headline != null)
              SignedMoneyText(
                amount: headline.units,
                unit: headline.unit,
                formatters: formatters,
                style: TypographyTokens.numericTitle,
              ),
            const SizedBox(height: 4),
            Text(
              dateLine,
              style: context.theme.typography.xs.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiInsightCard extends StatelessWidget {
  const _AiInsightCard({required this.entry});

  final JournalEntryWithPostings entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final hint = _heuristicInsight(entry, l10n);
    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.auto_awesome_outlined,
                size: 16,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.activityEntryDetailAiExplanation,
                    style: context.theme.typography.sm.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hint ?? l10n.activityEntryDetailNoExplanation,
                    style: context.theme.typography.sm.copyWith(
                      color: colors.mutedForeground,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _heuristicInsight(
  JournalEntryWithPostings entry,
  AppLocalizations l10n,
) {
  final narration = entry.entry.narration.toLowerCase();
  if (narration.contains('netflix') ||
      narration.contains('spotify') ||
      narration.contains('prime') ||
      narration.contains('subscription')) {
    return 'Recurring subscription detected. Cancel anytime via the merchant\'s portal.';
  }
  if (narration.contains('rent') || narration.contains('mortgage')) {
    return 'Recurring monthly housing expense. Tagged for FIRE essentials baseline.';
  }
  if (narration.contains('salary') || narration.contains('payroll')) {
    return 'Primary income stream. Used to back-fill cash-flow projections.';
  }
  return null;
}

Posting? _headlinePosting(
  List<Posting> postings,
  Map<String, Account> accounts,
) {
  Posting? headline;
  Decimal? best;
  for (final p in postings) {
    final magnitude = p.units.abs();
    if (best == null || magnitude > best) {
      best = magnitude;
      headline = p;
    }
  }
  return headline;
}

String _formatDate(DateTime date) {
  final h = date.hour.toString().padLeft(2, '0');
  final m = date.minute.toString().padLeft(2, '0');
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} $h:$m';
}
