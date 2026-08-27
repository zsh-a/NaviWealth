import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart' as dom;
import 'package:uuid/uuid.dart';

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
      ..orderBy([
        (t) => OrderingTerm(expression: t.baseCurrency),
        (t) => OrderingTerm(expression: t.quoteCurrency),
        (t) => OrderingTerm(expression: t.asOf),
      ]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  Future<List<dom.FxRate>> listAll() async {
    final rows =
        await (_db.select(_db.fxRates)..orderBy([
              (t) => OrderingTerm(expression: t.baseCurrency),
              (t) => OrderingTerm(expression: t.quoteCurrency),
              (t) => OrderingTerm(expression: t.asOf),
            ]))
            .get();
    return rows.map(_toDomain).toList();
  }

  /// Returns the newest stored observation for one currency pair.
  ///
  /// The sync service uses this cursor to request only the missing tail of a
  /// series while keeping a small overlap for retries and provider revisions.
  Future<DateTime?> latestDateForPair({
    required String base,
    required String quote,
  }) async {
    final b = _normalize(base, 'base');
    final q = _normalize(quote, 'quote');
    final row =
        await (_db.select(_db.fxRates)
              ..where(
                (t) => t.baseCurrency.equals(b) & t.quoteCurrency.equals(q),
              )
              ..orderBy([
                (t) =>
                    OrderingTerm(expression: t.asOf, mode: OrderingMode.desc),
              ])
              ..limit(1))
            .getSingleOrNull();
    final date = row?.asOf;
    return date == null ? null : DateTime.utc(date.year, date.month, date.day);
  }

  /// Returns every stored UTC calendar day for one currency pair.
  ///
  /// The FX sync cursor is normally based on the newest observation, but a
  /// newest-only cursor cannot notice a hole in the middle of a series. The
  /// sync service uses this lightweight date-only read to locate unusually
  /// large gaps and request a repair from the gap's beginning.
  Future<List<DateTime>> listDatesForPair({
    required String base,
    required String quote,
  }) async {
    final b = _normalize(base, 'base');
    final q = _normalize(quote, 'quote');
    final rows =
        await (_db.select(_db.fxRates)
              ..where(
                (t) => t.baseCurrency.equals(b) & t.quoteCurrency.equals(q),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.asOf)]))
            .get();
    return rows
        .map((row) => DateTime.utc(row.asOf.year, row.asOf.month, row.asOf.day))
        .toList(growable: false);
  }

  /// Insert or replace the rate for `(base, quote, day(asOf))`. Same-day
  /// re-records overwrite the prior value; different days create new rows.
  Future<dom.FxRate> upsertDaily({
    required String baseCurrency,
    required String quoteCurrency,
    required Decimal rate,
    required DateTime asOf,
    String? source,
    DateTime? fetchedAt,
  }) async {
    final value = dom.FxRate(
      base: baseCurrency,
      quote: quoteCurrency,
      date: asOf,
      rate: rate,
      source: source ?? 'manual',
      fetchedAt: (fetchedAt ?? DateTime.now()).toUtc(),
    );
    return (await upsertDailyBatch([value])).single;
  }

  /// Inserts or replaces a batch of daily observations in one transaction.
  ///
  /// Historical providers return many bars at once. Keeping the batch atomic
  /// prevents the live history stream from exposing a partially backfilled
  /// series and avoids one SQLite transaction per trading day.
  Future<List<dom.FxRate>> upsertDailyBatch(Iterable<dom.FxRate> rates) async {
    final byNaturalKey = <String, dom.FxRate>{};
    for (final rate in rates) {
      final key =
          '${rate.base}\u0000${rate.quote}\u0000${rate.date.millisecondsSinceEpoch}';
      byNaturalKey[key] = rate;
    }
    final values = byNaturalKey.values.toList(growable: false);
    if (values.isEmpty) return const <dom.FxRate>[];

    await _db.transaction(() async {
      for (final rate in values) {
        // Keep the repository's natural-key semantics explicit even on
        // development databases that predate the unique index migration.
        await (_db.delete(_db.fxRates)..where(
              (t) =>
                  t.baseCurrency.equals(rate.base) &
                  t.quoteCurrency.equals(rate.quote) &
                  t.asOf.equals(rate.date),
            ))
            .go();
        await _db
            .into(_db.fxRates)
            .insert(
              FxRatesCompanion.insert(
                id: _uuid.v4(),
                baseCurrency: rate.base,
                quoteCurrency: rate.quote,
                rate: rate.rate,
                asOf: rate.date,
                fetchedAt: rate.fetchedAt,
                source: Value(rate.source),
              ),
            );
      }
    });
    return values;
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
    fetchedAt: row.fetchedAt,
  );
}
