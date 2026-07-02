import 'package:decimal/decimal.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:naviwealth/core/sync/sync_meta.dart';

part 'posting.freezed.dart';

/// Cost annotation on a [Posting]. Anchors a "lot" — the specific
/// inventory the posting opens or closes.
///
/// Set [perUnit] in the cost currency (typically the asset's quote
/// currency, which need not equal the JE's transaction currency). The
/// optional [lotId] lets the user / cost-basis selector pick a specific
/// open lot to close in a sale; [acquiredOn] is the original purchase
/// date and is used by FIFO selection when [lotId] is unset.
///
/// `Cost` is mutually exclusive with [Posting.price] only on the entry
/// side: a closing leg may carry both — `cost` identifies which lot to
/// close, `price` records the realised disposal price — but in that case
/// the balance algorithm uses `cost` to compute the leg weight. See
/// [entryIsBalanced].
@freezed
abstract class Cost with _$Cost {
  const factory Cost({
    required Decimal perUnit,
    required String currency,
    String? lotId,
    DateTime? acquiredOn,
  }) = _Cost;
}

/// Inline price annotation on a [Posting]. Records the per-unit market
/// value at the moment of the entry — used both as the balance weight on
/// non-cost legs (e.g. an FX leg quoted at the spot rate) and as the
/// disposal price on a closing trade.
///
/// Persistent price history (mark-to-market over time) lives in the
/// `prices` table — see [PriceObservation]. `Price` here is the snapshot
/// captured on the JE, not a row in that table.
@freezed
abstract class Price with _$Price {
  const factory Price({required Decimal perUnit, required String currency}) =
      _Price;
}

/// One leg of a [JournalEntry]. Each posting describes "N units of `unit`
/// flowing into account `accountId`" with an optional cost (lot anchor)
/// or price (market snapshot) annotation.
///
/// Sign convention: [units] is the *signed delta* applied to the
/// account's balance. SUM(weight) over a JE's postings must equal zero;
/// see [entryIsBalanced] for the weight rule.
///
/// `unit` shares the namespace with `accounts.currency` (ISO 4217 codes
/// like `'CNY'`, `'USD'`) and `assets.id` (canonical
/// `<market>:<symbol>`) — a posting either flows fiat or flows a
/// commodity / security. The two cases are distinguished by whether the
/// `unit` resolves to an `assets` row.
@freezed
abstract class Posting with _$Posting {
  const factory Posting({
    required String id,
    required String journalEntryId,

    /// Position within the JE (0-based). Determines render order in the
    /// editor and the export. Stored explicitly so re-ordering is a
    /// single-column LWW update rather than a JE-wide rewrite.
    required int position,

    required String accountId,
    required Decimal units,
    required String unit,

    /// Cost annotation — set when this leg opens or closes a specific
    /// lot. See [Cost].
    Cost? cost,

    /// Price annotation — set when this leg carries an explicit market
    /// price (FX spot, sale price, etc.). See [Price].
    Price? price,

    required SyncMeta sync,
  }) = _Posting;
}
