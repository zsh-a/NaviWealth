import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/entry_kind.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/posting.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';

import '../../../core/ai/write/write.dart';
import '../../../core/format/formatters.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../shared/account_l10n.dart';
import '../../shared/entry_kind_labels.dart';

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
    final aiInsight = _heuristicInsight(entry, l10n);
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
          if (aiInsight != null) ...[
            const SizedBox(height: 12),
            _AiInsightCard(insight: aiInsight),
          ],
          const SizedBox(height: 12),
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
    final dateLine = formatters.dateTime(entry.entry.date);
    final title = entry.entry.narration.isEmpty ? '—' : entry.entry.narration;
    final payee = entry.entry.payee;
    final colors = context.theme.colors;
    final tint = _tintForKind(classification.kind, colors);
    return SoftCard(
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tint.withValues(alpha: 0.12),
              colors.foreground.withValues(alpha: 0.02),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _iconForKind(classification.kind),
                      color: tint,
                      size: AppIconSizes.md,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Text(
                      entryKindLabel(
                        AppLocalizations.of(context),
                        classification.kind,
                      ),
                      style: context.theme.typography.xs.copyWith(
                        color: colors.mutedForeground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s16),
              Text(
                title,
                style: context.theme.typography.lg.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              if (payee != null && payee.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s4),
                Text(
                  payee,
                  style: context.theme.typography.sm.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.s16),
              if (headline != null)
                SignedMoneyText(
                  amount: headline.units,
                  unit: headline.unit,
                  formatters: formatters,
                  style: TypographyTokens.numericDisplay,
                ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                dateLine,
                style: context.theme.typography.xs.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiInsightCard extends StatelessWidget {
  const _AiInsightCard({required this.insight});

  final String insight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
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
            child: Icon(FLucideIcons.sparkles, size: 16, color: colors.primary),
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
                  insight,
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
    );
  }
}

class _LedgerBreakdownCard extends StatelessWidget {
  const _LedgerBreakdownCard({
    required this.postings,
    required this.accountsById,
    required this.formatters,
  });

  final List<Posting> postings;
  final Map<String, Account> accountsById;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totals = _computeUnitTotals(postings);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FLucideIcons.listTree,
                size: AppIconSizes.sm,
                color: context.theme.colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  l10n.activityEntryDetailLedgerTitle,
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              _LedgerMetaPill(
                label: l10n.activityEntryDetailLegCount(postings.length),
                icon: FLucideIcons.gitBranch,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          for (var i = 0; i < postings.length; i++) ...[
            if (i > 0) const FDivider(),
            _DetailPostingRow(
              posting: postings[i],
              accountsById: accountsById,
              formatters: formatters,
            ),
          ],
          if (totals.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            const FDivider(),
            const SizedBox(height: AppSpacing.s8),
            for (final entry in totals.entries)
              _DetailUnitBalanceRow(
                unit: entry.key,
                total: entry.value,
                formatters: formatters,
              ),
          ],
        ],
      ),
    );
  }
}

class _DetailPostingRow extends StatelessWidget {
  const _DetailPostingRow({
    required this.posting,
    required this.accountsById,
    required this.formatters,
  });

  final Posting posting;
  final Map<String, Account> accountsById;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    final account = accountsById[posting.accountId];
    final accountLabel = account == null
        ? posting.accountId
        : localizedAccountPath(
            l10n,
            account,
            accountsById,
            dropSystemRoot: false,
          );
    final cost = posting.cost;
    final price = posting.price;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  accountLabel,
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              SignedMoneyText(
                amount: posting.units,
                unit: posting.unit,
                formatters: formatters,
                style: context.theme.typography.sm.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (cost != null || price != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Wrap(
              spacing: AppSpacing.s6,
              runSpacing: AppSpacing.s4,
              children: [
                if (cost != null)
                  _LedgerMetaPill(
                    label: _costLabel(cost),
                    icon: FLucideIcons.box,
                  ),
                if (price != null)
                  _LedgerMetaPill(
                    label: '@ ${_format(price.perUnit)} ${price.currency}',
                    icon: FLucideIcons.badgeCent,
                  ),
              ],
            ),
          ],
          if (account == null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              posting.accountId,
              style: context.theme.typography.xs2.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LedgerMetaPill extends StatelessWidget {
  const _LedgerMetaPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppIconSizes.xs, color: colors.mutedForeground),
          const SizedBox(width: AppSpacing.s4),
          Text(
            label,
            style: context.theme.typography.xs2.copyWith(
              color: colors.mutedForeground,
              fontFeatures: TypographyTokens.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailUnitBalanceRow extends StatelessWidget {
  const _DetailUnitBalanceRow({
    required this.unit,
    required this.total,
    required this.formatters,
  });

  final String unit;
  final Decimal total;
  final AppFormatters formatters;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s4),
      child: Row(
        children: [
          Icon(
            FLucideIcons.circleAlert,
            size: AppIconSizes.xs,
            color: colors.destructive,
          ),
          const SizedBox(width: AppSpacing.s6),
          Expanded(
            child: Text(
              'Σ $unit',
              style: context.theme.typography.xs.copyWith(
                color: colors.destructive,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SignedMoneyText(
            amount: total,
            unit: unit,
            formatters: formatters,
            style: context.theme.typography.xs.copyWith(
              fontWeight: FontWeight.w700,
            ),
            color: colors.destructive,
          ),
        ],
      ),
    );
  }
}

String? _heuristicInsight(
  JournalEntryWithPostings entry,
  AppLocalizations l10n,
) {
  final text = [
    entry.entry.narration,
    if (entry.entry.payee != null) entry.entry.payee!,
  ].join(' ').toLowerCase();
  if (_containsAny(text, const [
    'netflix',
    'spotify',
    'prime',
    'subscription',
    '订阅',
    '会员',
    '自动续费',
    '续费',
    '月费',
  ])) {
    return l10n.activityEntryDetailInsightSubscription;
  }
  if (_containsAny(text, const [
    'rent',
    'mortgage',
    'housing',
    '房租',
    '租金',
    '房贷',
    '按揭',
    '物业',
  ])) {
    return l10n.activityEntryDetailInsightHousing;
  }
  if (_containsAny(text, const [
    'salary',
    'payroll',
    'wage',
    '工资',
    '薪资',
    '薪水',
    '发薪',
    '奖金',
  ])) {
    return l10n.activityEntryDetailInsightIncome;
  }
  return null;
}

bool _containsAny(String text, List<String> keywords) {
  return keywords.any(text.contains);
}

Posting? _headlinePosting(
  List<Posting> postings,
  Map<String, Account> accounts,
) {
  Posting? headline;
  Decimal? best;
  Posting? fallback;
  Decimal? fallbackBest;
  for (final p in postings) {
    final magnitude = p.units.abs();
    if (fallbackBest == null || magnitude > fallbackBest) {
      fallbackBest = magnitude;
      fallback = p;
    }

    final account = accounts[p.accountId];
    if (account == null) continue;
    if (account.category != AccountSide.asset &&
        account.category != AccountSide.liability) {
      continue;
    }
    if (best == null || magnitude > best) {
      best = magnitude;
      headline = p;
    }
  }
  return headline ?? fallback;
}

IconData _iconForKind(EntryKind kind) {
  switch (kind) {
    case EntryKind.income:
      return FLucideIcons.arrowDownLeft;
    case EntryKind.expense:
      return FLucideIcons.shoppingBag;
    case EntryKind.payment:
      return FLucideIcons.banknote;
    case EntryKind.transfer:
      return FLucideIcons.arrowLeftRight;
    case EntryKind.trade:
      return FLucideIcons.chartLine;
    case EntryKind.adjustment:
      return FLucideIcons.slidersHorizontal;
    case EntryKind.opening:
      return FLucideIcons.flag;
    case EntryKind.other:
      return FLucideIcons.receipt;
  }
}

Color _tintForKind(EntryKind kind, FColors colors) {
  switch (kind) {
    case EntryKind.income:
    case EntryKind.trade:
      return colors.primary;
    case EntryKind.expense:
    case EntryKind.payment:
    case EntryKind.transfer:
    case EntryKind.adjustment:
    case EntryKind.opening:
    case EntryKind.other:
      return colors.mutedForeground;
  }
}

String _costLabel(Cost cost) {
  final lot = cost.lotId;
  final base = '{${_format(cost.perUnit)} ${cost.currency}}';
  return lot == null ? base : '$base $lot';
}

String _format(Decimal value) {
  if (value == Decimal.zero) return '0';
  final text = value.toString();
  if (!text.contains('.')) return text;
  final trimmed = text.replaceFirst(RegExp(r'\.?0+$'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}

Map<String, Decimal> _computeUnitTotals(List<Posting> postings) {
  final totals = <String, Decimal>{};
  for (final posting in postings) {
    totals.update(
      posting.unit,
      (existing) => existing + posting.units,
      ifAbsent: () => posting.units,
    );
  }
  totals.removeWhere((_, value) => value == Decimal.zero);
  return totals;
}
