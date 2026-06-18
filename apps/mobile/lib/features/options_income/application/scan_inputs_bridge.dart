import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/core/sync/mutation_context.dart';
import '../../../domain/values/money.dart';
import '../../accounts/data/account_balances_provider.dart';
import '../../accounts/domain/account_balances.dart';
import '../../finance/data/domain/asset.dart';
import '../../finance/data/domain/enums.dart';
import '../../finance/data/domain/manual_asset_metadata.dart';
import '../../finance/data/repositories/providers.dart';
import '../../investment/data/providers.dart';

/// Bridge that derives the side inputs ScanController needs from the
/// existing investment / accounts providers.
///
/// Two outputs:
///   * `holdingsBySymbol` — share counts keyed by uppercase ticker
///   * `availableCash` — cash bucket usable as the per-trade cap denominator
class ScanSideInputs {
  const ScanSideInputs({
    required this.holdingsBySymbol,
    required this.availableCash,
  });

  final Map<String, int> holdingsBySymbol;
  final Money availableCash;
}

final scanSideInputsProvider = FutureProvider.autoDispose<ScanSideInputs>((
  ref,
) async {
  // Defaults to USD because yfinance options are US-only at MVP.
  const baseCurrency = 'USD';
  // currentUserId is used implicitly downstream — touching the provider
  // keeps the bridge invalidating when the user switches.
  await ref.watch(currentUserIdProvider)();
  Map<String, int> holdings;
  try {
    final snapshot = await ref.watch(devicePortfolioSnapshotProvider.future);
    holdings = _extractShares(snapshot);
  } catch (_) {
    holdings = const {};
  }
  final manualAssets = await ref.watch(manualAssetsStreamProvider.future);
  final balances = await ref.watch(accountBalancesByIdProvider.future);
  return ScanSideInputs(
    holdingsBySymbol: holdings,
    availableCash: optionsAvailableCashFromBalances(
      manualAssets: manualAssets,
      balancesByAccountId: balances,
      currency: baseCurrency,
    ),
  );
});

Map<String, int> _extractShares(Map<String, Object?>? snapshot) {
  if (snapshot == null) return const {};
  final raw = snapshot['holdings'];
  if (raw is! Map) return const {};
  final out = <String, int>{};
  raw.forEach((_, value) {
    if (value is! Map) return;
    final symbol = (value['symbol'] as String?)?.toUpperCase();
    final qtyRaw = value['net_quantity'];
    if (symbol == null || qtyRaw == null) return;
    final qty = Decimal.tryParse(qtyRaw.toString());
    if (qty == null) return;
    out[symbol] = qty.floor().toBigInt().toInt();
  });
  return out;
}

Money optionsAvailableCashFromBalances({
  required Iterable<Asset> manualAssets,
  required Map<String, AccountBalances> balancesByAccountId,
  String currency = 'USD',
}) {
  final upper = currency.trim().toUpperCase();
  var total = Decimal.zero;
  final seenAccountIds = <String>{};

  for (final asset in manualAssets) {
    if (asset.type != AssetType.cash) continue;
    if (asset.currency.toUpperCase() != upper) continue;
    final metadata = ManualAssetMetadata.decode(asset.metadataJson);
    if (metadata is! CashMetadata) continue;
    if (!seenAccountIds.add(metadata.accountId)) continue;
    final leg = balancesByAccountId[metadata.accountId]?.legFor(upper);
    if (leg == null) continue;
    total += leg.units;
  }

  if (total < Decimal.zero) total = Decimal.zero;
  return Money(total, upper);
}
