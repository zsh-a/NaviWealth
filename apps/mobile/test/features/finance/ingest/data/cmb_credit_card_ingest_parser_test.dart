import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/data/cmb_credit_card_ingest_parser.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_parse_diagnostics.dart';

void main() {
  test('parses settled amounts exactly and audits negative directions', () {
    const statement = '''
招商银行信用卡对账单
账单周期 2026年08月
交易明细
08/01 Precision Merchant 90,071,992,547,409.93 1234 90,071,992,547,409.93
08/02 Refund Merchant -10.00 1234 -10.00
''';

    final report = parseCmbCreditCardLedgerReport(statement);

    expect(report.candidateRowCount, 2);
    expect(report.rows, hasLength(1));
    expect(report.rows.single.amountMinor, -9007199254740993);
    expect(report.rows.single.description, 'Precision Merchant');
    expect(report.issues, hasLength(1));
    expect(
      report.issues.single.code,
      IngestParseIssueCode.unsupportedDirection,
    );
  });
}
