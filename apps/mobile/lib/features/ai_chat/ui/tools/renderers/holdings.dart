part of 'tool_invocation_renderers.dart';

// ---------------------------------------------------------------------------
// get_holdings -> mini holdings table.
// Payload: { holdings: { <asset_id>: { symbol, name, net_quantity,
//           avg_unit_cost, cost_basis, currency } }, ... }
// ---------------------------------------------------------------------------

class _HoldingsTable extends StatelessWidget {
  const _HoldingsTable({required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final outMap = _asMap(output);
    if (outMap == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final holdings = _asMap(outMap['holdings']);
    if (holdings == null || holdings.isEmpty) {
      return ToolResultSurface(
        child: _EmptyResult(message: l10n.aiToolHoldingsEmpty),
      );
    }

    final rows = <_HoldingRow>[];
    for (final entry in holdings.entries) {
      final m = _asMap(entry.value);
      if (m == null) continue;
      rows.add(
        _HoldingRow(
          assetId: entry.key,
          symbol: _asString(m['symbol']),
          name: _asString(m['name']),
          quantity: _asDouble(m['net_quantity']) ?? 0,
          costBasis: _asDouble(m['cost_basis']) ?? 0,
          avgCost: _asDouble(m['avg_unit_cost']),
          currency: _asString(m['currency']) ?? 'CNY',
        ),
      );
    }
    if (rows.isEmpty) {
      return ToolResultSurface(
        child: _EmptyResult(message: l10n.aiToolHoldingsEmpty),
      );
    }
    rows.sort((a, b) => b.costBasis.compareTo(a.costBasis));
    final visible = rows.take(_kMaxVisibleRows).toList();
    final hidden = rows.length - visible.length;

    return ToolResultSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  l10n.aiToolAssetColumn,
                  style: context.microCaptionStyle,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  l10n.aiToolQuantityColumn,
                  textAlign: TextAlign.right,
                  style: context.microCaptionStyle,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  l10n.aiToolCostColumn,
                  textAlign: TextAlign.right,
                  style: context.microCaptionStyle,
                ),
              ),
            ],
          ),
          for (final row in visible) _holdingRowTile(context, row),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: Text(
                l10n.aiToolHiddenItems(hidden),
                style: context.captionStyle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _holdingRowTile(BuildContext context, _HoldingRow row) {
    final qtyText = NumberFormat.decimalPattern().format(row.quantity);
    final primary = row.symbol ?? row.name ?? row.assetId;
    final secondary = row.symbol != null && row.name != null ? row.name! : null;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.theme.colors.border.withValues(
              alpha: AppOpacity.muted,
            ),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primary,
                  style: context.captionStyle.copyWith(
                    color: context.theme.colors.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (secondary != null)
                  Text(
                    secondary,
                    style: context.microCaptionStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              qtyText,
              textAlign: TextAlign.right,
              style: context.captionStyle.copyWith(
                color: context.theme.colors.foreground,
                fontFeatures: TypographyTokens.tabularFigures,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: MoneyText(
                amount: row.costBasis,
                currencyCode: row.currency,
                style: context.theme.typography.body.xs,
                color: context.theme.colors.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldingRow {
  const _HoldingRow({
    required this.assetId,
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.costBasis,
    required this.avgCost,
    required this.currency,
  });
  final String assetId;
  final String? symbol;
  final String? name;
  final double quantity;
  final double costBasis;
  final double? avgCost;
  final String currency;
}

// ---------------------------------------------------------------------------
// list_payment_accounts -> compact account picker preview.
// Payload: { accounts: [ { id, name, type, currency } ], total_count, truncated }
// ---------------------------------------------------------------------------

class _PaymentAccountsView extends StatelessWidget {
  const _PaymentAccountsView({required this.output});
  final Object? output;

  @override
  Widget build(BuildContext context) {
    final outMap = _asMap(output);
    if (outMap == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final raw = _asList(outMap['accounts']) ?? const <Object?>[];
    final rows = <_PaymentAccountRow>[];
    for (final item in raw) {
      final m = _asMap(item);
      if (m == null) continue;
      final id = _asString(m['id']) ?? _asString(m['account_id']);
      final name = _asString(m['name']);
      if (id == null && name == null) continue;
      rows.add(
        _PaymentAccountRow(
          id: id ?? name!,
          name: name ?? id!,
          type: _asString(m['type']) ?? '',
          currency: _asString(m['currency']) ?? '',
        ),
      );
    }
    if (rows.isEmpty) {
      return ToolResultSurface(
        child: _EmptyResult(message: l10n.aiToolPaymentAccountsEmpty),
      );
    }

    final visible = rows.take(_kMaxVisibleRows).toList();
    final total = (outMap['total_count'] is int)
        ? outMap['total_count']! as int
        : rows.length;
    final hidden = math.max(0, total - visible.length);

    return ToolResultSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.aiToolPaymentAccountsTitle,
            style: context.microCaptionStyle,
          ),
          const SizedBox(height: AppSpacing.s4),
          for (final row in visible) _paymentAccountTile(context, row),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: Text(
                l10n.aiToolHiddenAccounts(hidden),
                style: context.captionStyle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _paymentAccountTile(BuildContext context, _PaymentAccountRow row) {
    final meta = [
      if (row.type.isNotEmpty) row.type,
      if (row.currency.isNotEmpty) row.currency,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.theme.colors.border.withValues(
              alpha: AppOpacity.muted,
            ),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            FLucideIcons.landmark,
            size: AppIconSizes.sm,
            color: context.theme.colors.mutedForeground,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  style: context.captionStyle.copyWith(
                    color: context.theme.colors.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  meta.isEmpty ? row.id : meta,
                  style: context.microCaptionStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentAccountRow {
  const _PaymentAccountRow({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
  });

  final String id;
  final String name;
  final String type;
  final String currency;
}
