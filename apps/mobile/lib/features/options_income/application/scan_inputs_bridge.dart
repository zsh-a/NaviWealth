import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/core/sync/mutation_context.dart';
import '../../../domain/values/money.dart';
import '../../investment/data/providers.dart';

/// Bridge that derives the side inputs ScanController needs from the
/// existing investment / accounts providers.
///
/// Two outputs:
///   * `holdingsBySymbol` — share counts keyed by uppercase ticker
///   * `availableCash` — cash bucket usable as the per-trade cap denominator
///
/// `availableCash` is a coarse default in P1 (high sentinel); refining it
/// to read the actual cash account total is tracked separately. The
/// scorer treats this as a per-trade cap, so a generous default does not
/// silently approve dangerous positions — the user's
/// `maxCapitalPerTradePct` still applies.
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
  final defaultCash = Money(Decimal.parse('1000000'), baseCurrency);
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
  return ScanSideInputs(holdingsBySymbol: holdings, availableCash: defaultCash);
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
