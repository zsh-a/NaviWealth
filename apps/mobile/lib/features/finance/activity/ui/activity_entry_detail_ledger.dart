part of 'activity_entry_detail_page.dart';

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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.activityEntryDetailLedgerTitle,
                  style: context.labelStyle,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppBadge(
                label: l10n.activityEntryDetailLegCount(postings.length),
                icon: FLucideIcons.gitBranch,
                size: AppBadgeSize.compact,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          const AppDivider(horizontalPadding: 0),
          for (var i = 0; i < postings.length; i++) ...[
            if (i > 0) const AppDivider(horizontalPadding: 0),
            _DetailPostingRow(
              posting: postings[i],
              accountsById: accountsById,
              formatters: formatters,
            ),
          ],
          if (totals.isNotEmpty) ...[
            const AppDivider(horizontalPadding: 0),
            const SizedBox(height: AppSpacing.s12),
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
                  style: context.mediumLabelStyle.copyWith(height: 1.35),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              SignedMoneyText(
                amount: posting.units,
                unit: _displayUnit(posting.unit),
                formatters: formatters,
                style: context.labelStyle,
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
                  AppBadge(
                    label: _costLabel(cost),
                    icon: FLucideIcons.box,
                    size: AppBadgeSize.compact,
                  ),
                if (price != null)
                  AppBadge(
                    label: '@ ${_format(price.perUnit)} ${price.currency}',
                    icon: FLucideIcons.badgeCent,
                    size: AppBadgeSize.compact,
                  ),
              ],
            ),
          ],
          // account == null 时 accountLabel 已回退为 posting.accountId，
          // 无需额外兜底文本。数据库验证：当前无孤立 posting 数据。
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
              'Σ ${_displayUnit(unit)}',
              style: context.captionLabelStyle.copyWith(
                color: colors.destructive,
              ),
            ),
          ),
          SignedMoneyText(
            amount: total,
            unit: _displayUnit(unit),
            formatters: formatters,
            style: context.captionLabelStyle,
            color: colors.destructive,
          ),
        ],
      ),
    );
  }
}
