import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';

void main() {
  group('ProposalPlan.tryParse', () {
    test('parses a ready trade plan with full payload', () {
      final plan = ProposalPlan.tryParse(<String, Object?>{
        'proposal_id': 'p-1',
        'kind': 'trade',
        'status': 'ready',
        'summary_zh': '买入 AAPL 100 股 @ 180（盈透）',
        'payload': <String, Object?>{
          'type': 'buy',
          'asset_id': 'aapl-id',
          'asset_symbol': 'AAPL',
          'asset_name': 'Apple Inc.',
          'account_id': 'acct-1',
          'account_name': '盈透',
          'quantity': 100,
          'price': 180,
          'fee': 1,
          'tax': 0,
          'currency': 'USD',
          'trade_date': '2026-04-30T00:00:00Z',
          'note': null,
        },
        'warnings': <Object?>['currency 未指定，已默认 USD'],
        'missing': <Object?>[],
      });
      expect(plan, isA<ReadyProposalPlan>());
      final ready = plan! as ReadyProposalPlan;
      expect(ready.proposalId, 'p-1');
      expect(ready.kind, 'trade');
      expect(ready.summaryZh, '买入 AAPL 100 股 @ 180（盈透）');
      expect(ready.warnings, hasLength(1));
      expect(ready.get('asset_id'), 'aapl-id');
      expect(ready.num_('quantity'), 100);
    });

    test('parses a clarification plan with candidates', () {
      final plan = ProposalPlan.tryParse(<String, Object?>{
        'proposal_id': 'p-2',
        'kind': 'trade',
        'status': 'needs_clarification',
        'ambiguous_field': 'asset',
        'reason': '存在多个匹配的资产',
        'candidates': <Object?>[
          <String, Object?>{
            'id': 'a1',
            'name': 'Apple Inc.',
            'symbol': 'AAPL',
            'type': 'stock',
          },
          <String, Object?>{
            'id': 'a2',
            'name': 'Apple Hospitality',
            'symbol': 'APLE',
            'type': 'stock',
          },
        ],
      });
      expect(plan, isA<ClarificationProposalPlan>());
      final c = plan! as ClarificationProposalPlan;
      expect(c.candidates, hasLength(2));
      expect(c.candidates.first.label, 'Apple Inc.');
      expect(c.ambiguousField, 'asset');
    });

    test('returns null for empty kind', () {
      expect(
        ProposalPlan.tryParse(<String, Object?>{
          'proposal_id': 'x',
          'kind': '',
          'status': 'ready',
          'summary_zh': '',
          'payload': <String, Object?>{},
        }),
        isNull,
      );
    });

    test('accepts an unfamiliar wire kind — registry resolves at render', () {
      // Shell no longer validates against a closed set; new domains can
      // emit their own kinds and the propose card looks them up via
      // `proposalKindRegistryProvider`. Unknown kinds still parse here,
      // and the renderer falls back to the "unknown" label/icon.
      final plan = ProposalPlan.tryParse(<String, Object?>{
        'proposal_id': 'y',
        'kind': 'sleep_target_adjust',
        'status': 'ready',
        'summary_zh': '',
        'payload': <String, Object?>{},
      });
      expect(plan, isA<ReadyProposalPlan>());
      expect((plan! as ReadyProposalPlan).kind, 'sleep_target_adjust');
    });

    test('returns null for non-map output', () {
      expect(ProposalPlan.tryParse(null), isNull);
      expect(ProposalPlan.tryParse('hello'), isNull);
      expect(ProposalPlan.tryParse(<Object?>['a']), isNull);
    });

    test('isProposeTool gates on the propose_ prefix', () {
      expect(isProposeTool('propose_trade'), isTrue);
      expect(isProposeTool('propose_expense'), isTrue);
      expect(isProposeTool('get_holdings'), isFalse);
      expect(isProposeTool(''), isFalse);
    });

    test('every backend kind round-trips', () {
      for (final wire in [
        'trade',
        'expense',
        'liability_payment',
        'account_create',
        'asset_valuation',
      ]) {
        final plan = ProposalPlan.tryParse(<String, Object?>{
          'proposal_id': 'p',
          'kind': wire,
          'status': 'ready',
          'summary_zh': 's',
          'payload': <String, Object?>{},
        });
        expect(
          plan,
          isA<ReadyProposalPlan>(),
          reason: 'kind $wire should parse',
        );
        expect((plan! as ReadyProposalPlan).kind, wire);
      }
    });
  });
}
