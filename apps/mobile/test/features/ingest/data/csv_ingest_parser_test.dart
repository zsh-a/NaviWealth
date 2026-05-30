import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ingest/data/csv_ingest_parser.dart';

void main() {
  group('parseCsvLedger', () {
    test('parses a header CSV and normalises to negative outflow', () {
      final rows = parseCsvLedger(
        'date,description,amount,currency\n'
        '2026-05-10,Starbucks Coffee,-38.00,CNY\n'
        '2026-05-11,Whole Foods,128.50,USD\n',
      );
      expect(rows, hasLength(2));
      expect(rows[0].description, 'Starbucks Coffee');
      expect(rows[0].amountMinor, -3800);
      expect(rows[0].currency, 'CNY');
      expect(rows[0].occurredAt, DateTime.utc(2026, 5, 10));
      // Positive bank column is still treated as an expense outflow.
      expect(rows[1].amountMinor, -12850);
      expect(rows[1].currency, 'USD');
    });

    test('falls back to positional columns when no header', () {
      final rows = parseCsvLedger('2026/05/12,美团外卖,-35,\n');
      expect(rows, hasLength(1));
      expect(rows[0].description, '美团外卖');
      expect(rows[0].amountMinor, -3500);
      expect(rows[0].occurredAt, DateTime.utc(2026, 5, 12));
    });

    test('merges payee + description and respects quoted commas', () {
      final rows = parseCsvLedger(
        'date,payee,description,amount\n'
        '2026-01-02,"Amazon, Inc.","order #A1",-9.99\n',
      );
      expect(rows, hasLength(1));
      expect(rows[0].description, 'Amazon, Inc. · order #A1');
      expect(rows[0].amountMinor, -999);
    });

    test('handles thousands separators, currency glyphs and parens', () {
      final rows = parseCsvLedger(
        'date,description,amount\n'
        '2026-03-01,Rent,"\$1,234.00"\n'
        '2026-03-02,Refundish,(50.00)\n',
      );
      expect(rows[0].amountMinor, -123400);
      expect(rows[1].amountMinor, -5000);
    });

    test('skips rows without a valid date or amount', () {
      final rows = parseCsvLedger(
        'date,description,amount\n'
        'not-a-date,Garbage,10\n'
        '2026-05-10,Valid,-1.00\n'
        '2026-05-11,No amount,\n'
        '\n',
      );
      expect(rows, hasLength(1));
      expect(rows.single.description, 'Valid');
    });

    test('parses US m/d/y and 2-digit years', () {
      final rows = parseCsvLedger('05/10/26,Diner,-12.00');
      expect(rows.single.occurredAt, DateTime.utc(2026, 5, 10));
    });

    test('parses WeChat Pay export and skips non-expense rows', () {
      final rows = parseCsvLedger(
        '#微信支付账单明细\n'
        '交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,备注\n'
        '2026-05-10 12:30:01,商户消费,瑞幸咖啡,拿铁,支出,¥18.00,零钱,支付成功,wx-1,\n'
        '2026-05-10 13:00:00,转账,朋友,红包,收入,¥8.00,零钱,已收款,wx-2,\n'
        '2026-05-10 14:00:00,商户消费,便利店,退款,支出,¥5.00,零钱,已全额退款,wx-3,\n',
      );
      expect(rows, hasLength(1));
      expect(rows.single.description, '瑞幸咖啡 · 拿铁 · 商户消费 · 零钱');
      expect(rows.single.amountMinor, -1800);
      expect(rows.single.currency, 'CNY');
      expect(rows.single.occurredAt, DateTime.utc(2026, 5, 10));
    });

    test('parses Alipay export with preamble and 收/支 direction', () {
      final rows = parseCsvLedger(
        '#支付宝交易记录明细查询\n'
        '交易号,商家订单号,交易创建时间,付款时间,类型,交易对方,商品名称,金额（元）,收/支,交易状态,备注\n'
        '`202605100001,order-1,2026-05-10 08:10:00,2026-05-10 08:11:00,即时到账,星巴克,咖啡,32.50,支出,交易成功,\n'
        '`202605100002,order-2,2026-05-10 09:10:00,2026-05-10 09:11:00,退款,星巴克,退款,32.50,收入,交易成功,\n',
      );
      expect(rows, hasLength(1));
      expect(rows.single.description, '星巴克 · 咖啡 · 即时到账');
      expect(rows.single.amountMinor, -3250);
    });

    test('parses bank statements with debit and credit columns', () {
      final rows = parseCsvLedger(
        '交易日期,交易摘要,对方户名,支出金额,收入金额,币种\n'
        '2026年05月11日,快捷支付,招商超市,66.80,,CNY\n'
        '2026年05月12日,工资,公司,,10000.00,CNY\n',
      );
      expect(rows, hasLength(1));
      expect(rows.single.description, '招商超市 · 快捷支付');
      expect(rows.single.amountMinor, -6680);
      expect(rows.single.occurredAt, DateTime.utc(2026, 5, 11));
    });

    test('empty input yields no rows', () {
      expect(parseCsvLedger(''), isEmpty);
      expect(parseCsvLedger('   \n  \n'), isEmpty);
    });
  });
}
