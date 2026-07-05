part of 'bank_ingest_parser.dart';

ParsedTransaction? _rowToBankExpense(
  List<String> cells,
  Map<int, _BankCol> mapping,
  String defaultCurrency,
) {
  String? cell(_BankCol col) {
    for (final entry in mapping.entries) {
      if (entry.value == col && entry.key < cells.length) {
        final value = cleanIngestCell(cells[entry.key]);
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  final date = parseIngestDate(cell(_BankCol.date));
  if (date == null) return null;
  if (_shouldSkipByStatus(cell(_BankCol.status))) return null;

  final debit = parseIngestAmountMinor(cell(_BankCol.debit));
  final credit = parseIngestAmountMinor(cell(_BankCol.credit));
  final amount = parseIngestAmountMinor(cell(_BankCol.amount));
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
  final dir = normalizeIngestText(direction ?? '');
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
  final normalized = normalizeIngestText(description);
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
