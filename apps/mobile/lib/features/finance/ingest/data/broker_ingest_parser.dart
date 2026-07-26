/// Deterministic broker CSV parser for the ingest draft queue.
///
/// Cash income, costs, account transfers, and trades are emitted as typed
/// drafts so review can route each activity to its correct destination.
library;

import '../domain/ingest_models.dart';
import 'delimited_ingest_scalars.dart';

enum _BrokerCol {
  date,
  description,
  type,
  symbol,
  quantity,
  price,
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
  'quantity': _BrokerCol.quantity,
  'qty': _BrokerCol.quantity,
  'shares': _BrokerCol.quantity,
  '成交数量': _BrokerCol.quantity,
  '数量': _BrokerCol.quantity,
  'price': _BrokerCol.price,
  'tradeprice': _BrokerCol.price,
  '成交价格': _BrokerCol.price,
  '价格': _BrokerCol.price,
  'amount': _BrokerCol.amount,
  'netamount': _BrokerCol.amount,
  'cashamount': _BrokerCol.amount,
  'settlementamount': _BrokerCol.amount,
  '金额': _BrokerCol.amount,
  '发生金额': _BrokerCol.amount,
  '成交金额': _BrokerCol.amount,
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

  final delimiter = detectIngestDelimiter(lines);
  final header = _findBrokerHeader(lines, delimiter);
  if (header == null) return const <ParsedTransaction>[];
  final mapping = _headerMapping(header.cells);
  if (mapping == null) return const <ParsedTransaction>[];

  final out = <ParsedTransaction>[];
  for (var i = header.index + 1; i < lines.length; i++) {
    final line = lines[i];
    if (isIngestPreambleLine(line)) continue;
    final rows = _rowToBrokerTransactions(
      splitIngestRow(line, delimiter),
      mapping,
      defaultCurrency,
    );
    out.addAll(rows);
  }
  return out;
}

({int index, List<String> cells})? _findBrokerHeader(
  List<String> lines,
  String delimiter,
) {
  for (var i = 0; i < lines.length; i++) {
    final cells = splitIngestRow(lines[i], delimiter);
    if (_headerMapping(cells) != null) return (index: i, cells: cells);
  }
  return null;
}

Map<int, _BrokerCol>? _headerMapping(List<String> cells) {
  final mapping = <int, _BrokerCol>{};
  for (var i = 0; i < cells.length; i++) {
    final col = _brokerHeaderAliases[normalizeIngestHeader(cells[i])];
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

List<ParsedTransaction> _rowToBrokerTransactions(
  List<String> cells,
  Map<int, _BrokerCol> mapping,
  String defaultCurrency,
) {
  String? cell(_BrokerCol col) {
    for (final entry in mapping.entries) {
      if (entry.value == col && entry.key < cells.length) {
        final value = cleanIngestCell(cells[entry.key]);
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  Iterable<String> cellsFor(_BrokerCol col) sync* {
    for (final entry in mapping.entries) {
      if (entry.value == col && entry.key < cells.length) {
        final value = cleanIngestCell(cells[entry.key]);
        if (value.isNotEmpty) yield value;
      }
    }
  }

  final date = parseIngestDate(cell(_BrokerCol.date), allowChineseDate: false);
  if (date == null) return const <ParsedTransaction>[];

  final type = cell(_BrokerCol.type);
  final desc = cell(_BrokerCol.description);
  final symbol = cell(_BrokerCol.symbol);
  final quantity = cell(_BrokerCol.quantity);
  final price = cell(_BrokerCol.price);
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

  final amount = parseIngestAmountMinor(cell(_BrokerCol.amount));
  final currency = (cell(_BrokerCol.currency) ?? defaultCurrency).toUpperCase();
  final normalizedCurrency = currency.isEmpty ? defaultCurrency : currency;
  final rows = <ParsedTransaction>[];

  if (amount != null && amount != 0 && _isBrokerTransfer(descriptor)) {
    rows.add(
      ParsedTransaction(
        description: [
          amount > 0 ? 'Broker deposit' : 'Broker withdrawal',
          ?type,
          ?desc,
        ].map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().join(' · '),
        amountMinor: amount,
        currency: normalizedCurrency,
        occurredAt: date,
        kind: IngestTransactionKind.transfer,
        categoryHint: 'transfer',
        confidence: 0.88,
      ),
    );
  }

  final tradeSide = _brokerTradeSide(descriptor);
  if (tradeSide != null && amount != null && amount != 0) {
    rows.add(
      ParsedTransaction(
        description: [
          'Broker trade',
          ?symbol,
          ?type,
          ?desc,
        ].map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().join(' · '),
        amountMinor: amount,
        currency: normalizedCurrency,
        occurredAt: date,
        kind: IngestTransactionKind.trade,
        categoryHint: 'trade',
        instrumentSymbol: symbol,
        quantity: quantity,
        unitPrice: price,
        activitySide: tradeSide,
        confidence: quantity == null ? 0.75 : 0.92,
      ),
    );
  }

  final incomeCategory = _brokerIncomeCategoryHint(descriptor);
  if (amount != null && amount > 0 && incomeCategory != null) {
    rows.add(
      ParsedTransaction(
        description: [
          incomeCategory == 'dividend' ? 'Broker dividend' : 'Broker interest',
          ?symbol,
          ?type,
          ?desc,
        ].map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().join(' · '),
        amountMinor: amount.abs(),
        currency: normalizedCurrency,
        occurredAt: date,
        kind: IngestTransactionKind.income,
        categoryHint: incomeCategory,
        confidence: 0.92,
      ),
    );
  }

  final expenseMinor = explicitFeeMinor > 0
      ? explicitFeeMinor
      : amount != null && amount < 0 && _isBrokerExpenseActivity(descriptor)
      ? amount.abs()
      : 0;
  if (expenseMinor > 0) {
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
    rows.add(
      ParsedTransaction(
        description: descriptionParts
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .join(' · '),
        amountMinor: -expenseMinor,
        currency: normalizedCurrency,
        occurredAt: date,
        categoryHint: category,
        confidence: 0.92,
      ),
    );
  }

  return rows;
}

String? _brokerIncomeCategoryHint(String raw) {
  final normalized = normalizeIngestText(raw);
  if (normalized.contains('dividend') ||
      normalized.contains('distribution') ||
      normalized.contains('股息') ||
      normalized.contains('分红')) {
    return 'dividend';
  }
  if (normalized.contains('creditinterest') ||
      normalized.contains('interestincome') ||
      normalized.contains('利息收入')) {
    return 'interest';
  }
  return null;
}

String? _brokerTradeSide(String raw) {
  final normalized = normalizeIngestText(raw);
  if (normalized.contains('buy') || normalized.contains('买入')) return 'buy';
  if (normalized.contains('sell') || normalized.contains('卖出')) return 'sell';
  return null;
}

bool _isBrokerTransfer(String raw) {
  final normalized = normalizeIngestText(raw);
  return normalized.contains('deposit') ||
      normalized.contains('withdrawal') ||
      normalized.contains('withdraw') ||
      normalized.contains('cashtransfer') ||
      normalized.contains('fundtransfer') ||
      normalized.contains('入金') ||
      normalized.contains('出金') ||
      normalized.contains('资金转入') ||
      normalized.contains('资金转出');
}

bool _isBrokerExpenseActivity(String raw) {
  final normalized = normalizeIngestText(raw);
  if (normalized.isEmpty) return false;
  if (_isBrokerFeeOrTax(normalized)) return true;
  return normalized.contains('margininterest') ||
      normalized.contains('interestpaid') ||
      normalized.contains('debitinterest') ||
      normalized.contains('融资利息') ||
      normalized.contains('利息支出');
}

String _brokerCategoryHint(String raw) {
  final normalized = normalizeIngestText(raw);
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
    final parsed = parseIngestAmountMinor(value);
    if (parsed != null) total += parsed.abs();
  }
  return total;
}
