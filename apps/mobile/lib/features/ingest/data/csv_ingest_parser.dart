/// §5.10.10 / S5a — the on-device deterministic statement parser.
///
/// No network, no LLM: a pasted CSV / TSV statement is turned into
/// [ParsedTransaction]s by pure string work. This is the "device-first,
/// 云端仅在必要时" rule in practice — the cloud Vision path (S5b) only
/// exists for inputs this parser structurally cannot read (images/PDF).
library;

import 'package:decimal/decimal.dart';

import '../domain/ingest_models.dart';

/// Header tokens (lower-cased, CJK included) that map a column to a role.
const Map<String, _Col> _headerAliases = <String, _Col>{
  'date': _Col.date,
  '日期': _Col.date,
  '交易日期': _Col.date,
  '交易时间': _Col.date,
  '交易创建时间': _Col.date,
  '付款时间': _Col.date,
  '支付时间': _Col.date,
  '入账日期': _Col.date,
  '记账日期': _Col.date,
  '账务日期': _Col.date,
  'time': _Col.date,
  'postdate': _Col.date,
  'transactiondate': _Col.date,
  'description': _Col.description,
  'desc': _Col.description,
  'narration': _Col.description,
  '摘要': _Col.description,
  '备注': _Col.description,
  '描述': _Col.description,
  '商品': _Col.description,
  '商品名称': _Col.description,
  '交易摘要': _Col.description,
  '交易说明': _Col.description,
  '用途': _Col.description,
  '附言': _Col.description,
  'payee': _Col.payee,
  'merchant': _Col.payee,
  '商家': _Col.payee,
  '交易对方': _Col.payee,
  '对方': _Col.payee,
  '对方户名': _Col.payee,
  '商户名称': _Col.payee,
  '收款方': _Col.payee,
  '付款方': _Col.payee,
  'amount': _Col.amount,
  '金额': _Col.amount,
  '金额(元)': _Col.amount,
  '金额（元）': _Col.amount,
  '发生额': _Col.amount,
  '交易金额': _Col.amount,
  '交易金额(元)': _Col.amount,
  '交易金额（元）': _Col.amount,
  '人民币金额': _Col.amount,
  '本币金额': _Col.amount,
  '支出': _Col.expenseAmount,
  '支出金额': _Col.expenseAmount,
  '借方金额': _Col.expenseAmount,
  '借方发生额': _Col.expenseAmount,
  '取出': _Col.expenseAmount,
  '转出金额': _Col.expenseAmount,
  '付款金额': _Col.expenseAmount,
  '消费金额': _Col.expenseAmount,
  '收入': _Col.incomeAmount,
  '收入金额': _Col.incomeAmount,
  '贷方金额': _Col.incomeAmount,
  '贷方发生额': _Col.incomeAmount,
  '存入': _Col.incomeAmount,
  '转入金额': _Col.incomeAmount,
  '收款金额': _Col.incomeAmount,
  'currency': _Col.currency,
  '货币': _Col.currency,
  '币种': _Col.currency,
  '币别': _Col.currency,
  '收/支': _Col.direction,
  '收支': _Col.direction,
  '收入/支出': _Col.direction,
  '借贷方向': _Col.direction,
  '交易方向': _Col.direction,
  '状态': _Col.status,
  '交易状态': _Col.status,
  '当前状态': _Col.status,
  '类型': _Col.type,
  '交易类型': _Col.type,
  '业务类型': _Col.type,
  '支付方式': _Col.paymentMethod,
  '付款方式': _Col.paymentMethod,
  '交易渠道': _Col.paymentMethod,
  '账户': _Col.paymentMethod,
};

enum _Col {
  date,
  description,
  payee,
  amount,
  expenseAmount,
  incomeAmount,
  currency,
  direction,
  status,
  type,
  paymentMethod,
}

/// Parse a CSV/TSV ledger dump. Rows that don't yield a valid date *and*
/// amount are skipped (never guessed) — a partial parse beats a wrong one.
/// [defaultCurrency] is used when the row carries no currency column.
List<ParsedTransaction> parseCsvLedger(
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
  final header = _findHeader(lines, delimiter);
  final mapping = header == null ? null : _headerMapping(header.cells);
  final dataStart = mapping != null ? header!.index + 1 : 0;
  // Positional fallback when there is no recognisable header:
  // date, description, amount, [currency].
  final effective =
      mapping ??
      <int, _Col>{
        0: _Col.date,
        1: _Col.description,
        2: _Col.amount,
        3: _Col.currency,
      };

  final out = <ParsedTransaction>[];
  for (var i = dataStart; i < lines.length; i++) {
    final line = lines[i];
    if (_isPreambleLine(line)) continue;
    final cells = _splitRow(line, delimiter);
    final txn = _rowToTransaction(cells, effective, defaultCurrency);
    if (txn != null) out.add(txn);
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

({int index, List<String> cells})? _findHeader(
  List<String> lines,
  String delimiter,
) {
  for (var i = 0; i < lines.length; i++) {
    final cells = _splitRow(lines[i], delimiter);
    if (_headerMapping(cells) != null) return (index: i, cells: cells);
  }
  return null;
}

bool _isPreambleLine(String line) {
  final t = line.trim();
  if (t.isEmpty) return true;
  if (t.startsWith('#')) return true;
  if (t.startsWith('----------------')) return true;
  return false;
}

List<String> _splitRow(String line, String delimiter) {
  // Minimal RFC-4180-ish handling: respect double-quoted fields so a
  // memo containing the delimiter doesn't shift columns.
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

Map<int, _Col>? _headerMapping(List<String> cells) {
  final mapping = <int, _Col>{};
  for (var i = 0; i < cells.length; i++) {
    final key = _normalizeHeader(cells[i]);
    final col = _headerAliases[key];
    if (col != null) mapping[i] = col;
  }
  // A header is only a header if it pins at least date + amount.
  if (mapping.values.contains(_Col.date) &&
      (mapping.values.contains(_Col.amount) ||
          mapping.values.contains(_Col.expenseAmount) ||
          mapping.values.contains(_Col.incomeAmount))) {
    return mapping;
  }
  return null;
}

String _normalizeHeader(String s) => _cleanCell(s)
    .toLowerCase()
    .replaceAll(RegExp(r'[\s_\-：:]+'), '')
    .replaceAll('（', '(')
    .replaceAll('）', ')');

ParsedTransaction? _rowToTransaction(
  List<String> cells,
  Map<int, _Col> mapping,
  String defaultCurrency,
) {
  String? cell(_Col c) {
    for (final e in mapping.entries) {
      if (e.value == c && e.key < cells.length) {
        final v = _cleanCell(cells[e.key]);
        if (v.isNotEmpty) return v;
      }
    }
    return null;
  }

  final date = _parseDate(cell(_Col.date));
  if (date == null) return null;

  if (_shouldSkipByStatus(cell(_Col.status))) return null;

  final direction = cell(_Col.direction);
  final explicitExpense = _parseAmountMinor(cell(_Col.expenseAmount));
  final explicitIncome = _parseAmountMinor(cell(_Col.incomeAmount));
  final genericAmount = _parseAmountMinor(cell(_Col.amount));
  final minor = _resolveExpenseMinor(
    amount: genericAmount,
    expenseAmount: explicitExpense,
    incomeAmount: explicitIncome,
    direction: direction,
  );
  if (minor == null || minor == 0) return null;

  final payee = cell(_Col.payee);
  final desc = cell(_Col.description);
  final type = cell(_Col.type);
  final payment = cell(_Col.paymentMethod);
  final descriptionParts = [
    payee,
    desc,
    type,
    payment,
  ].where((s) => s != null && s.isNotEmpty).cast<String>().toSet();
  final description = descriptionParts.join(' · ');

  final currency = (cell(_Col.currency) ?? defaultCurrency)
      .toUpperCase()
      .trim();

  return ParsedTransaction(
    // S5a only produces expenses; normalise to the negative-outflow
    // convention regardless of how the bank signed the column.
    description: description.isEmpty ? '未命名交易' : description,
    amountMinor: -minor.abs(),
    currency: currency.isEmpty ? defaultCurrency : currency,
    occurredAt: date,
  );
}

DateTime? _parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  final cleaned = _cleanCell(s);
  final iso = DateTime.tryParse(cleaned);
  if (iso != null) return DateTime.utc(iso.year, iso.month, iso.day);

  final m = RegExp(
    r'^(\d{1,4})[-/.](\d{1,2})[-/.](\d{1,4})',
  ).firstMatch(cleaned);
  final cm = RegExp(r'^(\d{4})年(\d{1,2})月(\d{1,2})日?').firstMatch(cleaned);
  if (m == null && cm == null) return null;
  if (cm != null) {
    final y = int.parse(cm.group(1)!);
    final mo = int.parse(cm.group(2)!);
    final d = int.parse(cm.group(3)!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    return DateTime.utc(y, mo, d);
  }
  final a = int.parse(m!.group(1)!);
  final b = int.parse(m.group(2)!);
  final c = int.parse(m.group(3)!);
  // yyyy-mm-dd when the first group is a 4-digit year, else mm/dd/yyyy.
  final int y;
  final int mo;
  final int d;
  if (a > 31) {
    y = a;
    mo = b;
    d = c;
  } else {
    y = c < 100 ? 2000 + c : c;
    mo = a;
    d = b;
  }
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime.utc(y, mo, d);
}

int? _parseAmountMinor(String? s) {
  if (s == null || s.isEmpty) return null;
  var t = _cleanCell(s);
  if (t.isEmpty || t == '/' || t == '--' || t == '-') return null;
  final negative = t.startsWith('-') || (t.startsWith('(') && t.endsWith(')'));
  // Drop currency glyphs / letters / spaces / parens, keep digits, sign,
  // separators. Then treat comma as a thousands separator.
  t = t.replaceAll(RegExp(r'[^\d.,-]'), '');
  if (t.contains(',') && t.contains('.')) {
    t = t.replaceAll(',', '');
  } else if (t.contains(',') && !t.contains('.')) {
    // Ambiguous "1,234" → thousands; "1,23" (rare) also → drop comma.
    t = t.replaceAll(',', '');
  }
  t = t.replaceAll(RegExp(r'(?!^)-'), '');
  final dec = Decimal.tryParse(t.replaceAll('-', ''));
  if (dec == null) return null;
  final minor = (dec * Decimal.fromInt(100)).round().toBigInt().toInt();
  return negative ? -minor : minor;
}

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

bool _shouldSkipByStatus(String? status) {
  if (status == null || status.isEmpty) return false;
  final s = status.replaceAll(RegExp(r'\s+'), '');
  return s.contains('失败') ||
      s.contains('关闭') ||
      s.contains('撤销') ||
      s.contains('取消') ||
      s.contains('全额退款') ||
      s.contains('已退款') ||
      s.contains('退款成功');
}

int? _resolveExpenseMinor({
  required int? amount,
  required int? expenseAmount,
  required int? incomeAmount,
  required String? direction,
}) {
  final dir = direction?.replaceAll(RegExp(r'\s+'), '');
  if (dir != null && dir.isNotEmpty) {
    if (dir.contains('收入') || dir == '收') return null;
    if (dir.contains('不计') || dir.contains('其他')) return null;
    if (dir.contains('退款')) return null;
    if (dir.contains('支出') || dir == '支') {
      return amount?.abs() ?? expenseAmount?.abs();
    }
  }
  if (expenseAmount != null && expenseAmount != 0) return expenseAmount.abs();
  if ((amount == null || amount == 0) &&
      incomeAmount != null &&
      incomeAmount != 0) {
    return null;
  }
  if (amount == null) return null;
  if (amount > 0 && incomeAmount != null && incomeAmount.abs() == amount) {
    return null;
  }
  return amount.abs();
}
