import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/data/statement_ingest_parser.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';

void main() {
  group('statement provider detection', () {
    test('detects Alipay, WeChat Pay, bank, and generic exports', () {
      expect(
        detectStatementProvider('#支付宝交易记录明细查询\n交易号,商家订单号,交易创建时间,付款时间'),
        StatementProvider.alipay,
      );
      expect(
        detectStatementProvider(
          '支付宝支付科技有限公司 电子客户回单\n'
          '交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,'
          '收/付款方式,交易状态,交易订单号,商家订单号,备注,',
        ),
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
        detectStatementProvider(
          'Date,Action,Symbol,Description,Fees & Comm,Amount',
        ),
        StatementProvider.broker,
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

    test('parses Alipay electronic receipt export conservatively', () {
      final rows = parseStatementLedger(
        '----------------支付宝交易明细列表----------------\n'
        '支付宝支付科技有限公司 电子客户回单\n'
        '交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,'
        '收/付款方式,交易状态,交易订单号,商家订单号,备注,\n'
        '2026-07-10 12:30:01,餐饮美食,示例餐厅,merchant@example.com,'
        '午餐,支出,31.50,余额,交易成功,trade-1,order-1,,\n'
        '2026-07-09 09:00:00,投资理财,示例基金,finance@example.com,'
        '基金申购,不计收支,1000.00,余额宝,交易成功,trade-2,order-2,,\n'
        '2026-07-08 08:00:00,其他,示例用户,user@example.com,'
        '退款,收入,10.00,余额,交易成功,trade-3,order-3,,\n'
        '2026-07-07 19:00:00,日用百货,示例超市,shop@example.com,'
        '"纸巾,家庭装",支出,28.80,银行卡,交易成功,trade-4,order-4,,\n'
        '2026-07-06 20:00:00,文化休闲,示例影院,cinema@example.com,'
        '电影票,支出,45.00,余额,已退款,trade-5,order-5,,\n',
      );

      expect(rows, hasLength(2));
      expect(rows[0].occurredAt, DateTime.utc(2026, 7, 10));
      expect(rows[0].amountMinor, -3150);
      expect(rows[0].description, '示例餐厅 · 午餐 · 餐饮美食 · 余额');
      expect(rows[0].categoryHint, 'dining');
      expect(rows[1].amountMinor, -2880);
      expect(rows[1].description, '示例超市 · 纸巾,家庭装 · 日用百货 · 银行卡');
      expect(rows[1].categoryHint, 'groceries');
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

    test('bank exports produce typed debit and salary-credit rows', () {
      final rows = parseStatementLedger(
        '交易日期,交易摘要,对方户名,借方金额,贷方金额,币种\n'
        '2026-05-11,快捷支付,招商超市,66.80,,CNY\n'
        '2026-05-12,工资,公司,,10000.00,CNY\n',
      );

      expect(rows, hasLength(2));
      expect(rows.first.description, '招商超市 · 快捷支付');
      expect(rows.first.amountMinor, -6680);
      expect(rows.first.categoryHint, 'groceries');
      expect(rows.last.kind, IngestTransactionKind.income);
      expect(rows.last.amountMinor, 1000000);
      expect(rows.last.categoryHint, 'salary');
    });

    test('bank provider supports amount plus debit-credit marker', () {
      final rows = parseStatementLedger(
        '账务日期,交易摘要,交易对方,借贷标志,发生额,币种\n'
        '2026-05-13,地铁出行,上海地铁,借,7.00,CNY\n'
        '2026-05-14,退款,商户,贷,7.00,CNY\n',
      );

      expect(rows, hasLength(1));
      expect(rows.single.description, '上海地铁 · 地铁出行');
      expect(rows.single.amountMinor, -700);
      expect(rows.single.categoryHint, 'transport');
    });

    test(
      'broker exports preserve income and withholding as separate drafts',
      () {
        final rows = parseStatementLedger(
          'ClientAccountID,Asset Category,Currency,Symbol,Date/Time,Description,Amount\n'
          'U123,Stocks,USD,AAPL,2026-05-10,Dividend,12.34\n'
          'U123,Stocks,USD,AAPL,2026-05-10,Withholding Tax,-3.70\n',
        );

        expect(rows, hasLength(2));
        expect(rows.first.kind, IngestTransactionKind.income);
        expect(rows.first.description, contains('dividend'));
        expect(rows.first.amountMinor, 1234);
        expect(rows.first.categoryHint, 'dividend');
        expect(rows.last.description, contains('withholding tax'));
        expect(rows.last.amountMinor, -370);
        expect(rows.last.categoryHint, 'tax:withholding');
      },
    );

    test('trade principal and transfers use typed review destinations', () {
      final brokerRows = parseStatementLedger(
        'Date,Action,Symbol,Description,Fees & Comm,Amount,Currency\n'
        '2026-05-10,BUY,AAPL,Bought 10 shares,,-1000.00,USD\n',
      );
      final transferRows = parseStatementLedger(
        '交易日期,交易摘要,交易对方,贷方金额,币种\n'
        '2026-05-11,转账收入,示例用户,1000.00,CNY\n',
      );

      expect(brokerRows, hasLength(1));
      expect(brokerRows.single.kind, IngestTransactionKind.trade);
      expect(brokerRows.single.instrumentSymbol, 'AAPL');
      expect(brokerRows.single.amountMinor, -100000);
      expect(transferRows, hasLength(1));
      expect(transferRows.single.kind, IngestTransactionKind.transfer);
      expect(transferRows.single.amountMinor, 100000);
    });
  });
}
