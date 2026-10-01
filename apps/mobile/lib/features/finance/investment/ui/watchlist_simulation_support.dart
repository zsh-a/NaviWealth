import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_repository.dart';
import 'package:naviwealth/features/finance/market/domain/a_share_identity.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';

enum WatchlistSimulationQuoteUnavailableReason {
  loading,
  requestFailed,
  missing,
  stale,
  previousCloseMissing,
  differentDay,
  invalid,
}

/// One eligibility decision feeds the projection, holdings and write request.
class WatchlistSimulationQuoteInputs {
  const WatchlistSimulationQuoteInputs({
    required this.changeByItemId,
    required this.reasonByItemId,
    required this.quoteAtByItemId,
    required this.latestQuoteAt,
  });

  final Map<String, Decimal?> changeByItemId;
  final Map<String, WatchlistSimulationQuoteUnavailableReason> reasonByItemId;
  final Map<String, DateTime> quoteAtByItemId;
  final DateTime? latestQuoteAt;
}

WatchlistSimulationQuoteInputs resolveWatchlistSimulationQuoteInputs({
  required List<WatchlistQuoteSnapshot> snapshots,
  required List<WatchlistSimulationPosition> positions,
  bool loading = false,
}) {
  final snapshotById = {
    for (final snapshot in snapshots) snapshot.item.id: snapshot,
  };
  final reasons = <String, WatchlistSimulationQuoteUnavailableReason>{};
  final dates = <String, DateTime>{};
  DateTime? latestDay;
  for (final position in positions) {
    final id = position.watchlistItemId;
    final snapshot = snapshotById[id];
    final quote = snapshot?.quote;
    if (quote != null) dates[id] = quote.asOf;
    final reason = switch (snapshot) {
      null =>
        loading
            ? WatchlistSimulationQuoteUnavailableReason.loading
            : WatchlistSimulationQuoteUnavailableReason.missing,
      _ when snapshot.isLoading =>
        WatchlistSimulationQuoteUnavailableReason.loading,
      _ when snapshot.hasError =>
        WatchlistSimulationQuoteUnavailableReason.requestFailed,
      _ when quote == null => WatchlistSimulationQuoteUnavailableReason.missing,
      _ when snapshot.response!.isStale =>
        WatchlistSimulationQuoteUnavailableReason.stale,
      _
          when !_quoteSymbolMatchesItem(quote.symbol, snapshot.item) ||
              quote.price <= Decimal.zero ||
              (quote.previousClose != null &&
                  quote.previousClose! < Decimal.zero) =>
        WatchlistSimulationQuoteUnavailableReason.invalid,
      _ when quote.changePercent == null =>
        WatchlistSimulationQuoteUnavailableReason.previousCloseMissing,
      _ => null,
    };
    if (reason != null) {
      reasons[id] = reason;
    } else {
      final day = watchlistSimulationUtcDay(quote!.asOf);
      if (latestDay == null || day.isAfter(latestDay)) latestDay = day;
    }
  }
  final changes = <String, Decimal?>{};
  DateTime? latestQuoteAt;
  for (final position in positions) {
    final id = position.watchlistItemId;
    final quote = snapshotById[id]?.quote;
    if (!reasons.containsKey(id) && quote != null) {
      if (watchlistSimulationUtcDay(quote.asOf) != latestDay) {
        reasons[id] = WatchlistSimulationQuoteUnavailableReason.differentDay;
      } else {
        changes[id] = quote.changePercent;
        if (latestQuoteAt == null || quote.asOf.isAfter(latestQuoteAt)) {
          latestQuoteAt = quote.asOf;
        }
      }
    }
    changes.putIfAbsent(id, () => null);
  }
  return WatchlistSimulationQuoteInputs(
    changeByItemId: changes,
    reasonByItemId: reasons,
    quoteAtByItemId: dates,
    latestQuoteAt: latestQuoteAt,
  );
}

bool _quoteSymbolMatchesItem(String symbol, WatchlistItem item) {
  if (item.market == AssetMarket.cnA) {
    final canonical = tryCanonicalAShareSymbol(symbol);
    return canonical != null &&
        canonical == tryCanonicalAShareSymbol(item.symbol);
  }
  return symbol.trim().toUpperCase() == item.symbol.trim().toUpperCase();
}

/// Longest accepted paper simulation name. Mirrors the repository guard so the
/// form can reject an over-long name before the write is attempted.
const int kWatchlistSimulationNameMaxLength = 80;

/// `us_stock:AAPL` → `AAPL`. Simulation rows can outlive the watchlist item
/// they referenced, so every label falls back to the encoded id.
String watchlistSimulationSymbolFromId(String id) {
  final separator = id.indexOf(':');
  return separator < 0 ? id : id.substring(separator + 1);
}

String watchlistSimulationSymbolLabel(
  WatchlistItem? item, {
  required String fallbackId,
}) => item?.displaySymbol ?? watchlistSimulationSymbolFromId(fallbackId);

/// `Apple Inc. (AAPL)` when the item is still in the watchlist, otherwise the
/// bare symbol.
String watchlistSimulationItemLabel(
  BuildContext context,
  WatchlistItem? item, {
  required String fallbackId,
}) {
  if (item == null) return watchlistSimulationSymbolFromId(fallbackId);
  final name = item.localizedName(Localizations.localeOf(context).languageCode);
  return name == null ? item.displaySymbol : '$name (${item.displaySymbol})';
}

/// Truncates to UTC midnight — observations are keyed by UTC calendar day.
DateTime watchlistSimulationUtcDay(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// Prints a 0..1 ratio weight as a two-decimal percentage for an editable
/// field, so an equal split reads `16.67` instead of `16.66666667`.
String watchlistSimulationPercentText(Decimal weight) =>
    (weight * Decimal.fromInt(100)).round(scale: 2).toString();

/// Parses an editable percentage back into a 0..1 ratio.
Decimal watchlistSimulationPercentToRatio(Decimal percent) =>
    (percent / Decimal.fromInt(100)).toDecimal(scaleOnInfinitePrecision: 8);

/// Splits [totalPercent] across [ids] at two-decimal precision so the printed
/// values add up to exactly [totalPercent].
///
/// Naively printing `100 / 3` as `33.33` three times totals `99.99` and is then
/// rejected by the strict 100% guard — the single most common way users got
/// stuck in the old allocation sheet. The remainder rides on the last entry.
Map<String, String> watchlistSimulationSplitPercentTexts({
  required List<String> ids,
  required Decimal totalPercent,
}) {
  if (ids.isEmpty) return const <String, String>{};
  final totalHundredths = (totalPercent.toDouble() * 100).round();
  final base = totalHundredths ~/ ids.length;
  final remainder = totalHundredths - base * ids.length;
  return <String, String>{
    for (var index = 0; index < ids.length; index++)
      ids[index]: ((index == ids.length - 1 ? base + remainder : base) / 100)
          .toStringAsFixed(2),
  };
}

/// Re-expresses stored ratios as two-decimal percentages that still sum to
/// 100 together with [cashPercentText].
///
/// A simulation saved at higher precision (six equal slices of `0.16666667`)
/// would otherwise open the editor showing six `16.67%` fields that already
/// fail the strict 100% guard, with no visible cause. Snapping keeps the
/// relative proportions and hands the user a valid starting state.
Map<String, String> watchlistSimulationSnapPercentTexts({
  required List<String> ids,
  required Map<String, Decimal> ratiosById,
  required String cashPercentText,
}) {
  if (ids.isEmpty) return const <String, String>{};
  final cashPercent = Decimal.tryParse(cashPercentText.trim()) ?? Decimal.zero;
  final totalRatio = ids.fold(
    Decimal.zero,
    (sum, id) => sum + (ratiosById[id] ?? Decimal.zero),
  );
  if (totalRatio <= Decimal.zero) {
    return watchlistSimulationSplitPercentTexts(
      ids: ids,
      totalPercent: Decimal.fromInt(100) - cashPercent,
    );
  }
  var remainingHundredths =
      ((Decimal.fromInt(100) - cashPercent).toDouble() * 100).round();
  if (remainingHundredths < 0) remainingHundredths = 0;
  final budget = remainingHundredths;
  final result = <String, String>{};
  for (var index = 0; index < ids.length; index++) {
    final isLast = index == ids.length - 1;
    // Every entry is measured against the whole budget, never against what is
    // still unassigned — otherwise the second slice of an even split would be
    // scaled down by the first slice's rounding and the proportions would
    // drift. Only the final entry absorbs the rounding remainder.
    final share = isLast
        ? remainingHundredths
        : ((ratiosById[ids[index]] ?? Decimal.zero).toDouble() /
                  totalRatio.toDouble() *
                  budget)
              .round();
    final hundredths = share.clamp(0, remainingHundredths);
    result[ids[index]] = (hundredths / 100).toStringAsFixed(2);
    remainingHundredths -= hundredths;
  }
  return result;
}

/// Snapshot of quote inputs used to value virtual holdings for paper
/// dividends. Passing every watchlist item keeps the captured quantity
/// identical to the pre-existing behaviour, including symbols that the
/// simulation itself does not weight.
Map<String, WatchlistSimulationHoldingInput> watchlistSimulationHoldingInputs(
  Iterable<WatchlistItem> items,
  Iterable<WatchlistQuoteSnapshot> snapshots,
) {
  final snapshotByItemId = {
    for (final snapshot in snapshots) snapshot.item.id: snapshot,
  };
  return <String, WatchlistSimulationHoldingInput>{
    for (final item in items)
      item.id: WatchlistSimulationHoldingInput(
        symbol: item.symbol,
        market: item.market,
        rawPrice: snapshotByItemId[item.id]?.quote?.price,
        priceCurrency: snapshotByItemId[item.id]?.quote?.currency,
        priceAsOf: snapshotByItemId[item.id]?.quote?.asOf,
        priceSource: snapshotByItemId[item.id]?.response?.source,
        quantityEligible:
            snapshotByItemId[item.id]?.response?.freshness !=
            DataFreshness.stale,
      ),
  };
}
