import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/posting.dart';

import '../../core/format/formatters.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import 'account_l10n.dart';

/// Read-only ledger card that mirrors the Beancount
/// posting layout: account path on the left, signed `units` and (when
/// present) cost / price annotations on the right, with a Σ row at the
/// bottom that surfaces the per-currency unit-balance check.
///
/// Used in:
///   * Journal-entry list expanded row.
///   * AI proposal cards.
///   * Trade / expense form preview before submit.
///
/// The widget intentionally takes a flat `accounts` lookup and
/// resolves names + parent paths internally so callers don't have to
/// pre-compute display strings. When an account id is unknown (most
/// often during a fresh sync) the widget falls back to the raw id —
/// the JE still renders, just with the bare id as a placeholder name.
class PostingsPreview extends StatelessWidget {
  const PostingsPreview({
    super.key,
    required this.postings,
    required this.accounts,
    this.title,
    this.showUnitBalanceTotals = true,
  });

  final List<Posting> postings;

  /// Account dictionary keyed by id. Only used for display; the
  /// invariant validator runs against the postings directly.
  final Map<String, Account> accounts;

  /// Optional title rendered above the leg list (typically the JE
  /// narration). Kept optional so AI proposal cards that already render
  /// their own header don't double up.
  final String? title;

  /// When `true`, a Σ-per-unit footer surfaces unbalanced amounts so
  /// the editor preview can flag a draft as not-yet-balanced. Read-only
  /// callers (list expansion) keep this `true` since a balanced JE
  /// renders zeros and is invisible enough.
  final bool showUnitBalanceTotals;

  @override
  Widget build(BuildContext context) {
    final unitTotals = _computeUnitTotals(postings);

    return Container(
      decoration: BoxDecoration(
        color: context.theme.colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.theme.colors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null && title!.isNotEmpty) ...[
            Text(
              title!,
              style: context.theme.typography.sm,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
          for (final p in postings) ...[
            _PostingRow(posting: p, accounts: accounts),
            const SizedBox(height: AppSpacing.s4),
          ],
          if (showUnitBalanceTotals && unitTotals.isNotEmpty) ...[
            const FDivider(),
            ...unitTotals.entries.map(
              (e) => _UnitBalanceRow(unit: e.key, total: e.value),
            ),
          ],
        ],
      ),
    );
  }
}

class _PostingRow extends StatelessWidget {
  const _PostingRow({required this.posting, required this.accounts});

  final Posting posting;
  final Map<String, Account> accounts;

  @override
  Widget build(BuildContext context) {
    final account = accounts[posting.accountId];
    final l10n = AppLocalizations.of(context);
    final accountLabel = account == null
        ? posting.accountId
        : localizedAccountPath(l10n, account, accounts, dropSystemRoot: false);

    final cost = posting.cost;
    final price = posting.price;
    final formatters = AppFormatters(locale: Localizations.localeOf(context));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                accountLabel,
                style: context.theme.typography.sm,
                overflow: TextOverflow.ellipsis,
              ),
              if (cost != null)
                Text(
                  _costLabel(cost),
                  style: context.theme.typography.xs2.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              if (price != null)
                Text(
                  '@ ${price.perUnit} ${price.currency}',
                  style: context.theme.typography.xs2.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        SignedMoneyText(
          amount: posting.units,
          unit: posting.unit,
          formatters: formatters,
          style: context.theme.typography.sm,
        ),
      ],
    );
  }
}

class _UnitBalanceRow extends StatelessWidget {
  const _UnitBalanceRow({required this.unit, required this.total});

  final String unit;
  final Decimal total;

  @override
  Widget build(BuildContext context) {
    final balanced = total == Decimal.zero;
    final tone = balanced
        ? SemanticColors.of(context).success
        : context.theme.colors.destructive;
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s2),
      child: Row(
        children: [
          Icon(
            balanced ? FLucideIcons.circleCheck : FLucideIcons.circleAlert,
            size: AppIconSizes.xs,
            color: tone,
          ),
          const SizedBox(width: AppSpacing.s4),
          Expanded(
            child: Text(
              'Σ $unit',
              style: context.theme.typography.xs2.copyWith(color: tone),
            ),
          ),
          SignedMoneyText(
            amount: total,
            unit: unit,
            formatters: formatters,
            style: context.theme.typography.xs2,
            color: tone,
          ),
        ],
      ),
    );
  }
}

String _costLabel(Cost cost) {
  final lot = cost.lotId;
  return lot == null
      ? '{${_format(cost.perUnit)} ${cost.currency}}'
      : '{${_format(cost.perUnit)} ${cost.currency}, $lot}';
}

/// Render a [Decimal] without trailing zeros — keeps the right column
/// from sprawling when most amounts are integer share counts.
String _format(Decimal d) {
  if (d == Decimal.zero) return '0';
  final s = d.toString();
  if (!s.contains('.')) return s;
  final trimmed = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}

/// Per-unit Σ over the postings, **without** running them through the
/// FxRateSource. The footer is meant to flag *unit-level* imbalance —
/// which is what users care about during entry — and the cross-currency
/// invariant check still runs on the repo's create path. Returns a map
/// keyed by `unit` with the running total, dropping units that already
/// sum to exactly zero so a balanced JE renders an empty footer.
Map<String, Decimal> _computeUnitTotals(List<Posting> postings) {
  final totals = <String, Decimal>{};
  for (final p in postings) {
    totals.update(
      p.unit,
      (existing) => existing + p.units,
      ifAbsent: () => p.units,
    );
  }
  totals.removeWhere((_, v) => v == Decimal.zero);
  return totals;
}
