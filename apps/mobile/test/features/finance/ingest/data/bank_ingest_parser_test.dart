import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/data/bank_ingest_parser.dart';

void main() {
  group('parseBankCashLedger', () {
    test('parses Chinese debit/credit split columns and skips credit rows', () {
      final rows = parseBankCashLedger(
        '交易日期,交易摘要,对方户名,借方金额,贷方金额,币种\n'
        '2026-05-11,快捷支付,招商超市,66.80,,CNY\n'
        '2026-05-12,工资,公司,,10000.00,CNY\n',
      );

      expect(rows, hasLength(1));
      expect(rows.single.description, '招商超市 · 快捷支付');
      expect(rows.single.amountMinor, -6680);
      expect(rows.single.currency, 'CNY');
      expect(rows.single.occurredAt, DateTime.utc(2026, 5, 11));
      expect(rows.single.categoryHint, 'groceries');
    });

    test('parses amount plus 借贷标志 exports', () {
      final rows = parseBankCashLedger(
        '账务日期,交易摘要,交易对方,借贷标志,发生额,币种,交易渠道\n'
        '2026年05月13日,地铁出行,上海地铁,借,7.00,CNY,银联\n'
        '2026年05月14日,退款,商户,贷,7.00,CNY,银联\n',
      );

      expect(rows, hasLength(1));
      expect(rows.single.description, '上海地铁 · 地铁出行 · 银联');
      expect(rows.single.amountMinor, -700);
      expect(rows.single.categoryHint, 'transport');
    });

    test('parses English debit/credit bank exports', () {
      final rows = parseBankCashLedger(
        'Posting Date,Details,Debit,Credit,Currency\n'
        '05/15/2026,"Amazon Marketplace","1,234.56",,USD\n'
        '05/16/2026,Payroll,,5000.00,USD\n',
        defaultCurrency: 'USD',
      );

      expect(rows, hasLength(1));
      expect(rows.single.description, 'Amazon Marketplace');
      expect(rows.single.amountMinor, -123456);
      expect(rows.single.currency, 'USD');
      expect(rows.single.categoryHint, 'shopping');
    });

    test('skips failed, cancelled, and refund rows', () {
      final rows = parseBankCashLedger(
        '交易日期,交易摘要,对方户名,借方金额,贷方金额,状态\n'
        '2026-05-11,快捷支付,商户,10.00,,交易失败\n'
        '2026-05-12,快捷支付,商户,10.00,,已退款\n'
        '2026-05-13,快捷支付,商户,10.00,,交易成功\n',
      );

      expect(rows, hasLength(1));
      expect(rows.single.occurredAt, DateTime.utc(2026, 5, 13));
    });
  });
}
