/// Deterministic bank CSV parser for the ingest draft queue.
///
/// The generic CSV parser handles simple `date,description,amount` exports.
/// Bank statements often split money into debit/credit columns or use a
/// signed `amount` plus a separate debit/credit marker. This parser covers
/// those common shapes as typed expense/income drafts. Transfer rows retain a
/// typed transfer destination so review can hand them to the atomic two-account
/// transfer form. Refund credits remain excluded until reconciliation can link
/// them to an original expense.
library;

import '../domain/ingest_models.dart';
import 'delimited_ingest_scalars.dart';

part 'bank_ingest_headers.dart';
part 'bank_ingest_rows.dart';
part 'bank_ingest_scalars.dart';

List<ParsedTransaction> parseBankCashLedger(
  String raw, {
  String defaultCurrency = 'CNY',
}) {
  final lines = raw
      .split(RegExp(r'\r\n|\r|\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) return const <ParsedTransaction>[];

  final delimiter = detectIngestDelimiter(lines);
  final header = _findBankHeader(lines, delimiter);
  if (header == null) return const <ParsedTransaction>[];
  final mapping = _headerMapping(header.cells);
  if (mapping == null) return const <ParsedTransaction>[];

  final out = <ParsedTransaction>[];
  for (var i = header.index + 1; i < lines.length; i++) {
    final line = lines[i];
    if (isIngestPreambleLine(line)) continue;
    final row = _rowToBankTransaction(
      splitIngestRow(line, delimiter),
      mapping,
      defaultCurrency,
    );
    if (row != null) out.add(row);
  }
  return out;
}
