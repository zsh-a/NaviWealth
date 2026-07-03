/// Deterministic bank CSV parser for the ingest draft queue.
///
/// The generic CSV parser handles simple `date,description,amount` exports.
/// Bank statements often split money into debit/credit columns or use a
/// signed `amount` plus a separate debit/credit marker. This parser covers
/// those common shapes while preserving the current ingest contract: only
/// expense outflows become drafts. Income, refunds, and transfer-like credit
/// rows are skipped until ingest has typed income/transfer destinations.
library;

import 'package:decimal/decimal.dart';

import '../domain/ingest_models.dart';

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

  final delimiter = _detectDelimiter(lines);
  final header = _findBankHeader(lines, delimiter);
  if (header == null) return const <ParsedTransaction>[];
  final mapping = _headerMapping(header.cells);
  if (mapping == null) return const <ParsedTransaction>[];

  final out = <ParsedTransaction>[];
  for (var i = header.index + 1; i < lines.length; i++) {
    final line = lines[i];
    if (_isPreambleLine(line)) continue;
    final row = _rowToBankExpense(
      _splitRow(line, delimiter),
      mapping,
      defaultCurrency,
    );
    if (row != null) out.add(row);
  }
  return out;
}
