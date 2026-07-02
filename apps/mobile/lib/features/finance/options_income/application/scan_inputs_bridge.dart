import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show innerJoin;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/finance/accounts/domain/account_balances.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/manual_asset_metadata.dart';
import 'package:naviwealth/features/investment/data/providers.dart';

/// Bridge that derives the side inputs ScanController needs from the
/// existing investment / accounts providers.
///
/// Two outputs:
///   * `holdingsBySymbol` — share counts keyed by uppercase ticker
///   * `exposureBySymbol` — current portfolio weight keyed by uppercase ticker
///   * `availableCash` — cash bucket usable as the per-trade cap denominator
class ScanSideInputs {
  const ScanSideInputs({
    required this.holdingsBySymbol,
    required this.exposureBySymbol,
    required this.availableCash,
  });

  final Map<String, int> holdingsBySymbol;
  final Map<String, Decimal> exposureBySymbol;
  final Money availableCash;
}

const _snapshotTimeout = Duration(seconds: 4);

final scanSideInputsProvider = FutureProvider.autoDispose<ScanSideInputs>((
  ref,
) async {
  final logger = AppLogger.instance;
  // Defaults to USD because yfinance options are US-only at MVP.
  const baseCurrency = 'USD';
  // currentUserId is used implicitly downstream — touching the provider
  // keeps the bridge invalidating when the user switches.
  final currentUserId = ref.watch(currentUserIdProvider);
  final snapshotFuture = ref.watch(devicePortfolioSnapshotProvider.future);
  final dbFuture = ref.watch(appDatabaseProvider.future);

  final ownerUserId = await currentUserId();
  Map<String, int> holdings;
  Map<String, Decimal> exposures;
  try {
    final snapshot = await snapshotFuture.timeout(_snapshotTimeout);
    holdings = _extractShares(snapshot);
    exposures = _extractExposures(snapshot);
    logger.d(
      'options-income side inputs: portfolio ok '
      'holdings=${holdings.length} exposures=${exposures.length}',
    );
  } catch (e, st) {
    logger.w(
      'options-income side inputs: portfolio snapshot unavailable',
      error: e,
      stackTrace: st,
    );
    holdings = const {};
    exposures = const {};
  }
  Money availableCash;
  try {
    availableCash = await _optionsAvailableCashFromDb(
      db: await dbFuture,
      ownerUserId: ownerUserId,
      currency: baseCurrency,
    );
    logger.d(
      'options-income side inputs: cash ok '
      '${availableCash.amount} ${availableCash.currency}',
    );
  } catch (e, st) {
    logger.w(
      'options-income side inputs: cash balance read failed',
      error: e,
      stackTrace: st,
    );
    availableCash = Money.zero(baseCurrency);
  }
  return ScanSideInputs(
    holdingsBySymbol: holdings,
    exposureBySymbol: exposures,
    availableCash: availableCash,
  );
});

Future<Money> _optionsAvailableCashFromDb({
  required AppDatabase db,
  required String ownerUserId,
  String currency = 'USD',
}) async {
  final upper = currency.trim().toUpperCase();
  final cashRows =
      await (db.select(db.assets)
            ..where((t) => t.ownerUserId.equals(ownerUserId))
            ..where((t) => t.deletedAt.isNull())
            ..where((t) => t.type.equalsValue(AssetType.cash))
            ..where((t) => t.currency.equals(upper)))
          .get();
  final accountIds = <String>{};
  for (final row in cashRows) {
    final metadata = ManualAssetMetadata.decode(row.metadataJson);
    if (metadata is CashMetadata) accountIds.add(metadata.accountId);
  }
  if (accountIds.isEmpty) {
    AppLogger.instance.d(
      'options-income cash lookup: no linked cash accounts '
      'cashAssets=${cashRows.length} currency=$upper',
    );
    return Money.zero(upper);
  }

  final rows =
      await (db.select(db.postings).join([
              innerJoin(
                db.journalEntries,
                db.journalEntries.id.equalsExp(db.postings.journalEntryId),
              ),
            ])
            ..where(db.postings.ownerUserId.equals(ownerUserId))
            ..where(db.postings.accountId.isIn(accountIds))
            ..where(db.postings.unit.equals(upper))
            ..where(db.postings.deletedAt.isNull())
            ..where(db.journalEntries.deletedAt.isNull()))
          .get();
  var total = Decimal.zero;
  for (final row in rows) {
    total += row.readTable(db.postings).units;
  }
  if (total < Decimal.zero) total = Decimal.zero;
  AppLogger.instance.d(
    'options-income cash lookup: cashAssets=${cashRows.length} '
    'linkedAccounts=${accountIds.length} postings=${rows.length} '
    'total=$total $upper',
  );
  return Money(total, upper);
}

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

Map<String, Decimal> _extractExposures(Map<String, Object?>? snapshot) {
  if (snapshot == null) return const {};
  final raw = snapshot['holdings'];
  if (raw is! Map) return const {};
  final out = <String, Decimal>{};
  raw.forEach((_, value) {
    if (value is! Map) return;
    final symbol = (value['symbol'] as String?)?.toUpperCase();
    final weightRaw = value['weight'];
    if (symbol == null || weightRaw == null) return;
    final weight = Decimal.tryParse(weightRaw.toString());
    if (weight == null) return;
    out[symbol] = weight.clamp(Decimal.zero, Decimal.one);
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
