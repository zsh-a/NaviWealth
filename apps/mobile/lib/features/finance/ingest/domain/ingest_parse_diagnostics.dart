/// Row-level diagnostics for deterministic statement parsing.
///
/// Diagnostics deliberately carry only a source line number and a stable
/// reason code. They never retain the original row text, so review telemetry
/// and traces cannot accidentally persist statement contents.
library;

enum IngestParseIssueCode {
  invalidDate,
  ignoredStatus,
  unsupportedIncome,
  unsupportedDirection,
  invalidAmount,
  zeroAmount,
  malformedRow,
  unsupportedActivity,
}

class IngestParseIssue {
  const IngestParseIssue({required this.lineNumber, required this.code});

  final int lineNumber;
  final IngestParseIssueCode code;
}

class ParsedLedgerReport<T> {
  ParsedLedgerReport({
    required List<T> rows,
    required List<IngestParseIssue> issues,
    required this.candidateRowCount,
    this.diagnosticsComplete = true,
  }) : rows = List.unmodifiable(rows),
       issues = List.unmodifiable(issues);

  final List<T> rows;
  final List<IngestParseIssue> issues;

  /// Non-empty, non-preamble data rows considered after the header.
  final int candidateRowCount;

  /// False for a provider parser that has not yet adopted row diagnostics.
  /// Callers must not present its issue count as complete row accounting.
  final bool diagnosticsComplete;

  int get acceptedRowCount => rows.length;
  int get skippedRowCount => issues.length;
  bool get accountsForEveryCandidate =>
      diagnosticsComplete &&
      acceptedRowCount + skippedRowCount == candidateRowCount;
}
