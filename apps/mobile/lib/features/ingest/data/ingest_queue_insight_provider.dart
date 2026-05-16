/// §5.10.10 / S5a.1 — Layer 3 ambient projection of the Layer 4 queue.
///
/// Mirrors the `DuplicateChargeSummary` shape: a tiny, dismissible
/// summary the home insight feed renders as a calm card. The card's
/// row tap deep-links to `/activity/ingest` (the §5.10.10 review page);
/// "静默冒泡" — it only appears while there is something to confirm.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ingest_models.dart';
import 'providers.dart';

class IngestQueueSummary {
  const IngestQueueSummary({
    required this.pendingCount,
    required this.freshCount,
  });

  /// Total parsed-but-unconfirmed drafts.
  final int pendingCount;

  /// Subset with no dedup match — the "全部确认 · 仅新增" set.
  final int freshCount;

  bool get isEmpty => pendingCount == 0;

  /// Stable dismissal scope: re-surfaces only when the shape changes
  /// (new batch ingested), not on every queue re-query.
  String get scopeHash => '$pendingCount:$freshCount';
}

final ingestQueueInsightProvider = Provider<IngestQueueSummary?>((ref) {
  final drafts = ref.watch(pendingIngestDraftsProvider).value;
  if (drafts == null || drafts.isEmpty) return null;
  final fresh = drafts
      .where((d) => d.verdict == DedupVerdict.newTxn)
      .length;
  return IngestQueueSummary(
    pendingCount: drafts.length,
    freshCount: fresh,
  );
});
