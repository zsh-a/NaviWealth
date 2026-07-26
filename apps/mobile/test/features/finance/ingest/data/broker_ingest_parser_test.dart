import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/data/broker_ingest_parser.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';

void main() {
  group('parseBrokerCashLedger', () {
    test('parses IBKR dividend income and withholding tax separately', () {
      final rows = parseBrokerCashLedger(
        'ClientAccountID,Asset Category,Currency,Symbol,Date/Time,Description,Amount\n'
        'U123,Stocks,USD,AAPL,2026-05-10,Dividend,12.34\n'
        'U123,Stocks,USD,AAPL,2026-05-10,Withholding Tax,-3.70\n',
      );

      expect(rows, hasLength(2));
      expect(
        rows.last.description,
        'Broker withholding tax · AAPL · Withholding Tax',
      );
      expect(rows.first.amountMinor, 1234);
      expect(rows.first.kind, IngestTransactionKind.income);
      expect(rows.first.categoryHint, 'dividend');
      expect(rows.last.amountMinor, -370);
      expect(rows.last.currency, 'USD');
      expect(rows.last.categoryHint, 'tax:withholding');
      expect(rows.last.occurredAt, DateTime.utc(2026, 5, 10));
    });

    test('keeps Schwab trades typed and splits their fees', () {
      final rows = parseBrokerCashLedger(
        'Date,Action,Symbol,Description,Quantity,Price,Fees & Comm,Amount,Currency\n'
        '05/11/2026,Buy,NVDA,NVIDIA Corp,1,900.00,-1.25,-901.25,USD\n'
        '05/12/2026,Sell,NVDA,NVIDIA Corp,1,910.00,0.00,910.00,USD\n',
      );

      expect(rows, hasLength(3));
      expect(rows.first.kind, IngestTransactionKind.trade);
      expect(rows.first.instrumentSymbol, 'NVDA');
      expect(rows.first.quantity, '1');
      expect(rows.first.unitPrice, '900.00');
      expect(rows[1].description, 'Broker fee · NVDA · Buy · NVIDIA Corp');
      expect(rows[1].amountMinor, -125);
      expect(rows[1].categoryHint, 'trading:fee');
      expect(rows.last.activitySide, 'sell');
    });

    test('parses Futu trade and fee as separate typed drafts', () {
      final rows = parseBrokerCashLedger(
        '成交日期,类型,证券代码,名称,成交金额,手续费,平台费,交收费,币种\n'
        '2026-05-12,买入,00700,腾讯控股,3500.00,3.00,15.00,0.50,HKD\n',
        defaultCurrency: 'HKD',
      );

      expect(rows, hasLength(2));
      expect(rows.first.kind, IngestTransactionKind.trade);
      expect(rows.first.activitySide, 'buy');
      expect(rows.last.description, 'Broker fee · 00700 · 买入 · 腾讯控股');
      expect(rows.last.amountMinor, -1850);
      expect(rows.last.currency, 'HKD');
    });

    test('types deposits, withdrawals, trades, and interest rows', () {
      final rows = parseBrokerCashLedger(
        'Date,Type,Symbol,Description,Amount,Currency\n'
        '2026-05-10,Deposit,,ACH Deposit,1000.00,USD\n'
        '2026-05-11,Withdrawal,,ACH Withdrawal,-500.00,USD\n'
        '2026-05-12,Buy,AAPL,Apple Inc,-190.00,USD\n'
        '2026-05-13,Interest,,Credit Interest,2.00,USD\n',
      );

      expect(rows, hasLength(4));
      expect(rows.first.kind, IngestTransactionKind.transfer);
      expect(rows.first.amountMinor, 100000);
      expect(rows[1].kind, IngestTransactionKind.transfer);
      expect(rows[1].amountMinor, -50000);
      expect(rows[2].kind, IngestTransactionKind.trade);
      expect(rows.last.kind, IngestTransactionKind.income);
      expect(rows.last.categoryHint, 'interest');
      expect(rows.last.amountMinor, 200);
    });
  });
}
