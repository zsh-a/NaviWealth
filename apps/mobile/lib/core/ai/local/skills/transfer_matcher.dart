/// Pairs cross-account transfers.
///
/// A real transfer shows up as two ledger entries — an outflow on
/// account A on day X and an inflow on account B on day X (±1–2).
/// The matcher pairs them so the UI can collapse them into a single
/// "transfer" and stop counting them as expense + income.
library;

import '../../contracts/task_context.dart' show AnalyticalUpload;
import 'transaction_input.dart';

class TransferMatch {
  const TransferMatch({
    required this.fromTxnId,
    required this.toTxnId,
    required this.amountMinor,
    required this.currency,
  });

  /// Source (outflow) transaction id.
  final String fromTxnId;

  /// Destination (inflow) transaction id.
  final String toTxnId;

  /// Absolute amount in minor units. Positive.
  final int amountMinor;

  final String currency;
}

/// The canonical [TransferMatch] → [AnalyticalUpload] conversion
/// (§4.3.3). Single source shared by the cloud
/// `ContextPack.analytical_uploads` path and the device
/// `get_transfer_links` tool (W-D4.3b) so the device tool's output is
/// exactly what the backend `transfer_links` read model mirrors (§10).
AnalyticalUpload transferMatchToUpload(TransferMatch m) {
  return AnalyticalUpload(
    kind: 'transfer_link',
    id: '${m.fromTxnId}|${m.toTxnId}',
    payload: <String, Object?>{
      'from_txn_id': m.fromTxnId,
      'to_txn_id': m.toTxnId,
      'amount_minor': m.amountMinor.toString(),
      'currency': m.currency,
    },
  );
}

const Duration kTransferMaxDateGap = Duration(days: 2);

/// Tolerated minor-unit difference between the two sides. Most
/// internal transfers settle exactly; FX transfers are explicitly
/// out of scope here (the currency must match), and processor fees
/// sometimes shave a few units. 50 minor units (≈ $0.50) covers
/// realistic noise without paying an FP.
const int kTransferAmountTolerance = 50;

List<TransferMatch> matchTransfers(Iterable<TransactionInput> txns) {
  final all = List<TransactionInput>.from(txns)
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  final consumed = <String>{};
  final out = <TransferMatch>[];

  for (var i = 0; i < all.length; i++) {
    final a = all[i];
    if (consumed.contains(a.id)) continue;
    final aAmt = parseAmountMinor(a.amountMinor);
    if (aAmt >= 0) continue; // only walk forward from outflows
    if (a.accountId == null) continue;

    for (var j = i + 1; j < all.length; j++) {
      final b = all[j];
      if (consumed.contains(b.id)) continue;
      if (b.accountId == null) continue;
      if (a.currency != b.currency) continue;
      if (a.accountId == b.accountId) continue;
      final gap = b.occurredAt.difference(a.occurredAt);
      if (gap > kTransferMaxDateGap) break;
      final bAmt = parseAmountMinor(b.amountMinor);
      if (bAmt <= 0) continue;
      final delta = (aAmt + bAmt).abs();
      if (delta > kTransferAmountTolerance) continue;

      out.add(
        TransferMatch(
          fromTxnId: a.id,
          toTxnId: b.id,
          amountMinor: bAmt,
          currency: a.currency,
        ),
      );
      consumed
        ..add(a.id)
        ..add(b.id);
      break;
    }
  }
  return out;
}
