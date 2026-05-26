import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';
import 'sync_meta.dart';

part 'journal_entry.freezed.dart';

/// One atomic economic event in the ledger. The ledger's "row of git
/// commit" — every position change in NaviWealth is a [JournalEntry]
/// composed of N [Posting]s whose weights sum to zero.
///
/// `tagIds` is denormalised onto the entry rather than mirrored through
/// `tag_links` because a JE always carries the same tag set across its
/// postings, and the alternative (M:N table just for journal entries)
/// would double the sync surface area for no gain. Per-posting tagging
/// would change the model and is intentionally out of scope.
///
/// `payee` is optional because internal events (transfers between owned
/// accounts, splits) don't have an external counter-party — surfacing a
/// payee field that's always blank in those cases hurts the form UX more
/// than denormalising helps. Code that wants a "who paid / who got paid"
/// view should fall back to the narration when payee is null.
@freezed
abstract class JournalEntry with _$JournalEntry {
  const factory JournalEntry({
    required String id,

    /// Trade date — when the economic event happened. Drives the natural
    /// ordering of the ledger and, together with [settledOn], lets reports
    /// distinguish "the trade" from "the cash settling".
    required DateTime date,

    /// Settlement date. NULL means same-day (most cash flows / transfers);
    /// the typical non-NULL case is broker T+2 settlement on a trade.
    DateTime? settledOn,

    /// Free-form description (`"Buy AAPL"`, `"Salary"`, `"Coffee at the
    /// office"`). Required and non-empty by convention so the timeline
    /// view always has something to render even before a user customises
    /// the entry.
    required String narration,

    /// Optional counter-party. Used by reports that want to slice spend
    /// by merchant ("Costco", "Walmart") or income by source.
    String? payee,

    @Default(<String>[]) List<String> tagIds,
    @Default(EntryFlag.confirmed) EntryFlag flag,
    required SyncMeta sync,
  }) = _JournalEntry;
}
