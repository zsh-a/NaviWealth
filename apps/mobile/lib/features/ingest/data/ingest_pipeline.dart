/// §5.10.10 / S5a — the pipeline orchestrator (pure planning step).
///
/// `①Capture → ②Route → ③Parse → ④Normalize → ⑤Dedup → ⑥Draft Queue`.
/// This class owns ②–⑤ and is deliberately I/O-free so it is trivially
/// unit-testable; persistence (⑥) and tracing live in the controller /
/// store. Confirmation (⑦) is a separate service that never lets the AI
/// be the final writer (§5.10.6).
library;

import 'package:uuid/uuid.dart';

import '../../../core/ai/local/skills/skills.dart';
import '../domain/ingest_models.dart';
import 'ingest_dedup.dart';
import 'statement_ingest_parser.dart';

class IngestPipeline {
  IngestPipeline({DateTime Function()? clock, String Function()? idGen})
    : _clock = clock ?? (() => DateTime.now().toUtc()),
      _idGen = idGen ?? (() => const Uuid().v4());

  final DateTime Function() _clock;
  final String Function() _idGen;

  /// How long a pending draft survives before housekeeping prunes it.
  static const Duration draftTtl = Duration(days: 30);

  /// Parse + normalize + dedup [source] against [existingLedger].
  /// Returns drafts in `pending` status — nothing is persisted here and
  /// nothing ever touches the ledger (§4.2 draft gate by construction).
  IngestResult plan({
    required IngestSource source,
    required List<TransactionInput> existingLedger,
    required String ownerUserId,
    String defaultCurrency = 'CNY',
    String? traceId,
  }) {
    if (!source.kind.isDeviceParsable) {
      return IngestResult(
        drafts: const <IngestDraft>[],
        rejectedReason:
            '「${source.kind.name}」来源需模型 Vision 解析，S5a 仅支持 CSV / 粘贴文本',
      );
    }

    final parsed = parseStatementLedger(
      source.payload,
      defaultCurrency: defaultCurrency,
    );
    return planFromParsed(
      parsed: parsed,
      source: source,
      existingLedger: existingLedger,
      ownerUserId: ownerUserId,
      traceId: traceId,
    );
  }

  /// Steps ④⑤⑥ on an already-parsed list. Shared by the device CSV
  /// path ([plan]) and the S5b provider-Vision path (where the LLM did ③).
  IngestResult planFromParsed({
    required List<ParsedTransaction> parsed,
    required IngestSource source,
    required List<TransactionInput> existingLedger,
    required String ownerUserId,
    String? traceId,
  }) {
    final now = _clock();
    final expiresAt = now.add(draftTtl);

    final drafts = <IngestDraft>[];
    final dedupLedger = existingLedger.toList(growable: true);
    for (final p in parsed) {
      // ④ Normalize — reuse the on-device classifier rather than
      // inventing a second heuristic (the ledger is the only computer).
      final classification = classifyTransaction(
        TransactionInput(
          id: 'ingest-probe',
          description: p.description,
          amountMinor: p.amountMinor.toString(),
          currency: p.currency,
          occurredAt: p.occurredAt,
        ),
      );
      final normalized = classification == null
          ? p
          : p.copyWith(categoryHint: classification.categoryHint);

      // ⑤ Dedup against device truth.
      final dedup = classifyDedup(normalized, dedupLedger);

      final draftId = _idGen();
      drafts.add(
        IngestDraft(
          draftId: draftId,
          ownerUserId: ownerUserId,
          createdAt: now,
          sourceKind: source.kind,
          parsed: normalized,
          verdict: dedup.verdict,
          status: DraftStatus.pending,
          originLabel: source.originLabel,
          dedupTargetEntryId: dedup.targetEntryId,
          traceId: traceId,
          expiresAt: expiresAt,
        ),
      );
      dedupLedger.add(
        TransactionInput(
          id: draftId,
          description: normalized.description,
          amountMinor: normalized.amountMinor.toString(),
          currency: normalized.currency,
          occurredAt: normalized.occurredAt,
          categoryId: normalized.categoryHint,
        ),
      );
    }
    return IngestResult(drafts: drafts);
  }
}
