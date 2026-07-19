/// §5.10.10 / S5a — Layer 4 record-entry pipeline domain types.
///
/// These model the *staging* shape only: a parsed-but-unconfirmed
/// transaction and its dedup verdict. None of this is sync wire format —
/// drafts live exclusively in the local `ingest_drafts` table and never
/// enter the OpLog. They become durable ledger truth only after the user
/// confirms, at which point the normal repository write path takes over.
library;

import 'ingest_parse_diagnostics.dart';

/// Where a batch of raw input came from. Only [csv] / [pasteText] are
/// handled by deterministic parsers in S5a; the image / pdf / email kinds
/// require the provider-Vision path (S5b/S5c/S5d) and are rejected when the
/// device has no configured model runtime.
enum IngestSourceKind { csv, pasteText, receiptImage, statementPdf, email }

extension IngestSourceKindX on IngestSourceKind {
  String get wire => name;

  static IngestSourceKind parse(String s) => IngestSourceKind.values.firstWhere(
    (k) => k.name == s,
    orElse: () => IngestSourceKind.csv,
  );

  /// Whether the on-device deterministic parser can handle this kind.
  bool get isDeviceParsable =>
      this == IngestSourceKind.csv || this == IngestSourceKind.pasteText;
}

/// Dedup outcome of one parsed row against the existing ledger.
enum DedupVerdict {
  /// No plausible match — safe to add.
  newTxn,

  /// Same merchant + near-equal amount within the date window — likely
  /// the same transaction the user already recorded; pre-checked to
  /// skip but overridable.
  likelyDuplicate,

  /// Exact merchant + amount + currency within the date window — a
  /// duplicate with high confidence.
  duplicate,
}

extension DedupVerdictX on DedupVerdict {
  String get wire => name;

  static DedupVerdict parse(String s) => DedupVerdict.values.firstWhere(
    (v) => v.name == s,
    orElse: () => DedupVerdict.newTxn,
  );

  /// Whether a batch "confirm all" should skip this row by default.
  bool get skipByDefault => this != DedupVerdict.newTxn;
}

/// Lifecycle of a single draft row.
enum DraftStatus { pending, confirming, confirmed, dismissed }

extension DraftStatusX on DraftStatus {
  String get wire => name;

  static DraftStatus parse(String s) => DraftStatus.values.firstWhere(
    (v) => v.name == s,
    orElse: () => DraftStatus.pending,
  );
}

/// A raw input batch handed to the pipeline. [payload] is the textual
/// content for deterministic kinds (CSV / pasted text) or the base64 binary
/// for Vision kinds (receipt image / statement PDF); [mime] is set only
/// for the latter (S5b-vision). [originLabel] is a human breadcrumb
/// (filename / "粘贴文本") surfaced in the trace.
class IngestSource {
  const IngestSource({
    required this.kind,
    required this.payload,
    this.mime,
    this.originLabel,
  });

  final IngestSourceKind kind;
  final String payload;
  final String? mime;
  final String? originLabel;
}

/// Economic direction of one parsed statement row.
///
/// This discriminator is persisted with drafts so the review and confirm
/// steps never have to infer intent again from the amount sign. Drafts
/// written before income ingest existed decode as [expense].
enum IngestTransactionKind { expense, income }

extension IngestTransactionKindX on IngestTransactionKind {
  String get wire => name;

  static IngestTransactionKind parse(String? value) =>
      IngestTransactionKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => IngestTransactionKind.expense,
      );
}

/// One parsed transaction. [amountMinor] is signed minor units: expenses
/// are negative and income is positive.
class ParsedTransaction {
  const ParsedTransaction({
    required this.description,
    required this.amountMinor,
    required this.currency,
    required this.occurredAt,
    this.kind = IngestTransactionKind.expense,
    this.categoryHint,
    this.confidence = 1.0,
  });

  final String description;
  final int amountMinor;
  final String currency;
  final DateTime occurredAt;
  final IngestTransactionKind kind;
  final String? categoryHint;
  final double confidence;

  ParsedTransaction copyWith({
    IngestTransactionKind? kind,
    String? categoryHint,
    double? confidence,
  }) => ParsedTransaction(
    description: description,
    amountMinor: amountMinor,
    currency: currency,
    occurredAt: occurredAt,
    kind: kind ?? this.kind,
    categoryHint: categoryHint ?? this.categoryHint,
    confidence: confidence ?? this.confidence,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'description': description,
    'amount_minor': amountMinor,
    'currency': currency,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'kind': kind.wire,
    if (categoryHint != null) 'category_hint': categoryHint,
    'confidence': confidence,
  };

  factory ParsedTransaction.fromJson(Map<String, Object?> json) {
    return ParsedTransaction(
      description: (json['description'] as String?) ?? '',
      amountMinor: (json['amount_minor'] as num?)?.toInt() ?? 0,
      currency: (json['currency'] as String?) ?? 'CNY',
      occurredAt:
          DateTime.tryParse((json['occurred_at'] as String?) ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      kind: IngestTransactionKindX.parse(json['kind'] as String?),
      categoryHint: json['category_hint'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// A persisted staging row: the parsed transaction plus its dedup
/// verdict and lifecycle status. Mirrors the `ingest_drafts` columns.
class IngestDraft {
  const IngestDraft({
    required this.draftId,
    required this.ownerUserId,
    required this.createdAt,
    required this.sourceKind,
    required this.parsed,
    required this.verdict,
    required this.status,
    this.originLabel,
    this.dedupTargetEntryId,
    this.traceId,
    this.expiresAt,
    this.revision = 0,
  });

  final String draftId;
  final String ownerUserId;
  final DateTime createdAt;
  final IngestSourceKind sourceKind;
  final ParsedTransaction parsed;
  final DedupVerdict verdict;
  final DraftStatus status;
  final String? originLabel;
  final String? dedupTargetEntryId;
  final String? traceId;
  final DateTime? expiresAt;
  final int revision;

  double get confidence => parsed.confidence;

  IngestDraft copyWith({DraftStatus? status, int? revision}) => IngestDraft(
    draftId: draftId,
    ownerUserId: ownerUserId,
    createdAt: createdAt,
    sourceKind: sourceKind,
    parsed: parsed,
    verdict: verdict,
    status: status ?? this.status,
    originLabel: originLabel,
    dedupTargetEntryId: dedupTargetEntryId,
    traceId: traceId,
    expiresAt: expiresAt,
    revision: revision ?? this.revision,
  );
}

/// Summary returned after a pipeline run, for the trace + a toast.
class IngestResult {
  const IngestResult({
    required this.drafts,
    this.rejectedReason,
    this.parseIssues = const <IngestParseIssue>[],
    this.parseCandidateRowCount = 0,
    this.parseDiagnosticsComplete = false,
  });

  final List<IngestDraft> drafts;
  final List<IngestParseIssue> parseIssues;
  final int parseCandidateRowCount;
  final bool parseDiagnosticsComplete;

  /// Set when the source kind could not be parsed on-device (e.g. an
  /// image in S5a). The pipeline never silently drops input.
  final String? rejectedReason;

  int get total => drafts.length;
  int get newCount =>
      drafts.where((d) => d.verdict == DedupVerdict.newTxn).length;
  int get duplicateCount => total - newCount;
  int get skippedCount => parseIssues.length;
  bool get accountsForEveryParseCandidate =>
      parseDiagnosticsComplete &&
      total + skippedCount == parseCandidateRowCount;
  bool get isRejected => rejectedReason != null;
}

/// Owner-scoped lifecycle totals used by activation and repeat-cycle UX.
/// Counts contain no transaction values or labels.
final class IngestDraftProgress {
  const IngestDraftProgress({
    required this.pending,
    required this.confirmed,
    required this.dismissed,
  });

  const IngestDraftProgress.empty() : pending = 0, confirmed = 0, dismissed = 0;

  final int pending;
  final int confirmed;
  final int dismissed;

  int get reviewed => confirmed + dismissed;
}
