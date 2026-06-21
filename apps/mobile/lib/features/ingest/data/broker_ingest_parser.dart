/// Deterministic broker CSV parser for the ingest draft queue.
///
/// The current confirmation path records parsed rows as expenses, so this
/// parser is deliberately narrow: it imports broker fees, commissions, taxes,
/// and margin-interest expenses only. Dividends, interest income, deposits,
/// withdrawals, and trade principal rows are skipped until ingest has a typed
/// investment-activity destination.
library;

import 'package:decimal/decimal.dart';

import '../domain/ingest_models.dart';

enum _BrokerCol {
  date,
  description,
  type,
  symbol,
  amount,
  currency,
  commission,
  fee,
  tax,
}

const Map<String, _BrokerCol> _brokerHeaderAliases = <String, _BrokerCol>{
  'date': _BrokerCol.date,
  'datetime': _BrokerCol.date,
  'date/time': _BrokerCol.date,
  'activitydate': _BrokerCol.date,
  'tradedate': _BrokerCol.date,
  'settledate': _BrokerCol.date,
  'settlementdate': _BrokerCol.date,
  '日期': _BrokerCol.date,
  '交易日期': _BrokerCol.date,
  '成交日期': _BrokerCol.date,
  '发生日期': _BrokerCol.date,
  'description': _BrokerCol.description,
  'desc': _BrokerCol.description,
  'activitydescription': _BrokerCol.description,
  'memo': _BrokerCol.description,
  'name': _BrokerCol.description,
  '描述': _BrokerCol.description,
  '备注': _BrokerCol.description,
  '名称': _BrokerCol.description,
  'type': _BrokerCol.type,
  'action': _BrokerCol.type,
  'trancode': _BrokerCol.type,
  'transcode': _BrokerCol.type,
  'transactiontype': _BrokerCol.type,
  'activitytype': _BrokerCol.type,
  '类型': _BrokerCol.type,
  '业务类型': _BrokerCol.type,
  '操作': _BrokerCol.type,
  'symbol': _BrokerCol.symbol,
  'ticker': _BrokerCol.symbol,
  'code': _BrokerCol.symbol,
  'instrument': _BrokerCol.symbol,
  '代码': _BrokerCol.symbol,
  '证券代码': _BrokerCol.symbol,
  '股票代码': _BrokerCol.symbol,
  'amount': _BrokerCol.amount,
  'netamount': _BrokerCol.amount,
  'cashamount': _BrokerCol.amount,
  'settlementamount': _BrokerCol.amount,
  '金额': _BrokerCol.amount,
  '发生金额': _BrokerCol.amount,
  '结算金额': _BrokerCol.amount,
  '净金额': _BrokerCol.amount,
  'currency': _BrokerCol.currency,
  'curr': _BrokerCol.currency,
  'ccy': _BrokerCol.currency,
  '币种': _BrokerCol.currency,
  '币别': _BrokerCol.currency,
  'commission': _BrokerCol.commission,
  'commissions': _BrokerCol.commission,
  'fees&comm': _BrokerCol.commission,
  'feescomm': _BrokerCol.commission,
  '手续费': _BrokerCol.commission,
  '佣金': _BrokerCol.commission,
  'fee': _BrokerCol.fee,
  'fees': _BrokerCol.fee,
  'platformfee': _BrokerCol.fee,
  'adrfee': _BrokerCol.fee,
  'secfee': _BrokerCol.fee,
  'exchangefee': _BrokerCol.fee,
  'regulatoryfee': _BrokerCol.fee,
  '费用': _BrokerCol.fee,
  '平台费': _BrokerCol.fee,
  '交收费': _BrokerCol.fee,
  '交易费': _BrokerCol.fee,
  'tax': _BrokerCol.tax,
  'taxes': _BrokerCol.tax,
  'withholding': _BrokerCol.tax,
  'withholdingtax': _BrokerCol.tax,
  '税': _BrokerCol.tax,
  '税费': _BrokerCol.tax,
  '预扣税': _BrokerCol.tax,
};

List<ParsedTransaction> parseBrokerCashLedger(
  String raw, {
  String defaultCurrency = 'USD',
}) {
  final lines = raw
      .split(RegExp(r'\r\n|\r|\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) return const <ParsedTransaction>[];

  final delimiter = _detectDelimiter(lines);
  final header = _findBrokerHeader(lines, delimiter);
  if (header == null) return const <ParsedTransaction>[];
  final mapping = _headerMapping(header.cells);
  if (mapping == null) return const <ParsedTransaction>[];

  final out = <ParsedTransaction>[];
  for (var i = header.index + 1; i < lines.length; i++) {
    final line = lines[i];
    if (_isPreambleLine(line)) continue;
    final row = _rowToBrokerExpense(
      _splitRow(line, delimiter),
      mapping,
      defaultCurrency,
    );
    if (row != null) out.add(row);
  }
  return out;
}

String _detectDelimiter(List<String> lines) {
  final sample = lines.firstWhere(
    (l) => !_isPreambleLine(l),
    orElse: () => lines.first,
  );
  if (sample.contains('\t')) return '\t';
  if (sample.contains(';') && !sample.contains(',')) return ';';
  return ',';
}

({int index, List<String> cells})? _findBrokerHeader(
  List<String> lines,
  String delimiter,
) {
  for (var i = 0; i < lines.length; i++) {
    final cells = _splitRow(lines[i], delimiter);
    if (_headerMapping(cells) != null) return (index: i, cells: cells);
  }
  return null;
}

Map<int, _BrokerCol>? _headerMapping(List<String> cells) {
  final mapping = <int, _BrokerCol>{};
  for (var i = 0; i < cells.length; i++) {
    final col = _brokerHeaderAliases[_normalizeHeader(cells[i])];
    if (col != null) mapping[i] = col;
  }
  final hasExpenseAmount =
      mapping.values.contains(_BrokerCol.amount) ||
      mapping.values.contains(_BrokerCol.commission) ||
      mapping.values.contains(_BrokerCol.fee) ||
      mapping.values.contains(_BrokerCol.tax);
  if (!mapping.values.contains(_BrokerCol.date) || !hasExpenseAmount) {
    return null;
  }
  return mapping;
}

ParsedTransaction? _rowToBrokerExpense(
  List<String> cells,
  Map<int, _BrokerCol> mapping,
  String defaultCurrency,
) {
  String? cell(_BrokerCol col) {
    for (final entry in mapping.entries) {
      if (entry.value == col && entry.key < cells.length) {
        final value = _cleanCell(cells[entry.key]);
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  Iterable<String> cellsFor(_BrokerCol col) sync* {
    for (final entry in mapping.entries) {
      if (entry.value == col && entry.key < cells.length) {
        final value = _cleanCell(cells[entry.key]);
        if (value.isNotEmpty) yield value;
      }
    }
  }

  final date = _parseDate(cell(_BrokerCol.date));
  if (date == null) return null;

  final type = cell(_BrokerCol.type);
  final desc = cell(_BrokerCol.description);
  final symbol = cell(_BrokerCol.symbol);
  final descriptor = [
    type,
    desc,
    symbol,
  ].where((s) => s != null && s.trim().isNotEmpty).cast<String>().join(' ');

  final explicitFeeMinor = _sumAbsMinor(<String>[
    ...cellsFor(_BrokerCol.commission),
    ...cellsFor(_BrokerCol.fee),
    ...cellsFor(_BrokerCol.tax),
  ]);
  final category = _brokerCategoryHint(descriptor);

  int? minor;
  if (explicitFeeMinor > 0) {
    minor = explicitFeeMinor;
  } else {
    final amount = _parseAmountMinor(cell(_BrokerCol.amount));
    if (amount == null || amount >= 0) return null;
    if (!_isBrokerExpenseActivity(descriptor)) return null;
    minor = amount.abs();
  }
  if (minor == 0) return null;

  final descriptionParts = <String>[
    category == 'tax:withholding'
        ? 'Broker withholding tax'
        : category == 'trading:tax'
        ? 'Broker trading tax'
        : 'Broker fee',
    ?symbol,
    ?type,
    ?desc,
  ];
  final description = descriptionParts
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .join(' · ');

  final currency = (cell(_BrokerCol.currency) ?? defaultCurrency).toUpperCase();
  return ParsedTransaction(
    description: description,
    amountMinor: -minor,
    currency: currency.isEmpty ? defaultCurrency : currency,
    occurredAt: date,
    categoryHint: category,
    confidence: 0.92,
  );
}

bool _isBrokerExpenseActivity(String raw) {
  final normalized = _normalizeText(raw);
  if (normalized.isEmpty) return false;
  if (_isBrokerFeeOrTax(normalized)) return true;
  return normalized.contains('margininterest') ||
      normalized.contains('interestpaid') ||
      normalized.contains('debitinterest') ||
      normalized.contains('融资利息') ||
      normalized.contains('利息支出');
}

String _brokerCategoryHint(String raw) {
  final normalized = _normalizeText(raw);
  if (normalized.contains('withholdingtax') ||
      normalized.contains('withholding') ||
      normalized.contains('预扣税')) {
    return 'tax:withholding';
  }
  if (normalized.contains('tax') ||
      normalized.contains('secfee') ||
      normalized.contains('regulatoryfee') ||
      normalized.contains('证监费') ||
      normalized.contains('税')) {
    return 'trading:tax';
  }
  return 'trading:fee';
}

bool _isBrokerFeeOrTax(String normalized) {
  return normalized.contains('fee') ||
      normalized.contains('commission') ||
      normalized.contains('commissions') ||
      normalized.contains('tax') ||
      normalized.contains('withholding') ||
      normalized.contains('regulatory') ||
      normalized.contains('手续费') ||
      normalized.contains('佣金') ||
      normalized.contains('费用') ||
      normalized.contains('平台费') ||
      normalized.contains('交收费') ||
      normalized.contains('税');
}

int _sumAbsMinor(Iterable<String?> values) {
  var total = 0;
  for (final value in values) {
    final parsed = _parseAmountMinor(value);
    if (parsed != null) total += parsed.abs();
  }
  return total;
}

DateTime? _parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  final cleaned = _cleanCell(s);
  final iso = DateTime.tryParse(cleaned);
  if (iso != null) return DateTime.utc(iso.year, iso.month, iso.day);
  final m = RegExp(
    r'^(\d{1,4})[-/.](\d{1,2})[-/.](\d{1,4})',
  ).firstMatch(cleaned);
  if (m == null) return null;
  final a = int.parse(m.group(1)!);
  final b = int.parse(m.group(2)!);
  final c = int.parse(m.group(3)!);
  final int year;
  final int month;
  final int day;
  if (a > 31) {
    year = a;
    month = b;
    day = c;
  } else {
    year = c < 100 ? 2000 + c : c;
    month = a;
    day = b;
  }
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime.utc(year, month, day);
}

int? _parseAmountMinor(String? s) {
  if (s == null || s.isEmpty) return null;
  var t = _cleanCell(s);
  if (t.isEmpty || t == '/' || t == '--' || t == '-') return null;
  final negative = t.startsWith('-') || (t.startsWith('(') && t.endsWith(')'));
  t = t.replaceAll(RegExp(r'[^\d.,-]'), '');
  if (t.contains(',')) t = t.replaceAll(',', '');
  t = t.replaceAll(RegExp(r'(?!^)-'), '');
  final dec = Decimal.tryParse(t.replaceAll('-', ''));
  if (dec == null) return null;
  final minor = (dec * Decimal.fromInt(100)).round().toBigInt().toInt();
  return negative ? -minor : minor;
}

List<String> _splitRow(String line, String delimiter) {
  final cells = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch == delimiter && !inQuotes) {
      cells.add(buf.toString().trim());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  cells.add(buf.toString().trim());
  return cells;
}

bool _isPreambleLine(String line) {
  final t = line.trim();
  return t.isEmpty || t.startsWith('#') || t.startsWith('----------------');
}

String _normalizeHeader(String s) => _cleanCell(s)
    .toLowerCase()
    .replaceAll(RegExp(r'[\s_\-：:]+'), '')
    .replaceAll('（', '(')
    .replaceAll('）', ')');

String _normalizeText(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[\s_\-：:·,，/()（）&]+'), '');

String _cleanCell(String s) {
  var t = s
      .replaceAll('\ufeff', '')
      .replaceAll('\u200b', '')
      .replaceAll('"', '')
      .trim();
  while (t.startsWith('`') || t.startsWith('\'')) {
    t = t.substring(1).trimLeft();
  }
  return t;
}
