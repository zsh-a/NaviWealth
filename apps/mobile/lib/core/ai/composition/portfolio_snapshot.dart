/// Cross-domain seam for the portfolio snapshot the chat surface
/// ships alongside each turn (`docs/lifeos-shell.md` §4, D-1.6b).
///
/// `ChatRepository` accepts an optional closure that returns a
/// JSON-shaped snapshot of the user's current portfolio. The shape
/// is consumed only by the LLM as wire context, so the closure is
/// intentionally typed as `Future<Map<String, Object?>?> Function()`
/// rather than a domain-specific model.
///
/// FinanceOS supplies the snapshot reader; other domains can compose
/// here in the future. Default is `null`, in which case the
/// repository omits the snapshot from the wire.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef PortfolioSnapshotReader = Future<Map<String, Object?>?> Function();

final portfolioSnapshotReaderProvider = Provider<PortfolioSnapshotReader?>(
  (ref) => null,
);
