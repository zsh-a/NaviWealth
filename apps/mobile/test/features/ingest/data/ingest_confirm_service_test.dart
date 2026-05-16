import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ai_chat/domain/proposal_plan.dart';
import 'package:naviwealth/features/ingest/data/ingest_confirm_service.dart';
import 'package:naviwealth/features/ingest/domain/ingest_models.dart';

IngestDraft _draft({String? categoryHint, int amountMinor = -3850}) =>
    IngestDraft(
      draftId: 'd1',
      ownerUserId: 'u1',
      createdAt: DateTime.utc(2026, 5, 10),
      sourceKind: IngestSourceKind.csv,
      parsed: ParsedTransaction(
        description: 'Starbucks Coffee',
        amountMinor: amountMinor,
        currency: 'CNY',
        occurredAt: DateTime.utc(2026, 5, 10),
        categoryHint: categoryHint,
      ),
      verdict: DedupVerdict.newTxn,
      status: DraftStatus.pending,
    );

void main() {
  group('IngestConfirmService.expensePlanFor', () {
    test('maps a draft to a propose_expense-shaped ready plan', () {
      final plan = IngestConfirmService.expensePlanFor(
        _draft(categoryHint: 'coffee'),
        fromAccountId: 'acct-cash',
      );

      expect(plan.kind, ProposalKind.expense);
      expect(plan.proposalId, 'd1');
      expect(plan.payload['account_id'], 'acct-cash');
      expect(plan.payload['currency'], 'CNY');
      expect(plan.payload['category'], 'coffee');
      expect(plan.payload['note'], 'Starbucks Coffee');
      expect(plan.payload['date'], '2026-05-10T00:00:00.000Z');
      // Amount is positive (sign handled by the JE builder) and exact.
      expect(
        Decimal.parse(plan.payload['amount']! as String),
        Decimal.parse('38.50'),
      );
    });

    test('defaults the category to "other" when unclassified', () {
      final plan = IngestConfirmService.expensePlanFor(
        _draft(),
        fromAccountId: 'acct-cash',
      );
      expect(plan.payload['category'], 'other');
    });

    test('amount minor → decimal handles sub-yuan and round values', () {
      expect(
        Decimal.parse(
          IngestConfirmService.expensePlanFor(
                _draft(amountMinor: -5),
                fromAccountId: 'a',
              ).payload['amount']!
              as String,
        ),
        Decimal.parse('0.05'),
      );
      expect(
        Decimal.parse(
          IngestConfirmService.expensePlanFor(
                _draft(amountMinor: -10000),
                fromAccountId: 'a',
              ).payload['amount']!
              as String,
        ),
        Decimal.parse('100.00'),
      );
    });
  });
}
