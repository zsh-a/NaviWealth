/// §5.10.10 / S5a — the pipeline orchestrator (pure planning step).
///
/// `①Capture → ②Route → ③Parse → ④Normalize → ⑤Dedup → ⑥Draft Queue`.
/// This class owns ②–⑤ and is deliberately I/O-free so it is trivially
/// unit-testable; persistence (⑥) and tracing live in the controller /
/// store. Confirmation (⑦) is a separate service that never lets the AI
/// be the final writer (§5.10.6).
library;

import 'package:uuid/uuid.dart';

import '../../ai_tools/local_skills/local_skills.dart';
import '../domain/ingest_models.dart';
import '../domain/ingest_parse_diagnostics.dart';
import 'ingest_dedup.dart';
import 'statement_ingest_parser.dart';

sealed class IngestPlanningPayload {
  const IngestPlanningPayload();
}

final class DeviceIngestPlanningPayload extends IngestPlanningPayload {
  const DeviceIngestPlanningPayload({
    required this.kind,
    required this.raw,
    required this.defaultCurrency,
  });

  final IngestSourceKind kind;
  final String raw;
  final String defaultCurrency;
}

final class PreParsedIngestPlanningPayload extends IngestPlanningPayload {
  PreParsedIngestPlanningPayload(List<ParsedTransaction> rows)
    : rows = List.unmodifiable(rows);

  final List<ParsedTransaction> rows;
}

final class IngestPlanningRequest {
  IngestPlanningRequest({
    required this.payload,
    required List<TransactionInput> existingLedger,
  }) : existingLedger = List.unmodifiable(existingLedger);

  final IngestPlanningPayload payload;
  final List<TransactionInput> existingLedger;
}

sealed class PlanningDedupTarget {
  const PlanningDedupTarget();
}

final class ExistingEntryTarget extends PlanningDedupTarget {
  const ExistingEntryTarget(this.id);

  final String id;
}

final class BatchRowTarget extends PlanningDedupTarget {
  const BatchRowTarget(this.index);

  final int index;
}

final class AnalyzedIngestRow {
  const AnalyzedIngestRow({
    required this.parsed,
    required this.verdict,
    this.target,
  });

  final ParsedTransaction parsed;
  final DedupVerdict verdict;
  final PlanningDedupTarget? target;
}

final class IngestPlanningAnalysis {
  IngestPlanningAnalysis({
    required List<AnalyzedIngestRow> rows,
    this.rejectedReason,
    List<IngestParseIssue> parseIssues = const <IngestParseIssue>[],
    this.parseCandidateRowCount = 0,
    this.parseDiagnosticsComplete = false,
  }) : rows = List.unmodifiable(rows),
       parseIssues = List.unmodifiable(parseIssues);

  final List<AnalyzedIngestRow> rows;
  final String? rejectedReason;
  final List<IngestParseIssue> parseIssues;
  final int parseCandidateRowCount;
  final bool parseDiagnosticsComplete;

  bool get isRejected => rejectedReason != null;
}

/// Parse, normalize and deduplicate without clocks, ids, I/O or closures.
/// Its object graph is sendable through the background executor seam.
IngestPlanningAnalysis analyzeIngestPlanning(IngestPlanningRequest request) {
  final List<ParsedTransaction> parsed;
  final List<IngestParseIssue> parseIssues;
  final int parseCandidateRowCount;
  final bool parseDiagnosticsComplete;
  switch (request.payload) {
    case DeviceIngestPlanningPayload payload:
      if (!payload.kind.isDeviceParsable) {
        return IngestPlanningAnalysis(
          rows: const <AnalyzedIngestRow>[],
          rejectedReason:
              '「${payload.kind.name}」来源需模型 Vision 解析，S5a 仅支持 CSV / 粘贴文本',
        );
      }
      final report = parseStatementLedgerReport(
        payload.raw,
        defaultCurrency: payload.defaultCurrency,
      );
      parsed = report.rows;
      parseIssues = report.ledger.issues;
      parseCandidateRowCount = report.ledger.candidateRowCount;
      parseDiagnosticsComplete = report.ledger.diagnosticsComplete;
    case PreParsedIngestPlanningPayload payload:
      parsed = payload.rows;
      parseIssues = const <IngestParseIssue>[];
      parseCandidateRowCount = parsed.length;
      parseDiagnosticsComplete = false;
  }

  final index = IngestDedupIndex<PlanningDedupTarget>();
  for (final entry in request.existingLedger) {
    index.add(entry, ExistingEntryTarget(entry.id));
  }

  final rows = <AnalyzedIngestRow>[];
  for (final row in parsed) {
    final classification =
        row.kind == IngestTransactionKind.expense && row.categoryHint == null
        ? classifyTransaction(
            TransactionInput(
              id: 'ingest-probe',
              description: row.description,
              amountMinor: row.amountMinor.toString(),
              currency: row.currency,
              occurredAt: row.occurredAt,
            ),
          )
        : null;
    final normalized = classification == null
        ? row
        : row.copyWith(categoryHint: classification.categoryHint);
    final dedup = index.match(normalized);
    final rowIndex = rows.length;
    rows.add(
      AnalyzedIngestRow(
        parsed: normalized,
        verdict: dedup.verdict,
        target: dedup.target,
      ),
    );
    index.add(
      TransactionInput(
        id: 'batch-row-$rowIndex',
        description: normalized.description,
        amountMinor: normalized.amountMinor.toString(),
        currency: normalized.currency,
        occurredAt: normalized.occurredAt,
        categoryId: normalized.categoryHint,
      ),
      BatchRowTarget(rowIndex),
    );
  }
  return IngestPlanningAnalysis(
    rows: rows,
    parseIssues: parseIssues,
    parseCandidateRowCount: parseCandidateRowCount,
    parseDiagnosticsComplete: parseDiagnosticsComplete,
  );
}

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
    final analysis = analyzeIngestPlanning(
      IngestPlanningRequest(
        payload: DeviceIngestPlanningPayload(
          kind: source.kind,
          raw: source.payload,
          defaultCurrency: defaultCurrency,
        ),
        existingLedger: existingLedger,
      ),
    );
    return materialize(
      analysis: analysis,
      source: source,
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
    final analysis = analyzeIngestPlanning(
      IngestPlanningRequest(
        payload: PreParsedIngestPlanningPayload(parsed),
        existingLedger: existingLedger,
      ),
    );
    return materialize(
      analysis: analysis,
      source: source,
      ownerUserId: ownerUserId,
      traceId: traceId,
    );
  }

  /// Add main-isolate clocks and ids to a pure planning result.
  IngestResult materialize({
    required IngestPlanningAnalysis analysis,
    required IngestSource source,
    required String ownerUserId,
    String? traceId,
  }) {
    if (analysis.isRejected) {
      return IngestResult(
        drafts: const <IngestDraft>[],
        rejectedReason: analysis.rejectedReason,
        parseIssues: analysis.parseIssues,
        parseCandidateRowCount: analysis.parseCandidateRowCount,
        parseDiagnosticsComplete: analysis.parseDiagnosticsComplete,
      );
    }
    final now = _clock();
    final expiresAt = now.add(draftTtl);

    final drafts = <IngestDraft>[];
    final draftIds = <String>[];
    for (var index = 0; index < analysis.rows.length; index++) {
      final row = analysis.rows[index];
      final targetId = switch (row.target) {
        null => null,
        ExistingEntryTarget(:final id) => id,
        BatchRowTarget(:final index)
            when index >= 0 && index < draftIds.length =>
          draftIds[index],
        BatchRowTarget(:final index) => throw StateError(
          'Invalid ingest batch target $index at row ${draftIds.length}.',
        ),
      };
      final draftId = _idGen();
      drafts.add(
        IngestDraft(
          draftId: draftId,
          ownerUserId: ownerUserId,
          createdAt: now,
          sourceKind: source.kind,
          parsed: row.parsed,
          verdict: row.verdict,
          status: DraftStatus.pending,
          originLabel: source.originLabel,
          dedupTargetEntryId: targetId,
          traceId: traceId,
          expiresAt: expiresAt,
        ),
      );
      draftIds.add(draftId);
    }
    return IngestResult(
      drafts: drafts,
      parseIssues: analysis.parseIssues,
      parseCandidateRowCount: analysis.parseCandidateRowCount,
      parseDiagnosticsComplete: analysis.parseDiagnosticsComplete,
    );
  }
}
