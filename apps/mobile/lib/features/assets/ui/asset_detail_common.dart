import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../data/domain/asset.dart';
import '../../../data/domain/enums.dart';
import '../../../domain/entities/historical_bar.dart';
import '../../../domain/services/market_data_service.dart';
import '../../../domain/values/asset_market.dart';
import '../asset_detail_providers.dart';

class AssetDetailMetricRow extends StatelessWidget {
  const AssetDetailMetricRow({
    super.key,
    required this.label,
    this.value,
    this.trailing,
  });

  final String label;
  final String? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing ?? Text(value ?? '\u2014', style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class AssetDetailErrorCard extends StatelessWidget {
  const AssetDetailErrorCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FCard.raw(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}

PriceHistoryKey? assetDetailHistoryKey(Asset asset) {
  final market = assetMarketFromWire(asset.market);
  if (market == null || market == AssetMarket.unknown) return null;
  return PriceHistoryKey(symbol: asset.symbol, market: market, days: 30);
}

Decimal? dailyChangeFromHistory(
  AsyncValue<MarketResponse<List<HistoricalBar>>>? historyAsync,
  Decimal quantity,
) {
  final bars = historyAsync?.value?.data;
  if (bars == null || bars.length < 2) return null;
  final last = bars[bars.length - 1].close;
  final prev = bars[bars.length - 2].close;
  return (last - prev) * quantity;
}

String formatAssetDetailQuantity(Decimal qty) {
  final fmt = NumberFormat.decimalPatternDigits(decimalDigits: 4);
  final raw = fmt.format(qty.toDouble());
  if (!raw.contains('.')) return raw;
  return raw.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

int assetDetailPriceFractionDigits(AssetType type) {
  switch (type) {
    case AssetType.crypto:
      return 6;
    case AssetType.stock:
    case AssetType.etf:
    case AssetType.mutualFund:
    case AssetType.bond:
      return 2;
    default:
      return 2;
  }
}
