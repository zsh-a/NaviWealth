import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../core/persistence/app_database.dart';
import '../../domain/entities/fx_rate.dart' as dom;

/// Read / write API for the local `fx_rates` table.
///
/// Unlike user-data tables, FX rates are global market data and are NOT
/// synced — every device pulls / records its own copy. The repository
/// therefore writes directly to Drift without enqueueing into the sync
/// outbox.
///
/// The data table stores wall-clock instants in `as_of`; this layer
/// normalises them to UTC calendar days so callers always see one rate per
/// trading day. Storing two rates for the same `(base, quote, day)` pair
/// resolves to "latest write wins" — `upsertDaily` performs the equivalent
/// of `INSERT OR REPLACE` keyed on the natural key.
class FxRateRepository {
  FxRateRepository({required AppDatabase db, Uuid uuid = const Uuid()})
    : _db = db,
      _uuid = uuid;

  final AppDatabase _db;
  final Uuid _uuid;

  /// Live stream of every recorded FX rate, ordered ascending by date so
  /// callers can index/lookup without re-sorting.
  Stream<List<dom.FxRate>> watchAll() {
    final query = _db.select(_db.fxRates)
      ..orderBy([(t) => OrderingTerm(expression: t.asOf)]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  Future<List<dom.FxRate>> listAll() async {
    final rows = await (_db.select(
      _db.fxRates,
    )..orderBy([(t) => OrderingTerm(expression: t.asOf)])).get();
    return rows.map(_toDomain).toList();
  }

  /// Insert or replace the rate for `(base, quote, day(asOf))`. Same-day
  /// re-records overwrite the prior value; different days create new rows.
  Future<dom.FxRate> upsertDaily({
    required String baseCurrency,
    required String quoteCurrency,
    required Decimal rate,
    required DateTime asOf,
    String? source,
  }) async {
    final base = _normalize(baseCurrency, 'baseCurrency');
    final quote = _normalize(quoteCurrency, 'quoteCurrency');
    if (base == quote) {
      throw ArgumentError(
        'baseCurrency and quoteCurrency must differ; got both = $base',
      );
    }
    if (rate <= Decimal.zero) {
      throw ArgumentError.value(rate, 'rate', 'must be positive');
    }
    final day = DateTime.utc(asOf.year, asOf.month, asOf.day);

    return _db.transaction(() async {
      // Manual upsert: drop any existing same-day row so callers don't
      // accumulate duplicates when re-entering the rate.
      await (_db.delete(_db.fxRates)..where(
            (t) =>
                t.baseCurrency.equals(base) &
                t.quoteCurrency.equals(quote) &
                t.asOf.equals(day),
          ))
          .go();
      final id = _uuid.v4();
      await _db
          .into(_db.fxRates)
          .insert(
            FxRatesCompanion.insert(
              id: id,
              baseCurrency: base,
              quoteCurrency: quote,
              rate: rate,
              asOf: day,
              source: Value(source),
            ),
          );
      return dom.FxRate(
        base: base,
        quote: quote,
        date: day,
        rate: rate,
        source: source ?? 'manual',
      );
    });
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.fxRates)..where((t) => t.id.equals(id))).go();
  }

  /// Delete the row matching the natural key `(base, quote, day(date))`.
  /// The domain [dom.FxRate] does not carry the Drift row id, so the
  /// FX-rate management UI deletes via this helper after the user swipes
  /// a row.
  Future<void> deleteByNaturalKey({
    required String base,
    required String quote,
    required DateTime date,
  }) async {
    final b = _normalize(base, 'base');
    final q = _normalize(quote, 'quote');
    final day = DateTime.utc(date.year, date.month, date.day);
    await (_db.delete(_db.fxRates)..where(
          (t) =>
              t.baseCurrency.equals(b) &
              t.quoteCurrency.equals(q) &
              t.asOf.equals(day),
        ))
        .go();
  }

  static String _normalize(String code, String field) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(code, field, 'must not be empty');
    }
    return trimmed.toUpperCase();
  }

  dom.FxRate _toDomain(FxRateRow row) => dom.FxRate(
    base: row.baseCurrency,
    quote: row.quoteCurrency,
    date: row.asOf,
    rate: row.rate,
    source: row.source ?? 'manual',
  );
}
