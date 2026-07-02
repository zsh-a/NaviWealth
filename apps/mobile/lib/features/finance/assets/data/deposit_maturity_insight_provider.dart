import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/manual_asset_metadata.dart';

const int kDepositMaturityWindowDays = 14;

class DepositMaturitySummary {
  const DepositMaturitySummary({required this.count, required this.days});

  final int count;
  final int days;
}

DepositMaturitySummary? summarizeDepositMaturities({
  required Iterable<Asset> assets,
  required DateTime now,
  int windowDays = kDepositMaturityWindowDays,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final candidates = <int>[];
  for (final asset in assets) {
    if (asset.type != AssetType.bankDepositTerm) continue;
    final metadata = ManualAssetMetadata.decode(asset.metadataJson);
    if (metadata is! DepositMetadata || metadata.maturityDate == null) {
      continue;
    }
    final maturity = metadata.maturityDate!;
    final maturityDay = DateTime(maturity.year, maturity.month, maturity.day);
    final days = maturityDay.difference(today).inDays;
    if (days < 0 || days > windowDays) continue;
    candidates.add(days);
  }
  if (candidates.isEmpty) return null;
  candidates.sort();
  return DepositMaturitySummary(
    count: candidates.length,
    days: candidates.first,
  );
}

final depositMaturityInsightProvider = Provider<DepositMaturitySummary?>((ref) {
  final assets = ref.watch(manualAssetsStreamProvider).value;
  if (assets == null) return null;
  return summarizeDepositMaturities(assets: assets, now: DateTime.now());
});
