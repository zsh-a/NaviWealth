/// §5.10.10 / S5a — Layer 4 record-entry pipeline domain types.
///
/// These model the *staging* shape only: a parsed-but-unconfirmed
/// transaction and its dedup verdict. None of this is sync wire format —
/// drafts live exclusively in the local `ingest_drafts` table and never
/// enter the OpLog. They become durable ledger truth only after the user
/// confirms, at which point the normal repository write path takes over.
library;

/// Where a batch of raw input came from. Only [csv] / [pasteText] are
/// handled on-device in S5a; the image / pdf / email kinds are reserved
/// for the cloud-Vision path (S5b/S5c/S5d) and currently rejected by the
/// pipeline with a clear reason.
enum IngestSourceKind { csv, pasteText, receiptImage, statementPdf, email }

extension IngestSourceKindX on IngestSourceKind {
  String get wire => name;

  static IngestSourceKind parse(String s) => IngestSourceKind.values
      .firstWhere((k) => k.name == s, orElse: () => IngestSourceKind.csv);

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

  static DedupVerdict parse(String s) => DedupVerdict.values
      .firstWhere((v) => v.name == s, orElse: () => DedupVerdict.newTxn);

  /// Whether a batch "confirm all" should skip this row by default.
  bool get skipByDefault => this != DedupVerdict.newTxn;
}

/// Lifecycle of a single draft row.
enum DraftStatus { pending, confirmed, dismissed }

extension DraftStatusX on DraftStatus {
  String get wire => name;

  static DraftStatus parse(String s) => DraftStatus.values
      .firstWhere((v) => v.name == s, orElse: () => DraftStatus.pending);
}

/// A raw input batch handed to the pipeline. [payload] is the textual
/// content for device kinds (CSV / pasted text) or the base64 binary
/// for cloud kinds (receipt image / statement PDF); [mime] is set only
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

/// One parsed transaction. [amountMinor] is signed minor units following
/// the same outflow-is-negative convention as `expenseToTransactionInput`
/// (S5a only ever produces expenses, so the value is negative).
class ParsedTransaction {
  const ParsedTransaction({
    required this.description,
    required this.amountMinor,
    required this.currency,
    required this.occurredAt,
    this.categoryHint,
    this.confidence = 1.0,
  });

  final String description;
  final int amountMinor;
  final String currency;
  final DateTime occurredAt;
  final String? categoryHint;
  final double confidence;

  ParsedTransaction copyWith({String? categoryHint, double? confidence}) =>
      ParsedTransaction(
        description: description,
        amountMinor: amountMinor,
        currency: currency,
        occurredAt: occurredAt,
        categoryHint: categoryHint ?? this.categoryHint,
        confidence: confidence ?? this.confidence,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'description': description,
    'amount_minor': amountMinor,
    'currency': currency,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
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

  double get confidence => parsed.confidence;

  IngestDraft copyWith({DraftStatus? status}) => IngestDraft(
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
  );
}

/// Summary returned after a pipeline run, for the trace + a toast.
class IngestResult {
  const IngestResult({
    required this.drafts,
    this.rejectedReason,
  });

  final List<IngestDraft> drafts;

  /// Set when the source kind could not be parsed on-device (e.g. an
  /// image in S5a). The pipeline never silently drops input.
  final String? rejectedReason;

  int get total => drafts.length;
  int get newCount =>
      drafts.where((d) => d.verdict == DedupVerdict.newTxn).length;
  int get duplicateCount => total - newCount;
  bool get isRejected => rejectedReason != null;
}
