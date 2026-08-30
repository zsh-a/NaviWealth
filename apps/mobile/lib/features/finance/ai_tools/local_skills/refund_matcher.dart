/// Pairs an original purchase with its later refund.
///
/// Convention: the earlier transaction is the original (negative
/// signed amount = outflow); the later one is the refund (positive,
/// roughly equal magnitude, same merchant). One-to-one match — if a
/// merchant issues two refunds for separate purchases on the same
/// day, the matcher picks them in arrival order.
library;

import 'package:naviwealth/core/ai/contracts/task_context.dart'
    show AnalyticalUpload;

import 'merchant_key.dart';
import 'transaction_input.dart';

class RefundMatch {
  const RefundMatch({
    required this.originalTxnId,
    required this.refundTxnId,
    required this.amountMinor,
    required this.currency,
  });

  final String originalTxnId;
  final String refundTxnId;

  /// Absolute amount in minor units. Positive.
  final int amountMinor;

  final String currency;
}

/// The canonical [RefundMatch] → [AnalyticalUpload] conversion.
///
/// `AnalyticalUpload` is a historical wire name. Today the output feeds
/// device prompt context and the `get_refund_links` tool from the same local
/// heuristic, so prompt preloading and tool responses cannot drift.
AnalyticalUpload refundMatchToUpload(RefundMatch m) {
  return AnalyticalUpload(
    kind: 'refund_link',
    id: '${m.originalTxnId}|${m.refundTxnId}',
    payload: <String, Object?>{
      'original_txn_id': m.originalTxnId,
      'refund_txn_id': m.refundTxnId,
      'amount_minor': m.amountMinor.toString(),
      'currency': m.currency,
    },
  );
}

/// Refunds typically settle within ~30 days of the original; longer
/// gaps are usually independent transactions that happen to net out.
const Duration kRefundMaxLag = Duration(days: 30);

/// Refund amount must agree to within 1% of the original (or 100
/// minor units, whichever is larger). Covers partial refunds of
/// price-adjusted items without admitting wildly different numbers.
const double kRefundAmountToleranceFraction = 0.01;
const int kRefundAmountToleranceMinor = 100;

List<RefundMatch> matchRefunds(Iterable<TransactionInput> txns) {
  final byMerchantCurrency = <String, List<TransactionInput>>{};
  for (final t in txns) {
    final key = merchantKey(t.description);
    if (key.isEmpty) continue;
    byMerchantCurrency
        .putIfAbsent('$key|${t.currency}', () => <TransactionInput>[])
        .add(t);
  }

  final out = <RefundMatch>[];
  for (final group in byMerchantCurrency.values) {
    out.addAll(_matchInGroup(group));
  }
  return out;
}

Iterable<RefundMatch> _matchInGroup(List<TransactionInput> group) sync* {
  final sorted = List<TransactionInput>.from(group)
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  final consumed = <String>{};
  for (var i = 0; i < sorted.length; i++) {
    final original = sorted[i];
    if (consumed.contains(original.id)) continue;
    final originalAmt = parseAmountMinor(original.amountMinor);
    if (originalAmt >= 0) continue; // only outflows can be refunded

    final tolerance = _toleranceFor(originalAmt);
    for (var j = i + 1; j < sorted.length; j++) {
      final candidate = sorted[j];
      if (consumed.contains(candidate.id)) continue;
      final lag = candidate.occurredAt.difference(original.occurredAt);
      if (lag > kRefundMaxLag) break;
      final candidateAmt = parseAmountMinor(candidate.amountMinor);
      if (candidateAmt <= 0) continue;
      if ((originalAmt + candidateAmt).abs() > tolerance) continue;

      yield RefundMatch(
        originalTxnId: original.id,
        refundTxnId: candidate.id,
        amountMinor: candidateAmt,
        currency: original.currency,
      );
      consumed
        ..add(original.id)
        ..add(candidate.id);
      break;
    }
  }
}

int _toleranceFor(int originalSignedAmount) {
  final magnitude = originalSignedAmount.abs();
  final pct = (magnitude * kRefundAmountToleranceFraction).ceil();
  return pct > kRefundAmountToleranceMinor ? pct : kRefundAmountToleranceMinor;
}
