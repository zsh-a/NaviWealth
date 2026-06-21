import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ingest/data/broker_ingest_parser.dart';

void main() {
  group('parseBrokerCashLedger', () {
    test('parses IBKR withholding tax and skips dividend income', () {
      final rows = parseBrokerCashLedger(
        'ClientAccountID,Asset Category,Currency,Symbol,Date/Time,Description,Amount\n'
        'U123,Stocks,USD,AAPL,2026-05-10,Dividend,12.34\n'
        'U123,Stocks,USD,AAPL,2026-05-10,Withholding Tax,-3.70\n',
      );

      expect(rows, hasLength(1));
      expect(
        rows.single.description,
        'Broker withholding tax · AAPL · Withholding Tax',
      );
      expect(rows.single.amountMinor, -370);
      expect(rows.single.currency, 'USD');
      expect(rows.single.categoryHint, 'tax:withholding');
      expect(rows.single.occurredAt, DateTime.utc(2026, 5, 10));
    });

    test(
      'parses Schwab-style Fees & Comm column without importing trade principal',
      () {
        final rows = parseBrokerCashLedger(
          'Date,Action,Symbol,Description,Quantity,Price,Fees & Comm,Amount,Currency\n'
          '05/11/2026,Buy,NVDA,NVIDIA Corp,1,900.00,-1.25,-901.25,USD\n'
          '05/12/2026,Sell,NVDA,NVIDIA Corp,1,910.00,0.00,910.00,USD\n',
        );

        expect(rows, hasLength(1));
        expect(
          rows.single.description,
          'Broker fee · NVDA · Buy · NVIDIA Corp',
        );
        expect(rows.single.amountMinor, -125);
        expect(rows.single.categoryHint, 'trading:fee');
      },
    );

    test('parses Futu trade fee columns as one expense draft', () {
      final rows = parseBrokerCashLedger(
        '成交日期,类型,证券代码,名称,成交金额,手续费,平台费,交收费,币种\n'
        '2026-05-12,买入,00700,腾讯控股,3500.00,3.00,15.00,0.50,HKD\n',
        defaultCurrency: 'HKD',
      );

      expect(rows, hasLength(1));
      expect(rows.single.description, 'Broker fee · 00700 · 买入 · 腾讯控股');
      expect(rows.single.amountMinor, -1850);
      expect(rows.single.currency, 'HKD');
    });

    test(
      'skips deposits, withdrawals, trade principal, and positive income',
      () {
        final rows = parseBrokerCashLedger(
          'Date,Type,Symbol,Description,Amount,Currency\n'
          '2026-05-10,Deposit,,ACH Deposit,1000.00,USD\n'
          '2026-05-11,Withdrawal,,ACH Withdrawal,-500.00,USD\n'
          '2026-05-12,Buy,AAPL,Apple Inc,-190.00,USD\n'
          '2026-05-13,Interest,,Credit Interest,2.00,USD\n',
        );

        expect(rows, isEmpty);
      },
    );
  });
}
