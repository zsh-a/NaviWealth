import '../../ai_tools/local_skills/transaction_input.dart';
import '../domain/ingest_models.dart';

/// Ingest-only evidence; generic Finance rules retain their existing input.
class IngestDedupCandidate extends TransactionInput {
  const IngestDedupCandidate({
    required super.id,
    required super.description,
    required super.amountMinor,
    required super.currency,
    required super.occurredAt,
    required this.kind,
    super.accountId,
    super.categoryId,
    this.sourceIdentity,
    this.sourceScope,
    this.allowDateDrift = true,
    this.dateHasTime = false,
  });

  factory IngestDedupCandidate.fromDraft(IngestDraft draft) =>
      IngestDedupCandidate.fromParsed(draft.parsed, id: draft.draftId);

  factory IngestDedupCandidate.fromParsed(
    ParsedTransaction parsed, {
    required String id,
  }) => IngestDedupCandidate(
    id: id,
    description: parsed.description,
    amountMinor: parsed.amountMinor.toString(),
    currency: parsed.currency,
    occurredAt: parsed.occurredAt,
    kind: parsed.kind,
    categoryId: parsed.categoryHint,
    sourceIdentity: parsed.sourceReference?.hasUniqueScope == true
        ? parsed.sourceReference!.identity
        : null,
    sourceScope: parsed.sourceReference?.hasUniqueScope == true
        ? parsed.sourceReference!.scope
        : null,
    allowDateDrift: false,
    dateHasTime: parsed.dateHasTime,
  );

  final IngestTransactionKind kind;
  final String? sourceIdentity;
  final String? sourceScope;
  final bool allowDateDrift;
  final bool dateHasTime;
}
