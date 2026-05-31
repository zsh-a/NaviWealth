import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ingest/data/statement_ingest_parser.dart';

void main() {
  group('statement provider detection', () {
    test('detects Alipay, WeChat Pay, bank, and generic exports', () {
      expect(
        detectStatementProvider('#支付宝交易记录明细查询\n交易号,商家订单号,交易创建时间,付款时间'),
        StatementProvider.alipay,
      );
      expect(
        detectStatementProvider('#微信支付账单明细\n交易时间,交易类型,交易对方,商品,收/支'),
        StatementProvider.wechatPay,
      );
      expect(
        detectStatementProvider('交易日期,交易摘要,支出金额,收入金额,币种'),
        StatementProvider.bank,
      );
      expect(
        detectStatementProvider('date,description,amount'),
        StatementProvider.generic,
      );
    });
  });

  group('parseStatementLedger', () {
    test('Alipay uses payment time rather than creation time', () {
      final rows = parseStatementLedger(
        '#支付宝交易记录明细查询\n'
        '交易号,商家订单号,交易创建时间,付款时间,类型,交易对方,商品名称,金额（元）,收/支,交易状态,备注\n'
        '`202605100001,order-1,2026-05-09 23:58:00,2026-05-10 00:02:00,即时到账,便利店,早餐,12.30,支出,交易成功,\n',
      );

      expect(rows, hasLength(1));
      expect(rows.single.occurredAt, DateTime.utc(2026, 5, 10));
      expect(rows.single.description, '便利店 · 早餐 · 即时到账');
      expect(rows.single.amountMinor, -1230);
    });

    test('keeps WeChat Pay expense parsing and refund skipping', () {
      final rows = parseStatementLedger(
        '#微信支付账单明细\n'
        '交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态\n'
        '2026-05-10 12:30:01,商户消费,瑞幸咖啡,拿铁,支出,¥18.00,零钱,支付成功\n'
        '2026-05-10 14:00:00,商户消费,便利店,退款,支出,¥5.00,零钱,已全额退款\n',
      );

      expect(rows, hasLength(1));
      expect(rows.single.description, '瑞幸咖啡 · 拿铁 · 商户消费 · 零钱');
      expect(rows.single.amountMinor, -1800);
    });

    test('bank exports keep debit rows and drop credit rows', () {
      final rows = parseStatementLedger(
        '交易日期,交易摘要,对方户名,借方金额,贷方金额,币种\n'
        '2026-05-11,快捷支付,招商超市,66.80,,CNY\n'
        '2026-05-12,工资,公司,,10000.00,CNY\n',
      );

      expect(rows, hasLength(1));
      expect(rows.single.description, '招商超市 · 快捷支付');
      expect(rows.single.amountMinor, -6680);
    });
  });
}
