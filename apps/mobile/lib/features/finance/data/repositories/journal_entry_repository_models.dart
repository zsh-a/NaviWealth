part of 'journal_entry_repository.dart';

class ActivityFeedCursor {
  const ActivityFeedCursor({required this.date, required this.id});

  final DateTime date;
  final String id;
}

class ActivityFeedReadPage {
  const ActivityFeedReadPage({required this.entries, required this.hasMore});

  final List<JournalEntryWithPostings> entries;
  final bool hasMore;
}

/// Lightweight draft: callers describe the JE without having to mint
/// ids or stamp sync metadata. The repo fills both before the row hits
/// SQLite.
class JournalEntryDraft {
  const JournalEntryDraft({
    this.id,
    required this.date,
    this.settledOn,
    required this.narration,
    this.payee,
    this.tagIds = const <String>[],
    this.flag = EntryFlag.confirmed,
  });

  final String? id;
  final DateTime date;
  final DateTime? settledOn;
  final String narration;
  final String? payee;
  final List<String> tagIds;
  final EntryFlag flag;
}

class PostingDraft {
  const PostingDraft({
    this.id,
    this.position,
    required this.accountId,
    required this.units,
    required this.unit,
    this.cost,
    this.price,
  });

  final String? id;
  final int? position;
  final String accountId;
  final Decimal units;
  final String unit;
  final Cost? cost;
  final Price? price;
}

/// Materialised JE — the entry plus its postings in canonical order.
class JournalEntryWithPostings {
  const JournalEntryWithPostings({required this.entry, required this.postings});

  final JournalEntry entry;
  final List<Posting> postings;
}

/// Thrown by [JournalEntryRepository] when a JE write would violate the
/// SUM(weight) = 0 invariant. Carries the structured report so callers
/// can render targeted errors instead of a generic "won't save" toast.
class JournalEntryUnbalancedException implements Exception {
  const JournalEntryUnbalancedException(this.message, {this.report});

  factory JournalEntryUnbalancedException.fromReport(
    JournalEntryBalanceReport report,
  ) {
    final summary = report.problems.isEmpty
        ? 'Σ(weight) = ${report.totalBaseWeight} '
              'exceeds tolerance ±${report.tolerance}.'
        : report.problems.map((p) => p.message).join('; ');
    return JournalEntryUnbalancedException(summary, report: report);
  }

  final String message;
  final JournalEntryBalanceReport? report;

  @override
  String toString() => 'JournalEntryUnbalancedException: $message';
}
