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

enum _BankCol {
  date,
  description,
  payee,
  amount,
  debit,
  credit,
  currency,
  direction,
  status,
  type,
  channel,
}

const Map<String, _BankCol> _bankHeaderAliases = <String, _BankCol>{
  'date': _BankCol.date,
  'postdate': _BankCol.date,
  'postingdate': _BankCol.date,
  'valuedate': _BankCol.date,
  'transactiondate': _BankCol.date,
  'transactiontime': _BankCol.date,
  '日期': _BankCol.date,
  '交易日期': _BankCol.date,
  '交易时间': _BankCol.date,
  '入账日期': _BankCol.date,
  '记账日期': _BankCol.date,
  '账务日期': _BankCol.date,
  '起息日期': _BankCol.date,
  'description': _BankCol.description,
  'details': _BankCol.description,
  'detail': _BankCol.description,
  'narration': _BankCol.description,
  'memo': _BankCol.description,
  '摘要': _BankCol.description,
  '交易摘要': _BankCol.description,
  '交易说明': _BankCol.description,
  '用途': _BankCol.description,
  '附言': _BankCol.description,
  '备注': _BankCol.description,
  '说明': _BankCol.description,
  'payee': _BankCol.payee,
  'payer': _BankCol.payee,
  'merchant': _BankCol.payee,
  'counterparty': _BankCol.payee,
  'counterpartyname': _BankCol.payee,
  'beneficiary': _BankCol.payee,
  '对方户名': _BankCol.payee,
  '对方名称': _BankCol.payee,
  '对方': _BankCol.payee,
  '交易对方': _BankCol.payee,
  '收款方': _BankCol.payee,
  '付款方': _BankCol.payee,
  '收款人': _BankCol.payee,
  '付款人': _BankCol.payee,
  '商户名称': _BankCol.payee,
  'amount': _BankCol.amount,
  'transactionamount': _BankCol.amount,
  '金额': _BankCol.amount,
  '金额(元)': _BankCol.amount,
  '金额（元）': _BankCol.amount,
  '发生额': _BankCol.amount,
  '交易金额': _BankCol.amount,
  '本币金额': _BankCol.amount,
  '人民币金额': _BankCol.amount,
  'debit': _BankCol.debit,
  'debitamount': _BankCol.debit,
  'paidout': _BankCol.debit,
  'withdrawal': _BankCol.debit,
  'outflow': _BankCol.debit,
  '支出': _BankCol.debit,
  '支出金额': _BankCol.debit,
  '借方金额': _BankCol.debit,
  '借方发生额': _BankCol.debit,
  '取出': _BankCol.debit,
  '转出金额': _BankCol.debit,
  '付款金额': _BankCol.debit,
  '消费金额': _BankCol.debit,
  'credit': _BankCol.credit,
  'creditamount': _BankCol.credit,
  'paidin': _BankCol.credit,
  'deposit': _BankCol.credit,
  'inflow': _BankCol.credit,
  '收入': _BankCol.credit,
  '收入金额': _BankCol.credit,
  '贷方金额': _BankCol.credit,
  '贷方发生额': _BankCol.credit,
  '存入': _BankCol.credit,
  '转入金额': _BankCol.credit,
  '收款金额': _BankCol.credit,
  'currency': _BankCol.currency,
  'ccy': _BankCol.currency,
  'curr': _BankCol.currency,
  '货币': _BankCol.currency,
  '币种': _BankCol.currency,
  '币别': _BankCol.currency,
  'direction': _BankCol.direction,
  'drcr': _BankCol.direction,
  'debitcredit': _BankCol.direction,
  '借贷': _BankCol.direction,
  '借贷标志': _BankCol.direction,
  '借贷方向': _BankCol.direction,
  '收支': _BankCol.direction,
  '收/支': _BankCol.direction,
  '收入/支出': _BankCol.direction,
  '交易方向': _BankCol.direction,
  'status': _BankCol.status,
  '状态': _BankCol.status,
  '交易状态': _BankCol.status,
  '当前状态': _BankCol.status,
  'type': _BankCol.type,
  'transactiontype': _BankCol.type,
  '业务类型': _BankCol.type,
  '交易类型': _BankCol.type,
  '渠道': _BankCol.channel,
  '交易渠道': _BankCol.channel,
  '支付方式': _BankCol.channel,
  '付款方式': _BankCol.channel,
};

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

String _detectDelimiter(List<String> lines) {
  final sample = lines.firstWhere(
    (l) => !_isPreambleLine(l),
    orElse: () => lines.first,
  );
  if (sample.contains('\t')) return '\t';
  if (sample.contains(';') && !sample.contains(',')) return ';';
  return ',';
}

({int index, List<String> cells})? _findBankHeader(
  List<String> lines,
  String delimiter,
) {
  for (var i = 0; i < lines.length; i++) {
    final cells = _splitRow(lines[i], delimiter);
    if (_headerMapping(cells) != null) return (index: i, cells: cells);
  }
  return null;
}

Map<int, _BankCol>? _headerMapping(List<String> cells) {
  final mapping = <int, _BankCol>{};
  for (var i = 0; i < cells.length; i++) {
    final col = _bankHeaderAliases[_normalizeHeader(cells[i])];
    if (col != null) mapping[i] = col;
  }
  final hasAmount =
      mapping.values.contains(_BankCol.amount) ||
      mapping.values.contains(_BankCol.debit) ||
      mapping.values.contains(_BankCol.credit);
  if (!mapping.values.contains(_BankCol.date) || !hasAmount) return null;
  return mapping;
}

ParsedTransaction? _rowToBankExpense(
  List<String> cells,
  Map<int, _BankCol> mapping,
  String defaultCurrency,
) {
  String? cell(_BankCol col) {
    for (final entry in mapping.entries) {
      if (entry.value == col && entry.key < cells.length) {
        final value = _cleanCell(cells[entry.key]);
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  final date = _parseDate(cell(_BankCol.date));
  if (date == null) return null;
  if (_shouldSkipByStatus(cell(_BankCol.status))) return null;

  final debit = _parseAmountMinor(cell(_BankCol.debit));
  final credit = _parseAmountMinor(cell(_BankCol.credit));
  final amount = _parseAmountMinor(cell(_BankCol.amount));
  final direction = cell(_BankCol.direction);
  final minor = _resolveExpenseMinor(
    amount: amount,
    debit: debit,
    credit: credit,
    direction: direction,
  );
  if (minor == null || minor == 0) return null;

  final payee = cell(_BankCol.payee);
  final desc = cell(_BankCol.description);
  final type = cell(_BankCol.type);
  final channel = cell(_BankCol.channel);
  final descriptionParts = <String>[
    ?payee,
    ?desc,
    ?type,
    ?channel,
  ].map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
  final description = descriptionParts.isEmpty
      ? 'Bank transaction'
      : descriptionParts.join(' · ');

  final currency = (cell(_BankCol.currency) ?? defaultCurrency)
      .toUpperCase()
      .trim();
  return ParsedTransaction(
    description: description,
    amountMinor: -minor.abs(),
    currency: currency.isEmpty ? defaultCurrency : currency,
    occurredAt: date,
    categoryHint: _categoryHint(description),
    confidence: 0.9,
  );
}

int? _resolveExpenseMinor({
  required int? amount,
  required int? debit,
  required int? credit,
  required String? direction,
}) {
  final dir = _normalizeText(direction ?? '');
  if (dir.isNotEmpty) {
    if (_isCreditDirection(dir)) return null;
    if (_isDebitDirection(dir)) return (amount ?? debit)?.abs();
  }
  if (debit != null && debit != 0) return debit.abs();
  if (credit != null && credit != 0 && (amount == null || amount == 0)) {
    return null;
  }
  if (amount == null || amount == 0) return null;
  if (credit != null && credit.abs() == amount.abs() && amount > 0) {
    return null;
  }
  return amount.abs();
}

bool _isDebitDirection(String dir) {
  return dir == 'd' ||
      dir == 'dr' ||
      dir == 'debit' ||
      dir == '借' ||
      dir == '支' ||
      dir.contains('debit') ||
      dir.contains('paidout') ||
      dir.contains('withdrawal') ||
      dir.contains('支出') ||
      dir.contains('借方') ||
      dir.contains('付款') ||
      dir.contains('转出') ||
      dir.contains('消费');
}

bool _isCreditDirection(String dir) {
  return dir == 'c' ||
      dir == 'cr' ||
      dir == 'credit' ||
      dir == '贷' ||
      dir == '收' ||
      dir.contains('credit') ||
      dir.contains('paidin') ||
      dir.contains('deposit') ||
      dir.contains('收入') ||
      dir.contains('贷方') ||
      dir.contains('收款') ||
      dir.contains('转入') ||
      dir.contains('退款');
}

String? _categoryHint(String description) {
  final normalized = _normalizeText(description);
  if (normalized.contains('地铁') ||
      normalized.contains('公交') ||
      normalized.contains('铁路') ||
      normalized.contains('高铁') ||
      normalized.contains('taxi') ||
      normalized.contains('uber') ||
      normalized.contains('滴滴')) {
    return 'transport';
  }
  if (normalized.contains('咖啡') ||
      normalized.contains('星巴克') ||
      normalized.contains('瑞幸') ||
      normalized.contains('coffee')) {
    return 'coffee';
  }
  if (normalized.contains('餐') ||
      normalized.contains('饭') ||
      normalized.contains('外卖') ||
      normalized.contains('restaurant') ||
      normalized.contains('dining')) {
    return 'dining';
  }
  if (normalized.contains('超市') ||
      normalized.contains('grocery') ||
      normalized.contains('wholefoods')) {
    return 'groceries';
  }
  if (normalized.contains('电费') ||
      normalized.contains('水费') ||
      normalized.contains('燃气') ||
      normalized.contains('utility')) {
    return 'utilities';
  }
  if (normalized.contains('购物') ||
      normalized.contains('商场') ||
      normalized.contains('amazon') ||
      normalized.contains('shopping')) {
    return 'shopping';
  }
  return null;
}

DateTime? _parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  final cleaned = _cleanCell(s);
  final iso = DateTime.tryParse(cleaned);
  if (iso != null) return DateTime.utc(iso.year, iso.month, iso.day);
  final cm = RegExp(r'^(\d{4})年(\d{1,2})月(\d{1,2})日?').firstMatch(cleaned);
  if (cm != null) {
    final year = int.parse(cm.group(1)!);
    final month = int.parse(cm.group(2)!);
    final day = int.parse(cm.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime.utc(year, month, day);
  }
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

bool _shouldSkipByStatus(String? status) {
  if (status == null || status.isEmpty) return false;
  final normalized = _normalizeText(status);
  return normalized.contains('失败') ||
      normalized.contains('关闭') ||
      normalized.contains('撤销') ||
      normalized.contains('取消') ||
      normalized.contains('退款') ||
      normalized.contains('reversed') ||
      normalized.contains('cancelled') ||
      normalized.contains('failed');
}

String _normalizeHeader(String s) => _cleanCell(s)
    .toLowerCase()
    .replaceAll(RegExp(r'[\s_\-：:\/]+'), '')
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
