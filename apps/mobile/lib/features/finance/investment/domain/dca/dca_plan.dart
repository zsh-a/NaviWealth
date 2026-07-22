import 'package:decimal/decimal.dart';

import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

import 'dca_simulator.dart';

final class DcaPlan {
  const DcaPlan({
    required this.id,
    required this.allocations,
    required this.amountPerContribution,
    required this.currency,
    required this.market,
    required this.frequency,
    required this.nextDueAt,
    required this.endAt,
    required this.lastExecutedAt,
    required this.enabled,
    required this.createdAt,
    required this.sync,
  });

  final String id;
  final List<DcaAllocation> allocations;
  final Decimal amountPerContribution;
  final String currency;
  final AssetMarket market;
  final DcaFrequency frequency;
  final DateTime nextDueAt;
  final DateTime? endAt;
  final DateTime? lastExecutedAt;
  final bool enabled;
  final DateTime createdAt;
  final SyncMeta sync;

  bool get isDue => enabled && !nextDueAt.isAfter(DateTime.now());
}

DateTime nextDcaDueDate(DateTime from, DcaFrequency frequency) {
  final utc = from.toUtc();
  final monthDelta = frequency == DcaFrequency.monthly ? 1 : 3;
  final firstOfTarget = DateTime.utc(utc.year, utc.month + monthDelta);
  final firstOfFollowing = DateTime.utc(
    firstOfTarget.year,
    firstOfTarget.month + 1,
  );
  final lastDay = firstOfFollowing.subtract(const Duration(days: 1)).day;
  return DateTime.utc(
    firstOfTarget.year,
    firstOfTarget.month,
    utc.day.clamp(1, lastDay),
  );
}
