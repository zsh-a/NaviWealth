import 'package:decimal/decimal.dart';

import '../../core/logging/app_logger.dart';

import '../entities/fx_rate.dart';
import '../values/money.dart';

/// Domain-side contract for converting [Money] across currencies.
///
/// Three calling shapes are supported:
/// - [convert] without `on`: use the most recent rate available (current).
/// - [convert] with `on` set to a transaction date: book the conversion
///   at the rate effective on that date — see [FxRateLookup] for the
///   backfill rule.
/// - Custom dates flow through the same `on` parameter.
abstract class CurrencyConverter {
  /// Convert [amount] into [to]. Same-currency calls short-circuit and
  /// return [amount] unchanged. Throws [FxRateNotFoundError] when no rate
  /// (direct or inverse) is available for the requested pair on or before
  /// [on] (or anywhere, if [on] is null).
  Money convert(Money amount, String to, {DateTime? on});
}

/// Thrown when [CurrencyConverter] cannot service a conversion request.
class FxRateNotFoundError extends StateError {
  FxRateNotFoundError(this.base, this.quote, this.on)
    : super(
        on == null
            ? 'No FX rate registered for $base→$quote.'
            : 'No FX rate registered for $base→$quote on or before '
                  '${on.toIso8601String().substring(0, 10)}.',
      );

  final String base;
  final String quote;
  final DateTime? on;
}

/// Pluggable read model over a set of [FxRate]s.
///
/// Splitting lookup from conversion lets us swap storage (in-memory list,
/// Drift table, remote cache) without touching the conversion math.
abstract class FxRateLookup {
  /// Return the rate to use when converting [base]→[quote] on [on].
  ///
  /// Backfill rule: pick the latest rate whose `date` is `<= on`. If [on]
  /// is null, return the most recent rate overall. The returned rate may
  /// be the inverse of a stored rate when only the reverse direction is
  /// recorded. Returns null when no candidate exists.
  FxRate? rateFor(String base, String quote, {DateTime? on});
}

/// In-memory [FxRateLookup] backed by a list of observed rates.
///
/// Suitable for tests and for the initial app version before a persistent
/// FX cache lands. The list is normalized at construction so callers can
/// pass rates in any order.
class InMemoryFxRateLookup implements FxRateLookup {
  InMemoryFxRateLookup(Iterable<FxRate> rates) : _byPair = _index(rates);

  final Map<_PairKey, List<FxRate>> _byPair;

  @override
  FxRate? rateFor(String base, String quote, {DateTime? on}) {
    final b = base.trim().toUpperCase();
    final q = quote.trim().toUpperCase();
    if (b == q) {
      throw ArgumentError('rateFor called with base == quote ($b)');
    }

    final direct = _pickForDate(_byPair[_PairKey(b, q)], on);
    final inverse = _pickForDate(_byPair[_PairKey(q, b)], on);

    // Prefer whichever observation is most recent — same-day stored
    // forward beats older inverse, and vice versa.
    if (direct != null && inverse != null) {
      return direct.date.isAfter(inverse.date) ? direct : inverse.inverse();
    }
    final result = direct ?? inverse?.inverse();
    if (result == null && _byPair.isNotEmpty) {
      AppLogger.instance.w(
        'FX lookup: no rate for $b→$q (on=$on). '
        'Available pairs: ${_byPair.keys.map((k) => '${k.base}→${k.quote}').join(', ')}',
      );
    }
    return result;
  }

  static FxRate? _pickForDate(List<FxRate>? rates, DateTime? on) {
    if (rates == null || rates.isEmpty) return null;
    if (on == null) return rates.last;
    // Normalize to UTC calendar day — rate dates are stored as UTC, but
    // callers may pass local-time DateTime (e.g. DateTime.now()). Treating
    // the local year/month/day as the lookup day keeps the comparison
    // consistent regardless of the caller's timezone.
    final local = on.toLocal();
    final cutoff = DateTime.utc(local.year, local.month, local.day);
    // rates is sorted ascending by date; walk backwards for nearest <= cutoff.
    for (var i = rates.length - 1; i >= 0; i--) {
      if (!rates[i].date.isAfter(cutoff)) return rates[i];
    }
    // No rate on or before the cutoff. Use the earliest available rate if
    // it's within 2 days — this absorbs timezone-induced off-by-one (a rate
    // synced at 4pm UTC+8 is stored as the previous UTC day). Rates far in
    // the past are left as null so historical trend points show 0.
    final earliest = rates.first;
    if (cutoff.difference(earliest.date).inDays.abs() <= 2) return earliest;
    return null;
  }

  static Map<_PairKey, List<FxRate>> _index(Iterable<FxRate> rates) {
    final map = <_PairKey, List<FxRate>>{};
    for (final r in rates) {
      map.putIfAbsent(_PairKey(r.base, r.quote), () => []).add(r);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.date.compareTo(b.date));
    }
    return map;
  }
}

/// Default [CurrencyConverter] that delegates rate selection to a
/// [FxRateLookup] and applies the rate via [Decimal] arithmetic.
class FxRateCurrencyConverter implements CurrencyConverter {
  FxRateCurrencyConverter(this._lookup);

  final FxRateLookup _lookup;

  @override
  Money convert(Money amount, String to, {DateTime? on}) {
    final target = to.trim().toUpperCase();
    if (target == amount.currency) return amount;

    final rate = _lookup.rateFor(amount.currency, target, on: on);
    if (rate == null) {
      throw FxRateNotFoundError(amount.currency, target, on);
    }
    return Money(amount.amount * rate.rate, target);
  }
}

class _PairKey {
  const _PairKey(this.base, this.quote);
  final String base;
  final String quote;

  @override
  bool operator ==(Object other) =>
      other is _PairKey && other.base == base && other.quote == quote;

  @override
  int get hashCode => Object.hash(base, quote);
}
