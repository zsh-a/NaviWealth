import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:naviwealth/core/sync/sync_meta.dart';

part 'price_observation.freezed.dart';

/// One row in the `prices` time-series. Records an *observation* of an
/// asset's price at a point in time — the holding's current value is
/// derived by looking up the latest observation, never by mutating the
/// asset row.
///
/// Identity is `(unit, quoteCurrency, observedOn)` plus a row id; the
/// composite uniqueness lives at the index level rather than the schema
/// level so historical observations remain queryable even when a user
/// re-edits a date.
///
/// `unit` shares the [Posting.unit] namespace — usually an `assets.id`,
/// but a fiat code is also valid (e.g. cataloguing a CNY/USD spot is a
/// legitimate observation independent of the `fx_rates` provider feed).
@freezed
abstract class PriceObservation with _$PriceObservation {
  const factory PriceObservation({
    required String id,
    required String unit,
    required String quoteCurrency,
    required DateTime observedOn,
    required Decimal perUnit,

    /// Where this observation came from. Free-form by design — the
    /// expected values are `'manual'`, `'yahoo'`, `'coingecko'` etc., but
    /// we don't constrain the column so a future provider can be added
    /// without a schema migration.
    required String source,
    required SyncMeta sync,
  }) = _PriceObservation;
}
