library;

import '../domain/ingest_models.dart';
import '../domain/ingest_parse_diagnostics.dart';
import '../domain/minor_unit_amount.dart';

final RegExp _statementPeriod = RegExp(r'(20\d{2})年(\d{2})月');
final RegExp _candidateRow = RegExp(r'^\s*\d{2}/\d{2}\s+');
final RegExp _transactionRow = RegExp(
  r'^\s*(\d{2})/(\d{2})\s+(?:(\d{2})/(\d{2})\s+)?(.+?)\s+'
  r'(-?[\d,]+\.\d{2})\s+(\d{4})\s+(-?[\d,]+\.\d{2})'
  r'(?:\(([A-Z]{2})\))?\s*$',
);

bool isCmbCreditCardStatement(String raw) =>
    raw.contains('招商银行信用卡对账单') &&
    raw.contains('交易明细') &&
    _statementPeriod.hasMatch(raw);

/// Parses the text layer of a CMB credit-card statement.
///
/// The final amount column is the settled CNY amount. Positive rows are card
/// spending; negative rows (repayments/refunds) are retained only as
/// privacy-safe diagnostics and never become expense drafts.
ParsedLedgerReport<ParsedTransaction> parseCmbCreditCardLedgerReport(
  String raw, {
  String defaultCurrency = 'CNY',
}) {
  final period = _statementPeriod.firstMatch(raw);
  if (period == null) {
    return ParsedLedgerReport(
      rows: const <ParsedTransaction>[],
      issues: const <IngestParseIssue>[],
      candidateRowCount: 0,
    );
  }
  final statementYear = int.parse(period.group(1)!);
  final statementMonth = int.parse(period.group(2)!);
  final rows = <ParsedTransaction>[];
  final issues = <IngestParseIssue>[];
  var candidateRowCount = 0;
  final lines = raw.split(RegExp(r'\r\n|\r|\n'));

  for (final (index, line) in lines.indexed) {
    if (!_candidateRow.hasMatch(line)) continue;
    candidateRowCount++;
    final match = _transactionRow.firstMatch(line);
    if (match == null) {
      issues.add(
        IngestParseIssue(
          lineNumber: index + 1,
          code: IngestParseIssueCode.malformedRow,
        ),
      );
      continue;
    }
    final month = int.parse(match.group(1)!);
    final day = int.parse(match.group(2)!);
    final year = month > statementMonth ? statementYear - 1 : statementYear;
    final occurredAt = DateTime.tryParse(
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}',
    );
    final amountMinor = parseMinorUnitAmount(
      match.group(8)!.replaceAll(',', ''),
    );
    if (occurredAt == null ||
        occurredAt.month != month ||
        occurredAt.day != day) {
      issues.add(
        IngestParseIssue(
          lineNumber: index + 1,
          code: IngestParseIssueCode.invalidDate,
        ),
      );
      continue;
    }
    if (amountMinor == null) {
      issues.add(
        IngestParseIssue(
          lineNumber: index + 1,
          code: IngestParseIssueCode.invalidAmount,
        ),
      );
      continue;
    }
    if (amountMinor == 0) {
      issues.add(
        IngestParseIssue(
          lineNumber: index + 1,
          code: IngestParseIssueCode.zeroAmount,
        ),
      );
      continue;
    }
    if (amountMinor < 0) {
      issues.add(
        IngestParseIssue(
          lineNumber: index + 1,
          code: IngestParseIssueCode.unsupportedDirection,
        ),
      );
      continue;
    }
    rows.add(
      ParsedTransaction(
        description: match.group(5)!.trim(),
        amountMinor: -amountMinor,
        currency: defaultCurrency.toUpperCase(),
        occurredAt: DateTime.utc(year, month, day),
      ),
    );
  }

  return ParsedLedgerReport(
    rows: rows,
    issues: issues,
    candidateRowCount: candidateRowCount,
  );
}
